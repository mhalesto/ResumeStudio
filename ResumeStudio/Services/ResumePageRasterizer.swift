import Foundation
import PDFKit
import UIKit

/// Rasterises each résumé PDF page to a PNG for the hosted trackable-link and
/// Review Room viewers, which show the images at full column width so nothing
/// is clipped on a phone the way an inline PDF is. Rendered at a retina-friendly
/// width on a white backing so a transparent PDF never shows the page colour
/// through it.
enum ResumePageRasterizer {
  static func images(fromPDF data: Data, targetWidth: CGFloat = 1240) -> [Data] {
    guard let document = PDFDocument(data: data) else { return [] }
    var images: [Data] = []
    for index in 0..<document.pageCount {
      guard let page = document.page(at: index) else { continue }
      let bounds = page.bounds(for: .mediaBox)
      guard bounds.width > 0, bounds.height > 0 else { continue }
      let scale = targetWidth / bounds.width
      let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
      let format = UIGraphicsImageRendererFormat.default()
      format.scale = 1
      format.opaque = true
      let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
        let cgContext = context.cgContext
        UIColor.white.setFill()
        cgContext.fill(CGRect(origin: .zero, size: size))
        cgContext.translateBy(x: 0, y: size.height)
        cgContext.scaleBy(x: scale, y: -scale)
        page.draw(with: .mediaBox, to: cgContext)
      }
      if let png = image.pngData() { images.append(png) }
    }
    return images
  }
}
