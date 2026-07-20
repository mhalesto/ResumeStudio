import PDFKit
import SwiftUI

struct LayoutStudioView: View {
  @EnvironmentObject private var store: ResumeStore
  @State private var layout = ResumeLayoutSettings.standard
  @State private var pageCount: Int?
  @State private var attachmentPageCount = 0
  @State private var isFitting = false
  @State private var fitMessage: String?

  var body: some View {
    Form {
      Section("Typography") {
        Picker("Typeface", selection: $layout.fontChoice) {
          ForEach(ResumeFontChoice.allCases) { Text($0.title).tag($0) }
        }
        VStack(alignment: .leading) {
          LabeledContent("Text size", value: "\(Int(layout.fontScale * 100))%")
          Slider(value: $layout.fontScale, in: 0.82...1.12, step: 0.01)
        }
        VStack(alignment: .leading) {
          LabeledContent("Line spacing", value: "\(Int(layout.lineSpacing * 100))%")
          Slider(value: $layout.lineSpacing, in: 0.88...1.15, step: 0.01)
        }
      }

      Section("Page") {
        Picker("Paper", selection: $layout.paperSize) {
          ForEach(ResumePaperSize.allCases) { Text($0.title).tag($0) }
        }
        Picker("Target", selection: $layout.pageTarget) {
          ForEach(ResumePageTarget.allCases) { Text($0.title).tag($0) }
        }
        VStack(alignment: .leading) {
          LabeledContent("Margins", value: "\(Int(layout.marginPoints)) pt")
          Slider(value: $layout.marginPoints, in: 24...50, step: 1)
        }
        if let pageCount { LabeledContent("Current output", value: "\(pageCount) page\(pageCount == 1 ? "" : "s")") }
        if attachmentPageCount > 0 {
          LabeledContent(
            "Attachments",
            value: "+\(attachmentPageCount) page\(attachmentPageCount == 1 ? "" : "s")")
        }
        Button {
          Task { await autoFit() }
        } label: {
          if isFitting { ProgressView("Finding the safest fit…") }
          else { Label("Auto-fit to page target", systemImage: "arrow.up.left.and.arrow.down.right") }
        }
        .disabled(layout.pageTarget == .automatic || isFitting)
        if let fitMessage { Text(fitMessage).font(.caption).foregroundStyle(Theme.mutedInk) }
      }

      Section("Section order") {
        ForEach(layout.sectionOrder) { block in
          HStack { Image(systemName: "line.3.horizontal").foregroundStyle(Theme.mutedInk); Text(block.title) }
        }
        .onMove { layout.sectionOrder.move(fromOffsets: $0, toOffset: $1) }
      }

      Section("Custom headings") {
        ForEach(ResumeContentBlock.allCases.filter { $0 != .additional }) { block in
          TextField(block.title, text: headingBinding(block))
        }
      }

      Section {
        NavigationLink {
          ResumePreviewView(document: store.document)
        } label: { Label("Preview layout", systemImage: "doc.text.magnifyingglass") }
        Button("Reset layout controls", systemImage: "arrow.counterclockwise", role: .destructive) {
          layout = .standard
        }
      }
    }
    .navigationTitle("Layout Studio")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar { EditButton() }
    .onAppear {
      layout = store.document.layout
      refreshPageCount()
    }
    .onChange(of: layout) { _, value in
      var normalized = value
      normalized.normalize()
      if normalized != store.document.layout { store.document.layout = normalized }
      refreshPageCount()
    }
  }

  private func headingBinding(_ block: ResumeContentBlock) -> Binding<String> {
    Binding(
      get: { layout.customHeadings[block.rawValue] ?? "" },
      set: { value in layout.customHeadings[block.rawValue] = value }
    )
  }

  /// The résumé's own length, which is what the page target is about. Attached
  /// certificates are reported separately rather than counted against it.
  private func refreshPageCount() {
    var document = store.document
    document.layout = layout
    pageCount = (try? ResumePDFRenderer.render(document: document, includeAttachments: false))
      .flatMap(PDFDocument.init(data:))?.pageCount
    attachmentPageCount = document.attachmentPageCount
  }

  @MainActor
  private func autoFit() async {
    isFitting = true
    fitMessage = nil
    do {
      var document = store.document
      document.layout = layout
      let result = try ResumeAutoFitService.fit(document, target: layout.pageTarget)
      layout = result.document.layout
      store.document = result.document
      pageCount = result.pageCount
      fitMessage = result.reachedTarget
        ? "Fit achieved without reducing text below the safe minimum."
        : "The content still needs \(result.pageCount) pages at the safe minimum size. Shorten or remove content instead of making it unreadable."
    } catch { fitMessage = error.localizedDescription }
    isFitting = false
  }
}

private enum ResumeComparisonField: String, CaseIterable, Identifiable {
  case personal, profile, competencies, experience, education, additional, references, appearance
  var id: String { rawValue }
  var title: LocalizedStringResource {
    switch self {
    case .personal: "Personal details"
    case .profile: "Professional profile"
    case .competencies: "Competencies"
    case .experience: "Experience"
    case .education: "Education"
    case .additional: "Additional sections"
    case .references: "References"
    case .appearance: "Template and layout"
    }
  }
}

struct ResumeVersionComparisonView: View {
  @EnvironmentObject private var store: ResumeStore
  @EnvironmentObject private var purchases: PurchaseManager
  @State private var leftID: UUID?
  @State private var rightID: UUID?

  private var left: ResumeDraft? { store.resumes.first { $0.id == leftID } }
  private var right: ResumeDraft? { store.resumes.first { $0.id == rightID } }
  private var changedFields: [ResumeComparisonField] {
    guard let left, let right else { return [] }
    return ResumeComparisonField.allCases.filter { differs($0, left.document, right.document) }
  }

  var body: some View {
    List {
      Section("Compare") {
        Picker("From", selection: $leftID) {
          Text("Choose version").tag(UUID?.none)
          ForEach(store.resumes) { Text($0.title).tag(Optional($0.id)) }
        }
        Picker("Against", selection: $rightID) {
          Text("Choose version").tag(UUID?.none)
          ForEach(store.resumes) { Text($0.title).tag(Optional($0.id)) }
        }
      }

      if let left, let right {
        Section {
          HStack {
            versionSummary(left)
            Image(systemName: "arrow.left.arrow.right").foregroundStyle(store.document.accent.color)
            versionSummary(right)
          }
        }
        if changedFields.isEmpty {
          Section { Label("These versions are identical.", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
        } else {
          Section("\(changedFields.count) changed areas") {
            ForEach(changedFields) { field in
              VStack(alignment: .leading, spacing: 8) {
                Label(field.title, systemImage: "arrow.triangle.2.circlepath")
                  .font(.headline).foregroundStyle(store.document.accent.color)
                HStack(alignment: .top, spacing: 12) {
                  Text(summary(field, left.document)).frame(maxWidth: .infinity, alignment: .leading)
                  Divider()
                  Text(summary(field, right.document)).frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption).foregroundStyle(Theme.inkSoft)
                Button("Restore \(left.title) version into active résumé") {
                  restore(field, from: left.document)
                }
                .font(.caption.bold())
              }
              .padding(.vertical, 5)
            }
          }
        }
      }
    }
    .navigationTitle("Compare Versions")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      rightID = store.activeResumeID
      leftID = store.resumes.first(where: { $0.id != store.activeResumeID })?.id
    }
  }

  private func versionSummary(_ draft: ResumeDraft) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(draft.title).font(.subheadline.bold())
      Text(draft.document.template.title).font(.caption).foregroundStyle(Theme.mutedInk)
      Text(draft.updatedAt, style: .relative).font(.caption2).foregroundStyle(Theme.mutedInk)
    }.frame(maxWidth: .infinity, alignment: .leading)
  }

  private func differs(_ field: ResumeComparisonField, _ lhs: ResumeDocument, _ rhs: ResumeDocument) -> Bool {
    switch field {
    case .personal: lhs.personal != rhs.personal
    case .profile: lhs.professionalProfile != rhs.professionalProfile
    case .competencies: lhs.competencies != rhs.competencies
    case .experience: lhs.experience != rhs.experience
    case .education: lhs.education != rhs.education
    case .additional: lhs.additionalSections != rhs.additionalSections
    case .references: lhs.references != rhs.references
    case .appearance: lhs.template != rhs.template || lhs.accent != rhs.accent || lhs.layout != rhs.layout
    }
  }

  private func summary(_ field: ResumeComparisonField, _ document: ResumeDocument) -> String {
    switch field {
    case .personal: [document.personal.fullName, document.personal.headline].filter { !$0.isBlank }.joined(separator: " · ")
    case .profile: String(document.professionalProfile.prefix(180))
    case .competencies: document.competencies.prefix(6).joined(separator: " · ")
    case .experience: "\(document.experience.count) roles · \(document.experience.flatMap(\.highlights).count) bullets"
    case .education: "\(document.education.count) education entries"
    case .additional: document.additionalSections.map(\.title).joined(separator: " · ")
    case .references: "\(document.references.count) references"
    case .appearance: "\(document.template.title) · \(document.layout.paperSize.title) · \(Int(document.layout.fontScale * 100))%"
    }
  }

  private func restore(_ field: ResumeComparisonField, from source: ResumeDocument) {
    if field == .appearance,
       (!purchases.canUse(source.template) || !purchases.canUse(source.accent)) {
      purchases.requestPlans()
      return
    }
    var active = store.document
    switch field {
    case .personal: active.personal = source.personal
    case .profile: active.professionalProfile = source.professionalProfile
    case .competencies: active.competencies = source.competencies
    case .experience: active.experience = source.experience
    case .education: active.education = source.education
    case .additional: active.additionalSections = source.additionalSections
    case .references: active.references = source.references
    case .appearance:
      active.template = source.template; active.accent = source.accent; active.layout = source.layout
    }
    store.replaceActiveDocument(with: active)
  }
}

struct MarketLocalizationStudioView: View {
  @EnvironmentObject private var resumeStore: ResumeStore
  @EnvironmentObject private var careerStore: CareerIntelligenceStore
  @State private var language = "English"
  @State private var translation: AITranslatedResume?
  @State private var isTranslating = false
  @State private var errorMessage: String?

  var body: some View {
    Form {
      Section("Target") {
        Picker("Market", selection: $careerStore.preferredMarket) {
          ForEach(ResumeMarket.allCases) { Text("\($0.flag) \($0.title)").tag($0) }
        }
        TextField("Document language", text: $language)
        LabeledContent("Recommended paper", value: [.unitedStates, .canada].contains(careerStore.preferredMarket) ? "US Letter" : "A4")
      }

      Section {
        Button("Apply market formatting", systemImage: "globe") {
          ResumeMarketLocalizationService.apply(
            market: careerStore.preferredMarket, language: language, to: &resumeStore.document)
        }
        if [.unitedStates, .canada, .unitedKingdom].contains(careerStore.preferredMarket), resumeStore.document.showsPortrait {
          Label("Keep a photo-free version for this market.", systemImage: "person.crop.circle.badge.exclamationmark")
            .font(.caption).foregroundStyle(.orange)
        }
      } footer: {
        Text("Formatting changes paper size and section terminology. It never removes personal data automatically.")
      }

      Section("Evidence-safe translation") {
        Button {
          Task { await translate() }
        } label: {
          if isTranslating { ProgressView("Translating without changing facts…") }
          else { Label("Translate résumé content", systemImage: "character.book.closed.fill") }
        }
        .disabled(language.isBlank || language.lowercased() == "english" || isTranslating)
        Text("The request excludes contact details, references and the profile photo. Employers, dates, numbers and experience identifiers must be preserved.")
          .font(.caption).foregroundStyle(Theme.mutedInk)
      }

      if let translation {
        Section("Translation review") {
          LabeledContent("Headline", value: translation.headline)
          Text(translation.professionalProfile)
          LabeledContent("Skills", value: "\(translation.competencies.count)")
          LabeledContent("Roles preserved", value: "\(translation.experience.count)")
          ForEach(translation.claimsRequiringConfirmation, id: \.self) {
            Label($0, systemImage: "exclamationmark.shield.fill").foregroundStyle(.orange)
          }
          Button("Create translated résumé version", systemImage: "doc.on.doc.fill") {
            var document = translation.applying(to: resumeStore.document)
            ResumeMarketLocalizationService.apply(
              market: careerStore.preferredMarket, language: language, to: &document)
            _ = resumeStore.createResume(
              title: "\(resumeStore.activeDraft?.title ?? "Résumé") — \(language)", from: document)
            self.translation = nil
          }
          .fontWeight(.semibold)
        }
      }

      if let errorMessage {
        Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
      }
    }
    .navigationTitle("Localize Résumé")
    .navigationBarTitleDisplayMode(.inline)
  }

  @MainActor
  private func translate() async {
    isTranslating = true; errorMessage = nil
    do {
      translation = try await ResumeAIService.shared.translateResume(
        document: resumeStore.document, targetLanguage: language,
        market: careerStore.preferredMarket)
    } catch { errorMessage = error.localizedDescription }
    isTranslating = false
  }
}
