import Foundation

enum CareerEvidenceKind: String, CaseIterable, Codable, Identifiable {
  case achievement
  case responsibility
  case project
  case skill
  case qualification
  case award
  case testimonial

  var id: String { rawValue }

  var title: LocalizedStringResource {
    switch self {
    case .achievement: "Achievement"
    case .responsibility: "Responsibility"
    case .project: "Project"
    case .skill: "Skill"
    case .qualification: "Qualification"
    case .award: "Award"
    case .testimonial: "Testimonial"
    }
  }

  var systemImage: String {
    switch self {
    case .achievement: "trophy.fill"
    case .responsibility: "briefcase.fill"
    case .project: "shippingbox.fill"
    case .skill: "bolt.fill"
    case .qualification: "graduationcap.fill"
    case .award: "medal.fill"
    case .testimonial: "quote.bubble.fill"
    }
  }
}

struct CareerEvidence: Identifiable, Codable, Equatable {
  var id = UUID()
  var kind: CareerEvidenceKind
  var title: String
  var detail: String
  var source: String
  var sourceResumeID: UUID?
  var tags: [String]
  var isVerified: Bool
  var createdAt = Date()
  var updatedAt = Date()
  var sourceURL: String? = nil
  var sourceFileName: String? = nil
}

enum CareerContactKind: String, CaseIterable, Codable, Identifiable {
  case recruiter
  case hiringManager
  case referral
  case mentor
  case colleague

  var id: String { rawValue }
  var title: LocalizedStringResource {
    switch self {
    case .recruiter: "Recruiter"
    case .hiringManager: "Hiring manager"
    case .referral: "Referral"
    case .mentor: "Mentor"
    case .colleague: "Colleague"
    }
  }
}

struct CareerContact: Identifiable, Codable, Equatable {
  var id = UUID()
  var name: String
  var role: String
  var company: String
  var email: String
  var linkedInURL: String
  var kind: CareerContactKind
  var applicationID: UUID?
  var notes: String
  var lastContactedAt: Date?
  var followUpAt: Date?
  var createdAt = Date()
  var interactions: [ContactInteraction]? = nil
  var relationshipStrength: Int? = nil
}

enum NetworkingMessageKind: String, CaseIterable, Codable, Identifiable {
  case introduction
  case referralRequest
  case applicationFollowUp
  case thankYou
  case reconnect

  var id: String { rawValue }
  var title: LocalizedStringResource {
    switch self {
    case .introduction: "Recruiter introduction"
    case .referralRequest: "Referral request"
    case .applicationFollowUp: "Application follow-up"
    case .thankYou: "Interview thank-you"
    case .reconnect: "Reconnect"
    }
  }
}

struct NetworkingDraft: Identifiable, Codable, Equatable {
  var id = UUID()
  var kind: NetworkingMessageKind
  var contactID: UUID?
  var applicationID: UUID?
  var subject: String
  var body: String
  var claimsRequiringConfirmation: [String]
  var createdAt = Date()
  var sentAt: Date? = nil
}

struct JobOffer: Identifiable, Codable, Equatable {
  var id = UUID()
  var applicationID: UUID?
  var company: String
  var role: String
  var currencyCode: String
  var baseSalary: Double
  var bonus: Double
  var equitySummary: String
  var benefits: String
  var workStyle: String
  var commuteMinutes: Int
  var growthRating: Int
  var cultureRating: Int
  var notes: String
  var deadline: Date?
  var negotiationDraft: String
  var createdAt = Date()
  var signingBonus: Double? = nil
  var employerRetirementAnnual: Double? = nil
  var medicalAnnual: Double? = nil
  var equityAnnualValue: Double? = nil
  var otherAnnualValue: Double? = nil
  var commuteAnnualCost: Double? = nil
  var remoteSavingsAnnual: Double? = nil
  var leaveDays: Int? = nil

  var firstYearCash: Double { baseSalary + bonus + (signingBonus ?? 0) }
  var estimatedAnnualValue: Double {
    firstYearCash + (employerRetirementAnnual ?? 0) + (medicalAnnual ?? 0)
      + (equityAnnualValue ?? 0) + (otherAnnualValue ?? 0)
      + (remoteSavingsAnnual ?? 0) - (commuteAnnualCost ?? 0)
  }
}

enum ReviewRequestStatus: String, CaseIterable, Codable, Identifiable {
  case draft
  case sent
  case feedbackReceived
  case closed
  case revoked

  var id: String { rawValue }
  var title: LocalizedStringResource {
    switch self {
    case .draft: "Draft"
    case .sent: "Sent"
    case .feedbackReceived: "Feedback received"
    case .closed: "Closed"
    case .revoked: "Link disabled"
    }
  }
}

struct ResumeReviewComment: Identifiable, Codable, Equatable {
  var id = UUID()
  var remoteID: String? = nil
  var section: String
  var author: String
  var comment: String
  var isResolved: Bool
  var createdAt = Date()
}

struct ResumeReviewRequest: Identifiable, Codable, Equatable {
  var id = UUID()
  var resumeID: UUID
  var reviewerName: String
  var reviewerEmail: String
  var message: String
  var accessCode: String
  var expiresAt: Date
  var status: ReviewRequestStatus
  var comments: [ResumeReviewComment]
  var createdAt = Date()
  var hostedURL: String? = nil
  var hostedToken: String? = nil
  var lastSyncedAt: Date? = nil

  var isExpired: Bool { expiresAt < Date() }
}

enum ResumeMarket: String, CaseIterable, Codable, Identifiable {
  case southAfrica
  case unitedKingdom
  case unitedStates
  case europeanUnion
  case australia
  case canada
  case international

  var id: String { rawValue }
  var title: LocalizedStringResource {
    switch self {
    case .southAfrica: "South Africa"
    case .unitedKingdom: "United Kingdom"
    case .unitedStates: "United States"
    case .europeanUnion: "European Union"
    case .australia: "Australia"
    case .canada: "Canada"
    case .international: "International"
    }
  }

  var flag: String {
    switch self {
    case .southAfrica: "🇿🇦"
    case .unitedKingdom: "🇬🇧"
    case .unitedStates: "🇺🇸"
    case .europeanUnion: "🇪🇺"
    case .australia: "🇦🇺"
    case .canada: "🇨🇦"
    case .international: "🌍"
    }
  }

  var dateStyleHint: String {
    switch self {
    case .unitedStates: "MMM yyyy"
    default: "MMM yyyy"
    }
  }
}

struct VoicePracticeAttempt: Identifiable, Codable, Equatable {
  var id = UUID()
  var applicationID: UUID?
  var question: String
  var transcript: String
  var durationSeconds: Double
  var wordsPerMinute: Int
  var fillerWords: [String]
  var starCoverage: [String]
  var strengths: [String]
  var improvements: [String]
  var suggestedAnswerShape: String
  var claimsRequiringConfirmation: [String]
  var createdAt = Date()
  var deliveryScore: Int? = nil
  var audioFilename: String? = nil
  var pauseCount: Int? = nil
  var longestPauseSeconds: Double? = nil
}

struct AIJobCapture: Codable, Equatable {
  var role: String
  var company: String
  var location: String
  var salary: String
  var closingDate: String
  var sourceURL: String
  var jobDescription: String
  var responsibilities: [String]
  var requirements: [String]
  var warnings: [String]
}

struct AIVoiceInterviewFeedback: Codable, Equatable {
  var strengths: [String]
  var improvements: [String]
  var starCoverage: [String]
  var suggestedAnswerShape: String
  var evidenceUsed: [String]
  var claimsRequiringConfirmation: [String]
}

struct AICareerToolkitDraft: Codable, Equatable {
  var title: String
  var body: String
  var highlights: [String]
  var evidenceSources: [String]
  var claimsRequiringConfirmation: [String]
}

struct AIProvenanceItem: Identifiable, Equatable {
  var id = UUID()
  var text: String
  var source: String
  var isVerified: Bool
}
