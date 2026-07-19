import Foundation

enum OutcomeLearningService {
  static func summarize(
    applications: [JobApplication],
    resumes: [ResumeDraft]
  ) -> OutcomeLearningSummary {
    let eligible = applications.filter(\.canReviewCurrentOutcome)
    let pending = eligible.filter(\.needsCurrentOutcomeReview)
      .sorted { $0.updatedAt > $1.updatedAt }
    let reviews = applications.flatMap { application in
      application.outcomeReviewList.map { (application: application, review: $0) }
    }

    if let application = pending.first {
      return OutcomeLearningSummary(
        eligibleCount: eligible.count,
        reviewedCount: reviews.count,
        pendingApplicationIDs: pending.map(\.id),
        recommendation: OutcomeLearningRecommendation(
          id: "collect-\(application.id.uuidString)-\(application.status.rawValue)",
          title: "Turn this result into useful evidence",
          detail: "Capture what happened with \(application.role.nilIfBlank ?? "this application") before the details fade.",
          evidence: pending.count == 1
            ? "One application is waiting for a private outcome review."
            : "\(pending.count) applications are waiting for a private outcome review.",
          actionTitle: "Review outcome",
          focus: .collectOutcome,
          applicationID: application.id,
          resumeID: application.resumeUsedForOutcome,
          sampleSize: reviews.count
        )
      )
    }

    if reviews.isEmpty {
      return OutcomeLearningSummary(
        eligibleCount: eligible.count,
        reviewedCount: 0,
        pendingApplicationIDs: [],
        recommendation: OutcomeLearningRecommendation(
          id: "collect-first",
          title: "Your next result will start the learning loop",
          detail: "When an application reaches interview, offer or rejection, add a short debrief here.",
          evidence: "Résumé advice stays general until it is grounded in a real outcome.",
          actionTitle: "Open applications",
          focus: .collectOutcome,
          applicationID: nil,
          resumeID: nil,
          sampleSize: 0
        )
      )
    }

    let actionable = reviews.filter { $0.review.reason.learningFocus.supportsDrafting }
    if let signal = strongestSignal(in: actionable) {
      let focus = signal.review.reason.learningFocus
      let count = actionable.count { $0.review.reason.learningFocus == focus }
      let explanation: String
      switch focus {
      case .professionalProfile:
        explanation = "Clarify the target and value proposition in the opening profile without inventing new experience."
      case .experienceEvidence:
        explanation = "Strengthen one existing achievement so the evidence is easier to find and trust."
      case .competencies:
        explanation = "Surface skills already supported by the résumé instead of adding unsupported keywords."
      default:
        explanation = "Use the recorded signal to make one focused improvement."
      }
      return OutcomeLearningSummary(
        eligibleCount: eligible.count,
        reviewedCount: reviews.count,
        pendingApplicationIDs: [],
        recommendation: OutcomeLearningRecommendation(
          id: "improve-\(focus.rawValue)-\(signal.application.id.uuidString)",
          title: String(localized: focus.title),
          detail: explanation,
          evidence: evidenceLabel(count: count, reason: signal.review.reason),
          actionTitle: "Create reviewed improvement",
          focus: focus,
          applicationID: signal.application.id,
          resumeID: signal.review.resumeID,
          sampleSize: count
        )
      )
    }

    if let best = bestPerformingResume(in: reviews, resumes: resumes) {
      return OutcomeLearningSummary(
        eligibleCount: eligible.count,
        reviewedCount: reviews.count,
        pendingApplicationIDs: [],
        recommendation: OutcomeLearningRecommendation(
          id: "preserve-\(best.id.uuidString)",
          title: "Reuse the résumé version earning progress",
          detail: "Start the next relevant application from \(best.title), then tailor only what the new role requires.",
          evidence: "\(best.positive) of \(best.total) reviewed outcomes using this version progressed positively. This is a correlation, not a promise.",
          actionTitle: "View résumé versions",
          focus: .preserveStrength,
          applicationID: nil,
          resumeID: best.id,
          sampleSize: best.total
        )
      )
    }

    if let source = bestPerformingSource(in: reviews) {
      return OutcomeLearningSummary(
        eligibleCount: eligible.count,
        reviewedCount: reviews.count,
        pendingApplicationIDs: [],
        recommendation: OutcomeLearningRecommendation(
          id: "target-\(source.name)",
          title: "Run the next search as a small experiment",
          detail: "Prioritise another well-matched role from \(source.name), while keeping the résumé version and role family comparable.",
          evidence: "\(source.positive) of \(source.total) reviewed outcomes from this source progressed positively.",
          actionTitle: "Capture next opportunity",
          focus: .targeting,
          applicationID: nil,
          resumeID: nil,
          sampleSize: source.total
        )
      )
    }

    return OutcomeLearningSummary(
      eligibleCount: eligible.count,
      reviewedCount: reviews.count,
      pendingApplicationIDs: [],
      recommendation: OutcomeLearningRecommendation(
        id: "targeting-baseline",
        title: "Keep the next change measurable",
        detail: "Apply to a closely matched role and change only one major résumé element so the next outcome is easier to learn from.",
        evidence: "\(reviews.count) outcome review\(reviews.count == 1 ? " is" : "s are") saved locally; there is not yet a repeated résumé signal.",
        actionTitle: "Capture next opportunity",
        focus: .targeting,
        applicationID: nil,
        resumeID: nil,
        sampleSize: reviews.count
      )
    )
  }

  private static func strongestSignal(
    in values: [(application: JobApplication, review: ApplicationOutcomeReview)]
  ) -> (application: JobApplication, review: ApplicationOutcomeReview)? {
    guard !values.isEmpty else { return nil }
    let grouped = Dictionary(grouping: values) { $0.review.reason.learningFocus }
    let focus = grouped.keys.sorted { left, right in
      let leftCount = grouped[left]?.count ?? 0
      let rightCount = grouped[right]?.count ?? 0
      if leftCount != rightCount { return leftCount > rightCount }
      return left.rawValue < right.rawValue
    }.first
    return focus.flatMap { grouped[$0]?.max { $0.review.updatedAt < $1.review.updatedAt } }
  }

  private static func evidenceLabel(count: Int, reason: ApplicationOutcomeReason) -> String {
    // Resolved before interpolation so the reason reads in the user's language.
    // Lower-casing suits the English sentence; German capitalises nouns, so this
    // sentence is a candidate for a per-language form if it ever reads oddly.
    let reasonText = String(localized: reason.title).lowercased()
    if count == 1 {
      return "One recorded outcome points to “\(reasonText)”. Treat it as a hypothesis to test, not a verdict."
    }
    return "\(count) recorded outcomes point to “\(reasonText)”."
  }

  private struct ResumeResult {
    let id: UUID
    let title: String
    let positive: Int
    let total: Int
  }

  private static func bestPerformingResume(
    in values: [(application: JobApplication, review: ApplicationOutcomeReview)],
    resumes: [ResumeDraft]
  ) -> ResumeResult? {
    let groups = Dictionary(grouping: values, by: { $0.review.resumeID })
    return groups.compactMap { id, outcomes -> ResumeResult? in
      guard outcomes.count >= 2 else { return nil }
      let positive = outcomes.count { isPositive($0.review) }
      guard positive > 0 else { return nil }
      let title = resumes.first(where: { $0.id == id })?.title ?? "a saved résumé version"
      return ResumeResult(id: id, title: title, positive: positive, total: outcomes.count)
    }.sorted {
      let left = Double($0.positive) / Double($0.total)
      let right = Double($1.positive) / Double($1.total)
      if left != right { return left > right }
      if $0.total != $1.total { return $0.total > $1.total }
      return $0.title < $1.title
    }.first
  }

  private struct SourceResult {
    let name: String
    let positive: Int
    let total: Int
  }

  private static func bestPerformingSource(
    in values: [(application: JobApplication, review: ApplicationOutcomeReview)]
  ) -> SourceResult? {
    let groups = Dictionary(grouping: values) { sourceName(for: $0.application) }
    return groups.compactMap { name, outcomes -> SourceResult? in
      guard outcomes.count >= 2 else { return nil }
      let positive = outcomes.count { isPositive($0.review) }
      guard positive > 0 else { return nil }
      return SourceResult(name: name, positive: positive, total: outcomes.count)
    }.sorted {
      let left = Double($0.positive) / Double($0.total)
      let right = Double($1.positive) / Double($1.total)
      if left != right { return left > right }
      if $0.total != $1.total { return $0.total > $1.total }
      return $0.name < $1.name
    }.first
  }

  private static func isPositive(_ review: ApplicationOutcomeReview) -> Bool {
    review.stage == .interview || review.stage == .offer || review.reason.isPositiveSignal
  }

  private static func sourceName(for application: JobApplication) -> String {
    guard let url = URL(string: application.sourceURL), let host = url.host() else {
      return application.sourceURL.isBlank ? "direct applications" : "other sources"
    }
    return host.replacingOccurrences(of: "www.", with: "")
  }
}
