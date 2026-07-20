import FirebaseAppCheck
import FirebaseCore
import Foundation

/// The on-device half of outcome benchmarks: works out which cohort this user
/// belongs to, measures their own history, and turns a released cohort into a
/// comparison worth reading.
///
/// Cohort membership is derived from the résumé the user already wrote — no
/// extra questions, and no free text ever leaves the device, because the cohort
/// is three enum cases.
enum BenchmarkAnalysis {
  /// Below this much personal history, a comparison says more about noise than
  /// about the user.
  static let minimumLocalHistory = 5
  /// How far from the cohort rate counts as genuinely ahead or behind, in
  /// percentage points. Anything inside this is reported as in line.
  static let meaningfulGapPoints = 5

  // MARK: - Cohort

  /// Ordered most specific first: "product manager" must not be caught by the
  /// generic manager wording that routes to operations.
  private static let familyKeywords: [(BenchmarkRoleFamily, [String])] = [
    (.product, ["product manager", "product owner", "product lead", "product"]),
    (.peopleOperations, [
      "people operations", "human resources", "recruit", "talent acquisition",
      "talent", "people partner", "hr ", "learning and development", "people",
    ]),
    (.dataAnalytics, [
      "data scientist", "data analyst", "data engineer", "analytics", "machine learning",
      "business intelligence", "statistician", "data",
    ]),
    (.engineering, [
      "software", "engineer", "developer", "programmer", "backend", "front end",
      "frontend", "full stack", "fullstack", "devops", "architect", "ios ", "android",
    ]),
    (.design, ["designer", "design", "user experience", "user interface", "creative", "graphic"]),
    (.marketing, [
      "marketing", "growth", "content", "brand", "communications", "social media", "seo",
    ]),
    (.sales, [
      "sales", "account executive", "business development", "new business",
    ]),
    (.customerSuccess, [
      "customer success", "customer support", "account manager", "client services",
      "helpdesk", "service desk",
    ]),
    (.financeAccounting, [
      "accountant", "accounting", "finance", "bookkeeper", "auditor", "audit",
      "treasury", "financial", "tax ",
    ]),
    (.legal, ["lawyer", "attorney", "paralegal", "legal", "counsel", "compliance"]),
    (.healthcare, [
      "nurse", "doctor", "clinical", "medical", "pharmac", "therapist", "radiograph",
      "caregiver", "healthcare",
    ]),
    (.education, [
      "teacher", "lecturer", "tutor", "education", "academic", "principal", "curriculum",
    ]),
    (.tradesTechnical, [
      "electrician", "plumber", "technician", "mechanic", "artisan", "welder", "fitter",
      "millwright", "boilermaker",
    ]),
    (.operationsLogistics, [
      "operations", "logistics", "supply chain", "procurement", "warehouse", "fleet",
      "project manager", "manager",
    ]),
  ]

  static func roleFamily(for text: String) -> BenchmarkRoleFamily {
    let lower = text.lowercased()
    for (family, keywords) in familyKeywords where keywords.contains(where: lower.contains) {
      return family
    }
    return .other
  }

  static func seniority(for text: String) -> BenchmarkSeniority {
    let lower = text.lowercased()
    let lead = ["head of", "director", "chief", "vice president", "vp ", "principal", "lead"]
    let senior = ["senior", "snr", "sr.", "sr "]
    let entry = [
      "junior", "jnr", "graduate", "intern", "trainee", "entry level", "apprentice", "assistant",
    ]
    if lead.contains(where: lower.contains) { return .lead }
    if senior.contains(where: lower.contains) { return .senior }
    if entry.contains(where: lower.contains) { return .entry }
    return .mid
  }

  /// The cohort is read from the headline the user already wrote, falling back
  /// to their most recent role when the headline says nothing useful.
  static func cohort(document: ResumeDocument, market: ResumeMarket) -> BenchmarkCohort {
    let headline = document.personal.headline
    let recentRole = document.experience.first?.role ?? ""
    let source = [headline, recentRole].filter { !$0.isBlank }.joined(separator: " ")
    return BenchmarkCohort(
      roleFamily: roleFamily(for: source),
      market: market,
      seniority: seniority(for: source)
    )
  }

  // MARK: - Local history

  /// Uses the same definitions of settled and progressed as the Reality Check,
  /// so the two features can never report different numbers for one history.
  static func localStats(
    applications: [JobApplication],
    now: Date = Date()
  ) -> (settled: Int, progressed: Int, medianDaysToProgress: Int?) {
    let settled = applications.filter { ApplicationCalibrationService.isSettled($0, now: now) }
    let progressed = settled.filter { ApplicationCalibrationService.progressed($0) }
    let durations = progressed
      .map { $0.updatedAt.timeIntervalSince($0.createdAt) / 86_400 }
      .filter { $0 >= 0 }
      .sorted()
    return (settled.count, progressed.count, median(durations))
  }

  static func contribution(
    cohort: BenchmarkCohort,
    applications: [JobApplication],
    now: Date = Date()
  ) -> BenchmarkContribution? {
    let stats = localStats(applications: applications, now: now)
    guard stats.settled >= 1 else { return nil }
    return BenchmarkContribution(
      cohort: cohort,
      settled: stats.settled,
      progressed: stats.progressed,
      medianDaysToProgress: stats.medianDaysToProgress
    )
  }

  private static func median(_ values: [Double]) -> Int? {
    guard !values.isEmpty else { return nil }
    let middle = values.count / 2
    let value = values.count.isMultiple(of: 2)
      ? (values[middle - 1] + values[middle]) / 2
      : values[middle]
    return Int(value.rounded())
  }

  // MARK: - Comparison

  static func compare(
    cohort: BenchmarkCohort,
    snapshot: BenchmarkSnapshot,
    applications: [JobApplication],
    now: Date = Date()
  ) -> BenchmarkComparison {
    let stats = localStats(applications: applications, now: now)
    let localPercent: Int? = stats.settled > 0
      ? Int((Double(stats.progressed) / Double(stats.settled) * 100).rounded())
      : nil

    guard snapshot.released, let cohortPercent = snapshot.progressionPercent else {
      return BenchmarkComparison(
        cohort: cohort,
        snapshot: snapshot,
        localSettled: stats.settled,
        localProgressed: stats.progressed,
        localProgressionPercent: localPercent,
        verdict: .unknown,
        headline: "This cohort is still too small to publish",
        detail: """
          Benchmarks appear once enough people in \(cohort.title) have contributed \
          outcomes. Until then there is no honest number to show you, so there is none.
          """
      )
    }

    guard stats.settled >= minimumLocalHistory, let localPercent else {
      return BenchmarkComparison(
        cohort: cohort,
        snapshot: snapshot,
        localSettled: stats.settled,
        localProgressed: stats.progressed,
        localProgressionPercent: localPercent,
        verdict: .unknown,
        headline: "Your cohort progresses \(cohortPercent)% of the time",
        detail: """
          Across \(snapshot.contributors) people in \(cohort.title). You need at least \
          \(minimumLocalHistory) settled applications of your own before comparing \
          means anything — you have \(stats.settled).
          """
      )
    }

    let gap = localPercent - cohortPercent
    let verdict: BenchmarkVerdict =
      gap >= meaningfulGapPoints ? .ahead : gap <= -meaningfulGapPoints ? .behind : .inLine

    let detail: String
    switch verdict {
    case .behind:
      detail = """
        You are progressing on \(localPercent)% of settled applications, against \
        \(cohortPercent)% across \(snapshot.contributors) people in \(cohort.title). \
        That gap is the part worth working on, and it is more likely to be about \
        targeting or evidence than about volume.
        """
    case .ahead:
      detail = """
        You are progressing on \(localPercent)% of settled applications, against \
        \(cohortPercent)% across \(snapshot.contributors) people in \(cohort.title). \
        Whatever you are currently doing is worth keeping rather than rebuilding.
        """
    case .inLine, .unknown:
      detail = """
        You are progressing on \(localPercent)% of settled applications, and your cohort \
        on \(cohortPercent)%, across \(snapshot.contributors) people. A difference this \
        small is not a signal.
        """
    }

    return BenchmarkComparison(
      cohort: cohort,
      snapshot: snapshot,
      localSettled: stats.settled,
      localProgressed: stats.progressed,
      localProgressionPercent: localPercent,
      verdict: verdict,
      headline: String(localized: verdict.title),
      detail: detail
    )
  }
}

/// The hosted benchmark API. One call: contribute this installation's counts for
/// its cohort, and receive that cohort's aggregate if it is large enough to
/// publish. Contributing is what makes the benchmark exist, so there is no
/// read-only route.
struct BenchmarkService {
  private struct Payload: Encodable {
    var clientID: String
    var cohort: BenchmarkCohort
    var settled: Int
    var progressed: Int
    var medianDaysToProgress: Int?
  }

  func contribute(_ contribution: BenchmarkContribution) async throws -> BenchmarkSnapshot {
    let payload = Payload(
      clientID: MonetizationIdentity.installationID,
      cohort: contribution.cohort,
      settled: contribution.settled,
      progressed: contribution.progressed,
      medianDaysToProgress: contribution.medianDaysToProgress
    )
    let baseURL = try SmartLinkService.resolvedBaseURL()
    var request = URLRequest(url: baseURL.appendingPathComponent("v1/benchmarks"))
    request.httpMethod = "POST"
    request.timeoutInterval = 30
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(try await appCheckToken(), forHTTPHeaderField: "X-Firebase-AppCheck")
    request.httpBody = try JSONEncoder().encode(payload)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw ResumeAIError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else {
      throw ResumeAIError.server(message: "Benchmarks are unavailable right now.")
    }
    guard let snapshot = try? JSONDecoder().decode(BenchmarkSnapshot.self, from: data) else {
      throw ResumeAIError.invalidResponse
    }
    return snapshot
  }

  private func appCheckToken() async throws -> String {
    if ProcessInfo.processInfo.environment["AI_SERVICE_BASE_URL"] != nil {
      return "emulator-bypass"
    }
    guard FirebaseApp.app() != nil else {
      throw ResumeAIError.server(message: "Still connecting. Try again in a moment.")
    }
    return try await withCheckedThrowingContinuation { continuation in
      AppCheck.appCheck().token(forcingRefresh: false) { result, error in
        if let token = result?.token, !token.isBlank {
          continuation.resume(returning: token)
        } else {
          _ = error
          continuation.resume(
            throwing: ResumeAIError.server(message: "Couldn't verify this device just now."))
        }
      }
    }
  }
}
