import PDFKit
import SwiftUI

/// Picks each section's look independently of the template it came with.
///
/// A template is a letterhead plus a set of decisions about the sections below
/// it. This screen unpicks the second half: keep the masthead you chose, take
/// the timeline from Chronicle, the pills from Atlas, the margin dates from
/// Modena. Every picker leads with "Template default", so nothing is customised
/// until it is asked for, and one button puts all of it back.
struct SectionStyleEditorView: View {
  @EnvironmentObject private var store: ResumeStore

  @State private var preview: UIImage?
  @State private var isRendering = false

  private var styles: ResumeSectionStyleOverrides { store.document.layout.sectionStyles }
  private var accent: Color { store.document.accent.color }

  var body: some View {
    Form {
      previewSection

      Section {
        picker("Page layout", SectionStyleCatalog.body, \.body)
        picker("Section headings", SectionStyleCatalog.headingNumbering, \.numberedSections)
        picker("Heading position", SectionStyleCatalog.headingPlacement, \.hangingHeadings)
        picker("Entry cards", SectionStyleCatalog.chrome, \.sectionChrome)
      } header: {
        Text("The page")
      } footer: {
        Text(
          "Page layout moves the scannable facts — contact, skills, education — into a column of their own, or flattens a two-column template back to one."
        )
      }

      Section("Sections") {
        picker("Experience", SectionStyleCatalog.experience, \.experience)
        picker("Skills", SectionStyleCatalog.competencies, \.competencies)
        picker("Education", SectionStyleCatalog.education, \.education)
        picker("References", SectionStyleCatalog.references, \.references)
        picker("Extra sections", SectionStyleCatalog.additional, \.additional)
        picker("Contact details", SectionStyleCatalog.contact, \.contact)
      }

      Section {
        NavigationLink {
          ResumePreviewView(document: store.document)
        } label: {
          Label("Preview full résumé", systemImage: "doc.text.magnifyingglass")
        }
        Button("Reset to template defaults", systemImage: "arrow.counterclockwise", role: .destructive) {
          store.document.layout.sectionStyles = .none
        }
        .disabled(styles.isEmpty)
      } footer: {
        Text(
          "Extra sections are the ones you add yourself — projects, certifications, languages, websites. They all share one style."
        )
      }
    }
    .scrollContentBackground(.hidden)
    .background(Theme.paper)
    .navigationTitle("Section styles")
    .navigationBarTitleDisplayMode(.inline)
    .task(id: store.document) { await renderPreview() }
  }

  // MARK: - Preview

  private var previewSection: some View {
    Section {
      HStack(alignment: .top, spacing: 14) {
        ZStack {
          Theme.muted
          if let preview {
            Image(uiImage: preview)
              .resizable()
              .scaledToFit()
          }
          if isRendering {
            ProgressView()
          }
        }
        .frame(width: 108, height: 153)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(Theme.muted, lineWidth: 1)
        }

        VStack(alignment: .leading, spacing: 5) {
          Text(store.document.template.title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.ink)
          Text(summary)
            .font(.caption)
            .foregroundStyle(Theme.mutedInk)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
      }
      .padding(.vertical, 4)
    }
  }

  private var summary: String {
    let changed = styles.count
    guard changed > 0 else {
      return String(localized: "Every section is drawn the way this template draws it.")
    }
    return changed == 1
      ? String(localized: "1 section changed from the template default.")
      : String(localized: "\(changed) sections changed from the template default.")
  }

  @MainActor
  private func renderPreview() async {
    isRendering = true
    defer { isRendering = false }
    // A beat, so dragging through a picker doesn't render every value on the way.
    try? await Task.sleep(nanoseconds: 220_000_000)
    guard !Task.isCancelled else { return }

    let document = store.document
    guard
      let data = try? ResumePDFRenderer.render(document: document, includeAttachments: false),
      let page = PDFDocument(data: data)?.page(at: 0)
    else { return }
    guard !Task.isCancelled else { return }
    preview = page.thumbnail(of: CGSize(width: 324, height: 459), for: .mediaBox)
  }

  // MARK: - Pickers

  /// One row per section. The value is a `nil`-able override, so "Template
  /// default" is a real choice rather than a sentinel case in every enum.
  private func picker<Value: Hashable>(
    _ title: LocalizedStringResource,
    _ options: [SectionStyleOption<Value>],
    _ path: WritableKeyPath<ResumeSectionStyleOverrides, Value?>
  ) -> some View {
    Picker(
      selection: Binding(
        get: { styles[keyPath: path] },
        set: { store.document.layout.sectionStyles[keyPath: path] = $0 }
      )
    ) {
      ForEach(options) { option in
        VStack(alignment: .leading) {
          Text(option.title)
          if let seenIn = option.seenIn {
            Text("as in \(seenIn)")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
        .tag(option.value)
      }
    } label: {
      HStack(spacing: 8) {
        Text(title)
        if styles[keyPath: path] != nil {
          Circle().fill(accent).frame(width: 6, height: 6)
        }
      }
    }
    // A pushed list, not the pop-up menu: the menu style flattens each option to
    // its first line and drops "as in Chronicle Timeline" — which is the whole
    // reason someone opens this screen.
    .pickerStyle(.navigationLink)
  }
}

#Preview {
  NavigationStack {
    SectionStyleEditorView()
      .environmentObject(ResumeStore(initialDocument: .example))
  }
}
