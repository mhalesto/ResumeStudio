import PDFKit
import UIKit

/// Renders template previews by actually exporting the résumé and taking page 1.
///
/// The cards used to show abstract grey and orange bars, which told you nothing
/// about what a template does with real content. These are the genuine article:
/// the same renderer that produces the PDF you export, so what you pick is what
/// you get.
@MainActor
enum TemplateThumbnailRenderer {
  private static var cache: [Key: UIImage] = [:]

  private struct Key: Hashable {
    let template: ResumeTemplate
    let accent: ResumeAccent
    let photo: Data?
    let crop: PhotoCrop?
    let width: Int
  }

  /// Preview content. Deliberately the example résumé rather than the user's own
  /// draft: a blank draft would render fifteen near-empty pages, which is useless
  /// for choosing a look. The portrait carries over so the photo templates show
  /// the real face once one is picked.
  private static func sample(
    template: ResumeTemplate, accent: ResumeAccent, photo: Data?, crop: PhotoCrop?
  ) -> ResumeDocument {
    var document = ResumeDocument.example
    document.template = template
    document.accent = accent
    document.photo = photo
    document.photoCrop = crop
    return document
  }

  static func thumbnail(
    template: ResumeTemplate,
    accent: ResumeAccent,
    photo: Data?,
    crop: PhotoCrop?,
    width: CGFloat
  ) -> UIImage? {
    let key = Key(template: template, accent: accent, photo: photo, crop: crop, width: Int(width))
    if let cached = cache[key] { return cached }

    let document = sample(template: template, accent: accent, photo: photo, crop: crop)
    guard
      let data = try? ResumePDFRenderer.render(document: document),
      let page = PDFDocument(data: data)?.page(at: 0)
    else { return nil }

    // A4 proportions, so the thumbnail is the page and not a crop of it.
    let size = CGSize(width: width, height: width * 842 / 595)
    let image = page.thumbnail(of: size, for: .mediaBox)
    cache[key] = image
    return image
  }
}
