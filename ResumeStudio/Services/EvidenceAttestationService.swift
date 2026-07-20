import FirebaseAppCheck
import FirebaseAuth
import FirebaseCore
import Foundation

/// The hosted side of evidence attestations: ask for a claim to be confirmed,
/// poll for the answer, and withdraw a request that is still open.
///
/// Mirrors `SmartLinkService` — App Check on every call, and the account token,
/// which is required here because a request belongs to an owner.
struct EvidenceAttestationService {
  struct CreatedRequest {
    var token: String
    var shareURL: URL
    var expiresAt: Date
  }

  struct RemoteStatus: Decodable {
    var status: AttestationStatus
    var verifierName: String
    var verifierRole: String
    var comment: String
    var respondedAt: Date?
    var expiresAt: Date
  }

  private struct CreatePayload: Encodable {
    var claim: String
    var context: String
  }

  private struct CreateResponse: Decodable {
    var token: String
    var shareURL: String
    var expiresAt: Date
  }

  func requestConfirmation(claim: String, context: String) async throws -> CreatedRequest {
    let response: CreateResponse = try await send(
      path: "v1/attestations", method: "POST",
      body: CreatePayload(claim: claim, context: context))
    guard let url = URL(string: response.shareURL) else { throw ResumeAIError.invalidResponse }
    return CreatedRequest(token: response.token, shareURL: url, expiresAt: response.expiresAt)
  }

  func status(token: String) async throws -> RemoteStatus {
    try await send(path: "v1/attestations/\(token)", method: "GET", body: Optional<String>.none)
  }

  func revoke(token: String) async throws {
    let _: EmptyReply = try await send(
      path: "v1/attestations/\(token)", method: "DELETE", body: Optional<String>.none)
  }

  private struct EmptyReply: Decodable {
    var status: String?
  }

  private func send<Body: Encodable, Result: Decodable>(
    path: String, method: String, body: Body?
  ) async throws -> Result {
    let baseURL = try SmartLinkService.resolvedBaseURL()
    var request = URLRequest(url: baseURL.appendingPathComponent(path))
    request.httpMethod = method
    request.timeoutInterval = 30
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(try await appCheckToken(), forHTTPHeaderField: "X-Firebase-AppCheck")
    guard let idToken = try await Auth.auth().currentUser?.getIDToken(forcingRefresh: false) else {
      throw ResumeAIError.server(
        message: "Sign in before asking someone to confirm a claim.")
    }
    request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
    if let body { request.httpBody = try JSONEncoder.attestationEncoder.encode(body) }

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw ResumeAIError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else {
      let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
      throw ResumeAIError.server(message: message ?? "That confirmation request failed.")
    }
    guard let result = try? JSONDecoder.attestationDecoder.decode(Result.self, from: data) else {
      throw ResumeAIError.invalidResponse
    }
    return result
  }

  private func appCheckToken() async throws -> String {
    if ProcessInfo.processInfo.environment["AI_SERVICE_BASE_URL"] != nil {
      return "emulator-bypass"
    }
    guard FirebaseApp.app() != nil else {
      throw ResumeAIError.server(message: "Still connecting. Try again in a moment.")
    }
    return try await withCheckedThrowingContinuation { continuation in
      AppCheck.appCheck().token(forcingRefresh: false) { result, error in
        if let token = result?.token, !token.isBlank {
          continuation.resume(returning: token)
        } else {
          _ = error
          continuation.resume(
            throwing: ResumeAIError.server(message: "Couldn't verify this device just now."))
        }
      }
    }
  }
}

extension JSONEncoder {
  /// ISO-8601, matching what the attestation routes read and write.
  static let attestationEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()
}

extension JSONDecoder {
  static let attestationDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()
}
