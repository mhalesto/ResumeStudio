import Foundation

/// A durable copy of one successful AI response. The original structured JSON is
/// retained so a result remains recoverable even when its generating view is gone.
struct SavedAIArtifact: Identifiable, Codable, Equatable {
  var id: UUID
  var action: ResumeAIAction
  var createdAt: Date
  var context: String?
  var provider: ProductInsightSource?
  var outputJSON: String
  var previewLines: [String]

  init(
    id: UUID = UUID(),
    action: ResumeAIAction,
    createdAt: Date = Date(),
    context: String? = nil,
    provider: ProductInsightSource? = nil,
    outputJSON: String,
    previewLines: [String]
  ) {
    self.id = id
    self.action = action
    self.createdAt = createdAt
    self.context = context
    self.provider = provider
    self.outputJSON = outputJSON
    self.previewLines = previewLines
  }
}

extension ResumeAIAction {
  var title: String {
    switch self {
    case .importResume: "Résumé import"
    case .improveBullet: "Improved résumé bullet"
    case .writeProfile: "Professional profile"
    case .suggestCompetencies: "Competency suggestions"
    case .analyzeJob: "Job match analysis"
    case .tailorResume: "Tailored résumé"
    case .writeCoverLetter: "Cover letter"
    case .interviewPrep: "Interview plan"
    case .interviewAssessment: "Interview assessment"
    case .gradeInterviewAssessment: "Assessment feedback"
    case .careerCoach: "Career Coach reply"
    case .captureJob: "Captured job"
    case .evaluateInterviewAnswer: "Interview answer feedback"
    case .careerToolkit: "Career toolkit draft"
    case .translateResume: "Translated résumé"
    case .outcomeLearning: "Outcome learning draft"
    }
  }

  var systemImage: String {
    switch self {
    case .importResume: "doc.badge.arrow.up"
    case .improveBullet, .writeProfile, .suggestCompetencies, .tailorResume, .translateResume,
         .outcomeLearning: "wand.and.stars"
    case .analyzeJob: "scope"
    case .writeCoverLetter: "envelope"
    case .interviewPrep, .interviewAssessment, .gradeInterviewAssessment,
         .evaluateInterviewAnswer: "person.wave.2"
    case .careerCoach: "bubble.left.and.bubble.right"
    case .captureJob: "briefcase"
    case .careerToolkit: "sparkles.rectangle.stack"
    }
  }
}
