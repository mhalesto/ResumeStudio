import SwiftUI

struct ResumePreviewView: View {
  let document: ResumeDocument

  @State private var pdfData: Data?
  @State private var renderError: String?
  @State private var isExporting = false
  @State private var isExportingDOCX = false
  @State private var docxData: Data?
  @State private var shareItem: ShareItem?
  @State private var atsSafe = false

  /// What actually gets rendered and exported: the chosen design, or an
  /// ATS-safe transform of it when the toggle is on.
  private var renderDocument: ResumeDocument {
    atsSafe ? Self.atsSafeVariant(of: document) : document
  }

  private var exportFilename: String {
    atsSafe ? "\(document.suggestedFilename)-ATS" : document.suggestedFilename
  }

  /// A guaranteed applicant-tracking-friendly version of the résumé: a single
  /// column with standard section headings and no photo, which the parsers most
  /// reliably read in the right order. Only the layout changes — every word of
  /// the résumé is the user's own.
  private static func atsSafeVariant(of document: ResumeDocument) -> ResumeDocument {
    var doc = document
    doc.template = .classic
    doc.photo = nil
    doc.photoCrop = nil
    return doc
  }

  var body: some View {
    Group {
      if let pdfData {
        PDFKitView(data: pdfData)
          .background(Theme.muted)
      } else if let renderError {
        ContentUnavailableView(
          "Unable to Create Preview",
          systemImage: "exclamationmark.triangle",
          description: Text(renderError)
        )
      } else {
        ProgressView("Creating PDF preview...")
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      // Two lines: what you're looking at, and in which style. As a plain
      // navigation title this ran past the edge and truncated.
      ToolbarItem(placement: .principal) {
        VStack(spacing: 1) {
          Text("Preview")
            .font(.headline)
          Text(atsSafe
            ? "ATS-safe layout"
            : "\(document.template.title) · \(document.accent.title)")
            .font(.caption2)
            .foregroundStyle(Theme.mutedInk)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
      }
      if pdfData != nil {
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button {
            prepareShare()
          } label: {
            Image(systemName: "square.and.arrow.up")
          }
          .accessibilityLabel("Share PDF")

          Menu {
            Button("Save PDF", systemImage: "doc.richtext") { isExporting = true }
            Button("Save editable DOCX", systemImage: "doc.text") { prepareDOCXExport() }
          } label: {
            Label("Export", systemImage: "square.and.arrow.down")
          }
        }
      }
    }
    .safeAreaInset(edge: .bottom) {
      // The whole journey ends here; make the last step the loudest thing on screen.
      VStack(spacing: 12) {
        Toggle(isOn: $atsSafe.animation(.easeInOut(duration: 0.2))) {
          VStack(alignment: .leading, spacing: 2) {
            Label("ATS-safe layout", systemImage: "checkmark.shield.fill")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(Theme.ink)
            Text("Single column, no photo — parses cleanly in applicant tracking systems.")
              .font(.caption)
              .foregroundStyle(Theme.mutedInk)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .tint(document.accent.color)

        if pdfData != nil {
          Button {
            prepareShare()
          } label: {
            Label("Share PDF", systemImage: "square.and.arrow.up")
              .font(.headline)
              .foregroundStyle(.white)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 16)
              .background(document.accent.color, in: Capsule())
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, 12)
      .padding(.bottom, 8)
      .background(.bar)
    }
    .task(id: renderDocument) {
      await renderPreview()
    }
    .fileExporter(
      isPresented: $isExporting,
      document: PDFFile(data: pdfData ?? Data()),
      contentType: .pdf,
      defaultFilename: exportFilename
    ) { _ in }
    .fileExporter(
      isPresented: $isExportingDOCX,
      document: DataFile(data: docxData ?? Data()),
      contentType: .wordProcessingDocument,
      defaultFilename: exportFilename
    ) { _ in }
    .sheet(item: $shareItem) { item in
      ShareSheet(activityItems: [item.url])
    }
  }

  @MainActor
  private func renderPreview() async {
    pdfData = nil
    renderError = nil
    do {
      // Give SwiftUI one frame to present the progress state before UIKit begins
      // its local PDF context. The renderer is main-actor isolated by UIKit, but
      // the pagination guard below keeps this work finite.
      await Task.yield()
      let data = try ResumePDFRenderer.render(document: renderDocument)
      guard !Task.isCancelled else { return }
      pdfData = data
      renderError = nil
    } catch is CancellationError {
      return
    } catch {
      pdfData = nil
      renderError = error.localizedDescription
    }
  }

  private func prepareShare() {
    guard let pdfData else { return }
    do {
      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(exportFilename)
        .appendingPathExtension("pdf")
      try pdfData.write(to: url, options: .atomic)
      shareItem = ShareItem(url: url)
    } catch {
      renderError = error.localizedDescription
    }
  }

  private func prepareDOCXExport() {
    do {
      docxData = try ResumeDOCXRenderer.render(document: renderDocument)
      isExportingDOCX = true
    } catch {
      renderError = error.localizedDescription
    }
  }
}

private struct ShareItem: Identifiable {
  let url: URL
  var id: URL { url }
}

#Preview {
  NavigationStack {
    ResumePreviewView(document: .example)
  }
}
