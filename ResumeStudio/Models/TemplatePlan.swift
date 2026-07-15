import CoreGraphics

/// What a template does with the *page*, as opposed to what it does with the
/// letterhead.
///
/// The original catalogue is all `.single`: one column, section after section,
/// down the page. The difference between those templates is the header art —
/// which is why, past the first inch, they all read rather alike.
///
/// This is the other axis. A plan moves the content itself: puts contact details
/// and skills in a column of their own, hangs dates in the margin, threads a rail
/// through the roles, or leads with skills instead of the summary. The layouts
/// recruiters actually meet — a narrow column for the scannable facts beside a
/// wide one for the story — are combinations of these, not new headers.
struct TemplatePlan: Equatable, Hashable {
  var body: BodyLayout = .single
  var experience: ExperienceStyle = .stacked
  var competencies: CompetencyStyle = .bullets
  var sectionChrome: SectionChrome = .plain
  var contact: ContactStyle = .inline
  /// Skills before the summary, for people whose skills are the pitch.
  var skillsFirst: Bool = false
  /// Sections counted off — 01, 02, 03 — the editorial numbering.
  var numberedSections: Bool = false
  /// Light type on a dark page: the whole sheet, not just a band. The renderer
  /// swaps its ink for the paper's sake everywhere the body is drawn.
  var darkPaper: Bool = false
  /// Section titles hang in a gutter to the left of the text, the way a reference
  /// book sets its side-headings. The body keeps a narrow measure beside them, so
  /// the page reads as one column with the headings living outside it.
  var hangingHeadings: Bool = false
  /// The summary is set inside the letterhead itself rather than beneath it —
  /// the opening paragraph as part of the masthead.
  var profileInHeader: Bool = false
  /// How far the body clears the left margin, for the templates whose page
  /// furniture — a full-height rail — occupies it.
  var bodyInset: CGFloat = 0
  /// Multiplies every type size. Below 1 it buys lines, and therefore pages.
  var density: CGFloat = 1

  /// Whether the page carries a second column of text. Real text in two columns
  /// stays selectable and searchable, but some applicant-tracking parsers read
  /// the columns in the wrong order, which is worth saying out loud rather than
  /// discovering after an application disappears.
  var hasSideColumn: Bool {
    if case .side = body { return true }
    return false
  }
}

enum BodyLayout: Equatable, Hashable {
  case single
  case side(SideColumn)
}

/// The narrow column: contact, skills, education — the facts a recruiter scans
/// for. The wide column keeps the summary and the experience, which is what they
/// actually read.
struct SideColumn: Equatable, Hashable {
  enum Edge { case leading, trailing }

  enum Fill {
    /// A full-height band of colour, the length of every page.
    case dark
    case accent
    case tint
    /// No band: the column is simply a second column of type.
    case none
  }

  var edge: Edge
  var width: CGFloat
  var fill: Fill
  /// The split templates run the summary the full width of the page and only
  /// then divide, so the opening paragraph is never squeezed into a gutter.
  var startsBelowProfile: Bool = false
  /// A hairline between the columns, for the unfilled ones — the Swiss look,
  /// where the divide is drawn rather than painted.
  var divider: Bool = false

  /// White type on the dark and accent bands, ink on the quiet ones.
  var prefersLightInk: Bool {
    fill == .dark || fill == .accent
  }
}

enum ExperienceStyle: Equatable, Hashable {
  case stacked
  /// A rail down the column with a dot at every role: the career path, drawn.
  case timeline
  /// Dates hang in the margin, roles hang off them.
  case dateGutter
}

enum CompetencyStyle: Equatable, Hashable {
  case bullets
  /// Pills. They read as a set of labels rather than a list of sentences.
  case chips
  /// Ticked, two across — the "skills matrix" look.
  case iconGrid
  /// Ranked bars, strongest first. The level is the position in the list, so
  /// the order chosen in the editor is the ranking — nothing is invented.
  case meters
  /// A row of five dots, filled by rank — the "rating" look the portfolio
  /// templates use. Same ranking logic as `meters`, drawn as beads.
  case dots
  /// Three across, plain type: the compact list the ATS guides recommend.
  case columns
}

enum SectionChrome: Equatable, Hashable {
  case plain
  /// Every entry in its own bordered card.
  case card
}

enum ContactStyle: Equatable, Hashable {
  case inline
  /// An icon beside each detail, stacked. Needs a column to live in, or a strip.
  case iconRows
}
