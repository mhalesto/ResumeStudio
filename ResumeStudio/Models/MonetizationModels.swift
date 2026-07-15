import Foundation

enum ResumeStudioPlan: String, Codable, CaseIterable, Identifiable {
  case free
  case go
  case pro

  var id: String { rawValue }

  var title: String {
    switch self {
    case .free: "Free"
    case .go: "Go"
    case .pro: "Pro"
    }
  }

  var monthlyAICredits: Int {
    switch self {
    case .free: 5
    case .go: 35
    case .pro: 150
    }
  }

  var hostedReviewRoomLimit: Int {
    switch self {
    case .free: 0
    case .go: 1
    case .pro: 10
    }
  }
}

enum ResumeStudioProduct {
  static let goMonthly = "com.halalisanimbanjwa.ResumeStudio.go.monthly"
  static let proMonthly = "com.halalisanimbanjwa.ResumeStudio.pro.monthly"
  static let designForever = "com.halalisanimbanjwa.ResumeStudio.designpack.forever"

  static let allIDs = [goMonthly, proMonthly, designForever]
  static let subscriptionIDs = Set([goMonthly, proMonthly])
}

struct MonetizationEntitlementProof: Codable, Equatable {
  var signedTransaction: String?
  var signedAppTransaction: String?
}

struct AIUsageSnapshot: Codable, Equatable {
  var tier: ResumeStudioPlan
  var creditsUsed: Int
  var creditsLimit: Int
  var creditsRemaining: Int
  var resetAt: Date?
  var bonusCreditsRemaining: Int? = nil
}

enum MonetizationCatalog {
  static let freeResumeTemplates: Set<ResumeTemplate> = [
    .modern, .minimal, .compact, .corporate, .classic, .academic,
    .monochrome, .ivy, .plinth, .chronicle, .signal, .pivot,
    // Twenty showcase designs from the Advanced Collection stay permanently
    // free, so the strongest layouts are part of the product experience rather
    // than merely an upsell preview.
    .apex, .aperture, .arclight, .blueprint, .catalyst,
    .circuit, .continuum, .district, .ember, .facet,
    .gallery, .halo, .helix, .kinetic, .lattice,
    .nexus, .orbit, .panorama, .quantum, .ribbon,
    // A taste of the Showcase Collection stays free; the rest are premium.
    .salute, .lozenge,
  ]

  static let freeCoverLetterTemplates: Set<CoverLetterTemplate> = [
    .modern, .minimal, .classic, .memo,
    // The ten Signature Collection letters ship free, so the most advanced
    // correspondence designs are part of the product rather than an upsell.
    .obsidian, .radiant, .verge, .datum, .pinnacle,
    .emblem, .cadence, .citadel, .stratus, .mirage,
  ]

  /// The original four accent colours are free; the five jewel tones are gated
  /// behind a subscription, the same way the premium templates are.
  static let freeAccents: Set<ResumeAccent> = [.orange, .blue, .teal, .burgundy]
}

extension ResumeAIAction {
  var creditCost: Int {
    switch self {
    case .improveBullet, .writeProfile, .suggestCompetencies, .careerCoach:
      1
    case .analyzeJob, .writeCoverLetter, .gradeInterviewAssessment,
      .captureJob, .evaluateInterviewAnswer, .careerToolkit:
      3
    case .importResume, .tailorResume, .interviewPrep, .interviewAssessment, .translateResume:
      5
    }
  }
}

extension Notification.Name {
  static let presentPlans = Notification.Name("ResumeStudio.presentPlans")
}
