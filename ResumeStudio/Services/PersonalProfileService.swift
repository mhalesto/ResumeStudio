import FirebaseAppCheck
import FirebaseAuth
import FirebaseCore
import Foundation

/// The hosted personal CV page API: publish a résumé behind a permanent vanity
/// handle, read its live state, check handle availability, and withdraw it.
/// Mirrors SmartLinkService — App Check on every call, the account token always
/// (publishing a handle needs a signed-in owner; the app is anonymously signed
/// in from launch).
struct PersonalProfileService {
  struct PublishRequest {
    var handle: String
    var displayName: String
    var headline: String
    var location: String
    var links: [ProfileLink]
    var searchable: Bool
    var pdfData: Data
    /// Page renders (PNG) for the fit-to-width web preview. Empty falls back to
    /// an inline PDF on the page.
    var pageImages: [Data]
  }

  struct PublishResult {
    var hostedURL: URL
    var handle: String
    var branded: Bool
    var searchable: Bool
  }

  func publish(_ request: PublishRequest) async throws -> PublishResult {
    let payload = PublishProfilePayload(
      clientID: MonetizationIdentity.installationID,
      entitlement: await PurchaseManager.shared.entitlementProof(),
      handle: request.handle,
      displayName: request.displayName,
      headline: request.headline,
      location: request.location,
      links: request.links.map { ProfileLinkPayload(label: $0.label, url: $0.url) },
      searchable: request.searchable,
      pdfBase64: request.pdfData.base64EncodedString(),
      pageImages: request.pageImages.map { $0.base64EncodedString() }
    )
    let response: PublishProfileResponse = try await self.request(
      path: "v1/profile", method: "POST", body: payload
    )
    guard let url = URL(string: response.hostedURL) else { throw ResumeAIError.invalidResponse }
    return PublishResult(
      hostedURL: url, handle: response.handle,
      branded: response.branded, searchable: response.searchable)
  }

  func fetch() async throws -> PersonalProfile? {
    let response: FetchProfileResponse = try await request(
      path: "v1/profile", method: "GET", body: Optional<String>.none
    )
    return response.profile
  }

  func unpublish() async throws {
    let _: DeleteProfileResponse = try await request(
      path: "v1/profile", method: "DELETE", body: Optional<String>.none
    )
  }

  /// Whether a handle is free (or already owned by the caller). The editor calls
  /// this as the owner types, so it is deliberately cheap and returns `false`
  /// rather than throwing on an invalid handle.
  func checkHandle(_ handle: String) async throws -> Bool {
    let response: HandleAvailabilityResponse = try await request(
      path: "v1/profile/handle/\(handle)", method: "GET", body: Optional<String>.none
    )
    return response.available
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
      let error = try? JSONDecoder().decode(ProfileErrorResponse.self, from: data)
      let message = error?.error ?? "The page request failed."
      // A taken handle is the one error the editor answers inline, so it is
      // flagged distinctly from a generic failure.
      if error?.code == "handle_taken" { throw PersonalProfileError.handleTaken(message: message) }
      throw PersonalProfileError.message(message)
    }
    guard let result = try? JSONDecoder.smartLinkDecoder.decode(Result.self, from: data) else {
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
          continuation.resume(throwing: ResumeAIError.server(
            message: "Couldn't verify this device just now. Try again in a moment."))
        }
      }
    }
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

/// A hosted-page request failure. `handleTaken` is the case the editor answers
/// inline with a "try another" nudge; everything else is a plain message.
enum PersonalProfileError: LocalizedError {
  case handleTaken(message: String)
  case message(String)

  var errorDescription: String? {
    switch self {
    case .handleTaken(let message), .message(let message): message
    }
  }

  var isHandleTaken: Bool {
    if case .handleTaken = self { return true }
    return false
  }
}

private struct PublishProfilePayload: Encodable {
  var clientID: String
  var entitlement: MonetizationEntitlementProof
  var handle: String
  var displayName: String
  var headline: String
  var location: String
  var links: [ProfileLinkPayload]
  var searchable: Bool
  var pdfBase64: String
  var pageImages: [String]
}

private struct ProfileLinkPayload: Encodable {
  var label: String
  var url: String
}

private struct PublishProfileResponse: Decodable {
  var hostedURL: String
  var handle: String
  var branded: Bool
  var searchable: Bool
}

private struct FetchProfileResponse: Decodable { var profile: PersonalProfile? }
private struct DeleteProfileResponse: Decodable { var deleted: Bool? }
private struct HandleAvailabilityResponse: Decodable { var available: Bool }
private struct ProfileErrorResponse: Decodable {
  var error: String
  var code: String?
}
