import CryptoKit
import UIKit

/// A launch-stable disk cache for the template/cover-letter thumbnails.
///
/// The renderers already keep an in-memory cache, but that dies with the
/// process, so every cold launch used to re-render a screenful of multi-page
/// PDFs on the main thread — the home screen's opening freeze. Persisting the
/// finished PNGs means a template is only ever rendered once; every launch after
/// the first loads a small image off the main thread instead.
enum ThumbnailDiskCache {
  /// Keyed by build number, so shipping a tweaked template regenerates its
  /// thumbnail rather than serving a stale cached PNG from the previous release.
  private static let directory: URL? = {
    let fileManager = FileManager.default
    guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
    else { return nil }

    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    let root = caches.appendingPathComponent("TemplateThumbnails", isDirectory: true)
    let directory = root.appendingPathComponent(build, isDirectory: true)
    try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

    // Best-effort sweep of thumbnails left by earlier builds so the cache does
    // not grow without bound across updates.
    if let leftovers = try? fileManager.contentsOfDirectory(
      at: root, includingPropertiesForKeys: nil) {
      for url in leftovers where url.lastPathComponent != build {
        try? fileManager.removeItem(at: url)
      }
    }
    prune(directory)
    return directory
  }()

  /// The most thumbnails to keep on disk within a build. Every template × accent ×
  /// photo-crop is its own file, so without a ceiling a user who tries many looks
  /// could accumulate thousands. Caches is purgeable, but a bound keeps it tidy.
  private static let maxCachedFiles = 400

  /// Trims the current build's directory to `maxCachedFiles`, deleting the
  /// least-recently-modified files first. Runs once per launch, before the
  /// session writes any new thumbnails.
  private static func prune(_ directory: URL) {
    let fileManager = FileManager.default
    guard
      let files = try? fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: .skipsHiddenFiles),
      files.count > maxCachedFiles
    else { return }

    let sorted = files.sorted { lhs, rhs in
      let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?
        .contentModificationDate ?? .distantPast
      let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?
        .contentModificationDate ?? .distantPast
      return l < r
    }
    for url in sorted.prefix(files.count - maxCachedFiles) {
      try? fileManager.removeItem(at: url)
    }
  }

  private static func fileURL(for name: String) -> URL? {
    directory?.appendingPathComponent(name).appendingPathExtension("png")
  }

  /// Loads and decodes a cached PNG off the main thread.
  static func load(_ name: String) async -> UIImage? {
    guard let url = fileURL(for: name) else { return nil }
    return await Task.detached(priority: .utility) {
      guard let data = try? Data(contentsOf: url) else { return nil }
      return UIImage(data: data)
    }.value
  }

  /// Writes a PNG off the main thread. Fire-and-forget: the in-memory cache
  /// already holds the image the caller just handed back to the view.
  static func save(_ image: UIImage, name: String) {
    guard let url = fileURL(for: name) else { return }
    Task.detached(priority: .utility) {
      guard let data = image.pngData() else { return }
      try? data.write(to: url, options: .atomic)
    }
  }

  /// A filename-safe, launch-stable digest of arbitrary photo bytes. Swift's
  /// `hashValue` is seeded per process, so it can't name a file that has to
  /// survive relaunch; a content hash can.
  static func digest(_ data: Data) -> String {
    let hash = SHA256.hash(data: data)
    return hash.prefix(8).map { String(format: "%02x", $0) }.joined()
  }
}

/// Serialises the main-actor thumbnail renders and puts one run-loop breath
/// between them.
///
/// A screenful of cards would otherwise fire their renders back-to-back in a
/// single synchronous burst — a full multi-page PDF each — and freeze the frame.
/// Passing every render through this gate spreads them across turns, so the list
/// keeps scrolling and the cards fill in progressively.
@MainActor
final class ThumbnailRenderGate {
  static let shared = ThumbnailRenderGate()

  private var isRendering = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  /// Suspends until no other render is in flight, then leaves a short run-loop
  /// window so taps, scrolling and selection animations paint before the next
  /// synchronous PDF render. Pair every `acquire()` with a `release()`.
  func acquire() async {
    while isRendering {
      await withCheckedContinuation { waiters.append($0) }
    }
    isRendering = true
    try? await Task.sleep(for: .milliseconds(80))
  }

  func release() {
    isRendering = false
    let resumed = waiters
    waiters.removeAll()
    for waiter in resumed { waiter.resume() }
  }
}
