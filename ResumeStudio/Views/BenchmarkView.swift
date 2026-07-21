import SwiftUI

/// Outcome benchmarks. The only screen in the app that reads across users, so it
/// opens with what it shares rather than burying it: contributing is what makes
/// a benchmark exist, and nothing is shown until a cohort is large enough that
/// no individual can be read out of it.
struct BenchmarkView: View {
  @EnvironmentObject private var resumeStore: ResumeStore
  @EnvironmentObject private var applicationStore: ApplicationStore
  @EnvironmentObject private var careerStore: CareerIntelligenceStore
  @EnvironmentObject private var network: NetworkMonitor

  @State private var comparison: BenchmarkComparison?
  @State private var isContributing = false
  @State private var errorMessage: String?

  private var accent: Color { resumeStore.document.accent.color }

  private var cohort: BenchmarkCohort {
    BenchmarkAnalysis.cohort(
      document: resumeStore.document, market: careerStore.preferredMarket)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        header
        cohortCard
        if let comparison {
          BenchmarkComparisonCard(comparison: comparison, accent: accent)
        } else {
          disclosureCard
        }
        if let errorMessage {
          Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
        }
        contributeButton
      }
      .padding(20)
      .padding(.bottom, 40)
      .frame(maxWidth: 720)
      .frame(maxWidth: .infinity)
    }
    .background(Theme.paper)
    .navigationTitle("Benchmarks")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("HOW YOU COMPARE").eyebrow().foregroundStyle(accent)
      Text("You, against people\nsearching like you")
        .displayFont(30)
        .foregroundStyle(Theme.ink)
      Text("""
        A progression rate on its own means very little. The same number next to \
        people applying for similar roles in the same market is the difference \
        between guessing and knowing.
        """)
        .font(.subheadline)
        .foregroundStyle(Theme.inkSoft)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var cohortCard: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("YOUR COHORT").eyebrow().foregroundStyle(Theme.mutedInk)
      Text(cohort.title)
        .font(.headline)
        .foregroundStyle(Theme.ink)
        .fixedSize(horizontal: false, vertical: true)
      Text("Read from your headline and most recent role. Change either and the cohort follows.")
        .font(.caption)
        .foregroundStyle(Theme.mutedInk)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardSurface(radius: 22)
  }

  private var disclosureCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("What is shared", systemImage: "lock.shield.fill")
        .font(.headline)
        .foregroundStyle(Theme.ink)
      ForEach(Self.disclosures, id: \.self) { line in
        Label {
          Text(line).font(.caption).foregroundStyle(Theme.inkSoft)
        } icon: {
          Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(accent)
        }
        .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardSurface(radius: 22)
  }

  private static let disclosures: [String] = [
    "Three counts: how many applications have settled, how many reached an interview, and how long that typically took.",
    "Your cohort, which is three fixed categories — never your job title, employer, or résumé text.",
    "Nothing else. No names, no adverts, no URLs, no résumé content.",
    "Contributing again replaces your previous figures rather than adding to them.",
    "A cohort is only ever shown once enough separate people are in it.",
  ]

  private var contributeButton: some View {
    Button {
      Task { await contribute() }
    } label: {
      HStack {
        if isContributing { ProgressView().tint(.white) }
        Text(comparison == nil ? "Contribute and compare" : "Refresh")
          .font(.headline)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 14)
      .background(accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .foregroundStyle(.white)
    }
    .buttonStyle(.plain)
    .disabled(isContributing || !network.isOnline)
    .opacity(network.isOnline ? 1 : 0.5)
  }

  private func contribute() async {
    errorMessage = nil
    let cohort = self.cohort
    guard
      let contribution = BenchmarkAnalysis.contribution(
        cohort: cohort, applications: applicationStore.applications)
    else {
      errorMessage = """
        You need at least one settled application before there is anything to \
        contribute or compare.
        """
      return
    }
    isContributing = true
    defer { isContributing = false }
    do {
      let snapshot = try await BenchmarkService().contribute(contribution)
      comparison = BenchmarkAnalysis.compare(
        cohort: cohort, snapshot: snapshot, applications: applicationStore.applications)
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private struct BenchmarkComparisonCard: View {
  let comparison: BenchmarkComparison
  let accent: Color

  private var tint: Color {
    switch comparison.verdict {
    case .ahead: .green
    case .behind: .orange
    case .inLine: accent
    case .unknown: Theme.mutedInk
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 13) {
        Image(systemName: comparison.verdict.systemImage)
          .font(.title2)
          .foregroundStyle(tint)
          .frame(width: 52, height: 52)
          .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 16))
        Text(comparison.headline)
          .font(.title3.bold())
          .foregroundStyle(Theme.ink)
          .fixedSize(horizontal: false, vertical: true)
      }

      if comparison.snapshot.released, let cohortPercent = comparison.snapshot.progressionPercent {
        HStack(spacing: 10) {
          BenchmarkFigure(
            value: comparison.localProgressionPercent.map { "\($0)%" } ?? "—",
            label: "You", tint: tint)
          BenchmarkFigure(value: "\(cohortPercent)%", label: "Your cohort", tint: Theme.mutedInk)
          BenchmarkFigure(
            value: comparison.snapshot.medianDaysToProgress.map { "\($0)d" } ?? "—",
            label: "Cohort time to interview", tint: Theme.mutedInk)
        }
      }

      Text(comparison.detail)
        .font(.subheadline)
        .foregroundStyle(Theme.inkSoft)
        .fixedSize(horizontal: false, vertical: true)

      if comparison.snapshot.released {
        Text("Based on \(comparison.snapshot.contributors) contributors and \(comparison.snapshot.settled) settled applications. Rates are rounded, and correlation is not cause.")
          .font(.caption)
          .foregroundStyle(Theme.mutedInk)
          .fixedSize(horizontal: false, vertical: true)
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
}

private struct BenchmarkFigure: View {
  let value: String
  let label: LocalizedStringResource
  let tint: Color

  var body: some View {
    VStack(spacing: 3) {
      Text(value).font(.title3.bold()).foregroundStyle(tint)
      Text(label)
        .font(.caption2)
        .foregroundStyle(Theme.mutedInk)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .minimumScaleFactor(0.7)
    }
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity)
    .cardSurface(radius: 17)
  }
}
