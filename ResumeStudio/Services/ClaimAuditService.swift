import Foundation

/// Audits every claim a résumé makes against what the same document — and the
/// evidence vault behind it — actually demonstrates.
///
/// Entirely on device and free of AI credits, like the recruiter scan and
/// opportunity ranking: this is matching, not generation. Nothing here is sent
/// anywhere, which matters, because the input is the reader's whole career.
///
/// The service never rewrites and never contradicts a claim. Its only assertion
/// is about **visibility** — whether support for a line can be found without
/// taking the writer's word for it.
enum ClaimAuditService {

  // MARK: - Entry point

  static func audit(
    document: ResumeDocument,
    evidence: [CareerEvidence] = [],
    attestations: [EvidenceAttestation] = []
  ) -> ClaimAuditReport {
    // What the page itself demonstrates. Competencies are excluded on purpose:
    // a skills list cannot be its own evidence, and treating it as such would
    // hide the exact failure this feature exists to surface.
    //
    // Built up in steps rather than one concatenation — the single expression
    // pushed the type checker past its limit.
    var demonstrations: [String] = []
    for entry in document.experience {
      demonstrations.append(entry.role)
      demonstrations.append(contentsOf: entry.highlights)
    }
    for entry in document.education {
      demonstrations.append(entry.qualification + " " + entry.details)
    }
    for section in document.additionalSections {
      demonstrations.append(contentsOf: section.items)
    }

    let confirmedEvidenceIDs = Set(
      attestations.filter(\.isConfirmed).map(\.evidenceID)
    )

    var claims: [AuditedClaim] = []

    for (index, competency) in document.competencies.enumerated()
    where !competency.isBlank {
      claims.append(
        auditCompetency(
          competency,
          id: "competency.\(index)",
          demonstrations: demonstrations,
          evidence: evidence,
          confirmedEvidenceIDs: confirmedEvidenceIDs
        )
      )
    }

    for entry in document.experience {
      for (index, highlight) in entry.highlights.enumerated() where !highlight.isBlank {
        claims.append(
          auditStatement(
            highlight,
            id: "experience.\(entry.id).\(index)",
            origin: .experience(role: entry.role, company: entry.company),
            evidence: evidence,
            confirmedEvidenceIDs: confirmedEvidenceIDs
          )
        )
      }
    }

    for section in document.additionalSections {
      for (index, item) in section.items.enumerated() where !item.isBlank {
        claims.append(
          auditStatement(
            item,
            id: "section.\(section.id).\(index)",
            origin: .additionalSection(title: section.title),
            evidence: evidence,
            confirmedEvidenceIDs: confirmedEvidenceIDs
          )
        )
      }
    }

    return ClaimAuditReport(claims: claims)
  }

  // MARK: - Competencies

  /// A named skill. The question a hiring manager asks of one — reported
  /// repeatedly as the thing that gets a résumé binned — is simply: does
  /// anything in the history show this happening?
  private static func auditCompetency(
    _ competency: String,
    id: String,
    demonstrations: [String],
    evidence: [CareerEvidence],
    confirmedEvidenceIDs: Set<UUID>
  ) -> AuditedClaim {
    let supporting = matchingEvidence(for: competency, in: evidence)
    let isConfirmed = supporting.contains { confirmedEvidenceIDs.contains($0) }
    let demonstratedBy = demonstrations.first { demonstrates(competency, in: $0) }

    // An attribute is a personality trait rather than something done. It cannot
    // be demonstrated by a bullet because it never describes an action, so it is
    // reported as bare whatever else the page says.
    if isAttribute(competency) {
      return AuditedClaim(
        id: id,
        text: competency,
        origin: .competency,
        backing: .bare,
        rationale:
          "This reads as a personal quality rather than something you did. A reader can't check it, so it does more work in an interview than on the page.",
        supportingEvidenceIDs: supporting,
        isConfirmedByReferee: isConfirmed
      )
    }

    if isConfirmed {
      return AuditedClaim(
        id: id,
        text: competency,
        origin: .competency,
        backing: .provable,
        rationale: "A referee has confirmed the evidence behind this skill.",
        supportingEvidenceIDs: supporting,
        isConfirmedByReferee: true
      )
    }

    if let demonstratedBy {
      // Demonstrated *and* quantified is the combination that survives being
      // asked about.
      let backing: ClaimBacking = carriesFigure(demonstratedBy) ? .provable : .assertable
      return AuditedClaim(
        id: id,
        text: competency,
        origin: .competency,
        backing: backing,
        rationale: backing == .provable
          ? "Shown with a figure: \u{201C}\(shorten(demonstratedBy))\u{201D}"
          : "Shown, but without a figure: \u{201C}\(shorten(demonstratedBy))\u{201D}",
        supportingEvidenceIDs: supporting,
        isConfirmedByReferee: false
      )
    }

    if !supporting.isEmpty {
      return AuditedClaim(
        id: id,
        text: competency,
        origin: .competency,
        backing: .assertable,
        rationale:
          "Your evidence vault has something for this, but no experience bullet mentions it — so it is missing from the résumé a reader actually sees.",
        supportingEvidenceIDs: supporting,
        isConfirmedByReferee: false
      )
    }

    return AuditedClaim(
      id: id,
      text: competency,
      origin: .competency,
      backing: .bare,
      rationale:
        "No bullet in your history mentions this, and nothing in your evidence vault covers it.",
      supportingEvidenceIDs: [],
      isConfirmedByReferee: false
    )
  }

  // MARK: - Bullets and section items

  /// A written statement — a bullet, a project line. It is already on the page,
  /// so the question is not whether it appears but whether it carries anything a
  /// reader can hold on to: a figure, a named piece of work, a confirmation.
  private static func auditStatement(
    _ statement: String,
    id: String,
    origin: ClaimOrigin,
    evidence: [CareerEvidence],
    confirmedEvidenceIDs: Set<UUID>
  ) -> AuditedClaim {
    let supporting = matchingEvidence(for: statement, in: evidence)
    let isConfirmed = supporting.contains { confirmedEvidenceIDs.contains($0) }

    if isConfirmed {
      return AuditedClaim(
        id: id, text: statement, origin: origin, backing: .provable,
        rationale: "A referee has confirmed this.",
        supportingEvidenceIDs: supporting, isConfirmedByReferee: true)
    }

    if carriesFigure(statement) {
      return AuditedClaim(
        id: id, text: statement, origin: origin, backing: .provable,
        rationale: "Carries a figure, which is the part that cannot be invented without consequences at interview.",
        supportingEvidenceIDs: supporting, isConfirmedByReferee: false)
    }

    if isAttribute(statement) || isFiller(statement) {
      return AuditedClaim(
        id: id, text: statement, origin: origin, backing: .bare,
        rationale:
          "This describes a duty or a quality rather than an outcome. What changed because you did it?",
        supportingEvidenceIDs: supporting, isConfirmedByReferee: false)
    }

    return AuditedClaim(
      id: id, text: statement, origin: origin, backing: .assertable,
      rationale: "Specific, but with no figure a reader can weigh. A number here would make it provable.",
      supportingEvidenceIDs: supporting, isConfirmedByReferee: false)
  }

  // MARK: - Matching

  /// Whether `claim` is demonstrated by `text`.
  ///
  /// Every meaningful word of the claim has to appear, so a two-word skill needs
  /// real support rather than one incidental hit: "stakeholder management" is
  /// not demonstrated by a bullet that merely says "managed".
  static func demonstrates(_ claim: String, in text: String) -> Bool {
    let claimStems = Set(stems(of: claim))
    guard !claimStems.isEmpty else { return false }
    return claimStems.allSatisfy { stem in
      stems(of: text).contains { matches($0, stem) }
    }
  }

  private static func matchingEvidence(for claim: String, in evidence: [CareerEvidence]) -> [UUID] {
    evidence.filter { item in
      demonstrates(claim, in: ([item.title, item.detail] + item.tags).joined(separator: " "))
    }.map(\.id)
  }

  /// Reduces a word to a comparable root.
  ///
  /// A five-character prefix, after mapping the irregular verbs a résumé leans
  /// on. This is deliberately blunt rather than a real stemmer: it converges
  /// manage/managed/management/manager, negotiate/negotiation and
  /// analyse/analysis/analytical, which is most of the vocabulary in play. It
  /// will occasionally collide two unrelated words — the cost of that is one
  /// claim reported as supported when it isn't, which is why the report's
  /// language stays advisory throughout.
  static func stem(_ word: String) -> String {
    let normalized = word.lowercased().filter { $0.isLetter }
    // The irregular map has to run before any length test: "led" is three
    // characters and would otherwise be discarded as noise before it could
    // become "lead", losing the most common leadership evidence on a résumé.
    let root = irregulars[normalized] ?? normalized
    guard root.count > 3 else { return root }
    return String(root.prefix(5))
  }

  private static func matches(_ lhs: String, _ rhs: String) -> Bool {
    guard lhs.count >= 4, rhs.count >= 4 else { return false }
    return lhs.hasPrefix(rhs) || rhs.hasPrefix(lhs)
  }

  private static func stems(of text: String) -> [String] {
    text.lowercased()
      .components(separatedBy: CharacterSet.letters.inverted)
      .filter { !$0.isEmpty && !stopWords.contains($0) }
      .map(stem)
      // Length is judged on the stem, so short irregulars survive while genuine
      // noise ("the", "and") still drops out.
      .filter { $0.count > 3 }
  }

  /// Past tenses that no prefix rule reaches, limited to verbs that actually
  /// carry weight on a résumé.
  private static let irregulars: [String: String] = [
    "led": "lead", "built": "build", "grew": "grow", "ran": "run",
    "wrote": "write", "drove": "drive", "won": "win", "sold": "sell",
    "spoke": "speak", "taught": "teach", "brought": "bring", "made": "make",
    "met": "meet", "held": "hold", "took": "take", "gave": "give",
    "began": "begin", "chose": "choose", "spent": "spend", "sent": "send",
    "rebuilt": "build", "oversaw": "oversee", "shrank": "shrink",
  ]

  private static let stopWords: Set<String> = [
    "with", "from", "that", "this", "were", "have", "into", "their", "them",
    "then", "than", "these", "those", "which", "while", "about", "across",
    "after", "also", "been", "being", "both", "each", "more", "most", "other",
    "over", "such", "through", "under", "using", "within", "would", "your",
  ]

  // MARK: - Signals

  /// Whether a statement carries a figure a reader can weigh.
  ///
  /// A bare four-digit year does not count: dates say when, not how much, and
  /// counting them would mark every dated bullet as proven.
  static func carriesFigure(_ text: String) -> Bool {
    let numbers = text.components(separatedBy: CharacterSet.decimalDigits.inverted)
      .filter { !$0.isEmpty }
    guard !numbers.isEmpty else { return false }
    return numbers.contains { number in
      guard number.count == 4, let year = Int(number) else { return true }
      return !(1900...2100).contains(year)
    }
  }

  /// Personality traits, which belong in an interview rather than in a claim.
  /// A reader cannot check "detail-oriented" against anything.
  static func isAttribute(_ text: String) -> Bool {
    let lower = text.lowercased()
    return attributeMarkers.contains { lower.contains($0) }
  }

  private static let attributeMarkers = [
    "detail-oriented", "detail oriented", "results-driven", "results driven",
    "team player", "self-starter", "self starter", "hard-working", "hard working",
    "hardworking", "go-getter", "passionate", "motivated", "enthusiastic",
    "dynamic", "proactive", "driven professional", "excellent communication",
    "strong communication", "good communicator", "excellent interpersonal",
    "works well under pressure", "think outside the box", "fast learner",
    "quick learner", "problem solver", "problem-solver", "strong work ethic",
  ]

  /// Duty language: describes the job that was assigned rather than anything
  /// that came of it.
  static func isFiller(_ text: String) -> Bool {
    let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    return fillerOpenings.contains { lower.hasPrefix($0) }
  }

  private static let fillerOpenings = [
    "responsible for", "duties included", "tasked with", "helped with",
    "assisted with", "worked on", "involved in", "participated in",
    "in charge of", "handled",
  ]

  /// Keeps a quoted bullet short enough to sit inside a rationale line.
  private static func shorten(_ text: String, limit: Int = 68) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > limit else { return trimmed }
    return trimmed.prefix(limit).trimmingCharacters(in: .whitespaces) + "\u{2026}"
  }
}
