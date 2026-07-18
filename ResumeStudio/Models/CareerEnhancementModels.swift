import Foundation

enum ApplicationActivityKind: String, CaseIterable, Codable, Identifiable {
  case captured, applied, statusChanged, interview, followUp, note, offer
  var id: String { rawValue }
  var title: String {
    switch self {
    case .captured: "Captured"
    case .applied: "Applied"
    case .statusChanged: "Stage changed"
    case .interview: "Interview"
    case .followUp: "Follow-up"
    case .note: "Note"
    case .offer: "Offer"
    }
  }
  var systemImage: String {
    switch self {
    case .captured: "tray.and.arrow.down.fill"
    case .applied: "paperplane.fill"
    case .statusChanged: "arrow.triangle.swap"
    case .interview: "person.2.fill"
    case .followUp: "bell.fill"
    case .note: "note.text"
    case .offer: "star.fill"
    }
  }
}

struct ApplicationActivity: Identifiable, Codable, Equatable {
  var id = UUID()
  var kind: ApplicationActivityKind
  var title: String
  var detail: String
  var occurredAt = Date()
}

struct CapturedJobSnapshot: Codable, Equatable {
  var location: String
  var salary: String
  var closingDate: String
  var responsibilities: [String]
  var requirements: [String]
  var warnings: [String]
  var originalContent: String
  var capturedAt = Date()
}

enum ContactInteractionKind: String, CaseIterable, Codable, Identifiable {
  case email, linkedIn, phone, meeting, note
  var id: String { rawValue }
  var title: String { rawValue == "linkedIn" ? "LinkedIn" : rawValue.capitalized }
  var systemImage: String {
    switch self {
    case .email: "envelope.fill"
    case .linkedIn: "person.crop.rectangle"
    case .phone: "phone.fill"
    case .meeting: "person.2.fill"
    case .note: "note.text"
    }
  }
}

struct ContactInteraction: Identifiable, Codable, Equatable {
  var id = UUID()
  var kind: ContactInteractionKind
  var summary: String
  var occurredAt = Date()
}

enum AIRevisionStatus: String, Codable { case applied, reverted }

struct AIRevision: Identifiable, Codable, Equatable {
  var id = UUID()
  var resumeID: UUID?
  var field: String
  var before: String
  var after: String
  var evidenceIDs: [UUID]
  var evidenceLabels: [String]
  var claimsRequiringConfirmation: [String]
  var status: AIRevisionStatus = .applied
  var createdAt = Date()
  var revertedAt: Date?
}

struct AIProcessingRecord: Identifiable, Codable, Equatable {
  var id = UUID()
  var action: String
  var purpose: String
  var includedVerifiedEvidence: Bool
  var provider: ProductInsightSource? = nil
  var completedAt = Date()
}

struct MarketGuidanceSource: Identifiable, Codable, Equatable {
  var id = UUID()
  var market: ResumeMarket
  var title: String
  var publisher: String
  var url: String
  var checkedAt: Date
  var note: String
}

struct SharedJobCapture: Codable, Equatable {
  var url: String
  var text: String
  var receivedAt = Date()
}

enum CareerPrivacySetting {
  static let aiEnabledKey = "careerAIProcessingEnabled"
  static let shareVerifiedEvidenceKey = "careerAIShareVerifiedEvidence"
  static let keepHistoryKey = "careerAIKeepProcessingHistory"
  static let onDeviceAIKey = "careerAIUseOnDeviceIntelligence"
  static let connectedFallbackKey = "careerAIAllowConnectedFallback"
}
