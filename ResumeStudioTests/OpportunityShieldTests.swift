import XCTest

@testable import ResumeStudio

@MainActor
final class OpportunityShieldTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  private var detailedAdvert: String {
    Array(repeating: """
      Lead the people operations programme, coach managers, analyse workforce trends,
      improve employee experience, define policy, partner with business leaders, measure
      outcomes and communicate practical changes across a growing organization.
      """, count: 7).joined(separator: " ")
  }

  private func posting(
    datePosted: Date,
    validThrough: Date? = nil,
    website: String = "https://careers.example.com"
  ) -> String {
    let iso = ISO8601DateFormatter()
    var object: [String: Any] = [
      "@type": "JobPosting",
      "title": "People Operations Manager",
      "datePosted": iso.string(from: datePosted),
      "hiringOrganization": ["name": "Example", "sameAs": website],
      "jobLocation": [
        "address": [
          "addressLocality": "Cape Town", "addressRegion": "Western Cape",
          "addressCountry": "ZA",
        ]
      ],
    ]
    if let validThrough { object["validThrough"] = iso.string(from: validThrough) }
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(data: data, encoding: .utf8)!
  }

  private func inspect(
    _ status: OpportunityPageStatus = .live,
    date: Date? = nil,
    posting: String? = nil
  ) -> OpportunityPageInspection {
    OpportunityPageInspection(
      status: status,
      checkedAt: date ?? now,
      finalURL: "https://careers.example.com/jobs/people-operations",
      httpStatus: status == .removed ? 404 : 200,
      readableText: detailedAdvert,
      structuredPosting: posting
    )
  }

  private func report(
    content: String? = nil,
    recruiterMessage: String = "",
    sourceURL: String = "https://careers.example.com/jobs/people-operations",
    structuredPosting: String? = nil,
    previous: OpportunitySignalReport? = nil,
    inspection: OpportunityPageInspection? = nil,
    now: Date? = nil
  ) -> OpportunitySignalReport {
    OpportunityShieldService.analyze(
      role: "People Operations Manager",
      company: "Example",
      location: "Cape Town",
      salary: "R900,000 per year",
      responsibilities: ["Coach managers", "Improve employee experience"],
      requirements: ["People operations experience", "Workforce analytics"],
      content: content ?? detailedAdvert,
      sourceURL: sourceURL,
      structuredPosting: structuredPosting,
      recruiterMessage: recruiterMessage,
      previous: previous,
      pageInspection: inspection,
      now: now ?? self.now
    )
  }

  func testStructuredPostingKeepsEmployerFreshnessAndLocationEvidence() {
    let raw = posting(
      datePosted: now.addingTimeInterval(-5 * 86_400),
      validThrough: now.addingTimeInterval(20 * 86_400)
    )
    let metadata = OpportunityShieldService.metadata(from: raw)

    XCTAssertEqual(metadata.title, "People Operations Manager")
    XCTAssertEqual(metadata.organization, "Example")
    XCTAssertEqual(metadata.employerWebsite, "https://careers.example.com")
    XCTAssertEqual(metadata.location, "Cape Town, Western Cape, ZA")
    XCTAssertNotNil(metadata.datePosted)
    XCTAssertNotNil(metadata.validThrough)
  }

  func testSpecificRecentOfficialListingHasStrongSignals() {
    let raw = posting(
      datePosted: now.addingTimeInterval(-5 * 86_400),
      validThrough: now.addingTimeInterval(20 * 86_400)
    )
    let result = report(
      structuredPosting: raw,
      inspection: inspect(.live, posting: raw)
    )

    XCTAssertEqual(result.band, .strong)
    XCTAssertEqual(result.confidence, .strong)
    XCTAssertEqual(result.pageStatus, .live)
    XCTAssertTrue(result.findings.contains { $0.id == "employer-domain-match" })
    XCTAssertTrue(result.findings.contains { $0.id == "freshness-recent" })
    XCTAssertTrue(result.findings.contains { $0.id == "safety-no-common-traps" })
  }

  func testPaymentAndChequeLanguageIsHighRiskEvenWhenListingLooksSpecific() {
    let result = report(
      content: detailedAdvert + " Buy gift cards for equipment and deposit a cheque we send you.",
      structuredPosting: posting(datePosted: now.addingTimeInterval(-3 * 86_400)),
      inspection: inspect()
    )

    XCTAssertEqual(result.band, .highRisk)
    XCTAssertTrue(result.findings.contains {
      $0.id == "safety-payment" && $0.severity == .danger
    })
  }

  func testFreeEmailAndMessagingOnlyContactRequiresVerification() {
    let result = report(
      recruiterMessage: "Contact hiringdesk@gmail.com on WhatsApp only to continue.",
      structuredPosting: posting(datePosted: now.addingTimeInterval(-3 * 86_400)),
      inspection: inspect()
    )

    XCTAssertEqual(result.band, .verify)
    XCTAssertTrue(result.findings.contains { $0.id == "safety-free-email" })
    XCTAssertTrue(result.findings.contains { $0.id == "safety-message-only" })
  }

  func testRemovedPageIsAConcreteHighRiskFreshnessSignal() {
    let raw = posting(datePosted: now.addingTimeInterval(-10 * 86_400))
    let result = report(
      structuredPosting: raw,
      inspection: inspect(.removed, posting: raw)
    )

    XCTAssertEqual(result.band, .highRisk)
    XCTAssertEqual(result.pageStatus, .removed)
    XCTAssertTrue(result.findings.contains { $0.id == "freshness-page-removed" })
  }

  func testMovedPostingDateRecordsARepostAndCheckHistory() {
    let firstPosting = posting(datePosted: now.addingTimeInterval(-20 * 86_400))
    let first = report(
      structuredPosting: firstPosting,
      inspection: inspect(.live, date: now.addingTimeInterval(-5 * 86_400), posting: firstPosting),
      now: now.addingTimeInterval(-5 * 86_400)
    )
    let secondPosting = posting(datePosted: now.addingTimeInterval(-2 * 86_400))
    let second = report(
      structuredPosting: secondPosting,
      previous: first,
      inspection: inspect(.live, posting: secondPosting)
    )

    XCTAssertEqual(second.repostCount, 1)
    XCTAssertEqual(second.checkHistory.count, 2)
    XCTAssertTrue(second.findings.contains { $0.id == "freshness-reposted" })
  }

  func testLegacyCapturedJobSnapshotDecodesWithoutShieldFields() throws {
    let json = """
      {
        "location": "Cape Town",
        "salary": "",
        "closingDate": "",
        "responsibilities": [],
        "requirements": [],
        "warnings": [],
        "originalContent": "Legacy advert",
        "capturedAt": 0
      }
      """
    let decoded = try JSONDecoder().decode(
      CapturedJobSnapshot.self, from: Data(json.utf8))

    XCTAssertNil(decoded.structuredPosting)
    XCTAssertNil(decoded.recruiterMessage)
    XCTAssertNil(decoded.opportunitySignal)
  }

  func testHighRiskFitIsRankedBehindASaferOpportunity() {
    let riskySignal = report(
      content: detailedAdvert + " Pay an application fee by gift card.",
      structuredPosting: posting(datePosted: now.addingTimeInterval(-2 * 86_400)),
      inspection: inspect()
    )
    let safeSignal = report(
      structuredPosting: posting(datePosted: now.addingTimeInterval(-2 * 86_400)),
      inspection: inspect()
    )
    var risky = makeApplication(
      role: "People Operations Manager", advert: detailedAdvert, signal: riskySignal)
    risky.company = "Risky Example"
    let safe = makeApplication(
      role: "Platform Engineer",
      advert: Array(repeating: "Kubernetes platform engineering infrastructure systems delivery", count: 12)
        .joined(separator: " "),
      signal: safeSignal
    )

    let ranking = OpportunityRankingService.rank(
      applications: [risky, safe], document: .example, now: now)

    XCTAssertEqual(ranking.scores.first?.role, "Platform Engineer")
    XCTAssertEqual(ranking.scores.last?.signalBand, .highRisk)
  }

  func testDeadlineAndWarmContactContributeExplainablePriorityReasons() {
    var application = makeApplication(
      role: "People Operations Manager", advert: detailedAdvert,
      signal: report(
        structuredPosting: posting(datePosted: now.addingTimeInterval(-2 * 86_400)),
        inspection: inspect()
      )
    )
    application.deadline = now.addingTimeInterval(2 * 86_400)
    let contact = CareerContact(
      name: "A Recruiter", role: "Recruiter", company: application.company,
      email: "", linkedInURL: "", kind: .recruiter,
      applicationID: nil, notes: "", relationshipStrength: 4
    )

    let score = OpportunityRankingService.score(
      application, document: .example, contacts: [contact], now: now)

    XCTAssertTrue(score.priorityReasons.contains("Deadline is within two days"))
    XCTAssertTrue(score.priorityReasons.contains("Warm contact at this employer"))
    XCTAssertTrue(score.priorityReasons.contains("Strong opportunity signals"))
  }

  private func makeApplication(
    role: String,
    advert: String,
    signal: OpportunitySignalReport
  ) -> JobApplication {
    JobApplication(
      company: "Example",
      role: role,
      jobDescription: advert,
      sourceURL: "https://careers.example.com/jobs/role",
      status: .saved,
      notes: "",
      baseResumeID: UUID(),
      capturedOpportunity: CapturedJobSnapshot(
        location: "Cape Town",
        salary: "R900,000",
        closingDate: "",
        responsibilities: ["Lead programmes"],
        requirements: ["Relevant experience"],
        warnings: [],
        originalContent: advert,
        opportunitySignal: signal
      )
    )
  }
}
