import Foundation

enum JobApplicationStatus: String, CaseIterable, Codable, Identifiable {
  case saved
  case applied
  case interview
  case offer
  case rejected

  var id: String { rawValue }
  /// Spelled out rather than `rawValue.capitalized` — a capitalised raw value is
  /// an English word by accident and can never be translated.
  var title: LocalizedStringResource {
    switch self {
    case .saved: "Saved"
    case .applied: "Applied"
    case .interview: "Interview"
    case .offer: "Offer"
    case .rejected: "Rejected"
    }
  }
  var systemImage: String {
    switch self {
    case .saved: "bookmark.fill"
    case .applied: "paperplane.fill"
    case .interview: "person.2.fill"
    case .offer: "star.fill"
    case .rejected: "xmark.circle.fill"
    }
  }
}

struct JobApplication: Identifiable, Codable, Equatable {
  var id = UUID()
  var company: String
  var role: String
  var jobDescription: String
  var sourceURL: String
  var status: JobApplicationStatus
  var notes: String
  var baseResumeID: UUID
  var tailoredResumeID: UUID?
  var matchAnalysis: AIJobMatchAnalysis?
  var interviewPlan: AIInterviewPlan?
  var interviewAssessment: AIInterviewAssessment? = nil
  var assessmentAttempts: [InterviewAssessmentAttempt]? = nil
  var capturedOpportunity: CapturedJobSnapshot? = nil
  var deadline: Date? = nil
  var activities: [ApplicationActivity]? = nil
  var packet: ApplicationPacket? = nil
  /// Short, user-authored debriefs for meaningful pipeline stages. Optional so
  /// existing local and iCloud archives continue to decode without migration.
  var outcomeReviews: [ApplicationOutcomeReview]? = nil
  var createdAt = Date()
  var updatedAt = Date()
}

extension JobApplication {
  var activityTimeline: [ApplicationActivity] {
    let stored = activities ?? []
    if stored.isEmpty {
      return [ApplicationActivity(kind: .captured, title: "Opportunity saved", detail: [role, company].filter { !$0.isBlank }.joined(separator: " at "), occurredAt: createdAt)]
    }
    return stored.sorted { $0.occurredAt > $1.occurredAt }
  }
}

struct AIInterviewAssessment: Codable, Equatable {
  var title: String
  var focusAreas: [String]
  var questions: [AIInterviewAssessmentQuestion]
}

struct AIInterviewAssessmentQuestion: Codable, Equatable, Identifiable {
  var id: String
  var category: String
  var prompt: String
  var options: [String]
  var correctOptionIndex: Int
  var explanation: String
  var resumeConnection: String
}

struct InterviewAssessmentAttempt: Codable, Equatable, Identifiable {
  var id = UUID()
  var assessmentTitle: String
  var score: Int
  var total: Int
  var completedAt = Date()
  var evaluation: AIAssessmentEvaluation? = nil
}

struct AIAssessmentEvaluation: Codable, Equatable {
  var score: Int
  var total: Int
  var percentage: Int
  var strengths: [String]
  var knowledgeGaps: [String]
  var focusPlan: [String]
  var overallFeedback: String
  var questionFeedback: [AIAssessmentQuestionFeedback]
}

struct AIAssessmentQuestionFeedback: Codable, Equatable, Identifiable {
  var id: String
  var isCorrect: Bool
  var feedback: String
}

enum InterviewFormat: String, CaseIterable, Codable, Identifiable {
  case video
  case phone
  case inPerson
  case panel
  case assessment

  var id: String { rawValue }
  var title: LocalizedStringResource {
    switch self {
    case .video: "Video"
    case .phone: "Phone"
    case .inPerson: "In person"
    case .panel: "Panel"
    case .assessment: "Assessment"
    }
  }
  var systemImage: String {
    switch self {
    case .video: "video.fill"
    case .phone: "phone.fill"
    case .inPerson: "person.fill"
    case .panel: "person.3.fill"
    case .assessment: "doc.text.fill"
    }
  }
}

enum InterviewOutcome: String, CaseIterable, Codable, Identifiable {
  case pending
  case progressed
  case offer
  case unsuccessful
  case withdrew

  var id: String { rawValue }
  var title: LocalizedStringResource {
    switch self {
    case .pending: "Awaiting result"
    case .progressed: "Progressed"
    case .offer: "Offer received"
    case .unsuccessful: "Unsuccessful"
    case .withdrew: "Withdrew"
    }
  }
}

struct InterviewEvent: Identifiable, Codable, Equatable {
  var id = UUID()
  var applicationID: UUID?
  var role: String
  var company: String
  var scheduledAt: Date
  var durationMinutes: Int
  var format: InterviewFormat
  var locationOrLink: String
  var interviewerNames: String
  var reminderEnabled: Bool
  var preparationNotes: String
  var outcome: InterviewOutcome
  var selfRating: Int
  var whatWentWell: String
  var needsImprovement: String
  var followUpNotes: String
  var createdAt = Date()
  var updatedAt = Date()

  var isPast: Bool { scheduledAt < Date() }
}

struct AIInterviewPlan: Codable, Equatable {
  var openingPitch: String
  var questions: [AIInterviewQuestion]
  var questionsToAsk: [String]
  var preparationTips: [String]
  var claimsRequiringConfirmation: [String]
}

struct AIInterviewQuestion: Codable, Equatable, Identifiable {
  var id: String
  var question: String
  var rationale: String
  var evidenceHint: String
}

struct JobDescriptionQuality: Equatable {
  var score: Int
  var blockingIssues: [String]
  var suggestions: [String]
  var isDetailedEnough: Bool { blockingIssues.isEmpty }
}

enum ATSIssueSeverity: String, Codable {
  case pass
  case warning
  case action
}

struct ATSCheckItem: Identifiable, Codable, Equatable {
  var id: String
  var title: String
  var detail: String
  var severity: ATSIssueSeverity
  var section: ResumeSection? = nil
}

struct ATSReadinessReport: Codable, Equatable {
  var items: [ATSCheckItem]
  var matchedKeywords: [String] = []
  var missingKeywords: [String] = []
  var passedCount: Int { items.count { $0.severity == .pass } }
  var actionCount: Int { items.count { $0.severity == .action } }
  var score: Int {
    guard !items.isEmpty else { return 0 }
    let points = items.reduce(0) { result, item in
      result + (item.severity == .pass ? 100 : item.severity == .warning ? 55 : 15)
    }
    return Int((Double(points) / Double(items.count)).rounded())
  }
}

struct ATSKeywordSuggestion: Identifiable, Equatable {
  var keyword: String
  var section: ResumeSection
  var guidance: String
  var id: String { keyword.lowercased() }
}
