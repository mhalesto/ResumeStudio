import AppIntents
import SwiftUI

struct PlatformIntegrationsView: View {
  @EnvironmentObject private var resumeStore: ResumeStore
  @EnvironmentObject private var applicationStore: ApplicationStore
  @State private var message: String?

  var body: some View {
    List {
      Section("Calendar") {
        if let interview = applicationStore.upcomingInterviews.first {
          Button("Add next interview to Calendar", systemImage: "calendar.badge.plus") {
            Task { await addInterview(interview) }
          }
          Text("\(interview.role) at \(interview.company) · \(interview.scheduledAt.formatted())")
            .font(.caption).foregroundStyle(Theme.mutedInk)
        } else {
          Label("Schedule an interview to add it to Calendar.", systemImage: "calendar")
            .foregroundStyle(Theme.mutedInk)
        }
        ForEach(applicationStore.applications.filter { $0.deadline != nil }.prefix(5)) { application in
          Button("Add \(application.company) deadline", systemImage: "calendar.badge.clock") {
            Task { await addDeadline(application) }
          }
        }
      }

      Section("Safari application autofill") {
        Button("Refresh private autofill profile", systemImage: "safari.fill") {
          do {
            try PlatformIntegrationService.publishAutofillProfile(resumeStore.document)
            message = "Safari autofill now uses the active résumé's contact details, headline and skills."
          } catch { message = error.localizedDescription }
        }
        Text("The Safari extension reads only the profile you explicitly publish to the private app group. It never submits an application automatically.")
          .font(.caption).foregroundStyle(Theme.mutedInk)
      }

      Section("Widgets and Shortcuts") {
        Button("Refresh widgets", systemImage: "widget.small") {
          PlatformIntegrationService.publishWidgetSnapshot(
            applications: applicationStore.applications,
            interviews: applicationStore.interviews,
            resume: resumeStore.document)
          message = "Widgets refreshed."
        }
        Label("Open Applications", systemImage: "briefcase.fill")
        Label("Open ATS Check", systemImage: "checkmark.shield.fill")
        Label("Open Template Finder", systemImage: "sparkles.rectangle.stack.fill")
        Text("These actions are available to Shortcuts and Siri after the app has launched once.")
          .font(.caption).foregroundStyle(Theme.mutedInk)
      }

      Section("Mail") {
        Text("Application Packets can open their application and follow-up messages directly in your preferred Mail app.")
          .font(.subheadline)
      }

      if let message {
        Section { Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
      }
    }
    .navigationTitle("Integrations")
    .navigationBarTitleDisplayMode(.inline)
  }

  @MainActor private func addInterview(_ interview: InterviewEvent) async {
    do { try await PlatformIntegrationService.addInterviewToCalendar(interview); message = "Interview added to Calendar." }
    catch { message = error.localizedDescription }
  }

  @MainActor private func addDeadline(_ application: JobApplication) async {
    do { try await PlatformIntegrationService.addDeadlineToCalendar(application); message = "Deadline added to Calendar." }
    catch { message = error.localizedDescription }
  }
}

struct OpenResumeStudioApplicationsIntent: AppIntent {
  static var title: LocalizedStringResource = "Open ResumeStudio Applications"
  static var description = IntentDescription("Open your private application command centre.")
  static var openAppWhenRun = true

  func perform() async throws -> some IntentResult {
    ShortcutRouteStore.queue("applications")
    return .result()
  }
}

struct OpenResumeStudioATSIntent: AppIntent {
  static var title: LocalizedStringResource = "Check My Résumé"
  static var description = IntentDescription("Open ResumeStudio's ATS readiness coach.")
  static var openAppWhenRun = true

  func perform() async throws -> some IntentResult {
    ShortcutRouteStore.queue("ats")
    return .result()
  }
}

struct OpenResumeStudioTemplatesIntent: AppIntent {
  static var title: LocalizedStringResource = "Find a Résumé Template"
  static var description = IntentDescription("Open ResumeStudio's template catalogue and finder.")
  static var openAppWhenRun = true

  func perform() async throws -> some IntentResult {
    ShortcutRouteStore.queue("templates")
    return .result()
  }
}

struct ResumeStudioShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(intent: OpenResumeStudioApplicationsIntent(), phrases: ["Open applications in \(.applicationName)"], shortTitle: "Applications", systemImageName: "briefcase.fill")
    AppShortcut(intent: OpenResumeStudioATSIntent(), phrases: ["Check my resume in \(.applicationName)"], shortTitle: "ATS Check", systemImageName: "checkmark.shield.fill")
    AppShortcut(intent: OpenResumeStudioTemplatesIntent(), phrases: ["Find a resume template in \(.applicationName)"], shortTitle: "Templates", systemImageName: "rectangle.split.2x1")
  }
}
