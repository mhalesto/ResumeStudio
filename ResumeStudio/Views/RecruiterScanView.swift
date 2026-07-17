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

  let document: ResumeDocument
  var pdfData: Data?
  /// Presented as a sheet from the preview; pushed from the career workspace.
  var showsDone = false
  var fixRouting: SectionFixRouting = .push

  private enum Phase { case intro, scanning, report }
  @Environment(\.dismiss) private var dismiss
  @State private var phase = Phase.intro
  @State private var pageImage: UIImage?
  @State private var renderError: String?
  @State private var scanStart: Date?
  @State private var scanTask: Task<Void, Never>?
  /// Remembered across résumés and sessions: how demanding the reader is.
  @AppStorage("recruiterScanStrictness") private var strictnessRaw =
    RecruiterScanStrictness.medium.rawValue

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
            .font(Theme.display(58))
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
      if let pdfData {
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
}
