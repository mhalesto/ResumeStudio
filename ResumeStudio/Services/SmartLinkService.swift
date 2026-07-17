import FirebaseAppCheck
import FirebaseAuth
import FirebaseCore
import Foundation

/// The hosted trackable-link API: publish a résumé PDF behind a link, poll its
/// open/reading activity, and revoke or delete it. Mirrors ReviewRoomService —
/// App Check on every call, the account token when one exists.
struct SmartLinkService {
  struct PublishRequest {
    var token: String
    var title: String
    var company: String
    var expiresAt: Date
    var pdfData: Data
    /// Page renders (PNG) for the fit-to-width viewer preview. Empty is allowed
    /// — the hosted page falls back to the inline PDF.
    var pageImages: [Data]
  }

  func publish(_ request: PublishRequest) async throws -> URL {
    let payload = PublishLinkPayload(
      clientID: MonetizationIdentity.installationID,
      entitlement: await PurchaseManager.shared.entitlementProof(),
      token: request.token,
      expiresAt: request.expiresAt,
      resumeTitle: request.title,
      company: request.company,
      pdfBase64: request.pdfData.base64EncodedString(),
      pageImagesBase64: request.pageImages.map { $0.base64EncodedString() }
    )
    let response: PublishLinkResponse = try await self.request(
      path: "v1/links", method: "POST", body: payload
    )
    guard let url = URL(string: response.hostedURL) else {
      throw ResumeAIError.invalidResponse
    }
    return url
  }

  func activity(token: String) async throws -> SmartLinkActivity {
    try await request(
      path: "v1/links/\(token)/activity", method: "GET", body: Optional<String>.none
    )
  }

  func revoke(token: String) async throws {
    let _: LinkLifecycleResponse = try await request(
      path: "v1/links/\(token)", method: "PATCH", body: Optional<String>.none
    )
  }

  func delete(token: String) async throws {
    let _: LinkLifecycleResponse = try await request(
      path: "v1/links/\(token)", method: "DELETE", body: Optional<String>.none
    )
  }

  /// The public viewer URL for a token, built from the app's own configured
  /// base rather than trusting a stored URL. The hosted `/cv/<token>` path is a
  /// stable backend contract, so reconstructing it here means a link always
  /// resolves — even one saved before the backend URL fix landed.
  static func viewerURL(token: String) -> URL? {
    guard let base = try? resolvedBaseURL() else { return nil }
    return base.appendingPathComponent("cv").appendingPathComponent(token)
  }

  private func request<Body: Encodable, Result: Decodable>(
    path: String, method: String, body: Body?
  ) async throws -> Result {
    let baseURL = try Self.resolvedBaseURL()
    var request = URLRequest(url: baseURL.appendingPathComponent(path))
    request.httpMethod = method
    request.timeoutInterval = 60
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(try await appCheckToken(), forHTTPHeaderField: "X-Firebase-AppCheck")
    if let token = try await Auth.auth().currentUser?.getIDToken(forcingRefresh: false) {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    if let body { request.httpBody = try JSONEncoder.smartLinkEncoder.encode(body) }
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw ResumeAIError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else {
      let error = try? JSONDecoder().decode(LinkErrorResponse.self, from: data)
      let message = error?.error ?? "The link request failed."
      // A plan/limit rejection is the one error the sheet can offer a fix for,
      // so it is flagged distinctly to surface an upgrade button.
      if error?.code == "link_limit" { throw SmartLinkError.planLimit(message: message) }
      throw SmartLinkError.message(message)
    }
    guard let result = try? JSONDecoder.smartLinkDecoder.decode(Result.self, from: data) else {
      throw ResumeAIError.invalidResponse
    }
    return result
  }

  private func appCheckToken() async throws -> String {
    // The local emulator bypasses App Check verification entirely, so a
    // placeholder saves development simulators from needing their debug token
    // registered in the Firebase console just to test links.
    if ProcessInfo.processInfo.environment["AI_SERVICE_BASE_URL"] != nil {
      return "emulator-bypass"
    }
    // Firebase configures itself non-blockingly at startup; touching AppCheck
    // before that raises an Objective-C exception Swift cannot catch. A launch
    // refresh that arrives early should fail soft and let the next one work.
    guard FirebaseApp.app() != nil else {
      throw ResumeAIError.server(message: "Still connecting. Pull to refresh in a moment.")
    }
    return try await withCheckedThrowingContinuation { continuation in
      AppCheck.appCheck().token(forcingRefresh: false) { result, error in
        if let token = result?.token, !token.isBlank {
          continuation.resume(returning: token)
        } else {
          continuation.resume(throwing: ResumeAIError.server(message: Self.appCheckFailureMessage(error)))
        }
      }
    }
  }

  /// A concise message for a failed attestation. Users never see the raw
  /// Firebase error — a wall of URLs and status codes reads as a crash — but a
  /// simulator build keeps the detail so an unregistered debug token is
  /// diagnosable from the one screen it surfaces on.
  private static func appCheckFailureMessage(_ error: Error?) -> String {
    #if targetEnvironment(simulator)
      if let detail = error?.localizedDescription.nilIfBlank {
        return "App Check could not verify this simulator: \(detail)"
      }
    #endif
    return "Couldn't verify this device just now. Pull to refresh in a moment."
  }

  static func resolvedBaseURL() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["AI_SERVICE_BASE_URL"],
      let url = URL(string: override) {
      return url
    }
    guard let raw = Bundle.main.object(forInfoDictionaryKey: "AIServiceBaseURL") as? String,
      let url = URL(string: raw), !raw.contains("$(")
    else { throw ResumeAIError.notConfigured }
    return url
  }
}

struct SmartLinkActivity: Decodable {
  var status: String
  var expiresAt: Date?
  var views: [SmartLinkView]
}

private struct PublishLinkPayload: Encodable {
  var clientID: String
  var entitlement: MonetizationEntitlementProof
  var token: String
  var expiresAt: Date
  var resumeTitle: String
  var company: String
  var pdfBase64: String
  var pageImagesBase64: [String]
}

private struct PublishLinkResponse: Decodable { var hostedURL: String }
private struct LinkLifecycleResponse: Decodable {
  var status: String?
  var deleted: Bool?
}
private struct LinkErrorResponse: Decodable {
  var error: String
  var code: String?
}

/// A trackable-link request failure. `planLimit` is the case the create sheet
/// answers with an upgrade button; everything else is a plain message.
enum SmartLinkError: LocalizedError {
  case planLimit(message: String)
  case message(String)

  var errorDescription: String? {
    switch self {
    case .planLimit(let message), .message(let message): message
    }
  }

  /// Whether the user could resolve this by changing plan.
  var suggestsUpgrade: Bool {
    if case .planLimit = self { return true }
    return false
  }
}

extension JSONEncoder {
  static let smartLinkEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()
}

extension JSONDecoder {
  static let smartLinkDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()
}
