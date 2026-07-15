import UIKit

enum ProfilePhoto {
  /// The draft is a JSON file rewritten on every edit, so a full-resolution photo
  /// would base64 into megabytes of write churn. This is plenty for a portrait
  /// that is only ever drawn a few centimetres across.
  static let maxDimension: CGFloat = 1024

  /// Downscales and re-encodes a picked image as JPEG.
  ///
  /// Note it keeps the photo's original framing rather than cropping it square:
  /// the crop lives in `PhotoCrop`, so the user can re-frame it later without
  /// having lost the parts that were cut off.
  static func prepare(_ data: Data) -> Data? {
    guard let image = UIImage(data: data) else { return nil }

    let longest = max(image.size.width, image.size.height)
    let scale = min(1, maxDimension / longest)
    let target = CGSize(
      width: (image.size.width * scale).rounded(),
      height: (image.size.height * scale).rounded()
    )

    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = true

    let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: target))
    }
    return resized.jpegData(compressionQuality: 0.82)
  }

  /// The square the crop selects, as its own image — what the circle actually shows.
  static func cropped(_ image: UIImage, to crop: PhotoCrop) -> UIImage? {
    // Work in pixels: a UIImage from JPEG data can carry a scale and an orientation,
    // and cropping the CGImage directly would ignore both.
    let pixels = CGSize(
      width: image.size.width * image.scale,
      height: image.size.height * image.scale
    )
    let rect = crop.rect(in: pixels)

    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = true

    return UIGraphicsImageRenderer(size: rect.size, format: format).image { _ in
      image.draw(
        in: CGRect(
          x: -rect.origin.x,
          y: -rect.origin.y,
          width: pixels.width,
          height: pixels.height
        )
      )
    }
  }
}
