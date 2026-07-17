import FirebaseAppCheck
import FirebaseAuth
import Foundation

actor ReviewRoomService {
  static let shared = ReviewRoomService()

  func publish(request review: ResumeReviewRequest, document: ResumeDocument) async throws -> URL {
    let (pdf, pageImages) = try await MainActor.run { () -> (Data, [Data]) in
      let pdf = try ResumePDFRenderer.render(document: document)
      return (pdf, ResumePageRasterizer.images(fromPDF: pdf))
    }
    guard pdf.count <= 5_000_000 else {
      throw ResumeAIError.server(message: "This PDF is too large for an online review room.")
    }
    let token = review.hostedToken ?? UUID().uuidString.replacingOccurrences(of: "-", with: "")
    let body = PublishReviewPayload(
      clientID: MonetizationIdentity.installationID,
      entitlement: await PurchaseManager.shared.entitlementProof(),
      token: token,
      accessCode: review.accessCode,
      expiresAt: review.expiresAt,
      reviewerName: review.reviewerName,
      message: review.message,
      resumeTitle: document.personal.fullName.nilIfBlank.map { "\($0) — Résumé review" } ?? "Résumé review",
      pdfBase64: pdf.base64EncodedString(),
      pageImagesBase64: pageImages.map { $0.base64EncodedString() }
    )
    let result: PublishReviewResponse = try await request(path: "v1/reviews", method: "POST", body: body)
    guard let url = URL(string: result.hostedURL) else { throw ResumeAIError.invalidResponse }
    return url
  }

  func comments(token: String) async throws -> [RemoteReviewComment] {
    let response: ReviewCommentsResponse = try await request(
      path: "v1/reviews/\(token)/comments", method: "GET", body: Optional<String>.none
    )
    return response.comments
  }

  func revoke(token: String) async throws {
    let _: ReviewLifecycleResponse = try await request(
      path: "v1/reviews/\(token)", method: "PATCH", body: Optional<String>.none)
  }

  func delete(token: String) async throws {
    let _: ReviewLifecycleResponse = try await request(
      path: "v1/reviews/\(token)", method: "DELETE", body: Optional<String>.none)
  }

  private func request<Body: Encodable, Result: Decodable>(
    path: String, method: String, body: Body?
  ) async throws -> Result {
    let baseURL = try resolvedBaseURL()
    var request = URLRequest(url: baseURL.appendingPathComponent(path))
    request.httpMethod = method
    request.timeoutInterval = 60
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(try await appCheckToken(), forHTTPHeaderField: "X-Firebase-AppCheck")
    if let token = try await Auth.auth().currentUser?.getIDToken(forcingRefresh: false) {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    if let body { request.httpBody = try JSONEncoder.reviewEncoder.encode(body) }
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw ResumeAIError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else {
      let error = try? JSONDecoder().decode(ReviewErrorResponse.self, from: data)
      throw ResumeAIError.server(message: error?.error ?? "Review Room request failed.")
    }
    guard let result = try? JSONDecoder.reviewDecoder.decode(Result.self, from: data) else {
      throw ResumeAIError.invalidResponse
    }
    return result
  }

  private func appCheckToken() async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
      AppCheck.appCheck().token(forcingRefresh: false) { result, error in
        if let token = result?.token, !token.isBlank {
          continuation.resume(returning: token)
        } else {
          continuation.resume(throwing: ResumeAIError.server(
            message: error?.localizedDescription.nilIfBlank.map { "This installation could not be verified: \($0)" }
              ?? "This installation could not be verified. Please relaunch the app and try again."
          ))
        }
      }
    }
  }

  private func resolvedBaseURL() throws -> URL {
    guard let raw = Bundle.main.object(forInfoDictionaryKey: "AIServiceBaseURL") as? String,
      let url = URL(string: raw), !raw.contains("$(")
    else { throw ResumeAIError.notConfigured }
    return url
  }
}

private struct PublishReviewPayload: Encodable {
  var clientID: String
  var entitlement: MonetizationEntitlementProof
  var token: String
  var accessCode: String
  var expiresAt: Date
  var reviewerName: String
  var message: String
  var resumeTitle: String
  var pdfBase64: String
  var pageImagesBase64: [String]
}

private struct PublishReviewResponse: Decodable { var hostedURL: String }
private struct ReviewCommentsResponse: Decodable { var comments: [RemoteReviewComment] }
private struct ReviewLifecycleResponse: Decodable {
  var status: String?
  var deleted: Bool?
}
private struct ReviewErrorResponse: Decodable { var error: String }

struct RemoteReviewComment: Decodable {
  var id: String
  var section: String
  var author: String
  var comment: String
  var createdAt: Date
}

private extension JSONEncoder {
  static let reviewEncoder: JSONEncoder = { let value = JSONEncoder(); value.dateEncodingStrategy = .iso8601; return value }()
}
private extension JSONDecoder {
  static let reviewDecoder: JSONDecoder = { let value = JSONDecoder(); value.dateDecodingStrategy = .iso8601; return value }()
}
