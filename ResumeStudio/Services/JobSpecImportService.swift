import Foundation
import PDFKit
import UIKit
import UniformTypeIdentifiers
import Vision
import ZIPFoundation

struct ImportedJobSpec: Equatable {
  let fileName: String
  let text: String
  let wasTruncated: Bool
  let ocrPageCount: Int
  let wasPageLimited: Bool

  var wordCount: Int { text.split(whereSeparator: \.isWhitespace).count }
}

enum JobSpecImportError: LocalizedError {
  case emptyDocument
  case unsupportedFormat(String)

  var errorDescription: String? {
    switch self {
    case .emptyDocument:
      "No readable text was found in that file. Try a clearer scan or image."
    case .unsupportedFormat(let extensionName):
      "The .\(extensionName) format is not supported. Choose a PDF, image, DOCX, RTF, or text file."
    }
  }
}

enum JobSpecImportService {
  static let supportedContentTypes: [UTType] = [
    .pdf,
    .wordProcessingDocument,
    .rtf,
    .plainText,
    .image,
  ]

  /// Leaves enough room under the server's 90 KB request ceiling for the résumé
  /// snapshot and JSON framing while retaining even unusually long job packs.
  private static let maximumCharacters = 45_000

  static func importDocument(
    from url: URL,
    progress: ((Double) async -> Void)? = nil
  ) async throws -> ImportedJobSpec {
    let accessed = url.startAccessingSecurityScopedResource()
    defer { if accessed { url.stopAccessingSecurityScopedResource() } }

    await progress?(0)
    try Task.checkCancellation()
    let rawText: String
    var ocrPageCount = 0
    var wasPageLimited = false
    switch url.pathExtension.lowercased() {
    case "pdf":
      guard let document = PDFDocument(url: url) else { throw CocoaError(.fileReadCorruptFile) }
      let result = try await recognizePDF(document, progress: progress)
      rawText = result.text
      ocrPageCount = result.ocrPageCount
      wasPageLimited = result.wasPageLimited
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
      let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
      guard contentType?.conforms(to: .image) == true,
            let image = UIImage(contentsOfFile: url.path),
            let cgImage = image.cgImage
      else { throw JobSpecImportError.unsupportedFormat(url.pathExtension.lowercased()) }
      rawText = try await recognizeText(in: cgImage)
    }

    try Task.checkCancellation()
    await progress?(1)
    let cleaned = clean(rawText)
    guard !cleaned.isBlank else { throw JobSpecImportError.emptyDocument }
    let wasTruncated = cleaned.count > maximumCharacters || wasPageLimited
    let text = wasTruncated
      ? String(cleaned.prefix(maximumCharacters)) + "\n\n[Long job specification shortened for analysis.]"
      : cleaned
    return ImportedJobSpec(
      fileName: url.lastPathComponent,
      text: text,
      wasTruncated: wasTruncated,
      ocrPageCount: ocrPageCount,
      wasPageLimited: wasPageLimited
    )
  }

  private static func recognizePDF(
    _ document: PDFDocument,
    progress: ((Double) async -> Void)?
  ) async throws -> (text: String, ocrPageCount: Int, wasPageLimited: Bool) {
    // Job packs are normally short. Capping OCR avoids turning an accidental
    // book upload into a long-running task while retaining the useful pages.
    let pageLimit = min(document.pageCount, 20)
    var pages: [String] = []
    var ocrPageCount = 0
    for index in 0..<pageLimit {
      try Task.checkCancellation()
      guard let page = document.page(at: index) else { continue }
      let selectableText = clean(page.string ?? "")
      let text: String
      if selectableText.count >= 20 {
        text = selectableText
      } else if let image = autoreleasepool(invoking: {
        page.thumbnail(of: CGSize(width: 1_400, height: 1_900), for: .mediaBox).cgImage
      }) {
        text = try await recognizeText(in: image)
        ocrPageCount += 1
      } else {
        text = selectableText
      }
      if !text.isBlank { pages.append(text) }
      await progress?(Double(index + 1) / Double(max(pageLimit, 1)))
    }
    return (pages.joined(separator: "\n\n"), ocrPageCount, document.pageCount > pageLimit)
  }

  private static func recognizeText(in image: CGImage) async throws -> String {
    try Task.checkCancellation()
    return try await Task.detached(priority: .userInitiated) {
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      request.automaticallyDetectsLanguage = true
      try VNImageRequestHandler(cgImage: image).perform([request])
      let observations = (request.results ?? []).sorted { left, right in
        let verticalDifference = abs(left.boundingBox.midY - right.boundingBox.midY)
        if verticalDifference > 0.02 { return left.boundingBox.midY > right.boundingBox.midY }
        return left.boundingBox.minX < right.boundingBox.minX
      }
      return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }.value
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
