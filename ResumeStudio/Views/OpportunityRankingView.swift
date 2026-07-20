import SwiftUI

/// Ranks the saved shortlist so effort goes where it can land. The scarcest
/// thing in a job search is the evening spent on an application that was never
/// going to work, and this screen exists to spend fewer of them.
struct OpportunityRankingView: View {
  @EnvironmentObject private var resumeStore: ResumeStore
  @EnvironmentObject private var applicationStore: ApplicationStore

  private var accent: Color { resumeStore.document.accent.color }

  private var ranking: OpportunityRanking {
    OpportunityRankingService.rank(
      applications: applicationStore.applications,
      document: resumeStore.document
    )
  }

  var body: some View {
    let ranking = self.ranking
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        header(ranking)
        if ranking.scores.isEmpty {
          emptyState
        } else {
          ForEach(ranking.scores) { score in
            OpportunityScoreCard(score: score, accent: accent)
          }
        }
        footnote
      }
      .padding(20)
      .padding(.bottom, 40)
      .frame(maxWidth: 720)
      .frame(maxWidth: .infinity)
    }
    .background(Theme.paper)
    .navigationTitle("Where to Apply")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func header(_ ranking: OpportunityRanking) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("YOUR SAVED SHORTLIST").eyebrow().foregroundStyle(accent)
      Text("Where the next hour goes")
        .font(Theme.display(30))
        .foregroundStyle(Theme.ink)
      Text(ranking.summary)
        .font(.subheadline)
        .foregroundStyle(Theme.inkSoft)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var emptyState: some View {
    VStack(alignment: .leading, spacing: 10) {
      Image(systemName: "tray").font(.title).foregroundStyle(accent)
      Text("No saved opportunities")
        .font(.headline)
        .foregroundStyle(Theme.ink)
      Text("""
        Capture adverts you are considering and keep them saved. This screen ranks \
        them against your résumé before you commit an evening to any of them.
        """)
        .font(.subheadline)
        .foregroundStyle(Theme.inkSoft)
        .fixedSize(horizontal: false, vertical: true)
      NavigationLink(value: HomeRoute.jobCapture) {
        Label("Capture a job", systemImage: "square.and.arrow.down.fill")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(accent)
      }
      .buttonStyle(.plain)
    }
    .padding(20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardSurface(radius: 22)
  }

  private var footnote: some View {
    Label(
      """
      Scored on this device against the same keyword check the ATS review uses. \
      No AI credits, no network, and the advert text never leaves your phone.
      """,
      systemImage: "lock.fill"
    )
    .font(.caption)
    .foregroundStyle(Theme.mutedInk)
    .fixedSize(horizontal: false, vertical: true)
    .padding(.top, 4)
  }
}

private struct OpportunityScoreCard: View {
  let score: OpportunityScore
  let accent: Color

  private var tint: Color {
    switch score.band {
    case .strong: .green
    case .possible: accent
    case .longShot: Theme.mutedInk
    case .unscored: Theme.mutedInk
    }
  }

  var body: some View {
    NavigationLink(value: HomeRoute.applicationDetail(score.id)) {
      VStack(alignment: .leading, spacing: 13) {
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: score.band.systemImage)
            .font(.title3)
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 14))
          VStack(alignment: .leading, spacing: 4) {
            Text(score.band.title)
              .font(.caption2.weight(.bold))
              .textCase(.uppercase)
              .foregroundStyle(tint)
            Text(score.label)
              .font(.headline)
              .foregroundStyle(Theme.ink)
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer(minLength: 0)
          if score.coverage != nil {
            VStack(spacing: 1) {
              Text(score.coveragePercentText)
                .font(.title3.bold())
                .foregroundStyle(tint)
              Text("matched")
                .font(.caption2)
                .foregroundStyle(Theme.mutedInk)
            }
          }
        }

        Text(score.band.guidance)
          .font(.subheadline)
          .foregroundStyle(Theme.inkSoft)
          .fixedSize(horizontal: false, vertical: true)

        if !score.topMissing.isEmpty {
          VStack(alignment: .leading, spacing: 6) {
            Text("Missing from your résumé")
              .font(.caption.weight(.semibold))
              .foregroundStyle(Theme.mutedInk)
            Text(score.topMissing.joined(separator: " · "))
              .font(.caption)
              .foregroundStyle(Theme.inkSoft)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      .padding(18)
      .frame(maxWidth: .infinity, alignment: .leading)
      .cardSurface(radius: 22)
    }
    .buttonStyle(.plain)
  }
}
