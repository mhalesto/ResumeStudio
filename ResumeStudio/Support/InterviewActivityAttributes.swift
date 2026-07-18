import ActivityKit
import Foundation

/// The Live Activity contract for the interview countdown.
///
/// This file is intentionally duplicated **verbatim** in the app target
/// (`Support/`) and the widget target (`ResumeStudioWidgets/`). ActivityKit
/// matches a running activity to its `ActivityConfiguration` by the attributes'
/// unqualified type name and Codable shape — not by module — so two identical
/// module-local copies interoperate (the same reason push-started activities
/// work from pure JSON). Keep the two copies byte-for-byte identical.
struct InterviewActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    /// When the interview starts. Drives the count-down timer.
    var scheduledAt: Date
    /// When the interview is expected to end (start + duration).
    var endsAt: Date
    /// True once the interview is underway, so the surface switches from a
    /// count-down to an "in progress" state instead of an invalid timer range.
    var isUnderway: Bool
  }

  /// Stable identifier of the `InterviewEvent` this activity tracks, so
  /// reconciliation can tell "update the running one" from "start a new one".
  var eventID: String
  var role: String
  var company: String
  /// Human label of the interview format, e.g. "Video".
  var format: String
  /// Where to be — a link, room, or address. May be empty.
  var locationOrLink: String
}
