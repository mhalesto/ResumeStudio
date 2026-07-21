import XCTest

@testable import ResumeStudio

/// Pins the rules behind "Back It Up".
///
/// The audit makes a claim about someone's career in their own words, so the
/// line it must never cross is asserting that anything is untrue. Every verdict
/// here is about what the page *shows*. These tests exist as much to hold that
/// boundary as to check the matching.
final class ClaimAuditTests: XCTestCase {

  // MARK: - Fixtures

  private func document(
    competencies: [String] = [],
    experience: [ExperienceEntry] = [],
    additionalSections: [ResumeAdditionalSection] = []
  ) -> ResumeDocument {
    var value = ResumeDocument.example
    value.competencies = competencies
    value.experience = experience
    value.education = []
    value.additionalSections = additionalSections
    return value
  }

  private func role(_ highlights: [String]) -> ExperienceEntry {
    ExperienceEntry(
      role: "Operations Lead", company: "Northwind", period: "2022 - Present",
      highlights: highlights)
  }

  private func evidence(
    title: String, detail: String = "", tags: [String] = [], verified: Bool = false
  ) -> CareerEvidence {
    CareerEvidence(
      kind: .achievement, title: title, detail: detail, source: "Self",
      sourceResumeID: nil, tags: tags, isVerified: verified)
  }

  private func confirmedAttestation(for evidenceID: UUID) -> EvidenceAttestation {
    EvidenceAttestation(
      evidenceID: evidenceID, token: "t", claim: "c", context: "",
      status: .confirmed, verifierName: "Dana Reed", verifierRole: "Former manager",
      comment: "Confirmed.", respondedAt: Date(), expiresAt: Date().addingTimeInterval(86_400))
  }

  private func claim(_ report: ClaimAuditReport, containing text: String) throws -> AuditedClaim {
    try XCTUnwrap(
      report.claims.first { $0.text.localizedCaseInsensitiveContains(text) },
      "Expected a claim mentioning \(text).")
  }

  // MARK: - The headline rule

  /// The pattern hiring managers describe binning: a skills list the bullets
  /// never demonstrate.
  func testASkillNoBulletDemonstratesIsReportedBare() throws {
    let report = ClaimAuditService.audit(
      document: document(
        competencies: ["Stakeholder management"],
        experience: [role(["Rebuilt the onboarding flow for new starters."])]))

    let skill = try claim(report, containing: "Stakeholder")
    XCTAssertEqual(skill.backing, .bare)
    XCTAssertTrue(skill.rationale.contains("No bullet"))
    XCTAssertEqual(skill.section, .competencies, "A bare skill has to route to the section that fixes it.")
  }

  func testASkillShownWithoutAFigureIsAssertable() throws {
    let report = ClaimAuditService.audit(
      document: document(
        competencies: ["Stakeholder management"],
        experience: [role(["Managed stakeholders across three product teams."])]))

    XCTAssertEqual(try claim(report, containing: "Stakeholder").backing, .assertable)
  }

  func testASkillShownWithAFigureIsProvable() throws {
    let report = ClaimAuditService.audit(
      document: document(
        competencies: ["Stakeholder management"],
        experience: [role(["Managed 14 stakeholders through a platform migration."])]))

    let skill = try claim(report, containing: "Stakeholder")
    XCTAssertEqual(skill.backing, .provable)
    XCTAssertTrue(skill.rationale.contains("figure"))
  }

  /// A skills list cannot vouch for itself — if it could, the failure this
  /// feature exists to catch would never surface.
  func testASkillIsNotEvidenceForItself() throws {
    let report = ClaimAuditService.audit(
      document: document(
        competencies: ["Stakeholder management", "Stakeholder management strategy"],
        experience: [role(["Rewrote the incident process."])]))

    let skills = report.claims.filter { $0.origin == .competency }
    XCTAssertEqual(skills.count, 2)
    XCTAssertTrue(
      skills.allSatisfy { $0.backing == .bare },
      "Two skills that only echo each other must not come out supported.")
  }

  // MARK: - Attributes and duty language

  func testPersonalAttributesAreBareEvenWhenTheBulletsEchoThem() throws {
    let report = ClaimAuditService.audit(
      document: document(
        competencies: ["Excellent communication"],
        experience: [role(["Excellent communication with 12 partner teams."])]))

    let skill = try claim(report, containing: "communication")
    XCTAssertEqual(
      skill.backing, .bare,
      "An attribute describes a quality, not something done, so a matching bullet cannot prove it.")
    XCTAssertTrue(skill.rationale.contains("personal quality"))
  }

  func testDutyLanguageIsReportedBare() throws {
    let report = ClaimAuditService.audit(
      document: document(experience: [role(["Responsible for the weekly reporting pack."])]))

    let bullet = try claim(report, containing: "reporting pack")
    XCTAssertEqual(bullet.backing, .bare)
    XCTAssertTrue(bullet.rationale.contains("What changed"))
  }

  func testASpecificBulletWithoutAFigureIsAssertableNotBare() throws {
    let report = ClaimAuditService.audit(
      document: document(experience: [role(["Rebuilt the onboarding flow for new starters."])]))

    XCTAssertEqual(try claim(report, containing: "onboarding").backing, .assertable)
  }

  // MARK: - Evidence and referees

  func testAConfirmedRefereeMakesAClaimProvable() throws {
    let item = evidence(title: "Stakeholder management", detail: "Ran the steering group.")
    let report = ClaimAuditService.audit(
      document: document(
        competencies: ["Stakeholder management"],
        experience: [role(["Rewrote the incident process."])]),
      evidence: [item],
      attestations: [confirmedAttestation(for: item.id)])

    let skill = try claim(report, containing: "Stakeholder")
    XCTAssertEqual(skill.backing, .provable)
    XCTAssertTrue(skill.isConfirmedByReferee)
  }

  /// Evidence in the vault that never made it onto the page is real, but the
  /// reader cannot see it — so it lifts the claim only as far as assertable,
  /// and the wording has to say why.
  func testVaultEvidenceMissingFromThePageIsOnlyAssertable() throws {
    let item = evidence(title: "Stakeholder management", detail: "Ran the steering group.")
    let report = ClaimAuditService.audit(
      document: document(
        competencies: ["Stakeholder management"],
        experience: [role(["Rewrote the incident process."])]),
      evidence: [item])

    let skill = try claim(report, containing: "Stakeholder")
    XCTAssertEqual(skill.backing, .assertable)
    XCTAssertEqual(skill.supportingEvidenceIDs, [item.id])
    XCTAssertTrue(skill.rationale.contains("evidence vault"))
  }

  func testAPendingAttestationDoesNotCountAsConfirmation() throws {
    let item = evidence(title: "Stakeholder management")
    var pending = confirmedAttestation(for: item.id)
    pending.status = .pending

    let report = ClaimAuditService.audit(
      document: document(
        competencies: ["Stakeholder management"],
        experience: [role(["Rewrote the incident process."])]),
      evidence: [item], attestations: [pending])

    XCTAssertFalse(try claim(report, containing: "Stakeholder").isConfirmedByReferee)
  }

  // MARK: - Matching

  func testMatchingConnectsInflectionsAndIrregularVerbs() {
    XCTAssertTrue(ClaimAuditService.demonstrates("Management", in: "Managed a team"))
    XCTAssertTrue(ClaimAuditService.demonstrates("Manager", in: "Management of the roadmap"))
    XCTAssertTrue(ClaimAuditService.demonstrates("Leadership", in: "Led a team of eight"))
    XCTAssertTrue(ClaimAuditService.demonstrates("Negotiation", in: "Negotiated three contracts"))
    XCTAssertTrue(ClaimAuditService.demonstrates("Analysis", in: "Analytical review of spend"))
  }

  func testEveryWordOfAMultiWordSkillHasToBeDemonstrated() {
    XCTAssertFalse(
      ClaimAuditService.demonstrates("Stakeholder management", in: "Managed the release calendar"),
      "One incidental word must not carry a two-word claim.")
    XCTAssertTrue(
      ClaimAuditService.demonstrates(
        "Stakeholder management", in: "Managed stakeholders across three teams"))
  }

  // MARK: - Figures

  func testAYearIsNotAFigure() {
    XCTAssertFalse(ClaimAuditService.carriesFigure("Joined the platform team in 2021."))
    XCTAssertTrue(ClaimAuditService.carriesFigure("Cut onboarding from 21 days to 6."))
    XCTAssertTrue(ClaimAuditService.carriesFigure("Grew revenue 40% in 2021."))
  }

  // MARK: - The report

  func testScoreCountsProvableFullyAndAssertableHalf() {
    let report = ClaimAuditService.audit(
      document: document(experience: [
        role([
          "Cut onboarding time by 40%.",  // provable
          "Rebuilt the onboarding flow.",  // assertable
        ])
      ]))

    XCTAssertEqual(report.provableCount, 1)
    XCTAssertEqual(report.assertableCount, 1)
    XCTAssertEqual(report.score, 75, "One full and one half of two claims is 75.")
  }

  /// An empty page is not a well-evidenced one.
  func testAResumeWithNoClaimsScoresZero() {
    let report = ClaimAuditService.audit(document: document())
    XCTAssertTrue(report.claims.isEmpty)
    XCTAssertEqual(report.score, 0)
  }

  func testPriorityFixesLeadWithUnsupportedSkills() throws {
    let report = ClaimAuditService.audit(
      document: document(
        competencies: ["Workforce planning"],
        experience: [role(["Responsible for the weekly reporting pack."])]))

    let first = try XCTUnwrap(report.priorityFixes.first)
    XCTAssertEqual(first.origin, .competency, "An unsupported skill is the cheapest thing to fix.")
    XCTAssertEqual(report.priorityFixes.count, 2)
  }

  func testInterviewDefenceListsWhatCanBeStoodBehindConfirmedFirst() throws {
    let item = evidence(title: "Incident process", detail: "Rewrote it.")
    let report = ClaimAuditService.audit(
      document: document(experience: [
        role(["Cut onboarding time by 40%.", "Rewrote the incident process."])
      ]),
      evidence: [item], attestations: [confirmedAttestation(for: item.id)])

    XCTAssertEqual(report.interviewDefence.count, 2)
    XCTAssertTrue(
      try XCTUnwrap(report.interviewDefence.first).isConfirmedByReferee,
      "A referee-confirmed claim is the one to lead with.")
    XCTAssertTrue(
      report.claims(backed: .bare).isEmpty,
      "Nothing here is unsupported, so the defence sheet covers every claim.")
  }

  // MARK: - A realistic résumé

  /// The built-in example is well written and almost entirely unquantified,
  /// which is exactly the résumé this feature is for. Pinned so a change to the
  /// scoring shows up as a deliberate decision rather than a drift.
  func testTheBuiltInExampleReadsAsMoreClaimedThanShown() {
    let report = ClaimAuditService.audit(document: .example)

    XCTAssertFalse(report.claims.isEmpty)
    XCTAssertGreaterThan(report.bareCount, 0, "Its skills list is not carried by its bullets.")
    XCTAssertLessThan(report.score, 60, "Almost nothing in it carries a figure.")
    XCTAssertTrue(
      report.claims.allSatisfy { !$0.rationale.isEmpty },
      "Every verdict has to explain itself.")
  }
}
