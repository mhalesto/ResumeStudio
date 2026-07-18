import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct ResumeLibraryView: View {
  @EnvironmentObject private var store: ResumeStore
  @EnvironmentObject private var cloudSync: ICloudSyncService
  @EnvironmentObject private var purchases: PurchaseManager
  @State private var renameDraft: ResumeDraft?
  @State private var renameText = ""

  var body: some View {
    List {
      Section {
        ForEach(store.resumes) { draft in
          Button {
            store.selectResume(draft.id)
          } label: {
            HStack(spacing: 12) {
              Image(systemName: draft.id == store.activeResumeID ? "checkmark.circle.fill" : "doc.text")
                .foregroundStyle(draft.id == store.activeResumeID ? store.document.accent.color : Theme.mutedInk)
              VStack(alignment: .leading, spacing: 3) {
                Text(draft.title).font(.headline).foregroundStyle(Theme.ink)
                Text("\(draft.document.personal.fullName.nilIfBlank ?? "Untitled") · \(draft.document.template.title)")
                  .font(.caption).foregroundStyle(Theme.mutedInk).lineLimit(1)
              }
              Spacer()
              Text(draft.updatedAt, style: .relative).font(.caption2).foregroundStyle(Theme.mutedInk)
            }
          }
          .buttonStyle(.plain)
          .swipeActions(edge: .trailing) {
            if store.resumes.count > 1 {
              Button(role: .destructive) { store.deleteResume(draft.id) } label: {
                Label("Delete", systemImage: "trash")
              }
            }
            Button {
              renameText = draft.title
              renameDraft = draft
            } label: { Label("Rename", systemImage: "pencil") }
            .tint(.blue)
          }
          .swipeActions(edge: .leading) {
            // Fork this version — a "save as" for tailoring one résumé per job
            // without losing the original.
            Button {
              if purchases.canCreateResume(currentCount: store.resumes.count) {
                _ = store.createResume(title: "\(draft.title) Copy", from: draft.document)
              } else {
                purchases.requestPlans()
              }
            } label: { Label("Duplicate", systemImage: "doc.on.doc") }
            .tint(store.document.accent.color)
          }
        }
      } header: { Text("Résumé versions") }

      Section {
        NavigationLink {
          TemplateGalleryView()
        } label: {
          LibraryPremiumActionCard(
            title: "Browse templates",
            subtitle: "\(ResumeTemplate.allCases.count) résumé and \(CoverLetterTemplate.allCases.count) cover-letter designs",
            detail: "Preview every layout and colour",
            systemImage: "rectangle.split.2x1.fill",
            accent: store.document.accent.color,
            artwork: .templates
          )
        }
        .listRowBackground(
          LibraryPremiumRowBackground(accent: store.document.accent.color)
        )
        .listRowSeparator(.hidden)
      }

      Section {
        NavigationLink {
          ResumeImportView()
        } label: {
          let allowance = purchases.currentImportAllowance
          LibraryPremiumActionCard(
            title: "Import résumé",
            subtitle: "PDF, DOCX, text or LinkedIn export",
            detail: "\(allowance.importsRemaining) AI-assisted imports left today · local previews unlimited",
            systemImage: "square.and.arrow.down.fill",
            accent: store.document.accent.color,
            artwork: .importResume
          )
        }
        .listRowBackground(
          LibraryPremiumRowBackground(accent: store.document.accent.color)
        )
        .listRowSeparator(.hidden)
      }

      Section("Version tools") {
        NavigationLink {
          ResumeVersionComparisonView()
        } label: {
          Label("Compare résumé versions", systemImage: "arrow.left.arrow.right.square")
        }
      }

      Section("Sync") {
        Toggle("iCloud sync", isOn: $cloudSync.isEnabled)
        Button("Sync now", systemImage: "arrow.triangle.2.circlepath") {
          Task { await cloudSync.synchronize() }
        }
        cloudStatus
      }
    }
    .navigationTitle("My résumés")
    .toolbar {
      Menu {
        Button("Blank résumé", systemImage: "doc") {
          if purchases.canCreateResume(currentCount: store.resumes.count) { store.createResume() }
          else { purchases.requestPlans() }
        }
        Button("Duplicate active", systemImage: "doc.on.doc") {
          if purchases.canCreateResume(currentCount: store.resumes.count) { store.duplicateActiveResume() }
          else { purchases.requestPlans() }
        }
      } label: { Image(systemName: "plus") }
    }
    .alert("Rename résumé", isPresented: Binding(
      get: { renameDraft != nil }, set: { if !$0 { renameDraft = nil } }
    )) {
      TextField("Name", text: $renameText)
      Button("Save") {
        if let renameDraft { store.renameResume(renameDraft.id, to: renameText) }
        renameDraft = nil
      }
      Button("Cancel", role: .cancel) { renameDraft = nil }
    }
  }

  @ViewBuilder private var cloudStatus: some View {
    switch cloudSync.status {
    case .notConfigured: Label("Sync paused", systemImage: "pause.circle")
    case .unavailable: Label("Sign into iCloud to sync", systemImage: "icloud.slash")
    case .syncing: ProgressView("Syncing…")
    case .conflict: Label("Resolve this conflict in Settings", systemImage: "exclamationmark.arrow.triangle.2.circlepath").foregroundStyle(.orange)
    case .synced(let date): Label("Synced \(date.formatted(.relative(presentation: .named)))", systemImage: "checkmark.icloud")
    case .failed(let message): Label(message, systemImage: "exclamationmark.icloud").foregroundStyle(.red)
    }
  }
}

private struct LibraryPremiumRowBackground: View {
  let accent: Color

  var body: some View {
    LinearGradient(
      colors: [accent.opacity(0.20), Theme.card, Theme.card],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
    .overlay {
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .strokeBorder(accent.opacity(0.30), lineWidth: 1)
    }
  }
}

private struct LibraryPremiumActionCard: View {
  enum Artwork { case templates, importResume }

  let title: String
  let subtitle: String
  let detail: String
  let systemImage: String
  let accent: Color
  let artwork: Artwork

  var body: some View {
    HStack(spacing: 15) {
      ZStack {
        RoundedRectangle(cornerRadius: 17, style: .continuous)
          .fill(accent.opacity(0.18))
        Image(systemName: systemImage)
          .font(.system(size: 23, weight: .semibold))
          .foregroundStyle(accent)
      }
      .frame(width: 58, height: 58)

      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 7) {
          Text(title)
            .font(.headline)
            .foregroundStyle(Theme.ink)
          Text("FEATURED")
            .font(.system(size: 8, weight: .black))
            .tracking(0.7)
            .foregroundStyle(accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(accent.opacity(0.14), in: Capsule())
        }
        Text(subtitle)
          .font(.subheadline.weight(.medium))
          .foregroundStyle(Theme.ink.opacity(0.78))
          .lineLimit(2)
        Text(detail)
          .font(.caption)
          .foregroundStyle(Theme.mutedInk)
          .lineLimit(2)
      }

      Spacer(minLength: 4)
      artworkView
        .frame(width: 48, height: 62)
    }
    .padding(.vertical, 10)
    .contentShape(Rectangle())
  }

  @ViewBuilder private var artworkView: some View {
    switch artwork {
    case .templates:
      ZStack {
        ForEach(0..<3, id: \.self) { index in
          RoundedRectangle(cornerRadius: 4)
            .fill(index == 2 ? accent.opacity(0.30) : Theme.paper)
            .overlay(alignment: .topLeading) {
              VStack(alignment: .leading, spacing: 3) {
                Capsule().fill(accent.opacity(0.85)).frame(width: 15, height: 3)
                Capsule().fill(Theme.mutedInk.opacity(0.45)).frame(width: 22, height: 2)
                Capsule().fill(Theme.mutedInk.opacity(0.30)).frame(width: 18, height: 2)
              }
              .padding(5)
            }
            .frame(width: 34, height: 47)
            .rotationEffect(.degrees(Double(index - 1) * 7))
            .offset(x: CGFloat(index - 1) * 6, y: CGFloat(abs(index - 1)) * 3)
            .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
        }
      }
    case .importResume:
      ZStack {
        Circle().fill(accent.opacity(0.13)).frame(width: 47, height: 47)
        Circle().stroke(accent.opacity(0.30), lineWidth: 1).frame(width: 47, height: 47)
        Image(systemName: "arrow.down.doc.fill")
          .font(.system(size: 21, weight: .semibold))
          .foregroundStyle(accent)
      }
    }
  }
}

struct ATSCheckerView: View {
  @EnvironmentObject private var store: ResumeStore
  @State private var jobDescription = ""
  @State private var baselineScore: Int?

  private var report: ATSReadinessReport {
    ATSReadinessService.analyze(document: store.document, jobDescription: jobDescription)
  }

  var body: some View {
    List {
      Section {
        HStack(spacing: 18) {
          ZStack {
            Circle().stroke(Theme.hairline, lineWidth: 9)
            Circle().trim(from: 0, to: Double(report.score) / 100)
              .stroke(store.document.accent.color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
              .rotationEffect(.degrees(-90))
            Text("\(report.score)").font(.title.bold())
          }.frame(width: 88, height: 88)
          VStack(alignment: .leading, spacing: 5) {
            Text("Transparent readiness score").font(.headline)
            Text("Built from the checks below—not a promise about any employer's ATS.")
              .font(.caption).foregroundStyle(Theme.mutedInk)
            if let baselineScore, baselineScore != report.score {
              Text("\(report.score >= baselineScore ? "+" : "")\(report.score - baselineScore) since opening")
                .font(.caption.bold()).foregroundStyle(report.score >= baselineScore ? .green : .orange)
            }
          }
        }.padding(.vertical, 6)
      }

      Section {
        TextEditor(text: $jobDescription)
          .frame(minHeight: 120)
          .accessibilityLabel("Optional job description")
      } header: { Text("Optional target job") }
        footer: { Text("Paste an advert to add evidence-backed keyword coverage and placement guidance.") }

      Section("Readiness checklist") {
        ForEach(report.items) { item in
          if let section = item.section {
            NavigationLink(value: HomeRoute.editor(section)) { issueRow(item) }
          } else {
            issueRow(item)
          }
        }
      }

      if !jobDescription.isBlank {
        Section("Keyword evidence") {
          if !report.matchedKeywords.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
              Label("Demonstrated", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
              FlowTagCloud(items: Array(report.matchedKeywords.prefix(16)), accent: .green)
            }
          }
          ForEach(ATSReadinessService.keywordSuggestions(document: store.document, jobDescription: jobDescription)) { suggestion in
            NavigationLink(value: HomeRoute.editor(suggestion.section)) {
              VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.keyword).font(.headline)
                Text(suggestion.guidance).font(.caption).foregroundStyle(Theme.mutedInk)
              }
            }
          }
        }
      }

      Section("Parser preview") {
        NavigationLink {
          ATSParsedResumeView(document: store.document)
        } label: {
          Label("View extracted text and reading order", systemImage: "text.viewfinder")
        }
      }

      Section {
        NavigationLink(value: HomeRoute.recruiterScan) {
          Label("Watch the 7.4-second recruiter scan", systemImage: "eye")
        }
      } header: {
        Text("The human pass")
      } footer: {
        Text("The checks above are for the machine. This replays the recruiter's first look on your résumé, from published eye-tracking research.")
      }
    }
    .supportsKeyboardDismissal()
    .navigationTitle("ATS readiness")
    .onAppear { baselineScore = report.score }
  }

  private func issueRow(_ item: ATSCheckItem) -> some View {
    HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon(for: item.severity))
              .foregroundStyle(color(for: item.severity)).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
              Text(item.title).font(.headline)
              Text(item.detail).font(.caption).foregroundStyle(Theme.mutedInk)
            }
          }
          .padding(.vertical, 3)
  }

  private func icon(for severity: ATSIssueSeverity) -> String {
    switch severity { case .pass: "checkmark.circle.fill"; case .warning: "exclamationmark.triangle.fill"; case .action: "xmark.circle.fill" }
  }
  private func color(for severity: ATSIssueSeverity) -> Color {
    switch severity { case .pass: .green; case .warning: .orange; case .action: .red }
  }
}

struct ATSParsedResumeView: View {
  let document: ResumeDocument
  @State private var extractedText = ""
  @State private var pageCount = 0
  @State private var errorMessage: String?

  var body: some View {
    List {
      Section {
        LabeledContent("Pages", value: "\(pageCount)")
        LabeledContent("Structure", value: document.template.plan.hasSideColumn ? "Two-column" : "Single-column")
        if document.template.plan.hasSideColumn {
          Label("Check the sequence below: some systems read the narrow column before the main story.", systemImage: "exclamationmark.triangle.fill")
            .font(.caption).foregroundStyle(.orange)
        }
      }
      Section("What a text extractor sees") {
        Text(extractedText.isBlank ? "No searchable text was extracted." : extractedText)
          .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
      }
      if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
    }
    .navigationTitle("ATS Parsed View")
    .navigationBarTitleDisplayMode(.inline)
    .task { render() }
  }

  @MainActor private func render() {
    do {
      let data = try ResumePDFRenderer.render(document: document)
      let pdf = PDFDocument(data: data)
      pageCount = pdf?.pageCount ?? 0
      extractedText = pdf?.string ?? ""
    } catch { errorMessage = error.localizedDescription }
  }
}

struct ApplicationTrackerView: View {
  @EnvironmentObject private var store: ApplicationStore
  @State private var status: JobApplicationStatus = .saved

  var body: some View {
    List {
      Section {
        Picker("Stage", selection: $status) {
          ForEach(JobApplicationStatus.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
      }

      Section {
        ForEach(store.applications(with: status)) { application in
          NavigationLink(value: HomeRoute.applicationDetail(application.id)) {
            VStack(alignment: .leading, spacing: 4) {
              Text(application.role.isBlank ? "Untitled role" : application.role).font(.headline)
              Text(application.company.isBlank ? "Company not set" : application.company)
                .font(.subheadline).foregroundStyle(Theme.mutedInk)
              Text(application.updatedAt, style: .relative).font(.caption2).foregroundStyle(Theme.mutedInk)
            }
          }
        }
      } header: { Text("\(store.applications(with: status).count) \(status.title.lowercased())") }

      Section {
        NavigationLink(value: HomeRoute.jobTargeting) {
          Label("Add and target a job", systemImage: "plus.circle.fill")
        }
      }
    }
    .navigationTitle("Applications")
  }
}

struct ApplicationDetailView: View {
  @EnvironmentObject private var store: ApplicationStore
  let applicationID: UUID
  @State private var draft: JobApplication?
  @State private var originalStatus: JobApplicationStatus?
  @State private var outcomeReviewRequest: OutcomeReviewRequest?

  var body: some View {
    Form {
      if let binding = Binding($draft) {
        Section("Job") {
          TextField("Role", text: binding.role)
          TextField("Company", text: binding.company)
          TextField("Source URL", text: binding.sourceURL)
          Picker("Status", selection: Binding(
            get: { binding.wrappedValue.status },
            set: { updateStatus($0) }
          )) {
            ForEach(JobApplicationStatus.allCases) { Text($0.title).tag($0) }
          }
        }
        Section("Notes") { TextEditor(text: binding.notes).frame(minHeight: 120) }
        if binding.wrappedValue.canReviewCurrentOutcome {
          Section {
            Button {
              outcomeReviewRequest = OutcomeReviewRequest(applicationID: applicationID)
            } label: {
              HStack(spacing: 12) {
                Image(systemName: binding.wrappedValue.currentOutcomeReview == nil
                  ? "checklist" : "checkmark.seal.fill")
                  .foregroundStyle(.orange).frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                  Text(binding.wrappedValue.currentOutcomeReview == nil
                    ? "Review this outcome" : "Outcome reviewed")
                    .font(.headline).foregroundStyle(Theme.ink)
                  Text(binding.wrappedValue.currentOutcomeReview?.reason.title
                    ?? "Capture what happened and improve the next application.")
                    .font(.caption).foregroundStyle(Theme.mutedInk)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.mutedInk)
              }
            }
            .buttonStyle(.plain)
          } header: { Text("Learning loop") }
            footer: { Text("The debrief stays private and remains tied to the exact résumé version used.") }
        }
        if let deadline = binding.wrappedValue.deadline {
          Section("Deadline") {
            DatePicker("Closing date", selection: Binding(
              get: { deadline }, set: { draft?.deadline = $0 }
            ), displayedComponents: [.date, .hourAndMinute])
            Label("A reminder is scheduled three days before the deadline.", systemImage: "bell.badge.fill")
              .font(.caption).foregroundStyle(Theme.mutedInk)
          }
        }
        Section("Activity timeline") {
          ForEach(binding.wrappedValue.activityTimeline) { activity in
            HStack(alignment: .top, spacing: 12) {
              Image(systemName: activity.kind.systemImage).foregroundStyle(.orange).frame(width: 22)
              VStack(alignment: .leading, spacing: 3) {
                Text(activity.title).font(.headline)
                if !activity.detail.isBlank { Text(activity.detail).font(.caption).foregroundStyle(Theme.mutedInk) }
                Text(activity.occurredAt, style: .relative).font(.caption2).foregroundStyle(Theme.mutedInk)
              }
            }
          }
        }
        Section {
          NavigationLink(value: HomeRoute.applicationPacket(applicationID)) {
            Label("Open application packet", systemImage: "shippingbox.fill")
          }
          NavigationLink(value: HomeRoute.interviewPrep(applicationID)) {
            Label("Prepare for interview", systemImage: "person.wave.2.fill")
          }
          NavigationLink(value: HomeRoute.interviewEditor(interviewID: nil, applicationID: applicationID)) {
            Label("Schedule interview", systemImage: "calendar.badge.plus")
          }
          NavigationLink(value: HomeRoute.networking) {
            Label("Plan recruiter follow-up", systemImage: "person.2.wave.2.fill")
          }
          NavigationLink(value: HomeRoute.offers) {
            Label("Add or compare an offer", systemImage: "scale.3d")
          }
        }
      } else {
        ContentUnavailableView("Application not found", systemImage: "doc.questionmark")
      }
    }
    .supportsKeyboardDismissal()
    .navigationTitle(draft?.role.nilIfBlank ?? "Application")
    .onAppear {
      draft = store.applications.first { $0.id == applicationID }
      originalStatus = draft?.status
    }
    .onDisappear {
      guard var draft else { return }
      if let originalStatus, originalStatus != draft.status {
        var activities = draft.activities ?? []
        activities.append(ApplicationActivity(kind: .statusChanged, title: "Moved to \(draft.status.title)", detail: "Previously \(originalStatus.title)"))
        draft.activities = activities
      }
      store.update(draft)
    }
    .sheet(item: $outcomeReviewRequest, onDismiss: reload) { request in
      OutcomeReviewSheet(applicationID: request.applicationID)
    }
  }

  private func reload() {
    draft = store.applications.first { $0.id == applicationID }
    originalStatus = draft?.status
  }

  private func updateStatus(_ status: JobApplicationStatus) {
    guard var current = draft, current.status != status else { return }
    let previous = current.status
    current.status = status
    var activities = current.activities ?? []
    activities.append(ApplicationActivity(
      kind: status == .applied ? .applied : status == .offer ? .offer : .statusChanged,
      title: "Moved to \(status.title)", detail: "Previously \(previous.title)"
    ))
    current.activities = activities
    draft = current
    originalStatus = status
    store.update(current)
    if current.canReviewCurrentOutcome && current.currentOutcomeReview == nil {
      outcomeReviewRequest = OutcomeReviewRequest(applicationID: applicationID)
    }
  }
}

struct ResumeImportView: View {
  @EnvironmentObject private var store: ResumeStore
  @EnvironmentObject private var purchases: PurchaseManager
  @EnvironmentObject private var network: NetworkMonitor
  @Environment(\.dismiss) private var dismiss
  @State private var isChoosingFiles = false
  @State private var imported: ResumeDocument?
  @State private var title = "Imported Résumé"
  @State private var errorMessage: String?
  @State private var importWarnings: [String] = []
  @State private var isStructuringWithAI = false
  @State private var isAIEnhanced = false
  @State private var importStatus = "Choose a file to create a private on-device preview."
  @State private var versionChoice: ImportVersionChoice?
  @State private var pendingVersionAction: PendingImportVersionAction?
  @State private var queuedVersionAction: PendingImportVersionAction?

  private static let supportedTypes: [UTType] = [
    .pdf,
    UTType(filenameExtension: "docx") ?? .data,
    .commaSeparatedText,
    .zip,
    .plainText,
  ]

  var body: some View {
    List {
      Section {
        Label("AI structures your résumé", systemImage: "sparkles")
          .foregroundStyle(store.document.accent.color)
        Text("Your file is opened on this iPhone, then its extracted text is sent securely to the AI service to identify experience, education, skills and other résumé sections. The original file is not uploaded.")
          .font(.footnote)
          .foregroundStyle(Theme.mutedInk)
        let allowance = purchases.currentImportAllowance
        Label(
          "\(allowance.importsRemaining) of \(allowance.importsLimit) AI-assisted imports remaining today",
          systemImage: "calendar.badge.checkmark"
        )
        .font(.footnote.weight(.semibold))
        Text("AI-assisted imports have their own daily allowance and never use your general AI credits. Local extraction and previews remain available after the allowance is used or while offline.")
          .font(.caption).foregroundStyle(Theme.mutedInk)
      }

      Section {
        Button {
          isChoosingFiles = true
        } label: {
          if isStructuringWithAI {
            HStack {
              ProgressView()
              Text("Preparing your résumé…")
            }
          } else {
            Label("Choose files", systemImage: "folder.badge.plus")
          }
        }
        .disabled(isStructuringWithAI)
        Text(importStatus).font(.caption).foregroundStyle(Theme.mutedInk)
      }

      if let imported {
        Section("Import review") {
          TextField("Version name", text: $title)
          ImportSummaryRow(label: "Name", value: imported.personal.fullName.nilIfBlank ?? "Needs review")
          ImportSummaryRow(label: "Experience", value: "\(imported.experience.count) role(s)")
          ImportSummaryRow(label: "Education", value: "\(imported.education.count) item(s)")
          ImportSummaryRow(label: "Skills", value: "\(imported.competencies.count) found")
          ForEach(importWarnings.prefix(3), id: \.self) { warning in
            Label(warning, systemImage: "exclamationmark.triangle")
              .font(.caption)
              .foregroundStyle(.orange)
          }
          Label(
            isAIEnhanced
              ? "AI organized this import without rewriting it. Review the mapped fields before exporting."
              : "This on-device preview is ready to save and edit. Review the mapped fields before exporting.",
            systemImage: isAIEnhanced ? "checkmark.shield" : "iphone.and.arrow.forward"
          )
            .font(.caption).foregroundStyle(.orange)
          if purchases.canCreateResume(currentCount: store.resumes.count) {
            Button("Create résumé version", systemImage: "checkmark.circle.fill") {
              createImportedVersion(imported)
            }
            .fontWeight(.semibold)
          }
        }

        if !purchases.canCreateResume(currentCount: store.resumes.count) {
          Section {
            Label(
              "Free keeps up to \(purchases.resumeVersionLimit ?? 3) saved résumé versions. Your imported preview is safe until you choose what to do.",
              systemImage: "tray.full.fill"
            )
            .font(.footnote)

            Button("Replace current résumé", systemImage: "arrow.triangle.2.circlepath") {
              requestVersionAction(.replace, id: store.activeResumeID)
            }
            Button("Choose a version to replace", systemImage: "rectangle.2.swap") {
              versionChoice = ImportVersionChoice(mode: .replace)
            }
            Button("Delete a version and import", systemImage: "trash") {
              versionChoice = ImportVersionChoice(mode: .deleteAndImport)
            }
            .tint(.red)
            Button("Upgrade for unlimited versions", systemImage: "sparkles") {
              purchases.requestPlans()
            }
            .fontWeight(.semibold)
          } header: {
            Text("Your résumé library is full")
          } footer: {
            Text("Replacing or deleting affects only the version you choose. Your other résumés stay unchanged.")
          }
        }
      }

      if let errorMessage {
        Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
      }
    }
    .supportsKeyboardDismissal()
    .navigationTitle("Import résumé")
    .fileImporter(
      isPresented: $isChoosingFiles,
      allowedContentTypes: Self.supportedTypes,
      allowsMultipleSelection: true
    ) { result in
      do {
        let urls = try result.get()
        guard !urls.isEmpty else { return }
        structureWithAI(urls)
      } catch {
        imported = nil
        errorMessage = error.localizedDescription
      }
    }
    .sheet(item: $versionChoice, onDismiss: presentQueuedVersionAction) { choice in
      ImportVersionChoiceView(
        mode: choice.mode,
        importedTitle: title,
        onChoose: { id in
          queueVersionAction(choice.mode, id: id)
          versionChoice = nil
        },
        onUpgrade: {
          versionChoice = nil
          purchases.requestPlans()
        }
      )
      .environmentObject(store)
    }
    .sheet(item: $pendingVersionAction) { action in
      let source = store.resumes.first(where: { $0.id == action.id })
      PremiumConfirmationSheet(
        title: action.mode == .replace ? "Replace saved résumé?" : "Delete and save import?",
        message: action.mode == .replace
          ? "The imported preview will replace the selected version."
          : "One saved version will be removed to make room for the import.",
        systemImage: action.mode == .replace ? "arrow.triangle.2.circlepath" : "trash.fill",
        accent: store.document.accent.color,
        iconIsDestructive: action.mode == .deleteAndImport,
        rows: [
          PremiumConfirmationRow(
            eyebrow: action.mode == .replace ? "SAVED VERSION" : "VERSION TO DELETE",
            title: source?.title ?? "Selected résumé",
            detail: source.map {
              "\($0.document.personal.fullName.nilIfBlank ?? "Untitled") · \($0.document.template.title)"
            } ?? "Saved version",
            systemImage: action.mode == .replace ? "doc.text" : "trash",
            tone: action.mode == .replace ? .neutral : .destructive
          ),
          PremiumConfirmationRow(
            eyebrow: "IMPORTED PREVIEW",
            title: action.importedTitle,
            detail: {
              let document = action.importedDocument
              return "\(document.experience.count) role\(document.experience.count == 1 ? "" : "s") · \(document.competencies.count) skill\(document.competencies.count == 1 ? "" : "s")"
            }(),
            systemImage: "arrow.down.doc.fill",
            tone: .accent
          ),
        ],
        safetyNote: "Only this version changes. Your other saved résumés stay untouched.",
        confirmTitle: action.mode == .replace ? "Replace saved version" : "Delete version and save import",
        cancelTitle: "Keep my saved versions",
        onConfirm: { performVersionAction(action) },
        onCancel: { pendingVersionAction = nil }
      )
      .premiumConfirmationPresentation()
    }
  }

  private func structureWithAI(_ urls: [URL]) {
    imported = nil
    title = "Imported Résumé"
    errorMessage = nil
    importWarnings = []
    isAIEnhanced = false
    isStructuringWithAI = true
    importStatus = "Reading your file privately on this device…"

    Task {
      do {
        let local = try await Task.detached(priority: .userInitiated) {
          (
            text: try ResumeImportService.extractText(from: urls),
            document: try ResumeImportService.importDocuments(from: urls)
          )
        }.value
        applyImportedDocument(local.document)
        importStatus = "Local preview ready."

        guard network.isOnline else {
          importWarnings = ["You are offline, so this preview uses on-device import. Reconnect and choose the file again for AI-assisted structuring."]
          isStructuringWithAI = false
          return
        }

        let allowance = purchases.currentImportAllowance
        guard allowance.importsRemaining > 0 else {
          importWarnings = ["Your AI-assisted import allowance resets tomorrow. This local preview can still be saved, replaced or edited now."]
          isStructuringWithAI = false
          return
        }

        importStatus = "Local preview ready. AI is improving the section mapping…"
        do {
          let aiImport = try await ResumeAIService.shared.importResume(text: local.text)
          let document = aiImport.document
          guard !document.personal.fullName.isBlank
            || !document.experience.isEmpty
            || !document.education.isEmpty
          else {
            throw ResumeAIError.server(
              message: aiImport.warnings.first ?? "AI could not identify résumé content in this file."
            )
          }
          applyImportedDocument(document)
          isAIEnhanced = true
          importWarnings = aiImport.warnings
          importStatus = "AI-assisted structure ready. Review it before saving."
        } catch {
          importWarnings = ["AI assistance was unavailable: \(error.localizedDescription) Your on-device preview is still ready to use."]
          importStatus = "Local preview ready."
        }
        isStructuringWithAI = false
      } catch {
        imported = nil
        errorMessage = error.localizedDescription
        isStructuringWithAI = false
      }
    }
  }

  private func applyImportedDocument(_ document: ResumeDocument) {
    imported = document
    if !document.personal.fullName.isBlank {
      title = "\(document.personal.fullName) Résumé"
    }
  }

  private func createImportedVersion(_ document: ResumeDocument) {
    _ = store.createResume(title: title, from: document)
    dismiss()
  }

  private func requestVersionAction(_ mode: ImportVersionChoice.Mode, id: UUID) {
    guard let imported else { return }
    pendingVersionAction = PendingImportVersionAction(
      mode: mode,
      id: id,
      importedDocument: imported,
      importedTitle: title
    )
  }

  private func queueVersionAction(_ mode: ImportVersionChoice.Mode, id: UUID) {
    guard let imported else { return }
    queuedVersionAction = PendingImportVersionAction(
      mode: mode,
      id: id,
      importedDocument: imported,
      importedTitle: title
    )
  }

  private func presentQueuedVersionAction() {
    guard let action = queuedVersionAction else { return }
    queuedVersionAction = nil
    pendingVersionAction = action
  }

  private func performVersionAction(_ action: PendingImportVersionAction) {
    pendingVersionAction = nil
    switch action.mode {
    case .replace:
      guard store.replaceResume(
        action.id,
        with: action.importedDocument,
        title: action.importedTitle
      ) else { return }
      dismiss()
    case .deleteAndImport:
      guard store.createResume(
        replacing: action.id,
        title: action.importedTitle,
        from: action.importedDocument
      ) != nil else { return }
      dismiss()
    }
  }
}

private struct ImportVersionChoice: Identifiable {
  enum Mode: Equatable { case replace, deleteAndImport }
  let id = UUID()
  let mode: Mode
}

private struct PendingImportVersionAction: Identifiable {
  let mode: ImportVersionChoice.Mode
  let id: UUID
  let importedDocument: ResumeDocument
  let importedTitle: String
}

private struct ImportVersionChoiceView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: ResumeStore
  let mode: ImportVersionChoice.Mode
  let importedTitle: String
  let onChoose: (UUID) -> Void
  let onUpgrade: () -> Void

  var body: some View {
    NavigationStack {
      List {
        Section {
          Text(mode == .replace
            ? "Choose the saved version that should become “\(importedTitle)”."
            : "Choose one version to delete. The imported résumé will immediately take its place.")
            .font(.footnote).foregroundStyle(Theme.mutedInk)
        }
        Section(mode == .replace ? "Replace a version" : "Delete and import") {
          ForEach(store.resumes) { draft in
            Button(role: mode == .deleteAndImport ? .destructive : nil) {
              onChoose(draft.id)
            } label: {
              HStack(spacing: 12) {
                Image(systemName: mode == .replace ? "rectangle.2.swap" : "trash")
                VStack(alignment: .leading, spacing: 3) {
                  Text(draft.title).font(.headline)
                  Text(draft.document.personal.fullName.nilIfBlank ?? "Untitled résumé")
                    .font(.caption).foregroundStyle(Theme.mutedInk)
                }
                Spacer()
                if draft.id == store.activeResumeID {
                  Text("Current").font(.caption.bold()).foregroundStyle(Theme.mutedInk)
                }
              }
            }
          }
        }
        Section {
          Button("Keep every version and upgrade", systemImage: "sparkles") { onUpgrade() }
            .fontWeight(.semibold)
        }
      }
      .navigationTitle(mode == .replace ? "Choose a version" : "Free up a slot")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      }
    }
  }
}

private struct ImportSummaryRow: View {
  let label: String
  let value: String
  var body: some View {
    HStack { Text(label); Spacer(); Text(value).foregroundStyle(Theme.mutedInk) }
  }
}

struct InterviewCenterView: View {
  @EnvironmentObject private var resumeStore: ResumeStore
  @EnvironmentObject private var applicationStore: ApplicationStore
  @State private var selectedDate = Date()

  private var interviewsOnSelectedDate: [InterviewEvent] {
    applicationStore.interviews.filter {
      Calendar.current.isDate($0.scheduledAt, inSameDayAs: selectedDate)
    }.sorted { $0.scheduledAt < $1.scheduledAt }
  }

  var body: some View {
    List {
      Section {
        HStack(spacing: 14) {
          ZStack {
            Circle().fill(resumeStore.document.accent.color.opacity(0.14))
            Image(systemName: resumeStore.document.completionPercentage >= 90 ? "lock.open.fill" : "lock.fill")
              .foregroundStyle(resumeStore.document.accent.color)
          }.frame(width: 46, height: 46)
          VStack(alignment: .leading, spacing: 4) {
            Text(resumeStore.document.completionPercentage >= 90 ? "AI preparation unlocked" : "Complete 90% to unlock AI")
              .font(.headline)
            ProgressView(value: Double(resumeStore.document.completionPercentage), total: 100)
              .tint(resumeStore.document.accent.color)
            Text("Résumé is \(resumeStore.document.completionPercentage)% complete")
              .font(.caption).foregroundStyle(Theme.mutedInk)
          }
        }
        if resumeStore.document.completionPercentage < 90 {
          NavigationLink(value: HomeRoute.editor(resumeStore.document.incompleteSections.first)) {
            Label("Finish résumé", systemImage: "arrow.right.circle.fill")
          }
        }
      }

      if let next = applicationStore.upcomingInterviews.first {
        Section("Next interview") {
          NavigationLink(value: HomeRoute.interviewEditor(interviewID: next.id, applicationID: next.applicationID)) {
            InterviewEventRow(interview: next, showsOutcome: false)
          }
          if let applicationID = next.applicationID {
            NavigationLink(value: HomeRoute.interviewPrep(applicationID)) {
              Label("Open preparation", systemImage: "sparkles")
            }.disabled(completion(forApplicationID: applicationID) < 90)
          }
        }
      }

      Section("Calendar") {
        DatePicker("Interview calendar", selection: $selectedDate, displayedComponents: .date)
          .datePickerStyle(.graphical)
        if interviewsOnSelectedDate.isEmpty {
          Label("No interviews on this day", systemImage: "calendar")
            .foregroundStyle(Theme.mutedInk)
        } else {
          ForEach(interviewsOnSelectedDate) { interview in
            NavigationLink(value: HomeRoute.interviewEditor(interviewID: interview.id, applicationID: interview.applicationID)) {
              InterviewEventRow(interview: interview, showsOutcome: interview.isPast)
            }
          }
        }
      }

      Section("Prepare with AI") {
        if applicationStore.applications.isEmpty {
          NavigationLink(value: HomeRoute.jobTargeting) {
            Label("Add a target job first", systemImage: "briefcase.fill")
          }
        } else {
          ForEach(applicationStore.applications.prefix(5)) { application in
            NavigationLink(value: HomeRoute.interviewPrep(application.id)) {
              VStack(alignment: .leading, spacing: 3) {
                Text(application.role.nilIfBlank ?? "Untitled role").font(.headline)
                Text(application.company.nilIfBlank ?? "Company not set")
                  .font(.caption).foregroundStyle(Theme.mutedInk)
              }
            }
            .disabled(resumeCompletion(for: application) < 90)
          }
        }
        Divider()
        Text("Preparation and assessments use the résumé linked to each application and unlock at 90% completion.")
          .font(.caption).foregroundStyle(Theme.mutedInk)
      }

      Section("Upcoming") {
        if applicationStore.upcomingInterviews.isEmpty {
          Text("No upcoming interviews yet.").foregroundStyle(Theme.mutedInk)
        }
        ForEach(applicationStore.upcomingInterviews) { interview in
          NavigationLink(value: HomeRoute.interviewEditor(interviewID: interview.id, applicationID: interview.applicationID)) {
            InterviewEventRow(interview: interview, showsOutcome: false)
          }
        }
      }

      Section("Past interviews and results") {
        if applicationStore.pastInterviews.isEmpty {
          Text("Past interviews and your reflections will appear here.").foregroundStyle(Theme.mutedInk)
        }
        ForEach(applicationStore.pastInterviews) { interview in
          NavigationLink(value: HomeRoute.interviewEditor(interviewID: interview.id, applicationID: interview.applicationID)) {
            InterviewEventRow(interview: interview, showsOutcome: true)
          }
        }
      }
    }
    .navigationTitle("Prepare for Interview")
    .toolbar {
      NavigationLink(value: HomeRoute.interviewEditor(interviewID: nil, applicationID: nil)) {
        Label("Add interview", systemImage: "calendar.badge.plus")
      }
    }
  }

  private func resumeCompletion(for application: JobApplication) -> Int {
    let id = application.tailoredResumeID ?? application.baseResumeID
    return resumeStore.resumes.first(where: { $0.id == id })?.document.completionPercentage ?? 0
  }

  private func completion(forApplicationID id: UUID) -> Int {
    guard let application = applicationStore.applications.first(where: { $0.id == id }) else { return 0 }
    return resumeCompletion(for: application)
  }
}

private struct InterviewEventRow: View {
  let interview: InterviewEvent
  let showsOutcome: Bool
  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: interview.format.systemImage)
        .foregroundStyle(.tint).frame(width: 25)
      VStack(alignment: .leading, spacing: 3) {
        Text(interview.role.nilIfBlank ?? "Interview").font(.headline)
        Text([interview.company, interview.scheduledAt.formatted(date: .abbreviated, time: .shortened)]
          .filter { !$0.isBlank }.joined(separator: " · "))
          .font(.caption).foregroundStyle(Theme.mutedInk)
        if showsOutcome { Text(interview.outcome.title).font(.caption.weight(.semibold)) }
      }
    }.padding(.vertical, 3)
  }
}

struct InterviewEditorView: View {
  @EnvironmentObject private var store: ApplicationStore
  @Environment(\.dismiss) private var dismiss
  let interviewID: UUID?
  let applicationID: UUID?

  @State private var selectedApplicationID: UUID?
  @State private var role = ""
  @State private var company = ""
  @State private var scheduledAt = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
  @State private var durationMinutes = 60
  @State private var format: InterviewFormat = .video
  @State private var locationOrLink = ""
  @State private var interviewerNames = ""
  @State private var reminderEnabled = true
  @State private var preparationNotes = ""
  @State private var outcome: InterviewOutcome = .pending
  @State private var selfRating = 3
  @State private var whatWentWell = ""
  @State private var needsImprovement = ""
  @State private var followUpNotes = ""
  @State private var reminderError: String?
  @State private var isSaving = false
  @State private var addToCalendar = false

  var body: some View {
    Form {
      Section("Role") {
        if !store.applications.isEmpty {
          Picker("Application", selection: $selectedApplicationID) {
            Text("None").tag(Optional<UUID>.none)
            ForEach(store.applications) { application in
              Text([application.role, application.company].filter { !$0.isBlank }.joined(separator: " — "))
                .tag(Optional(application.id))
            }
          }.onChange(of: selectedApplicationID) { _, _ in fillFromApplication() }
        }
        TextField("Role", text: $role)
        TextField("Company", text: $company)
      }

      Section("Schedule") {
        DatePicker("Date and time", selection: $scheduledAt)
        Picker("Duration", selection: $durationMinutes) {
          ForEach([15, 30, 45, 60, 90, 120], id: \.self) { Text("\($0) minutes").tag($0) }
        }
        Picker("Format", selection: $format) {
          ForEach(InterviewFormat.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
        }
        TextField("Location or meeting link", text: $locationOrLink)
          .textInputAutocapitalization(.never)
        TextField("Interviewer names", text: $interviewerNames)
      }

      Section {
        Toggle("Remind me one day before", isOn: $reminderEnabled)
        Toggle("Add to Apple Calendar", isOn: $addToCalendar)
        Text("If the interview is booked less than a day ahead, the reminder is scheduled one hour before.")
          .font(.caption).foregroundStyle(Theme.mutedInk)
      } header: { Text("Reminder") }

      Section("Preparation notes") {
        TextEditor(text: $preparationNotes).frame(minHeight: 100)
      }

      if scheduledAt < Date() || outcome != .pending {
        Section("Result and reflection") {
          Picker("Outcome", selection: $outcome) {
            ForEach(InterviewOutcome.allCases) { Text($0.title).tag($0) }
          }
          Stepper("My performance: \(selfRating)/5", value: $selfRating, in: 1...5)
          LabeledContent("What went well") {
            TextField("Your strengths", text: $whatWentWell, axis: .vertical)
          }
          LabeledContent("Work on next") {
            TextField("Improvement areas", text: $needsImprovement, axis: .vertical)
          }
          LabeledContent("Follow-up") {
            TextField("Thank-you note, next steps…", text: $followUpNotes, axis: .vertical)
          }
        }
      }

      if let reminderError {
        Section { Label(reminderError, systemImage: "bell.slash.fill").foregroundStyle(.orange) }
      }

      if let interviewID {
        Section {
          Button("Delete interview", systemImage: "trash", role: .destructive) {
            store.deleteInterview(interviewID); dismiss()
          }
        }
      }
    }
    .supportsKeyboardDismissal()
    .navigationTitle(interviewID == nil ? "Add interview" : "Interview details")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
          .disabled(role.isBlank || isSaving)
      }
    }
    .onAppear { load() }
  }

  private func load() {
    selectedApplicationID = applicationID
    guard let interviewID, let interview = store.interviews.first(where: { $0.id == interviewID }) else {
      fillFromApplication(); return
    }
    selectedApplicationID = interview.applicationID
    role = interview.role; company = interview.company; scheduledAt = interview.scheduledAt
    durationMinutes = interview.durationMinutes; format = interview.format
    locationOrLink = interview.locationOrLink; interviewerNames = interview.interviewerNames
    reminderEnabled = interview.reminderEnabled; preparationNotes = interview.preparationNotes
    outcome = interview.outcome; selfRating = interview.selfRating
    whatWentWell = interview.whatWentWell; needsImprovement = interview.needsImprovement
    followUpNotes = interview.followUpNotes
  }

  private func fillFromApplication() {
    guard let selectedApplicationID,
      let application = store.applications.first(where: { $0.id == selectedApplicationID })
    else { return }
    role = application.role; company = application.company
  }

  @MainActor private func save() async {
    isSaving = true; reminderError = nil
    let existing = interviewID.flatMap { id in store.interviews.first { $0.id == id } }
    let interview = InterviewEvent(
      id: interviewID ?? UUID(), applicationID: selectedApplicationID, role: role, company: company,
      scheduledAt: scheduledAt, durationMinutes: durationMinutes, format: format,
      locationOrLink: locationOrLink, interviewerNames: interviewerNames,
      reminderEnabled: reminderEnabled, preparationNotes: preparationNotes, outcome: outcome,
      selfRating: selfRating, whatWentWell: whatWentWell, needsImprovement: needsImprovement,
      followUpNotes: followUpNotes, createdAt: existing?.createdAt ?? Date(), updatedAt: Date()
    )
    if existing == nil { store.addInterview(interview) } else { store.updateInterview(interview) }
    if var application = selectedApplicationID.flatMap({ id in store.applications.first { $0.id == id } }) {
      application.status = .interview; store.update(application)
    }
    do {
      if reminderEnabled { try await InterviewReminderService.schedule(for: interview) }
      else { InterviewReminderService.cancel(interviewID: interview.id) }
      if addToCalendar { try await CareerCalendarService.addInterview(interview) }
      dismiss()
    } catch {
      reminderError = error.localizedDescription
    }
    isSaving = false
  }
}

struct InterviewPrepView: View {
  @EnvironmentObject private var resumeStore: ResumeStore
  @EnvironmentObject private var applicationStore: ApplicationStore
  let applicationID: UUID?

  @State private var role = ""
  @State private var company = ""
  @State private var jobDescription = ""
  @State private var plan: AIInterviewPlan?
  @State private var assessment: AIInterviewAssessment?
  @State private var isLoadingPlan = false
  @State private var isLoadingAssessment = false
  @State private var showAssessment = false
  @State private var errorMessage: String?

  private var isUnlocked: Bool { sourceDocument.completionPercentage >= 90 }

  var body: some View {
    List {
      if !isUnlocked {
        Section {
          Label("AI interview tools unlock when this résumé reaches 90% completion.", systemImage: "lock.fill")
          ProgressView(value: Double(sourceDocument.completionPercentage), total: 100)
          Text("Currently \(sourceDocument.completionPercentage)% complete")
            .font(.caption).foregroundStyle(Theme.mutedInk)
          NavigationLink(value: HomeRoute.editor(sourceDocument.incompleteSections.first)) {
            Label("Complete résumé", systemImage: "arrow.right.circle.fill")
          }
        }
      }

      Section("Target interview") {
        TextField("Role", text: $role)
        TextField("Company", text: $company)
        JobSpecImportButton(jobDescription: $jobDescription, errorMessage: $errorMessage)
        TextEditor(text: $jobDescription).frame(minHeight: 100)
          .accessibilityLabel("Job description")
        Text("Upload or paste the advert. Explicit responsibilities and requirements shape the likely questions, while answers stay grounded in your résumé.")
          .font(.caption).foregroundStyle(Theme.mutedInk)
      }

      Section("AI preparation") {
        Button("Build personalised interview plan", systemImage: "sparkles") {
          Task { await generatePlan() }
        }.disabled(!isUnlocked || role.isBlank || isLoadingPlan || isLoadingAssessment)

        Button(assessment == nil ? "Create résumé-based assessment" : "Regenerate assessment", systemImage: "checkmark.rectangle.stack.fill") {
          Task { await generateAssessment() }
        }.disabled(!isUnlocked || role.isBlank || isLoadingPlan || isLoadingAssessment)

        if isLoadingPlan { ProgressView("Preparing questions and evidence…") }
        if isLoadingAssessment { ProgressView("Creating your assessment…") }
      }

      if let assessment {
        Section {
          Text(assessment.title).font(.headline)
          Text(assessment.focusAreas.joined(separator: " • "))
            .font(.caption).foregroundStyle(Theme.mutedInk)
          if let latest = application?.assessmentAttempts?.last {
            Label("Latest score: \(latest.score)/\(latest.total) (\(latest.evaluation?.percentage ?? percentage(score: latest.score, total: latest.total))%)", systemImage: "chart.bar.fill")
            if let gaps = latest.evaluation?.knowledgeGaps, !gaps.isEmpty {
              Text("Focus next: \(gaps.prefix(2).joined(separator: " • "))")
                .font(.caption).foregroundStyle(.orange)
            }
          }
          Button("Start 8-question assessment", systemImage: "play.circle.fill") { showAssessment = true }
            .fontWeight(.semibold)
        } header: { Text("Practice assessment") }
      }

      if let attempts = application?.assessmentAttempts, !attempts.isEmpty {
        Section("Assessment history") {
          ForEach(attempts.reversed()) { attempt in
            VStack(alignment: .leading, spacing: 4) {
              HStack {
                Text("\(attempt.score)/\(attempt.total)").font(.headline).monospacedDigit()
                Spacer()
                Text(attempt.completedAt, style: .date).font(.caption).foregroundStyle(Theme.mutedInk)
              }
              if let evaluation = attempt.evaluation {
                Text("\(evaluation.percentage)% · Focus: \(evaluation.knowledgeGaps.prefix(2).joined(separator: ", "))")
                  .font(.caption).foregroundStyle(Theme.mutedInk)
              }
            }.padding(.vertical, 3)
          }
        }
      }

      Section {
        Label("Situation — set the relevant context", systemImage: "1.circle.fill")
        Label("Task — explain your responsibility", systemImage: "2.circle.fill")
        Label("Action — focus on what you personally did", systemImage: "3.circle.fill")
        Label("Result — close with a truthful outcome or learning", systemImage: "4.circle.fill")
      } header: { Text("Use STAR for evidence") }

      if let errorMessage {
        Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
      }

      if let plan {
        Section("Your opening pitch") { Text(plan.openingPitch) }
        Section("Likely questions") {
          ForEach(plan.questions) { item in
            DisclosureGroup {
              VStack(alignment: .leading, spacing: 9) {
                Label(item.rationale, systemImage: "questionmark.circle")
                Label(item.evidenceHint, systemImage: "doc.text.magnifyingglass")
                  .foregroundStyle(Theme.mutedInk)
              }.font(.footnote).padding(.vertical, 6)
            } label: { Text(item.question).fontWeight(.semibold) }
          }
        }
        Section("Questions you can ask") {
          ForEach(plan.questionsToAsk, id: \.self) { Label($0, systemImage: "bubble.left.and.bubble.right") }
        }
        Section("Preparation checklist") {
          ForEach(plan.preparationTips, id: \.self) { Label($0, systemImage: "checkmark.circle") }
        }
        if !plan.claimsRequiringConfirmation.isEmpty {
          Section("Verify before using") {
            ForEach(plan.claimsRequiringConfirmation, id: \.self) {
              Label($0, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
          }
        }
      }

      Section("Interview-day essentials") {
        Label("Research the company and interviewer", systemImage: "building.2")
        Label("Test the meeting link, camera and audio", systemImage: "video")
        Label("Keep your résumé and job advert nearby", systemImage: "doc.on.doc")
        Label("Prepare two thoughtful questions", systemImage: "bubble.left.and.questionmark.bubble.right")
        Label("Send a concise thank-you follow-up", systemImage: "envelope")
      }
    }
    .supportsKeyboardDismissal()
    .navigationTitle("Prepare for Interview")
    .onAppear { loadApplication() }
    .onDisappear { persistTargetDetails() }
    .sheet(isPresented: $showAssessment) {
      if let assessment {
        InterviewAssessmentView(assessment: assessment) { answers in
          let evaluation = try await ResumeAIService.shared.gradeInterviewAssessment(
            document: sourceDocument, assessment: assessment, selectedAnswers: answers)
          recordAttempt(evaluation: evaluation)
          return evaluation
        }
      }
    }
  }

  private var sourceDocument: ResumeDocument {
    guard let application else { return resumeStore.document }
    let id = application.tailoredResumeID ?? application.baseResumeID
    return resumeStore.resumes.first(where: { $0.id == id })?.document ?? resumeStore.document
  }

  private var application: JobApplication? {
    guard let applicationID else { return nil }
    return applicationStore.applications.first { $0.id == applicationID }
  }

  private func loadApplication() {
    guard let application else { return }
    role = application.role; company = application.company; jobDescription = application.jobDescription
    plan = application.interviewPlan; assessment = application.interviewAssessment
  }

  @MainActor private func generatePlan() async {
    isLoadingPlan = true; errorMessage = nil; AppKeyboard.dismiss()
    do {
      let result = try await ResumeAIService.shared.prepareInterview(
        document: sourceDocument, jobDescription: jobDescription, role: role, company: company)
      plan = result
      if var application {
        application.role = role; application.company = company
        application.jobDescription = jobDescription
        application.interviewPlan = result; application.status = .interview
        applicationStore.update(application)
      }
    } catch { errorMessage = error.localizedDescription }
    isLoadingPlan = false
  }

  @MainActor private func generateAssessment() async {
    isLoadingAssessment = true; errorMessage = nil; AppKeyboard.dismiss()
    do {
      let result = try await ResumeAIService.shared.createInterviewAssessment(
        document: sourceDocument, jobDescription: jobDescription, role: role, company: company)
      assessment = result
      if var application {
        application.role = role; application.company = company
        application.jobDescription = jobDescription
        application.interviewAssessment = result
        applicationStore.update(application)
      }
    } catch { errorMessage = error.localizedDescription }
    isLoadingAssessment = false
  }

  private func recordAttempt(evaluation: AIAssessmentEvaluation) {
    guard var application, let assessment else { return }
    var attempts = application.assessmentAttempts ?? []
    attempts.append(InterviewAssessmentAttempt(
      assessmentTitle: assessment.title,
      score: evaluation.score,
      total: evaluation.total,
      evaluation: evaluation
    ))
    application.assessmentAttempts = attempts
    applicationStore.update(application)
  }

  private func persistTargetDetails() {
    guard var application else { return }
    application.role = role
    application.company = company
    application.jobDescription = jobDescription
    applicationStore.update(application)
  }

  private func percentage(score: Int, total: Int) -> Int {
    guard total > 0 else { return 0 }
    return Int((Double(score) / Double(total) * 100).rounded())
  }
}

private struct InterviewAssessmentView: View {
  let assessment: AIInterviewAssessment
  let onGrade: ([String: Int]) async throws -> AIAssessmentEvaluation
  @Environment(\.dismiss) private var dismiss
  @State private var currentIndex = 0
  @State private var answers: [String: Int] = [:]
  @State private var showingResults = false
  @State private var isGrading = false
  @State private var evaluation: AIAssessmentEvaluation?
  @State private var gradingError: String?

  var body: some View {
    NavigationStack {
      Group {
        if showingResults { results }
        else { question }
      }
      .navigationTitle(showingResults ? "Assessment result" : "Question \(currentIndex + 1) of \(assessment.questions.count)")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
      }
    }
  }

  private var question: some View {
    let item = assessment.questions[currentIndex]
    return VStack(alignment: .leading, spacing: 20) {
      ProgressView(value: Double(currentIndex + 1), total: Double(assessment.questions.count))
      Text(item.category.uppercased()).eyebrow().foregroundStyle(.tint)
      Text(item.prompt).font(.title3.weight(.bold)).fixedSize(horizontal: false, vertical: true)
      ForEach(Array(item.options.enumerated()), id: \.offset) { index, option in
        Button {
          answers[item.id] = index
        } label: {
          HStack(alignment: .top, spacing: 12) {
            Image(systemName: answers[item.id] == index ? "checkmark.circle.fill" : "circle")
            Text(option).frame(maxWidth: .infinity, alignment: .leading)
          }
          .padding(14)
          .background(answers[item.id] == index ? Color.accentColor.opacity(0.12) : Theme.muted, in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
      }
      Spacer()
      Button(currentIndex == assessment.questions.count - 1 ? "Finish assessment" : "Next question") {
        if currentIndex == assessment.questions.count - 1 {
          Task { await grade() }
        } else { currentIndex += 1 }
      }
      .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
      .disabled(answers[item.id] == nil || isGrading)
      if isGrading { ProgressView("AI is marking your answers…") }
      if let gradingError {
        Label(gradingError, systemImage: "exclamationmark.triangle.fill")
          .font(.footnote).foregroundStyle(.red)
      }
    }.padding()
  }

  private var results: some View {
    List {
      if let evaluation {
        Section {
        VStack(spacing: 8) {
          Text("\(evaluation.score)/\(evaluation.total)").font(.system(size: 44, weight: .bold))
          Text("\(evaluation.percentage)% · \(evaluation.percentage >= 75 ? "Strong preparation" : "More practice recommended")")
            .foregroundStyle(Theme.mutedInk)
        }.frame(maxWidth: .infinity).padding(.vertical)
        Text(evaluation.overallFeedback)
      }
        if !evaluation.strengths.isEmpty {
          Section("Strengths") {
            ForEach(evaluation.strengths, id: \.self) { Label($0, systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
          }
        }
        if !evaluation.knowledgeGaps.isEmpty {
          Section("Where to improve") {
            ForEach(evaluation.knowledgeGaps, id: \.self) { Label($0, systemImage: "scope").foregroundStyle(.orange) }
          }
        }
        Section("Your focus plan") {
          ForEach(Array(evaluation.focusPlan.enumerated()), id: \.offset) { index, step in
            Label(step, systemImage: "\(index + 1).circle.fill")
          }
        }
        Section("Answer review") {
          ForEach(assessment.questions) { item in
            let feedback = evaluation.questionFeedback.first { $0.id == item.id }
            DisclosureGroup {
              VStack(alignment: .leading, spacing: 8) {
                Text(feedback?.feedback ?? item.explanation)
                Text(item.explanation)
                Label(item.resumeConnection, systemImage: "doc.text.magnifyingglass")
                  .foregroundStyle(Theme.mutedInk)
              }.font(.footnote).padding(.vertical, 5)
            } label: {
              Label(item.prompt, systemImage: feedback?.isCorrect == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(feedback?.isCorrect == true ? .green : .red)
            }
          }
        }
        Button("Done") { dismiss() }.frame(maxWidth: .infinity)
      }
    }
  }

  @MainActor private func grade() async {
    isGrading = true; gradingError = nil
    do {
      evaluation = try await onGrade(answers)
      showingResults = true
    } catch { gradingError = error.localizedDescription }
    isGrading = false
  }
}
