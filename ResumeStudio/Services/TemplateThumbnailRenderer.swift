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
/// `ThumbnailDiskCache`). Everything renders at a single canonical resolution and
/// the cards scale it down, so the same template is never rendered twice just
/// because two screens show it at different sizes. Renders pass through
/// `ThumbnailRenderGate` so a screenful of cards can't stack their renders into
/// one main-thread freeze.
@MainActor
enum TemplateThumbnailRenderer {
  private static var cache: [Key: UIImage] = [:]

  /// One resolution for every card. The largest on-screen preview is the
  /// comparison view at 210pt (630px @3x); 640 keeps that crisp and lets every
  /// smaller card scale the same image down.
  static let renderWidth: CGFloat = 640

  private struct Key: Hashable {
    let template: ResumeTemplate
    let accent: ResumeAccent
    let photo: Data?
    let crop: PhotoCrop?

    /// A filename-safe, launch-stable identity for the disk cache.
    var diskName: String {
      var name = "resume-\(template.rawValue)-\(accent.rawValue)"
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
    template: ResumeTemplate, accent: ResumeAccent, photo: Data?, crop: PhotoCrop?
  ) -> UIImage? {
    cache[Key(template: template, accent: accent, photo: photo, crop: crop)]
  }

  /// The full lookup: memory → disk → render. The render is serialised and
  /// happens only on the first ever request for a given template/accent.
  static func image(
    template: ResumeTemplate,
    accent: ResumeAccent,
    photo: Data?,
    crop: PhotoCrop?
  ) async -> UIImage? {
    let key = Key(template: template, accent: accent, photo: photo, crop: crop)
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

    guard let image = render(key: key, width: renderWidth) else { return nil }
    cache[key] = image
    ThumbnailDiskCache.save(image, name: key.diskName)
    return image
  }

  /// Renders the previews for `templates` ahead of being scrolled to, so the
  /// carousel and gallery are warm on the first launch too. Cheap on later
  /// launches: each call is a memory or disk hit. Yields between templates and
  /// stops the moment its task is cancelled.
  static func prewarm(
    templates: [ResumeTemplate], accent: ResumeAccent, photo: Data?, crop: PhotoCrop?
  ) async {
    for template in templates {
      if Task.isCancelled { return }
      _ = await image(template: template, accent: accent, photo: photo, crop: crop)
    }
  }

  /// A one-off, higher-resolution render for sharing a preview image. Not cached:
  /// it is user-initiated and infrequent, and does not belong beside the small
  /// card thumbnails.
  static func shareImage(
    template: ResumeTemplate, accent: ResumeAccent, photo: Data?, crop: PhotoCrop?
  ) async -> UIImage? {
    if Task.isCancelled { return nil }
    let key = Key(template: template, accent: accent, photo: photo, crop: crop)
    return render(key: key, width: 1000)
  }

  private static func render(key: Key, width: CGFloat) -> UIImage? {
    let document = sample(
      template: key.template, accent: key.accent, photo: key.photo, crop: key.crop)
    guard
      let data = try? ResumePDFRenderer.render(document: document),
      let page = PDFDocument(data: data)?.page(at: 0)
    else { return nil }

    // A4 proportions, so the thumbnail is the page and not a crop of it.
    let size = CGSize(width: width, height: width * 842 / 595)
    return page.thumbnail(of: size, for: .mediaBox)
  }
}
