import Foundation

/// A single thing in the rendered résumé that a double tap can open for editing.
enum ResumeQuickEditTarget: Identifiable, Hashable {
  case photo
  case name
  case headline
  case contact
  case profile
  case competencies
  case experience(UUID)
  case education(UUID)
  case reference(UUID)
  case additional(UUID)

  var id: String {
    switch self {
    case .photo: "photo"
    case .name: "name"
    case .headline: "headline"
    case .contact: "contact"
    case .profile: "profile"
    case .competencies: "competencies"
    case .experience(let id): "experience-\(id)"
    case .education(let id): "education-\(id)"
    case .reference(let id): "reference-\(id)"
    case .additional(let id): "additional-\(id)"
    }
  }

  var title: LocalizedStringResource {
    switch self {
    case .photo: "Photo"
    case .name: "Your name"
    case .headline: "Job title"
    case .contact: "Contact details"
    case .profile: "Professional profile"
    case .competencies: "Core competencies"
    case .experience: "Role"
    case .education: "Qualification"
    case .reference: "Reference"
    case .additional: "Section"
    }
  }

  var prompt: LocalizedStringResource {
    switch self {
    case .photo: "Swap the portrait on this résumé"
    case .name: "The name across the top of the page"
    case .headline: "The line under your name"
    case .contact: "How employers reach you"
    case .profile: "Your opening summary"
    case .competencies: "The skills you lead with"
    case .experience: "What you did and when"
    case .education: "Where you studied"
    case .reference: "Who can vouch for you"
    case .additional: "Your own section"
    }
  }

  /// One field does not deserve half the screen. Targets whose editor has a known
  /// size open at exactly that height; the open-ended ones fall back to a medium
  /// sheet. Either way it can still be dragged up to full height.
  var preferredHeight: CGFloat? {
    switch self {
    case .name, .headline: 342
    case .contact: 412
    case .profile: 424
    case .photo: 496
    case .competencies, .experience, .education, .reference, .additional: nil
    }
  }

  var systemImage: String {
    switch self {
    case .photo: "person.crop.square"
    case .name: "textformat"
    case .headline: "text.badge.star"
    case .contact: "envelope"
    case .profile: "text.alignleft"
    case .competencies: "checkmark.seal"
    case .experience: "briefcase"
    case .education: "graduationcap"
    case .reference: "person.2"
    case .additional: "square.stack.3d.up"
    }
  }
}

/// Works out which part of a résumé a tapped line of the rendered PDF came from.
///
/// The 140 templates lay the same content out in wildly different ways, so a
/// position on the page says almost nothing about what is there — but the words
/// are always the user's own. Matching the tapped line against the document's own
/// text therefore works identically across every design, and asks nothing of the
/// renderer.
enum ResumeQuickEditLocator {
  /// Above this fraction of page one counts as the letterhead, which is the only
  /// place a portrait is ever drawn and the tie-breaker between a name used as a
  /// heading and the same words appearing in a role further down.
  private static let headerFraction: CGFloat = 0.28

  static func target(
    forLine line: String,
    preceding: String = "",
    following: String = "",
    relativeY: CGFloat,
    pageIndex: Int,
    in document: ResumeDocument
  ) -> ResumeQuickEditTarget? {
    let isLetterhead = pageIndex == 0 && relativeY <= headerFraction
    let needle = normalised(line)

    // A blank patch, or the two letters of a monogram. On a résumé that prints a
    // portrait, that is the portrait: it is the one part of the page carrying no
    // words of its own. Photo-led templates hang it in a sidebar well below the
    // letterhead, so how far down the page the tap landed cannot decide this on
    // its own — which left the portrait untappable on most of the designs built
    // around one. Elsewhere a blank patch is only margin, and stays inert.
    guard needle.count >= 5 else {
      if pageIndex == 0, document.showsPortrait { return .photo }
      return isLetterhead ? .photo : nil
    }

    // Which section the tap landed in, which is the only thing that separates two
    // identical strings printed in different parts of the page.
    let section =
      self.section(ofHeading: needle, in: document)
      ?? self.section(under: normalised(preceding), in: document)

    let ranked = candidates(in: document)
      .map { (candidate: $0, score: score(needle: needle, candidate: $0.normalisedText)) }
      .filter { $0.score > 0 }

    let best = ranked.max { lhs, rhs in
      if lhs.score != rhs.score { return lhs.score < rhs.score }
      // A referee is usually a former manager, so their company is also an
      // employer on the résumé and matches both equally well. The heading above
      // the tap says which of the two is actually being pointed at — without it
      // the tie fell to whichever was built first, which was always the role.
      let lhsInSection = section?.contains(lhs.candidate.target) ?? false
      let rhsInSection = section?.contains(rhs.candidate.target) ?? false
      if lhsInSection != rhsInSection { return rhsInSection }
      // Equally good matches — "Software Engineer" is both a job title and a role
      // — are settled by where on the page the tap landed.
      if lhs.candidate.isLetterhead != rhs.candidate.isLetterhead {
        return rhs.candidate.isLetterhead == isLetterhead
      }
      // Otherwise the tighter match is the more specific field.
      return lhs.candidate.normalisedText.count > rhs.candidate.normalisedText.count
    }

    // An exact hit on the user's own words beats everything.
    if let best, best.score >= 1 { return best.candidate.target }
    // Otherwise a section heading, which is the template's wording rather than
    // theirs, and the most natural thing to aim at when a section is what you
    // want to change.
    if let heading = heading(for: needle, following: normalised(following), in: document) {
      return heading
    }
    if let best { return best.candidate.target }
    return isLetterhead ? .photo : nil
  }

  /// A part of the résumé, as named by the heading printed above it.
  private enum Section: Equatable {
    case profile, competencies, experience, education, references, contact
    case additional(UUID)

    func contains(_ target: ResumeQuickEditTarget) -> Bool {
      switch (self, target) {
      case (.profile, .profile), (.competencies, .competencies),
        (.experience, .experience), (.education, .education),
        (.references, .reference), (.contact, .contact):
        true
      case (.additional(let mine), .additional(let theirs)):
        mine == theirs
      default:
        false
      }
    }
  }

  /// The wordings templates print for each section. Kept as one table because
  /// both jobs — reading a tapped heading, and finding the last heading above a
  /// tap — have to agree on what counts as a heading.
  private static let headings: [(phrases: Set<String>, section: Section)] = [
    (
      [
        "professional profile", "profile", "summary", "professional summary",
        "career summary", "about", "about me", "objective", "career objective",
        "personal statement",
      ], .profile
    ),
    (
      [
        "core competencies", "competencies", "skills", "key skills", "core skills",
        "areas of expertise", "expertise", "strengths", "capabilities",
      ], .competencies
    ),
    (
      [
        "professional experience", "experience", "work experience", "employment",
        "employment history", "work history", "career history", "career",
      ], .experience
    ),
    (
      [
        "education", "education and training", "qualifications", "academic background",
        "academic", "training",
      ], .education
    ),
    (["references", "referees", "references available on request"], .references),
    (["contact", "contact details", "contact information", "get in touch"], .contact),
  ]

  /// A section running over a page break is reprinted as "Education —
  /// continued", which names the same section as the heading it follows.
  private static func withoutContinuation(_ needle: String) -> String {
    for suffix in [" continued", " cont d", " cont", " ctd"] where needle.hasSuffix(suffix) {
      return String(needle.dropLast(suffix.count))
    }
    return needle
  }

  /// The section a tapped line names, if the line is a heading at all. Matched
  /// only exactly — anything looser and the word "experience" sitting inside a
  /// bullet would hijack the whole section.
  private static func section(
    ofHeading rawNeedle: String, in document: ResumeDocument
  ) -> Section? {
    let needle = withoutContinuation(rawNeedle)
    if let custom = document.additionalSections.first(where: { normalised($0.title) == needle }) {
      return .additional(custom.id)
    }
    return headings.first { $0.phrases.contains(needle) }?.section
  }

  /// The section a tap sits inside, read as the last heading printed above it.
  /// Templates set headings in their own wording, so this looks for any of the
  /// known phrasings as a whole line's worth of words and takes the one nearest
  /// the tap.
  private static func section(under preceding: String, in document: ResumeDocument) -> Section? {
    guard !preceding.isEmpty else { return nil }
    let haystack = " \(preceding) "
    var best: (position: String.Index, section: Section)?

    func consider(_ phrase: String, _ section: Section) {
      guard !phrase.isEmpty,
        let found = haystack.range(of: " \(phrase) ", options: .backwards)
      else { return }
      if let current = best, current.position >= found.lowerBound { return }
      best = (found.lowerBound, section)
    }

    for entry in headings {
      for phrase in entry.phrases { consider(phrase, entry.section) }
      // "Education — continued" names its section as surely as the original.
      for phrase in entry.phrases { consider("\(phrase) continued", entry.section) }
    }
    // A section the user named themselves counts too, and beats the built-in
    // list when both appear, because it is printed with their own words.
    for custom in document.additionalSections {
      consider(normalised(custom.title), .additional(custom.id))
    }
    return best?.section
  }

  /// Section headings come from the template, not the document, so they are
  /// matched from a list — and only exactly.
  private static func heading(
    for rawNeedle: String, following: String, in document: ResumeDocument
  ) -> ResumeQuickEditTarget? {
    /// The entry of this section actually printed under the heading that was
    /// tapped. Without this, a heading on page two opens page one's first entry —
    /// which is never the one being looked at.
    func onThisPage<T>(_ entries: [T], _ text: (T) -> [String]) -> T? {
      entries.first { entry in
        text(entry)
          .map(normalised)
          .contains { !$0.isEmpty && following.contains($0) }
      }
    }

    switch section(ofHeading: rawNeedle, in: document) {
    case .profile:
      return .profile
    case .competencies:
      return .competencies
    case .experience:
      let entry = onThisPage(document.experience) { [$0.role, $0.company] }
        ?? document.experience.first
      return entry.map { .experience($0.id) }
    case .education:
      let entry = onThisPage(document.education) { [$0.qualification, $0.institution] }
        ?? document.education.first
      return entry.map { .education($0.id) }
    case .references:
      let entry = onThisPage(document.references) { [$0.name, $0.company] }
        ?? document.references.first
      return entry.map { .reference($0.id) }
    case .contact:
      return .contact
    // A section the user named themselves is matched as their own words by the
    // scoring pass, which runs first and is the more specific answer.
    case .additional, nil:
      return nil
    }
  }

  private struct Candidate {
    let target: ResumeQuickEditTarget
    let normalisedText: String
    let isLetterhead: Bool
  }

  private static func candidates(in document: ResumeDocument) -> [Candidate] {
    var result: [Candidate] = []

    func add(_ target: ResumeQuickEditTarget, _ text: String, letterhead: Bool = false) {
      let normalised = normalised(text)
      guard !normalised.isEmpty else { return }
      result.append(
        Candidate(target: target, normalisedText: normalised, isLetterhead: letterhead))
    }

    add(.name, document.personal.fullName, letterhead: true)
    add(.headline, document.personal.headline, letterhead: true)
    add(.contact, document.personal.phone, letterhead: true)
    add(.contact, document.personal.email, letterhead: true)
    add(.profile, document.professionalProfile)
    for skill in document.competencies { add(.competencies, skill) }

    for entry in document.experience {
      let target = ResumeQuickEditTarget.experience(entry.id)
      add(target, entry.role)
      add(target, entry.company)
      add(target, entry.period)
      for highlight in entry.highlights { add(target, highlight) }
    }
    for entry in document.education {
      let target = ResumeQuickEditTarget.education(entry.id)
      add(target, entry.qualification)
      add(target, entry.institution)
      add(target, entry.period)
      add(target, entry.details)
    }
    for entry in document.references {
      let target = ResumeQuickEditTarget.reference(entry.id)
      add(target, entry.name)
      add(target, entry.company)
      add(target, entry.phone)
      add(target, entry.email)
    }
    for section in document.additionalSections {
      let target = ResumeQuickEditTarget.additional(section.id)
      add(target, section.title)
      for item in section.items { add(target, item) }
    }

    return result
  }

  /// How much of the tapped line this candidate accounts for, `0...1`.
  ///
  /// A wrapped paragraph gives a line that is a fragment of the stored text, and a
  /// two-column skills row gives a line holding several stored values, so both
  /// directions of containment count as a hit.
  private static func score(needle: String, candidate: String) -> Double {
    if candidate == needle { return 1 }
    if candidate.contains(needle) { return 1 }
    if needle.contains(candidate), candidate.count >= 5 {
      return Double(candidate.count) / Double(needle.count)
    }
    return 0
  }

  /// Case, accents and punctuation all vary between what is stored and what a
  /// template prints — bullets, pipes, en dashes, small caps. Comparing on words
  /// alone survives all of it.
  private static func normalised(_ text: String) -> String {
    text
      .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }
}
