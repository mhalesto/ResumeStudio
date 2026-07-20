import Foundation
import PDFKit
import UIKit

/// A supporting document printed after the last page of the résumé — a
/// certificate, a portfolio page, a reference letter, a transcript.
///
/// The payload lives inside the résumé itself, exactly as the portrait does, so
/// everything that already takes a `ResumeDocument` — the PDF export, iCloud
/// sync, the library archive, Review Rooms, trackable links, packet exports —
/// carries attachments without needing to know they exist.
///
/// That choice is what makes the import caps in `ResumeAttachmentLimits` matter:
/// the draft is a JSON file rewritten on every edit, so an unbounded payload
/// here would be re-encoded on every keystroke. Images are re-encoded down to
/// print resolution on the way in, and an oversized PDF is flattened rather than
/// stored whole.
struct ResumeAttachment: Identifiable, Codable, Equatable {
  enum Kind: String, Codable {
    case image
    case pdf
  }

  var id: UUID

  /// Printed above the artwork, and the row's name in the editor.
  var title: String

  var kind: Kind

  /// A JPEG, or the bytes of a PDF. Always the output of `ResumeAttachmentImporter`.
  var data: Data

  /// How many pages this adds to the export, measured once at import.
  var pageCount: Int

  /// Per-version inclusion, like the portrait's visibility toggle: unchecking it
  /// keeps the file on the résumé but leaves it out of the export.
  var isIncluded: Bool

  /// Off for artwork that carries its own heading, so nothing is printed over it.
  var showsTitleOnPage: Bool

  init(
    id: UUID = UUID(),
    title: String,
    kind: Kind,
    data: Data,
    pageCount: Int,
    isIncluded: Bool = true,
    showsTitleOnPage: Bool = true
  ) {
    self.id = id
    self.title = title
    self.kind = kind
    self.data = data
    self.pageCount = max(0, pageCount)
    self.isIncluded = isIncluded
    self.showsTitleOnPage = showsTitleOnPage
  }

  private enum CodingKeys: String, CodingKey {
    case id, title, kind, data, pageCount, isIncluded, showsTitleOnPage
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
    kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .image
    data = try container.decode(Data.self, forKey: .data)
    pageCount = max(0, try container.decodeIfPresent(Int.self, forKey: .pageCount) ?? 1)
    isIncluded = try container.decodeIfPresent(Bool.self, forKey: .isIncluded) ?? true
    showsTitleOnPage = try container.decodeIfPresent(Bool.self, forKey: .showsTitleOnPage) ?? true
  }

  var displayTitle: String {
    title.isBlank ? String(localized: "Untitled attachment") : title
  }

  var formattedSize: String {
    Int64(data.count).formatted(.byteCount(style: .file))
  }

  /// "PDF · 3 pages · 412 KB" — the row's subtitle in the editor.
  var summary: String {
    let type = kind == .pdf ? String(localized: "PDF") : String(localized: "Image")
    let pages =
      pageCount == 1
      ? String(localized: "1 page") : String(localized: "\(pageCount) pages")
    return "\(type) · \(pages) · \(formattedSize)"
  }

  /// A small rendering of the first page, for the editor list. Rebuilding this
  /// decodes the whole payload, so callers cache it rather than calling from
  /// inside a SwiftUI body.
  @MainActor
  func thumbnail(maxDimension: CGFloat = 220) -> UIImage? {
    switch kind {
    case .image:
      guard let image = UIImage(data: data) else { return nil }
      let longest = max(image.size.width, image.size.height)
      guard longest > maxDimension else { return image }
      let scale = maxDimension / longest
      let target = CGSize(
        width: (image.size.width * scale).rounded(),
        height: (image.size.height * scale).rounded()
      )
      let format = UIGraphicsImageRendererFormat.default()
      format.scale = 1
      format.opaque = true
      return UIGraphicsImageRenderer(size: target, format: format).image { _ in
        image.draw(in: CGRect(origin: .zero, size: target))
      }
    case .pdf:
      guard let page = PDFDocument(data: data)?.page(at: 0) else { return nil }
      let bounds = page.bounds(for: .mediaBox)
      guard bounds.width > 0, bounds.height > 0 else { return nil }
      let scale = maxDimension / max(bounds.width, bounds.height)
      let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
      return page.thumbnail(of: size, for: .mediaBox)
    }
  }
}

extension ResumeAttachment: Hashable {
  /// Identity and size, never the bytes: a document carrying several megabytes of
  /// attachments is hashed wherever SwiftUI diffs it, and hashing the payload
  /// would make that walk every byte. Equal attachments still agree here,
  /// because equality implies the same id.
  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
    hasher.combine(data.count)
  }
}

// MARK: - Document helpers

extension ResumeDocument {
  /// The attachments that will actually be printed, in the order they appear in
  /// the editor. An attachment that measured zero pages is skipped rather than
  /// producing a blank sheet.
  var includedAttachments: [ResumeAttachment] {
    attachments.filter { $0.isIncluded && $0.pageCount > 0 }
  }

  /// How many pages the attachments add to the export.
  var attachmentPageCount: Int {
    includedAttachments.reduce(0) { $0 + $1.pageCount }
  }

  var attachmentByteCount: Int {
    attachments.reduce(0) { $0 + $1.data.count }
  }

  /// Whether another file would fit, so the editor can explain the limit before
  /// the user picks a file rather than after.
  func canAcceptAttachment(ofSize bytes: Int) -> Bool {
    attachments.count < ResumeAttachmentLimits.maxAttachments
      && attachmentByteCount + bytes <= ResumeAttachmentLimits.maxTotalBytes
  }
}

// MARK: - Limits

enum ResumeAttachmentLimits {
  static let maxAttachments = 10

  /// Per file, after preparation. A PDF above this is flattened to fit.
  static let maxPreparedBytes = 4 * 1024 * 1024

  /// Across the whole résumé. The draft is rewritten on every edit, so this is
  /// the number that keeps autosave cheap.
  static let maxTotalBytes = 6 * 1024 * 1024

  /// A guard on the export, not on the library: a malformed PDF reporting an
  /// absurd page count can't turn one export into thousands of pages.
  static let maxExportedPages = 60

  /// ≈200 dpi across A4's long edge — past the point print can show and well
  /// past the point a recruiter's screen can.
  static let imageMaxDimension: CGFloat = 1654

  /// The resolution an oversized PDF is flattened at.
  static let flattenDPI: CGFloat = 144
}

// MARK: - Import

enum ResumeAttachmentError: LocalizedError, Equatable {
  case unreadable
  case emptyDocument
  case tooLarge
  case libraryFull
  case noRoomLeft

  var errorDescription: String? {
    switch self {
    case .unreadable:
      String(localized: "That file could not be read. Attach a PDF, JPG, PNG, or HEIC file.")
    case .emptyDocument:
      String(localized: "That PDF has no pages to attach.")
    case .tooLarge:
      String(
        localized:
          "That file is too large to attach, even after compression. Export it at a smaller size and try again."
      )
    case .libraryFull:
      String(
        localized:
          "You can attach up to \(ResumeAttachmentLimits.maxAttachments) files to one résumé. Remove one to add another."
      )
    case .noRoomLeft:
      String(
        localized:
          "Your attachments have reached the size limit for one résumé. Remove one to add another."
      )
    }
  }
}

/// Turns a picked photo or file into something safe to store in the draft.
enum ResumeAttachmentImporter {
  /// Detection reads the bytes rather than trusting the picker's declared type:
  /// files arrive from Photos, Files, share sheets and drag and drop, and the
  /// type they claim is not always the type they are.
  @MainActor
  static func make(title: String, from data: Data) throws -> ResumeAttachment {
    guard !data.isEmpty else { throw ResumeAttachmentError.unreadable }

    if let pdf = PDFDocument(data: data) {
      guard pdf.pageCount > 0 else { throw ResumeAttachmentError.emptyDocument }
      return ResumeAttachment(
        title: title,
        kind: .pdf,
        data: try preparedPDF(data, document: pdf),
        pageCount: pdf.pageCount
      )
    }

    guard let prepared = preparedImage(data) else { throw ResumeAttachmentError.unreadable }
    return ResumeAttachment(title: title, kind: .image, data: prepared, pageCount: 1)
  }

  /// A PDF is kept exactly as it arrived whenever it fits — that keeps its text
  /// selectable and its vectors sharp. Only an oversized one is flattened, and
  /// only as far as it takes to fit.
  @MainActor
  private static func preparedPDF(_ data: Data, document: PDFDocument) throws -> Data {
    guard data.count > ResumeAttachmentLimits.maxPreparedBytes else { return data }
    for dpi in [ResumeAttachmentLimits.flattenDPI, 110, 96] {
      guard let flattened = flattened(document, dpi: dpi) else { continue }
      if flattened.count <= ResumeAttachmentLimits.maxPreparedBytes { return flattened }
    }
    throw ResumeAttachmentError.tooLarge
  }

  /// Redraws every page as a compressed raster of itself. Used only as a rescue
  /// for a PDF too big to keep whole, so the loss of selectable text is the
  /// price of the file being attachable at all.
  @MainActor
  private static func flattened(_ document: PDFDocument, dpi: CGFloat) -> Data? {
    guard let first = document.page(at: 0) else { return nil }
    let scale = dpi / 72
    let renderer = UIGraphicsPDFRenderer(bounds: first.bounds(for: .mediaBox))
    return renderer.pdfData { context in
      for index in 0..<document.pageCount {
        guard let page = document.page(at: index) else { continue }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { continue }
        context.beginPage(withBounds: bounds, pageInfo: [:])

        let pixels = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let raster = UIGraphicsImageRenderer(size: pixels, format: format).image { imageContext in
          let cgContext = imageContext.cgContext
          UIColor.white.setFill()
          cgContext.fill(CGRect(origin: .zero, size: pixels))
          cgContext.translateBy(x: 0, y: pixels.height)
          cgContext.scaleBy(x: scale, y: -scale)
          cgContext.translateBy(x: -bounds.minX, y: -bounds.minY)
          page.draw(with: .mediaBox, to: cgContext)
        }

        // Back through JPEG so the page embeds compressed pixels rather than the
        // bitmap the renderer just produced.
        let compressed = raster.jpegData(compressionQuality: 0.7).flatMap(UIImage.init(data:))
        (compressed ?? raster).draw(in: CGRect(origin: .zero, size: bounds.size))
      }
    }
  }

  /// Downscales to print resolution and re-encodes as JPEG, stepping the size and
  /// quality down together until the result fits.
  @MainActor
  private static func preparedImage(_ data: Data) -> Data? {
    guard let image = UIImage(data: data) else { return nil }

    let attempts: [(CGFloat, CGFloat)] = [
      (ResumeAttachmentLimits.imageMaxDimension, 0.82),
      (ResumeAttachmentLimits.imageMaxDimension, 0.68),
      (1240, 0.62),
      (992, 0.55),
    ]

    var smallest: Data?
    for (dimension, quality) in attempts {
      guard let encoded = encoded(image, maxDimension: dimension, quality: quality) else { continue }
      smallest = encoded
      if encoded.count <= ResumeAttachmentLimits.maxPreparedBytes { return encoded }
    }
    return smallest
  }

  @MainActor
  private static func encoded(_ image: UIImage, maxDimension: CGFloat, quality: CGFloat) -> Data? {
    let longest = max(image.size.width, image.size.height)
    guard longest > 0 else { return nil }
    let scale = min(1, maxDimension / longest)
    let target = CGSize(
      width: max(1, (image.size.width * scale).rounded()),
      height: max(1, (image.size.height * scale).rounded())
    )

    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = true
    let resized = UIGraphicsImageRenderer(size: target, format: format).image { context in
      UIColor.white.setFill()
      context.cgContext.fill(CGRect(origin: .zero, size: target))
      image.draw(in: CGRect(origin: .zero, size: target))
    }
    return resized.jpegData(compressionQuality: quality)
  }

  /// A readable default title from a picked file's name: "AWS-certificate.pdf"
  /// becomes "AWS certificate".
  static func suggestedTitle(fromFilename filename: String) -> String {
    let base = (filename as NSString).deletingPathExtension
    let cleaned =
      base
      .replacingOccurrences(of: "_", with: " ")
      .replacingOccurrences(of: "-", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? String(localized: "Attachment") : cleaned
  }
}
