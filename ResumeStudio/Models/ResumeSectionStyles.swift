import Foundation

/// Section styles the user has chosen for themselves, overriding the ones their
/// template ships with.
///
/// A template is two things at once: a letterhead, and a set of decisions about
/// how each section below it is drawn. Those decisions already exist as
/// `TemplatePlan` — this simply lets a person keep the letterhead they picked
/// while taking the timeline from Chronicle, the skill pills from Atlas or the
/// margin dates from Modena.
///
/// Every field is optional, and `nil` means "whatever the template says". A
/// résumé with no overrides renders byte-for-byte as it did before this existed.
struct ResumeSectionStyleOverrides: Codable, Equatable, Hashable {
  var body: BodyLayoutChoice?
  var experience: ExperienceStyle?
  var competencies: CompetencyStyle?
  var education: EducationStyle?
  var references: ReferenceStyle?
  var additional: AdditionalSectionStyle?
  var contact: ContactStyle?
  var sectionChrome: SectionChrome?
  var numberedSections: Bool?
  var hangingHeadings: Bool?

  static let none = ResumeSectionStyleOverrides()

  var isEmpty: Bool { self == .none }

  /// How many sections have been taken off their template default — the badge
  /// the editor shows so a customised résumé says so at a glance.
  var count: Int {
    var total = 0
    if body != nil { total += 1 }
    if experience != nil { total += 1 }
    if competencies != nil { total += 1 }
    if education != nil { total += 1 }
    if references != nil { total += 1 }
    if additional != nil { total += 1 }
    if contact != nil { total += 1 }
    if sectionChrome != nil { total += 1 }
    if numberedSections != nil { total += 1 }
    if hangingHeadings != nil { total += 1 }
    return total
  }
}

/// The page's shape, as a choice rather than a `BodyLayout` — that carries a
/// whole `SideColumn` with widths and fills, which is the template's business,
/// not something to ask a person to fill in.
enum BodyLayoutChoice: String, Codable, CaseIterable, Equatable, Hashable {
  case single
  case leftColumn
  case rightColumn
}

extension TemplatePlan {
  /// The template's plan with the user's choices laid over it.
  func applying(_ overrides: ResumeSectionStyleOverrides) -> TemplatePlan {
    var plan = self
    if let experience = overrides.experience { plan.experience = experience }
    if let competencies = overrides.competencies { plan.competencies = competencies }
    if let contact = overrides.contact { plan.contact = contact }
    if let chrome = overrides.sectionChrome { plan.sectionChrome = chrome }
    if let numbered = overrides.numberedSections { plan.numberedSections = numbered }
    if let hanging = overrides.hangingHeadings { plan.hangingHeadings = hanging }
    if let education = overrides.education { plan.education = education }
    if let references = overrides.references { plan.references = references }
    if let additional = overrides.additional { plan.additional = additional }

    if let choice = overrides.body {
      plan.body = resolvedBody(for: choice)
    }
    return plan
  }

  /// Moving a column keeps whatever the template already painted there — its
  /// width, its fill, whether it opens below the summary. A template that never
  /// had one gets the safest possible column: plain type behind a hairline,
  /// which sits under any of the letterheads without fighting them.
  private func resolvedBody(for choice: BodyLayoutChoice) -> BodyLayout {
    switch choice {
    case .single:
      return .single
    case .leftColumn, .rightColumn:
      let edge: SideColumn.Edge = choice == .leftColumn ? .leading : .trailing
      if case .side(let existing) = body {
        var moved = existing
        moved.edge = edge
        return .side(moved)
      }
      return .side(SideColumn(edge: edge, width: 176, fill: .none, divider: true))
    }
  }
}

// MARK: - Display

/// One entry in a section's style picker: what to call it, and a template that
/// already uses it — because "the experience style from another template" is
/// exactly how someone arrives at this screen.
struct SectionStyleOption<Value: Hashable>: Identifiable, Hashable {
  var value: Value?
  var title: LocalizedStringResource
  /// A template the style is native to, named so the choice is recognisable.
  var seenIn: String?

  var id: String { "\(String(describing: value))" }

  static func == (lhs: SectionStyleOption<Value>, rhs: SectionStyleOption<Value>) -> Bool {
    lhs.value == rhs.value
  }

  func hash(into hasher: inout Hasher) { hasher.combine(value) }
}

enum SectionStyleCatalog {
  static let templateDefaultTitle: LocalizedStringResource = "Template default"

  static let body: [SectionStyleOption<BodyLayoutChoice>] = [
    .init(value: nil, title: templateDefaultTitle),
    .init(value: .single, title: "One column", seenIn: "Classic Editorial"),
    .init(value: .leftColumn, title: "Column on the left", seenIn: "Atlas Sidebar"),
    .init(value: .rightColumn, title: "Column on the right", seenIn: "Verso Panel"),
  ]

  static let experience: [SectionStyleOption<ExperienceStyle>] = [
    .init(value: nil, title: templateDefaultTitle),
    .init(value: .stacked, title: "Stacked", seenIn: "Modern Executive"),
    .init(value: .timeline, title: "Timeline rail", seenIn: "Chronicle Timeline"),
    .init(value: .dateGutter, title: "Dates in the margin", seenIn: "Modena Margin"),
  ]

  static let competencies: [SectionStyleOption<CompetencyStyle>] = [
    .init(value: nil, title: templateDefaultTitle),
    .init(value: .bullets, title: "Bulleted list", seenIn: "Classic Editorial"),
    .init(value: .chips, title: "Pills", seenIn: "Atlas Sidebar"),
    .init(value: .columns, title: "Three columns", seenIn: "Ivy League"),
    .init(value: .iconGrid, title: "Ticked matrix", seenIn: "Signal Icons"),
    .init(value: .meters, title: "Ranked bars", seenIn: "Gauge Sidebar"),
    .init(value: .dots, title: "Dot ratings", seenIn: "Medallion"),
  ]

  static let education: [SectionStyleOption<EducationStyle>] = [
    .init(value: nil, title: templateDefaultTitle),
    .init(value: .stacked, title: "Stacked", seenIn: "Modern Executive"),
    .init(value: .dateGutter, title: "Dates in the margin", seenIn: "Gazette Margins"),
    .init(value: .card, title: "Cards", seenIn: "Strata Cards"),
  ]

  static let references: [SectionStyleOption<ReferenceStyle>] = [
    .init(value: nil, title: templateDefaultTitle),
    .init(value: .cards, title: "Cards", seenIn: "Modern Executive"),
    .init(value: .plain, title: "Plain, two up"),
    .init(value: .compact, title: "One line each"),
  ]

  static let additional: [SectionStyleOption<AdditionalSectionStyle>] = [
    .init(value: nil, title: templateDefaultTitle),
    .init(value: .bullets, title: "Bulleted list"),
    .init(value: .chips, title: "Pills", seenIn: "Atlas Sidebar"),
    .init(value: .columns, title: "Three columns", seenIn: "Ivy League"),
    .init(value: .plain, title: "Plain lines"),
  ]

  static let contact: [SectionStyleOption<ContactStyle>] = [
    .init(value: nil, title: templateDefaultTitle),
    .init(value: .inline, title: "On one line", seenIn: "Modern Executive"),
    .init(value: .iconRows, title: "Icon beside each", seenIn: "Signal Icons"),
  ]

  static let chrome: [SectionStyleOption<SectionChrome>] = [
    .init(value: nil, title: templateDefaultTitle),
    .init(value: .plain, title: "No card"),
    .init(value: .card, title: "Card per entry", seenIn: "Strata Cards"),
  ]

  static let headingNumbering: [SectionStyleOption<Bool>] = [
    .init(value: nil, title: templateDefaultTitle),
    .init(value: false, title: "Plain headings"),
    .init(value: true, title: "Numbered 01, 02, 03", seenIn: "Folio Numbered"),
  ]

  static let headingPlacement: [SectionStyleOption<Bool>] = [
    .init(value: nil, title: templateDefaultTitle),
    .init(value: false, title: "Above the text"),
    .init(value: true, title: "In the left margin", seenIn: "Terrace Margins"),
  ]
}
