import Foundation

/// Coarse role families for benchmark cohorts. Deliberately broad, and mirrored
/// exactly by `BENCHMARK_ROLE_FAMILIES` in `functions/src/benchmark-policy.js` —
/// the server rejects anything not on its own list, so the two must agree.
enum BenchmarkRoleFamily: String, Codable, CaseIterable, Identifiable {
  case engineering
  case dataAnalytics
  case design
  case product
  case marketing
  case sales
  case customerSuccess
  case financeAccounting
  case peopleOperations
  case operationsLogistics
  case healthcare
  case education
  case legal
  case tradesTechnical
  case other

  var id: String { rawValue }

  var title: LocalizedStringResource {
    switch self {
    case .engineering: "Engineering"
    case .dataAnalytics: "Data & analytics"
    case .design: "Design"
    case .product: "Product"
    case .marketing: "Marketing"
    case .sales: "Sales"
    case .customerSuccess: "Customer success"
    case .financeAccounting: "Finance & accounting"
    case .peopleOperations: "People & HR"
    case .operationsLogistics: "Operations & logistics"
    case .healthcare: "Healthcare"
    case .education: "Education"
    case .legal: "Legal & compliance"
    case .tradesTechnical: "Trades & technical"
    case .other: "Other"
    }
  }
}

enum BenchmarkSeniority: String, Codable, CaseIterable, Identifiable {
  case entry
  case mid
  case senior
  case lead

  var id: String { rawValue }

  var title: LocalizedStringResource {
    switch self {
    case .entry: "Entry level"
    case .mid: "Mid level"
    case .senior: "Senior"
    case .lead: "Lead & above"
    }
  }
}

struct BenchmarkCohort: Codable, Equatable, Hashable {
  var roleFamily: BenchmarkRoleFamily
  var market: ResumeMarket
  var seniority: BenchmarkSeniority

  var title: String {
    "\(String(localized: seniority.title)) · \(String(localized: roleFamily.title)) · \(String(localized: market.title))"
  }
}

/// What this installation would contribute: counts only. No résumé content, no
/// employer names, no job titles, no URLs.
struct BenchmarkContribution: Codable, Equatable {
  var cohort: BenchmarkCohort
  var settled: Int
  var progressed: Int
  var medianDaysToProgress: Int?
}

/// What the server released for a cohort. Everything is rounded server-side, and
/// nothing is released at all until enough distinct installations are in it.
struct BenchmarkSnapshot: Codable, Equatable {
  var released: Bool
  var contributors: Int
  var settled: Int
  var progressionPercent: Int?
  var medianDaysToProgress: Int?

  static let unreleased = BenchmarkSnapshot(
    released: false, contributors: 0, settled: 0,
    progressionPercent: nil, medianDaysToProgress: nil
  )
}

enum BenchmarkVerdict: String, Equatable {
  case ahead
  case inLine
  case behind
  /// Either the cohort or this user's own history is too thin to compare.
  case unknown

  var title: LocalizedStringResource {
    switch self {
    case .ahead: "Ahead of your cohort"
    case .inLine: "In line with your cohort"
    case .behind: "Behind your cohort"
    case .unknown: "Not comparable yet"
    }
  }

  var systemImage: String {
    switch self {
    case .ahead: "arrow.up.right.circle.fill"
    case .inLine: "equal.circle.fill"
    case .behind: "arrow.down.right.circle.fill"
    case .unknown: "questionmark.circle"
    }
  }
}

struct BenchmarkComparison: Equatable {
  var cohort: BenchmarkCohort
  var snapshot: BenchmarkSnapshot
  var localSettled: Int
  var localProgressed: Int
  var localProgressionPercent: Int?
  var verdict: BenchmarkVerdict
  var headline: String
  var detail: String
}
