import PDFKit
import XCTest

@testable import ResumeStudio

@MainActor
final class ResumeStudioTests: XCTestCase {
  func testTemplateCatalogueContainsThirteenDistinctStyles() {
    XCTAssertEqual(ResumeTemplate.allCases.count, 13)
    XCTAssertEqual(Set(ResumeTemplate.allCases.map(\.title)).count, 13)
  }

  func testEveryTemplateRendersSearchablePDF() throws {
    for template in ResumeTemplate.allCases {
      var source = ResumeDocument.example
      source.template = template
      let data = try ResumePDFRenderer.render(document: source)

      XCTAssertTrue(data.starts(with: Data("%PDF".utf8)), template.title)

      let pdf = try XCTUnwrap(PDFDocument(data: data))
      XCTAssertGreaterThanOrEqual(pdf.pageCount, 1, template.title)

      let searchableText = (0..<pdf.pageCount)
        .compactMap { pdf.page(at: $0)?.string }
        .joined(separator: "\n")

      XCTAssertTrue(searchableText.contains("Avery Sample"), template.title)
      XCTAssertTrue(searchableText.contains("Riley Example"), template.title)
      XCTAssertTrue(searchableText.contains("Morgan Sample"), template.title)
    }
  }

  func testResumeDocumentRoundTripsThroughJSON() throws {
    let source = ResumeDocument.example
    let data = try JSONEncoder().encode(source)
    let decoded = try JSONDecoder().decode(ResumeDocument.self, from: data)
    XCTAssertEqual(decoded, source)
  }

  func testBlankResumeStillProducesAValidPage() throws {
    let data = try ResumePDFRenderer.render(document: .blank)
    let pdf = try XCTUnwrap(PDFDocument(data: data))
    XCTAssertEqual(pdf.pageCount, 1)
  }

  func testLegacyDevelopmentDraftMigratesToFictionalExample() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("json")
    defer { try? FileManager.default.removeItem(at: url) }

    let encoded = try JSONEncoder().encode(ResumeDocument.example)
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object.removeValue(forKey: "schemaVersion")
    object.removeValue(forKey: "template")
    try JSONSerialization.data(withJSONObject: object).write(to: url)

    let store = ResumeStore(fileURL: url)

    XCTAssertEqual(store.document.schemaVersion, ResumeDocument.currentSchemaVersion)
    XCTAssertEqual(store.document, .example)
  }
}
