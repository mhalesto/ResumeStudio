import Foundation

/// "Back It Up" — the résumé's claims audited against what actually demonstrates
/// them.
///
/// The ATS checker asks *will the machine read it?*; the recruiter scan asks
/// *what does the human leave with?*; this asks **can the reader see anything
/// behind it?** It exists because the market changed: hiring managers now report
/// rejecting résumés that read as machine-padded, and the pattern they name is
/// specific — a skills list the experience bullets never demonstrate. Quantified
/// outcomes have become the authenticity signal precisely because prose is cheap
/// to generate and a real number is not.
///
/// The distinction that keeps this honest: a verdict is about **what the page
/// shows**, never about whether the claim is true. "Bare" means a reader cannot
/// see the support from the page alone, which is a writing problem with a
/// writing fix — add the example, attach the evidence, or cut the line. The
/// audit never asserts that anything is false, and it never rewrites.
enum ClaimBacking: String, Codable, CaseIterable, Identifiable {
  /// A number, a named artefact, or a referee who confirmed it. The kind of
  /// support that survives being asked about in an interview.
  case provable
  /// Something in the history or the evidence vault demonstrates it, but the
  /// page carries no figure. Defensible out loud; thin on paper.
  case assertable
  /// Nothing on the page or in the vault demonstrates it. This is the pattern
  /// hiring managers describe binning: a claim the rest of the résumé forgets.
  case bare

  var id: String { rawValue }

  var title: LocalizedStringResource {
    switch self {
    case .provable: "Provable"
    case .assertable: "Assertable"
    case .bare: "Bare"
    }
  }

  var detail: LocalizedStringResource {
    switch self {
    case .provable: "Carries a figure, a named piece of work, or a confirmation."
    case .assertable: "You could defend it in an interview, but the page doesn't show it."
    case .bare: "Nothing on the page demonstrates this claim."
    }
  }

  var systemImage: String {
    switch self {
    case .provable: "checkmark.seal.fill"
    case .assertable: "text.badge.checkmark"
    case .bare: "questionmark.circle.fill"
    }
  }
}

/// Where on the résumé a claim was made. Carried so a finding can send the
/// reader to the exact place that fixes it, the way the recruiter scan's
/// "Fix in <section>" rows do.
enum ClaimOrigin: Equatable, Codable {
  /// One entry in the core competencies list — the section the research
  /// singles out, because it is the cheapest place to make a claim.
  case competency
  /// One achievement bullet under a role.
  case experience(role: String, company: String)
  /// An item in a custom section: projects, certifications, volunteering.
  case additionalSection(title: String)

  var section: ResumeSection {
    switch self {
    case .competency: .competencies
    case .experience: .experience
    case .additionalSection: .experience
    }
  }

  /// Where this claim sits, for display above the claim itself.
  var label: String {
    switch self {
    case .competency:
      String(localized: "Core competencies")
    case .experience(let role, let company):
      [role, company].filter { !$0.isBlank }.joined(separator: " — ")
    case .additionalSection(let title):
      title
    }
  }
}

/// One claim, and what the résumé offers in support of it.
struct AuditedClaim: Identifiable, Equatable {
  let id: String
  /// The claim as written, quoted back unchanged — the reader has to recognise
  /// their own line.
  let text: String
  let origin: ClaimOrigin
  let backing: ClaimBacking
  /// Why this verdict, in one sentence, naming what was or wasn't found. Never
  /// a rewrite and never a judgement about the truth of the claim.
  let rationale: String
  /// Evidence-vault items that demonstrate this claim, if any.
  let supportingEvidenceIDs: [UUID]
  /// Set when a referee has confirmed the evidence behind this claim.
  let isConfirmedByReferee: Bool

  var section: ResumeSection { origin.section }
}

/// The audit as a whole.
struct ClaimAuditReport: Equatable {
  let claims: [AuditedClaim]

  init(claims: [AuditedClaim]) {
    self.claims = claims
  }

  func claims(backed backing: ClaimBacking) -> [AuditedClaim] {
    claims.filter { $0.backing == backing }
  }

  var provableCount: Int { claims(backed: .provable).count }
  var assertableCount: Int { claims(backed: .assertable).count }
  var bareCount: Int { claims(backed: .bare).count }

  /// How much of the résumé a reader can see support for, 0–100.
  ///
  /// A provable claim counts fully and an assertable one counts half: it is
  /// genuinely weaker on the page, but calling it worthless would push people
  /// to stuff invented numbers into honest lines, which is the opposite of the
  /// point. A résumé with no claims at all scores zero rather than a hundred —
  /// an empty page is not a well-evidenced one.
  var score: Int {
    guard !claims.isEmpty else { return 0 }
    let earned = Double(provableCount) + Double(assertableCount) * 0.5
    return Int((earned / Double(claims.count) * 100).rounded())
  }

  /// The one-line result. Deliberately about the page rather than the person.
  var verdict: LocalizedStringResource {
    switch score {
    case 80...: "A reader can see the proof"
    case 60..<80: "Mostly supported, with gaps"
    case 35..<60: "More claimed than shown"
    default: "The page asserts more than it demonstrates"
    }
  }

  /// The claims most worth fixing first: bare ones, competencies before
  /// bullets, because an unsupported skills list is the pattern hiring managers
  /// say they reject on and the fastest thing to correct.
  var priorityFixes: [AuditedClaim] {
    claims(backed: .bare).sorted { lhs, rhs in
      if (lhs.origin == .competency) != (rhs.origin == .competency) {
        return lhs.origin == .competency
      }
      return lhs.text < rhs.text
    }
  }

  /// The claims to rehearse before an interview: everything a reader can see,
  /// strongest first. Same audit, different question — these are the lines you
  /// will be asked to stand behind.
  var interviewDefence: [AuditedClaim] {
    (claims(backed: .provable) + claims(backed: .assertable))
      .sorted { lhs, rhs in
        if lhs.isConfirmedByReferee != rhs.isConfirmedByReferee {
          return lhs.isConfirmedByReferee
        }
        return lhs.text < rhs.text
      }
  }
}
