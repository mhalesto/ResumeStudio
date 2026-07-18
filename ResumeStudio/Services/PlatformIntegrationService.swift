import EventKit
import Foundation
import UIKit
import WidgetKit

enum PlatformIntegrationError: LocalizedError {
  case calendarDenied
  case unavailable

  var errorDescription: String? {
    switch self {
    case .calendarDenied: "Calendar access was not granted. You can enable it in Settings."
    case .unavailable: "This action is not available on this device."
    }
  }
}

enum PlatformIntegrationService {
  static let appGroup = "group.com.halalisanimbanjwa.ResumeStudio"

  @MainActor
  static func addInterviewToCalendar(_ interview: InterviewEvent) async throws {
    let store = EKEventStore()
    let granted: Bool
    if #available(iOS 17, *) {
      granted = try await store.requestFullAccessToEvents()
    } else {
      granted = try await withCheckedThrowingContinuation { continuation in
        store.requestAccess(to: .event) { allowed, error in
          if let error { continuation.resume(throwing: error) }
          else { continuation.resume(returning: allowed) }
        }
      }
    }
    guard granted else { throw PlatformIntegrationError.calendarDenied }
    let event = EKEvent(eventStore: store)
    event.calendar = store.defaultCalendarForNewEvents
    event.title = "Interview: \(interview.role) at \(interview.company)"
    event.startDate = interview.scheduledAt
    event.endDate = interview.scheduledAt.addingTimeInterval(Double(max(interview.durationMinutes, 15)) * 60)
    event.location = interview.locationOrLink
    event.notes = [interview.preparationNotes, interview.interviewerNames.nilIfBlank.map { "Interviewers: \($0)" }]
      .compactMap { $0 }.filter { !$0.isBlank }.joined(separator: "\n\n")
    event.url = URL(string: "resumestudio://interviews")
    if interview.reminderEnabled { event.addAlarm(EKAlarm(relativeOffset: -86_400)) }
    try store.save(event, span: .thisEvent)
  }

  @MainActor
  static func addDeadlineToCalendar(_ application: JobApplication) async throws {
    guard let deadline = application.deadline else { throw PlatformIntegrationError.unavailable }
    let store = EKEventStore()
    let granted = try await store.requestFullAccessToEvents()
    guard granted else { throw PlatformIntegrationError.calendarDenied }
    let event = EKEvent(eventStore: store)
    event.calendar = store.defaultCalendarForNewEvents
    event.title = "Application deadline: \(application.role) at \(application.company)"
    event.startDate = deadline
    event.endDate = deadline.addingTimeInterval(3_600)
    event.notes = [application.notes.nilIfBlank, application.sourceURL.nilIfBlank]
      .compactMap { $0 }.joined(separator: "\n\n")
    event.url = URL(string: "resumestudio://applications")
    event.addAlarm(EKAlarm(relativeOffset: -86_400))
    try store.save(event, span: .thisEvent)
  }

  @MainActor
  static func openMail(subject: String, body: String, recipient: String = "") {
    var components = URLComponents()
    components.scheme = "mailto"
    components.path = recipient
    components.queryItems = [
      URLQueryItem(name: "subject", value: subject),
      URLQueryItem(name: "body", value: body),
    ]
    guard let url = components.url else { return }
    UIApplication.shared.open(url)
  }

  static func publishAutofillProfile(_ document: ResumeDocument) throws {
    guard let defaults = UserDefaults(suiteName: appGroup) else { throw PlatformIntegrationError.unavailable }
    let profile: [String: Any] = [
      "fullName": document.personal.fullName,
      "email": document.personal.email,
      "phone": document.personal.phone,
      "headline": document.personal.headline,
      "professionalProfile": document.professionalProfile,
      "skills": document.competencies,
      "updatedAt": Date().timeIntervalSince1970,
    ]
    defaults.set(try JSONSerialization.data(withJSONObject: profile), forKey: "safariAutofillProfile")
  }

  static func publishWidgetSnapshot(
    applications: [JobApplication],
    interviews: [InterviewEvent],
    resume: ResumeDocument,
    smartLinks: [SmartLink] = []
  ) {
    guard let defaults = UserDefaults(suiteName: appGroup) else { return }
    let next = interviews.filter { !$0.isPast }.sorted { $0.scheduledAt < $1.scheduledAt }.first
    defaults.set(applications.count, forKey: "widgetTracked")
    defaults.set(applications.count { $0.status == .interview }, forKey: "widgetInterviews")
    defaults.set(applications.count { $0.status == .offer }, forKey: "widgetOffers")
    defaults.set(resume.completionPercentage, forKey: "widgetResumeCompletion")
    defaults.set(next?.role ?? "", forKey: "widgetNextRole")
    defaults.set(next?.company ?? "", forKey: "widgetNextCompany")
    defaults.set(next?.scheduledAt.timeIntervalSince1970 ?? 0, forKey: "widgetNextDate")

    // Trackable-links ("Smart Links") stats power the large widget's dashboard
    // and its last-7-days opens graph.
    defaults.set(smartLinks.count(where: \.isActive), forKey: "widgetLinksActive")
    defaults.set(smartLinks.reduce(0) { $0 + $1.totalOpens }, forKey: "widgetLinkOpens")
    defaults.set(smartLinks.reduce(0) { $0 + $1.totalSeconds } / 60, forKey: "widgetLinkReadMinutes")
    defaults.set(smartLinks.reduce(0) { $0 + $1.totalDownloads }, forKey: "widgetLinkDownloads")
    let trend = widgetLinkTrend(from: smartLinks, days: 7)
    defaults.set(trend.map(\.opens), forKey: "widgetLinkTrendOpens")
    defaults.set(trend.map(\.label), forKey: "widgetLinkTrendLabels")

    WidgetCenter.shared.reloadAllTimelines()
  }

  /// Total opens per calendar day for the last `days` days (oldest first),
  /// labelled with a single-letter weekday for the widget's bar chart.
  private static func widgetLinkTrend(
    from links: [SmartLink], days: Int
  ) -> [(label: String, opens: Int)] {
    var opensByDay: [String: Int] = [:]
    for activity in links.flatMap(\.dailyActivity) {
      opensByDay[activity.day, default: 0] += activity.opens
    }
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let formatter = DateFormatter()
    formatter.dateFormat = "EEEEE" // single-letter weekday
    return (0..<days).compactMap { offset in
      guard let date = calendar.date(byAdding: .day, value: offset - days + 1, to: today)
      else { return nil }
      let components = calendar.dateComponents([.year, .month, .day], from: date)
      guard let year = components.year, let month = components.month, let day = components.day
      else { return nil }
      let key = String(format: "%04d-%02d-%02d", year, month, day)
      return (formatter.string(from: date), opensByDay[key] ?? 0)
    }
  }
}

enum ShortcutRouteStore {
  private static let key = "ResumeStudio.pendingShortcutRoute"

  static func queue(_ route: String) {
    UserDefaults.standard.set(route, forKey: key)
    NotificationCenter.default.post(name: .shortcutRouteQueued, object: nil)
  }

  static func consume() -> String? {
    guard let route = UserDefaults.standard.string(forKey: key) else { return nil }
    UserDefaults.standard.removeObject(forKey: key)
    return route
  }
}

extension Notification.Name {
  static let shortcutRouteQueued = Notification.Name("ResumeStudio.shortcutRouteQueued")
}
