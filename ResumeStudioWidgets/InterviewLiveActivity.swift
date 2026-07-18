import ActivityKit
import SwiftUI
import WidgetKit

/// The interview countdown Live Activity: a Lock Screen banner and the full set
/// of Dynamic Island presentations. The count-down is driven by SwiftUI's
/// self-updating `Text(timerInterval:)`, so it ticks without the app running.
struct InterviewLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: InterviewActivityAttributes.self) { context in
      InterviewLockScreenView(context: context)
        .activityBackgroundTint(Color.black.opacity(0.45))
        .activitySystemActionForegroundColor(.orange)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Label {
            Text(context.attributes.company.isEmpty ? "Interview" : context.attributes.company)
              .lineLimit(1)
          } icon: {
            Image(systemName: "person.badge.clock.fill")
          }
          .font(.caption.bold())
          .foregroundStyle(.orange)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(context.attributes.format)
            .font(.caption2.bold())
            .foregroundStyle(.secondary)
        }
        DynamicIslandExpandedRegion(.center) {
          Text(context.attributes.role.isEmpty ? "Interview" : context.attributes.role)
            .font(.headline)
            .lineLimit(1)
        }
        DynamicIslandExpandedRegion(.bottom) {
          HStack {
            Text(context.state.isUnderway ? "In progress" : "Starts in")
              .font(.caption)
              .foregroundStyle(.secondary)
            Spacer()
            InterviewCountdownText(state: context.state)
              .font(.system(.title3, design: .rounded).weight(.bold))
              .monospacedDigit()
              .foregroundStyle(.orange)
          }
        }
      } compactLeading: {
        Image(systemName: "person.badge.clock.fill")
          .foregroundStyle(.orange)
      } compactTrailing: {
        InterviewCountdownText(state: context.state)
          .monospacedDigit()
          .foregroundStyle(.orange)
          .frame(maxWidth: 58)
      } minimal: {
        Image(systemName: "person.badge.clock.fill")
          .foregroundStyle(.orange)
      }
      .widgetURL(URL(string: "resumestudio://interviews"))
      .keylineTint(.orange)
    }
  }
}

/// Lock Screen / banner presentation.
private struct InterviewLockScreenView: View {
  let context: ActivityViewContext<InterviewActivityAttributes>

  var body: some View {
    HStack(alignment: .center, spacing: 14) {
      VStack(alignment: .leading, spacing: 3) {
        Text(context.state.isUnderway ? "INTERVIEW NOW" : "NEXT INTERVIEW")
          .font(.caption2.bold())
          .foregroundStyle(.orange)
        Text(context.attributes.role.isEmpty ? "Interview" : context.attributes.role)
          .font(.headline)
          .lineLimit(1)
        Text(context.attributes.company)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        if !context.attributes.locationOrLink.isEmpty {
          Label(context.attributes.locationOrLink, systemImage: "mappin.and.ellipse")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      Spacer(minLength: 8)
      VStack(alignment: .trailing, spacing: 2) {
        InterviewCountdownText(state: context.state)
          .font(.system(.title, design: .rounded).weight(.bold))
          .monospacedDigit()
          .foregroundStyle(.orange)
        Text(context.state.isUnderway ? "in progress" : "to go")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .padding(16)
  }
}

/// A self-updating count-down that stays valid across the whole activity window:
/// a live timer before the interview, a static label once it is underway or done
/// (a `timerInterval` needs its lower bound below its upper bound).
private struct InterviewCountdownText: View {
  let state: InterviewActivityAttributes.ContentState

  var body: some View {
    let now = Date()
    if now < state.scheduledAt {
      Text(timerInterval: now...state.scheduledAt, countsDown: true)
        .multilineTextAlignment(.trailing)
    } else if now < state.endsAt {
      Text("Now")
    } else {
      Text("Done")
    }
  }
}
