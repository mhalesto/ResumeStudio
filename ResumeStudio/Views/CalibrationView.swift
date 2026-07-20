import SwiftUI

/// The screen that says the unflattering thing. Everything shown here is drawn
/// from the user's own recorded applications, on device, and every claim carries
/// the sample it came from.
struct CalibrationView: View {
  @EnvironmentObject private var resumeStore: ResumeStore
  @EnvironmentObject private var applicationStore: ApplicationStore

  private var accent: Color { resumeStore.document.accent.color }

  private var report: ApplicationCalibrationReport {
    ApplicationCalibrationService.calibrate(applications: applicationStore.applications)
  }

  var body: some View {
    let report = self.report
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        header
        statistics(report)
        ForEach(report.signals) { signal in
          CalibrationSignalCard(signal: signal, accent: accent)
        }
        footnote
      }
      .padding(20)
      .padding(.bottom, 40)
      .frame(maxWidth: 720)
      .frame(maxWidth: .infinity)
    }
    .background(Theme.paper)
    .navigationTitle("Reality Check")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("WHAT YOUR HISTORY SHOWS").eyebrow().foregroundStyle(accent)
      Text("The parts worth hearing")
        .font(Theme.display(30))
        .foregroundStyle(Theme.ink)
      Text("""
        Most résumé tools only tell you what is going well. This one compares the \
        applications that moved against the ones that did not, and reports the \
        difference — including when the difference is uncomfortable.
        """)
        .font(.subheadline)
        .foregroundStyle(Theme.inkSoft)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func statistics(_ report: ApplicationCalibrationReport) -> some View {
    HStack(spacing: 10) {
      CalibrationStat(value: "\(report.settledCount)", label: "Settled")
      CalibrationStat(value: "\(report.progressedCount)", label: "Reached interview")
      CalibrationStat(value: report.progressionRateText ?? "—", label: "Progression rate")
    }
  }

  private var footnote: some View {
    Label(
      """
      Calculated on this device from your applications and outcome reviews. Nothing \
      here is uploaded, and nothing here is compared against other people.
      """,
      systemImage: "lock.fill"
    )
    .font(.caption)
    .foregroundStyle(Theme.mutedInk)
    .fixedSize(horizontal: false, vertical: true)
    .padding(.top, 4)
  }
}

private struct CalibrationStat: View {
  let value: String
  let label: LocalizedStringResource

  var body: some View {
    VStack(spacing: 3) {
      Text(value).font(.title2.bold()).foregroundStyle(Theme.ink)
      Text(label)
        .font(.caption2)
        .foregroundStyle(Theme.mutedInk)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .padding(.vertical, 13)
    .frame(maxWidth: .infinity)
    .cardSurface(radius: 17)
  }
}

struct CalibrationSignalCard: View {
  let signal: ApplicationCalibrationSignal
  let accent: Color

  /// Good news is never dressed in warning colours, and a hard finding is never
  /// softened into the accent.
  private var tint: Color { signal.kind.isEncouraging ? .green : accent }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 13) {
        Image(systemName: signal.kind.systemImage)
          .font(.title2)
          .foregroundStyle(tint)
          .frame(width: 52, height: 52)
          .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 16))
        VStack(alignment: .leading, spacing: 5) {
          confidenceBadge
          Text(signal.headline).font(.title3.bold()).foregroundStyle(Theme.ink)
        }
      }

      Text(signal.detail)
        .font(.subheadline)
        .foregroundStyle(Theme.inkSoft)
        .fixedSize(horizontal: false, vertical: true)

      Label(signal.evidence, systemImage: "chart.xyaxis.line")
        .font(.caption)
        .foregroundStyle(Theme.mutedInk)
        .fixedSize(horizontal: false, vertical: true)

      Text(signal.confidence.caveat)
        .font(.caption)
        .foregroundStyle(Theme.mutedInk)
        .fixedSize(horizontal: false, vertical: true)

      if let section = signal.focus?.editorSection {
        NavigationLink(value: HomeRoute.editor(section)) {
          Label("Open \(String(localized: section.title).lowercased())", systemImage: "arrow.right")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(20)
    .background(
      LinearGradient(
        colors: [tint.opacity(0.12), Theme.card, Theme.card],
        startPoint: .topLeading, endPoint: .bottomTrailing),
      in: RoundedRectangle(cornerRadius: 24, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .strokeBorder(tint.opacity(0.24), lineWidth: 1)
    }
  }

  private var confidenceBadge: some View {
    Text(signal.confidence.title)
      .font(.caption2.weight(.bold))
      .textCase(.uppercase)
      .foregroundStyle(tint)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(tint.opacity(0.15), in: Capsule())
      .accessibilityLabel("Confidence: \(String(localized: signal.confidence.title))")
  }
}
