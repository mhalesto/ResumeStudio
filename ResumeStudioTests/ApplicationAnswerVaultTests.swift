import XCTest

@testable import ResumeStudio

@MainActor
final class ApplicationAnswerVaultTests: XCTestCase {
  func testStarterVaultCoversCommonScreeningQuestionsWithoutPublishingBlanks() {
    let starters = ApplicationAnswer.starterEntries

    XCTAssertEqual(starters.count, 7)
    XCTAssertEqual(Set(starters.map(\.category)).count, starters.count)
    XCTAssertTrue(starters.allSatisfy { !$0.canPublish })
    XCTAssertTrue(
      starters.first(where: { $0.category == .workAuthorization })?
        .matchTerms.contains("authorized to work") == true
    )
  }

  func testVaultPersistsEditsAndOnlyEnablesCompletedAnswers() {
    let suiteName = "ApplicationAnswerVaultTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = ApplicationAnswerVaultStore(defaults: defaults)
    var availability = store.answers.first(where: { $0.category == .availability })!

    store.setEnabled(true, id: availability.id)
    XCTAssertFalse(store.answers.first(where: { $0.id == availability.id })!.isEnabled)

    availability.answer = "I can start after four weeks' notice."
    availability.isEnabled = true
    store.upsert(availability)

    let reloaded = ApplicationAnswerVaultStore(defaults: defaults)
    XCTAssertEqual(reloaded.publishableAnswers.count, 1)
    XCTAssertEqual(reloaded.publishableAnswers.first?.answer, availability.answer)
  }

  func testSafariPayloadExcludesDisabledAndBlankAnswers() {
    let enabled = ApplicationAnswer(
      category: .relocation,
      title: "Are you willing to relocate?",
      answer: "Yes",
      isEnabled: true
    )
    let disabled = ApplicationAnswer(
      category: .compensation,
      title: "What salary do you expect?",
      answer: "Market related",
      isEnabled: false
    )
    let blank = ApplicationAnswer(
      category: .custom,
      title: "Portfolio URL",
      answer: "",
      keywords: ["portfolio"],
      isEnabled: true
    )

    let payload = PlatformIntegrationService.makeSafariApplicationAnswers([
      enabled, disabled, blank,
    ])

    XCTAssertEqual(payload.count, 1)
    XCTAssertEqual(payload.first?["title"] as? String, enabled.title)
    XCTAssertEqual(payload.first?["answer"] as? String, "Yes")
    XCTAssertTrue((payload.first?["matchTerms"] as? [String])?.contains("willing to relocate") == true)
  }
}
