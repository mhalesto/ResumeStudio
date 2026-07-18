import SwiftUI
import WidgetKit

private let appGroup = "group.com.halalisanimbanjwa.ResumeStudio"

/// One day of the trackable-links opens trend, drawn as a bar in the large
/// widget. `index` keeps consecutive days distinct on the x-axis — single-letter
/// weekday labels repeat across a week and would otherwise collapse together.
struct WidgetTrendPoint: Identifiable {
  let index: Int
  let label: String
  let opens: Int
  var id: Int { index }
}

struct ResumeStudioWidgetEntry: TimelineEntry {
  let date: Date
  let tracked: Int
  let interviews: Int
  let offers: Int
  let resumeCompletion: Int
  let nextRole: String
  let nextCompany: String
  let nextDate: Date?
  // Trackable-links ("Smart Links") stats, shown on the large widget.
  let linksActive: Int
  let linkOpens: Int
  let linkReadMinutes: Int
  let linkDownloads: Int
  let linkTrend: [WidgetTrendPoint]
}

struct ResumeStudioWidgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> ResumeStudioWidgetEntry {
    ResumeStudioWidgetEntry(
      date: .now,
      tracked: 12,
      interviews: 2,
      offers: 1,
      resumeCompletion: 92,
      nextRole: "Product Designer",
      nextCompany: "Northstar",
      nextDate: .now.addingTimeInterval(86_400),
      linksActive: 3,
      linkOpens: 47,
      linkReadMinutes: 18,
      linkDownloads: 5,
      linkTrend: Self.sampleTrend)
  }

  func getSnapshot(in context: Context, completion: @escaping (ResumeStudioWidgetEntry) -> Void) {
    completion(context.isPreview ? placeholder(in: context) : currentEntry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<ResumeStudioWidgetEntry>) -> Void) {
    let entry = currentEntry()
    let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1_800)
    completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
  }

  private func currentEntry() -> ResumeStudioWidgetEntry {
    let defaults = UserDefaults(suiteName: appGroup)
    let nextTimestamp = defaults?.double(forKey: "widgetNextDate") ?? 0
    let opens = defaults?.array(forKey: "widgetLinkTrendOpens") as? [Int] ?? []
    let labels = defaults?.array(forKey: "widgetLinkTrendLabels") as? [String] ?? []
    let trend = zip(labels, opens).enumerated().map { offset, pair in
      WidgetTrendPoint(index: offset, label: pair.0, opens: pair.1)
    }
    return ResumeStudioWidgetEntry(
      date: .now,
      tracked: defaults?.integer(forKey: "widgetTracked") ?? 0,
      interviews: defaults?.integer(forKey: "widgetInterviews") ?? 0,
      offers: defaults?.integer(forKey: "widgetOffers") ?? 0,
      resumeCompletion: defaults?.integer(forKey: "widgetResumeCompletion") ?? 0,
      nextRole: defaults?.string(forKey: "widgetNextRole") ?? "",
      nextCompany: defaults?.string(forKey: "widgetNextCompany") ?? "",
      nextDate: nextTimestamp > 0 ? Date(timeIntervalSince1970: nextTimestamp) : nil,
      linksActive: defaults?.integer(forKey: "widgetLinksActive") ?? 0,
      linkOpens: defaults?.integer(forKey: "widgetLinkOpens") ?? 0,
      linkReadMinutes: defaults?.integer(forKey: "widgetLinkReadMinutes") ?? 0,
      linkDownloads: defaults?.integer(forKey: "widgetLinkDownloads") ?? 0,
      linkTrend: trend)
  }

  static let sampleTrend: [WidgetTrendPoint] = {
    let labels = ["M", "T", "W", "T", "F", "S", "S"]
    let opens = [2, 5, 3, 8, 6, 4, 9]
    return zip(labels, opens).enumerated().map { WidgetTrendPoint(index: $0, label: $1.0, opens: $1.1) }
  }()
}

struct ResumeStudioWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: ResumeStudioWidgetEntry

  var body: some View {
    Group {
      if family == .systemLarge {
        largeBody
      } else {
        compactBody
      }
    }
    .containerBackground(for: .widget) {
      LinearGradient(colors: [Color(.systemBackground), .orange.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    .widgetURL(widgetURL)
  }

  private var widgetURL: URL? {
    if family == .systemLarge {
      return URL(string: "resumestudio://links")
    }
    return URL(string: entry.nextRole.isEmpty ? "resumestudio://applications" : "resumestudio://interviews")
  }

  // MARK: - Small & Medium (unchanged behaviour)

  private var compactBody: some View {
    VStack(alignment: .leading, spacing: 10) {
      header
      if family == .systemMedium, !entry.nextRole.isEmpty {
        VStack(alignment: .leading, spacing: 3) {
          Text("NEXT INTERVIEW").font(.caption2.bold()).foregroundStyle(.secondary)
          Text(entry.nextRole).font(.headline).lineLimit(1)
          Text(entry.nextCompany).font(.caption).foregroundStyle(.secondary).lineLimit(1)
          if let nextDate = entry.nextDate {
            Text(nextDate, style: .relative).font(.caption.bold()).foregroundStyle(.orange)
          }
        }
      } else {
        Text("\(entry.tracked)")
          .font(.system(size: 34, weight: .bold, design: .rounded))
        Text("applications tracked").font(.caption).foregroundStyle(.secondary)
      }

      Spacer(minLength: 0)
      HStack(spacing: 14) {
        Label("\(entry.interviews)", systemImage: "person.2.fill")
        Label("\(entry.offers)", systemImage: "checkmark.seal.fill")
      }
      .font(.caption.bold())
    }
  }

  // MARK: - Large (trackable-links dashboard with graph)

  private var largeBody: some View {
    VStack(alignment: .leading, spacing: 12) {
      header

      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text("\(entry.linkOpens)")
          .font(.system(size: 40, weight: .bold, design: .rounded))
        Text("résumé opens").font(.subheadline).foregroundStyle(.secondary)
      }

      Text("LAST 7 DAYS").font(.caption2.bold()).foregroundStyle(.secondary)
      trendChart
        .frame(maxWidth: .infinity)
        .frame(height: 92)

      Spacer(minLength: 0)

      HStack(spacing: 0) {
        statTile("\(entry.linksActive)", "Live", "dot.radiowaves.left.and.right")
        divider
        statTile("\(entry.linkReadMinutes)m", "Read", "clock.fill")
        divider
        statTile("\(entry.linkDownloads)", "Saves", "arrow.down.circle.fill")
        divider
        statTile("\(entry.tracked)", "Applied", "briefcase.fill")
      }
    }
  }

  @ViewBuilder private var trendChart: some View {
    if entry.linkTrend.contains(where: { $0.opens > 0 }) {
      let maxOpens = max(entry.linkTrend.map(\.opens).max() ?? 0, 1)
      VStack(spacing: 6) {
        GeometryReader { geo in
          HStack(alignment: .bottom, spacing: 8) {
            ForEach(entry.linkTrend) { point in
              RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(point.opens > 0
                  ? AnyShapeStyle(.orange.gradient)
                  : AnyShapeStyle(.orange.opacity(0.18)))
                .frame(maxWidth: .infinity)
                .frame(height: max(3, CGFloat(point.opens) / CGFloat(maxOpens) * geo.size.height))
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        HStack(spacing: 8) {
          ForEach(entry.linkTrend) { point in
            Text(point.label)
              .font(.system(size: 10, weight: .medium))
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity)
          }
        }
      }
    } else {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(.orange.opacity(0.08))
        .overlay {
          VStack(spacing: 4) {
            Image(systemName: "chart.bar.xaxis").font(.title3).foregroundStyle(.orange)
            Text("Share a link to see opens here")
              .font(.caption).foregroundStyle(.secondary)
          }
        }
    }
  }

  private var divider: some View {
    Rectangle().fill(.secondary.opacity(0.2)).frame(width: 1, height: 30)
  }

  private func statTile(_ value: String, _ label: String, _ icon: String) -> some View {
    VStack(spacing: 3) {
      Image(systemName: icon).font(.caption2).foregroundStyle(.orange)
      Text(value).font(.callout.bold()).monospacedDigit()
      Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
  }

  private var header: some View {
    HStack {
      Label("Resume Studio", systemImage: "doc.text.fill")
        .font(.caption.bold())
      Spacer()
      Text("\(entry.resumeCompletion)%")
        .font(.caption.bold())
        .foregroundStyle(.orange)
    }
  }
}

struct ResumeStudioCareerWidget: Widget {
  let kind = "ResumeStudioCareerWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: ResumeStudioWidgetProvider()) { entry in
      ResumeStudioWidgetView(entry: entry)
    }
    .configurationDisplayName("Career Momentum")
    .description("See application progress, offers, your next interview and trackable-link opens.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

@main
struct ResumeStudioWidgetBundle: WidgetBundle {
  var body: some Widget {
    ResumeStudioCareerWidget()
    InterviewLiveActivity()
  }
}
