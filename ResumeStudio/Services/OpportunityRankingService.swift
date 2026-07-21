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
    document: ResumeDocument,
    contacts: [CareerContact] = [],
    now: Date = Date()
  ) -> OpportunityRanking {
    let candidates = applications.filter { $0.status == .saved }
    let scores = candidates.map { score($0, document: document, contacts: contacts, now: now) }
    return OpportunityRanking(
      scores: scores.sorted { left, right in
        if left.signalBand == .highRisk && right.signalBand != .highRisk { return false }
        if right.signalBand == .highRisk && left.signalBand != .highRisk { return true }
        if left.priorityScore != right.priorityScore { return left.priorityScore > right.priorityScore }
        if left.band != right.band { return left.band.rank < right.band.rank }
        if left.coverage != right.coverage { return (left.coverage ?? 0) > (right.coverage ?? 0) }
        return left.label < right.label
      }
    )
  }

  static func score(
    _ application: JobApplication,
    document: ResumeDocument,
    contacts: [CareerContact] = [],
    now: Date = Date()
  ) -> OpportunityScore {
    let advert = application.jobDescription
    guard advert.split(whereSeparator: \.isWhitespace).count >= minimumAdvertWords else {
      let effortPriority = priority(
        coverage: nil, application: application, contacts: contacts, now: now)
      return OpportunityScore(
        id: application.id,
        role: application.role,
        company: application.company,
        coverage: nil,
        band: .unscored,
        matchedCount: 0,
        missingCount: 0,
        topMissing: [],
        signalBand: application.capturedOpportunity?.opportunitySignal?.band,
        priorityScore: effortPriority.score,
        priorityReasons: effortPriority.reasons,
        deadline: application.deadline
      )
    }

    let report = ATSReadinessService.analyze(document: document, jobDescription: advert)
    let matched = report.matchedKeywords.count
    let total = matched + report.missingKeywords.count
    guard total > 0 else {
      let effortPriority = priority(
        coverage: nil, application: application, contacts: contacts, now: now)
      return OpportunityScore(
        id: application.id,
        role: application.role,
        company: application.company,
        coverage: nil,
        band: .unscored,
        matchedCount: 0,
        missingCount: 0,
        topMissing: [],
        signalBand: application.capturedOpportunity?.opportunitySignal?.band,
        priorityScore: effortPriority.score,
        priorityReasons: effortPriority.reasons,
        deadline: application.deadline
      )
    }

    let coverage = Double(matched) / Double(total)
    let topMissing = ATSReadinessService
      .keywordSuggestions(document: document, jobDescription: advert)
      .prefix(missingKeywordLimit)
      .map(\.keyword)

    let effortPriority = priority(
      coverage: coverage, application: application, contacts: contacts, now: now)
    return OpportunityScore(
      id: application.id,
      role: application.role,
      company: application.company,
      coverage: coverage,
      band: band(for: coverage),
      matchedCount: matched,
      missingCount: report.missingKeywords.count,
      topMissing: topMissing,
      signalBand: application.capturedOpportunity?.opportunitySignal?.band,
      priorityScore: effortPriority.score,
      priorityReasons: effortPriority.reasons,
      deadline: application.deadline
    )
  }

  private static func priority(
    coverage: Double?,
    application: JobApplication,
    contacts: [CareerContact],
    now: Date
  ) -> (score: Double, reasons: [String]) {
    var score = (coverage ?? 0) * 0.7
    var reasons: [String] = []
    if let coverage {
      reasons.append("\(Int((coverage * 100).rounded()))% résumé language coverage")
    } else {
      reasons.append("Full advert needed for fit scoring")
    }

    if let signal = application.capturedOpportunity?.opportunitySignal?.band {
      score += signal.rankingWeight
      switch signal {
      case .strong: reasons.append("Strong opportunity signals")
      case .verify: reasons.append("Verify the listing before tailoring")
      case .highRisk: reasons.append("Resolve high-risk signals before applying")
      }
    }

    if let deadline = application.deadline {
      let days = Calendar.current.dateComponents(
        [.day], from: Calendar.current.startOfDay(for: now),
        to: Calendar.current.startOfDay(for: deadline)
      ).day ?? 0
      if days < 0 {
        score -= 0.2
        reasons.append("Saved deadline has passed")
      } else if days <= 2 {
        score += 0.18
        reasons.append("Deadline is within two days")
      } else if days <= 7 {
        score += 0.12
        reasons.append("Deadline is within a week")
      } else if days <= 14 {
        score += 0.06
        reasons.append("Deadline is within two weeks")
      }
    }

    let warmContact = contacts.first { contact in
      contact.applicationID == application.id
        || (!contact.company.isBlank && !application.company.isBlank
          && contact.company.caseInsensitiveCompare(application.company) == .orderedSame)
    }
    if let warmContact {
      let bonus = min(0.16, 0.1 + Double(warmContact.relationshipStrength ?? 0) * 0.012)
      score += bonus
      reasons.append("Warm contact at this employer")
    }
    return (max(-1, min(1.2, score)), reasons)
  }

  static func band(for coverage: Double) -> OpportunityBand {
    if coverage >= strongCoverage { return .strong }
    if coverage >= possibleCoverage { return .possible }
    return .longShot
  }
}
