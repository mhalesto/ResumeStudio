import PDFKit
import UIKit

/// Renders cover letter previews by actually exporting the letter and taking page 1.
///
/// Same reasoning as `TemplateThumbnailRenderer`: grey bars tell you nothing about
/// what a template does with real prose. These are the genuine article, produced by
/// the same renderer that makes the PDF you send. Results are cached in memory and
/// on disk, render at one canonical resolution, and pass through the shared gate,
/// for the same performance reasons documented there.
@MainActor
enum CoverLetterThumbnailRenderer {
  private static var cache: [Key: UIImage] = [:]

  static let renderWidth: CGFloat = 640

  private struct Key: Hashable {
    let template: CoverLetterTemplate
    let accent: ResumeAccent

    var diskName: String { "cover-\(template.rawValue)-\(accent.rawValue)" }
  }

  /// A synchronous peek at the in-memory cache, so a card already rendered this
  /// session shows instantly without a skeleton flash.
  static func cached(template: CoverLetterTemplate, accent: ResumeAccent) -> UIImage? {
    cache[Key(template: template, accent: accent)]
  }

  /// The full lookup: memory → disk → render. The render is serialised and
  /// happens only on the first ever request for a given template/accent.
  static func image(template: CoverLetterTemplate, accent: ResumeAccent) async -> UIImage? {
    let key = Key(template: template, accent: accent)
    if let cached = cache[key] { return cached }

    if let onDisk = await ThumbnailDiskCache.load(key.diskName) {
      cache[key] = onDisk
      return onDisk
    }

    await ThumbnailRenderGate.shared.acquire()
    defer { ThumbnailRenderGate.shared.release() }

    if Task.isCancelled { return nil }
    if let cached = cache[key] { return cached }

    guard let image = render(key: key) else { return nil }
    cache[key] = image
    ThumbnailDiskCache.save(image, name: key.diskName)
    return image
  }

  /// Renders the previews for `templates` ahead of being scrolled to, so the
  /// carousel is warm on the first launch too.
  static func prewarm(templates: [CoverLetterTemplate], accent: ResumeAccent) async {
    for template in templates {
      if Task.isCancelled { return }
      _ = await image(template: template, accent: accent)
    }
  }

  private static func render(key: Key) -> UIImage? {
    // The example letter, so every style previews with a full page of real
    // correspondence rather than whatever half-written draft is on the go.
    var document = CoverLetterDocument.example
    document.template = key.template
    document.accent = key.accent

    guard
      let data = try? CoverLetterPDFRenderer.render(document: document),
      let page = PDFDocument(data: data)?.page(at: 0)
    else { return nil }

    // A4 proportions, so the thumbnail is the page and not a crop of it.
    let size = CGSize(width: renderWidth, height: renderWidth * 842 / 595)
    return page.thumbnail(of: size, for: .mediaBox)
  }
}
