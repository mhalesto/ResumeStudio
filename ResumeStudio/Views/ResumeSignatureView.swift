import PDFKit
import PencilKit
import SwiftUI

/// Draws and positions the signature that is composited into the exported PDF.
/// The editor keeps the PencilKit vectors in the résumé, never in shared prefs or
/// a cloud signing service.
struct ResumeSignatureView: View {
  @Binding private var signature: ResumeSignature?

  let pdfData: Data?
  let resumePageCount: Int
  let accent: Color

  @Environment(\.dismiss) private var dismiss
  @State private var drawing: PKDrawing
  @State private var selectedPage: Int
  @State private var placement: ResumeSignaturePlacement
  @State private var widthPoints: Double
  @State private var pagePreview: UIImage?
  @State private var confirmsRemoval = false

  init(
    signature: Binding<ResumeSignature?>,
    pdfData: Data?,
    resumePageCount: Int,
    accent: Color
  ) {
    _signature = signature
    self.pdfData = pdfData
    self.resumePageCount = max(1, resumePageCount)
    self.accent = accent

    let existing = signature.wrappedValue
    _drawing = State(initialValue: existing?.drawing ?? PKDrawing())
    _selectedPage = State(
      initialValue: min(max(0, existing?.pageIndex ?? 0), max(0, resumePageCount - 1)))
    _placement = State(initialValue: existing?.placement ?? .lowerTrailing)
    _widthPoints = State(initialValue: existing?.widthPoints ?? 128)
  }

  private var hasDrawing: Bool { !drawing.strokes.isEmpty }

  var body: some View {
    Form {
      Section {
        ZStack(alignment: .topTrailing) {
          SignatureCanvas(drawing: $drawing)
            .frame(height: 170)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
              RoundedRectangle(cornerRadius: 14)
                .strokeBorder(accent.opacity(0.24), lineWidth: 1)
            }

          if hasDrawing {
            Button("Clear", systemImage: "eraser") { drawing = PKDrawing() }
              .labelStyle(.iconOnly)
              .buttonStyle(.bordered)
              .tint(Theme.mutedInk)
              .padding(10)
          }
        }
        .accessibilityElement(children: .contain)
      } header: {
        Text("Draw signature")
      } footer: {
        Text("Use a finger or Apple Pencil. Your signature stays inside this résumé on this device and in your own synced résumé library.")
      }

      Section("Placement") {
        Stepper(
          "Page \(selectedPage + 1) of \(resumePageCount)",
          value: $selectedPage,
          in: 0...max(0, resumePageCount - 1)
        )

        Picker("Position", selection: $placement) {
          ForEach(ResumeSignaturePlacement.allCases) { option in
            Label(option.title, systemImage: option.systemImage).tag(option)
          }
        }
        .pickerStyle(.segmented)

        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Size")
            Spacer()
            Text("\(Int(widthPoints)) pt").foregroundStyle(Theme.mutedInk)
          }
          Slider(value: $widthPoints, in: 88...176, step: 4).tint(accent)
        }
      }

      Section {
        pagePlacementPreview
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
      } header: {
        Text("Page preview")
      } footer: {
        Text("The signature is placed just above the footer and does not add a page or change searchable résumé text.")
      }

      if signature != nil {
        Section {
          Button("Remove signature", systemImage: "trash", role: .destructive) {
            confirmsRemoval = true
          }
        }
      }
    }
    .supportsKeyboardDismissal()
    .scrollContentBackground(.hidden)
    .background(Theme.paper)
    .navigationTitle(
      signature == nil
        ? String(localized: "Sign document")
        : String(localized: "Edit signature")
    )
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { dismiss() }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") { save() }
          .fontWeight(.semibold)
          .disabled(!hasDrawing)
      }
    }
    .task(id: selectedPage) { refreshPagePreview() }
    .confirmationDialog(
      "Remove this signature?",
      isPresented: $confirmsRemoval,
      titleVisibility: .visible
    ) {
      Button("Remove signature", role: .destructive) {
        signature = nil
        dismiss()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("The résumé content stays unchanged; only the hand-drawn mark is removed.")
    }
  }

  private var pagePlacementPreview: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color.white)
        .shadow(color: .black.opacity(0.08), radius: 5, y: 2)

      if let pagePreview {
        Image(uiImage: pagePreview)
          .resizable()
          .scaledToFit()
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      } else {
        ProgressView()
      }

      GeometryReader { geometry in
        if let image = previewSignatureImage {
          let previewWidth = geometry.size.width * CGFloat(widthPoints / 595)
          Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: previewWidth, height: max(12, previewWidth * 0.38))
            .padding(3)
            .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 2))
            .position(
              x: signaturePreviewX(in: geometry.size),
              y: geometry.size.height * 0.925
            )
        }
      }
    }
    .frame(width: 190, height: 269)
    .accessibilityLabel(
      String(localized: "Page \(selectedPage + 1) signature placement preview")
    )
  }

  private var previewSignatureImage: UIImage? {
    guard hasDrawing else { return nil }
    return ResumeSignature(
      drawingData: drawing.dataRepresentation(),
      pageIndex: selectedPage,
      placement: placement,
      widthPoints: widthPoints
    ).image(scale: 2)
  }

  private func signaturePreviewX(in size: CGSize) -> CGFloat {
    let halfWidth = size.width * CGFloat(widthPoints / 595) / 2
    let inset = size.width * 0.06 + halfWidth
    return switch placement {
    case .lowerLeading: inset
    case .lowerCenter: size.width / 2
    case .lowerTrailing: size.width - inset
    }
  }

  @MainActor
  private func refreshPagePreview() {
    guard let pdfData, let page = PDFDocument(data: pdfData)?.page(at: selectedPage) else {
      pagePreview = nil
      return
    }
    pagePreview = page.thumbnail(of: CGSize(width: 380, height: 538), for: .mediaBox)
  }

  private func save() {
    guard hasDrawing else { return }
    signature = ResumeSignature(
      drawingData: drawing.dataRepresentation(),
      pageIndex: selectedPage,
      placement: placement,
      widthPoints: widthPoints
    )
    dismiss()
  }
}

private struct SignatureCanvas: UIViewRepresentable {
  @Binding var drawing: PKDrawing

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeUIView(context: Context) -> PKCanvasView {
    let canvas = PKCanvasView(frame: .zero)
    canvas.delegate = context.coordinator
    canvas.backgroundColor = .clear
    canvas.isOpaque = false
    canvas.isScrollEnabled = false
    canvas.drawingPolicy = .anyInput
    canvas.tool = PKInkingTool(.pen, color: UIColor(red: 0.08, green: 0.16, blue: 0.35, alpha: 1), width: 3)
    canvas.drawing = drawing
    return canvas
  }

  func updateUIView(_ canvas: PKCanvasView, context: Context) {
    context.coordinator.parent = self
    guard canvas.drawing.dataRepresentation() != drawing.dataRepresentation() else { return }
    canvas.drawing = drawing
  }

  final class Coordinator: NSObject, PKCanvasViewDelegate {
    var parent: SignatureCanvas

    init(_ parent: SignatureCanvas) { self.parent = parent }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
      parent.drawing = canvasView.drawing
    }
  }
}

#Preview {
  NavigationStack {
    ResumeSignatureView(
      signature: .constant(nil),
      pdfData: nil,
      resumePageCount: 2,
      accent: .purple
    )
  }
}
