import ActivityKit
import Foundation

/// Starts, updates, and ends the interview countdown Live Activity.
///
/// Reconciliation is idempotent and cheap, so `RootView` calls `reconcile` from
/// the same funnel that refreshes the widget snapshot — foreground, launch, and
/// every application-store save (which is how a scheduled or edited interview
/// reaches this controller). There is only ever one activity: the single most
/// imminent interview whose window is currently open.
@MainActor
enum InterviewLiveActivityController {
  /// How far ahead of an interview the count-down appears.
  static let leadTime: TimeInterval = 24 * 60 * 60
  /// How long after the scheduled end the activity lingers before dismissing —
  /// long enough to survive an interview that overruns its planned duration.
  static let endGrace: TimeInterval = 30 * 60

  /// The one interview to surface: the soonest whose window is open — from
  /// `leadTime` before it starts until `endGrace` after it is expected to end.
  /// Pure and side-effect free so the selection rule can be unit-tested without
  /// ActivityKit. `nonisolated` so tests can call it off the main actor.
  nonisolated static func eligibleInterview(
    from interviews: [InterviewEvent], now: Date = Date()
  ) -> InterviewEvent? {
    interviews
      .filter { interview in
        let ends = interview.scheduledAt.addingTimeInterval(Double(interview.durationMinutes) * 60)
        return interview.scheduledAt.addingTimeInterval(-leadTime) <= now
          && now <= ends.addingTimeInterval(endGrace)
      }
      .min { $0.scheduledAt < $1.scheduledAt }
  }

  static func reconcile(with interviews: [InterviewEvent]) {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      endAll()
      return
    }

    let now = Date()
    let target = eligibleInterview(from: interviews, now: now)
    let running = Activity<InterviewActivityAttributes>.activities

    guard let target else {
      endAll()
      return
    }

    let targetID = target.id.uuidString
    let ends = target.scheduledAt.addingTimeInterval(Double(target.durationMinutes) * 60)
    let state = InterviewActivityAttributes.ContentState(
      scheduledAt: target.scheduledAt,
      endsAt: ends,
      isUnderway: now >= target.scheduledAt && now < ends)
    let staleDate = ends.addingTimeInterval(endGrace)
    let content = ActivityContent(state: state, staleDate: staleDate)

    // Dismiss any activity that is no longer the one we want on screen.
    for activity in running where activity.attributes.eventID != targetID {
      Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    if let existing = running.first(where: { $0.attributes.eventID == targetID }) {
      Task { await existing.update(content) }
    } else {
      let attributes = InterviewActivityAttributes(
        eventID: targetID,
        role: target.role,
        company: target.company,
        format: target.format.title,
        locationOrLink: target.locationOrLink)
      // `request` is synchronous and throwing; a denial or rate-limit is not
      // actionable here, so a failure just leaves no activity on screen.
      _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
    }
  }

  static func endAll() {
    for activity in Activity<InterviewActivityAttributes>.activities {
      Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
  }
}
