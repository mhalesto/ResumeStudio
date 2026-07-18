import Charts
import SwiftUI
import UIKit

private enum SmartLinkChartRange: String, CaseIterable, Identifiable {
  case week = "7D"
  case month = "30D"
  case quarter = "90D"
  case all = "All"

  var id: Self { self }
  var days: Int? {
    switch self {
    case .week: 7
    case .month: 30
    case .quarter: 90
    case .all: nil
    }
  }
}

private enum SmartLinkChartMetric: String, CaseIterable, Identifiable {
  case opens = "Opens"
  case reading = "Read time"
  case downloads = "PDF saves"

  var id: Self { self }
  var icon: String {
    switch self {
    case .opens: "eye"
    case .reading: "clock"
    case .downloads: "arrow.down.circle"
    }
  }

  func value(_ point: SmartLinkChartPoint) -> Double {
    switch self {
    case .opens: Double(point.opens)
    case .reading: Double(point.seconds) / 60
    case .downloads: Double(point.downloads)
    }
  }

  func formatted(_ point: SmartLinkChartPoint) -> String {
    switch self {
    case .opens: "\(point.opens) open\(point.opens == 1 ? "" : "s")"
    case .reading: "\(readingTime(point.seconds)) read"
    case .downloads: "\(point.downloads) save\(point.downloads == 1 ? "" : "s")"
    }
  }
}

private enum SmartLinkChartStyle: String, CaseIterable, Identifiable {
  case bars = "Bars"
  case line = "Line"
  case area = "Area"

  var id: Self { self }
  var icon: String {
    switch self {
    case .bars: "chart.bar"
    case .line: "chart.xyaxis.line"
    case .area: "chart.line.uptrend.xyaxis"
    }
  }
}

private enum SmartLinkListScope: String, CaseIterable, Identifiable {
  case all = "All links"
  case live = "Live"
  case engaged = "Opened"
  case waiting = "Waiting"

  var id: Self { self }
}

private enum SmartLinkListSort: String, CaseIterable, Identifiable {
  case recent = "Recent activity"
  case engaged = "Most read"
  case newest = "Newest"

  var id: Self { self }
}

private struct SmartLinkChartPoint: Identifiable {
  var day: String
  var date: Date
  var opens: Int
  var seconds: Int
  var downloads: Int

  var id: String { day }
}

/// The trackable-links surface: every hosted résumé link, who opened it, and
/// for how long it was read. The list is the pipeline view; the payoff moments
/// arrive as notifications from `SmartLinkStore.refresh()`.
struct SmartLinksView: View {
  @EnvironmentObject private var store: ResumeStore
  @EnvironmentObject private var smartLinks: SmartLinkStore
  @State private var isCreating = false
  @State private var chartRange: SmartLinkChartRange = .week
  @State private var chartMetric: SmartLinkChartMetric = .opens
  @State private var chartStyle: SmartLinkChartStyle = .bars
  @State private var listScope: SmartLinkListScope = .all
  @State private var listSort: SmartLinkListSort = .recent

  private var accent: Color { store.document.accent.color }
  private var scopedLinks: [SmartLink] {
    smartLinks.links.filter { link in
      switch listScope {
      case .all: true
      case .live: link.isActive
      case .engaged: link.totalOpens > 0
      case .waiting: link.totalOpens == 0
      }
    }
  }
  private var displayedLinks: [SmartLink] {
    scopedLinks.sorted { lhs, rhs in
      switch listSort {
      case .recent:
        (lhs.lastSeenAt ?? lhs.createdAt) > (rhs.lastSeenAt ?? rhs.createdAt)
      case .engaged:
        lhs.totalSeconds == rhs.totalSeconds
          ? lhs.totalOpens > rhs.totalOpens
          : lhs.totalSeconds > rhs.totalSeconds
      case .newest: lhs.createdAt > rhs.createdAt
      }
    }
  }
  private var chartPoints: [SmartLinkChartPoint] {
    makeSmartLinkChartPoints(links: scopedLinks, range: chartRange)
  }
  private var totalOpens: Int { smartLinks.links.reduce(0) { $0 + $1.totalOpens } }
  private var totalSeconds: Int { smartLinks.links.reduce(0) { $0 + $1.totalSeconds } }
  private var totalDownloads: Int { smartLinks.links.reduce(0) { $0 + $1.totalDownloads } }

  var body: some View {
    ScrollView {
      if smartLinks.links.isEmpty {
        emptyState
      } else {
        VStack(alignment: .leading, spacing: 18) {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
            summaryMetric("\(smartLinks.activeCount)", "Live", "dot.radiowaves.left.and.right")
            summaryMetric("\(totalOpens)", "Opens", "eye")
            summaryMetric(readingTime(totalSeconds), "Read", "clock")
            summaryMetric("\(totalDownloads)", "PDF saves", "arrow.down.circle")
          }

          SmartLinkTrendCard(
            points: chartPoints,
            range: $chartRange,
            metric: $chartMetric,
            style: $chartStyle,
            accent: accent
          )

          if let insight = SmartLinkInsight.best(from: smartLinks.links) {
            SmartLinkInsightCard(insight: insight, accent: accent)
          }

          HStack(alignment: .firstTextBaseline) {
            Text("Your links")
              .font(Theme.display(25))
            Spacer()
            Menu {
              Picker("Show", selection: $listScope) {
                ForEach(SmartLinkListScope.allCases) { Text($0.rawValue).tag($0) }
              }
              Picker("Sort", selection: $listSort) {
                ForEach(SmartLinkListSort.allCases) { Text($0.rawValue).tag($0) }
              }
            } label: {
              Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                .font(.subheadline.weight(.semibold))
            }
          }

          if displayedLinks.isEmpty {
            ContentUnavailableView(
              "No matching links",
              systemImage: "line.3.horizontal.decrease.circle",
              description: Text("Choose a different link filter.")
            )
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity)
            .cardSurface()
          } else {
            VStack(spacing: 0) {
              ForEach(Array(displayedLinks.enumerated()), id: \.element.id) { index, link in
                NavigationLink {
                  SmartLinkDetailView(link: link)
                } label: {
                  SmartLinkRow(link: link, accent: accent)
                }
                .buttonStyle(.plain)
                if index < displayedLinks.count - 1 {
                  Divider().padding(.leading, 47)
                }
              }
            }
            .padding(.horizontal, 16)
            .cardSurface()
          }

          if let error = smartLinks.lastRefreshError {
            Label(error, systemImage: "exclamationmark.triangle")
              .font(.caption)
              .foregroundStyle(.orange)
          }

          Label(
            "Anonymous by design: no names, locations, or IP addresses are shown or retained in your analytics.",
            systemImage: "hand.raised.fill"
          )
          .font(.caption)
          .foregroundStyle(Theme.mutedInk)
        }
        .padding(20)
        .padding(.bottom, 30)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
      }
    }
    .background(Theme.paper)
    .navigationTitle("Trackable links")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          isCreating = true
        } label: {
          Image(systemName: "plus")
        }
        .accessibilityLabel("Create trackable link")
      }
    }
    .refreshable { await smartLinks.refresh(force: true) }
    .task {
      await smartLinks.recoverHostedLinks()
      await smartLinks.refresh(force: true)
    }
    .sheet(isPresented: $isCreating) {
      NavigationStack { CreateSmartLinkSheet() }
    }
  }

  private var emptyState: some View {
    VStack(alignment: .leading, spacing: 12) {
      Image(systemName: "chart.xyaxis.line")
        .font(.title2.weight(.semibold))
        .foregroundStyle(accent)
        .padding(12)
        .background(accent.opacity(0.12), in: Circle())
      Text("Know when you're read")
        .font(Theme.display(30))
      Text("Send a link instead of an attachment. See meaningful opens, visible reading time, PDF saves, and daily engagement trends.")
        .font(.subheadline)
        .foregroundStyle(Theme.inkSoft)
      Text("Viewers are anonymous, and the shared page tells them that engagement is measured.")
        .font(.caption)
        .foregroundStyle(Theme.mutedInk)
      Button {
        isCreating = true
      } label: {
        Label("Create your first link", systemImage: "link.badge.plus")
          .font(.headline)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 6)
      }
      .buttonStyle(.borderedProminent)
      .tint(accent)
      .padding(.top, 6)
      if smartLinks.isRecovering {
        HStack(spacing: 8) {
          ProgressView()
          Text("Checking for your hosted links…")
        }
        .font(.caption)
        .foregroundStyle(Theme.mutedInk)
        .frame(maxWidth: .infinity)
      } else if let error = smartLinks.lastRefreshError {
        VStack(alignment: .leading, spacing: 7) {
          Text(error).font(.caption).foregroundStyle(.orange)
          Button("Check again") {
            Task { await smartLinks.recoverHostedLinks() }
          }
          .font(.caption.weight(.semibold))
        }
      }
    }
    .padding(22)
    .cardSurface()
    .padding(20)
    .frame(maxWidth: 620)
    .frame(maxWidth: .infinity)
  }

  private func summaryMetric(_ value: String, _ label: String, _ icon: String) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack {
        Image(systemName: icon).foregroundStyle(accent)
        Spacer()
        Text(label).eyebrow().foregroundStyle(Theme.mutedInk)
      }
      Text(value)
        .font(.title2.bold().monospacedDigit())
        .foregroundStyle(Theme.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
    .padding(15)
    .cardSurface(radius: 18)
  }
}

private struct SmartLinkTrendCard: View {
  let points: [SmartLinkChartPoint]
  @Binding var range: SmartLinkChartRange
  @Binding var metric: SmartLinkChartMetric
  @Binding var style: SmartLinkChartStyle
  let accent: Color

  @State private var selectedDate: Date?

  private var selectedPoint: SmartLinkChartPoint? {
    guard let selectedDate else { return nil }
    return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
  }
  private var axisStride: Int {
    switch range {
    case .week: 1
    case .month: 7
    case .quarter: 14
    case .all: max(1, points.count / 5)
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Engagement trend")
            .font(.title3.bold())
          Text(metric.rawValue)
            .font(.caption)
            .foregroundStyle(Theme.mutedInk)
        }
        Spacer()
        Menu {
          Picker("Metric", selection: $metric) {
            ForEach(SmartLinkChartMetric.allCases) { option in
              Label(option.rawValue, systemImage: option.icon).tag(option)
            }
          }
        } label: {
          Label(metric.rawValue, systemImage: metric.icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.muted, in: Capsule())
        }
        .accessibilityLabel("Chart metric: \(metric.rawValue)")

        Menu {
          Picker("Graph type", selection: $style) {
            ForEach(SmartLinkChartStyle.allCases) { option in
              Label(option.rawValue, systemImage: option.icon).tag(option)
            }
          }
        } label: {
          Image(systemName: style.icon)
            .font(.subheadline.weight(.semibold))
            .frame(width: 34, height: 34)
            .background(Theme.muted, in: Circle())
        }
        .accessibilityLabel("Graph type: \(style.rawValue)")
      }

      Picker("Date range", selection: $range) {
        ForEach(SmartLinkChartRange.allCases) { Text($0.rawValue).tag($0) }
      }
      .pickerStyle(.segmented)

      if points.isEmpty {
        VStack(spacing: 9) {
          Image(systemName: "chart.bar.xaxis")
            .font(.title2)
            .foregroundStyle(accent)
          Text("Daily trends start with the next open")
            .font(.subheadline.weight(.semibold))
          Text("Lifetime totals stay above; new activity will build the day-by-day view here.")
            .font(.caption)
            .foregroundStyle(Theme.mutedInk)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 190)
      } else {
        Chart {
          ForEach(points) { point in
            switch style {
            case .bars:
              BarMark(
                x: .value("Day", point.date, unit: .day),
                y: .value(metric.rawValue, metric.value(point))
              )
              .foregroundStyle(accent.gradient)
              .cornerRadius(4)
            case .line:
              LineMark(
                x: .value("Day", point.date),
                y: .value(metric.rawValue, metric.value(point))
              )
              .foregroundStyle(accent)
              .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
              .interpolationMethod(.catmullRom)
              PointMark(
                x: .value("Day", point.date),
                y: .value(metric.rawValue, metric.value(point))
              )
              .foregroundStyle(accent)
            case .area:
              AreaMark(
                x: .value("Day", point.date),
                y: .value(metric.rawValue, metric.value(point))
              )
              .foregroundStyle(
                LinearGradient(
                  colors: [accent.opacity(0.5), accent.opacity(0.04)],
                  startPoint: .top,
                  endPoint: .bottom
                )
              )
              .interpolationMethod(.catmullRom)
              LineMark(
                x: .value("Day", point.date),
                y: .value(metric.rawValue, metric.value(point))
              )
              .foregroundStyle(accent)
              .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
              .interpolationMethod(.catmullRom)
            }
          }

          if let selectedPoint {
            RuleMark(x: .value("Selected day", selectedPoint.date))
              .foregroundStyle(Theme.mutedInk.opacity(0.55))
              .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
              .annotation(position: .top, spacing: 5) {
                VStack(alignment: .leading, spacing: 2) {
                  Text(selectedPoint.date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.caption2)
                    .foregroundStyle(Theme.mutedInk)
                  Text(metric.formatted(selectedPoint))
                    .font(.caption.bold())
                    .foregroundStyle(Theme.ink)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
              }
          }
        }
        .chartXAxis {
          AxisMarks(values: .stride(by: .day, count: axisStride)) { _ in
            AxisGridLine().foregroundStyle(Theme.hairline.opacity(0.6))
            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
          }
        }
        .chartYAxis {
          AxisMarks(position: .leading) { _ in
            AxisGridLine().foregroundStyle(Theme.hairline.opacity(0.6))
            AxisValueLabel()
          }
        }
        .chartXSelection(value: $selectedDate)
        .frame(height: 220)
        .onChange(of: range) { selectedDate = nil }
        .onChange(of: metric) { selectedDate = nil }
      }

      HStack(spacing: 5) {
        Image(systemName: "hand.draw")
        Text("Drag across the graph to inspect a day.")
      }
      .font(.caption2)
      .foregroundStyle(Theme.mutedInk)
    }
    .padding(18)
    .cardSurface()
  }
}

private struct SmartLinkInsight {
  var icon: String
  var title: String
  var message: String

  static func best(from links: [SmartLink]) -> SmartLinkInsight? {
    if let new = links.filter({ $0.unseenOpens > 0 })
      .max(by: { ($0.lastSeenAt ?? .distantPast) < ($1.lastSeenAt ?? .distantPast) }) {
      let label = new.company.nilIfBlank ?? new.title
      return SmartLinkInsight(
        icon: "bell.badge.fill",
        title: "Fresh activity",
        message: "\(label) has \(new.unseenOpens) new open\(new.unseenOpens == 1 ? "" : "s"). This is a timely moment to review the detail and consider following up."
      )
    }

    if let engaged = links.filter({ $0.totalSeconds > 0 })
      .max(by: { $0.totalSeconds < $1.totalSeconds }) {
      let label = engaged.company.nilIfBlank ?? engaged.title
      let repeatSignal = engaged.totalOpens > 1
        ? " across \(engaged.totalOpens) opens"
        : ""
      return SmartLinkInsight(
        icon: "sparkles",
        title: "Most engaged link",
        message: "\(label) leads with \(readingTime(engaged.totalSeconds)) of visible reading\(repeatSignal). Treat it as a follow-up signal, not proof of intent."
      )
    }

    if links.contains(where: { $0.isActive }) {
      return SmartLinkInsight(
        icon: "paperplane.fill",
        title: "Ready to measure",
        message: "Your link is live. Share it directly with the intended reader; the first meaningful open will appear here."
      )
    }
    return nil
  }
}

private struct SmartLinkInsightCard: View {
  let insight: SmartLinkInsight
  let accent: Color

  var body: some View {
    HStack(alignment: .top, spacing: 13) {
      Image(systemName: insight.icon)
        .font(.headline)
        .foregroundStyle(accent)
        .frame(width: 38, height: 38)
        .background(accent.opacity(0.12), in: Circle())
      VStack(alignment: .leading, spacing: 4) {
        Text(insight.title).font(.subheadline.bold())
        Text(insight.message)
          .font(.caption)
          .foregroundStyle(Theme.inkSoft)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .strokeBorder(accent.opacity(0.18))
    }
  }
}

private func makeSmartLinkChartPoints(
  links: [SmartLink], range: SmartLinkChartRange
) -> [SmartLinkChartPoint] {
  var totals: [String: (opens: Int, seconds: Int, downloads: Int)] = [:]
  for activity in links.flatMap(\.dailyActivity) {
    let current = totals[activity.day] ?? (0, 0, 0)
    totals[activity.day] = (
      current.opens + activity.opens,
      current.seconds + activity.seconds,
      current.downloads + activity.downloads
    )
  }

  let calendar = Calendar.current
  let today = calendar.startOfDay(for: Date())
  let days: [(String, Date)]
  if let count = range.days {
    days = (0..<count).compactMap { offset in
      guard let date = calendar.date(byAdding: .day, value: offset - count + 1, to: today)
      else { return nil }
      let components = calendar.dateComponents([.year, .month, .day], from: date)
      guard let year = components.year, let month = components.month, let day = components.day
      else { return nil }
      return (String(format: "%04d-%02d-%02d", year, month, day), date)
    }
  } else {
    days = totals.keys.sorted().compactMap { day in
      guard let date = SmartLinkDailyActivity(day: day, opens: 0, seconds: 0, downloads: 0).date
      else { return nil }
      return (day, date)
    }
  }

  guard !totals.isEmpty else { return [] }
  return days.map { day, date in
    let total = totals[day] ?? (0, 0, 0)
    return SmartLinkChartPoint(
      day: day,
      date: date,
      opens: total.opens,
      seconds: total.seconds,
      downloads: total.downloads
    )
  }
}

struct SmartLinkRow: View {
  let link: SmartLink
  let accent: Color

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Circle()
        .fill(statusColor)
        .frame(width: 9, height: 9)
        .padding(.top, 7)
      VStack(alignment: .leading, spacing: 3) {
        Text(link.company.isBlank ? link.title : link.company)
          .font(.headline)
          .foregroundStyle(Theme.ink)
        Text(summary)
          .font(.caption)
          .foregroundStyle(Theme.mutedInk)
      }
      Spacer()
      HStack(spacing: 7) {
        if link.unseenOpens > 0 {
          Text("\(link.unseenOpens) new")
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(accent, in: Capsule())
            .foregroundStyle(.white)
        }
        Image(systemName: "chevron.right")
          .font(.caption.bold())
          .foregroundStyle(Theme.mutedInk.opacity(0.7))
      }
    }
    .padding(.vertical, 14)
    .contentShape(Rectangle())
  }

  private var statusColor: Color {
    switch link.status {
    case .open: link.isActive ? .green : .orange
    case .expired: .orange
    case .revoked: .secondary
    }
  }

  private var summary: String {
    var parts: [String] = []
    if !link.isActive { parts.append(link.status == .revoked ? "Revoked" : "Expired") }
    parts.append("\(link.totalOpens) open\(link.totalOpens == 1 ? "" : "s")")
    if link.totalSeconds > 0 { parts.append("\(readingTime(link.totalSeconds)) read") }
    if link.totalDownloads > 0 {
      parts.append("\(link.totalDownloads) PDF save\(link.totalDownloads == 1 ? "" : "s")")
    }
    if let seen = link.lastSeenAt {
      parts.append("last \(seen.formatted(.relative(presentation: .named)))")
    }
    return parts.joined(separator: " · ")
  }
}

/// One link's full story: every visitor, opens, honest reading time, and the
/// controls that end it. Opening this screen acknowledges the activity.
struct SmartLinkDetailView: View {
  @EnvironmentObject private var store: ResumeStore
  @EnvironmentObject private var smartLinks: SmartLinkStore
  @Environment(\.dismiss) private var dismiss
  let link: SmartLink

  @State private var isWorking = false
  @State private var errorMessage: String?
  @State private var confirmRevoke = false
  @State private var confirmDelete = false
  @State private var chartRange: SmartLinkChartRange = .month
  @State private var chartMetric: SmartLinkChartMetric = .opens
  @State private var chartStyle: SmartLinkChartStyle = .bars

  private var accent: Color { store.document.accent.color }
  private var current: SmartLink { smartLinks.links.first { $0.id == link.id } ?? link }
  private var chartPoints: [SmartLinkChartPoint] {
    makeSmartLinkChartPoints(links: [current], range: chartRange)
  }
  /// Reconstructed from the token so links saved before the backend URL fix
  /// still share a URL that resolves.
  private var shareURL: URL? {
    guard current.canShare else { return nil }
    return SmartLinkService.viewerURL(token: current.token) ?? current.url
  }

  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 6) {
          Text(current.title).font(.headline)
          if !current.company.isBlank {
            Text("Sent to \(current.company)").font(.subheadline).foregroundStyle(Theme.inkSoft)
          }
          Text("\(current.status.title) · expires \(current.expiresAt.formatted(date: .abbreviated, time: .omitted))")
            .font(.caption)
            .foregroundStyle(Theme.mutedInk)
        }
        .padding(.vertical, 2)
        if current.isActive, let shareURL {
          ShareLink(item: shareURL) {
            Label("Share link", systemImage: "square.and.arrow.up")
          }
          Button {
            UIPasteboard.general.string = shareURL.absoluteString
          } label: {
            Label("Copy link", systemImage: "doc.on.doc")
          }
        } else if current.isActive && !current.canShare {
          Label(
            "Activity recovered. The original share address was not stored by the older server, so create a replacement if you need to share it again.",
            systemImage: "arrow.clockwise.icloud"
          )
          .font(.caption)
          .foregroundStyle(Theme.mutedInk)
        }
      }

      Section {
        HStack(spacing: 8) {
          detailMetric("\(current.totalOpens)", "Opens")
          detailMetric(readingTime(current.totalSeconds), "Read")
          detailMetric("\(current.totalDownloads)", "PDF saves")
        }
        .padding(.vertical, 4)
      }

      Section {
        SmartLinkTrendCard(
          points: chartPoints,
          range: $chartRange,
          metric: $chartMetric,
          style: $chartStyle,
          accent: accent
        )
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
      }

      Section {
        if current.views.isEmpty {
          Text("No opens yet. You'll get a notification the moment it happens.")
            .font(.subheadline)
            .foregroundStyle(Theme.mutedInk)
        }
        ForEach(current.views) { view in
          HStack(alignment: .top, spacing: 12) {
            Image(systemName: deviceIcon(view.viewer))
              .foregroundStyle(accent)
              .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
              Text(view.viewer).font(.subheadline.weight(.semibold))
              Text(viewSummary(view))
                .font(.caption)
                .foregroundStyle(Theme.mutedInk)
              if view.downloadedPDF {
                Label("Downloaded the PDF", systemImage: "arrow.down.circle.fill")
                  .font(.caption2.weight(.semibold))
                  .foregroundStyle(accent)
              }
            }
          }
          .padding(.vertical, 2)
        }
      } header: {
        Text("Reading activity")
      } footer: {
        Text("Viewers are counted by device, never identified. Reading time only accrues while the page is actually visible.")
      }

      Section {
        if current.isActive {
          Button(role: .destructive) {
            confirmRevoke = true
          } label: {
            Label("Revoke link", systemImage: "xmark.circle")
          }
          .disabled(isWorking)
        }
        Button(role: .destructive) {
          confirmDelete = true
        } label: {
          Label("Delete link and its history", systemImage: "trash")
        }
        .disabled(isWorking)
      } footer: {
        if let errorMessage {
          Text(errorMessage).foregroundStyle(.orange)
        } else {
          Text("Revoking stops the link working immediately. Deleting also removes its reading history everywhere.")
        }
      }
    }
    .navigationTitle("Link activity")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { smartLinks.acknowledge(link.id) }
    .confirmationDialog("Revoke this link?", isPresented: $confirmRevoke, titleVisibility: .visible) {
      Button("Revoke link", role: .destructive) {
        Task {
          isWorking = true
          defer { isWorking = false }
          do { try await smartLinks.revoke(link.id) } catch { errorMessage = error.localizedDescription }
        }
      }
    } message: {
      Text("Anyone opening it will see that the résumé is no longer available.")
    }
    .confirmationDialog("Delete this link?", isPresented: $confirmDelete, titleVisibility: .visible) {
      Button("Delete link", role: .destructive) {
        Task {
          isWorking = true
          await smartLinks.delete(link.id)
          isWorking = false
          dismiss()
        }
      }
    } message: {
      Text("The hosted PDF and all reading history are removed.")
    }
  }

  private func detailMetric(_ value: String, _ label: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(value)
        .font(.headline.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      Text(label).eyebrow().foregroundStyle(Theme.mutedInk)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func viewSummary(_ view: SmartLinkView) -> String {
    var parts = ["\(view.opens) open\(view.opens == 1 ? "" : "s")"]
    if view.seconds > 0 { parts.append("\(readingTime(view.seconds)) read") }
    if let seen = view.lastSeenAt {
      parts.append("last \(seen.formatted(.relative(presentation: .named)))")
    }
    return parts.joined(separator: " · ")
  }

  private func deviceIcon(_ hint: String) -> String {
    if hint.contains("iPhone") || hint.contains("Android") { return "iphone" }
    if hint.contains("iPad") { return "ipad" }
    if hint.contains("Mac") { return "laptopcomputer" }
    if hint.contains("Windows") || hint.contains("Linux") { return "desktopcomputer" }
    return "eye"
  }
}

/// Publishes the current résumé behind a fresh trackable link.
struct CreateSmartLinkSheet: View {
  @EnvironmentObject private var store: ResumeStore
  @EnvironmentObject private var smartLinks: SmartLinkStore
  @EnvironmentObject private var purchases: PurchaseManager
  @Environment(\.dismiss) private var dismiss

  @State private var company = ""
  @State private var expiryDays = 30
  @State private var isPublishing = false
  @State private var errorMessage: String?
  @State private var canUpgrade = false
  @State private var canRefreshAccess = false
  @State private var publishedURL: URL?

  private var accent: Color { store.document.accent.color }
  private var allowance: Int { purchases.plan.smartLinkLimit }
  private var atCap: Bool { smartLinks.activeCount >= allowance }

  var body: some View {
    Form {
      if let publishedURL {
        Section {
          VStack(alignment: .leading, spacing: 8) {
            Label("Your link is live", systemImage: "checkmark.circle.fill")
              .font(.headline)
              .foregroundStyle(.green)
            Text(publishedURL.absoluteString)
              .font(.footnote.monospaced())
              .foregroundStyle(Theme.inkSoft)
              .textSelection(.enabled)
          }
          .padding(.vertical, 4)
          ShareLink(item: publishedURL) {
            Label("Share link", systemImage: "square.and.arrow.up")
          }
          Button {
            UIPasteboard.general.string = publishedURL.absoluteString
          } label: {
            Label("Copy link", systemImage: "doc.on.doc")
          }
        } footer: {
          Text("You'll be notified the first time it's opened. Activity lives in Trackable links.")
        }
      } else {
        Section {
          TextField("Company or recruiter (for your eyes only)", text: $company)
          Picker("Link expires in", selection: $expiryDays) {
            Text("30 days").tag(30)
            Text("60 days").tag(60)
            Text("90 days").tag(90)
          }
        } header: {
          Text("New trackable link")
        } footer: {
          Text("Hosts “\(store.document.suggestedFilename).pdf” behind a private link. The viewer page says opens are visible to you.")
        }

        Section {
          Button {
            publish()
          } label: {
            if isPublishing {
              HStack(spacing: 10) {
                ProgressView()
                Text("Publishing…")
              }
            } else {
              Label("Create link", systemImage: "link.badge.plus")
                .font(.headline)
            }
          }
          .disabled(isPublishing || atCap)
        } footer: {
          VStack(alignment: .leading, spacing: 6) {
            // The server enforces the plan (and rejects unverifiable purchases),
            // so its message is authoritative. Showing the client-side "X of Y
            // on your plan" line beside it contradicted the error — hide it
            // whenever the server has spoken.
            if let errorMessage {
              Text(errorMessage).foregroundStyle(.orange)
              if canUpgrade {
                Button("See plans") {
                  openPlansAfterDismiss()
                }
                .font(.footnote.weight(.semibold))
              } else if canRefreshAccess {
                Button("Refresh App Store access") { refreshPaidAccess() }
                  .font(.footnote.weight(.semibold))
              }
            } else if atCap {
              Text(allowance == 1
                ? "Free hosts one active link — revoke the current one, or upgrade for more."
                : "Your plan supports \(allowance) active links. Revoke one to create another.")
              Button("See plans") {
                openPlansAfterDismiss()
              }
              .font(.footnote.weight(.semibold))
            } else {
              Text("\(smartLinks.activeCount) of \(allowance) active links on your plan.")
            }
          }
        }
      }
    }
    .navigationTitle("Trackable link")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button(publishedURL == nil ? "Cancel" : "Done") { dismiss() }
      }
    }
  }

  private func publish() {
    isPublishing = true
    errorMessage = nil
    canUpgrade = false
    canRefreshAccess = false
    let document = store.document
    let company = company
    let expiry = Date(timeIntervalSinceNow: TimeInterval(expiryDays) * 86_400)
    Task {
      defer { isPublishing = false }
      do {
        await purchases.refreshEntitlements()
        let proof = purchases.entitlementProof()
        if purchases.plan != .free && proof.signedTransaction == nil {
          errorMessage = "Your \(purchases.plan.title) access is active on this device, but hosted features still need a fresh App Store verification. Refresh access and try again."
          canRefreshAccess = true
          return
        }
        let pdf = try ResumePDFRenderer.render(document: document)
        let pageImages = ResumePageRasterizer.images(fromPDF: pdf)
        let token = SmartLink.newToken()
        let published = try await SmartLinkService().publish(SmartLinkService.PublishRequest(
          token: token,
          title: document.suggestedFilename,
          company: company,
          expiresAt: expiry,
          pdfData: pdf,
          pageImages: pageImages
        ))
        // Prefer the token-derived URL so the saved link never inherits a
        // malformed origin from the backend response.
        let url = SmartLinkService.viewerURL(token: token) ?? published.url
        smartLinks.add(SmartLink(
          remoteID: published.remoteID,
          token: token,
          url: url,
          title: document.suggestedFilename,
          company: company,
          createdAt: Date(),
          expiresAt: expiry
        ))
        publishedURL = url
      } catch {
        if (error as? SmartLinkError)?.suggestsUpgrade == true, purchases.plan != .free {
          errorMessage = "ResumeStudio recognizes your \(purchases.plan.title) plan, but the hosted-link service could not verify it. Refresh App Store access and try again."
          canRefreshAccess = true
        } else {
          errorMessage = error.localizedDescription
          canUpgrade = (error as? SmartLinkError)?.suggestsUpgrade ?? false
        }
      }
    }
  }

  private func refreshPaidAccess() {
    isPublishing = true
    errorMessage = nil
    canRefreshAccess = false
    Task {
      await purchases.restorePurchases()
      isPublishing = false
      let verified = purchases.entitlementProof().signedTransaction != nil
      if verified {
        errorMessage = "\(purchases.plan.title) access refreshed. You can create the link now."
      } else {
        errorMessage = "The App Store has not returned a server-verifiable subscription yet. Check your connection, then try again."
        canRefreshAccess = true
      }
    }
  }

  private func openPlansAfterDismiss() {
    dismiss()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
      NotificationCenter.default.post(name: .presentPlans, object: nil)
    }
  }
}

private func readingTime(_ seconds: Int) -> String {
  if seconds >= 60 { return "\(seconds / 60)m \(seconds % 60)s" }
  return "\(seconds)s"
}

extension ResumeStudioPlan {
  /// Active hosted trackable links per plan. Enforced by the backend; shown
  /// here so the cap never surprises anyone.
  var smartLinkLimit: Int {
    switch self {
    case .free: 1
    case .go: 5
    case .pro: 25
    }
  }
}

#Preview {
  NavigationStack {
    SmartLinksView()
      .environmentObject(ResumeStore())
      .environmentObject(SmartLinkStore())
      .environmentObject(PurchaseManager.shared)
  }
}
