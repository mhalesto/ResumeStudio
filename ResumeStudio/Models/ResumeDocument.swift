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
  var additionalSections: [ResumeAdditionalSection]
  var accent: ResumeAccent
  var template: ResumeTemplate
  var layout: ResumeLayoutSettings

  /// A JPEG portrait, already downscaled by `ProfilePhoto.prepare`. Optional, and
  /// deliberately *not* a schema bump: `ResumeStore` replaces any draft older than
  /// the current version with the example, so bumping would delete real résumés.
  /// An absent key simply decodes to `nil`.
  var photo: Data?

  /// Which part of `photo` the circle shows. Absent means centred and zoomed out,
  /// which is exactly how photos were framed before this was adjustable.
  var photoCrop: PhotoCrop?

  /// Per-version visibility. Hiding a portrait never deletes its image or crop,
  /// so a user can keep photo and non-photo résumé variants without re-importing.
  var isPhotoVisible: Bool

  /// Certificates, portfolio pages and other supporting documents, printed after
  /// the last page of the résumé. Like `photo`, deliberately not a schema bump:
  /// an absent key decodes to none. See `ResumeAttachment`.
  var attachments: [ResumeAttachment]

  /// An optional hand-drawn mark over one résumé page. Stored as PencilKit
  /// vectors so it stays editable and prints sharply; older drafts simply
  /// decode this absent key as unsigned.
  var signature: ResumeSignature?

  var suggestedFilename: String {
    let source = personal.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
    let base = source.isEmpty ? "Resume" : "\(source) Resume"
    let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
    return base.components(separatedBy: invalid).joined(separator: "-")
  }

  /// How complete the draft is, `0...1` — one point per section a recruiter
  /// expects to find. Drives the home screen's progress bar.
  ///
  /// Entries only count when they carry real content, so an empty row added in
  /// an editor doesn't inflate the score.
  var completion: Double {
    let checks: [Bool] = [
      !personal.fullName.isBlank,
      !personal.headline.isBlank,
      !personal.email.isBlank,
      !personal.phone.isBlank,
      !professionalProfile.isBlank,
      competencies.contains { !$0.isBlank },
      experience.contains { !$0.role.isBlank || !$0.company.isBlank },
      education.contains { !$0.qualification.isBlank || !$0.institution.isBlank },
      references.contains { !$0.name.isBlank },
    ]
    return Double(checks.count { $0 }) / Double(checks.count)
  }

  /// `completion` as a whole percentage, for display.
  var completionPercentage: Int {
    Int((completion * 100).rounded())
  }

  /// The sections still waiting on content, in the order they appear in the
  /// editor. The home screen points at the first one so there is always an
  /// obvious next move.
  var incompleteSections: [ResumeSection] {
    ResumeSection.allCases.filter { !isComplete($0) }
  }

  func isComplete(_ section: ResumeSection) -> Bool {
    switch section {
    case .personal:
      !personal.fullName.isBlank && !personal.headline.isBlank && !personal.email.isBlank
        && !personal.phone.isBlank
    case .profile:
      !professionalProfile.isBlank
    case .competencies:
      competencies.contains { !$0.isBlank }
    case .experience:
      experience.contains { !$0.role.isBlank || !$0.company.isBlank }
    case .education:
      education.contains { !$0.qualification.isBlank || !$0.institution.isBlank }
    case .references:
      references.contains { !$0.name.isBlank }
    }
  }

  static let blank = ResumeDocument(
    schemaVersion: currentSchemaVersion,
    personal: PersonalDetails(fullName: "", headline: "", phone: "", email: ""),
    professionalProfile: "",
    competencies: [],
    experience: [],
    education: [],
    references: [],
    additionalSections: [],
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
    additionalSections: [
      ResumeAdditionalSection(
        title: "Certifications",
        items: ["Certificate in People Analytics — Sample Learning Institute, 2021"]
      ),
      ResumeAdditionalSection(
        title: "Languages",
        items: ["English — Fluent", "Spanish — Conversational"]
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
    case additionalSections
    case accent
    case template
    case photo
    case photoCrop
    case isPhotoVisible
    case layout
    case attachments
    case signature
  }

  init(
    schemaVersion: Int = currentSchemaVersion,
    personal: PersonalDetails,
    professionalProfile: String,
    competencies: [String],
    experience: [ExperienceEntry],
    education: [EducationEntry],
    references: [ReferenceEntry],
    additionalSections: [ResumeAdditionalSection] = [],
    accent: ResumeAccent,
    template: ResumeTemplate,
    photo: Data? = nil,
    photoCrop: PhotoCrop? = nil,
    isPhotoVisible: Bool = true,
    layout: ResumeLayoutSettings = .standard,
    attachments: [ResumeAttachment] = [],
    signature: ResumeSignature? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.personal = personal
    self.professionalProfile = professionalProfile
    self.competencies = competencies
    self.experience = experience
    self.education = education
    self.references = references
    self.additionalSections = additionalSections
    self.accent = accent
    self.template = template
    self.photo = photo
    self.photoCrop = photoCrop
    self.isPhotoVisible = isPhotoVisible
    self.layout = layout
    self.attachments = attachments
    self.signature = signature
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
    additionalSections =
      try container.decodeIfPresent([ResumeAdditionalSection].self, forKey: .additionalSections) ?? []
    accent = try container.decodeIfPresent(ResumeAccent.self, forKey: .accent) ?? .orange
    template = try container.decodeIfPresent(ResumeTemplate.self, forKey: .template) ?? .modern
    photo = try container.decodeIfPresent(Data.self, forKey: .photo)
    photoCrop = try container.decodeIfPresent(PhotoCrop.self, forKey: .photoCrop)
    isPhotoVisible = try container.decodeIfPresent(Bool.self, forKey: .isPhotoVisible) ?? true
    layout = try container.decodeIfPresent(ResumeLayoutSettings.self, forKey: .layout) ?? .standard
    layout.normalize()
    attachments =
      try container.decodeIfPresent([ResumeAttachment].self, forKey: .attachments) ?? []
    signature = try container.decodeIfPresent(ResumeSignature.self, forKey: .signature)
  }

  var photoImage: UIImage? {
    photo.flatMap(UIImage.init(data:))
  }

  /// Whether the exported PDF actually prints a portrait. When visibility is
  /// disabled, both the photo and photo-led templates' initials placeholder are
  /// removed and the letterhead closes up the space.
  var showsPortrait: Bool {
    isPhotoVisible && (template.isPhotoLed || photo != nil)
  }

  /// The portrait as the circle shows it. Everything that draws the photo — the
  /// PDF, the thumbnails, the editor — goes through this, so they can't disagree.
  var croppedPhotoImage: UIImage? {
    guard let image = photoImage else { return nil }
    return ProfilePhoto.cropped(image, to: photoCrop ?? .centred)
  }

  /// Stands in for a portrait when none has been chosen — the photo templates
  /// draw these in the accent ring rather than an empty hole.
  var initials: String {
    let words = personal.fullName
      .split(separator: " ")
      .prefix(2)
      .compactMap(\.first)
    return words.isEmpty ? "?" : String(words).uppercased()
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

struct ResumeAdditionalSection: Identifiable, Codable, Equatable, Hashable {
  var id = UUID()
  var title: String
  var items: [String]
}

struct ResumeDraft: Identifiable, Codable, Equatable, Hashable {
  var id: UUID
  var title: String
  var document: ResumeDocument
  var createdAt: Date
  var updatedAt: Date

  init(
    id: UUID = UUID(),
    title: String,
    document: ResumeDocument,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.title = title
    self.document = document
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

enum ResumeAccent: String, CaseIterable, Codable, Identifiable {
  case orange
  case blue
  case teal
  case burgundy
  // The Signature palette: five jewel accents gated behind a subscription, the
  // same way the premium templates are.
  case emerald
  case amethyst
  case sapphire
  case rose
  case midnight
  // The Atelier palette: five more refined tones, also part of the subscription.
  case bronze
  case graphite
  case plum
  case steel
  case terracotta
  // The Luxe palette: six nuanced, high-contrast tones designed to feel rich
  // on screen while remaining clear and professional in exported documents.
  case champagne
  case peacock
  case mulberry
  case moss
  case cobalt
  case cocoa

  var id: String { rawValue }

  /// Display names. Only "Burnt Orange" comes from the prototype; the rest are
  /// named to match its tone. The colours themselves are unchanged — they are
  /// the app's own, and they drive the exported PDF.
  var title: LocalizedStringResource {
    return switch self {
    case .orange: "Burnt Orange"
    case .blue: "Deep Blue"
    case .teal: "Pine Teal"
    case .burgundy: "Burgundy"
    case .emerald: "Emerald"
    case .amethyst: "Amethyst"
    case .sapphire: "Sapphire"
    case .rose: "Rose Gold"
    case .midnight: "Midnight"
    case .bronze: "Bronze"
    case .graphite: "Graphite"
    case .plum: "Plum"
    case .steel: "Steel Blue"
    case .terracotta: "Terracotta"
    case .champagne: "Champagne Gold"
    case .peacock: "Peacock"
    case .mulberry: "Mulberry"
    case .moss: "Moss"
    case .cobalt: "Cobalt"
    case .cocoa: "Cocoa"
    }
  }

  /// The four original accents ship free; every richer tone is part of the
  /// subscription, checked through `PurchaseManager.canUse(_:)` in the UI.
  var isPremium: Bool {
    !MonetizationCatalog.freeAccents.contains(self)
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
    case .emerald:
      UIColor(red: 0.06, green: 0.45, blue: 0.31, alpha: 1)
    case .amethyst:
      UIColor(red: 0.45, green: 0.26, blue: 0.60, alpha: 1)
    case .sapphire:
      UIColor(red: 0.13, green: 0.24, blue: 0.58, alpha: 1)
    case .rose:
      UIColor(red: 0.79, green: 0.32, blue: 0.44, alpha: 1)
    case .midnight:
      UIColor(red: 0.14, green: 0.18, blue: 0.28, alpha: 1)
    case .bronze:
      UIColor(red: 0.63, green: 0.44, blue: 0.18, alpha: 1)
    case .graphite:
      UIColor(red: 0.26, green: 0.29, blue: 0.33, alpha: 1)
    case .plum:
      UIColor(red: 0.42, green: 0.18, blue: 0.38, alpha: 1)
    case .steel:
      UIColor(red: 0.28, green: 0.42, blue: 0.53, alpha: 1)
    case .terracotta:
      UIColor(red: 0.75, green: 0.39, blue: 0.28, alpha: 1)
    case .champagne:
      UIColor(red: 0.608, green: 0.431, blue: 0.141, alpha: 1)
    case .peacock:
      UIColor(red: 0.04, green: 0.40, blue: 0.44, alpha: 1)
    case .mulberry:
      UIColor(red: 0.54, green: 0.20, blue: 0.37, alpha: 1)
    case .moss:
      UIColor(red: 0.36, green: 0.42, blue: 0.23, alpha: 1)
    case .cobalt:
      UIColor(red: 0.20, green: 0.31, blue: 0.64, alpha: 1)
    case .cocoa:
      UIColor(red: 0.42, green: 0.28, blue: 0.24, alpha: 1)
    }
  }
}

enum TemplateStyleTag: String, CaseIterable, Identifiable, Hashable {
  case studio
  case showcase
  case structured
  case modern
  case clean
  case classic
  case bold
  case creative
  case photo
  case ats

  var id: String { rawValue }

  var title: LocalizedStringResource {
    switch self {
    // The most art-directed application systems: every résumé has a bespoke
    // matching letterhead rather than sharing a parameterised construction.
    case .studio: "Studio"
    // The Showcase Collection: the portfolio-grade, "goes a bit beyond" designs —
    // monogram badges, vertical names, dot ratings. Kept first so someone after a
    // standout résumé finds them in one tap.
    case .showcase: "Showcase"
    // The templates that rearrange the page rather than the letterhead. First in
    // the filter row because it is the thing people are actually looking for
    // when they say a résumé looks like every other résumé.
    case .structured: "Structured"
    case .modern: "Modern"
    case .clean: "Clean"
    case .classic: "Classic"
    case .bold: "Bold"
    case .creative: "Creative"
    case .photo: "Photo"
    case .ats: "ATS"
    }
  }
}

enum ResumeTemplate: String, CaseIterable, Codable, Identifiable {
  case atlas
  case verso
  case oxford
  case chronicle
  case gazette
  case strata
  case duo
  case signal
  case concise
  case pivot
  case portrait
  case spotlight
  case beacon
  case harbor
  case bloom
  case atelier
  case canvas
  case modern
  case aurora
  case slate
  case onyx
  case minimal
  case lumen
  case nordic
  case cascade
  case contemporary
  case horizon
  case vector
  case technical
  case creative
  case mosaic
  case vertex
  case timeline
  case compact
  case corporate
  case meridian
  case classic
  case elegant
  case linen
  case ledger
  case quill
  case academic
  case monochrome
  case editorial
  case noir
  case gauge
  case folio
  case insignia
  case marquee
  case metro
  case ivy
  case crest
  case geneva
  case plinth
  case stockholm
  case tandem
  case varsity
  case laureate
  case modena
  case nova
  case prism
  case aurelia
  case nocturne
  case monarch
  case eclipse
  case contour
  case axis
  case terrace
  case vantage
  // Advanced Collection — 32 art-directed layouts released as one complete
  // expansion. Their shared renderer is parameterised, but every case has its
  // own page plan, masthead geometry, typography and section language.
  case apex
  case aperture
  case arclight
  case blueprint
  case catalyst
  case circuit
  case continuum
  case district
  case ember
  case facet
  case gallery
  case halo
  case helix
  case kinetic
  case lattice
  case nexus
  case orbit
  case panorama
  case quantum
  case ribbon
  case runway
  case sentinel
  case spectrum
  case summit
  case tessera
  case vault
  case wave
  case zenith
  case alcove
  case sovereign
  case palisade
  case volta
  // The Signature Collection: mastheads 8-15, a second construction set built
  // beyond the first thirty-two. Each reaches for a picture the earlier ones do
  // not — a duotone split, a radial halo, tiled metrics, a monogram watermark,
  // layered glass, an equaliser, an architected frame, drifting gradient bands.
  case obsidian
  case radiant
  case verge
  case datum
  case pinnacle
  case cobalt
  case equinox
  case mirage
  case parallax
  case emblem
  case cadence
  case citadel
  case atrium
  case zephyr
  case cinder
  case keystone
  case loom
  case graphite
  case stratus
  case vellum
  // The Showcase Collection: portfolio-grade designs that go a step beyond —
  // greetings, monogram badges, vertical names, dot ratings. Mastheads 16-25.
  case salute
  case couture
  case medallion
  case sable
  case terracotta
  case lozenge
  case circlet
  case vogue
  case signet
  case almanac
  // The Studio Collection: nine deliberately unrelated visual systems rather
  // than variants of one masthead. Each also has a coordinated cover letter.
  case kintsugi
  case bauhaus
  case terminal
  case topograph
  case passport
  case transit
  case cutline
  case receipt
  case constellation

  var id: String { rawValue }

  /// Every template keeps a place for the portrait, so a photo is optional on all
  /// of them. These are the ones whose design is *built* around it: they draw the
  /// frame — initials inside it — before a photo is even picked. The rest close
  /// the space up and read exactly as they did when they had no photo at all.
  var isPhotoLed: Bool {
    switch self {
    case .portrait, .spotlight, .beacon, .harbor, .bloom, .atelier, .canvas, .atlas, .insignia,
      .nova, .monarch, .eclipse, .aperture, .gallery, .halo, .orbit, .panorama, .spectrum,
      .zenith, .alcove, .radiant, .zephyr, .vellum,
      .salute, .couture, .medallion, .sable, .terracotta, .circlet, .vogue:
      true
    case .passport, .cutline, .constellation:
      true
    default: false
    }
  }

  /// How the page itself is built. Everything not listed here flows one column
  /// down the page, which is the whole of the original catalogue — see
  /// `TemplatePlan`.
  var plan: TemplatePlan {
    switch self {
    case .atlas:
      TemplatePlan(
        body: .side(SideColumn(edge: .leading, width: 186, fill: .dark)),
        competencies: .chips,
        contact: .iconRows
      )
    case .verso:
      TemplatePlan(
        body: .side(SideColumn(edge: .trailing, width: 178, fill: .tint)),
        contact: .iconRows
      )
    case .oxford:
      TemplatePlan(
        body: .side(SideColumn(edge: .leading, width: 182, fill: .accent)),
        contact: .iconRows
      )
    case .chronicle:
      TemplatePlan(experience: .timeline, contact: .iconRows)
    case .gazette:
      TemplatePlan(experience: .dateGutter)
    case .strata:
      TemplatePlan(competencies: .chips, sectionChrome: .card)
    case .duo:
      TemplatePlan(
        body: .side(
          SideColumn(edge: .trailing, width: 190, fill: .none, startsBelowProfile: true)),
        competencies: .chips
      )
    case .signal:
      TemplatePlan(competencies: .iconGrid, contact: .iconRows)
    case .concise:
      TemplatePlan(
        body: .side(
          SideColumn(edge: .trailing, width: 176, fill: .none, startsBelowProfile: true)),
        competencies: .chips,
        density: 0.86
      )
    case .pivot:
      TemplatePlan(competencies: .chips, skillsFirst: true)
    case .noir:
      TemplatePlan(competencies: .chips, darkPaper: true)
    case .gauge:
      TemplatePlan(
        body: .side(SideColumn(edge: .trailing, width: 182, fill: .dark)),
        competencies: .meters,
        contact: .iconRows
      )
    case .folio:
      TemplatePlan(numberedSections: true)
    case .insignia:
      TemplatePlan(competencies: .chips)
    case .marquee:
      TemplatePlan(competencies: .chips, skillsFirst: true)
    case .metro:
      TemplatePlan(competencies: .chips, sectionChrome: .card)
    case .ivy:
      TemplatePlan(competencies: .columns)
    case .crest:
      TemplatePlan(
        body: .side(SideColumn(edge: .leading, width: 180, fill: .tint)),
        competencies: .chips,
        contact: .iconRows
      )
    case .geneva:
      TemplatePlan(
        body: .side(SideColumn(edge: .leading, width: 172, fill: .none, divider: true)),
        competencies: .meters,
        contact: .iconRows
      )
    case .plinth:
      TemplatePlan(competencies: .chips)
    // The catalogue drawn from the templates the web actually crowns: the
    // two-column the builder sites call their most-used, the timeline-dotted
    // double column, the one-page campus split, and the date-margin CV the
    // LaTeX crowd never let go of.
    case .stockholm:
      TemplatePlan(
        body: .side(SideColumn(edge: .trailing, width: 168, fill: .none)),
        competencies: .chips,
        contact: .iconRows
      )
    case .tandem:
      TemplatePlan(
        body: .side(SideColumn(edge: .trailing, width: 172, fill: .tint)),
        experience: .timeline,
        competencies: .chips,
        contact: .iconRows
      )
    case .varsity:
      TemplatePlan(
        body: .side(SideColumn(edge: .leading, width: 162, fill: .none)),
        competencies: .columns,
        density: 0.94
      )
    case .modena:
      TemplatePlan(experience: .dateGutter, competencies: .chips)
    case .nova:
      TemplatePlan(competencies: .chips)
    case .prism:
      TemplatePlan(
        body: .side(SideColumn(edge: .trailing, width: 178, fill: .accent)),
        competencies: .chips,
        contact: .iconRows
      )
    case .nocturne:
      TemplatePlan(darkPaper: true)
    // The art-led five. Each one moves something the others leave alone: the
    // letterhead into a disc, the name into an outline, the job title up the
    // page, the headings into the margin, the summary into the masthead.
    case .eclipse:
      TemplatePlan(competencies: .chips)
    case .contour:
      TemplatePlan(competencies: .chips)
    case .axis:
      TemplatePlan(competencies: .chips, bodyInset: 54)
    case .terrace:
      TemplatePlan(competencies: .chips, hangingHeadings: true)
    case .vantage:
      TemplatePlan(competencies: .chips, profileInHeader: true)
    case .apex:
      TemplatePlan(experience: .timeline, competencies: .chips, numberedSections: true)
    case .aperture:
      TemplatePlan(
        body: .side(SideColumn(edge: .leading, width: 184, fill: .tint, startsBelowProfile: true)),
        competencies: .chips,
        contact: .iconRows
      )
    case .arclight:
      TemplatePlan(experience: .dateGutter, competencies: .iconGrid, contact: .iconRows)
    case .blueprint:
      TemplatePlan(
        body: .side(SideColumn(edge: .trailing, width: 174, fill: .none, divider: true)),
        competencies: .columns,
        contact: .iconRows
      )
    case .catalyst:
      TemplatePlan(experience: .timeline, competencies: .meters, skillsFirst: true)
    case .circuit:
      TemplatePlan(
        body: .side(SideColumn(edge: .leading, width: 170, fill: .dark)),
        experience: .timeline,
        competencies: .meters,
        contact: .iconRows
      )
    case .continuum:
      TemplatePlan(experience: .dateGutter, competencies: .chips, numberedSections: true)
    case .district:
      TemplatePlan(
        body: .side(SideColumn(edge: .trailing, width: 184, fill: .tint)),
        experience: .timeline,
        competencies: .iconGrid,
        contact: .iconRows
      )
    case .ember:
      TemplatePlan(competencies: .chips, sectionChrome: .card, darkPaper: true)
    case .facet:
      TemplatePlan(
        body: .side(SideColumn(edge: .leading, width: 176, fill: .accent, startsBelowProfile: true)),
        competencies: .columns,
        contact: .iconRows
      )
    case .gallery:
      TemplatePlan(competencies: .iconGrid, sectionChrome: .card, numberedSections: true)
    case .halo:
      TemplatePlan(competencies: .chips, sectionChrome: .card, profileInHeader: true)
    case .helix:
      TemplatePlan(
        body: .side(SideColumn(edge: .trailing, width: 166, fill: .none)),
        experience: .timeline,
        competencies: .chips,
        numberedSections: true
      )
    case .kinetic:
      TemplatePlan(experience: .timeline, competencies: .iconGrid, numberedSections: true)
    case .lattice:
      TemplatePlan(
        body: .side(SideColumn(edge: .leading, width: 174, fill: .tint)),
        experience: .dateGutter,
        competencies: .meters,
        contact: .iconRows
      )
    case .nexus:
      TemplatePlan(competencies: .meters, sectionChrome: .card, skillsFirst: true)
    case .orbit:
      TemplatePlan(competencies: .chips, numberedSections: true, hangingHeadings: true)
    case .panorama:
      TemplatePlan(
        body: .side(SideColumn(edge: .trailing, width: 192, fill: .none, startsBelowProfile: true)),
        competencies: .columns,
        contact: .iconRows
      )
    case .quantum:
      TemplatePlan(
        body: .side(SideColumn(edge: .leading, width: 180, fill: .none, divider: true)),
        competencies: .iconGrid,
        contact: .iconRows,
        density: 0.92
      )
    case .ribbon:
      TemplatePlan(experience: .timeline, competencies: .chips, bodyInset: 28)
    case .runway:
      TemplatePlan(experience: .dateGutter, competencies: .meters, numberedSections: true)
    case .sentinel:
      TemplatePlan(
        body: .side(SideColumn(edge: .trailing, width: 178, fill: .dark)),
        competencies: .iconGrid,
        contact: .iconRows
      )
    case .spectrum:
      TemplatePlan(competencies: .chips, sectionChrome: .card, numberedSections: true)
    case .summit:
      TemplatePlan(competencies: .columns, skillsFirst: true, numberedSections: true)
    case .tessera:
      TemplatePlan(
        body: .side(SideColumn(edge: .leading, width: 190, fill: .tint)),
        competencies: .chips,
        sectionChrome: .card,
        contact: .iconRows
      )
    case .vault:
      TemplatePlan(competencies: .columns, numberedSections: true, darkPaper: true)
    case .wave:
      TemplatePlan(experience: .timeline, competencies: .chips, hangingHeadings: true)
    case .zenith:
      TemplatePlan(competencies: .chips, numberedSections: true, profileInHeader: true)
    case .alcove:
      TemplatePlan(
        body: .side(SideColumn(edge: .trailing, width: 176, fill: .accent, startsBelowProfile: true)),
        competencies: .meters,
        contact: .iconRows
      )
    case .sovereign:
      TemplatePlan(
        experience: .dateGutter,
        competencies: .columns,
        profileInHeader: true
      )
    case .palisade:
      TemplatePlan(
        body: .side(SideColumn(edge: .leading, width: 188, fill: .dark)),
        experience: .dateGutter,
        competencies: .chips,
        sectionChrome: .card,
        contact: .iconRows
      )
    case .volta:
      TemplatePlan(
        experience: .timeline,
        competencies: .meters,
        numberedSections: true,
        bodyInset: 42
      )
    // The Signature Collection page plans.
    case .obsidian:
      TemplatePlan(competencies: .chips, sectionChrome: .card, darkPaper: true)
    case .radiant:
      TemplatePlan(competencies: .chips, profileInHeader: true)
    case .verge:
      TemplatePlan(competencies: .columns)
    case .datum:
      TemplatePlan(competencies: .meters, numberedSections: true)
    case .pinnacle:
      TemplatePlan(competencies: .columns, numberedSections: true)
    case .cobalt:
      TemplatePlan(competencies: .chips, sectionChrome: .card)
    case .equinox:
      TemplatePlan(competencies: .columns)
    case .mirage:
      TemplatePlan(competencies: .chips)
    case .parallax:
      TemplatePlan(competencies: .chips, sectionChrome: .card)
    case .emblem:
      TemplatePlan(competencies: .chips)
    case .cadence:
      TemplatePlan(experience: .timeline, competencies: .meters)
    case .citadel:
      TemplatePlan(experience: .dateGutter, competencies: .columns)
    case .atrium:
      TemplatePlan(competencies: .chips)
    case .zephyr:
      TemplatePlan(competencies: .chips, profileInHeader: true)
    case .cinder:
      TemplatePlan(competencies: .chips, sectionChrome: .card, darkPaper: true)
    case .keystone:
      TemplatePlan(competencies: .columns, numberedSections: true)
    case .loom:
      TemplatePlan(competencies: .chips)
    case .graphite:
      TemplatePlan(competencies: .columns, density: 0.94)
    case .stratus:
      TemplatePlan(competencies: .chips)
    case .vellum:
      TemplatePlan(experience: .dateGutter, competencies: .columns)
    // The Showcase Collection.
    case .salute:
      // Greeting masthead, then a quiet facts column beside ranked skills.
      TemplatePlan(
        body: .side(SideColumn(edge: .leading, width: 176, fill: .none, divider: true)),
        competencies: .meters, skillsFirst: true)
    case .couture:
      // Fashion editorial: dates hang in the margin, skills read as a set.
      TemplatePlan(experience: .dateGutter, competencies: .columns)
    case .medallion:
      // Monogram hero over a two-column page rated in dots.
      TemplatePlan(
        body: .side(SideColumn(edge: .leading, width: 178, fill: .none, divider: true)),
        competencies: .dots)
    case .sable:
      // Dark facts column with icon rows, story on the light side.
      TemplatePlan(
        body: .side(SideColumn(edge: .leading, width: 186, fill: .dark)),
        competencies: .dots, contact: .iconRows, skillsFirst: true)
    case .terracotta:
      // Earthen masthead, timeline roles, ranked strengths in the margin column.
      TemplatePlan(
        body: .side(SideColumn(edge: .trailing, width: 168, fill: .none, divider: true)),
        experience: .timeline, competencies: .meters)
    case .lozenge:
      // Airy single column; the pill labels and dot ratings carry the look.
      TemplatePlan(competencies: .dots, sectionChrome: .card)
    case .circlet:
      // Ringed portrait hero, dot-rated skills lead the page.
      TemplatePlan(competencies: .dots, skillsFirst: true)
    case .vogue:
      // Oversized serif editorial with dates hung in the margin.
      TemplatePlan(experience: .dateGutter, competencies: .columns)
    case .signet:
      // Centred classic beneath a seal; strengths rated in dots.
      TemplatePlan(competencies: .dots)
    case .almanac:
      // Infographic fact strip; carded sections and dot-rated strengths.
      TemplatePlan(competencies: .dots, sectionChrome: .card, skillsFirst: true)
    // The Studio Collection changes the page below the letterhead as strongly as
    // the art above it. These plans intentionally combine layout axes that no
    // existing template combines, so the nine remain distinct with long content.
    case .kintsugi:
      TemplatePlan(
        experience: .dateGutter, competencies: .columns, numberedSections: true,
        density: 0.97)
    case .bauhaus:
      TemplatePlan(
        body: .side(
          SideColumn(edge: .leading, width: 164, fill: .accent, startsBelowProfile: true)),
        competencies: .dots, sectionChrome: .card, contact: .iconRows)
    case .terminal:
      TemplatePlan(
        experience: .timeline, competencies: .columns, numberedSections: true,
        darkPaper: true, density: 0.90)
    case .topograph:
      TemplatePlan(
        competencies: .chips, numberedSections: true, hangingHeadings: true,
        bodyInset: 32)
    case .passport:
      TemplatePlan(
        body: .side(SideColumn(edge: .trailing, width: 182, fill: .tint)),
        experience: .dateGutter, competencies: .iconGrid, contact: .iconRows)
    case .transit:
      TemplatePlan(
        experience: .timeline, competencies: .iconGrid, numberedSections: true,
        bodyInset: 38)
    case .cutline:
      TemplatePlan(
        experience: .dateGutter, competencies: .dots, profileInHeader: true,
        density: 0.96)
    case .receipt:
      TemplatePlan(
        competencies: .columns, skillsFirst: true, numberedSections: true,
        density: 0.82)
    case .constellation:
      TemplatePlan(
        experience: .timeline, competencies: .dots, sectionChrome: .card,
        numberedSections: true, darkPaper: true, profileInHeader: true)
    default:
      TemplatePlan()
    }
  }

  var title: String {
    if let advancedStyle { return advancedStyle.title }
    return switch self {
    case .atlas: "Atlas Sidebar"
    case .verso: "Verso Panel"
    case .oxford: "Oxford Column"
    case .chronicle: "Chronicle Timeline"
    case .gazette: "Gazette Margins"
    case .strata: "Strata Cards"
    case .duo: "Duo Columns"
    case .signal: "Signal Icons"
    case .concise: "Concise Duo"
    case .pivot: "Pivot Skills-First"
    case .portrait: "Portrait Executive"
    case .spotlight: "Spotlight Profile"
    case .beacon: "Beacon Badge"
    case .harbor: "Harbor Split"
    case .bloom: "Bloom Card"
    case .atelier: "Atelier Bold"
    case .canvas: "Canvas Split"
    case .modern: "Modern Executive"
    case .aurora: "Aurora Gradient"
    case .slate: "Slate Panel"
    case .onyx: "Onyx Contrast"
    case .minimal: "Clean Minimal"
    case .lumen: "Lumen Light"
    case .nordic: "Nordic Air"
    case .cascade: "Cascade Steps"
    case .contemporary: "Contemporary Split"
    case .horizon: "Horizon Modern"
    case .vector: "Vector Grid"
    case .technical: "Tech Grid"
    case .creative: "Creative Blocks"
    case .mosaic: "Mosaic Tiles"
    case .vertex: "Vertex Angle"
    case .timeline: "Timeline Focus"
    case .compact: "Compact Pro"
    case .corporate: "Corporate Slate"
    case .meridian: "Meridian Rail"
    case .classic: "Classic Editorial"
    case .elegant: "Elegant Serif"
    case .linen: "Linen Press"
    case .ledger: "Ledger Frame"
    case .quill: "Quill Manuscript"
    case .academic: "Academic CV"
    case .monochrome: "Monochrome Ink"
    case .editorial: "Editorial Column"
    case .noir: "Noir Ink"
    case .gauge: "Gauge Sidebar"
    case .folio: "Folio Numbered"
    case .insignia: "Insignia Monogram"
    case .marquee: "Marquee Type"
    case .metro: "Metro Blocks"
    case .ivy: "Ivy League"
    case .crest: "Crest Banner"
    case .geneva: "Geneva Split"
    case .plinth: "Plinth Footer"
    case .stockholm: "Stockholm Duet"
    case .tandem: "Tandem Rail"
    case .varsity: "Varsity One-Page"
    case .laureate: "Laureate Standard"
    case .modena: "Modena Margin"
    case .nova: "Nova Banner"
    case .prism: "Prism Panel"
    case .aurelia: "Aurelia Fine Serif"
    case .nocturne: "Nocturne Serif"
    case .monarch: "Monarch Executive"
    case .eclipse: "Eclipse Arc"
    case .contour: "Contour Outline"
    case .axis: "Axis Spine"
    case .terrace: "Terrace Margins"
    case .vantage: "Vantage Hero"
    default: rawValue.capitalized
    }
  }

  var subtitle: String {
    if let advancedStyle { return advancedStyle.subtitle }
    return switch self {
    case .atlas: "Dark sidebar: photo, contact icons, skill pills"
    case .verso: "Quiet panel down the right for the scannable facts"
    case .oxford: "Full-colour column beside a serif page"
    case .chronicle: "A rail through the roles, dated at every stop"
    case .gazette: "Dates hang in the margin, roles in the column"
    case .strata: "Every entry in its own bordered card"
    case .duo: "Summary across the top, then two columns"
    case .signal: "Icon contact strip and a ticked skills matrix"
    case .concise: "Compressed two-column that buys back a page"
    case .pivot: "Skills lead, experience follows"
    case .portrait: "Photo header with a ringed portrait"
    case .spotlight: "Centred portrait above a clean page"
    case .beacon: "Oversized accent badge beside the name"
    case .harbor: "Portrait straddling a two-tone horizon"
    case .bloom: "Soft rounded card with a friendly portrait"
    case .atelier: "Colour block with an overhanging portrait"
    case .canvas: "Two-tone panel, portrait on the seam"
    case .modern: "Bold header and crisp section rules"
    case .aurora: "Gradient letterhead that fades to ink"
    case .slate: "Deep charcoal panel with an accent edge"
    case .onyx: "Condensed caps on a full black band"
    case .minimal: "Airy layout with subtle accents"
    case .lumen: "Featherweight type and wide letter spacing"
    case .nordic: "Generous whitespace and quiet detail"
    case .cascade: "Stepped accent bars under the name"
    case .contemporary: "Asymmetric header with a split accent"
    case .horizon: "Clean split letterhead with a strong horizon line"
    case .vector: "Dot-grid letterhead with squared corners"
    case .technical: "Precise lines and modern technical type"
    case .creative: "Playful geometry with confident contrast"
    case .mosaic: "Tiled accent squares and geometric type"
    case .vertex: "Diagonal accent wedge and sharp angles"
    case .timeline: "Career storytelling with timeline details"
    case .compact: "Dense, recruiter-friendly information"
    case .corporate: "Structured bands for leadership roles"
    case .meridian: "Full-height accent rail down every page"
    case .classic: "Serif typography and timeless spacing"
    case .elegant: "Refined type with understated ornament"
    case .linen: "Warm tinted letterhead in a book serif"
    case .ledger: "Ruled frame around a printed page"
    case .quill: "Old-style serif with a printer's ornament"
    case .academic: "Formal scholarly typography and hierarchy"
    case .monochrome: "Black-and-white editorial confidence"
    case .editorial: "Magazine-inspired type with a refined side rule"
    case .noir: "Light ink on a full dark page"
    case .gauge: "Dark side column with ranked skill meters"
    case .folio: "Editorial sections counted off 01, 02, 03"
    case .insignia: "Initials set as a logo tile letterhead"
    case .marquee: "Your name set like a headline"
    case .metro: "Solid colour blocks head every section"
    case .ivy: "The plain serif format recruiters recommend"
    case .crest: "Full-width banner over a tinted column"
    case .geneva: "Hairline split, meters and Swiss whitespace"
    case .plinth: "Contact lives in a colour footer band"
    case .stockholm: "The web's best-loved duet: facts beside the story"
    case .tandem: "A dotted rail through the roles, tinted column beside"
    case .varsity: "The campus one-pager: asymmetric, tight, complete"
    case .laureate: "Two-tone name over award-list rules"
    case .modena: "The scholar's margin: dates hang left of every role"
    case .nova: "Colour banner, icon strip and a squared portrait"
    case .prism: "A full accent column carries the scannable facts"
    case .aurelia: "Fine serif, wide letterspacing, ornament rules"
    case .nocturne: "A book serif set on the dark page"
    case .monarch: "Navy letterhead with a squared executive portrait"
    case .eclipse: "A colour disc off the corner, portrait crossing it"
    case .contour: "Surname in hollow outline, the page left to breathe"
    case .axis: "Your title set vertically up a full-height spine"
    case .terrace: "Headings hang in the margin, text keeps its measure"
    case .vantage: "The summary set inside a full-bleed hero panel"
    default: "Art-directed résumé layout"
    }
  }

  var systemImage: String {
    if let advancedStyle { return advancedStyle.systemImage }
    return switch self {
    case .atlas: "sidebar.left"
    case .verso: "sidebar.right"
    case .oxford: "book.and.wrench"
    case .chronicle: "point.topleft.down.to.point.bottomright.curvepath"
    case .gazette: "calendar.day.timeline.left"
    case .strata: "square.stack.3d.up.fill"
    case .duo: "rectangle.split.2x2"
    case .signal: "checkmark.seal.fill"
    case .concise: "arrow.down.right.and.arrow.up.left"
    case .pivot: "arrow.triangle.swap"
    case .portrait: "person.crop.circle.fill"
    case .spotlight: "person.crop.circle.badge.checkmark"
    case .beacon: "seal.fill"
    case .harbor: "water.waves"
    case .bloom: "camera.macro"
    case .atelier: "paintpalette.fill"
    case .canvas: "rectangle.lefthalf.inset.filled"
    case .modern: "rectangle.topthird.inset.filled"
    case .aurora: "sun.horizon.fill"
    case .slate: "rectangle.inset.filled"
    case .onyx: "diamond.fill"
    case .minimal: "rectangle.inset.filled.and.person.filled"
    case .lumen: "sparkle"
    case .nordic: "leaf.fill"
    case .cascade: "stairs"
    case .contemporary: "rectangle.split.2x1.fill"
    case .horizon: "rectangle.split.1x2.fill"
    case .vector: "circle.grid.3x3.fill"
    case .technical: "chevron.left.forwardslash.chevron.right"
    case .creative: "square.grid.2x2.fill"
    case .mosaic: "square.grid.3x3.square"
    case .vertex: "triangle.fill"
    case .timeline: "list.bullet.indent"
    case .compact: "list.bullet.rectangle.fill"
    case .corporate: "building.2.fill"
    case .meridian: "rectangle.leftthird.inset.filled"
    case .classic: "text.book.closed.fill"
    case .elegant: "textformat"
    case .linen: "doc.richtext"
    case .ledger: "book.closed.fill"
    case .quill: "pencil.and.outline"
    case .academic: "graduationcap.fill"
    case .monochrome: "circle.lefthalf.filled"
    case .editorial: "newspaper.fill"
    case .noir: "moon.fill"
    case .gauge: "gauge.with.dots.needle.67percent"
    case .folio: "number.square.fill"
    case .insignia: "person.crop.square.fill"
    case .marquee: "textformat.size"
    case .metro: "squares.below.rectangle"
    case .ivy: "building.columns.fill"
    case .crest: "flag.fill"
    case .geneva: "square.split.2x1"
    case .plinth: "dock.rectangle"
    case .stockholm: "rectangle.righthalf.inset.filled"
    case .tandem: "list.bullet.below.rectangle"
    case .varsity: "rectangle.split.2x1"
    case .laureate: "laurel.leading"
    case .modena: "increase.indent"
    case .nova: "person.crop.rectangle.fill"
    case .prism: "square.split.2x1.fill"
    case .aurelia: "diamond"
    case .nocturne: "moon.stars.fill"
    case .monarch: "crown.fill"
    case .eclipse: "circle.circle.fill"
    case .contour: "character.textbox"
    case .axis: "arrow.up.and.line.horizontal.and.arrow.down"
    case .terrace: "text.alignleft"
    case .vantage: "rectangle.tophalf.inset.filled"
    default: "doc.richtext.fill"
    }
  }

  var styleTags: Set<TemplateStyleTag> {
    if let advancedStyle { return advancedStyle.styleTags }
    return switch self {
    // The structural ten. Only Gazette claims ATS: a second column of text stays
    // selectable, but some parsers read the columns out of order, and saying
    // otherwise would be selling a template on a promise it cannot keep.
    case .atlas: [.structured, .modern, .bold, .photo]
    case .verso: [.structured, .modern, .clean]
    case .oxford: [.structured, .classic, .bold]
    case .chronicle: [.structured, .modern, .creative]
    case .gazette: [.structured, .classic, .clean, .ats]
    case .strata: [.structured, .modern, .creative]
    case .duo: [.structured, .modern, .clean]
    case .signal: [.structured, .modern, .creative]
    case .concise: [.structured, .clean]
    case .pivot: [.structured, .modern, .bold]
    case .portrait: [.modern, .bold, .photo]
    case .spotlight: [.modern, .clean, .photo]
    case .beacon: [.bold, .modern, .photo]
    case .harbor: [.modern, .clean, .photo]
    case .bloom: [.clean, .creative, .photo]
    case .atelier: [.bold, .creative, .photo]
    case .canvas: [.modern, .creative, .photo]
    case .modern: [.modern, .bold, .ats]
    case .aurora: [.modern, .bold, .creative]
    case .slate: [.modern, .bold, .ats]
    case .onyx: [.bold, .modern]
    case .minimal: [.modern, .clean, .ats]
    case .lumen: [.clean, .modern, .ats]
    case .nordic: [.modern, .clean]
    case .cascade: [.modern, .creative]
    case .contemporary: [.modern, .creative]
    case .horizon: [.modern, .clean, .bold, .ats]
    case .vector: [.modern, .creative, .clean]
    case .technical: [.modern, .clean, .ats]
    case .creative: [.bold, .creative]
    case .mosaic: [.creative, .bold]
    case .vertex: [.creative, .bold]
    case .timeline: [.modern, .creative]
    case .compact: [.clean, .ats]
    case .corporate: [.classic, .bold, .ats]
    case .meridian: [.classic, .clean]
    case .classic: [.classic, .clean, .ats]
    case .elegant: [.classic, .clean]
    case .linen: [.classic, .clean]
    case .ledger: [.classic, .bold, .ats]
    case .quill: [.classic, .clean, .ats]
    case .academic: [.classic, .ats]
    case .monochrome: [.classic, .clean, .ats]
    case .editorial: [.classic, .bold, .creative]
    // The ten drawn from the templates the internet actually rates: the dark
    // page, the metered sidebar, the numbered folio, the monogram logo, the
    // oversized headline, the colour blocks, the recruiter's plain serif, the
    // banner-and-column, the Swiss split, and the footer that carries contact.
    case .noir: [.bold, .creative, .modern]
    case .gauge: [.structured, .modern, .bold]
    case .folio: [.creative, .classic, .bold]
    case .insignia: [.modern, .clean, .photo]
    case .marquee: [.bold, .creative, .modern]
    case .metro: [.modern, .bold, .creative]
    case .ivy: [.classic, .clean, .ats]
    case .crest: [.structured, .bold, .modern]
    case .geneva: [.structured, .clean, .modern]
    case .plinth: [.modern, .clean, .bold]
    // The ten modelled on the most-reviewed formats on the web: the builder
    // sites' favourite duet, the timeline double column, the campus one-pager,
    // the LaTeX classics, the banner-and-portrait, and the luxe serifs.
    case .stockholm: [.structured, .modern, .clean]
    case .tandem: [.structured, .modern, .creative]
    case .varsity: [.structured, .clean]
    case .laureate: [.classic, .modern, .ats]
    case .modena: [.structured, .classic, .ats]
    case .nova: [.modern, .bold, .photo]
    case .prism: [.structured, .bold, .creative]
    case .aurelia: [.classic, .clean, .creative]
    case .nocturne: [.bold, .classic, .creative]
    case .monarch: [.classic, .bold, .photo]
    // The art-led five. Only Terrace claims structure: it is the one that moves
    // the content rather than the letterhead, and its single measure of text
    // keeps it readable to a parser even with the headings out in the margin.
    case .eclipse: [.creative, .modern, .bold, .photo]
    case .contour: [.creative, .modern, .clean]
    case .axis: [.bold, .creative, .modern]
    case .terrace: [.structured, .clean, .modern]
    case .vantage: [.bold, .modern, .creative]
    default: [.modern, .creative]
    }
  }

  /// Metadata for the Advanced Collection. `ordinal` drives a four-by-eight
  /// family of mastheads in the PDF and loading artwork; the copy and page plans
  /// remain individually authored above, so no two catalogue entries collapse
  /// to the same design.
  var advancedStyle: AdvancedResumeStyle? {
    switch self {
    case .apex:
      AdvancedResumeStyle(0, "Apex Command", "Numbered career rail with a precision masthead", "mountain.2.fill", [.structured, .bold, .modern])
    case .aperture:
      AdvancedResumeStyle(1, "Aperture Profile", "Portrait aperture over a cinematic facts column", "camera.aperture", [.structured, .photo, .creative, .modern])
    case .arclight:
      AdvancedResumeStyle(2, "Arclight Grid", "Luminous arc header with dated editorial margins", "light.beacon.max.fill", [.structured, .modern, .clean])
    case .blueprint:
      AdvancedResumeStyle(3, "Blueprint Studio", "Technical split grid with a measured information rail", "ruler.fill", [.structured, .clean, .ats])
    case .catalyst:
      AdvancedResumeStyle(4, "Catalyst Motion", "Skills-first meters accelerate into a career timeline", "bolt.horizontal.circle.fill", [.structured, .bold, .modern])
    case .circuit:
      AdvancedResumeStyle(5, "Circuit Director", "Dark systems column with connected role milestones", "point.3.connected.trianglepath.dotted", [.structured, .bold, .modern])
    case .continuum:
      AdvancedResumeStyle(6, "Continuum Ledger", "Numbered chronology flowing through generous margins", "infinity", [.structured, .classic, .clean])
    case .district:
      AdvancedResumeStyle(7, "District Timeline", "Urban two-column grid with a guided career rail", "building.2.crop.circle.fill", [.structured, .modern, .creative])
    case .ember:
      AdvancedResumeStyle(8, "Ember Atelier", "Warm illuminated cards on dramatic dark paper", "flame.fill", [.structured, .bold, .creative])
    case .facet:
      AdvancedResumeStyle(9, "Facet Column", "Gem-cut colour panel beneath a full-width opening", "diamond.inset.filled", [.structured, .bold, .creative])
    case .gallery:
      AdvancedResumeStyle(10, "Gallery Portrait", "Curated profile frame with numbered exhibit cards", "photo.artframe", [.structured, .photo, .creative])
    case .halo:
      AdvancedResumeStyle(11, "Halo Signature", "Orbit portrait and profile share a sculpted masthead", "circle.dotted.circle.fill", [.structured, .photo, .modern])
    case .helix:
      AdvancedResumeStyle(12, "Helix Narrative", "Interlocking timeline and facts column tell one story", "waveform.path.ecg.rectangle.fill", [.structured, .modern, .creative])
    case .kinetic:
      AdvancedResumeStyle(13, "Kinetic Matrix", "Numbered movement grid with checked strengths", "wind", [.structured, .bold, .modern])
    case .lattice:
      AdvancedResumeStyle(14, "Lattice Scholar", "Dated roles and ranked strengths in a refined lattice", "square.grid.3x3.fill", [.structured, .classic, .clean])
    case .nexus:
      AdvancedResumeStyle(15, "Nexus Cards", "Skills command centre above modular experience cards", "circle.grid.cross.fill", [.structured, .modern, .bold])
    case .orbit:
      AdvancedResumeStyle(16, "Orbit Editorial", "Portrait orbit with headings suspended in the margin", "circle.hexagongrid.fill", [.structured, .photo, .creative])
    case .panorama:
      AdvancedResumeStyle(17, "Panorama Split", "Wide opening statement above an asymmetric duet", "rectangle.split.3x1.fill", [.structured, .photo, .modern])
    case .quantum:
      AdvancedResumeStyle(18, "Quantum Grid", "Compressed Swiss divider with a verified skill matrix", "atom", [.structured, .modern, .clean])
    case .ribbon:
      AdvancedResumeStyle(19, "Ribbon Career", "Folded page ribbon beside a continuous role rail", "bookmark.square.fill", [.structured, .modern, .creative])
    case .runway:
      AdvancedResumeStyle(20, "Runway Metrics", "Executive runway of dated roles and ranked expertise", "arrow.up.right", [.structured, .bold, .modern])
    case .sentinel:
      AdvancedResumeStyle(21, "Sentinel Panel", "Commanding dark facts panel with verified strengths", "shield.lefthalf.filled", [.structured, .bold, .modern])
    case .spectrum:
      AdvancedResumeStyle(22, "Spectrum Portrait", "Colour-spectrum portrait masthead over numbered cards", "rainbow", [.structured, .photo, .creative])
    case .summit:
      AdvancedResumeStyle(23, "Summit Brief", "Skills-first executive one-pager with numbered sections", "flag.pattern.checkered", [.structured, .clean, .ats])
    case .tessera:
      AdvancedResumeStyle(24, "Tessera Mosaic", "Soft mosaic column and precise modular experience cards", "square.grid.4x3.fill", [.structured, .creative, .modern])
    case .vault:
      AdvancedResumeStyle(25, "Vault Monograph", "Numbered editorial typography on a midnight sheet", "lock.square.stack.fill", [.structured, .bold, .classic])
    case .wave:
      AdvancedResumeStyle(26, "Wave Narrative", "Flowing career line with terrace-style side headings", "water.waves", [.structured, .creative, .modern])
    case .zenith:
      AdvancedResumeStyle(27, "Zenith Executive", "Portrait, profile and numbered hierarchy in one hero", "crown.fill", [.structured, .photo, .bold])
    case .alcove:
      AdvancedResumeStyle(28, "Alcove Portrait", "Intimate portrait panel with ranked expertise", "rectangle.portrait.inset.filled", [.structured, .photo, .modern])
    case .sovereign:
      AdvancedResumeStyle(29, "Sovereign Editorial", "Full-bleed profile with stately date-led typography", "seal.fill", [.structured, .classic, .bold])
    case .palisade:
      AdvancedResumeStyle(30, "Palisade Command", "Fortified dark column beside executive role cards", "rectangle.3.group.fill", [.structured, .bold, .classic])
    case .volta:
      AdvancedResumeStyle(31, "Volta Energy", "Electric spine, ranked strengths and numbered milestones", "bolt.ring.closed", [.structured, .bold, .creative])
    // The Signature Collection: mastheads 8-15, addressed explicitly rather than
    // through the ordinal-modulo scheme the first thirty-two use. The ordinal is
    // kept unique so the running "NN / PAGE" mark never repeats.
    case .obsidian:
      AdvancedResumeStyle(motif: 12, variant: 0, ordinal: 32, "Obsidian Layers", "Stacked glass panels on a midnight masthead", "square.stack.3d.down.right.fill", [.bold, .modern, .creative])
    case .radiant:
      AdvancedResumeStyle(motif: 9, variant: 0, ordinal: 33, "Radiant Halo", "A radial glow crowns the portrait and profile", "sun.max.fill", [.modern, .creative, .photo])
    case .verge:
      AdvancedResumeStyle(motif: 8, variant: 0, ordinal: 34, "Verge Duotone", "A two-tone diagonal split behind a bold name", "triangle.righthalf.filled", [.bold, .modern])
    case .datum:
      AdvancedResumeStyle(motif: 10, variant: 0, ordinal: 35, "Datum Metrics", "Headline metrics tiled beneath the masthead", "chart.bar.doc.horizontal.fill", [.modern, .clean, .bold])
    case .pinnacle:
      AdvancedResumeStyle(motif: 14, variant: 0, ordinal: 36, "Pinnacle Executive", "An architected frame and a keystone crest", "building.columns.fill", [.classic, .bold])
    case .cobalt:
      AdvancedResumeStyle(motif: 8, variant: 1, ordinal: 37, "Cobalt Blocks", "Bold offset colour blocks and clean type", "square.split.diagonal.fill", [.bold, .modern, .creative])
    case .equinox:
      AdvancedResumeStyle(motif: 8, variant: 2, ordinal: 38, "Equinox Split", "Light and shadow meet along the centre line", "circle.righthalf.filled", [.modern, .clean])
    case .mirage:
      AdvancedResumeStyle(motif: 15, variant: 0, ordinal: 39, "Mirage Gradient", "Soft stratus gradient bands as a masthead", "aqi.medium", [.modern, .creative])
    case .parallax:
      AdvancedResumeStyle(motif: 12, variant: 1, ordinal: 40, "Parallax Depth", "Offset layered panels create real depth", "rectangle.stack.fill", [.modern, .bold, .creative])
    case .emblem:
      AdvancedResumeStyle(motif: 11, variant: 0, ordinal: 41, "Emblem Monogram", "A hexagon monogram anchors the letterhead", "hexagon.fill", [.bold, .modern, .clean])
    case .cadence:
      AdvancedResumeStyle(motif: 13, variant: 0, ordinal: 42, "Cadence Rhythm", "An equaliser of accent bars sets the beat", "waveform", [.modern, .creative, .bold])
    case .citadel:
      AdvancedResumeStyle(motif: 14, variant: 1, ordinal: 43, "Citadel Command", "Fortress framing for leadership résumés", "building.2.fill", [.classic, .bold])
    case .atrium:
      AdvancedResumeStyle(motif: 15, variant: 1, ordinal: 44, "Atrium Light", "An airy stratus wash and generous white space", "sun.horizon.fill", [.clean, .modern])
    case .zephyr:
      AdvancedResumeStyle(motif: 9, variant: 1, ordinal: 45, "Zephyr Glow", "A feather-light halo over a calm profile", "wind", [.clean, .modern, .photo])
    case .cinder:
      AdvancedResumeStyle(motif: 12, variant: 2, ordinal: 46, "Cinder Ember", "Warm ember panels on a dramatic dark sheet", "flame.circle.fill", [.bold, .creative])
    case .keystone:
      AdvancedResumeStyle(motif: 14, variant: 2, ordinal: 47, "Keystone Arch", "A keystone crowns the numbered sections", "triangle.fill", [.classic, .clean])
    case .loom:
      AdvancedResumeStyle(motif: 13, variant: 1, ordinal: 48, "Loom Weave", "Woven accent lines thread the masthead", "square.grid.3x3.middle.filled", [.creative, .modern])
    case .graphite:
      AdvancedResumeStyle(motif: 11, variant: 1, ordinal: 49, "Graphite Matte", "A matte monogram tile and quiet precision", "hexagon", [.clean, .modern, .ats])
    case .stratus:
      AdvancedResumeStyle(motif: 15, variant: 2, ordinal: 50, "Stratus Drift", "Layered cloud bands drift behind the name", "cloud.fill", [.clean, .modern, .creative])
    case .vellum:
      AdvancedResumeStyle(motif: 9, variant: 2, ordinal: 51, "Vellum Press", "A warm halo on pressed editorial paper", "doc.richtext.fill", [.classic, .clean, .photo])
    // The Showcase Collection: mastheads 16-25, each a bespoke construction.
    case .salute:
      AdvancedResumeStyle(motif: 16, variant: 0, ordinal: 52, "Salute Greeting", "A warm hello, a round portrait and ranked skills", "hand.wave.fill", [.showcase, .modern, .clean, .photo])
    case .couture:
      AdvancedResumeStyle(motif: 17, variant: 1, ordinal: 53, "Couture Vertical", "A tall name up the page beside a fashion portrait", "textformat.abc.dottedunderline", [.showcase, .creative, .photo, .bold])
    case .medallion:
      AdvancedResumeStyle(motif: 18, variant: 0, ordinal: 54, "Medallion Monogram", "A circular monogram seal, big portrait and dot ratings", "seal.fill", [.showcase, .creative, .photo, .modern])
    case .sable:
      AdvancedResumeStyle(motif: 19, variant: 0, ordinal: 55, "Sable Sidebar", "A dark facts column with icons beside a bright story", "sidebar.left", [.showcase, .bold, .photo, .modern])
    case .terracotta:
      AdvancedResumeStyle(motif: 20, variant: 2, ordinal: 56, "Terracotta Circle", "A warm earthen masthead and a bold profile circle", "circle.circle.fill", [.showcase, .creative, .classic, .photo])
    case .lozenge:
      AdvancedResumeStyle(motif: 21, variant: 0, ordinal: 57, "Lozenge Pills", "Capsule section labels over an airy two-column page", "capsule.portrait.fill", [.showcase, .clean, .modern])
    case .circlet:
      AdvancedResumeStyle(motif: 22, variant: 0, ordinal: 58, "Circlet Orbit", "A ringed portrait with orbiting rated skills", "circle.dashed.inset.filled", [.showcase, .photo, .creative, .modern])
    case .vogue:
      AdvancedResumeStyle(motif: 23, variant: 1, ordinal: 59, "Vogue Editorial", "Oversized serif name, hairline rules, margin labels", "textformat.size.larger", [.showcase, .creative, .classic, .bold])
    case .signet:
      AdvancedResumeStyle(motif: 24, variant: 0, ordinal: 60, "Signet Seal", "A pressed wax-seal monogram over a centred classic", "checkmark.seal.fill", [.showcase, .classic, .clean])
    case .almanac:
      AdvancedResumeStyle(motif: 25, variant: 0, ordinal: 61, "Almanac Infographic", "An icon-led fact strip with dot-rated strengths", "chart.bar.xaxis", [.showcase, .modern, .creative, .bold])
    // The Studio Collection owns motifs 26-34. Unlike earlier collection
    // variants, every motif has dedicated PDF and loading artwork.
    case .kintsugi:
      AdvancedResumeStyle(motif: 26, variant: 0, ordinal: 62, "Kintsugi Gold", "Warm editorial paper repaired with a fractured gold seam", "scribble.variable", [.studio, .structured, .classic, .creative, .ats])
    case .bauhaus:
      AdvancedResumeStyle(motif: 27, variant: 1, ordinal: 63, "Bauhaus Signal", "Primary geometry turns the facts column into a graphic poster", "circle.square.fill", [.studio, .structured, .bold, .creative])
    case .terminal:
      AdvancedResumeStyle(motif: 28, variant: 2, ordinal: 64, "Terminal Command", "A dark command-line résumé with a live career prompt", "terminal.fill", [.studio, .structured, .bold, .modern, .ats])
    case .topograph:
      AdvancedResumeStyle(motif: 29, variant: 0, ordinal: 65, "Topograph Field", "Contour lines and map coordinates guide margin headings", "map.fill", [.studio, .structured, .clean, .creative, .ats])
    case .passport:
      AdvancedResumeStyle(motif: 30, variant: 1, ordinal: 66, "Passport Profile", "An identity dossier with stamps, portrait and travel-document precision", "person.text.rectangle.fill", [.studio, .structured, .photo, .creative])
    case .transit:
      AdvancedResumeStyle(motif: 31, variant: 3, ordinal: 67, "Transit Map", "Connected stations turn experience into a navigable career route", "point.3.filled.connected.trianglepath.dotted", [.studio, .structured, .modern, .creative])
    case .cutline:
      AdvancedResumeStyle(motif: 32, variant: 0, ordinal: 68, "Cutline Editorial", "A cropped portrait and diagonal byline cut through oversized type", "scissors", [.studio, .structured, .photo, .bold, .creative])
    case .receipt:
      AdvancedResumeStyle(motif: 33, variant: 2, ordinal: 69, "Receipt One-Page", "A compact proof-of-work strip inspired by a printed receipt", "scroll.fill", [.studio, .structured, .clean, .modern, .ats])
    case .constellation:
      AdvancedResumeStyle(motif: 34, variant: 3, ordinal: 70, "Constellation Story", "A midnight network maps the people, roles and strengths in your orbit", "sparkles", [.studio, .structured, .photo, .bold, .creative])
    default:
      nil
    }
  }
}

struct AdvancedResumeStyle {
  let ordinal: Int
  let title: String
  let subtitle: String
  let systemImage: String
  let styleTags: Set<TemplateStyleTag>

  /// The first thirty-two derive motif and variant from `ordinal`; the Signature
  /// Collection sets them outright so it can reach mastheads 8-15 without
  /// disturbing that scheme. Absent overrides leave the original behaviour intact.
  private let motifOverride: Int?
  private let variantOverride: Int?

  init(
    _ ordinal: Int,
    _ title: String,
    _ subtitle: String,
    _ systemImage: String,
    _ styleTags: Set<TemplateStyleTag>
  ) {
    self.ordinal = ordinal
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.styleTags = styleTags
    self.motifOverride = nil
    self.variantOverride = nil
  }

  init(
    motif: Int,
    variant: Int,
    ordinal: Int,
    _ title: String,
    _ subtitle: String,
    _ systemImage: String,
    _ styleTags: Set<TemplateStyleTag>
  ) {
    self.ordinal = ordinal
    self.title = title
    self.subtitle = subtitle
    self.systemImage = systemImage
    self.styleTags = styleTags
    self.motifOverride = motif
    self.variantOverride = variant
  }

  /// The original sixteen constructions use variants; motifs 16-34 are bespoke
  /// Showcase and Studio designs. The renderer uses both values.
  var motif: Int { motifOverride ?? (ordinal % 8) }
  var variant: Int { variantOverride ?? (ordinal / 8) }
  var headerHeight: CGFloat {
    let heights: [CGFloat] = [
      158, 176, 166, 154, 184, 170, 162, 188,
      178, 172, 168, 164, 182, 174, 170, 180,
      178, 210, 174, 186, 192, 182, 204, 184, 198,
    ]
    return heights[min(max(motif, 0), heights.count - 1)] + CGFloat(variant * 3)
  }
}
