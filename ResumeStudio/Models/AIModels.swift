import Foundation

/// Resolves a display label to English for AI request payloads. The prompts are
/// written in English, so a translated app must not quietly change what the
/// model is asked — only what the user is shown.
func aiPayloadLabel(_ resource: LocalizedStringResource) -> String {
  var pinned = resource
  pinned.locale = Locale(identifier: "en")
  return String(localized: pinned)
}

enum ResumeAIAction: String, Codable {
  case importResume
  case improveBullet
  case writeProfile
  case suggestCompetencies
  case analyzeJob
  case tailorResume
  case writeCoverLetter
  case interviewPrep
  case interviewAssessment
  case gradeInterviewAssessment
  case careerCoach
  case captureJob
  case evaluateInterviewAnswer
  case careerToolkit
  case translateResume
  case outcomeLearning
  case negotiationPractice
}

struct AIResumeImportPayload: Codable {
  var resumeText: String
  var sourceImageCount: Int? = nil
}

struct AIImportedResume: Codable, Equatable {
  var personal: AIImportedPersonalDetails
  var professionalProfile: String
  var competencies: [String]
  var experience: [AIImportedExperience]
  var education: [AIImportedEducation]
  var references: [AIImportedReference]
  var additionalSections: [AIImportedAdditionalSection]
  var warnings: [String]

  var document: ResumeDocument {
    var result = ResumeDocument.blank
    result.personal = PersonalDetails(
      fullName: personal.fullName,
      headline: personal.headline,
      phone: personal.phone,
      email: personal.email
    )
    result.professionalProfile = professionalProfile
    result.competencies = competencies.filter { !$0.isBlank }
    result.experience = experience.compactMap { entry in
      guard !entry.role.isBlank || !entry.company.isBlank else { return nil }
      return ExperienceEntry(
        role: entry.role,
        company: entry.company,
        period: entry.period,
        highlights: entry.highlights.filter { !$0.isBlank }
      )
    }
    result.education = education.compactMap { entry in
      guard !entry.qualification.isBlank || !entry.institution.isBlank else { return nil }
      return EducationEntry(
        qualification: entry.qualification,
        institution: entry.institution,
        period: entry.period,
        details: entry.details
      )
    }
    result.references = references.compactMap { entry in
      guard !entry.name.isBlank else { return nil }
      return ReferenceEntry(
        name: entry.name,
        company: entry.company,
        phone: entry.phone,
        email: entry.email
      )
    }
    result.additionalSections = additionalSections.compactMap { section in
      let title = section.title.trimmingCharacters(in: .whitespacesAndNewlines)
      let items = section.items.filter { !$0.isBlank }
      guard !title.isEmpty, !items.isEmpty,
        !title.localizedCaseInsensitiveContains("imported content")
      else { return nil }
      return ResumeAdditionalSection(title: title, items: items)
    }
    return result
  }
}

struct AIImportedPersonalDetails: Codable, Equatable {
  var fullName: String
  var headline: String
  var phone: String
  var email: String
}

struct AIImportedExperience: Codable, Equatable {
  var role: String
  var company: String
  var period: String
  var highlights: [String]
}

struct AIImportedEducation: Codable, Equatable {
  var qualification: String
  var institution: String
  var period: String
  var details: String
}

struct AIImportedReference: Codable, Equatable {
  var name: String
  var company: String
  var phone: String
  var email: String
}

struct AIImportedAdditionalSection: Codable, Equatable {
  var title: String
  var items: [String]
}

/// A deliberately redacted view of a resume. Contact details, references and
/// the profile photo never need to leave the device for writing assistance.
struct AIResumeSnapshot: Codable, Equatable {
  var headline: String
  var professionalProfile: String
  var competencies: [String]
  var experience: [AIExperienceSnapshot]
  var education: [AIEducationSnapshot]
  var additionalSections: [AIAdditionalSectionSnapshot]

  init(document: ResumeDocument) {
    headline = document.personal.headline
    professionalProfile = document.professionalProfile
    competencies = document.competencies.filter { !$0.isBlank }
    experience = document.experience.map(AIExperienceSnapshot.init)
    education = document.education.map(AIEducationSnapshot.init)
    additionalSections = document.additionalSections.compactMap(AIAdditionalSectionSnapshot.init)
  }
}

struct AIOutcomeLearningSignal: Codable, Equatable {
  var stage: String
  var reason: String
  var feedbackSource: String
  var feedback: String
  var whatWorked: String
  var nextChange: String
}

struct AIOutcomeLearningPayload: Codable, Equatable {
  var resume: AIResumeSnapshot
  var focus: String
  var recommendation: String
  var signals: [AIOutcomeLearningSignal]
}

struct AIOutcomeLearningDraft: Codable, Equatable {
  var title: String
  var rationale: String
  var proposedProfile: String
  var proposedCompetencies: [String]
  var experienceEntryID: String
  var originalBullet: String
  var proposedBullet: String
  var coachingSteps: [String]
  var claimsRequiringConfirmation: [String]

  var hasProfileChange: Bool { !proposedProfile.isBlank }
  var hasCompetencyChanges: Bool { !proposedCompetencies.isEmpty }
  var hasExperienceChange: Bool {
    !experienceEntryID.isBlank && !originalBullet.isBlank && !proposedBullet.isBlank
  }
  var hasResumeChanges: Bool { hasProfileChange || hasCompetencyChanges || hasExperienceChange }
}

struct AIAdditionalSectionSnapshot: Codable, Equatable {
  var title: String
  var items: [String]

  init?(section: ResumeAdditionalSection) {
    let cleanTitle = section.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanItems = section.items.filter { !$0.isBlank }
    guard !cleanTitle.isEmpty || !cleanItems.isEmpty else { return nil }
    title = cleanTitle
    items = cleanItems
  }
}

struct AIExperienceSnapshot: Codable, Equatable {
  var id: String
  var role: String
  var company: String
  var period: String
  var highlights: [String]

  init(entry: ExperienceEntry) {
    id = entry.id.uuidString
    role = entry.role
    company = entry.company
    period = entry.period
    highlights = entry.highlights.filter { !$0.isBlank }
  }
}

struct AIEducationSnapshot: Codable, Equatable {
  var qualification: String
  var institution: String
  var period: String
  var details: String

  init(entry: EducationEntry) {
    qualification = entry.qualification
    institution = entry.institution
    period = entry.period
    details = entry.details
  }
}

struct ImproveBulletPayload: Codable {
  var bullet: String
  var role: String
  var company: String
}

struct ResumePayload: Codable {
  var resume: AIResumeSnapshot
}

struct ProfileWithEvidencePayload: Codable {
  var resume: AIResumeSnapshot
  var evidence: [AICareerEvidenceSnapshot]
}

struct SkillsPayload: Codable {
  var resume: AIResumeSnapshot
  var jobDescription: String
}

struct JobTargetingPayload: Codable {
  var resume: AIResumeSnapshot
  var jobDescription: String
}

struct CoverLetterAIPayload: Codable {
  var resume: AIResumeSnapshot
  var jobDescription: String
  var jobTitle: String
  var company: String
  var recipientName: String
}

struct InterviewPrepPayload: Codable {
  var resume: AIResumeSnapshot
  var jobDescription: String
  var role: String
  var company: String
  var resumeCompletionPercentage: Int
}

struct InterviewAssessmentPayload: Codable {
  var resume: AIResumeSnapshot
  var jobDescription: String
  var role: String
  var company: String
  var resumeCompletionPercentage: Int
}

struct InterviewAssessmentGradingPayload: Codable {
  var resume: AIResumeSnapshot
  var assessment: AIInterviewAssessment
  var selectedAnswers: [String: Int]
  var resumeCompletionPercentage: Int
}

enum CareerCoachMessageRole: String, Codable, Equatable {
  case user
  case assistant
}

struct CareerCoachMessage: Identifiable, Codable, Equatable {
  var id = UUID()
  var role: CareerCoachMessageRole
  var content: String
  var createdAt = Date()
}

struct CareerCoachContext: Codable, Equatable {
  var resumeTitle: String
  var resumeCompletionPercentage: Int
  var resume: AIResumeSnapshot
  var applications: [CareerCoachApplicationSnapshot]
  var interviews: [CareerCoachInterviewSnapshot]
  var assessmentHistory: [CareerCoachAssessmentSnapshot]
  var coverLetter: CareerCoachCoverLetterSnapshot?

  init(
    resumeTitle: String,
    document: ResumeDocument,
    applications: [JobApplication],
    interviews: [InterviewEvent],
    coverLetter: CoverLetterDocument
  ) {
    self.resumeTitle = resumeTitle.careerCoachLimited(to: 120)
    resumeCompletionPercentage = document.completionPercentage
    resume = AIResumeSnapshot(document: document)
    self.applications = Array(applications.prefix(12)).map(CareerCoachApplicationSnapshot.init)
    self.interviews = Array(interviews.sorted { $0.scheduledAt > $1.scheduledAt }.prefix(12))
      .map(CareerCoachInterviewSnapshot.init)
    assessmentHistory = Array(
      applications.flatMap { application in
        (application.assessmentAttempts ?? []).map {
          CareerCoachAssessmentSnapshot(application: application, attempt: $0)
        }
      }.sorted { $0.completedAt > $1.completedAt }.prefix(12)
    )

    let hasCoverLetterContext = !coverLetter.jobTitle.isBlank || !coverLetter.companyName.isBlank
      || coverLetter.bodyParagraphs.contains { !$0.isBlank }
    self.coverLetter = hasCoverLetterContext
      ? CareerCoachCoverLetterSnapshot(document: coverLetter) : nil
  }
}

struct CareerCoachApplicationSnapshot: Codable, Equatable {
  var role: String
  var company: String
  var status: String
  var jobDescription: String
  var notes: String
  var matchSummary: String
  var missingKeywords: [String]

  init(application: JobApplication) {
    role = application.role.careerCoachLimited(to: 140)
    company = application.company.careerCoachLimited(to: 140)
    status = aiPayloadLabel(application.status.title)
    jobDescription = application.jobDescription.careerCoachLimited(to: 3_500)
    notes = application.notes.careerCoachLimited(to: 1_200)
    matchSummary = (application.matchAnalysis?.summary ?? "").careerCoachLimited(to: 800)
    missingKeywords = Array((application.matchAnalysis?.missingKeywords ?? []).prefix(20))
  }
}

struct CareerCoachInterviewSnapshot: Codable, Equatable {
  var role: String
  var company: String
  var scheduledAt: String
  var format: String
  var outcome: String
  var selfRating: Int
  var preparationNotes: String
  var whatWentWell: String
  var needsImprovement: String
  var followUpNotes: String

  init(interview: InterviewEvent) {
    role = interview.role.careerCoachLimited(to: 140)
    company = interview.company.careerCoachLimited(to: 140)
    scheduledAt = interview.scheduledAt.ISO8601Format()
    // Machine-facing, not UI: these land in an AI request whose prompts are
    // written in English. Pinned to English so a translated app doesn't quietly
    // change what the model is asked.
    format = aiPayloadLabel(interview.format.title)
    outcome = aiPayloadLabel(interview.outcome.title)
    selfRating = interview.selfRating
    preparationNotes = interview.preparationNotes.careerCoachLimited(to: 1_200)
    whatWentWell = interview.whatWentWell.careerCoachLimited(to: 1_200)
    needsImprovement = interview.needsImprovement.careerCoachLimited(to: 1_200)
    followUpNotes = interview.followUpNotes.careerCoachLimited(to: 1_200)
  }
}

struct CareerCoachAssessmentSnapshot: Codable, Equatable {
  var role: String
  var company: String
  var title: String
  var score: Int
  var total: Int
  var completedAt: Date
  var knowledgeGaps: [String]
  var focusPlan: [String]

  init(application: JobApplication, attempt: InterviewAssessmentAttempt) {
    role = application.role.careerCoachLimited(to: 140)
    company = application.company.careerCoachLimited(to: 140)
    title = attempt.assessmentTitle.careerCoachLimited(to: 180)
    score = attempt.score
    total = attempt.total
    completedAt = attempt.completedAt
    knowledgeGaps = Array((attempt.evaluation?.knowledgeGaps ?? []).prefix(12))
    focusPlan = Array((attempt.evaluation?.focusPlan ?? []).prefix(12))
  }
}

struct CareerCoachCoverLetterSnapshot: Codable, Equatable {
  var jobTitle: String
  var company: String
  var subject: String
  var bodyParagraphs: [String]
  var jobDescription: String

  init(document: CoverLetterDocument) {
    jobTitle = document.jobTitle.careerCoachLimited(to: 140)
    company = document.companyName.careerCoachLimited(to: 140)
    subject = document.subject.careerCoachLimited(to: 220)
    bodyParagraphs = Array(document.bodyParagraphs.filter { !$0.isBlank }.prefix(5))
      .map { $0.careerCoachLimited(to: 1_500) }
    jobDescription = document.jobDescription.careerCoachLimited(to: 3_500)
  }
}

struct CareerCoachPayload: Codable {
  var context: CareerCoachContext
  var messages: [CareerCoachMessage]
}

struct AIJobCapturePayload: Codable {
  var content: String
  var sourceURL: String
}

struct AICareerEvidenceSnapshot: Codable, Equatable {
  var kind: String
  var title: String
  var detail: String
  var source: String
  var tags: [String]

  init(_ evidence: CareerEvidence) {
    kind = aiPayloadLabel(evidence.kind.title)
    title = evidence.title.careerAILimited(to: 180)
    detail = evidence.detail.careerAILimited(to: 1_200)
    source = evidence.source.careerAILimited(to: 220)
    tags = Array(evidence.tags.prefix(12))
  }
}

struct AIVoiceInterviewFeedbackPayload: Codable {
  var resume: AIResumeSnapshot
  var evidence: [AICareerEvidenceSnapshot]
  var role: String
  var company: String
  var jobDescription: String
  var question: String
  var transcript: String
  var durationSeconds: Double
  var wordsPerMinute: Int
  var fillerWords: [String]
}

struct AICareerToolkitPayload: Codable {
  var draftKind: String
  var resume: AIResumeSnapshot
  var evidence: [AICareerEvidenceSnapshot]
  var role: String
  var company: String
  var jobDescription: String
  var recipient: String
  var market: String
  var userRequest: String
}

/// One line of the rehearsal as the backend sees it: only the two speaking
/// parts travel — coach nudges stay on the device.
struct AINegotiationWireMessage: Codable, Equatable {
  var speaker: String
  var content: String
}

struct AINegotiationPracticePayload: Codable {
  var stage: String
  var persona: String
  var difficulty: String
  var goal: String
  var offerSummary: String
  var role: String
  var company: String
  var resume: AIResumeSnapshot
  var evidence: [AICareerEvidenceSnapshot]
  var messages: [AINegotiationWireMessage]
}

struct AICareerCoachReply: Codable, Equatable {
  var reply: String
  var suggestedPrompts: [String]
}

private extension String {
  func careerCoachLimited(to limit: Int) -> String {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > limit else { return trimmed }
    return String(trimmed.prefix(limit)) + "…"
  }
}

private extension String {
  func careerAILimited(to limit: Int) -> String {
    let clean = trimmingCharacters(in: .whitespacesAndNewlines)
    return clean.count <= limit ? clean : String(clean.prefix(limit)) + "…"
  }
}

struct AITextAlternatives: Codable, Equatable {
  var alternatives: [String]
  var claimsRequiringConfirmation: [String]
  var evidenceSources: [String]? = nil
  var sentenceSources: [AISentenceSource]? = nil
}

struct AISentenceSource: Codable, Equatable, Identifiable {
  var sentence: String
  var source: String
  var id: String { sentence + source }
}

struct AICompetencySuggestions: Codable, Equatable {
  var suggestions: [String]
  var rationale: String
}

struct AIJobMatchAnalysis: Codable, Equatable {
  var summary: String
  var matchedKeywords: [String]
  var missingKeywords: [String]
  var recommendations: [String]
  var claimsRequiringConfirmation: [String]
}

struct AITailoredResume: Codable, Equatable {
  var headline: String
  var professionalProfile: String
  var competencies: [String]
  var experience: [AITailoredExperience]
  var claimsRequiringConfirmation: [String]
}

struct AITailoredExperience: Codable, Equatable, Identifiable {
  var id: String
  var highlights: [String]
}

struct AIGeneratedCoverLetter: Codable, Equatable {
  var subject: String
  var greeting: String
  var bodyParagraphs: [String]
  var closing: String
  var claimsRequiringConfirmation: [String]
}
