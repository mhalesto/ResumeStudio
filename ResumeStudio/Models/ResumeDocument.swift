import Foundation
import SwiftUI
import UIKit

struct ResumeDocument: Codable, Equatable, Hashable {
  static let currentSchemaVersion = 2

  var schemaVersion: Int
  var personal: PersonalDetails
  var professionalProfile: String
  var competencies: [String]
  var experience: [ExperienceEntry]
  var education: [EducationEntry]
  var references: [ReferenceEntry]
  var accent: ResumeAccent
  var template: ResumeTemplate

  var suggestedFilename: String {
    let source = personal.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
    let base = source.isEmpty ? "Resume" : "\(source) Resume"
    let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
    return base.components(separatedBy: invalid).joined(separator: "-")
  }

  static let blank = ResumeDocument(
    schemaVersion: currentSchemaVersion,
    personal: PersonalDetails(fullName: "", headline: "", phone: "", email: ""),
    professionalProfile: "",
    competencies: [],
    experience: [],
    education: [],
    references: [],
    accent: .orange,
    template: .modern
  )

  static let example = ResumeDocument(
    schemaVersion: currentSchemaVersion,
    personal: PersonalDetails(
      fullName: "Avery Sample",
      headline: "People Operations Manager | Employee Experience",
      phone: "+1 202 555 0147",
      email: "avery.sample@example.com"
    ),
    professionalProfile:
      "People-focused operations professional with 7+ years of experience building inclusive employee programmes, improving manager support, and turning workforce insights into practical action. Known for clear communication, thoughtful problem-solving, and creating scalable processes that strengthen culture while supporting business growth.",
    competencies: [
      "People Operations Strategy",
      "Employee Experience",
      "Manager Coaching",
      "Workforce Planning",
      "People Analytics",
      "Talent Acquisition",
      "Policy & Process Design",
      "Change Communication",
    ],
    experience: [
      ExperienceEntry(
        role: "People Operations Manager",
        company: "Northstar Works",
        period: "Jan 2023 - Present",
        highlights: [
          "Built a quarterly people-planning rhythm that connected hiring, development, and retention priorities.",
          "Introduced a manager toolkit and coaching programme that improved confidence in performance conversations.",
          "Created a clear employee-listening process and translated recurring themes into measurable action plans.",
          "Simplified onboarding workflows and reduced manual administration across the employee lifecycle.",
          "Partnered with leaders on organisation design, role clarity, and change communication.",
        ]
      ),
      ExperienceEntry(
        role: "Employee Experience Partner",
        company: "Brightside Labs",
        period: "Mar 2020 - Dec 2022",
        highlights: [
          "Designed employee journeys for onboarding, internal mobility, and returning from extended leave.",
          "Facilitated workshops on feedback, team agreements, and inclusive meeting practices.",
          "Maintained people dashboards and prepared monthly insights for leadership reviews.",
          "Supported policy updates with plain-language guidance for employees and managers.",
          "Coordinated engagement initiatives across hybrid teams in three regions.",
        ]
      ),
      ExperienceEntry(
        role: "Talent Coordinator",
        company: "Cedar Street Group",
        period: "Jun 2018 - Feb 2020",
        highlights: [
          "Coordinated interview scheduling, candidate communication, and offer documentation.",
          "Created weekly recruiting reports that highlighted pipeline health and hiring bottlenecks.",
          "Improved candidate templates and interview guidance for a more consistent experience.",
          "Supported university outreach and early-career hiring events.",
        ]
      ),
    ],
    education: [
      EducationEntry(
        qualification: "Bachelor of Business Administration",
        institution: "Example State University",
        period: "2014 - 2018",
        details: "Concentration in Human Resource Management"
      ),
      EducationEntry(
        qualification: "Certificate in People Analytics",
        institution: "Sample Learning Institute",
        period: "2021",
        details: ""
      ),
    ],
    references: [
      ReferenceEntry(
        name: "Riley Example",
        company: "Northstar Works",
        phone: "+1 202 555 0198",
        email: "riley.example@example.com"
      ),
      ReferenceEntry(
        name: "Morgan Sample",
        company: "Brightside Labs",
        phone: "+1 202 555 0164",
        email: "morgan.sample@example.com"
      ),
    ],
    accent: .orange,
    template: .modern
  )

  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case personal
    case professionalProfile
    case competencies
    case experience
    case education
    case references
    case accent
    case template
  }

  init(
    schemaVersion: Int = currentSchemaVersion,
    personal: PersonalDetails,
    professionalProfile: String,
    competencies: [String],
    experience: [ExperienceEntry],
    education: [EducationEntry],
    references: [ReferenceEntry],
    accent: ResumeAccent,
    template: ResumeTemplate
  ) {
    self.schemaVersion = schemaVersion
    self.personal = personal
    self.professionalProfile = professionalProfile
    self.competencies = competencies
    self.experience = experience
    self.education = education
    self.references = references
    self.accent = accent
    self.template = template
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    personal = try container.decode(PersonalDetails.self, forKey: .personal)
    professionalProfile = try container.decode(String.self, forKey: .professionalProfile)
    competencies = try container.decode([String].self, forKey: .competencies)
    experience = try container.decode([ExperienceEntry].self, forKey: .experience)
    education = try container.decode([EducationEntry].self, forKey: .education)
    references = try container.decode([ReferenceEntry].self, forKey: .references)
    accent = try container.decodeIfPresent(ResumeAccent.self, forKey: .accent) ?? .orange
    template = try container.decodeIfPresent(ResumeTemplate.self, forKey: .template) ?? .modern
  }
}

struct PersonalDetails: Codable, Equatable, Hashable {
  var fullName: String
  var headline: String
  var phone: String
  var email: String
}

struct ExperienceEntry: Identifiable, Codable, Equatable, Hashable {
  var id = UUID()
  var role: String
  var company: String
  var period: String
  var highlights: [String]
}

struct EducationEntry: Identifiable, Codable, Equatable, Hashable {
  var id = UUID()
  var qualification: String
  var institution: String
  var period: String
  var details: String
}

struct ReferenceEntry: Identifiable, Codable, Equatable, Hashable {
  var id = UUID()
  var name: String
  var company: String
  var phone: String
  var email: String
}

enum ResumeAccent: String, CaseIterable, Codable, Identifiable {
  case orange
  case blue
  case teal
  case burgundy

  var id: String { rawValue }

  var title: String {
    rawValue.capitalized
  }

  var color: Color {
    Color(uiColor: uiColor)
  }

  var uiColor: UIColor {
    switch self {
    case .orange:
      UIColor(red: 0.82, green: 0.28, blue: 0.04, alpha: 1)
    case .blue:
      UIColor(red: 0.11, green: 0.38, blue: 0.70, alpha: 1)
    case .teal:
      UIColor(red: 0.05, green: 0.47, blue: 0.47, alpha: 1)
    case .burgundy:
      UIColor(red: 0.55, green: 0.10, blue: 0.21, alpha: 1)
    }
  }
}

enum ResumeTemplate: String, CaseIterable, Codable, Identifiable {
  case modern
  case classic
  case minimal
  case contemporary
  case corporate
  case elegant
  case nordic
  case creative
  case technical
  case compact
  case academic
  case timeline
  case monochrome

  var id: String { rawValue }

  var title: String {
    switch self {
    case .modern: "Modern Executive"
    case .classic: "Classic Editorial"
    case .minimal: "Clean Minimal"
    case .contemporary: "Contemporary Split"
    case .corporate: "Corporate Slate"
    case .elegant: "Elegant Serif"
    case .nordic: "Nordic Air"
    case .creative: "Creative Blocks"
    case .technical: "Tech Grid"
    case .compact: "Compact Pro"
    case .academic: "Academic CV"
    case .timeline: "Timeline Focus"
    case .monochrome: "Monochrome Ink"
    }
  }

  var subtitle: String {
    switch self {
    case .modern: "Bold header and crisp section rules"
    case .classic: "Serif typography and timeless spacing"
    case .minimal: "Airy layout with subtle accents"
    case .contemporary: "Asymmetric header with a split accent"
    case .corporate: "Structured bands for leadership roles"
    case .elegant: "Refined type with understated ornament"
    case .nordic: "Generous whitespace and quiet detail"
    case .creative: "Playful geometry with confident contrast"
    case .technical: "Precise lines and modern technical type"
    case .compact: "Dense, recruiter-friendly information"
    case .academic: "Formal scholarly typography and hierarchy"
    case .timeline: "Career storytelling with timeline details"
    case .monochrome: "Black-and-white editorial confidence"
    }
  }

  var systemImage: String {
    switch self {
    case .modern: "rectangle.topthird.inset.filled"
    case .classic: "text.book.closed.fill"
    case .minimal: "rectangle.inset.filled.and.person.filled"
    case .contemporary: "rectangle.split.2x1.fill"
    case .corporate: "building.2.fill"
    case .elegant: "textformat"
    case .nordic: "leaf.fill"
    case .creative: "square.grid.2x2.fill"
    case .technical: "chevron.left.forwardslash.chevron.right"
    case .compact: "list.bullet.rectangle.fill"
    case .academic: "graduationcap.fill"
    case .timeline: "list.bullet.indent"
    case .monochrome: "circle.lefthalf.filled"
    }
  }
}
