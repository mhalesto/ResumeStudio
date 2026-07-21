import Foundation

/// The decision Opportunity Shield makes about a posting. It deliberately avoids
/// "real" and "fake": no parser can know an employer's private hiring intent.
enum OpportunitySignalBand: String, Codable, CaseIterable, Identifiable {
  case strong
  case verify
  case highRisk

  var id: String { rawValue }

  var title: LocalizedStringResource {
    switch self {
    case .strong: "Strong signals"
    case .verify: "Verify first"
    case .highRisk: "High-risk signals"
    }
  }

  var guidance: LocalizedStringResource {
    switch self {
    case .strong:
      "The listing exposes enough current, specific and verifiable detail to justify the next step."
    case .verify:
      "Some useful signals are missing or unclear. Confirm the role on the employer's own website before sharing sensitive information."
    case .highRisk:
      "One or more concrete warning signs need attention before you spend time tailoring or share personal information."
    }
  }

  var systemImage: String {
    switch self {
    case .strong: "checkmark.shield.fill"
    case .verify: "shield.lefthalf.filled"
    case .highRisk: "exclamationmark.shield.fill"
    }
  }

  /// Higher is safer. Used as one input to shortlist priority, never as proof.
  var rankingWeight: Double {
    switch self {
    case .strong: 0.12
    case .verify: -0.12
    case .highRisk: -1
    }
  }
}

enum OpportunitySignalConfidence: String, Codable {
  case limited
  case useful
  case strong

  var title: LocalizedStringResource {
    switch self {
    case .limited: "Limited evidence"
    case .useful: "Useful evidence"
    case .strong: "Strong evidence"
    }
  }
}

enum OpportunitySignalCategory: String, Codable, CaseIterable, Identifiable {
  case freshness
  case employer
  case listing
  case safety

  var id: String { rawValue }

  var title: LocalizedStringResource {
    switch self {
    case .freshness: "Freshness"
    case .employer: "Employer verification"
    case .listing: "Listing quality"
    case .safety: "Safety"
    }
  }

  var systemImage: String {
    switch self {
    case .freshness: "clock.badge.checkmark"
    case .employer: "building.2.crop.circle"
    case .listing: "doc.text.magnifyingglass"
    case .safety: "lock.shield"
    }
  }
}

enum OpportunitySignalSeverity: String, Codable {
  case positive
  case information
  case caution
  case danger

  var systemImage: String {
    switch self {
    case .positive: "checkmark.circle.fill"
    case .information: "info.circle.fill"
    case .caution: "exclamationmark.circle.fill"
    case .danger: "xmark.octagon.fill"
    }
  }
}

struct OpportunitySignalFinding: Identifiable, Codable, Equatable {
  /// A stable policy identifier such as `fresh-recent` or `safety-fee`.
  var id: String
  var category: OpportunitySignalCategory
  var severity: OpportunitySignalSeverity
  var title: String
  var detail: String
}

enum OpportunityPageStatus: String, Codable {
  case notChecked
  case live
  case removed
  case inconclusive
  case unreachable

  var title: LocalizedStringResource {
    switch self {
    case .notChecked: "Not checked online"
    case .live: "Listing still live"
    case .removed: "Listing removed"
    case .inconclusive: "Page could not confirm the role"
    case .unreachable: "Page could not be reached"
    }
  }
}

struct OpportunityCheckRecord: Identifiable, Codable, Equatable {
  var checkedAt: Date
  var pageStatus: OpportunityPageStatus
  var postingDate: Date?
  var contentDigest: String

  var id: String {
    "\(checkedAt.timeIntervalSince1970)-\(pageStatus.rawValue)-\(contentDigest)"
  }
}

struct OpportunitySignalReport: Codable, Equatable {
  var band: OpportunitySignalBand
  var confidence: OpportunitySignalConfidence
  var findings: [OpportunitySignalFinding]
  var checkedAt: Date
  var datePosted: Date?
  var validThrough: Date?
  var employerWebsite: String?
  var postingFingerprint: String
  var contentDigest: String
  var repostCount: Int
  var pageStatus: OpportunityPageStatus
  var pageCheckedAt: Date?
  var checkHistory: [OpportunityCheckRecord]

  func findings(in category: OpportunitySignalCategory) -> [OpportunitySignalFinding] {
    findings.filter { $0.category == category }
  }

  var shouldRefresh: Bool {
    guard let pageCheckedAt else { return true }
    return Date().timeIntervalSince(pageCheckedAt) >= 24 * 60 * 60
  }
}

/// The result of a conservative reachability check. The readable page and
/// structured posting are transient inputs used to rebuild the saved report.
struct OpportunityPageInspection: Equatable {
  var status: OpportunityPageStatus
  var checkedAt: Date
  var finalURL: String
  var httpStatus: Int?
  var readableText: String
  var structuredPosting: String?
}
