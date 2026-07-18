import CoreGraphics
import Foundation

/// Audits the résumé against the six fixation points of the recruiter
/// eye-tracking research and builds the gaze path the scan simulation replays.
/// Entirely on device: no network, no credits, and it works the same offline.
enum RecruiterScanService {

  // MARK: - Guided repair

  /// Builds an editable repair copy without inventing career facts. The only
  /// content change made automatically is moving an existing quantified result
  /// into the first, most-read bullet. Empty rows are temporary form slots and
  /// are removed again by `finalizeRepairDraft` if the user leaves them blank.
  static func makeRepairDraft(
    document: ResumeDocument,
    report: RecruiterScanReport
  ) -> ResumeDocument {
    var draft = document
    let issueIDs = Set(report.findings.filter { $0.severity != .pass }.map(\.id))

    // These two fields can be completed from facts already present elsewhere
    // in the CV. They remain editable in review, but do not depend on network
    // AI and never introduce a new employer, qualification, skill or result.
    if issueIDs.contains("identity"), draft.personal.headline.isBlank,
      let headline = localHeadline(for: draft)
    {
      draft.personal.headline = headline
    }
    if issueIDs.contains("profile-skim"), draft.professionalProfile.isBlank,
      let profile = localProfile(for: draft)
    {
      draft.professionalProfile = profile
    }

    if !draft.experience.isEmpty, issueIDs.contains("evidence") {
      let highlights = draft.experience[0].highlights
      if highlights.first.map(isQuantified) != true,
        let quantifiedIndex = highlights.dropFirst().firstIndex(where: isQuantified)
      {
        let quantified = draft.experience[0].highlights.remove(at: quantifiedIndex)
        draft.experience[0].highlights.insert(quantified, at: 0)
      }
    }

    let needsCurrentRole = !issueIDs.isDisjoint(with: ["current-role", "current-dates", "evidence"])
    if needsCurrentRole, draft.experience.isEmpty {
      draft.experience.append(ExperienceEntry(role: "", company: "", period: "", highlights: []))
    }
    if issueIDs.contains("trajectory"), draft.experience.count < 2 {
      while draft.experience.count < 2 {
        draft.experience.append(ExperienceEntry(role: "", company: "", period: "", highlights: []))
      }
    }
    if issueIDs.contains("evidence"), !draft.experience.isEmpty,
      draft.experience[0].highlights.isEmpty
    {
      draft.experience[0].highlights = [""]
    }
    if issueIDs.contains("education"), draft.education.isEmpty {
      draft.education.append(EducationEntry(
        qualification: "", institution: "", period: "", details: ""))
    }
    return draft
  }

  /// Removes untouched form placeholders before committing the reviewed copy.
  static func finalizeRepairDraft(_ draft: ResumeDocument) -> ResumeDocument {
    var result = draft
    result.experience = result.experience.compactMap { entry in
      var clean = entry
      clean.highlights = clean.highlights.filter { !$0.isBlank }
      let hasIdentity = !clean.role.isBlank || !clean.company.isBlank || !clean.period.isBlank
      return hasIdentity || !clean.highlights.isEmpty ? clean : nil
    }
    result.education = result.education.filter {
      !$0.qualification.isBlank || !$0.institution.isBlank || !$0.period.isBlank || !$0.details.isBlank
    }
    return result
  }

  /// A network-free headline assembled only from the latest role and skills.
  static func localHeadline(for document: ResumeDocument) -> String? {
    guard let role = document.experience.first?.role.nilIfBlank else { return nil }
    let skills = document.competencies
      .compactMap(\.nilIfBlank)
      .filter { $0.localizedCaseInsensitiveCompare(role) != .orderedSame }
    if skills.isEmpty { return role }
    return ([role] + Array(skills.prefix(2))).joined(separator: " | ")
  }

  /// A concise professional profile built from CV facts. This is intentionally
  /// deterministic: it works offline and cannot embellish what the user wrote.
  static func localProfile(for document: ResumeDocument) -> String? {
    var sentences: [String] = []
    if let current = document.experience.first,
      let role = current.role.nilIfBlank
    {
      var opening = role
      if let company = current.company.nilIfBlank { opening += " at \(company)" }
      if let proof = current.highlights.first?.nilIfBlank {
        opening += " with experience in \(sentenceFragment(proof))"
      }
      sentences.append(opening + ".")
    }

    if document.experience.count > 1,
      let previousRole = document.experience[1].role.nilIfBlank
    {
      var previous = "Previous experience includes \(previousRole)"
      if let company = document.experience[1].company.nilIfBlank {
        previous += " at \(company)"
      }
      sentences.append(previous + ".")
    }

    let skills = document.competencies.compactMap(\.nilIfBlank)
    if !skills.isEmpty {
      sentences.append("Core strengths include \(naturalList(Array(skills.prefix(4)))).")
    }

    if let education = document.education.first(where: {
      !$0.qualification.isBlank || !$0.institution.isBlank
    }) {
      let qualification = education.qualification.nilIfBlank
      let institution = education.institution.nilIfBlank
      if let qualification, let institution {
        sentences.append("Education includes \(qualification) from \(institution).")
      } else if let qualification {
        sentences.append("Education includes \(qualification).")
      } else if let institution {
        sentences.append("Education includes study at \(institution).")
      }
    }

    guard !sentences.isEmpty else { return nil }
    // Keep the fallback safely below the strictest 55-word scan limit.
    var result = ""
    for sentence in sentences {
      let candidate = result.isEmpty ? sentence : "\(result) \(sentence)"
      if candidate.split(whereSeparator: \.isWhitespace).count > 52 { break }
      result = candidate
    }
    return result.nilIfBlank
  }

  /// Combines user-supplied proof with the existing bullet. Both the metric and
  /// outcome are required so a bare number can never be mistaken for a fix.
  static func addingVerifiedMetric(
    _ metric: String,
    outcome: String,
    context: String = "",
    to bullet: String
  ) -> String? {
    let cleanMetric = metric.trimmed
    let cleanOutcome = outcome.trimmed
    guard !cleanMetric.isEmpty, !cleanOutcome.isEmpty else { return nil }
    var base = bullet.trimmed
    while base.last == "." || base.last == ";" { base.removeLast() }
    var proof = "\(cleanMetric) \(cleanOutcome)"
    if let cleanContext = context.nilIfBlank { proof += " \(cleanContext)" }
    return base.isEmpty ? "Delivered \(proof)." : "\(base), delivering \(proof)."
  }

  private static func sentenceFragment(_ value: String) -> String {
    var clean = value.trimmed
    while clean.last == "." || clean.last == ";" { clean.removeLast() }
    guard let first = clean.first else { return clean }
    return first.lowercased() + String(clean.dropFirst())
  }

  private static func naturalList(_ values: [String]) -> String {
    switch values.count {
    case 0: ""
    case 1: values[0]
    case 2: values.joined(separator: " and ")
    default: values.dropLast().joined(separator: ", ") + ", and " + values.last!
    }
  }

  // MARK: - Audit

  static func analyze(
    document: ResumeDocument,
    strictness: RecruiterScanStrictness = .medium
  ) -> RecruiterScanReport {
    var findings: [RecruiterScanFinding] = []
    var captured: [String] = []
    var missed: [String] = []

    // The bars each fixation has to clear at this strictness.
    let bulletLengthLimit = switch strictness {
    case .low: 260
    case .medium: 220
    case .high: 180
    }
    let profileWordLimit = switch strictness {
    case .low: 110
    case .medium: 79
    case .high: 55
    }

    let current = document.experience.first
    let previous = document.experience.dropFirst().first

    // Name and headline — where the scan opens.
    let hasName = !document.personal.fullName.isBlank
    let hasHeadline = !document.personal.headline.isBlank
    if hasName && hasHeadline {
      findings.append(RecruiterScanFinding(
        id: "identity", title: "Name and headline", gazeSeconds: 1.0, severity: .pass,
        detail: "The scan opens on a name with a one-line answer to “who is this?” beside it.",
        section: .personal, points: 12, maxPoints: 12))
      captured.append("\(document.personal.fullName.trimmed) — \(document.personal.headline.trimmed)")
    } else if hasName {
      findings.append(RecruiterScanFinding(
        id: "identity", title: "Name and headline", gazeSeconds: 1.0, severity: .warning,
        detail: "Your name registers, but there is no headline to say what you are. The first second answers less than it could.",
        section: .personal, points: 7, maxPoints: 12))
      captured.append(document.personal.fullName.trimmed)
      missed.append("A headline saying what you are")
    } else {
      findings.append(RecruiterScanFinding(
        id: "identity", title: "Name and headline", gazeSeconds: 1.0, severity: .action,
        detail: "The first fixation of the scan is your name — add it, with a one-line headline beside it.",
        section: .personal, points: 0, maxPoints: 12))
      missed.append("A name to remember you by")
    }

    // Current title and company — the largest single share of gaze time.
    let role = current?.role.trimmed ?? ""
    let company = current?.company.trimmed ?? ""
    if !role.isEmpty && !company.isEmpty {
      findings.append(RecruiterScanFinding(
        id: "current-role", title: "Current title and company", gazeSeconds: 1.5, severity: .pass,
        detail: "The biggest share of the scan lands on your latest title and employer, and both are there.",
        section: .experience, points: 22, maxPoints: 22))
      captured.append("\(role) at \(company)")
    } else if !role.isEmpty || !company.isEmpty {
      findings.append(RecruiterScanFinding(
        id: "current-role", title: "Current title and company", gazeSeconds: 1.5, severity: .warning,
        detail: role.isEmpty
          ? "The employer is named but not your title there — the single most-read line on the page is half empty."
          : "Your title is there but not the company — recruiters read the pair together.",
        section: .experience, points: 13, maxPoints: 22))
      captured.append(role.isEmpty ? company : role)
      missed.append(role.isEmpty ? "Your title at \(company)" : "The company behind “\(role)”")
    } else {
      findings.append(RecruiterScanFinding(
        id: "current-role", title: "Current title and company", gazeSeconds: 1.5, severity: .action,
        detail: "The most-read line of any résumé is the latest title and company. Add your most recent role first.",
        section: .experience, points: 0, maxPoints: 22))
      missed.append("A current title and company")
    }

    // Dates on the current role — the progression check.
    if let current, !current.period.isBlank {
      findings.append(RecruiterScanFinding(
        id: "current-dates", title: "Dates on the current role", gazeSeconds: 0.7, severity: .pass,
        detail: "After the title, eyes dart to the dates. Yours are where they look.",
        section: .experience, points: 12, maxPoints: 12))
      captured.append("In the role \(current.period.trimmed)")
    } else {
      let severity: ATSIssueSeverity = strictness == .low ? .warning : .action
      findings.append(RecruiterScanFinding(
        id: "current-dates", title: "Dates on the current role", gazeSeconds: 0.7, severity: severity,
        detail: "An undated role reads as a gap being hidden. Add the period, even if it is simply “2024 – present”.",
        section: .experience, points: severity == .warning ? 7 : 0, maxPoints: 12))
      missed.append("How long you have been in the role")
    }

    // The step before — trajectory.
    if let previous {
      let complete = !previous.role.isBlank && !previous.company.isBlank && !previous.period.isBlank
      let severity: ATSIssueSeverity = complete ? .pass : (strictness == .high ? .action : .warning)
      findings.append(RecruiterScanFinding(
        id: "trajectory", title: "Previous role and dates", gazeSeconds: 1.4, severity: severity,
        detail: complete
          ? "The scan compares your last two roles to read the career's direction, and both steps are legible."
          : "The previous role is started but missing its title, company or dates, so the trajectory reads as a question mark.",
        section: .experience, points: complete ? 16 : (severity == .warning ? 10 : 0), maxPoints: 16))
      if complete { captured.append("The step before: \(previous.role.trimmed)") }
      else { missed.append("A complete previous role") }
    } else if current != nil {
      let severity: ATSIssueSeverity = switch strictness {
      case .low: .pass
      case .medium: .warning
      case .high: .action
      }
      let detail = switch strictness {
      case .low:
        "One role listed. A generous reader takes a single strong role at face value early in a career."
      case .medium:
        "One role listed: the scan looks for the step before it and finds none. Early in a career, internships, projects or vacation work fill that fixation."
      case .high:
        "A demanding screen reads career direction from at least two steps. Add the role, internship or project that came before this one."
      }
      findings.append(RecruiterScanFinding(
        id: "trajectory", title: "Previous role and dates", gazeSeconds: 1.4, severity: severity,
        detail: detail,
        section: .experience,
        points: severity == .pass ? 16 : (severity == .warning ? 10 : 0), maxPoints: 16))
      if severity == .pass { captured.append("A single, current role — taken on trust") }
      else { missed.append("The role before this one") }
    } else {
      findings.append(RecruiterScanFinding(
        id: "trajectory", title: "Previous role and dates", gazeSeconds: 1.4, severity: .action,
        detail: "With no experience listed, the two fixations recruiters spend on career trajectory land on blank paper.",
        section: .experience, points: 0, maxPoints: 16))
      missed.append("A career trajectory to read")
    }

    // The first bullet — proof, read more than the entire bottom half.
    let bullets = (current?.highlights ?? []).map(\.trimmed).filter { !$0.isEmpty }
    let firstQuantified = bullets.first.map(isQuantified) ?? false
    let anyQuantified = bullets.contains(where: isQuantified)
    let firstBulletFits = (bullets.first?.count ?? 0) <= bulletLengthLimit
    let evidencePasses = switch strictness {
    case .low: !bullets.isEmpty && firstBulletFits
    case .medium, .high: firstQuantified && firstBulletFits
    }
    if evidencePasses {
      findings.append(RecruiterScanFinding(
        id: "evidence", title: "Proof in the first bullet", gazeSeconds: 0.9, severity: .pass,
        detail: firstQuantified
          ? "The first bullet under your latest role draws more gaze than the whole bottom half of the page — yours opens with a measurable result."
          : "The first bullet under your latest role is there and readable. A stricter screen would ask it for a number.",
        section: .experience, points: 20, maxPoints: 20))
      captured.append(firstQuantified ? "One measurable result" : "A readable first proof point")
    } else if !bullets.isEmpty {
      let severity: ATSIssueSeverity =
        (strictness == .high && !anyQuantified) ? .action : .warning
      findings.append(RecruiterScanFinding(
        id: "evidence", title: "Proof in the first bullet", gazeSeconds: 0.9, severity: severity,
        detail: anyQuantified
          ? "There is a measurable result in this role, but not in the first bullet — the only one the scan reliably reads. Move it up."
          : severity == .action
            ? "A demanding screen reads the first bullet, finds no number anywhere in the role, and moves on. Add a result, a scale, a percentage."
            : "The first bullet is read more than the entire bottom half of the page. Give it a number: a result, a scale, a percentage.",
        section: .experience, points: severity == .warning ? 12 : 0, maxPoints: 20))
      missed.append("A number that proves the first bullet")
    } else {
      findings.append(RecruiterScanFinding(
        id: "evidence", title: "Proof in the first bullet", gazeSeconds: 0.9, severity: .action,
        detail: "The latest role has no bullets, so the scan's best-read line under the title does not exist yet.",
        section: .experience, points: 0, maxPoints: 20))
      missed.append("Any evidence under the latest role")
    }

    // Education — the flick to the bottom before deciding.
    let hasEducation = document.education.contains { !$0.qualification.isBlank || !$0.institution.isBlank }
    let educationSeverity: ATSIssueSeverity =
      hasEducation ? .pass : (strictness == .low ? .warning : .action)
    findings.append(RecruiterScanFinding(
      id: "education", title: "Education check", gazeSeconds: 1.0, severity: educationSeverity,
      detail: hasEducation
        ? "Before deciding, eyes flick down to verify education. Yours is there to find."
        : "The scan ends with a flick to education. If the section stays empty, that last fixation ends the pass on a blank.",
      section: .education,
      points: hasEducation ? 10 : (educationSeverity == .warning ? 6 : 0), maxPoints: 10))
    if hasEducation {
      let entry = document.education.first { !$0.qualification.isBlank || !$0.institution.isBlank }
      captured.append((entry?.qualification.isBlank == false ? entry?.qualification : entry?.institution)?.trimmed ?? "Education confirmed")
    } else {
      missed.append("Education to verify")
    }

    // Profile skimmability — the horizontal sweep between name and roles.
    let profileWords = document.professionalProfile.split(whereSeparator: \.isWhitespace).count
    if (1...profileWordLimit).contains(profileWords) {
      findings.append(RecruiterScanFinding(
        id: "profile-skim", title: "Profile skims in one sweep", gazeSeconds: 0.6, severity: .pass,
        detail: "The eye crosses the summary once on its way down. At this length it can actually be read in that sweep.",
        section: .profile, points: 8, maxPoints: 8))
    } else if profileWords > profileWordLimit {
      findings.append(RecruiterScanFinding(
        id: "profile-skim", title: "Profile skims in one sweep", gazeSeconds: 0.6, severity: .warning,
        detail: "At \(profileWords) words the summary is a block the scan jumps over rather than reads. Three to five lines survive the sweep.",
        section: .profile, points: 5, maxPoints: 8))
      missed.append("A summary short enough to be read")
    } else {
      let severity: ATSIssueSeverity = strictness == .high ? .action : .warning
      findings.append(RecruiterScanFinding(
        id: "profile-skim", title: "Profile skims in one sweep", gazeSeconds: 0.6, severity: severity,
        detail: "The horizontal sweep after your name crosses empty space where a two-line pitch could sit.",
        section: .profile, points: severity == .warning ? 3 : 0, maxPoints: 8))
    }

    return RecruiterScanReport(
      findings: findings,
      notes: notes(for: document),
      capturedFacts: captured,
      missedFacts: missed
    )
  }

  /// Layout and portrait context — surfaced, never scored, because these are
  /// choices the user made deliberately, often for a specific market.
  private static func notes(for document: ResumeDocument) -> [RecruiterScanNote] {
    var notes: [RecruiterScanNote] = []
    let plan = document.template.plan

    if document.showsPortrait {
      notes.append(RecruiterScanNote(
        id: "portrait", icon: "person.crop.circle",
        title: "The portrait pulls the eye first",
        detail: "In the eye-tracking research, a photo claims a large share of the first look before a word is read. Keep it for photo-expected markets; for US and UK applications the photo-free variant gives those seconds back to your work."))
    }
    if plan.hasSideColumn {
      notes.append(RecruiterScanNote(
        id: "facts-rail", icon: "sidebar.left",
        title: "A rail built for the fact-hunt",
        detail: "This template keeps contact, skills and education in their own column — the same facts the scan hunts for, gathered where one vertical sweep finds them."))
    }
    if plan.experience == .dateGutter {
      notes.append(RecruiterScanNote(
        id: "date-gutter", icon: "calendar",
        title: "Dates hang where eyes verify them",
        detail: "The margin dates put every period on one vertical line, which is exactly the progression check recruiters run."))
    }
    if plan.skillsFirst {
      notes.append(RecruiterScanNote(
        id: "skills-first", icon: "list.star",
        title: "Skills meet the eye before the story",
        detail: "This layout leads with skills, so the scan's early sweep crosses your toolkit before the first role."))
    }
    if plan.darkPaper {
      notes.append(RecruiterScanNote(
        id: "dark-paper", icon: "circle.lefthalf.filled",
        title: "Dark paper in a white stack",
        detail: "Unmissable on a screen full of white pages — just check the contrast survives an office printer before an in-person interview."))
    }
    return notes
  }

  /// True when a bullet carries something countable — a digit or a percentage.
  static func isQuantified(_ bullet: String) -> Bool {
    bullet.contains("%") || bullet.contains(where: \.isNumber)
  }

  // MARK: - Gaze path

  /// The simulated scan: an F-pattern adapted to what the template actually
  /// does with the page. Points are normalized to the page, durations sum to
  /// `RecruiterScanStudy.scanSeconds`, and a visible portrait re-allocates a
  /// share of the scan to the face — which is the study's own finding.
  static func gazePath(for document: ResumeDocument) -> [RecruiterGazeStop] {
    let plan = document.template.plan
    // A4 is 595pt wide, US Letter 612 — close enough that one normalization
    // serves a simulation whose zones are deliberately approximate.
    let pageWidth: CGFloat = 595

    let mainLeft: CGFloat
    let mainRight: CGFloat
    var railX: CGFloat?
    switch plan.body {
    case .single:
      mainLeft = 0.10 + plan.bodyInset / pageWidth
      mainRight = 0.90
    case .side(let column):
      let width = column.width / pageWidth
      if column.edge == .leading {
        mainLeft = width + 0.07
        mainRight = 0.92
        railX = width / 2 + 0.02
      } else {
        mainLeft = 0.08
        mainRight = 1 - width - 0.07
        railX = 1 - width / 2 - 0.02
      }
    }

    // The vertical stops are estimated from how much page the opening blocks
    // actually consume — a long summary or a big skills grid pushes the roles
    // down, and the simulation should land on them, not at fixed depths.
    let headlineY: CGFloat = plan.profileInHeader ? 0.08 : 0.09
    let headerBottom: CGFloat = plan.profileInHeader ? 0.21 : 0.165
    let profileWords = document.professionalProfile.split(whereSeparator: \.isWhitespace).count
    let profileBlock: CGFloat =
      profileWords == 0 ? 0.015 : 0.048 + CGFloat((profileWords + 11) / 12) * 0.017
    let visibleSkills = document.competencies.filter { !$0.isBlank }.count
    let skillsInMainColumn = railX == nil && visibleSkills > 0
    let skillsBlock: CGFloat =
      skillsInMainColumn ? 0.05 + CGFloat((visibleSkills + 1) / 2) * 0.019 : 0
    let profileY: CGFloat =
      plan.profileInHeader
      ? 0.15
      : headerBottom + (plan.skillsFirst ? skillsBlock : 0) + profileBlock * 0.45
    let skillsY: CGFloat =
      plan.skillsFirst
      ? headerBottom + skillsBlock * 0.45
      : headerBottom + profileBlock + skillsBlock * 0.5
    let currentRoleY = min(0.62, headerBottom + profileBlock + skillsBlock + 0.02)
    let currentBullets = (document.experience.first?.highlights.filter { !$0.isBlank }.count) ?? 0
    let roleBlock: CGFloat = 0.05 + CGFloat(max(1, currentBullets)) * 0.017
    let previousRoleY = min(0.80, currentRoleY + roleBlock)

    // Where the dates sit depends on the experience style: hung in the margin,
    // beside the timeline rail, or right-aligned on the title line.
    let dateX: CGFloat = switch plan.experience {
    case .dateGutter: max(0.04, mainLeft - 0.05)
    case .timeline: mainLeft + 0.03
    case .stacked: mainRight - 0.06
    }

    var stops: [RecruiterGazeStop] = []
    func add(_ x: CGFloat, _ y: CGFloat, _ duration: Double, _ label: String) {
      stops.append(RecruiterGazeStop(
        point: CGPoint(x: min(max(x, 0.03), 0.97), y: min(max(y, 0.03), 0.97)),
        duration: duration,
        label: label))
    }

    add(mainLeft + 0.14, headlineY, 1.0, "Name and headline")
    add((mainLeft + mainRight) / 2, profileY, 0.6, "Profile sweep")
    if plan.skillsFirst {
      add(mainLeft + 0.16, skillsY, 0.4, "Skills glance")
    }
    add(mainLeft + 0.10, currentRoleY, 1.5, "Current title and company")
    add(dateX, currentRoleY, 0.7, "Dates check")
    add(mainLeft + 0.16, currentRoleY + 0.05, 0.9, "First proof point")
    add(mainLeft + 0.10, previousRoleY, 0.9, "Previous role")
    add(dateX, previousRoleY, 0.5, "Previous dates")
    if !plan.skillsFirst {
      if let railX {
        add(railX, 0.42, 0.4, "Skills glance")
      } else if skillsInMainColumn {
        // The eye jumps back up to the skills block it skated past — the
        // out-of-order dart the eye-tracking maps actually show.
        add(mainLeft + 0.16, skillsY, 0.4, "Skills glance")
      } else {
        add(mainLeft + 0.16, min(0.75, previousRoleY + roleBlock), 0.4, "Skills glance")
      }
    }
    if let railX {
      add(railX, 0.62, 0.9, "Education check")
    } else {
      add(mainLeft + 0.12, 0.84, 0.9, "Education check")
    }

    // A visible portrait steals a fixed share of the scan; everything else
    // shrinks proportionally so the total stays honest.
    if document.showsPortrait {
      let portraitDwell = 1.5
      let scale = (RecruiterScanStudy.scanSeconds - portraitDwell) / RecruiterScanStudy.scanSeconds
      stops = stops.map {
        RecruiterGazeStop(point: $0.point, duration: $0.duration * scale, label: $0.label)
      }
      let portraitX: CGFloat = document.template.isPhotoLed ? 0.5 : (railX ?? mainLeft + 0.06)
      let portrait = RecruiterGazeStop(
        point: CGPoint(x: portraitX, y: 0.09),
        duration: portraitDwell,
        label: "The portrait")
      stops.insert(portrait, at: 0)
    }

    return stops
  }
}

private extension String {
  var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
