import Foundation

enum ResumePageTarget: String, CaseIterable, Codable, Identifiable {
  case automatic
  case one
  case two

  var id: String { rawValue }
  var title: String {
    switch self {
    case .automatic: "Automatic"
    case .one: "One page"
    case .two: "Two pages"
    }
  }
  var pageCount: Int? {
    switch self {
    case .automatic: nil
    case .one: 1
    case .two: 2
    }
  }
}

enum ResumePaperSize: String, CaseIterable, Codable, Identifiable {
  case a4
  case letter

  var id: String { rawValue }
  var title: String { self == .a4 ? "A4" : "US Letter" }
}

enum ResumeFontChoice: String, CaseIterable, Codable, Identifiable {
  case template
  case cleanSans
  case editorialSerif
  case modernRounded
  case technicalMono

  var id: String { rawValue }
  var title: String {
    switch self {
    case .template: "Template default"
    case .cleanSans: "Clean Sans"
    case .editorialSerif: "Editorial Serif"
    case .modernRounded: "Modern Rounded"
    case .technicalMono: "Technical Mono"
    }
  }
}

enum ResumeContentBlock: String, CaseIterable, Codable, Identifiable {
  case profile
  case competencies
  case experience
  case education
  case additional
  case references

  var id: String { rawValue }
  var title: String {
    switch self {
    case .profile: "Professional Profile"
    case .competencies: "Core Competencies"
    case .experience: "Professional Experience"
    case .education: "Education"
    case .additional: "Additional Sections"
    case .references: "References"
    }
  }
}

struct ResumeLayoutSettings: Codable, Equatable, Hashable {
  var fontChoice: ResumeFontChoice = .template
  var fontScale: Double = 1
  var lineSpacing: Double = 1
  var marginPoints: Double = 34
  var pageTarget: ResumePageTarget = .automatic
  var paperSize: ResumePaperSize = .a4
  var sectionOrder: [ResumeContentBlock] = ResumeContentBlock.allCases
  var customHeadings: [String: String] = [:]

  static let standard = ResumeLayoutSettings()

  mutating func normalize() {
    fontScale = min(max(fontScale, 0.82), 1.12)
    lineSpacing = min(max(lineSpacing, 0.88), 1.15)
    marginPoints = min(max(marginPoints, 24), 50)
    let known = Set(ResumeContentBlock.allCases)
    var unique = sectionOrder.filter { known.contains($0) }
    unique = unique.reduce(into: []) { result, block in
      if !result.contains(block) { result.append(block) }
    }
    unique.append(contentsOf: ResumeContentBlock.allCases.filter { !unique.contains($0) })
    sectionOrder = unique
  }

  func heading(for block: ResumeContentBlock) -> String {
    customHeadings[block.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines)
      .nilIfBlank ?? block.title
  }
}

enum TemplateSeniority: String, CaseIterable, Codable, Identifiable {
  case earlyCareer
  case experienced
  case leadership
  case executive

  var id: String { rawValue }
  var title: String {
    switch self {
    case .earlyCareer: "Early career"
    case .experienced: "Experienced"
    case .leadership: "Leadership"
    case .executive: "Executive"
    }
  }
}

struct TemplateFinderPreferences: Codable, Equatable {
  var role = ""
  var seniority: TemplateSeniority = .experienced
  var market: ResumeMarket = .international
  var wantsPhoto = false
  var strictATS = true
  var targetPages: ResumePageTarget = .automatic
  var freeOnly = false
}

struct TemplateRecommendation: Identifiable, Equatable {
  var template: ResumeTemplate
  var score: Int
  var reasons: [String]
  var id: ResumeTemplate { template }

  init(template: ResumeTemplate, score: Int, reasons: [String]) {
    self.template = template
    self.score = min(100, max(0, score))
    self.reasons = reasons
  }
}

struct ApplicationPacket: Identifiable, Codable, Equatable {
  var id = UUID()
  var applicationID: UUID
  var resumeID: UUID
  var coverLetter: CoverLetterDocument
  var applicationEmailSubject: String
  var applicationEmailBody: String
  var followUpEmailSubject: String
  var followUpEmailBody: String
  var interviewChecklist: [String]
  var createdAt = Date()
  var updatedAt = Date()

  static func make(
    application: JobApplication,
    resumeID: UUID,
    resume: ResumeDocument,
    matchingTemplate: CoverLetterTemplate? = nil
  ) -> ApplicationPacket {
    let role = application.role.nilIfBlank ?? "the advertised role"
    let company = application.company.nilIfBlank ?? "your organisation"
    var letter = CoverLetterDocument.blank
    letter.senderName = resume.personal.fullName
    letter.senderHeadline = resume.personal.headline
    letter.senderPhone = resume.personal.phone
    letter.senderEmail = resume.personal.email
    letter.jobTitle = application.role
    letter.companyName = application.company
    letter.subject = "Application for \(role)"
    letter.jobDescription = application.jobDescription
    letter.accent = resume.accent
    letter.template = matchingTemplate
      ?? CoverLetterTemplate.allCases.first(where: { $0.pairsWith == resume.template })
      ?? .modern

    return ApplicationPacket(
      applicationID: application.id,
      resumeID: resumeID,
      coverLetter: letter,
      applicationEmailSubject: "Application for \(role) — \(resume.personal.fullName)",
      applicationEmailBody:
        "Dear Hiring Team,\n\nPlease find attached my résumé and cover letter for the \(role) position at \(company). Thank you for considering my application.\n\nKind regards,\n\(resume.personal.fullName)",
      followUpEmailSubject: "Following up: \(role) application",
      followUpEmailBody:
        "Dear Hiring Team,\n\nI am following up on my application for the \(role) position. I remain interested in the opportunity and would be happy to provide any additional information.\n\nKind regards,\n\(resume.personal.fullName)",
      interviewChecklist: [
        "Review the role requirements and company priorities",
        "Prepare three evidence-backed STAR examples",
        "Practise a concise opening pitch",
        "Prepare thoughtful questions for the interviewers",
        "Confirm the interview time, format and location",
      ]
    )
  }
}

struct ResumeTranslationPayload: Codable {
  var resume: AIResumeSnapshot
  var targetLanguage: String
  var market: String
}

struct AITranslatedResume: Codable, Equatable {
  var headline: String
  var professionalProfile: String
  var competencies: [String]
  var experience: [AITailoredExperience]
  var education: [AITranslatedEducation]
  var additionalSections: [AIImportedAdditionalSection]
  var translatedHeadings: [String: String]
  var claimsRequiringConfirmation: [String]

  func applying(to source: ResumeDocument) -> ResumeDocument {
    var result = source
    result.personal.headline = headline
    result.professionalProfile = professionalProfile
    result.competencies = competencies
    let translatedExperience = Dictionary(uniqueKeysWithValues: experience.map { ($0.id, $0.highlights) })
    for index in result.experience.indices {
      if let highlights = translatedExperience[result.experience[index].id.uuidString] {
        result.experience[index].highlights = highlights
      }
    }
    for item in education where result.education.indices.contains(item.index) {
      result.education[item.index].qualification = item.qualification
      result.education[item.index].institution = item.institution
      result.education[item.index].period = item.period
      result.education[item.index].details = item.details
    }
    result.additionalSections = additionalSections.map {
      ResumeAdditionalSection(title: $0.title, items: $0.items)
    }
    result.layout.customHeadings.merge(translatedHeadings) { _, translated in translated }
    return result
  }
}

struct AITranslatedEducation: Codable, Equatable {
  var index: Int
  var qualification: String
  var institution: String
  var period: String
  var details: String
}

struct ApplicationAnalyticsSummary: Equatable {
  var tracked: Int
  var applied: Int
  var interviews: Int
  var offers: Int
  var responses: Int
  var applicationToInterviewRate: Int
  var interviewToOfferRate: Int
  var averageDaysToResponse: Double?
  var bySource: [ApplicationSourceMetric]
  var byResume: [ApplicationResumeMetric]

  static let empty = ApplicationAnalyticsSummary(
    tracked: 0, applied: 0, interviews: 0, offers: 0, responses: 0,
    applicationToInterviewRate: 0, interviewToOfferRate: 0,
    averageDaysToResponse: nil, bySource: [], byResume: []
  )
}

struct ApplicationSourceMetric: Identifiable, Equatable {
  var name: String
  var count: Int
  var interviews: Int
  var id: String { name }
}

struct ApplicationResumeMetric: Identifiable, Equatable {
  var id: UUID
  var count: Int
  var interviews: Int
}
