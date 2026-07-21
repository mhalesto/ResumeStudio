import Foundation

/// What to do with a saved opportunity. The bands exist to answer one question —
/// where is the next hour of effort best spent — so the guidance is a verdict,
/// not a description.
enum OpportunityBand: String, Codable, CaseIterable, Identifiable {
  case strong
  case possible
  case longShot
  case unscored

  var id: String { rawValue }

  var title: LocalizedStringResource {
    switch self {
    case .strong: "Apply"
    case .possible: "Tailor first"
    case .longShot: "Long shot"
    case .unscored: "Not enough advert"
    }
  }

  var guidance: LocalizedStringResource {
    switch self {
    case .strong:
      "Your résumé already speaks this advert's language. This is where an application is worth sending as it stands."
    case .possible:
      "A real chance, but not without work. Tailoring this one is a better use of an hour than sending three long shots."
    case .longShot:
      "Little of this advert's language appears in your résumé. Send it only if you know something the text does not show."
    case .unscored:
      "The saved advert is too short to score. Paste the full posting and this becomes rankable."
    }
  }

  var systemImage: String {
    switch self {
    case .strong: "checkmark.circle.fill"
    case .possible: "slider.horizontal.3"
    case .longShot: "arrow.up.forward.circle"
    case .unscored: "doc.badge.ellipsis"
    }
  }

  /// Sort order for the ranked list: act on these first.
  var rank: Int {
    switch self {
    case .strong: 0
    case .possible: 1
    case .longShot: 2
    case .unscored: 3
    }
  }
}

struct OpportunityScore: Identifiable, Equatable {
  var id: UUID
  var role: String
  var company: String
  /// Share of the advert's meaningful language the résumé already covers. Nil
  /// when the advert was too thin to judge.
  var coverage: Double?
  var band: OpportunityBand
  var matchedCount: Int
  var missingCount: Int
  /// The advert's most frequent terms that the résumé never uses, most
  /// important first.
  var topMissing: [String]
  /// Opportunity Shield is a separate axis from résumé fit. It can lower a
  /// strong keyword match when the listing itself needs verification.
  var signalBand: OpportunitySignalBand? = nil
  /// Combined shortlist ordering: fit, safety/freshness, deadline and a warm
  /// contact. This is an effort score, not a probability of being hired.
  var priorityScore: Double = 0
  var priorityReasons: [String] = []
  var deadline: Date? = nil

  var coveragePercentText: String {
    guard let coverage else { return "—" }
    return "\(Int((coverage * 100).rounded()))%"
  }

  var label: String {
    let parts = [role, company].filter { !$0.isBlank }
    return parts.isEmpty ? "Untitled opportunity" : parts.joined(separator: " at ")
  }
}

struct OpportunityRanking: Equatable {
  /// Best use of effort first.
  var scores: [OpportunityScore]

  var strongCount: Int { scores.count { $0.band == .strong } }
  var possibleCount: Int { scores.count { $0.band == .possible } }
  var longShotCount: Int { scores.count { $0.band == .longShot } }
  var unscoredCount: Int { scores.count { $0.band == .unscored } }
  var verifyFirstCount: Int {
    scores.count { $0.signalBand == .verify || $0.signalBand == .highRisk }
  }

  /// The one-line verdict over the whole shortlist.
  var summary: String {
    guard !scores.isEmpty else {
      return "Nothing saved yet. Capture a few adverts and this ranks them before you spend an evening on the wrong one."
    }
    if strongCount == 0 && possibleCount == 0 {
      return "Nothing here matches your résumé closely yet. That is worth knowing before you write \(scores.count) cover letter\(scores.count == 1 ? "" : "s")."
    }
    var parts: [String] = []
    if strongCount > 0 { parts.append("\(strongCount) ready to send") }
    if possibleCount > 0 { parts.append("\(possibleCount) worth tailoring") }
    if longShotCount > 0 { parts.append("\(longShotCount) to skip") }
    if verifyFirstCount > 0 { parts.append("\(verifyFirstCount) to verify first") }
    return parts.joined(separator: ", ") + "."
  }

  static let empty = OpportunityRanking(scores: [])
}
