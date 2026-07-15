import PDFKit
import UIKit

/// Renders cover letter previews by actually exporting the letter and taking page 1.
///
/// Same reasoning as `TemplateThumbnailRenderer`: grey bars tell you nothing about
/// what a template does with real prose. These are the genuine article, produced by
/// the same renderer that makes the PDF you send.
@MainActor
enum CoverLetterThumbnailRenderer {
  private static var cache: [Key: UIImage] = [:]

  private struct Key: Hashable {
    let template: CoverLetterTemplate
    let accent: ResumeAccent
    let width: Int
  }

  static func thumbnail(
    template: CoverLetterTemplate,
    accent: ResumeAccent,
    width: CGFloat
  ) -> UIImage? {
    let key = Key(template: template, accent: accent, width: Int(width))
    if let cached = cache[key] { return cached }

    // The example letter, so every style previews with a full page of real
    // correspondence rather than whatever half-written draft is on the go.
    var document = CoverLetterDocument.example
    document.template = template
    document.accent = accent

    guard
      let data = try? CoverLetterPDFRenderer.render(document: document),
      let page = PDFDocument(data: data)?.page(at: 0)
    else { return nil }

    // A4 proportions, so the thumbnail is the page and not a crop of it.
    let size = CGSize(width: width, height: width * 842 / 595)
    let image = page.thumbnail(of: size, for: .mediaBox)
    cache[key] = image
    return image
  }
}
