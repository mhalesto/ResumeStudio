import Foundation

/// Reads the application history and reports what it actually shows, including
/// the parts that are unflattering. Everything here is computed on device from
/// data the user already recorded; nothing is sent anywhere.
///
/// The thresholds are named constants rather than inline numbers because the UI
/// makes promises about them ("at least four comparable applications"), and the
/// tests pin those promises.
enum ApplicationCalibrationService {
  /// An application that has been sitting this long without moving has told us
  /// something, even though no one replied.
  static let settlingDays = 21
  /// Below this, "no responses yet" is ordinary noise rather than a finding.
  static let droughtMinimumSettled = 8
  /// A job-match analysis with fewer keywords than this is too thin to score.
  static let minimumKeywordSample = 4
  /// Matching at least this share of a job's language counts as well matched.
  static let strongCoverageThreshold = 0.6
  /// Comparing two groups needs a floor in each, or the difference is noise.
  static let comparisonMinimumStretch = 4
  static let comparisonMinimumMatched = 2
  static let advantageMinimumPerGroup = 3
  /// The share of applications that must be stretches before the pattern reads
  /// as reaching rather than a healthy spread.
  static let stretchShareThreshold = 0.6
  /// How much better the well-matched group must do before we say so.
  static let meaningfulRateGap = 0.15
  static let concentrationMinimumSettled = 6
  static let concentrationShareThreshold = 0.7
  static let progressMinimumSettled = 4
  static let healthyProgressionRate = 0.2
  static let emergingSampleSize = 6
  static let consistentSampleSize = 12

  static func calibrate(
    applications: [JobApplication],
    now: Date = Date()
  ) -> ApplicationCalibrationReport {
    let settled = applications.filter { isSettled($0, now: now) }
    let progressedApplications = settled.filter { progressed($0) }
    let scored = settled.compactMap { application -> ScoredApplication? in
      guard let coverage = matchCoverage(application) else { return nil }
      return ScoredApplication(
        application: application,
        coverage: coverage,
        progressed: Self.progressed(application)
      )
    }

    var signals: [ApplicationCalibrationSignal] = []
    signals.append(contentsOf: matchComparisonSignals(scored))
    if let drought = droughtSignal(settled: settled, progressed: progressedApplications) {
      signals.append(drought)
    }
    if let concentration = concentrationSignal(settled: settled) {
      signals.append(concentration)
    }
    if let progress = progressSignal(settled: settled, progressed: progressedApplications) {
      signals.append(progress)
    }
    if signals.isEmpty, let waiting = notEnoughDataSignal(settled: settled, scored: scored) {
      signals.append(waiting)
    }

    return ApplicationCalibrationReport(
      signals: signals.sorted { priority($0.kind) < priority($1.kind) },
      settledCount: settled.count,
      progressedCount: progressedApplications.count,
      analyzedCount: scored.count
    )
  }

  // MARK: - Signals

  /// The comparison at the centre of this feature: do the roles you already
  /// match do better than the roles you are reaching for? Only one of the two
  /// signals can fire, because they are separated by how lopsided the spread is.
  private static func matchComparisonSignals(
    _ scored: [ScoredApplication]
  ) -> [ApplicationCalibrationSignal] {
    let matched = scored.filter { $0.coverage >= strongCoverageThreshold }
    let stretch = scored.filter { $0.coverage < strongCoverageThreshold }
    guard !scored.isEmpty else { return [] }

    let matchedRate = rate(of: matched)
    let stretchRate = rate(of: stretch)
    let gap = matchedRate - stretchRate
    guard gap >= meaningfulRateGap else { return [] }

    let stretchShare = Double(stretch.count) / Double(scored.count)
    let matchedPercent = Int((matchedRate * 100).rounded())
    let stretchPercent = Int((stretchRate * 100).rounded())

    if stretchShare >= stretchShareThreshold,
      stretch.count >= comparisonMinimumStretch,
      matched.count >= comparisonMinimumMatched {
      let sample = scored.count
      return [
        ApplicationCalibrationSignal(
          id: "reach-gap",
          kind: .reachGap,
          headline: String(localized: CalibrationSignalKind.reachGap.title),
          detail: """
            \(Int((stretchShare * 100).rounded()))% of your applications went to roles \
            where you matched less than \(Int(strongCoverageThreshold * 100))% of the job's \
            language. Those are not landing. The roles you already matched are.
            """,
          evidence: """
            \(matched.count) well-matched application\(matched.count == 1 ? "" : "s") \
            progressed \(matchedPercent)% of the time. \(stretch.count) stretch \
            application\(stretch.count == 1 ? "" : "s") progressed \(stretchPercent)%.
            """,
          confidence: confidence(for: sample),
          sampleSize: sample,
          focus: .targeting,
          applicationIDs: stretch.map(\.application.id)
        )
      ]
    }

    if matched.count >= advantageMinimumPerGroup, stretch.count >= advantageMinimumPerGroup {
      let sample = scored.count
      return [
        ApplicationCalibrationSignal(
          id: "match-advantage",
          kind: .matchAdvantage,
          headline: String(localized: CalibrationSignalKind.matchAdvantage.title),
          detail: """
            Your progress is concentrated in roles whose language your résumé already \
            covers. Keep the spread, and put the careful tailoring where the match is \
            closest.
            """,
          evidence: """
            \(matchedPercent)% of well-matched applications progressed, against \
            \(stretchPercent)% of stretches, across \(sample) analysed applications.
            """,
          confidence: confidence(for: sample),
          sampleSize: sample,
          focus: .preserveStrength,
          applicationIDs: matched.map(\.application.id)
        )
      ]
    }

    return []
  }

  private static func droughtSignal(
    settled: [JobApplication],
    progressed: [JobApplication]
  ) -> ApplicationCalibrationSignal? {
    guard settled.count >= droughtMinimumSettled, progressed.isEmpty else { return nil }
    return ApplicationCalibrationSignal(
      id: "response-drought",
      kind: .responseDrought,
      headline: String(localized: CalibrationSignalKind.responseDrought.title),
      detail: """
        \(settled.count) applications have settled without a single one reaching an \
        interview. Sending more of the same is unlikely to change that. The next useful \
        move is upstream: what the résumé claims, or which roles it is sent to.
        """,
      evidence: """
        \(settled.count) applications either closed or sat for more than \(settlingDays) \
        days. None progressed.
        """,
      confidence: confidence(for: settled.count),
      sampleSize: settled.count,
      focus: .professionalProfile,
      applicationIDs: settled.map(\.id)
    )
  }

  private static func concentrationSignal(
    settled: [JobApplication]
  ) -> ApplicationCalibrationSignal? {
    guard settled.count >= concentrationMinimumSettled else { return nil }
    let grouped = Dictionary(grouping: settled, by: \.sourceLabel)
    guard
      let (name, group) = grouped.max(by: { $0.value.count < $1.value.count }),
      Double(group.count) / Double(settled.count) >= concentrationShareThreshold,
      !group.contains(where: progressed)
    else { return nil }

    return ApplicationCalibrationSignal(
      id: "source-concentration-\(name)",
      kind: .sourceConcentration,
      headline: String(localized: CalibrationSignalKind.sourceConcentration.title),
      detail: """
        Nearly everything you have sent came from \(name), and nothing from it has \
        progressed. A second channel is a cheaper experiment than another rewrite.
        """,
      evidence: """
        \(group.count) of \(settled.count) settled applications came from \(name), with \
        no interviews from that source.
        """,
      confidence: confidence(for: group.count),
      sampleSize: group.count,
      focus: .targeting,
      applicationIDs: group.map(\.id)
    )
  }

  private static func progressSignal(
    settled: [JobApplication],
    progressed: [JobApplication]
  ) -> ApplicationCalibrationSignal? {
    guard settled.count >= progressMinimumSettled, !progressed.isEmpty else { return nil }
    let rate = Double(progressed.count) / Double(settled.count)
    guard rate >= healthyProgressionRate else { return nil }
    return ApplicationCalibrationSignal(
      id: "steady-progress",
      kind: .steadyProgress,
      headline: String(localized: CalibrationSignalKind.steadyProgress.title),
      detail: """
        \(progressed.count) of \(settled.count) settled applications reached an interview \
        or better. That is above the point where the search is worth continuing as it is \
        rather than rebuilt.
        """,
      evidence: "A \(Int((rate * 100).rounded()))% progression rate across \(settled.count) settled applications.",
      confidence: confidence(for: settled.count),
      sampleSize: settled.count,
      focus: .preserveStrength,
      applicationIDs: progressed.map(\.id)
    )
  }

  private static func notEnoughDataSignal(
    settled: [JobApplication],
    scored: [ScoredApplication]
  ) -> ApplicationCalibrationSignal? {
    let detail: String
    if settled.isEmpty {
      detail = """
        Calibration compares applications that have settled — closed, or sent more than \
        \(settlingDays) days ago. None have yet.
        """
    } else if scored.isEmpty {
      detail = """
        \(settled.count) application\(settled.count == 1 ? " has" : "s have") settled, but \
        none carry a job-match analysis. Running the match check on a captured job is what \
        makes the comparison possible.
        """
    } else {
      detail = """
        \(settled.count) application\(settled.count == 1 ? " has" : "s have") settled. A few \
        more, with match analyses, and the comparison becomes worth showing.
        """
    }
    return ApplicationCalibrationSignal(
      id: "not-enough-data",
      kind: .notEnoughData,
      headline: String(localized: CalibrationSignalKind.notEnoughData.title),
      detail: detail,
      evidence: "Nothing here is inferred from other people's data.",
      confidence: .provisional,
      sampleSize: settled.count,
      focus: nil,
      applicationIDs: []
    )
  }

  // MARK: - Shared measures

  private struct ScoredApplication {
    let application: JobApplication
    let coverage: Double
    let progressed: Bool
  }

  /// Whether an application has told us anything yet. A saved-but-unsent role
  /// never has; a closed one always has; a sent one has once it has gone quiet
  /// for long enough that silence is the answer.
  static func isSettled(_ application: JobApplication, now: Date = Date()) -> Bool {
    switch application.status {
    case .saved:
      return false
    case .interview, .offer, .rejected:
      return true
    case .applied:
      let elapsed = now.timeIntervalSince(application.updatedAt)
      return elapsed >= Double(settlingDays) * 24 * 60 * 60
    }
  }

  /// Reached an interview at any point — including applications that were later
  /// rejected, because the interview still happened and the résumé still worked.
  static func progressed(_ application: JobApplication) -> Bool {
    if application.status == .interview || application.status == .offer { return true }
    return application.outcomeReviewList.contains { $0.stage == .interview || $0.stage == .offer }
  }

  /// How much of the job's language the résumé already covered, from the saved
  /// match analysis. Nil when there is no analysis, or too few keywords for the
  /// ratio to mean anything.
  static func matchCoverage(_ application: JobApplication) -> Double? {
    guard let analysis = application.matchAnalysis else { return nil }
    let matched = analysis.matchedKeywords.count
    let total = matched + analysis.missingKeywords.count
    guard total >= minimumKeywordSample else { return nil }
    return Double(matched) / Double(total)
  }

  static func confidence(for sampleSize: Int) -> CalibrationConfidence {
    if sampleSize >= consistentSampleSize { return .consistent }
    if sampleSize >= emergingSampleSize { return .emerging }
    return .provisional
  }

  private static func rate(of scored: [ScoredApplication]) -> Double {
    guard !scored.isEmpty else { return 0 }
    return Double(scored.count { $0.progressed }) / Double(scored.count)
  }

  /// Hardest useful truth first. A drought is blunt, but a reach gap explains it
  /// and says what to do instead, so it leads when both are present.
  private static func priority(_ kind: CalibrationSignalKind) -> Int {
    switch kind {
    case .reachGap: 0
    case .responseDrought: 1
    case .sourceConcentration: 2
    case .matchAdvantage: 3
    case .steadyProgress: 4
    case .notEnoughData: 5
    }
  }
}
