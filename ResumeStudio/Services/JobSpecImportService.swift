import Foundation
import PDFKit
import UIKit
import UniformTypeIdentifiers
import ZIPFoundation

struct ImportedJobSpec: Equatable {
  let fileName: String
  let text: String
  let wasTruncated: Bool

  var wordCount: Int { text.split(whereSeparator: \.isWhitespace).count }
}

enum JobSpecImportError: LocalizedError {
  case emptyDocument
  case unsupportedFormat(String)

  var errorDescription: String? {
    switch self {
    case .emptyDocument:
      "No readable text was found in that file. Scanned PDFs need selectable text or OCR first."
    case .unsupportedFormat(let extensionName):
      "The .\(extensionName) format is not supported. Choose a PDF, DOCX, RTF, or text file."
    }
  }
}

enum JobSpecImportService {
  static let supportedContentTypes: [UTType] = [
    .pdf,
    .wordProcessingDocument,
    .rtf,
    .plainText,
  ]

  /// Leaves enough room under the server's 90 KB request ceiling for the résumé
  /// snapshot and JSON framing while retaining even unusually long job packs.
  private static let maximumCharacters = 45_000

  static func importDocument(from url: URL) throws -> ImportedJobSpec {
    let accessed = url.startAccessingSecurityScopedResource()
    defer { if accessed { url.stopAccessingSecurityScopedResource() } }

    let rawText: String
    switch url.pathExtension.lowercased() {
    case "pdf":
      guard let document = PDFDocument(url: url) else { throw CocoaError(.fileReadCorruptFile) }
      rawText = (0..<document.pageCount)
        .compactMap { document.page(at: $0)?.string }
        .joined(separator: "\n\n")
    case "docx":
      rawText = try extractDOCX(from: url)
    case "rtf":
      let data = try Data(contentsOf: url)
      rawText = try NSAttributedString(
        data: data,
        options: [.documentType: NSAttributedString.DocumentType.rtf],
        documentAttributes: nil
      ).string
    case "txt", "text", "md":
      rawText = try String(contentsOf: url, encoding: .utf8)
    default:
      throw JobSpecImportError.unsupportedFormat(url.pathExtension.lowercased())
    }

    let cleaned = clean(rawText)
    guard !cleaned.isBlank else { throw JobSpecImportError.emptyDocument }
    let wasTruncated = cleaned.count > maximumCharacters
    let text = wasTruncated
      ? String(cleaned.prefix(maximumCharacters)) + "\n\n[Long job specification shortened for analysis.]"
      : cleaned
    return ImportedJobSpec(fileName: url.lastPathComponent, text: text, wasTruncated: wasTruncated)
  }

  private static func extractDOCX(from url: URL) throws -> String {
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.unzipItem(at: url, to: folder)
    let documentURL = folder.appendingPathComponent("word/document.xml")
    var xml = try String(contentsOf: documentURL, encoding: .utf8)
    xml = xml.replacingOccurrences(of: "</w:p>", with: "\n")
      .replacingOccurrences(of: "<w:tab[^>]*/>", with: "\t", options: .regularExpression)
      .replacingOccurrences(of: "<w:br[^>]*/>", with: "\n", options: .regularExpression)
      .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    return xml
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&apos;", with: "'")
  }

  private static func clean(_ text: String) -> String {
    text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
      .replacingOccurrences(of: " *\n *", with: "\n", options: .regularExpression)
      .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
