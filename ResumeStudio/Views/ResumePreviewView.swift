import SwiftUI

struct ResumePreviewView: View {
    let document: ResumeDocument

    @State private var pdfData: Data?
    @State private var renderError: String?
    @State private var isExporting = false
    @State private var shareItem: ShareItem?

    var body: some View {
        Group {
            if let pdfData {
                PDFKitView(data: pdfData)
                    .background(Color(uiColor: .secondarySystemBackground))
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
        .navigationTitle("PDF Preview")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if pdfData != nil {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Export", systemImage: "square.and.arrow.down") {
                        isExporting = true
                    }
                    Button("Share", systemImage: "square.and.arrow.up") {
                        prepareShare()
                    }
                }
            }
        }
        .task(id: document) {
            renderPreview()
        }
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
            pdfData = try ResumePDFRenderer.render(document: document)
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
            shareItem = ShareItem(url: url)
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
        ResumePreviewView(document: .mandisaSample)
    }
}
