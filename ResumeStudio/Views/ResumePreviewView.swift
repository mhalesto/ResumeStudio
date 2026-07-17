import PDFKit
import SwiftUI
import UIKit

struct ResumePreviewView: View {
  let document: ResumeDocument

  @State private var pdfData: Data?
  @State private var renderError: String?
  @State private var isExporting = false
  @State private var isExportingDOCX = false
  @State private var docxData: Data?
  @State private var showCopied = false
  @State private var shareItem: ShareItem?
  @State private var atsSafe = false
  @State private var showRecruiterScan = false
  @State private var showCreateLink = false

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
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button {
          showRecruiterScan = true
        } label: {
          Image(systemName: "eye")
        }
        .accessibilityLabel("Recruiter scan")
        .disabled(pdfData == nil)

        Button {
          prepareShare()
        } label: {
          Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel("Share PDF")
        .disabled(pdfData == nil)

        Menu {
          Button("Save PDF", systemImage: "doc.richtext") { isExporting = true }
          Button("Save editable DOCX", systemImage: "doc.text") { prepareDOCXExport() }
        } label: {
          Image(systemName: "square.and.arrow.down")
        }
        .accessibilityLabel("Download")
        .disabled(pdfData == nil)

        // The overflow of page actions — kept out of the preview so the résumé
        // itself gets the full screen.
        Menu {
          Toggle(isOn: $atsSafe.animation(.easeInOut(duration: 0.2))) {
            Label("ATS-safe layout", systemImage: "checkmark.shield")
          }
          Section {
            Button {
              showCreateLink = true
            } label: {
              Label("Send as trackable link", systemImage: "link.badge.plus")
            }
          }
          Section {
            Button {
              printResume()
            } label: {
              Label("Print", systemImage: "printer")
            }
            Button {
              copyResumeText()
            } label: {
              Label("Copy résumé text", systemImage: "doc.on.clipboard")
            }
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More actions")
      }
    }
    .overlay(alignment: .bottom) {
      if showCopied {
        Label("Résumé text copied", systemImage: "checkmark.circle.fill")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 18)
          .padding(.vertical, 11)
          .background(.black.opacity(0.82), in: Capsule())
          .padding(.bottom, 30)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
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
    .sheet(isPresented: $showRecruiterScan) {
      NavigationStack {
        RecruiterScanView(
          document: renderDocument, pdfData: pdfData, showsDone: true,
          fixRouting: .dismissToHome)
      }
    }
    .sheet(isPresented: $showCreateLink) {
      NavigationStack { CreateSmartLinkSheet() }
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

  /// Hands the rendered PDF to AirPrint.
  private func printResume() {
    guard let pdfData else { return }
    let info = UIPrintInfo(dictionary: nil)
    info.outputType = .general
    info.jobName = exportFilename
    let controller = UIPrintInteractionController.shared
    controller.printInfo = info
    controller.printingItem = pdfData
    controller.present(animated: true, completionHandler: nil)
  }

  /// Copies the résumé's text to the clipboard, for pasting straight into an
  /// online application's form fields.
  private func copyResumeText() {
    guard let pdfData, let pdf = PDFDocument(data: pdfData) else { return }
    let text = (0..<pdf.pageCount)
      .compactMap { pdf.page(at: $0)?.string }
      .joined(separator: "\n")
    guard !text.isEmpty else { return }
    UIPasteboard.general.string = text
    withAnimation { showCopied = true }
    Task {
      try? await Task.sleep(nanoseconds: 1_600_000_000)
      withAnimation { showCopied = false }
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
