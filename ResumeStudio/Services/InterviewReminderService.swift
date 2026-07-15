import Foundation
import UserNotifications

enum InterviewReminderService {
  static func schedule(for interview: InterviewEvent) async throws {
    cancel(interviewID: interview.id)
    guard interview.reminderEnabled, interview.scheduledAt > Date() else { return }

    let center = UNUserNotificationCenter.current()
    let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
    guard granted else { throw ReminderError.permissionDenied }

    let reminderDate = interview.scheduledAt.addingTimeInterval(-24 * 60 * 60)
    let fallbackDate = interview.scheduledAt.addingTimeInterval(-60 * 60)
    let fireDate = reminderDate > Date() ? reminderDate : fallbackDate
    guard fireDate > Date() else { return }

    let content = UNMutableNotificationContent()
    content.title = reminderDate > Date() ? "Interview tomorrow" : "Interview in one hour"
    content.body = [interview.role, interview.company].filter { !$0.isBlank }.joined(separator: " at ")
    content.sound = .default
    content.userInfo = ["interviewID": interview.id.uuidString]

    let components = Calendar.current.dateComponents(
      [.year, .month, .day, .hour, .minute], from: fireDate)
    let request = UNNotificationRequest(
      identifier: identifier(interview.id),
      content: content,
      trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    )
    try await center.add(request)
  }

  static func cancel(interviewID: UUID) {
    UNUserNotificationCenter.current().removePendingNotificationRequests(
      withIdentifiers: [identifier(interviewID)])
  }

  private static func identifier(_ id: UUID) -> String { "interview-reminder-\(id.uuidString)" }
}

enum ReminderError: LocalizedError {
  case permissionDenied
  var errorDescription: String? {
    "Notifications are disabled. Enable them in Settings to receive interview reminders."
  }
}
