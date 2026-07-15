import PDFKit
import UIKit

/// Renders template previews by actually exporting the résumé and taking page 1.
///
/// The cards used to show abstract grey and orange bars, which told you nothing
/// about what a template does with real content. These are the genuine article:
/// the same renderer that produces the PDF you export, so what you pick is what
/// you get.
///
/// Rendering a page is expensive, so results are cached twice over: in memory
/// for the session, and on disk so a template is only ever rendered once (see
/// `ThumbnailDiskCache`). Renders pass through `ThumbnailRenderGate` so a
/// screenful of cards can't stack their renders into one main-thread freeze.
@MainActor
enum TemplateThumbnailRenderer {
  private static var cache: [Key: UIImage] = [:]

  private struct Key: Hashable {
    let template: ResumeTemplate
    let accent: ResumeAccent
    let photo: Data?
    let crop: PhotoCrop?
    let width: Int

    /// A filename-safe, launch-stable identity for the disk cache.
    var diskName: String {
      var name = "resume-\(template.rawValue)-\(accent.rawValue)-\(width)"
      if let photo { name += "-p\(ThumbnailDiskCache.digest(photo))" }
      if let crop {
        name += "-c\(Int(crop.centerX * 1000))x\(Int(crop.centerY * 1000))z\(Int(crop.zoom * 1000))"
      }
      return name
    }
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

  /// A synchronous peek at the in-memory cache, so a card that has already been
  /// rendered this session shows instantly without a skeleton flash.
  static func cached(
    template: ResumeTemplate, accent: ResumeAccent, photo: Data?, crop: PhotoCrop?, width: CGFloat
  ) -> UIImage? {
    cache[Key(template: template, accent: accent, photo: photo, crop: crop, width: Int(width))]
  }

  /// The full lookup: memory → disk → render. The render is serialised and
  /// happens only on the first ever request for a given template/accent.
  static func image(
    template: ResumeTemplate,
    accent: ResumeAccent,
    photo: Data?,
    crop: PhotoCrop?,
    width: CGFloat
  ) async -> UIImage? {
    let key = Key(template: template, accent: accent, photo: photo, crop: crop, width: Int(width))
    if let cached = cache[key] { return cached }

    if let onDisk = await ThumbnailDiskCache.load(key.diskName) {
      cache[key] = onDisk
      return onDisk
    }

    await ThumbnailRenderGate.shared.acquire()
    defer { ThumbnailRenderGate.shared.release() }

    // The card may have scrolled away while we waited our turn; don't spend a
    // render on something no longer on screen.
    if Task.isCancelled { return nil }
    // Another card with the same key may have rendered while we waited.
    if let cached = cache[key] { return cached }

    guard let image = render(key: key) else { return nil }
    cache[key] = image
    ThumbnailDiskCache.save(image, name: key.diskName)
    return image
  }

  private static func render(key: Key) -> UIImage? {
    let document = sample(
      template: key.template, accent: key.accent, photo: key.photo, crop: key.crop)
    guard
      let data = try? ResumePDFRenderer.render(document: document),
      let page = PDFDocument(data: data)?.page(at: 0)
    else { return nil }

    // A4 proportions, so the thumbnail is the page and not a crop of it.
    let size = CGSize(width: CGFloat(key.width), height: CGFloat(key.width) * 842 / 595)
    return page.thumbnail(of: size, for: .mediaBox)
  }
}
