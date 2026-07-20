import Foundation

enum ApplicationActivityKind: String, CaseIterable, Codable, Identifiable {
  case captured, applied, statusChanged, interview, followUp, note, offer
  var id: String { rawValue }
  var title: LocalizedStringResource {
    switch self {
    case .captured: "Captured"
    case .applied: "Applied"
    case .statusChanged: "Stage changed"
    case .interview: "Interview"
    case .followUp: "Follow-up"
    case .note: "Note"
    case .offer: "Offer"
    }
  }
  var systemImage: String {
    switch self {
    case .captured: "tray.and.arrow.down.fill"
    case .applied: "paperplane.fill"
    case .statusChanged: "arrow.triangle.swap"
    case .interview: "person.2.fill"
    case .followUp: "bell.fill"
    case .note: "note.text"
    case .offer: "star.fill"
    }
  }
}

struct ApplicationActivity: Identifiable, Codable, Equatable {
  var id = UUID()
  var kind: ApplicationActivityKind
  var title: String
  var detail: String
  var occurredAt = Date()
}

struct CapturedJobSnapshot: Codable, Equatable {
  var location: String
  var salary: String
  var closingDate: String
  var responsibilities: [String]
  var requirements: [String]
  var warnings: [String]
  var originalContent: String
  var capturedAt = Date()
}

enum ContactInteractionKind: String, CaseIterable, Codable, Identifiable {
  case email, linkedIn, phone, meeting, note
  var id: String { rawValue }
  /// Spelled out rather than derived from `rawValue`, so each label can be
  /// translated. "LinkedIn" is a product name and stays as it is.
  var title: LocalizedStringResource {
    switch self {
    case .email: "Email"
    case .linkedIn: "LinkedIn"
    case .phone: "Phone"
    case .meeting: "Meeting"
    case .note: "Note"
    }
  }
  var systemImage: String {
    switch self {
    case .email: "envelope.fill"
    case .linkedIn: "person.crop.rectangle"
    case .phone: "phone.fill"
    case .meeting: "person.2.fill"
    case .note: "note.text"
    }
  }
}

struct ContactInteraction: Identifiable, Codable, Equatable {
  var id = UUID()
  var kind: ContactInteractionKind
  var summary: String
  var occurredAt = Date()
}

enum AIRevisionStatus: String, Codable { case applied, reverted }

struct AIRevision: Identifiable, Codable, Equatable {
  var id = UUID()
  var resumeID: UUID?
  var field: String
  var before: String
  var after: String
  var evidenceIDs: [UUID]
  var evidenceLabels: [String]
  var claimsRequiringConfirmation: [String]
  var status: AIRevisionStatus = .applied
  var createdAt = Date()
  var revertedAt: Date?
}

struct AIProcessingRecord: Identifiable, Codable, Equatable {
  var id = UUID()
  var action: String
  var purpose: String
  var includedVerifiedEvidence: Bool
  var provider: ProductInsightSource? = nil
  var completedAt = Date()
}

struct MarketGuidanceSource: Identifiable, Codable, Equatable {
  var id = UUID()
  var market: ResumeMarket
  var title: String
  var publisher: String
  var url: String
  var checkedAt: Date
  var note: String
}

struct SharedJobCapture: Codable, Equatable {
  var url: String
  var text: String
  /// The page's own title, and the schema.org JobPosting it publishes for search
  /// engines, as read in Safari by the share extension. Optional because a
  /// capture queued by an older build decodes without them, and because plenty
  /// of pages publish no structured posting at all.
  var title: String? = nil
  var posting: String? = nil
  var receivedAt = Date()

  /// What to hand the capture step. A structured posting is the same words the
  /// board gives Google, without the navigation, cookie banners and "similar
  /// jobs" that surround them on the page — so it is worth far more than a
  /// longer sweep of visible text.
  var bestAvailableText: String {
    if let described = Self.described(posting) { return described }
    // With no structured posting, the page title is the most reliable thing on
    // the page — boards set it to "Role at Company" almost without exception,
    // while the same words in the body are surrounded by navigation. Skipped
    // when the text already opens with it, which is common enough.
    guard let heading = title?.trimmingCharacters(in: .whitespacesAndNewlines),
      !heading.isBlank, !text.hasPrefix(heading)
    else { return text }
    return text.isBlank ? heading : "\(heading)\n\n\(text)"
  }

  /// Flattens a JobPosting into the plain wording the rest of the pipeline reads.
  private static func described(_ posting: String?) -> String? {
    guard let data = posting?.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }

    var lines: [String] = []
    if let title = object["title"] as? String { lines.append(title) }
    if let organisation = object["hiringOrganization"] as? [String: Any],
      let name = organisation["name"] as? String
    {
      lines.append(name)
    }
    if let location = describedLocation(object) { lines.append(location) }
    for key in ["employmentType", "datePosted"] {
      if let value = object[key] as? String { lines.append(value) }
    }
    if let closing = object["validThrough"] as? String {
      lines.append("Closing date: \(closing)")
    }
    // Pay is the thing most often buried furthest down a posting, and the thing
    // most worth having when the offer conversation comes round.
    if let salary = describedSalary(object) { lines.append("Salary: \(salary)") }
    if let description = object["description"] as? String {
      lines.append(strippingMarkup(from: description))
    }

    let joined = lines.filter { !$0.isBlank }.joined(separator: "\n")
    return joined.isBlank ? nil : joined
  }

  /// Where the work is. A remote posting says so through `jobLocationType`
  /// rather than in the address, and that is worth carrying across plainly.
  private static func describedLocation(_ object: [String: Any]) -> String? {
    var parts: [String] = []
    // `jobLocation` is a single place on most boards and a list on a few.
    let places: [[String: Any]] = {
      if let one = object["jobLocation"] as? [String: Any] { return [one] }
      return object["jobLocation"] as? [[String: Any]] ?? []
    }()
    for place in places {
      guard let address = place["address"] as? [String: Any] else { continue }
      let named = ["addressLocality", "addressRegion", "addressCountry"]
        .compactMap { address[$0] as? String }
      if !named.isEmpty { parts.append(named.joined(separator: ", ")) }
    }
    if let type = object["jobLocationType"] as? String, type.uppercased().contains("TELECOMMUTE")
    {
      parts.append(String(localized: "Remote"))
    }
    let joined = parts.joined(separator: " · ")
    return joined.isBlank ? nil : joined
  }

  /// `baseSalary` is a MonetaryAmount: a currency, and a value that is either a
  /// single figure or a range, quoted per hour, month or year.
  private static func describedSalary(_ object: [String: Any]) -> String? {
    guard let salary = object["baseSalary"] as? [String: Any],
      let value = salary["value"] as? [String: Any]
    else { return nil }

    func number(_ key: String) -> String? {
      if let amount = value[key] as? Double {
        return amount.formatted(.number.precision(.fractionLength(0)))
      }
      if let amount = value[key] as? Int { return String(amount) }
      if let amount = value[key] as? String, !amount.isBlank { return amount }
      return nil
    }

    let figure: String
    if let single = number("value") {
      figure = single
    } else if let low = number("minValue"), let high = number("maxValue") {
      figure = "\(low) – \(high)"
    } else if let low = number("minValue") {
      figure = "from \(low)"
    } else {
      return nil
    }

    let currency = (salary["currency"] as? String) ?? ""
    let unit = (value["unitText"] as? String)?.lowercased()
    let period =
      switch unit {
      case "hour": String(localized: "per hour")
      case "day": String(localized: "per day")
      case "week": String(localized: "per week")
      case "month": String(localized: "per month")
      case "year": String(localized: "per year")
      default: ""
      }
    return [currency, figure, period].filter { !$0.isBlank }.joined(separator: " ")
  }

  /// JobPosting descriptions are published as escaped HTML. Block tags become
  /// line breaks so the paragraphing survives, and the rest simply goes.
  private static func strippingMarkup(from html: String) -> String {
    let broken = html.replacingOccurrences(
      of: "<(br|/p|/div|/li|/h[1-6])[^>]*>", with: "\n",
      options: [.regularExpression, .caseInsensitive])
    let stripped = broken.replacingOccurrences(
      of: "<[^>]+>", with: "", options: .regularExpression)
    return stripped
      .replacingOccurrences(of: "&nbsp;", with: " ")
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&#39;", with: "'")
      .replacingOccurrences(
        of: "\n\\s*\n\\s*\n+", with: "\n\n", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

enum CareerPrivacySetting {
  static let aiEnabledKey = "careerAIProcessingEnabled"
  static let shareVerifiedEvidenceKey = "careerAIShareVerifiedEvidence"
  static let keepHistoryKey = "careerAIKeepProcessingHistory"
  static let onDeviceAIKey = "careerAIUseOnDeviceIntelligence"
  static let connectedFallbackKey = "careerAIAllowConnectedFallback"
}
