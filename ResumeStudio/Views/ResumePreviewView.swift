import PDFKit
import SwiftUI
import UIKit

struct ResumePreviewView: View {
  private let sourceDocument: ResumeDocument
  @EnvironmentObject private var store: ResumeStore
  @EnvironmentObject private var purchases: PurchaseManager
  @State private var document: ResumeDocument

  @State private var pdfData: Data?
  @State private var renderError: String?
  @State private var isRendering = false
  @State private var isExporting = false
  @State private var isExportingDOCX = false
  @State private var docxData: Data?
  @State private var showCopied = false
  @State private var shareItem: ShareItem?
  @State private var atsSafe = false
  @State private var showRecruiterScan = false
  @State private var showCreateLink = false
  @State private var showSignature = false
  @State private var showAttachments = false
  @State private var showStyleMenu = false
  @State private var pendingPlanRequest = false
  @State private var quickEditTarget: ResumeQuickEditTarget?
  @State private var showQuickEditHint = false
  /// Whether this preview is showing the store's active résumé and may write back
  /// to it. Resolved once on appear: the split-window preview reads its own store
  /// while inheriting the app's from the environment, and must not persist here.
  @State private var canPersist = false
  /// Whether the arrows walk the whole catalogue or only the unlocked designs.
  /// Stored, because it is a browsing habit rather than a per-résumé setting.
  /// Starts on the designs that can actually be kept; "All" is there for anyone
  /// who wants to see what the rest of the catalogue looks like on their own CV.
  @AppStorage("previewBrowsesAllTemplates") private var browseAllTemplates = false

  init(document: ResumeDocument) {
    sourceDocument = document
    _document = State(initialValue: document)
  }

  /// What actually gets rendered and exported: the chosen design, or an
  /// ATS-safe transform of it when the toggle is on.
  private var renderDocument: ResumeDocument {
    atsSafe ? Self.atsSafeVariant(of: document) : document
  }

  private var exportFilename: String {
    atsSafe ? "\(document.suggestedFilename)-ATS" : document.suggestedFilename
  }

  /// A re-render keeps the previous page on screen, so `pdfData` alone no longer
  /// means the bytes match what is selected. Exporting mid-step would hand over
  /// the design the user just moved off.
  private var exportsUnavailable: Bool {
    pdfData == nil || isRendering
  }

  /// A guaranteed applicant-tracking-friendly version of the résumé: a single
  /// column with standard section headings and no photo, which the parsers most
  /// reliably read in the right order. Only the layout changes — every word of
  /// the résumé is the user's own.
  ///
  /// Attachments come off too: a parser reading a scanned certificate finds
  /// either nothing or a page of stray words, which is exactly what this variant
  /// exists to avoid.
  private static func atsSafeVariant(of document: ResumeDocument) -> ResumeDocument {
    var doc = document
    doc.template = .classic
    doc.photo = nil
    doc.photoCrop = nil
    doc.attachments = []
    return doc
  }

  var body: some View {
    Group {
      if let pdfData {
        PDFKitView(
          data: pdfData, onDoubleTap: openQuickEdit, highlight: document.accent.color)
          .background(Theme.muted)
          // Stepping through templates re-renders on every tap. The previous
          // page stays up underneath so the preview never blinks back to an
          // empty screen mid-browse; this is the only sign anything is busy.
          .overlay(alignment: .topTrailing) {
            if isRendering {
              ProgressView()
                .padding(11)
                .background(.regularMaterial, in: Circle())
                .padding(14)
            }
          }
          .animation(.easeInOut(duration: 0.2), value: isRendering)
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
            : "\(document.template.title) · \(String(localized: document.accent.title))")
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
        .disabled(exportsUnavailable)

        // Template and colour, tried on against the real page — a brush rather
        // than a pencil, because the words are edited by double-tapping the page
        // itself and this button only ever changes how they look.
        Button {
          showStyleMenu = true
        } label: {
          Image(systemName: "paintbrush.pointed")
        }
        .accessibilityLabel("Template and colour")
        .popover(isPresented: $showStyleMenu) {
          styleMenu
        }

        // Sharing and saving are one intent — handing the PDF to something else
        // — so they share a button instead of sitting side by side as two
        // near-identical arrows.
        Menu {
          Button("Share PDF", systemImage: "square.and.arrow.up") { prepareShare() }
          Section {
            Button("Save PDF", systemImage: "doc.richtext") { isExporting = true }
            Button("Save editable DOCX", systemImage: "doc.text") { prepareDOCXExport() }
          }
        } label: {
          Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel("Share and save")
        .disabled(exportsUnavailable)

        // The overflow of page actions — kept out of the preview so the résumé
        // itself gets the full screen.
        Menu {
          Toggle(isOn: $atsSafe.animation(.easeInOut(duration: 0.2))) {
            Label("ATS-safe layout", systemImage: "checkmark.shield")
          }
          Section {
            Button {
              showSignature = true
            } label: {
              Label(
                signatureActionTitle,
                systemImage: "signature"
              )
            }
            .disabled(exportsUnavailable)

            Button {
              showAttachments = true
            } label: {
              Label(attachmentActionTitle, systemImage: "paperclip.badge.plus")
            }
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
        toast("Résumé text copied", systemImage: "checkmark.circle.fill")
      } else if showQuickEditHint {
        toast("Double-tap a name, skill or role to edit it", systemImage: "hand.tap.fill")
      }
    }
    .task(id: renderDocument) {
      await renderPreview()
    }
    // The tap itself is the only confirmation there is until the sheet finishes
    // rising, which is what made a hit feel indistinguishable from a miss.
    .sensoryFeedback(.impact(weight: .light), trigger: quickEditTarget) { _, new in
      new != nil
    }
    .sensoryFeedback(.warning, trigger: showQuickEditHint) { _, showing in showing }
    .onAppear { canPersist = store.document == sourceDocument }
    .onChange(of: sourceDocument) { _, updated in
      var next = updated
      // A design being previewed but not owned is not in the résumé, so an
      // external content change would otherwise snap the preview off it.
      if !purchases.canUse(document.template) { next.template = document.template }
      document = next
    }
    .sheet(item: $quickEditTarget) { target in
      ResumeQuickEditSheet(
        document: document,
        target: target,
        accent: document.accent.color,
        onSave: applyContentEdit
      )
      .presentationDetents(
        target.preferredHeight.map { [.height($0), .large] } ?? [.medium, .large])
      .presentationDragIndicator(.visible)
      .presentationCornerRadius(30)
      .presentationBackground(Theme.paper)
    }
    .sheet(isPresented: $showSignature) {
      NavigationStack {
        ResumeSignatureView(
          signature: signatureBinding,
          pdfData: pdfData,
          resumePageCount: resumePageCount,
          accent: document.accent.color
        )
      }
      .presentationDragIndicator(.visible)
      .presentationCornerRadius(30)
      .presentationBackground(Theme.paper)
    }
    .sheet(isPresented: $showAttachments) {
      NavigationStack {
        ResumeAttachmentsView(document: editableDocumentBinding)
      }
      .presentationDragIndicator(.visible)
      .presentationCornerRadius(30)
      .presentationBackground(Theme.paper)
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
          document: document, pdfData: pdfData, showsDone: true,
          fixRouting: .dismissToHome,
          onDocumentUpdated: { document = $0 })
      }
    }
    .sheet(isPresented: $showCreateLink) {
      NavigationStack { CreateSmartLinkSheet() }
    }
  }

  private func toast(_ message: LocalizedStringKey, systemImage: String) -> some View {
    Label(message, systemImage: systemImage)
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(.white)
      .padding(.horizontal, 18)
      .padding(.vertical, 11)
      .background(.black.opacity(0.82), in: Capsule())
      .padding(.horizontal, 24)
      .padding(.bottom, 30)
      .transition(.move(edge: .bottom).combined(with: .opacity))
  }

  private var resumePageCount: Int {
    guard let pdfData, let pdf = PDFDocument(data: pdfData) else { return 1 }
    return max(1, pdf.pageCount - renderDocument.attachmentPageCount)
  }

  private var attachmentActionTitle: String {
    let count = document.attachments.count
    guard count > 0 else { return String(localized: "Add attachments") }
    return String(localized: "Attachments (\(count))")
  }

  private var signatureActionTitle: String {
    document.signature == nil
      ? String(localized: "Sign document")
      : String(localized: "Edit signature")
  }

  /// Both document tools are content edits, not design purchases. They therefore
  /// persist even while the user is comparing a locked template; only that
  /// unowned template is omitted from the saved version by `applyContentEdit`.
  private var editableDocumentBinding: Binding<ResumeDocument> {
    Binding(
      get: { document },
      set: { applyContentEdit($0) }
    )
  }

  private var signatureBinding: Binding<ResumeSignature?> {
    Binding(
      get: { document.signature },
      set: { newValue in
        var updated = document
        updated.signature = newValue
        applyContentEdit(updated)
      }
    )
  }

  // MARK: - Style menu

  /// Template and accent, changed against the real page. It is a popover rather
  /// than a `Menu` for two reasons — a menu closes on every tap, and it cannot
  /// hold the swatch scroller. Trying designs on is the point, so the panel
  /// stays put until you tap away from it.
  private var styleMenu: some View {
    VStack(alignment: .leading, spacing: 0) {
      templateStepper
      Divider()
      accentSwatches
      if !purchases.unlocksAllTemplates {
        Divider()
        upgradeCallout
      }
      Spacer(minLength: 0)
    }
    // An explicit size, because a popover sizes its container from an ideal
    // pass that the swatch scroller throws off — leaving the panel drawn well
    // above the rows UIKit is actually hit-testing. Both agree on a fixed frame.
    .frame(width: 300, height: purchases.unlocksAllTemplates ? 232 : 292, alignment: .top)
    .dynamicTypeSize(...DynamicTypeSize.xLarge)
    .presentationCompactAdaptation(.popover)
    .sensoryFeedback(.selection, trigger: document.template)
    .sensoryFeedback(.selection, trigger: document.accent)
    .onDisappear { presentPlansIfRequested() }
  }

  /// Walks the catalogue one design at a time, so a template can be judged
  /// against the actual résumé instead of a thumbnail.
  private var templateStepper: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text("Template")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      HStack(spacing: 10) {
        stepButton(offset: -1, systemImage: "chevron.left", label: "Previous template")
        VStack(spacing: 2) {
          HStack(spacing: 5) {
            if !purchases.canUse(document.template) {
              Image(systemName: "lock.fill").font(.caption2)
            }
            Text(document.template.title)
              .font(.subheadline.weight(.semibold))
              .lineLimit(1)
              .minimumScaleFactor(0.75)
          }
          Group {
            if atsSafe {
              Text("ATS-safe layout is on")
            } else if let position = templatePosition {
              // A locked design still renders — seeing it is the point of
              // walking the whole catalogue — but it is never written back to
              // the résumé, so say so rather than let it look applied.
              Text(purchases.canUse(document.template)
                ? "\(position.index) of \(position.total)"
                : "\(position.index) of \(position.total) · preview only")
            }
          }
          .font(.caption2)
          .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        stepButton(offset: 1, systemImage: "chevron.right", label: "Next template")
      }
      Picker("Browse", selection: $browseAllTemplates) {
        Text("All").tag(true)
        Text("Unlocked").tag(false)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    // ATS-safe layout renders as Classic whatever is selected, so stepping
    // would move a number nothing on screen responds to.
    .opacity(atsSafe ? 0.4 : 1)
    .allowsHitTesting(!atsSafe)
  }

  private func stepButton(
    offset: Int, systemImage: String, label: LocalizedStringKey
  ) -> some View {
    Button {
      stepTemplate(by: offset)
    } label: {
      Image(systemName: systemImage)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(Color.primary)
        .frame(width: 38, height: 38)
        .background(Color.primary.opacity(0.06), in: Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
  }

  /// Every accent in one horizontal run. Locked tones stay visible with their
  /// real colour, the same way the appearance editor shows them.
  private var accentSwatches: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text("Accent colour")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
      ScrollView(.horizontal, showsIndicators: false) {
        // A plain HStack leaves the scroller's cross-axis size up to the
        // popover's ideal-height pass, which lands the row outside the slot it
        // was given. A fixed grid row states that height outright.
        LazyHGrid(rows: [GridItem(.fixed(30))], spacing: 13) {
          ForEach(ResumeAccent.allCases) { option in
            accentSwatch(option)
          }
        }
        .padding(.horizontal, 16)
        // Room for the selection ring, which sits outside the swatch.
        .padding(.vertical, 6)
      }
      .frame(height: 42)
      .contentMargins(.vertical, 0, for: .scrollContent)
    }
    .padding(.vertical, 12)
  }

  private func accentSwatch(_ option: ResumeAccent) -> some View {
    let unlocked = purchases.canUse(option)
    let isSelected = document.accent == option
    return Button {
      guard unlocked else {
        pendingPlanRequest = true
        showStyleMenu = false
        return
      }
      apply { $0.accent = option }
    } label: {
      Circle()
        .fill(option.color)
        .frame(width: 30, height: 30)
        .overlay { Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1) }
        .overlay {
          if !unlocked {
            Image(systemName: "lock.fill")
              .font(.system(size: 11, weight: .bold))
              .foregroundStyle(.white)
              .shadow(color: .black.opacity(0.35), radius: 1)
          }
        }
        .overlay {
          if isSelected {
            Circle()
              .strokeBorder(Color.primary.opacity(0.8), lineWidth: 2)
              .padding(-4)
          }
        }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      "\(String(localized: option.title)) accent colour\(option.isPremium ? ", premium" : "")")
    .accessibilityHint(unlocked ? "" : "Available with Go, Pro, or the Design Pack")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  /// The catalogue sells itself best right after someone has stepped through it
  /// on their own résumé, so the offer sits at the end of the panel rather than
  /// only in Settings. It disappears once there is nothing left to unlock.
  private var upgradeCallout: some View {
    Button {
      pendingPlanRequest = true
      showStyleMenu = false
    } label: {
      HStack(spacing: 11) {
        Image(systemName: "crown.fill")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(
            LinearGradient(
              colors: [
                Color(red: 1.0, green: 0.87, blue: 0.45),
                Color(red: 0.85, green: 0.62, blue: 0.13),
              ],
              startPoint: .top,
              endPoint: .bottom
            )
          )
        VStack(alignment: .leading, spacing: 1) {
          Text("Unlock all \(ResumeTemplate.allCases.count) templates")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.primary)
          Text("Every design and accent colour")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 4)
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityHint("Opens plans")
  }

  // MARK: - Style changes

  /// What the arrows walk: the whole catalogue by default, or just the designs
  /// this plan can apply, for someone who would rather not step through
  /// anything they cannot keep.
  private var availableTemplates: [ResumeTemplate] {
    browseAllTemplates
      ? ResumeTemplate.allCases
      : ResumeTemplate.allCases.filter { purchases.canUse($0) }
  }

  private var templatePosition: (index: Int, total: Int)? {
    let options = availableTemplates
    guard let index = options.firstIndex(of: document.template) else { return nil }
    return (index + 1, options.count)
  }

  /// Moves `offset` designs along the available list, wrapping at either end so
  /// the arrows never dead-end partway through the catalogue.
  private func stepTemplate(by offset: Int) {
    let options = availableTemplates
    guard !options.isEmpty else { return }
    guard let current = options.firstIndex(of: document.template) else {
      // The résumé is on a design this plan no longer unlocks — a lapsed
      // subscription. Enter the list from whichever end the arrow points at.
      apply { $0.template = offset > 0 ? options[0] : options[options.count - 1] }
      return
    }
    let next = (current + offset % options.count + options.count) % options.count
    apply { $0.template = options[next] }
  }

  /// Applies a design change to the preview, and to the résumé itself when this
  /// preview is showing the store's active document — a template you settled on
  /// here should still be there after you leave.
  ///
  /// The split-window preview reads from its own store while inheriting the main
  /// one from the environment, so the equality check stops a change made there
  /// from landing on whichever résumé the main window happens to have open.
  private func apply(_ change: (inout ResumeDocument) -> Void) {
    var updated = document
    change(&updated)
    guard updated != document else { return }
    document = updated
    // Browsing the full catalogue lands on designs this plan does not include.
    // They render, so they can be judged, but a template the user cannot export
    // never gets written into their résumé.
    guard canPersist, purchases.canUse(updated.template) else { return }
    store.document = updated
  }

  // MARK: - Quick edit

  /// Turns a double tap on the page into the field it landed on.
  private func openQuickEdit(
    line: String, preceding: String, following: String, relativeY: CGFloat, pageIndex: Int
  ) {
    let target = ResumeQuickEditLocator.target(
      forLine: line, preceding: preceding, following: following, relativeY: relativeY,
      pageIndex: pageIndex, in: document)
    // The ATS-safe variant drops the portrait, so there is nothing to tap for.
    guard let target, !(atsSafe && target == .photo) else {
      // A gesture that does nothing reads as broken, so say what it is for.
      withAnimation { showQuickEditHint = true }
      Task {
        try? await Task.sleep(nanoseconds: 2_200_000_000)
        withAnimation { showQuickEditHint = false }
      }
      return
    }
    quickEditTarget = target
  }

  /// Content edits are the user's own words, so they always belong to the résumé
  /// — including while a design they cannot export is on screen for comparison,
  /// in which case only that design is left behind.
  private func applyContentEdit(_ edited: ResumeDocument) {
    guard edited != document else { return }
    document = edited
    guard canPersist else { return }
    var persisted = edited
    if !purchases.canUse(persisted.template) { persisted.template = store.document.template }
    store.document = persisted
  }

  /// The plan picker is a sheet, so it has to wait for the popover to actually
  /// be gone — nothing presents on top of a live popover.
  private func presentPlansIfRequested() {
    guard pendingPlanRequest else { return }
    pendingPlanRequest = false
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(150))
      purchases.requestPlans()
    }
  }

  @MainActor
  private func renderPreview() async {
    renderError = nil
    isRendering = true
    defer { isRendering = false }
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
      ProductInsights.record(.documentExported, once: true)
    } catch {
      renderError = error.localizedDescription
    }
  }

  private func prepareDOCXExport() {
    do {
      docxData = try ResumeDOCXRenderer.render(document: renderDocument)
      isExportingDOCX = true
      ProductInsights.record(.documentExported, once: true)
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
    ProductInsights.record(.documentExported, once: true)
    controller.present(animated: true, completionHandler: nil)
  }

  /// Copies the résumé's text to the clipboard, for pasting straight into an
  /// online application's form fields. Attachment pages are left out — nobody
  /// pasting into a form wants a certificate's wording in the middle of it.
  private func copyResumeText() {
    guard let pdfData, let pdf = PDFDocument(data: pdfData) else { return }
    let lastResumePage = max(0, pdf.pageCount - renderDocument.attachmentPageCount)
    let text = (0..<lastResumePage)
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
  .environmentObject(ResumeStore(initialDocument: .example))
  .environmentObject(CareerIntelligenceStore())
  .environmentObject(PurchaseManager.shared)
}
