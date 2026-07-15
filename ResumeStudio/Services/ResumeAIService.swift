import FirebaseAppCheck
import FirebaseAuth
import Foundation

enum ResumeAIError: LocalizedError, Equatable {
  case notConfigured
  case invalidResponse
  case server(message: String)
  case transport(message: String)
  case offline
  case resumeIncomplete

  var errorDescription: String? {
    switch self {
    case .notConfigured:
      "AI is not configured yet. Add AI_SERVICE_BASE_URL to the app build settings."
    case .invalidResponse:
      "The AI service returned an unreadable response. Please try again."
    case .server(let message), .transport(let message):
      message
    case .offline:
      "You’re offline. Reconnect to the internet and try again."
    case .resumeIncomplete:
      "Complete at least 90% of your résumé before using AI interview preparation."
    }
  }

  /// A network failure that a retry won't fix until the connection returns —
  /// worth its own, calmer treatment than a generic error.
  static func from(_ error: Error) -> ResumeAIError {
    if let aiError = error as? ResumeAIError { return aiError }
    if let urlError = error as? URLError,
      [
        .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
        .cannotFindHost, .dnsLookupFailed, .timedOut, .dataNotAllowed,
      ].contains(urlError.code) {
      return .offline
    }
    return .transport(message: error.localizedDescription)
  }
}

actor ResumeAIService {
  static let shared = ResumeAIService()

  private let session: URLSession
  private let explicitBaseURL: URL?

  init(baseURL: URL? = nil, session: URLSession = .shared) {
    explicitBaseURL = baseURL
    self.session = session
  }

  func importResume(text: String) async throws -> AIImportedResume {
    let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanText.isEmpty else { throw ResumeAIError.invalidResponse }
    return try await request(
      action: .importResume,
      payload: AIResumeImportPayload(resumeText: String(cleanText.prefix(55_000)))
    )
  }

  func improveBullet(_ bullet: String, role: String, company: String) async throws
    -> AITextAlternatives
  {
    return try await request(
      action: .improveBullet,
      payload: ImproveBulletPayload(bullet: bullet, role: role, company: company)
    )
  }

  func writeProfile(for document: ResumeDocument, evidence: [CareerEvidence] = []) async throws -> AITextAlternatives {
    return try await request(
      action: .writeProfile,
      payload: ProfileWithEvidencePayload(
        resume: AIResumeSnapshot(document: document),
        evidence: Self.shareVerifiedEvidence
          ? Array(evidence.filter(\.isVerified).prefix(40)).map(AICareerEvidenceSnapshot.init) : []
      )
    )
  }

  func suggestCompetencies(for document: ResumeDocument, jobDescription: String = "") async throws
    -> AICompetencySuggestions
  {
    try await request(
      action: .suggestCompetencies,
      payload: SkillsPayload(
        resume: AIResumeSnapshot(document: document),
        jobDescription: jobDescription
      )
    )
  }

  func analyzeJob(document: ResumeDocument, jobDescription: String) async throws
    -> AIJobMatchAnalysis
  {
    try await request(
      action: .analyzeJob,
      payload: JobTargetingPayload(
        resume: AIResumeSnapshot(document: document),
        jobDescription: jobDescription
      )
    )
  }

  func tailorResume(document: ResumeDocument, jobDescription: String) async throws
    -> AITailoredResume
  {
    try await request(
      action: .tailorResume,
      payload: JobTargetingPayload(
        resume: AIResumeSnapshot(document: document),
        jobDescription: jobDescription
      )
    )
  }

  func translateResume(
    document: ResumeDocument,
    targetLanguage: String,
    market: ResumeMarket
  ) async throws -> AITranslatedResume {
    try await request(
      action: .translateResume,
      payload: ResumeTranslationPayload(
        resume: AIResumeSnapshot(document: document),
        targetLanguage: String(targetLanguage.prefix(80)),
        market: market.title
      )
    )
  }

  func writeCoverLetter(
    document: ResumeDocument,
    jobDescription: String,
    jobTitle: String,
    company: String,
    recipientName: String
  ) async throws -> AIGeneratedCoverLetter {
    try await request(
      action: .writeCoverLetter,
      payload: CoverLetterAIPayload(
        resume: AIResumeSnapshot(document: document),
        jobDescription: jobDescription,
        jobTitle: jobTitle,
        company: company,
        recipientName: recipientName
      )
    )
  }

  func prepareInterview(
    document: ResumeDocument,
    jobDescription: String,
    role: String,
    company: String
  ) async throws -> AIInterviewPlan {
    guard document.completionPercentage >= 90 else { throw ResumeAIError.resumeIncomplete }
    return try await request(
      action: .interviewPrep,
      payload: InterviewPrepPayload(
        resume: AIResumeSnapshot(document: document),
        jobDescription: jobDescription,
        role: role,
        company: company,
        resumeCompletionPercentage: document.completionPercentage
      )
    )
  }

  func createInterviewAssessment(
    document: ResumeDocument,
    jobDescription: String,
    role: String,
    company: String
  ) async throws -> AIInterviewAssessment {
    guard document.completionPercentage >= 90 else { throw ResumeAIError.resumeIncomplete }
    return try await request(
      action: .interviewAssessment,
      payload: InterviewAssessmentPayload(
        resume: AIResumeSnapshot(document: document),
        jobDescription: jobDescription,
        role: role,
        company: company,
        resumeCompletionPercentage: document.completionPercentage
      )
    )
  }

  func gradeInterviewAssessment(
    document: ResumeDocument,
    assessment: AIInterviewAssessment,
    selectedAnswers: [String: Int]
  ) async throws -> AIAssessmentEvaluation {
    guard document.completionPercentage >= 90 else { throw ResumeAIError.resumeIncomplete }
    let evaluation: AIAssessmentEvaluation = try await request(
      action: .gradeInterviewAssessment,
      payload: InterviewAssessmentGradingPayload(
        resume: AIResumeSnapshot(document: document),
        assessment: assessment,
        selectedAnswers: selectedAnswers,
        resumeCompletionPercentage: document.completionPercentage
      )
    )
    let score = assessment.questions.count {
      selectedAnswers[$0.id] == $0.correctOptionIndex
    }
    let total = assessment.questions.count
    return AIAssessmentEvaluation(
      score: score,
      total: total,
      percentage: total == 0 ? 0 : Int((Double(score) / Double(total) * 100).rounded()),
      strengths: evaluation.strengths,
      knowledgeGaps: evaluation.knowledgeGaps,
      focusPlan: evaluation.focusPlan,
      overallFeedback: evaluation.overallFeedback,
      questionFeedback: evaluation.questionFeedback
    )
  }

  func careerCoach(
    context: CareerCoachContext,
    messages: [CareerCoachMessage]
  ) async throws -> AICareerCoachReply {
    var conversation = Array(messages.suffix(12))
    // The first assistant message is a local, personalised welcome. Keep it on
    // device so even the user's display name is not included in an AI request.
    if conversation.first?.role == .assistant {
      conversation.removeFirst()
    }
    let reply: AICareerCoachReply = try await request(
      action: .careerCoach,
      payload: CareerCoachPayload(
        context: context,
        messages: conversation
      )
    )
    return reply
  }

  func captureJob(content: String, sourceURL: String = "") async throws -> AIJobCapture {
    let clean = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { throw ResumeAIError.invalidResponse }
    return try await request(
      action: .captureJob,
      payload: AIJobCapturePayload(
        content: String(clean.prefix(45_000)),
        sourceURL: String(sourceURL.prefix(1_000))
      )
    )
  }

  func evaluateInterviewAnswer(
    document: ResumeDocument,
    evidence: [CareerEvidence],
    application: JobApplication?,
    question: String,
    transcript: String,
    durationSeconds: Double,
    wordsPerMinute: Int,
    fillerWords: [String]
  ) async throws -> AIVoiceInterviewFeedback {
    try await request(
      action: .evaluateInterviewAnswer,
      payload: AIVoiceInterviewFeedbackPayload(
        resume: AIResumeSnapshot(document: document),
        evidence: Self.shareVerifiedEvidence
          ? Array(evidence.filter(\.isVerified).prefix(40)).map(AICareerEvidenceSnapshot.init) : [],
        role: application?.role ?? "",
        company: application?.company ?? "",
        jobDescription: String((application?.jobDescription ?? "").prefix(7_000)),
        question: String(question.prefix(1_000)),
        transcript: String(transcript.prefix(10_000)),
        durationSeconds: durationSeconds,
        wordsPerMinute: wordsPerMinute,
        fillerWords: Array(fillerWords.prefix(30))
      )
    )
  }

  func createCareerToolkitDraft(
    kind: String,
    document: ResumeDocument,
    evidence: [CareerEvidence],
    application: JobApplication? = nil,
    recipient: String = "",
    market: ResumeMarket = .international,
    request: String = ""
  ) async throws -> AICareerToolkitDraft {
    try await self.request(
      action: .careerToolkit,
      artifactContext: kind,
      payload: AICareerToolkitPayload(
        draftKind: kind,
        resume: AIResumeSnapshot(document: document),
        evidence: Self.shareVerifiedEvidence
          ? Array(evidence.filter(\.isVerified).prefix(50)).map(AICareerEvidenceSnapshot.init) : [],
        role: application?.role ?? "",
        company: application?.company ?? "",
        jobDescription: String((application?.jobDescription ?? "").prefix(7_000)),
        recipient: String(recipient.prefix(220)),
        market: market.title,
        userRequest: String(request.prefix(2_000))
      )
    )
  }

  private func request<Payload: Encodable, Result: Codable>(
    action: ResumeAIAction,
    artifactContext: String? = nil,
    payload: Payload
  ) async throws -> Result {
    guard Self.aiProcessingEnabled else {
      throw ResumeAIError.server(message: "AI processing is paused in Privacy Centre.")
    }
    let knownUsage = await PurchaseManager.shared.currentUsage
    if let knownUsage, knownUsage.creditsRemaining < action.creditCost {
      await PurchaseManager.shared.requestPlans()
      throw ResumeAIError.server(
        message: "This action needs \(action.creditCost) AI credits. Choose Go or Pro for a larger monthly allowance."
      )
    }
    let baseURL = try resolvedBaseURL()
    let endpoint = baseURL.appendingPathComponent("v1/ai")
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = 45
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("ResumeStudio-iOS/1", forHTTPHeaderField: "X-ResumeStudio-Client")
    request.setValue(try await appCheckToken(), forHTTPHeaderField: "X-Firebase-AppCheck")
    if let user = Auth.auth().currentUser,
      let token = try? await user.getIDToken(forcingRefresh: false)
    {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    let entitlement = await PurchaseManager.shared.entitlementProof()
    request.httpBody = try JSONEncoder().encode(
      AIAPIRequest(
        action: action,
        clientID: MonetizationIdentity.installationID,
        entitlement: entitlement,
        payload: payload
      )
    )

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw ResumeAIError.from(error)
    }

    guard let http = response as? HTTPURLResponse else {
      throw ResumeAIError.invalidResponse
    }

    guard (200..<300).contains(http.statusCode) else {
      let errorDecoder = JSONDecoder()
      errorDecoder.dateDecodingStrategy = .iso8601
      let error = try? errorDecoder.decode(AIAPIErrorResponse.self, from: data)
      if let usage = error?.usage { await PurchaseManager.shared.updateUsage(usage) }
      if error?.code == "insufficient_credits" {
        await PurchaseManager.shared.requestPlans()
      }
      throw ResumeAIError.server(
        message: error?.error ?? "AI request failed with status \(http.statusCode)."
      )
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let envelope = try? decoder.decode(AIAPIResponse<Result>.self, from: data) else {
      throw ResumeAIError.invalidResponse
    }
    if let usage = envelope.usage { await PurchaseManager.shared.updateUsage(usage) }
    await MainActor.run {
      AIArtifactStore.shared.record(envelope.result, action: action, context: artifactContext)
      NotificationCenter.default.post(
        name: .aiRequestDidComplete,
        object: nil,
        userInfo: ["action": action.rawValue]
      )
    }
    return envelope.result
  }

  private func appCheckToken() async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
      AppCheck.appCheck().token(forcingRefresh: false) { result, error in
        if let token = result?.token, !token.isBlank {
          continuation.resume(returning: token)
        } else {
          let detail = error?.localizedDescription.nilIfBlank
          continuation.resume(throwing: ResumeAIError.server(
            message: detail.map { "This installation could not be verified: \($0)" }
              ?? "This installation could not be verified. Please relaunch the app and try again."
          ))
        }
      }
    }
  }

  private func resolvedBaseURL() throws -> URL {
    if let explicitBaseURL { return explicitBaseURL }
    if let override = ProcessInfo.processInfo.environment["AI_SERVICE_BASE_URL"],
      let url = URL(string: override), !override.isEmpty
    {
      return url
    }
    guard
      let raw = Bundle.main.object(forInfoDictionaryKey: "AIServiceBaseURL") as? String,
      !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !raw.contains("$("),
      let url = URL(string: raw)
    else {
      throw ResumeAIError.notConfigured
    }
    return url
  }

  private static var aiProcessingEnabled: Bool {
    UserDefaults.standard.object(forKey: CareerPrivacySetting.aiEnabledKey) as? Bool ?? true
  }

  private static var shareVerifiedEvidence: Bool {
    UserDefaults.standard.object(forKey: CareerPrivacySetting.shareVerifiedEvidenceKey) as? Bool ?? true
  }
}

extension Notification.Name {
  static let aiRequestDidComplete = Notification.Name("ResumeStudio.aiRequestDidComplete")
}

private struct AIAPIRequest<Payload: Encodable>: Encodable {
  var action: ResumeAIAction
  var clientID: String
  var entitlement: MonetizationEntitlementProof
  var payload: Payload
}

private struct AIAPIResponse<Result: Decodable>: Decodable {
  var result: Result
  var usage: AIUsageSnapshot?
}

private struct AIAPIErrorResponse: Decodable {
  var error: String
  var code: String?
  var usage: AIUsageSnapshot?
}
