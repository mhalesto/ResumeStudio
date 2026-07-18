import Foundation

/// A labelled external link shown on the hosted CV page (LinkedIn, a portfolio,
/// GitHub…). `id` is local only — the backend contract is just `{label, url}`,
/// so it is excluded from coding and defaulted when a fetched page is decoded.
struct ProfileLink: Identifiable, Codable, Equatable, Hashable {
  var id = UUID()
  var label: String
  var url: String

  init(id: UUID = UUID(), label: String = "", url: String = "") {
    self.id = id
    self.label = label
    self.url = url
  }

  enum CodingKeys: String, CodingKey { case label, url }
}

/// The published state of a person's hosted CV page (the vanity `/p/<handle>`
/// URL). Mirrors the backend's profile payload.
struct PersonalProfile: Codable, Equatable {
  var handle: String
  var displayName: String
  var headline: String
  var location: String
  var links: [ProfileLink]
  var searchable: Bool
  /// True on Free — the page carries a "Made with ResumeStudio" footer that Go
  /// and Pro remove.
  var branded: Bool
  var pageCount: Int
  var hostedURL: String
  var updatedAt: Date?

  var url: URL? { URL(string: hostedURL) }

  /// A URL-safe handle guess from a name, e.g. "Jane Doe" → "jane-doe".
  static func suggestedHandle(from name: String) -> String {
    let lowered = name.lowercased()
    var slug = ""
    var lastWasHyphen = false
    for scalar in lowered.unicodeScalars {
      if scalar == "-" || scalar == " " || scalar == "." || scalar == "_" {
        if !slug.isEmpty && !lastWasHyphen { slug.append("-"); lastWasHyphen = true }
      } else if (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9") {
        slug.unicodeScalars.append(scalar)
        lastWasHyphen = false
      }
    }
    while slug.hasSuffix("-") { slug.removeLast() }
    return String(slug.prefix(30))
  }

  /// Client-side mirror of the backend's `validHandle`: 3–30 chars, lowercase
  /// alphanumeric and single interior hyphens. Keeps the editor from firing a
  /// request the server will only reject.
  static func isValidHandle(_ value: String) -> Bool {
    guard (3...30).contains(value.count) else { return false }
    guard value.range(of: "^[a-z0-9][a-z0-9-]{1,28}[a-z0-9]$", options: .regularExpression) != nil
    else { return false }
    return !value.contains("--")
  }
}
