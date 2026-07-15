import SwiftUI

struct JobSpecImportButton: View {
  @Binding var jobDescription: String
  @Binding var errorMessage: String?

  @State private var isChoosingFile = false
  @State private var importedSpec: ImportedJobSpec?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button("Upload job spec", systemImage: "doc.badge.plus") {
        isChoosingFile = true
      }

      if let importedSpec {
        Label(
          "\(importedSpec.fileName) · \(importedSpec.wordCount) words",
          systemImage: "checkmark.circle.fill"
        )
        .font(.caption)
        .foregroundStyle(.green)

        if importedSpec.wasTruncated {
          Label("A very long document was shortened to fit the AI request.", systemImage: "scissors")
            .font(.caption)
            .foregroundStyle(.orange)
        }
      } else {
        Text("PDF, DOCX, RTF, or TXT · extracted on this iPhone")
          .font(.caption)
          .foregroundStyle(Theme.mutedInk)
      }
    }
    .fileImporter(
      isPresented: $isChoosingFile,
      allowedContentTypes: JobSpecImportService.supportedContentTypes,
      allowsMultipleSelection: false
    ) { result in
      do {
        guard let url = try result.get().first else { return }
        let imported = try JobSpecImportService.importDocument(from: url)
        jobDescription = imported.text
        importedSpec = imported
        errorMessage = nil
      } catch {
        importedSpec = nil
        errorMessage = error.localizedDescription
      }
    }
  }
}
