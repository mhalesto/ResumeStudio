import Foundation

enum OutcomeFeedbackSource: String, CaseIterable, Codable, Identifiable {
  case none
  case recruiter
  case interviewer
  case automated
  case selfReflection

  var id: String { rawValue }

  var title: LocalizedStringResource {
    switch self {
    case .none: "No direct feedback"
    case .recruiter: "Recruiter"
    case .interviewer: "Interviewer"
    case .automated: "Automated message"
    case .selfReflection: "My reflection"
    }
  }
}

enum ApplicationOutcomeReason: String, CaseIterable, Codable, Identifiable {
  case strongRoleFit
  case strongEvidence
  case skillsMatch
  case referralOrSource
  case profileUnclear
  case evidenceTooWeak
  case skillsGap
  case experienceGap
  case roleMismatch
  case timingOrCompetition
  case compensationOrLocation
  case noFeedback
  case other

  var id: String { rawValue }

  var title: LocalizedStringResource {
    switch self {
    case .strongRoleFit: "Strong role fit"
    case .strongEvidence: "Evidence landed well"
    case .skillsMatch: "Skills matched"
    case .referralOrSource: "Referral or source helped"
    case .profileUnclear: "Positioning was unclear"
    case .evidenceTooWeak: "Evidence needed more proof"
    case .skillsGap: "A skills gap mattered"
    case .experienceGap: "An experience gap mattered"
    case .roleMismatch: "The role was not the right match"
    case .timingOrCompetition: "Timing or competition"
    case .compensationOrLocation: "Location or compensation"
    case .noFeedback: "No useful feedback"
    case .other: "Something else"
    }
  }

  var systemImage: String {
    switch self {
    case .strongRoleFit, .strongEvidence, .skillsMatch, .referralOrSource:
      "checkmark.seal.fill"
    case .profileUnclear, .evidenceTooWeak, .skillsGap, .experienceGap, .roleMismatch:
      "arrow.up.circle.fill"
    case .timingOrCompetition, .compensationOrLocation, .noFeedback, .other:
      "ellipsis.circle.fill"
    }
  }

  var learningFocus: OutcomeLearningFocus {
    switch self {
    case .profileUnclear, .roleMismatch: .professionalProfile
    case .evidenceTooWeak, .experienceGap: .experienceEvidence
    case .skillsGap: .competencies
    case .strongRoleFit, .strongEvidence, .skillsMatch: .preserveStrength
    case .referralOrSource: .targeting
    case .timingOrCompetition, .compensationOrLocation, .noFeedback, .other: .targeting
    }
  }

  var isPositiveSignal: Bool {
    [.strongRoleFit, .strongEvidence, .skillsMatch, .referralOrSource].contains(self)
  }
}

struct ApplicationOutcomeReview: Identifiable, Codable, Equatable {
  var id = UUID()
  var stage: JobApplicationStatus
  var reason: ApplicationOutcomeReason
  var feedbackSource: OutcomeFeedbackSource
  var feedback: String
  var whatWorked: String
  var nextChange: String
  var followUpAt: Date?
  var resumeID: UUID
  var packetID: UUID?
  var createdAt = Date()
  var updatedAt = Date()
}

extension JobApplication {
  var outcomeReviewList: [ApplicationOutcomeReview] { outcomeReviews ?? [] }

  var canReviewCurrentOutcome: Bool {
    [.interview, .offer, .rejected].contains(status)
  }

  var currentOutcomeReview: ApplicationOutcomeReview? {
    outcomeReviewList.first { $0.stage == status }
  }

  var needsCurrentOutcomeReview: Bool {
    canReviewCurrentOutcome && currentOutcomeReview == nil
  }

  var resumeUsedForOutcome: UUID {
    packet?.resumeID ?? tailoredResumeID ?? baseResumeID
  }
}

enum OutcomeLearningFocus: String, Codable, Equatable {
  case collectOutcome
  case professionalProfile
  case experienceEvidence
  case competencies
  case targeting
  case preserveStrength

  var title: LocalizedStringResource {
    switch self {
    case .collectOutcome: "Review an outcome"
    case .professionalProfile: "Clarify your positioning"
    case .experienceEvidence: "Strengthen your evidence"
    case .competencies: "Surface relevant skills"
    case .targeting: "Refine your targeting"
    case .preserveStrength: "Reuse what is working"
    }
  }

  var systemImage: String {
    switch self {
    case .collectOutcome: "checklist"
    case .professionalProfile: "person.text.rectangle"
    case .experienceEvidence: "chart.bar.doc.horizontal"
    case .competencies: "square.grid.2x2.fill"
    case .targeting: "scope"
    case .preserveStrength: "checkmark.seal.fill"
    }
  }

  var editorSection: ResumeSection? {
    switch self {
    case .professionalProfile: .profile
    case .experienceEvidence: .experience
    case .competencies: .competencies
    default: nil
    }
  }

  var supportsDrafting: Bool { editorSection != nil }
}

struct OutcomeLearningRecommendation: Identifiable, Equatable {
  var id: String
  var title: String
  var detail: String
  var evidence: String
  var actionTitle: String
  var focus: OutcomeLearningFocus
  var applicationID: UUID?
  var resumeID: UUID?
  var sampleSize: Int
}

struct OutcomeLearningSummary: Equatable {
  var eligibleCount: Int
  var reviewedCount: Int
  var pendingApplicationIDs: [UUID]
  var recommendation: OutcomeLearningRecommendation
}
