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

struct JobPageContent {
  var text: String
  var title: String?
  var structuredPosting: String?
  var finalURL: String
  var httpStatus: Int
}

enum JobCaptureService {
  private static let closedPagePhrases = [
    "this job is no longer available",
    "this position is no longer available",
    "this vacancy is no longer available",
    "this job has expired",
    "this vacancy has expired",
    "this job has been removed",
    "this position has been filled",
    "applications are now closed",
    "applications for this role are closed",
    "job not found",
    "position not found",
  ]

  static func text(from rawURL: String) async throws -> String {
    try await page(from: rawURL).text
  }

  /// Downloads only a public advert. The resulting page content is processed on
  /// device and never includes résumé or profile data.
  static func page(from rawURL: String) async throws -> JobPageContent {
    let result = try await response(from: rawURL)
    guard (200..<400).contains(result.status), let html = decode(result.data) else {
      throw JobCaptureError.unreadablePage
    }

    let text = readableText(from: html)
    guard text.split(whereSeparator: \.isWhitespace).count >= 40 else {
      throw JobCaptureError.unreadablePage
    }

    return JobPageContent(
      text: String(text.prefix(45_000)),
      title: pageTitle(from: html),
      structuredPosting: structuredPosting(from: html),
      finalURL: result.finalURL,
      httpStatus: result.status
    )
  }

  /// A deliberately conservative monitor: a page is only called live when the
  /// role or employer can still be matched. An ambiguous page stays
  /// inconclusive, which avoids treating redirects and job-board home pages as
  /// evidence that a role is open.
  static func inspect(
    rawURL: String,
    expectedRole: String,
    expectedCompany: String,
    checkedAt: Date = Date()
  ) async -> OpportunityPageInspection {
    do {
      let result = try await response(from: rawURL)
      guard let html = decode(result.data) else {
        return inspection(.unreachable, checkedAt, result.finalURL, result.status)
      }

      let text = String(readableText(from: html).prefix(45_000))
      let posting = structuredPosting(from: html)
      let searchable = "\(pageTitle(from: html) ?? "") \(text)".lowercased()

      let opening = String(searchable.prefix(3_000))
      if result.status == 404 || result.status == 410
        || closedPagePhrases.contains(where: opening.contains)
      {
        return inspection(.removed, checkedAt, result.finalURL, result.status, text, posting)
      }

      guard (200..<400).contains(result.status) else {
        return inspection(.unreachable, checkedAt, result.finalURL, result.status, text, posting)
      }

      let roleMatches = meaningfulTokens(in: expectedRole).filter(searchable.contains).count
      let companyMatches = meaningfulTokens(in: expectedCompany, minimumLength: 2)
        .filter(searchable.contains).count
      let roleTokenTarget = min(2, meaningfulTokens(in: expectedRole).count)
      let roleConfirmed = roleTokenTarget > 0 && roleMatches >= roleTokenTarget
      let companyConfirmed = expectedCompany.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || companyMatches > 0

      let status: OpportunityPageStatus = roleConfirmed && companyConfirmed ? .live : .inconclusive
      return inspection(status, checkedAt, result.finalURL, result.status, text, posting)
    } catch {
      return inspection(.unreachable, checkedAt, rawURL, nil)
    }
  }

  private static func response(from rawURL: String) async throws -> (
    data: Data, status: Int, finalURL: String
  ) {
    guard let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
      ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    else { throw JobCaptureError.invalidURL }

    var request = URLRequest(url: url)
    request.timeoutInterval = 20
    request.setValue(
      "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) ResumeStudio/1.0",
      forHTTPHeaderField: "User-Agent"
    )
    request.setValue("bytes=0-1499999", forHTTPHeaderField: "Range")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw JobCaptureError.unreadablePage }
    return (data, http.statusCode, http.url?.absoluteString ?? url.absoluteString)
  }

  private static func inspection(
    _ status: OpportunityPageStatus,
    _ checkedAt: Date,
    _ finalURL: String,
    _ httpStatus: Int?,
    _ readableText: String = "",
    _ structuredPosting: String? = nil
  ) -> OpportunityPageInspection {
    OpportunityPageInspection(
      status: status,
      checkedAt: checkedAt,
      finalURL: finalURL,
      httpStatus: httpStatus,
      readableText: readableText,
      structuredPosting: structuredPosting
    )
  }

  private static func decode(_ data: Data) -> String? {
    String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
  }

  private static func meaningfulTokens(in value: String, minimumLength: Int = 3) -> [String] {
    let ignored = Set(["and", "the", "for", "with", "from", "senior", "junior"])
    return value.lowercased()
      .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
      .map(String.init)
      .filter { $0.count >= minimumLength && !ignored.contains($0) }
  }

  private static func readableText(from html: String) -> String {
    html
      .replacingOccurrences(
        of: "(?is)<(script|style|svg|nav|footer)[^>]*>.*?</\\1>",
        with: " ",
        options: .regularExpression
      )
      .replacingOccurrences(
        of: "(?i)<br\\s*/?>|</p>|</li>|</h[1-6]>",
        with: "\n",
        options: .regularExpression
      )
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
  }

  private static func pageTitle(from html: String) -> String? {
    guard let range = html.range(
      of: "(?is)<title[^>]*>(.*?)</title>",
      options: .regularExpression
    ) else { return nil }
    let matched = String(html[range])
      .replacingOccurrences(of: "(?is)</?title[^>]*>", with: "", options: .regularExpression)
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return matched.isEmpty ? nil : matched
  }

  private static func structuredPosting(from html: String) -> String? {
    guard let regex = try? NSRegularExpression(
      pattern: "(?is)<script[^>]*type\\s*=\\s*[\\\"']application/ld\\+json[\\\"'][^>]*>(.*?)</script>"
    ) else { return nil }

    let source = html as NSString
    for match in regex.matches(in: html, range: NSRange(location: 0, length: source.length)) {
      guard match.numberOfRanges > 1 else { continue }
      let candidate = source.substring(with: match.range(at: 1))
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard let data = candidate.data(using: .utf8),
        let object = try? JSONSerialization.jsonObject(with: data),
        let posting = findJobPosting(in: object),
        let encoded = try? JSONSerialization.data(withJSONObject: posting, options: [.sortedKeys]),
        let result = String(data: encoded, encoding: .utf8)
      else { continue }
      return result
    }
    return nil
  }

  private static func findJobPosting(in object: Any) -> [String: Any]? {
    if let dictionary = object as? [String: Any] {
      let type = dictionary["@type"]
      let isPosting = (type as? String) == "JobPosting"
        || (type as? [String])?.contains("JobPosting") == true
      if isPosting { return dictionary }
      for value in dictionary.values {
        if let posting = findJobPosting(in: value) { return posting }
      }
    } else if let array = object as? [Any] {
      for value in array {
        if let posting = findJobPosting(in: value) { return posting }
      }
    }
    return nil
  }
}
