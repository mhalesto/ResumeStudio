import Foundation

/// Ranks saved opportunities against the current résumé so the next hour goes to
/// the application most likely to land, and the hopeless ones are named as such.
///
/// Runs entirely on device against the existing ATS keyword engine, so it costs
/// no AI credits and works offline.
enum OpportunityRankingService {
  /// Bands are anchored to the ATS keyword check's own pass line rather than to
  /// fresh numbers, so a résumé that "passes" the ATS check for an advert can
  /// never be ranked a long shot for the same advert.
  static var strongCoverage: Double { ATSReadinessService.jobLanguagePassThreshold * 1.55 }
  static var possibleCoverage: Double { ATSReadinessService.jobLanguagePassThreshold * 0.9 }
  /// Below this many words an advert is a job title and a link, not something
  /// that can be scored. `JobDescriptionAnalyzer` treats the same length as a
  /// blocking issue.
  static let minimumAdvertWords = 40
  /// How many missing terms are worth showing before the list becomes noise.
  static let missingKeywordLimit = 5

  static func rank(
    applications: [JobApplication],
    document: ResumeDocument
  ) -> OpportunityRanking {
    let candidates = applications.filter { $0.status == .saved }
    let scores = candidates.map { score($0, document: document) }
    return OpportunityRanking(
      scores: scores.sorted { left, right in
        if left.band != right.band { return left.band.rank < right.band.rank }
        if left.coverage != right.coverage { return (left.coverage ?? 0) > (right.coverage ?? 0) }
        return left.label < right.label
      }
    )
  }

  static func score(_ application: JobApplication, document: ResumeDocument) -> OpportunityScore {
    let advert = application.jobDescription
    guard advert.split(whereSeparator: \.isWhitespace).count >= minimumAdvertWords else {
      return OpportunityScore(
        id: application.id,
        role: application.role,
        company: application.company,
        coverage: nil,
        band: .unscored,
        matchedCount: 0,
        missingCount: 0,
        topMissing: []
      )
    }

    let report = ATSReadinessService.analyze(document: document, jobDescription: advert)
    let matched = report.matchedKeywords.count
    let total = matched + report.missingKeywords.count
    guard total > 0 else {
      return OpportunityScore(
        id: application.id,
        role: application.role,
        company: application.company,
        coverage: nil,
        band: .unscored,
        matchedCount: 0,
        missingCount: 0,
        topMissing: []
      )
    }

    let coverage = Double(matched) / Double(total)
    let topMissing = ATSReadinessService
      .keywordSuggestions(document: document, jobDescription: advert)
      .prefix(missingKeywordLimit)
      .map(\.keyword)

    return OpportunityScore(
      id: application.id,
      role: application.role,
      company: application.company,
      coverage: coverage,
      band: band(for: coverage),
      matchedCount: matched,
      missingCount: report.missingKeywords.count,
      topMissing: topMissing
    )
  }

  static func band(for coverage: Double) -> OpportunityBand {
    if coverage >= strongCoverage { return .strong }
    if coverage >= possibleCoverage { return .possible }
    return .longShot
  }
}
