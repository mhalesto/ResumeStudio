import SwiftUI

struct JobSpecImportButton: View {
  @Binding var jobDescription: String
  @Binding var errorMessage: String?

  @State private var isChoosingFile = false
  @State private var isImporting = false
  @State private var importedSpec: ImportedJobSpec?
  @State private var importProgress = 0.0
  @State private var importTask: Task<Void, Never>?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button("Upload job spec", systemImage: "doc.badge.plus") {
        isChoosingFile = true
      }
      .disabled(isImporting)

      if isImporting {
        VStack(alignment: .leading, spacing: 6) {
          ProgressView(value: importProgress) {
            Text("Reading text on this iPhone… \(Int(importProgress * 100))%")
          }
          Button("Cancel import", systemImage: "xmark.circle") { importTask?.cancel() }
            .font(.caption.weight(.semibold))
        }
        .font(.caption)
        .accessibilityIdentifier("jobSpec.importProgress")
      }

      if let importedSpec {
        Label(
          "\(importedSpec.fileName) · \(importedSpec.wordCount) words",
          systemImage: "checkmark.circle.fill"
        )
        .font(.caption)
        .foregroundStyle(.green)

        if importedSpec.wasTruncated {
          Label(
            importedSpec.wasPageLimited
              ? "Only the first 20 pages were imported. Choose a shorter job pack if later pages matter."
              : "A very long document was shortened to fit the AI request.",
            systemImage: "scissors"
          )
            .font(.caption)
            .foregroundStyle(.orange)
        }
        if importedSpec.ocrPageCount > 0 {
          Label(
            "Text was recognized from \(importedSpec.ocrPageCount) scanned page\(importedSpec.ocrPageCount == 1 ? "" : "s").",
            systemImage: "viewfinder"
          )
          .font(.caption).foregroundStyle(Theme.mutedInk)
        }
      } else {
        Text("PDF, image, DOCX, RTF, or TXT · extracted on this iPhone")
          .font(.caption)
          .foregroundStyle(Theme.mutedInk)
      }
    }
    .fileImporter(
      isPresented: $isChoosingFile,
      allowedContentTypes: JobSpecImportService.supportedContentTypes,
      allowsMultipleSelection: false
    ) { result in
      importTask?.cancel()
      importTask = Task { @MainActor in
        isImporting = true
        importProgress = 0
        defer { isImporting = false }
        do {
          guard let url = try result.get().first else { return }
          let imported = try await JobSpecImportService.importDocument(from: url) { value in
            await MainActor.run { importProgress = value }
          }
          try Task.checkCancellation()
          jobDescription = imported.text
          importedSpec = imported
          errorMessage = nil
        } catch is CancellationError {
          errorMessage = nil
        } catch {
          importedSpec = nil
          errorMessage = error.localizedDescription
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Import job specification")
    .onDisappear { importTask?.cancel() }
  }
}
