import SwiftUI
import WidgetKit

private let appGroup = "group.com.halalisanimbanjwa.ResumeStudio"

struct ResumeStudioWidgetEntry: TimelineEntry {
  let date: Date
  let tracked: Int
  let interviews: Int
  let offers: Int
  let resumeCompletion: Int
  let nextRole: String
  let nextCompany: String
  let nextDate: Date?
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
      nextDate: .now.addingTimeInterval(86_400))
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
    return ResumeStudioWidgetEntry(
      date: .now,
      tracked: defaults?.integer(forKey: "widgetTracked") ?? 0,
      interviews: defaults?.integer(forKey: "widgetInterviews") ?? 0,
      offers: defaults?.integer(forKey: "widgetOffers") ?? 0,
      resumeCompletion: defaults?.integer(forKey: "widgetResumeCompletion") ?? 0,
      nextRole: defaults?.string(forKey: "widgetNextRole") ?? "",
      nextCompany: defaults?.string(forKey: "widgetNextCompany") ?? "",
      nextDate: nextTimestamp > 0 ? Date(timeIntervalSince1970: nextTimestamp) : nil)
  }
}

struct ResumeStudioWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: ResumeStudioWidgetEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Label("Resume Studio", systemImage: "doc.text.fill")
          .font(.caption.bold())
        Spacer()
        Text("\(entry.resumeCompletion)%")
          .font(.caption.bold())
          .foregroundStyle(.orange)
      }

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
    .containerBackground(for: .widget) {
      LinearGradient(colors: [Color(.systemBackground), .orange.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    .widgetURL(URL(string: entry.nextRole.isEmpty ? "resumestudio://applications" : "resumestudio://interviews"))
  }
}

struct ResumeStudioCareerWidget: Widget {
  let kind = "ResumeStudioCareerWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: ResumeStudioWidgetProvider()) { entry in
      ResumeStudioWidgetView(entry: entry)
    }
    .configurationDisplayName("Career Momentum")
    .description("See application progress, offers and your next interview.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

@main
struct ResumeStudioWidgetBundle: WidgetBundle {
  var body: some Widget {
    ResumeStudioCareerWidget()
  }
}
