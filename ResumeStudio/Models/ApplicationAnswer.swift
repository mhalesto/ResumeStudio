import Foundation

enum ApplicationAnswerCategory: String, CaseIterable, Codable, Identifiable {
  case workAuthorization
  case sponsorship
  case availability
  case compensation
  case relocation
  case workPreference
  case motivation
  case custom

  var id: String { rawValue }

  var title: LocalizedStringResource {
    switch self {
    case .workAuthorization: "Work authorization"
    case .sponsorship: "Visa sponsorship"
    case .availability: "Availability"
    case .compensation: "Salary expectations"
    case .relocation: "Relocation"
    case .workPreference: "Work arrangement"
    case .motivation: "Role motivation"
    case .custom: "Custom question"
    }
  }

  var systemImage: String {
    switch self {
    case .workAuthorization: "checkmark.seal.fill"
    case .sponsorship: "person.text.rectangle.fill"
    case .availability: "calendar.badge.clock"
    case .compensation: "banknote.fill"
    case .relocation: "location.fill"
    case .workPreference: "house.and.flag.fill"
    case .motivation: "text.bubble.fill"
    case .custom: "square.and.pencil"
    }
  }

  var starterTitle: LocalizedStringResource {
    switch self {
    case .workAuthorization: "Are you legally authorized to work here?"
    case .sponsorship: "Will you require visa sponsorship?"
    case .availability: "When can you start?"
    case .compensation: "What are your salary expectations?"
    case .relocation: "Are you willing to relocate?"
    case .workPreference: "What work arrangement do you prefer?"
    case .motivation: "Why are you interested in this role?"
    case .custom: "Application question"
    }
  }

  var defaultMatchTerms: [String] {
    switch self {
    case .workAuthorization:
      ["authorized to work", "legally authorized", "right to work", "work authorization"]
    case .sponsorship:
      ["require sponsorship", "visa sponsorship", "employment sponsorship", "sponsor you"]
    case .availability:
      ["available to start", "start date", "notice period", "when can you start"]
    case .compensation:
      ["salary expectation", "expected salary", "desired salary", "compensation expectation", "pay expectation"]
    case .relocation:
      ["willing to relocate", "open to relocation", "relocate"]
    case .workPreference:
      ["work arrangement", "work preference", "remote preference", "remote hybrid", "onsite hybrid"]
    case .motivation:
      ["why do you want", "why are you interested", "why this role", "why this company"]
    case .custom:
      []
    }
  }
}

struct ApplicationAnswer: Identifiable, Codable, Equatable {
  var id = UUID()
  var category: ApplicationAnswerCategory
  var title: String
  var answer: String
  var keywords: [String]
  var isEnabled: Bool
  var updatedAt = Date()

  init(
    id: UUID = UUID(),
    category: ApplicationAnswerCategory,
    title: String,
    answer: String = "",
    keywords: [String] = [],
    isEnabled: Bool = false,
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.category = category
    self.title = title
    self.answer = answer
    self.keywords = keywords
    self.isEnabled = isEnabled
    self.updatedAt = updatedAt
  }

  var canPublish: Bool {
    isEnabled
      && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !matchTerms.isEmpty
  }

  var matchTerms: [String] {
    var seen: Set<String> = []
    return ([title] + keywords + category.defaultMatchTerms)
      .map(Self.normalizedMatchTerm)
      .filter { $0.count >= 3 && seen.insert($0).inserted }
  }

  static var starterEntries: [ApplicationAnswer] {
    ApplicationAnswerCategory.allCases
      .filter { $0 != .custom }
      .map { ApplicationAnswer(category: $0, title: String(localized: $0.starterTitle)) }
  }

  private static func normalizedMatchTerm(_ value: String) -> String {
    value.lowercased()
      .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
