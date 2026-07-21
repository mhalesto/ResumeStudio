import PDFKit
import SwiftUI
import UIKit

/// The recruiter's first look, replayed on the user's own résumé: a 7.4-second
/// gaze spotlight tracing the eye-tracking F-pattern over page one, then a
/// report of what a recruiter left the scan holding — and what they looked for
/// and never found. The ATS checker is the machine's pass; this is the human's.
struct RecruiterScanView: View {
  /// How a "Fix in <section>" row reaches the editor. Pushed from the career
  /// workspace, the enclosing stack resolves `HomeRoute` itself; presented as
  /// a sheet over the preview, the sheet has to fold away first and hand the
  /// destination to the home stack.
  enum SectionFixRouting {
    case push
    case dismissToHome
  }

  @State private var document: ResumeDocument
  let pdfData: Data?
  /// Presented as a sheet from the preview; pushed from the career workspace.
  let showsDone: Bool
  let fixRouting: SectionFixRouting
  let onDocumentUpdated: ((ResumeDocument) -> Void)?

  private enum Phase { case intro, scanning, report }
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var resumeStore: ResumeStore
  @EnvironmentObject private var careerStore: CareerIntelligenceStore
  @State private var phase = Phase.intro
  @State private var pageImage: UIImage?
  @State private var renderError: String?
  @State private var scanStart: Date?
  @State private var scanTask: Task<Void, Never>?
  @State private var showsRepairReview = false
  @State private var repairSummary: String?
  @State private var documentBeforeRepair: ResumeDocument?
  @State private var repairRevisionIDs: [UUID] = []
  @State private var didModifyDocument = false
  /// Remembered across résumés and sessions: how demanding the reader is.
  @AppStorage("recruiterScanStrictness") private var strictnessRaw =
    RecruiterScanStrictness.medium.rawValue

  init(
    document: ResumeDocument,
    pdfData: Data? = nil,
    showsDone: Bool = false,
    fixRouting: SectionFixRouting = .push,
    onDocumentUpdated: ((ResumeDocument) -> Void)? = nil
  ) {
    _document = State(initialValue: document)
    self.pdfData = pdfData
    self.showsDone = showsDone
    self.fixRouting = fixRouting
    self.onDocumentUpdated = onDocumentUpdated
  }

  private var strictness: RecruiterScanStrictness {
    RecruiterScanStrictness(rawValue: strictnessRaw) ?? .medium
  }

  private var accent: Color { document.accent.color }
  private var report: RecruiterScanReport {
    RecruiterScanService.analyze(document: document, strictness: strictness)
  }
  private var schedule: GazeSchedule { GazeSchedule(stops: RecruiterScanService.gazePath(for: document)) }

  var body: some View {
    Group {
      switch phase {
      case .intro: intro
      case .scanning: scanStage
      case .report: reportView
      }
    }
    .background(Theme.paper.ignoresSafeArea())
    .navigationTitle("Recruiter scan")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if showsDone {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
    }
    .task { await preparePage() }
    .onDisappear { scanTask?.cancel() }
    .sheet(isPresented: $showsRepairReview) {
      RecruiterScanRepairView(document: document, strictness: strictness) { updated, revisionIDs in
        applyRepair(updated, revisionIDs: revisionIDs)
      }
    }
  }

  // MARK: - Intro

  private var intro: some View {
    ScrollView {
      VStack(spacing: 22) {
        VStack(spacing: 6) {
          Text("The first look")
            .eyebrow()
            .foregroundStyle(Theme.mutedInk)
          Text("7.4 seconds")
            .displayFont(58)
            .foregroundStyle(Theme.ink)
          Text("That is how long a recruiter's first pass over a résumé lasts, measured with eye-tracking. Almost all of it lands on six data points.")
            .font(.subheadline)
            .foregroundStyle(Theme.inkSoft)
            .multilineTextAlignment(.center)
        }
        .padding(.top, 26)
        .padding(.horizontal, 24)

        VStack(alignment: .leading, spacing: 10) {
          fixationRow("1", "Your name")
          fixationRow("2", "Current title and company")
          fixationRow("3", "Previous title and company")
          fixationRow("4", "Dates on the current role")
          fixationRow("5", "Dates on the previous role")
          fixationRow("6", "Education")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .padding(.horizontal, 20)

        VStack(alignment: .leading, spacing: 9) {
          Text("How demanding is the reader?")
            .eyebrow()
            .foregroundStyle(Theme.mutedInk)
          Picker("Strictness", selection: $strictnessRaw) {
            ForEach(RecruiterScanStrictness.allCases) { level in
              Text(level.title).tag(level.rawValue)
            }
          }
          .pickerStyle(.segmented)
          Text(strictness.detail)
            .font(.caption)
            .foregroundStyle(Theme.mutedInk)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: Theme.tileRadius)
        .padding(.horizontal, 20)

        Button {
          startScan()
        } label: {
          Label("Watch the scan on your résumé", systemImage: "eye")
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(accent)
        .disabled(pageImage == nil)
        .padding(.horizontal, 20)

        if let renderError {
          Text(renderError)
            .font(.caption)
            .foregroundStyle(.orange)
            .padding(.horizontal, 24)
        }

        Text("A simulation built from published eye-tracking research. It runs entirely on this device — no credits, no upload, works offline.")
          .font(.caption2)
          .foregroundStyle(Theme.mutedInk)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 28)
          .padding(.bottom, 20)
      }
    }
  }

  private func fixationRow(_ number: String, _ text: String) -> some View {
    HStack(spacing: 12) {
      Text(number)
        .font(.caption.bold().monospacedDigit())
        .frame(width: 24, height: 24)
        .background(accent.opacity(0.14), in: Circle())
        .foregroundStyle(accent)
      Text(text)
        .font(.subheadline)
        .foregroundStyle(Theme.ink)
    }
  }

  // MARK: - Scan stage

  private var scanStage: some View {
    VStack(spacing: 14) {
      if let pageImage, let scanStart {
        TimelineView(.animation) { timeline in
          let elapsed = timeline.date.timeIntervalSince(scanStart)
          let state = schedule.state(at: elapsed)
          VStack(spacing: 14) {
            pageCanvas(image: pageImage, elapsed: elapsed, spotlight: state.point)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .padding(.horizontal, 18)
            HStack {
              Text(state.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .animation(nil, value: state.label)
              Spacer()
              Text(String(format: "%.1fs", max(0, schedule.total - elapsed)))
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .cardSurface(radius: Theme.tileRadius)
            .padding(.horizontal, 18)
          }
        }
      } else {
        ProgressView()
      }
    }
    .padding(.vertical, 14)
  }

  /// The page under the recruiter's eye: a veil with a soft spotlight hole at
  /// the current fixation, and a heat trail where the gaze has already been.
  private func pageCanvas(image: UIImage, elapsed: TimeInterval, spotlight: CGPoint) -> some View {
    Image(uiImage: image)
      .resizable()
      .scaledToFit()
      .overlay {
        Canvas { context, size in
          context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.42)))
          context.blendMode = .destinationOut
          let center = CGPoint(x: spotlight.x * size.width, y: spotlight.y * size.height)
          let radius = size.width * 0.17
          context.fill(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .radialGradient(
              Gradient(colors: [.white, .white, .white.opacity(0)]),
              center: center, startRadius: radius * 0.3, endRadius: radius))
          context.blendMode = .normal
          heatTrail(into: &context, size: size, elapsed: elapsed)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .shadow(color: Theme.ink.opacity(0.15), radius: 16, y: 8)
  }

  /// Soft blobs over every fixation the gaze has already visited, sized and
  /// weighted by dwell time — the heatmap, accumulating live.
  private func heatTrail(into context: inout GraphicsContext, size: CGSize, elapsed: TimeInterval) {
    for segment in schedule.segments where segment.start < elapsed {
      let center = CGPoint(x: segment.stop.point.x * size.width, y: segment.stop.point.y * size.height)
      let radius = size.width * (0.055 + 0.05 * min(1, segment.stop.duration / 1.5))
      let strength = 0.20 + 0.25 * min(1, segment.stop.duration / 1.5)
      context.fill(
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
        with: .radialGradient(
          Gradient(colors: [accent.opacity(strength), accent.opacity(0)]),
          center: center, startRadius: 0, endRadius: radius))
    }
  }

  // MARK: - Report

  private var reportView: some View {
    List {
      Section {
        HStack(spacing: 18) {
          ZStack {
            Circle().stroke(Theme.hairline, lineWidth: 9)
            Circle().trim(from: 0, to: Double(report.score) / 100)
              .stroke(accent, style: StrokeStyle(lineWidth: 9, lineCap: .round))
              .rotationEffect(.degrees(-90))
            Text("\(report.score)").font(.title.bold())
          }
          .frame(width: 88, height: 88)
          VStack(alignment: .leading, spacing: 5) {
            Text(report.verdict).font(.headline)
            Text(report.verdictDetail)
              .font(.caption)
              .foregroundStyle(Theme.mutedInk)
          }
        }
        .padding(.vertical, 6)
        // The ring carries the score visually and the number sits inside it, so
        // read as separate elements this announces a bare "72" with no unit and
        // no verdict. Collapse the whole hero into one score reading.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("First-impression score")
        .accessibilityValue("\(report.score) out of 100. \(report.verdict). \(report.verdictDetail)")
      }

      if let repairSummary {
        Section {
          VStack(alignment: .leading, spacing: 10) {
            Label {
              Text(repairSummary).font(.subheadline)
            } icon: {
              Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
            }
            if documentBeforeRepair != nil {
              Button("Undo reviewed changes", systemImage: "arrow.uturn.backward") {
                undoRepair()
              }
              .font(.caption.weight(.semibold))
              .foregroundStyle(accent)
            }
          }
        }
      }

      Section {
        Picker("Strictness", selection: $strictnessRaw) {
          ForEach(RecruiterScanStrictness.allCases) { level in
            Text(level.title).tag(level.rawValue)
          }
        }
        .pickerStyle(.segmented)
      } header: {
        Text("How demanding is the reader?")
      } footer: {
        Text(strictness.detail)
      }

      if report.findings.contains(where: { $0.severity != .pass }) {
        Section {
          Button {
            showsRepairReview = true
          } label: {
            HStack(spacing: 14) {
              Image(systemName: "wand.and.stars")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(accent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
              VStack(alignment: .leading, spacing: 3) {
                Text("Auto-fix and review")
                  .font(.headline)
                  .foregroundStyle(Theme.ink)
                Text("Prepare supported improvements, then confirm every CV change.")
                  .font(.caption)
                  .foregroundStyle(Theme.mutedInk)
              }
              Spacer(minLength: 6)
              Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(accent)
            }
            .padding(.vertical, 5)
          }
          .buttonStyle(.plain)
        } header: {
          Text("Improve this CV")
        } footer: {
          Text("Existing facts can be reordered or rewritten. Missing roles, dates, education and measurable results stay blank until you add them—AI never invents them.")
        }
      }

      if !report.capturedFacts.isEmpty {
        Section("What the recruiter left with") {
          ForEach(report.capturedFacts, id: \.self) { fact in
            Label { Text(fact).font(.subheadline) } icon: {
              Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
          }
        }
      }

      if !report.missedFacts.isEmpty {
        Section("What they looked for and never found") {
          ForEach(report.missedFacts, id: \.self) { fact in
            Label { Text(fact).font(.subheadline) } icon: {
              Image(systemName: "eye.slash").foregroundStyle(.orange)
            }
          }
        }
      }

      Section {
        ForEach(report.findings) { finding in
          findingRow(finding)
        }
      } header: {
        Text("The six fixation points")
      } footer: {
        Text("Weighted by the share of the scan each point claims. The score is how much of the 7.4 seconds lands on real information.")
      }

      if !report.notes.isEmpty {
        Section("Layout notes") {
          ForEach(report.notes) { note in
            HStack(alignment: .top, spacing: 12) {
              Image(systemName: note.icon)
                .foregroundStyle(accent)
                .frame(width: 22)
              VStack(alignment: .leading, spacing: 3) {
                Text(note.title).font(.headline)
                Text(note.detail).font(.caption).foregroundStyle(Theme.mutedInk)
              }
            }
            .padding(.vertical, 3)
          }
        }
      }

      Section {
        Button {
          startScan()
        } label: {
          Label("Watch the scan again", systemImage: "arrow.counterclockwise")
        }
      } footer: {
        Text("Based on a published 2018 eye-tracking study of recruiter behaviour. Every check runs on device.")
      }
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(Theme.paper)
  }

  private func applyRepair(_ updated: ResumeDocument, revisionIDs: [UUID]) {
    let previousScore = report.score
    documentBeforeRepair = document
    repairRevisionIDs = revisionIDs
    document = updated
    onDocumentUpdated?(updated)
    didModifyDocument = true
    pageImage = nil
    renderError = nil
    let updatedReport = RecruiterScanService.analyze(document: updated, strictness: strictness)
    repairSummary = updatedReport.score > previousScore
      ? "Recruiter Scan improved from \(previousScore) to \(updatedReport.score). Review any remaining checks below."
      : "Your reviewed CV changes were saved. Review the remaining checks below."
    Task { await preparePage() }
  }

  private func undoRepair() {
    guard let previous = documentBeforeRepair else { return }
    resumeStore.replaceActiveDocument(with: previous)
    for id in repairRevisionIDs {
      careerStore.markRevisionReverted(id)
    }
    document = previous
    onDocumentUpdated?(previous)
    documentBeforeRepair = nil
    repairRevisionIDs = []
    didModifyDocument = true
    pageImage = nil
    renderError = nil
    repairSummary = "The reviewed Recruiter Scan changes were undone."
    Task { await preparePage() }
  }

  @ViewBuilder
  private func findingRow(_ finding: RecruiterScanFinding) -> some View {
    if let section = finding.section, finding.severity != .pass {
      switch fixRouting {
      case .push:
        NavigationLink(value: HomeRoute.editor(section)) {
          findingRowBody(finding, fixesIn: section)
        }
      case .dismissToHome:
        Button {
          openEditor(at: section)
        } label: {
          findingRowBody(finding, fixesIn: section)
        }
        .buttonStyle(.plain)
      }
    } else {
      findingRowBody(finding, fixesIn: nil)
    }
  }

  private func findingRowBody(_ finding: RecruiterScanFinding, fixesIn section: ResumeSection?) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: icon(for: finding.severity))
        .foregroundStyle(color(for: finding.severity))
        .frame(width: 22)
      VStack(alignment: .leading, spacing: 5) {
        HStack {
          Text(finding.title).font(.headline)
          Spacer()
          Text(String(format: "%.1fs", finding.gazeSeconds))
            .font(.caption2.bold().monospacedDigit())
            .foregroundStyle(Theme.mutedInk)
        }
        GeometryReader { proxy in
          ZStack(alignment: .leading) {
            Capsule().fill(Theme.muted)
            Capsule()
              .fill(accent.opacity(0.8))
              .frame(width: proxy.size.width * finding.gazeSeconds / RecruiterScanStudy.scanSeconds)
          }
        }
        .frame(height: 4)
        Text(finding.detail).font(.caption).foregroundStyle(Theme.mutedInk)
        if let section {
          HStack(spacing: 3) {
            Text("Fix in \(section.title)")
            if fixRouting == .dismissToHome {
              Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
            }
          }
          .font(.caption2.weight(.semibold))
          .foregroundStyle(accent)
        }
      }
    }
    .padding(.vertical, 3)
    .contentShape(Rectangle())
  }

  /// The sheet route: fold the scan away, then hand the destination to the
  /// home stack — the same door the app's shortcuts and widgets come through.
  private func openEditor(at section: ResumeSection) {
    dismiss()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
      NotificationCenter.default.post(name: .selectAppTab, object: "home")
      NotificationCenter.default.post(name: .openHomeRoute, object: HomeRoute.editor(section))
    }
  }

  private func icon(for severity: ATSIssueSeverity) -> String {
    switch severity {
    case .pass: "checkmark.circle.fill"
    case .warning: "exclamationmark.triangle.fill"
    case .action: "xmark.circle.fill"
    }
  }

  private func color(for severity: ATSIssueSeverity) -> Color {
    switch severity {
    case .pass: .green
    case .warning: .orange
    case .action: .red
    }
  }

  // MARK: - Machinery

  @MainActor
  private func preparePage() async {
    guard pageImage == nil else { return }
    do {
      await Task.yield()
      let data: Data
      if !didModifyDocument, let pdfData {
        data = pdfData
      } else {
        data = try ResumePDFRenderer.render(document: document)
      }
      guard let pdf = PDFDocument(data: data), let page = pdf.page(at: 0) else {
        renderError = "The résumé preview could not be read."
        return
      }
      let bounds = page.bounds(for: .mediaBox)
      let scale = 1400 / max(bounds.width, bounds.height)
      pageImage = page.thumbnail(
        of: CGSize(width: bounds.width * scale, height: bounds.height * scale),
        for: .mediaBox)
    } catch {
      renderError = error.localizedDescription
    }
  }

  private func startScan() {
    scanTask?.cancel()
    scanStart = Date()
    withAnimation(.easeInOut(duration: 0.25)) { phase = .scanning }
    let total = schedule.total
    scanTask = Task {
      try? await Task.sleep(nanoseconds: UInt64((total + 0.5) * 1_000_000_000))
      guard !Task.isCancelled else { return }
      withAnimation(.easeInOut(duration: 0.3)) { phase = .report }
    }
  }
}

/// A single review surface for every failed recruiter fixation. It prepares
/// evidence-constrained wording and safe ordering changes, while missing facts
/// remain explicit text fields. The active résumé changes only at final apply.
private struct RecruiterScanRepairView: View {
  let original: ResumeDocument
  let strictness: RecruiterScanStrictness
  let issueIDs: Set<String>
  let originalReport: RecruiterScanReport
  let onApply: (ResumeDocument, [UUID]) -> Void

  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var resumeStore: ResumeStore
  @EnvironmentObject private var careerStore: CareerIntelligenceStore
  @State private var draft: ResumeDocument
  @State private var isPreparingAI = false
  @State private var didPrepareAI = false
  @State private var aiErrorMessage: String?
  @State private var claimsRequiringConfirmation: [String] = []
  @State private var profileEvidenceSources: [String] = []
  @State private var generatedProfile = false
  @State private var preparationNotice: String?
  @State private var metricValue = ""
  @State private var metricOutcome = ""
  @State private var metricContext = ""

  init(
    document: ResumeDocument,
    strictness: RecruiterScanStrictness,
    onApply: @escaping (ResumeDocument, [UUID]) -> Void
  ) {
    let report = RecruiterScanService.analyze(document: document, strictness: strictness)
    original = document
    self.strictness = strictness
    originalReport = report
    issueIDs = Set(report.findings.filter { $0.severity != .pass }.map(\.id))
    self.onApply = onApply
    _draft = State(initialValue: RecruiterScanService.makeRepairDraft(
      document: document, report: report))
  }

  private var reviewedDraft: ResumeDocument {
    RecruiterScanService.finalizeRepairDraft(draft)
  }

  private var liveReport: RecruiterScanReport {
    RecruiterScanService.analyze(document: reviewedDraft, strictness: strictness)
  }

  private var remainingIssueCount: Int {
    liveReport.findings.count { issueIDs.contains($0.id) && $0.severity != .pass }
  }

  private var changedSectionCount: Int {
    let updated = reviewedDraft
    return [
      updated.personal != original.personal,
      updated.professionalProfile != original.professionalProfile,
      updated.experience != original.experience,
      updated.education != original.education,
    ].count(where: { $0 })
  }

  private var hasChanges: Bool { reviewedDraft != original }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          repairHero
          automaticPreparationStatus

          if issueIDs.contains("identity") { personalRepairCard }
          if !issueIDs.isDisjoint(with: ["current-role", "current-dates"]) {
            currentRoleRepairCard
          }
          if issueIDs.contains("trajectory") { previousRoleRepairCard }
          if issueIDs.contains("evidence") { evidenceRepairCard }
          if issueIDs.contains("education") { educationRepairCard }
          if issueIDs.contains("profile-skim") { profileRepairCard }

          if !claimsRequiringConfirmation.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
              Label("Confirm these claims", systemImage: "exclamationmark.shield.fill")
                .font(.headline)
                .foregroundStyle(.orange)
              ForEach(claimsRequiringConfirmation, id: \.self) { claim in
                Text("• \(claim)")
                  .font(.subheadline)
                  .foregroundStyle(Theme.inkSoft)
              }
            }
            .padding(18)
            .cardSurface()
          }

          Text("Contact details, references and the profile photo are never included in AI writing requests. Review every factual claim before exporting.")
            .font(.caption2)
            .foregroundStyle(Theme.mutedInk)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
        }
        .padding(20)
        .padding(.bottom, 92)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
      }
      .background(Theme.paper)
      .navigationTitle("Review CV improvements")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(Theme.paper, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        applyBar
      }
      .task { await prepareAutomaticImprovements() }
    }
  }

  private var repairHero: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label("GUIDED REPAIR", systemImage: "wand.and.stars")
        .font(.caption.bold())
        .tracking(1.2)
        .foregroundStyle(original.accent.color)
      Text("Make every second count.")
        .displayFont(32)
        .foregroundStyle(Theme.heroInk)
      Text("Review the prepared wording, add the facts only you know, and apply all confirmed changes together.")
        .font(.subheadline)
        .foregroundStyle(Theme.heroMutedInk)

      HStack(spacing: 12) {
        scorePill(title: "Before", score: originalReport.score, color: Theme.heroMutedInk)
        Image(systemName: "arrow.right")
          .font(.caption.bold())
          .foregroundStyle(Theme.heroMutedInk)
        scorePill(title: "Review", score: liveReport.score, color: original.accent.color)
        Spacer()
        Text(remainingIssueCount == 0 ? "All checks ready" : "\(remainingIssueCount) remaining")
          .font(.caption.weight(.semibold))
          .foregroundStyle(remainingIssueCount == 0 ? Color.green : Color.orange)
      }
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      ZStack {
        LinearGradient(
          colors: [Theme.heroTop, Theme.heroBottom],
          startPoint: .topLeading,
          endPoint: .bottomTrailing)
        Circle()
          .fill(original.accent.color.opacity(0.22))
          .frame(width: 180, height: 180)
          .blur(radius: 45)
          .offset(x: 190, y: -70)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 26, style: .continuous)
        .strokeBorder(.white.opacity(0.07), lineWidth: 1)
    }
  }

  private func scorePill(title: String, score: Int, color: Color) -> some View {
    HStack(spacing: 5) {
      Text(title).font(.caption2)
      Text("\(score)").font(.caption.bold().monospacedDigit())
    }
    .foregroundStyle(color)
    .padding(.horizontal, 9)
    .padding(.vertical, 6)
    .background(.white.opacity(0.07), in: Capsule())
  }

  @ViewBuilder
  private var automaticPreparationStatus: some View {
    if isPreparingAI {
      HStack(spacing: 12) {
        ProgressView().tint(original.accent.color)
        VStack(alignment: .leading, spacing: 2) {
          Text("Preparing supported improvements…").font(.subheadline.weight(.semibold))
          Text("Using existing CV facts and verified evidence only.")
            .font(.caption).foregroundStyle(Theme.mutedInk)
        }
      }
      .padding(16)
      .cardSurface(radius: Theme.tileRadius)
    } else if let aiErrorMessage {
      VStack(alignment: .leading, spacing: 8) {
        Label("Some wording needs manual review", systemImage: "exclamationmark.triangle.fill")
          .font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
        Text(aiErrorMessage).font(.caption).foregroundStyle(Theme.mutedInk)
        Button("Try automatic wording again") { Task { await prepareAutomaticImprovements(force: true) } }
          .font(.caption.weight(.semibold)).foregroundStyle(original.accent.color)
      }
      .padding(16)
      .cardSurface(radius: Theme.tileRadius)
    } else if didPrepareAI {
      VStack(alignment: .leading, spacing: 3) {
        Label("Real improvements prepared for your review", systemImage: "checkmark.shield.fill")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.green)
        if let preparationNotice {
          Text(preparationNotice)
            .font(.caption)
            .foregroundStyle(Theme.mutedInk)
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .cardSurface(radius: Theme.tileRadius)
    }
  }

  private var personalRepairCard: some View {
    repairCard(id: "identity", title: "Name and headline", systemImage: "person.text.rectangle") {
      repairTextField("Full name", text: $draft.personal.fullName, prompt: "Your full name")
      repairTextField("Professional headline", text: $draft.personal.headline, prompt: "Role | specialty | value")
    }
  }

  private var currentRoleRepairCard: some View {
    repairCard(
      id: issueIDs.contains("current-role") ? "current-role" : "current-dates",
      title: "Current role",
      systemImage: "briefcase.fill"
    ) {
      repairTextField("Job title", text: $draft.experience[0].role, prompt: "Your current or latest role")
      repairTextField("Company", text: $draft.experience[0].company, prompt: "Employer or organisation")
      repairTextField("Dates", text: $draft.experience[0].period, prompt: "Jan 2024 – Present")
    }
  }

  private var previousRoleRepairCard: some View {
    repairCard(id: "trajectory", title: "Previous role and dates", systemImage: "clock.arrow.circlepath") {
      Text("Add the role, internship, project or placement immediately before your current one.")
        .font(.caption).foregroundStyle(Theme.mutedInk)
      repairTextField("Job title", text: $draft.experience[1].role, prompt: "Previous role")
      repairTextField("Company", text: $draft.experience[1].company, prompt: "Employer or organisation")
      repairTextField("Dates", text: $draft.experience[1].period, prompt: "Mar 2021 – Dec 2023")
    }
  }

  private var evidenceRepairCard: some View {
    repairCard(id: "evidence", title: "Proof in the first bullet", systemImage: "chart.line.uptrend.xyaxis") {
      Text("Lead with a result, scale or percentage the recruiter can verify. Automatic wording preserves facts but cannot create the missing number.")
        .font(.caption).foregroundStyle(Theme.mutedInk)
      if let originalBullet = original.experience.first?.highlights.first?.nilIfBlank,
        originalBullet != draft.experience[0].highlights[0]
      {
        originalTextBlock(originalBullet)
      }
      TextField(
        "Example: Reduced onboarding time by 30% across four teams",
        text: $draft.experience[0].highlights[0],
        axis: .vertical
      )
      .lineLimit(3...7)
      .textFieldStyle(.roundedBorder)
      Text(RecruiterScanService.isQuantified(draft.experience[0].highlights[0])
        ? "A measurable result is present."
        : "Add a truthful number, percentage, amount, frequency or scale.")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(RecruiterScanService.isQuantified(draft.experience[0].highlights[0]) ? Color.green : Color.orange)

      if !RecruiterScanService.isQuantified(draft.experience[0].highlights[0]) {
        Divider().padding(.vertical, 2)
        Text("ADD VERIFIED PROOF")
          .font(.caption2.bold())
          .tracking(0.8)
          .foregroundStyle(original.accent.color)
        Text("Supply the fact and the app will build it into the bullet. Nothing is guessed.")
          .font(.caption)
          .foregroundStyle(Theme.mutedInk)
        HStack(spacing: 10) {
          metricField("Metric", text: $metricValue, prompt: "30%")
          metricField("Result", text: $metricOutcome, prompt: "fewer false alarms")
        }
        metricField("Context (optional)", text: $metricContext, prompt: "across 3 mobile releases")
        Button {
          insertVerifiedMetric()
        } label: {
          Label("Build this proof into the bullet", systemImage: "plus.circle.fill")
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
        }
        .buttonStyle(.borderedProminent)
        .tint(original.accent.color)
        .disabled(metricValue.isBlank || metricOutcome.isBlank)
      }
    }
  }

  private var educationRepairCard: some View {
    repairCard(id: "education", title: "Education check", systemImage: "graduationcap.fill") {
      repairTextField("Qualification", text: $draft.education[0].qualification, prompt: "Degree, diploma or certificate")
      repairTextField("Institution", text: $draft.education[0].institution, prompt: "School, university or provider")
      repairTextField("Dates", text: $draft.education[0].period, prompt: "2018 – 2022")
      repairTextField("Details", text: $draft.education[0].details, prompt: "Major, distinction or relevant focus")
    }
  }

  private var profileRepairCard: some View {
    repairCard(id: "profile-skim", title: "Professional profile", systemImage: "text.alignleft") {
      Text("Keep this to a focused three-to-five-line pitch grounded in the CV below.")
        .font(.caption).foregroundStyle(Theme.mutedInk)
      if let originalProfile = original.professionalProfile.nilIfBlank,
        originalProfile != draft.professionalProfile
      {
        originalTextBlock(originalProfile)
      }
      TextEditor(text: $draft.professionalProfile)
        .font(.subheadline)
        .scrollContentBackground(.hidden)
        .padding(10)
        .frame(minHeight: 130)
        .background(Theme.muted.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      let words = draft.professionalProfile.split(whereSeparator: \.isWhitespace).count
      Text("\(words) words · target \(profileWordLimit) or fewer")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(words == 0 || words > profileWordLimit ? Color.orange : Color.green)
      if generatedProfile, !profileEvidenceSources.isEmpty {
        Text("Sources: \(profileEvidenceSources.joined(separator: " · "))")
          .font(.caption2).foregroundStyle(Theme.mutedInk).lineLimit(3)
      }
    }
  }

  private func repairCard<Content: View>(
    id: String,
    title: String,
    systemImage: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    let finding = liveReport.findings.first { $0.id == id }
      ?? liveReport.findings.first { issueIDs.contains($0.id) }
    let severity = finding?.severity ?? .action
    return VStack(alignment: .leading, spacing: 13) {
      HStack(spacing: 11) {
        Image(systemName: systemImage)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(original.accent.color)
          .frame(width: 36, height: 36)
          .background(original.accent.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(.headline)
          Label(statusTitle(for: severity), systemImage: statusIcon(for: severity))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(statusColor(for: severity))
        }
        Spacer()
      }
      if let originalFinding = originalReport.findings.first(where: { $0.id == id }) {
        Text(originalFinding.detail)
          .font(.caption)
          .foregroundStyle(Theme.mutedInk)
      }
      content()
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardSurface()
  }

  private func repairTextField(_ label: String, text: Binding<String>, prompt: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(label).font(.caption.weight(.semibold)).foregroundStyle(Theme.inkSoft)
      TextField(prompt, text: text)
        .textFieldStyle(.roundedBorder)
        .textInputAutocapitalization(.words)
    }
  }

  private func originalTextBlock(_ text: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("ORIGINAL")
        .font(.caption2.bold())
        .tracking(0.8)
        .foregroundStyle(Theme.mutedInk)
      Text(text)
        .font(.caption)
        .foregroundStyle(Theme.inkSoft)
        .lineLimit(5)
    }
    .padding(11)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.muted.opacity(0.42), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }

  private func metricField(_ label: String, text: Binding<String>, prompt: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(label).font(.caption.weight(.semibold)).foregroundStyle(Theme.inkSoft)
      TextField(prompt, text: text)
        .textFieldStyle(.roundedBorder)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func insertVerifiedMetric() {
    guard !draft.experience.isEmpty, !draft.experience[0].highlights.isEmpty else { return }
    guard let improved = RecruiterScanService.addingVerifiedMetric(
      metricValue,
      outcome: metricOutcome,
      context: metricContext,
      to: draft.experience[0].highlights[0]
    ) else { return }
    draft.experience[0].highlights[0] = improved
  }

  private var applyBar: some View {
    VStack(spacing: 7) {
      Button {
        applyReviewedChanges()
      } label: {
        Label(
          changedSectionCount == 1 ? "Apply reviewed change" : "Apply \(changedSectionCount) reviewed changes",
          systemImage: "checkmark.circle.fill"
        )
        .font(.headline)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(hasChanges ? original.accent.color : Theme.mutedInk, in: Capsule())
      }
      .buttonStyle(.plain)
      .disabled(!hasChanges)
      Text("Nothing is added to your CV until you apply.")
        .font(.caption2).foregroundStyle(Theme.mutedInk)
    }
    .padding(.horizontal, 20)
    .padding(.top, 11)
    .padding(.bottom, 8)
    .background(.regularMaterial)
  }

  private var profileWordLimit: Int {
    switch strictness {
    case .low: 110
    case .medium: 79
    case .high: 55
    }
  }

  @MainActor
  private func prepareAutomaticImprovements(force: Bool = false) async {
    guard force || !didPrepareAI else { return }
    isPreparingAI = true
    aiErrorMessage = nil
    preparationNotice = nil
    didPrepareAI = false
    var failures: [String] = []
    var usedPrivateFallback = false
    let locallyPreparedProfile = original.professionalProfile.isBlank
      && !draft.professionalProfile.isBlank

    if issueIDs.contains("profile-skim"),
      !draft.experience.isEmpty || !draft.competencies.isEmpty || !draft.education.isEmpty
    {
      do {
        let result = try await ResumeAIService.shared.writeProfile(
          for: reviewedDraft, evidence: careerStore.verifiedEvidence)
        let proposed = result.alternatives
          .filter { $0.split(whereSeparator: \.isWhitespace).count <= profileWordLimit }
          .min { lhs, rhs in
            lhs.split(whereSeparator: \.isWhitespace).count
              < rhs.split(whereSeparator: \.isWhitespace).count
          }
          ?? result.alternatives.min { lhs, rhs in
            lhs.split(whereSeparator: \.isWhitespace).count
              < rhs.split(whereSeparator: \.isWhitespace).count
          }
        if let proposed = proposed?.nilIfBlank {
          draft.professionalProfile = proposed
          generatedProfile = true
          profileEvidenceSources = result.evidenceSources ?? []
          appendUniqueClaims(result.claimsRequiringConfirmation)
        }
      } catch {
        if locallyPreparedProfile {
          usedPrivateFallback = true
        } else {
          failures.append("profile wording: \(ResumeAIError.from(error).localizedDescription)")
        }
      }
    }

    let evidenceStillNeedsWork = liveReport.findings.first { $0.id == "evidence" }?.severity != .pass
    if issueIDs.contains("evidence"), evidenceStillNeedsWork, !draft.experience.isEmpty,
      let source = draft.experience[0].highlights.first?.nilIfBlank,
      RecruiterScanService.isQuantified(source)
    {
      do {
        let result = try await ResumeAIService.shared.improveBullet(
          source,
          role: draft.experience[0].role,
          company: draft.experience[0].company)
        let proposed = RecruiterScanService.isQuantified(source)
          ? result.alternatives.first(where: RecruiterScanService.isQuantified)
          : result.alternatives.first
        if let proposed = proposed?.nilIfBlank {
          draft.experience[0].highlights[0] = proposed
          appendUniqueClaims(result.claimsRequiringConfirmation)
        }
      } catch {
        failures.append("first-bullet wording: \(ResumeAIError.from(error).localizedDescription)")
      }
    }

    isPreparingAI = false
    didPrepareAI = true
    aiErrorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
    if usedPrivateFallback {
      preparationNotice = "Connected AI was unavailable, so the headline and profile were built privately from facts already in this CV."
    }
  }

  private func appendUniqueClaims(_ claims: [String]) {
    for claim in claims where !claimsRequiringConfirmation.contains(claim) {
      claimsRequiringConfirmation.append(claim)
    }
  }

  private func applyReviewedChanges() {
    let updated = reviewedDraft
    guard updated != original else { return }
    resumeStore.replaceActiveDocument(with: updated)
    var revisionIDs: [UUID] = []
    if generatedProfile, updated.professionalProfile != original.professionalProfile {
      let revision = AIRevision(
        resumeID: resumeStore.activeResumeID,
        field: "Professional profile",
        before: original.professionalProfile,
        after: updated.professionalProfile,
        evidenceIDs: careerStore.verifiedEvidence.map(\.id),
        evidenceLabels: profileEvidenceSources,
        claimsRequiringConfirmation: claimsRequiringConfirmation
      )
      careerStore.addRevision(revision)
      revisionIDs.append(revision.id)
    }
    onApply(updated, revisionIDs)
    dismiss()
  }

  private func statusTitle(for severity: ATSIssueSeverity) -> String {
    switch severity {
    case .pass: "Ready for review"
    case .warning: "Needs a stronger answer"
    case .action: "Missing required information"
    }
  }

  private func statusIcon(for severity: ATSIssueSeverity) -> String {
    switch severity {
    case .pass: "checkmark.circle.fill"
    case .warning: "exclamationmark.triangle.fill"
    case .action: "xmark.circle.fill"
    }
  }

  private func statusColor(for severity: ATSIssueSeverity) -> Color {
    switch severity {
    case .pass: .green
    case .warning: .orange
    case .action: .red
    }
  }
}

/// The gaze path with arrival times worked out, so any elapsed time maps to a
/// position: dwelling on a stop, or mid-saccade between two.
private struct GazeSchedule {
  struct Segment {
    let stop: RecruiterGazeStop
    let start: Double
    let end: Double
  }

  let segments: [Segment]
  let total: Double

  init(stops: [RecruiterGazeStop]) {
    var time = 0.0
    segments = stops.map { stop in
      defer { time += stop.duration }
      return Segment(stop: stop, start: time, end: time + stop.duration)
    }
    total = time
  }

  func state(at elapsed: TimeInterval) -> (point: CGPoint, label: String) {
    guard let last = segments.last else { return (CGPoint(x: 0.5, y: 0.5), "") }
    let time = min(max(elapsed, 0), last.end - 0.001)
    guard let index = segments.firstIndex(where: { time < $0.end }) else {
      return (last.stop.point, last.stop.label)
    }
    let segment = segments[index]
    // The eye does not teleport: the first slice of each dwell is the saccade
    // from the previous stop, eased so the move reads as a glance.
    let travel = min(0.22, segment.stop.duration * 0.45)
    if index > 0, time - segment.start < travel {
      let progress = (time - segment.start) / travel
      let eased = progress * progress * (3 - 2 * progress)
      let from = segments[index - 1].stop.point
      let to = segment.stop.point
      return (
        CGPoint(x: from.x + (to.x - from.x) * eased, y: from.y + (to.y - from.y) * eased),
        segment.stop.label
      )
    }
    return (segment.stop.point, segment.stop.label)
  }
}

#Preview {
  NavigationStack {
    RecruiterScanView(document: .example)
  }
  .environmentObject(ResumeStore(initialDocument: .example))
  .environmentObject(CareerIntelligenceStore())
}
