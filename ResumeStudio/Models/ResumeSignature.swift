import PencilKit
import UIKit

/// A hand-drawn signature placed over one résumé page at export time.
///
/// PencilKit's vector drawing is stored rather than a screenshot, so the mark
/// remains crisp in the PDF and can be reopened for another stroke later. The
/// page is zero-based internally; the editor presents it as the familiar 1, 2…
struct ResumeSignature: Codable, Equatable, Hashable {
  var drawingData: Data
  var pageIndex: Int
  var placement: ResumeSignaturePlacement
  var widthPoints: Double

  init(
    drawingData: Data,
    pageIndex: Int = 0,
    placement: ResumeSignaturePlacement = .lowerTrailing,
    widthPoints: Double = 128
  ) {
    self.drawingData = drawingData
    self.pageIndex = max(0, pageIndex)
    self.placement = placement
    self.widthPoints = min(max(widthPoints, 88), 176)
  }

  private enum CodingKeys: String, CodingKey {
    case drawingData, pageIndex, placement, widthPoints
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    drawingData = try container.decode(Data.self, forKey: .drawingData)
    pageIndex = max(0, try container.decodeIfPresent(Int.self, forKey: .pageIndex) ?? 0)
    placement =
      try container.decodeIfPresent(ResumeSignaturePlacement.self, forKey: .placement)
      ?? .lowerTrailing
    widthPoints = min(
      max(try container.decodeIfPresent(Double.self, forKey: .widthPoints) ?? 128, 88),
      176
    )
  }

  var drawing: PKDrawing {
    (try? PKDrawing(data: drawingData)) ?? PKDrawing()
  }

  /// A tightly cropped transparent rendering for the PDF and placement preview.
  @MainActor
  func image(scale: CGFloat = 3) -> UIImage? {
    let drawing = drawing
    guard !drawing.strokes.isEmpty else { return nil }
    let bounds = drawing.bounds.insetBy(dx: -8, dy: -8)
    guard bounds.width > 0, bounds.height > 0 else { return nil }
    return drawing.image(from: bounds, scale: scale)
  }
}

enum ResumeSignaturePlacement: String, Codable, CaseIterable, Identifiable {
  case lowerLeading
  case lowerCenter
  case lowerTrailing

  var id: Self { self }

  var title: String {
    switch self {
    case .lowerLeading: String(localized: "Left")
    case .lowerCenter: String(localized: "Centre")
    case .lowerTrailing: String(localized: "Right")
    }
  }

  var systemImage: String {
    switch self {
    case .lowerLeading: "align.horizontal.left"
    case .lowerCenter: "align.horizontal.center"
    case .lowerTrailing: "align.horizontal.right"
    }
  }
}
