import SwiftUI

/// Frames the portrait: drag to move, pinch to zoom.
///
/// The parts that will be cut away stay visible but dimmed, so you're choosing
/// what to show rather than guessing what you're losing. What's inside the circle
/// here is exactly what the PDF draws.
struct PhotoCropView: View {
  let image: UIImage
  let accent: Color
  /// Called with the framing to keep; not applied unless you confirm.
  let onSave: (PhotoCrop) -> Void

  @Environment(\.dismiss) private var dismiss

  @State private var zoom: CGFloat
  @State private var offset: CGSize
  @State private var liveZoom: CGFloat = 1
  @State private var liveOffset: CGSize = .zero

  private static let diameter: CGFloat = 280
  private static let maxZoom: CGFloat = 5
  private var diameter: CGFloat { Self.diameter }

  init(image: UIImage, crop: PhotoCrop?, accent: Color, onSave: @escaping (PhotoCrop) -> Void) {
    self.image = image
    self.accent = accent
    self.onSave = onSave

    let crop = crop ?? .centred
    let startZoom = CGFloat(crop.zoom).clamped(to: 1...Self.maxZoom)
    _zoom = State(initialValue: startZoom)

    // Reconstruct the pan from the stored centre, so reopening picks up where
    // the user left off rather than snapping back to the middle.
    let size = image.size
    let scale = (Self.diameter / min(size.width, size.height)) * startZoom
    _offset = State(
      initialValue: CGSize(
        width: (size.width / 2 - CGFloat(crop.centerX) * size.width) * scale,
        height: (size.height / 2 - CGFloat(crop.centerY) * size.height) * scale
      )
    )
  }

  // MARK: - Geometry

  private var currentZoom: CGFloat {
    (zoom * liveZoom).clamped(to: 1...Self.maxZoom)
  }

  /// Points-per-image-point. At zoom 1 the shorter side exactly fills the circle.
  private var displayScale: CGFloat {
    (diameter / min(image.size.width, image.size.height)) * currentZoom
  }

  private var displaySize: CGSize {
    CGSize(width: image.size.width * displayScale, height: image.size.height * displayScale)
  }

  /// Never let the image pull away from the circle's edge and expose a blank corner.
  private func clamp(_ candidate: CGSize) -> CGSize {
    let limitX = max(0, (displaySize.width - diameter) / 2)
    let limitY = max(0, (displaySize.height - diameter) / 2)
    return CGSize(
      width: candidate.width.clamped(to: -limitX...limitX),
      height: candidate.height.clamped(to: -limitY...limitY)
    )
  }

  private var currentOffset: CGSize {
    clamp(CGSize(width: offset.width + liveOffset.width, height: offset.height + liveOffset.height))
  }

  private var crop: PhotoCrop {
    let panned = currentOffset
    let centre = CGPoint(
      x: image.size.width / 2 - panned.width / displayScale,
      y: image.size.height / 2 - panned.height / displayScale
    )
    return PhotoCrop(
      centerX: Double(centre.x / image.size.width),
      centerY: Double(centre.y / image.size.height),
      zoom: Double(currentZoom)
    )
  }

  // MARK: - Body

  var body: some View {
    NavigationStack {
      ZStack {
        Color.black.ignoresSafeArea()

        // The image is deliberately not clipped: what gets cut away stays on
        // screen, just dimmed, so you can see what you're leaving out.
        Image(uiImage: image)
          .resizable()
          .frame(width: displaySize.width, height: displaySize.height)
          .offset(currentOffset)

        // Full-screen dim with the circle punched out. This has to live at the
        // top of the stack, not as an overlay on the circle's frame, or it only
        // darkens a square the size of the window.
        dimming

        Circle()
          .strokeBorder(accent, lineWidth: 3)
          .frame(width: diameter, height: diameter)
          .allowsHitTesting(false)

        VStack {
          Spacer()
          Text("Drag to move · Pinch to zoom")
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.6))
            .padding(.bottom, 28)
        }
        .allowsHitTesting(false)
      }
      .contentShape(Rectangle())
      .gesture(
        SimultaneousGesture(
          DragGesture()
            .onChanged { liveOffset = $0.translation }
            .onEnded { _ in
              offset = currentOffset
              liveOffset = .zero
            },
          MagnifyGesture()
            .onChanged { liveZoom = $0.magnification }
            .onEnded { _ in
              zoom = currentZoom
              liveZoom = 1
              offset = clamp(offset)
            }
        )
      )
      .navigationTitle("Frame your photo")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.black, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      .toolbarColorScheme(.dark, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") {
            onSave(crop)
            dismiss()
          }
          .font(.headline)
          .tint(accent)
        }
        ToolbarItem(placement: .bottomBar) {
          Button("Reset") {
            withAnimation(.snappy) {
              zoom = 1
              offset = .zero
              liveZoom = 1
              liveOffset = .zero
            }
          }
          .tint(.white)
        }
      }
    }
  }

  /// Everything outside the circle, darkened.
  private var dimming: some View {
    Rectangle()
      .fill(.black.opacity(0.62))
      .ignoresSafeArea()
      .mask {
        Rectangle()
          .ignoresSafeArea()
          .overlay {
            Circle()
              .frame(width: diameter, height: diameter)
              .blendMode(.destinationOut)
          }
          .compositingGroup()
      }
      .allowsHitTesting(false)
  }
}
