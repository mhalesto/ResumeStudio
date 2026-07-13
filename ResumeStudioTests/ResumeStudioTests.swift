import PDFKit
import XCTest
@testable import ResumeStudio

@MainActor
final class ResumeStudioTests: XCTestCase {
    func testSampleResumeRendersSearchablePDF() throws {
        let data = try ResumePDFRenderer.render(document: .mandisaSample)

        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))

        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThanOrEqual(pdf.pageCount, 2)

        let searchableText = (0..<pdf.pageCount)
            .compactMap { pdf.page(at: $0)?.string }
            .joined(separator: "\n")

        XCTAssertTrue(searchableText.contains("Mandisa Nkabinde"))
        XCTAssertTrue(searchableText.contains("Triselle Munsamy"))
        XCTAssertTrue(searchableText.contains("Philile Mbambo"))
    }

    func testResumeDocumentRoundTripsThroughJSON() throws {
        let source = ResumeDocument.mandisaSample
        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(ResumeDocument.self, from: data)
        XCTAssertEqual(decoded, source)
    }

    func testBlankResumeStillProducesAValidPage() throws {
        let data = try ResumePDFRenderer.render(document: .blank)
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(pdf.pageCount, 1)
    }
}
