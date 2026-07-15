import SwiftUI

struct CoverLetterPreviewView: View {
  let document: CoverLetterDocument

  @State private var pdfData: Data?
  @State private var renderError: String?
  @State private var isExporting = false
  @State private var shareItem: CoverLetterShareItem?

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
        ProgressView("Creating cover letter…")
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .principal) {
        VStack(spacing: 1) {
          Text("Cover Letter").font(.headline)
          Text(document.template.title)
            .font(.caption2)
            .foregroundStyle(Theme.mutedInk)
        }
      }
      if pdfData != nil {
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button {
            prepareShare()
          } label: {
            Image(systemName: "square.and.arrow.up")
          }
          .accessibilityLabel("Share cover letter PDF")

          Button("Save to Files", systemImage: "square.and.arrow.down") {
            isExporting = true
          }
        }
      }
    }
    .safeAreaInset(edge: .bottom) {
      if pdfData != nil {
        Button {
          prepareShare()
        } label: {
          Label("Share Cover Letter", systemImage: "square.and.arrow.up")
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(document.accent.color, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .background(.bar)
      }
    }
    .task(id: document) { renderPreview() }
    .fileExporter(
      isPresented: $isExporting,
      document: PDFFile(data: pdfData ?? Data()),
      contentType: .pdf,
      defaultFilename: document.suggestedFilename
    ) { _ in }
    .sheet(item: $shareItem) { item in
      ShareSheet(activityItems: [item.url])
    }
  }

  private func renderPreview() {
    do {
      pdfData = try CoverLetterPDFRenderer.render(document: document)
      renderError = nil
    } catch {
      pdfData = nil
      renderError = error.localizedDescription
    }
  }

  private func prepareShare() {
    guard let pdfData else { return }
    do {
      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(document.suggestedFilename)
        .appendingPathExtension("pdf")
      try pdfData.write(to: url, options: .atomic)
      shareItem = CoverLetterShareItem(url: url)
    } catch {
      renderError = error.localizedDescription
    }
  }
}

private struct CoverLetterShareItem: Identifiable {
  let url: URL
  var id: URL { url }
}
