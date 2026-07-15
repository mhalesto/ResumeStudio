import CoreGraphics
import Foundation

/// Which part of the portrait is shown in the circle.
///
/// Stored alongside the *uncropped* photo rather than baked into the pixels, so
/// the framing stays adjustable: you can reopen the cropper and pull back out.
struct PhotoCrop: Codable, Equatable, Hashable {
  /// Centre of the visible circle, normalised to the source image (0...1).
  var centerX: Double
  var centerY: Double

  /// 1 means the largest square that fits the image; higher values zoom in.
  var zoom: Double

  /// Centred, fully zoomed out — the same square an uncropped photo used to get.
  static let centred = PhotoCrop(centerX: 0.5, centerY: 0.5, zoom: 1)

  /// The square of `size` this crop selects, in pixels, clamped so it can never
  /// run off the edge of the image (which would show blank corners in the PDF).
  func rect(in size: CGSize) -> CGRect {
    let shortest = min(size.width, size.height)
    let side = max(1, shortest / max(1, zoom))
    let half = side / 2

    let x = (centerX * size.width).clamped(to: half...(size.width - half))
    let y = (centerY * size.height).clamped(to: half...(size.height - half))

    return CGRect(x: x - half, y: y - half, width: side, height: side)
  }
}

extension Comparable {
  func clamped(to limits: ClosedRange<Self>) -> Self {
    // A degenerate range means the image is smaller than the crop; take the bound.
    guard limits.lowerBound <= limits.upperBound else { return limits.lowerBound }
    return min(max(self, limits.lowerBound), limits.upperBound)
  }
}
