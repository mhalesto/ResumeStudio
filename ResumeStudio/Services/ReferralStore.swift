import FirebaseAuth
import Foundation

@MainActor
final class ReferralStore: ObservableObject {
  @Published private(set) var profile: ReferralProfile?
  @Published private(set) var isLoading = false
  @Published private(set) var message: String?
  @Published private(set) var errorMessage: String?
  @Published var pendingCode: String

  private static let pendingCodeKey = "pendingReferralCode"

  init() {
    pendingCode = UserDefaults.standard.string(forKey: Self.pendingCodeKey) ?? ""
  }

  func accept(url: URL) {
    guard url.scheme == "resumestudio", url.host == "referral",
      let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?.first(where: { $0.name == "code" })?.value
    else { return }
    setPendingCode(code)
  }

  func setPendingCode(_ value: String) {
    let code = value.uppercased().filter { $0.isLetter || $0.isNumber }
    pendingCode = String(code.prefix(16))
    UserDefaults.standard.set(pendingCode, forKey: Self.pendingCodeKey)
  }

  func load() async {
    guard Auth.auth().currentUser?.isAnonymous == false else { return }
    isLoading = true; errorMessage = nil
    defer { isLoading = false }
    do { profile = try await request(path: "v1/referrals", method: "GET", body: Optional<String>.none) }
    catch { errorMessage = error.localizedDescription }
  }

  func redeem() async {
    guard !pendingCode.isBlank else { errorMessage = "Enter a referral code."; return }
    isLoading = true; errorMessage = nil; message = nil
    defer { isLoading = false }
    do {
      let result: ReferralRedemption = try await request(
        path: "v1/referrals/redeem", method: "POST", body: ["code": pendingCode])
      message = result.message
      UserDefaults.standard.removeObject(forKey: Self.pendingCodeKey)
      pendingCode = ""
      PurchaseManager.shared.addReferralCredits(result.creditsAwarded)
      profile = try await request(path: "v1/referrals", method: "GET", body: Optional<String>.none)
    } catch { errorMessage = error.localizedDescription }
  }

  private func request<Result: Decodable, Body: Encodable>(
    path: String, method: String, body: Body?
  ) async throws -> Result {
    guard let user = Auth.auth().currentUser else { throw ReferralError.signInRequired }
    let token = try await user.getIDToken(forcingRefresh: false)
    let endpoint = try baseURL().appendingPathComponent(path)
    var request = URLRequest(url: endpoint)
    request.httpMethod = method
    request.timeoutInterval = 30
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONEncoder().encode(body)
    }
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw ReferralError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else {
      let value = try? JSONDecoder().decode(ReferralAPIError.self, from: data)
      throw ReferralError.server(value?.error ?? "Unable to complete the referral request.")
    }
    return try JSONDecoder().decode(Result.self, from: data)
  }

  private func baseURL() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["AI_SERVICE_BASE_URL"],
      let url = URL(string: override), !override.isBlank { return url }
    guard let value = Bundle.main.object(forInfoDictionaryKey: "AIServiceBaseURL") as? String,
      let url = URL(string: value), !value.isBlank
    else { throw ReferralError.invalidResponse }
    return url
  }
}

private struct ReferralAPIError: Decodable { var error: String }

private enum ReferralError: LocalizedError {
  case signInRequired
  case invalidResponse
  case server(String)

  var errorDescription: String? {
    switch self {
    case .signInRequired: "Create or sign in to your account first."
    case .invalidResponse: "The referral service returned an unreadable response."
    case .server(let message): message
    }
  }
}
