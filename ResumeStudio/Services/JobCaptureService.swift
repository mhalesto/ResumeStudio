import Foundation

enum JobCaptureError: LocalizedError {
  case invalidURL
  case unreadablePage

  var errorDescription: String? {
    switch self {
    case .invalidURL: "Enter a complete job link beginning with https://."
    case .unreadablePage: "That page did not expose readable job text. Paste the advert or upload the job specification instead."
    }
  }
}

enum JobCaptureService {
  static func text(from rawURL: String) async throws -> String {
    guard let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
      ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    else { throw JobCaptureError.invalidURL }

    var request = URLRequest(url: url)
    request.timeoutInterval = 20
    request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) ResumeStudio/1.0", forHTTPHeaderField: "User-Agent")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode),
      let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    else { throw JobCaptureError.unreadablePage }

    let withoutScripts = html
      .replacingOccurrences(of: "(?is)<(script|style|svg|nav|footer)[^>]*>.*?</\\1>", with: " ", options: .regularExpression)
      .replacingOccurrences(of: "(?i)<br\\s*/?>|</p>|</li>|</h[1-6]>", with: "\n", options: .regularExpression)
      .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
      .replacingOccurrences(of: "&nbsp;", with: " ")
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&#39;", with: "'")
      .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
      .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    guard withoutScripts.split(whereSeparator: \.isWhitespace).count >= 40 else {
      throw JobCaptureError.unreadablePage
    }
    return String(withoutScripts.prefix(45_000))
  }
}
