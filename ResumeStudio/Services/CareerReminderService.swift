import EventKit
import Foundation
import UserNotifications

enum CareerReminderService {
  static func cancel(contactID: UUID) {
    cancel("contact-follow-up-\(contactID.uuidString)")
  }

  static func schedule(contact: CareerContact) async throws {
    let identifier = "contact-follow-up-\(contact.id.uuidString)"
    cancel(identifier)
    guard let date = contact.followUpAt, date > Date() else { return }
    try await schedule(
      identifier: identifier,
      title: "Follow up with \(contact.name)",
      body: [contact.role, contact.company].filter { !$0.isBlank }.joined(separator: " at "),
      date: date,
      userInfo: ["contactID": contact.id.uuidString]
    )
  }

  static func schedule(application: JobApplication) async throws {
    let identifier = "application-deadline-\(application.id.uuidString)"
    cancel(identifier)
    guard let deadline = application.deadline, deadline > Date() else { return }
    let advance = Calendar.current.date(byAdding: .day, value: -3, to: deadline) ?? deadline
    let date = advance > Date() ? advance : deadline.addingTimeInterval(-3600)
    guard date > Date() else { return }
    try await schedule(
      identifier: identifier,
      title: "Application deadline approaching",
      body: [application.role, application.company].filter { !$0.isBlank }.joined(separator: " at "),
      date: date,
      userInfo: ["applicationID": application.id.uuidString]
    )
  }

  private static func schedule(
    identifier: String, title: String, body: String, date: Date, userInfo: [AnyHashable: Any]
  ) async throws {
    let center = UNUserNotificationCenter.current()
    let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
    guard granted else { throw ReminderError.permissionDenied }
    let content = UNMutableNotificationContent()
    content.title = title; content.body = body; content.sound = .default; content.userInfo = userInfo
    let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    try await center.add(UNNotificationRequest(
      identifier: identifier,
      content: content,
      trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    ))
  }

  private static func cancel(_ identifier: String) {
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
  }
}

enum CareerCalendarService {
  static func addInterview(_ interview: InterviewEvent) async throws {
    let store = EKEventStore()
    let granted = try await store.requestFullAccessToEvents()
    guard granted else { throw CalendarError.permissionDenied }
    let event = EKEvent(eventStore: store)
    event.title = "Interview: \([interview.role, interview.company].filter { !$0.isBlank }.joined(separator: " at "))"
    event.startDate = interview.scheduledAt
    event.endDate = interview.scheduledAt.addingTimeInterval(Double(interview.durationMinutes) * 60)
    event.location = interview.locationOrLink
    event.notes = interview.preparationNotes
    event.calendar = store.defaultCalendarForNewEvents
    event.addAlarm(EKAlarm(relativeOffset: -3600))
    try store.save(event, span: .thisEvent)
  }
}

enum CalendarError: LocalizedError {
  case permissionDenied
  var errorDescription: String? { "Calendar access is disabled. Enable it in Settings to add interviews." }
}
