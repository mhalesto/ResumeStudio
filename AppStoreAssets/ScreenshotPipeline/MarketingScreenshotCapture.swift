import SwiftUI
import UIKit
import XCTest

@testable import ResumeStudio

/// Renders each marketing screen in a real UIWindow on the simulator and writes
/// full-resolution PNGs for the App Store screenshot compositor. Temporary
/// tooling — not part of the app's test suite proper.
@MainActor
final class MarketingScreenshotCapture: XCTestCase {

  private static let outputDirectory = URL(
    fileURLWithPath:
      "/private/tmp/claude-502/-Users-halalisanimbanjwa-Documents-GitHub-ios-ResumeStudio/a4440b03-e742-4d16-b43d-5802e540baf4/scratchpad/raw",
    isDirectory: true
  )

  private struct Shot {
    let id: String
    let settleSeconds: Double
    let colorScheme: UIUserInterfaceStyle
    let view: AnyView
  }

  private struct SeededStores {
    let resumeStore: ResumeStore
    let coverLetterStore: CoverLetterStore
    let applicationStore: ApplicationStore
    let careerStore: CareerIntelligenceStore
    let coachStore: CareerCoachStore
    let cloudSync: ICloudSyncService
  }

  func testCaptureMarketingScreens() async throws {
    try FileManager.default.createDirectory(
      at: Self.outputDirectory, withIntermediateDirectories: true)

    UserDefaults.standard.set(AppAppearance.light.rawValue, forKey: "appAppearance")
    UserDefaults.standard.set(true, forKey: "careerCoachIntroDismissed")

    let stores = seedStores()
    guard
      let scene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene }).first
    else {
      XCTFail("No window scene available")
      return
    }

    for shot in shots(stores) {
      let window = UIWindow(windowScene: scene)
      window.frame = scene.screen.bounds
      window.overrideUserInterfaceStyle = shot.colorScheme
      window.backgroundColor = .systemBackground
      window.rootViewController = UIHostingController(rootView: shot.view)
      window.windowLevel = .alert + 1
      window.makeKeyAndVisible()

      try await Task.sleep(nanoseconds: UInt64(shot.settleSeconds * 1_000_000_000))

      let format = UIGraphicsImageRendererFormat()
      format.scale = scene.screen.scale
      format.opaque = true
      let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
      let image = renderer.image { _ in
        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
      }

      guard let data = image.pngData() else {
        XCTFail("PNG encoding failed for \(shot.id)")
        continue
      }
      let url = Self.outputDirectory.appendingPathComponent("\(shot.id).png")
      try data.write(to: url)
      XCTAssertGreaterThan(data.count, 50_000, "\(shot.id) looks blank")

      window.isHidden = true
      window.rootViewController = nil
    }
  }

  // MARK: - Screens

  private func shots(_ stores: SeededStores) -> [Shot] {
    func wrap<V: View>(_ view: V) -> AnyView {
      AnyView(
        view
          .environmentObject(stores.resumeStore)
          .environmentObject(stores.coverLetterStore)
          .environmentObject(stores.applicationStore)
          .environmentObject(stores.careerStore)
          .environmentObject(stores.cloudSync)
          .environmentObject(PurchaseManager.shared)
          .tint(stores.resumeStore.document.accent.color)
      )
    }

    return [
      Shot(
        id: "01-home", settleSeconds: 9.5, colorScheme: .light,
        view: wrap(RootView())
      ),
      Shot(
        id: "02-preview", settleSeconds: 4.5, colorScheme: .light,
        view: wrap(NavigationStack { ResumePreviewView(document: stores.resumeStore.document) })
      ),
      Shot(
        id: "03-templates", settleSeconds: 6, colorScheme: .light,
        view: wrap(NavigationStack { TemplateGalleryView() })
      ),
      Shot(
        id: "04-editor", settleSeconds: 3, colorScheme: .light,
        view: wrap(NavigationStack { ResumeEditorView(focus: nil) })
      ),
      Shot(
        id: "05-ats", settleSeconds: 3, colorScheme: .light,
        view: wrap(NavigationStack { ATSCheckerView() })
      ),
      Shot(
        id: "06-pipeline", settleSeconds: 3.5, colorScheme: .light,
        view: wrap(NavigationStack { ApplicationCommandCenterView() })
      ),
      Shot(
        id: "07-voice", settleSeconds: 3.5, colorScheme: .light,
        view: wrap(NavigationStack { VoiceInterviewStudioView() })
      ),
      Shot(
        id: "08-intel", settleSeconds: 3.5, colorScheme: .light,
        view: wrap(NavigationStack { CareerIntelligenceHubView() })
      ),
      Shot(
        id: "09-cover", settleSeconds: 4.5, colorScheme: .light,
        view: wrap(NavigationStack { CoverLetterPreviewView(document: stores.coverLetterStore.document) })
      ),
      Shot(
        id: "10-coach", settleSeconds: 3.5, colorScheme: .light,
        view: wrap(CareerCoachView(chatStore: stores.coachStore))
      ),
      Shot(
        id: "11-interviews", settleSeconds: 3.5, colorScheme: .light,
        view: wrap(NavigationStack { InterviewCenterView() })
      ),
      Shot(
        id: "12-privacy", settleSeconds: 3, colorScheme: .light,
        view: wrap(NavigationStack { PrivacyCenterView() })
      ),
    ]
  }

  // MARK: - Seed data

  private func seedStores() -> SeededStores {
    let temp = FileManager.default.temporaryDirectory
      .appendingPathComponent("marketing-seed-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)

    let resumeStore = ResumeStore(
      fileURL: temp.appendingPathComponent("resumes.json"),
      initialDocument: .example
    )
    let coverLetterStore = CoverLetterStore(initialDocument: .example)
    let applicationStore = ApplicationStore(fileURL: temp.appendingPathComponent("applications.json"))
    let careerStore = CareerIntelligenceStore(fileURL: temp.appendingPathComponent("career.json"))
    let coachStore = CareerCoachStore(fileURL: temp.appendingPathComponent("coach.json"))
    let cloudSync = ICloudSyncService()

    seedApplications(into: applicationStore, baseResumeID: resumeStore.activeResumeID)
    seedCareerIntelligence(into: careerStore, resumeID: resumeStore.activeResumeID)
    seedCoach(into: coachStore)

    return SeededStores(
      resumeStore: resumeStore,
      coverLetterStore: coverLetterStore,
      applicationStore: applicationStore,
      careerStore: careerStore,
      coachStore: coachStore,
      cloudSync: cloudSync
    )
  }

  private func seedApplications(into store: ApplicationStore, baseResumeID: UUID) {
    let now = Date()

    let evergreenAnalysis = AIJobMatchAnalysis(
      summary:
        "Strong alignment with the role's people-operations core. Your manager-enablement and onboarding work maps directly to the stated priorities; senior stakeholder evidence could be clearer.",
      matchedKeywords: [
        "People operations", "Manager coaching", "Onboarding", "Employee experience",
        "People analytics", "Change communication", "Workforce planning",
      ],
      missingKeywords: ["HRIS migration", "Compensation benchmarking"],
      recommendations: [
        "Lead your profile with the quarterly people-planning rhythm you built at Northstar Works.",
        "Quantify the manager toolkit adoption — how many managers, what changed.",
        "Add one line of evidence about partnering with senior leaders on organisation design.",
      ],
      claimsRequiringConfirmation: [
        "Confirm the size of the manager population you supported at Northstar Works."
      ]
    )

    let evergreenPlan = AIInterviewPlan(
      openingPitch:
        "I build people operations that managers actually use — from a quarterly planning rhythm connecting hiring to retention, to a coaching toolkit that made performance conversations something managers stopped avoiding.",
      questions: [
        AIInterviewQuestion(
          id: "q1",
          question: "Walk me through a people programme you built from scratch.",
          rationale: "The role owns programme design end to end.",
          evidenceHint: "Quarterly people-planning rhythm at Northstar Works."
        ),
        AIInterviewQuestion(
          id: "q2",
          question: "How do you help managers get better at difficult conversations?",
          rationale: "Manager enablement is the first responsibility listed.",
          evidenceHint: "Manager toolkit and coaching programme."
        ),
        AIInterviewQuestion(
          id: "q3",
          question: "Tell me about turning employee feedback into visible change.",
          rationale: "They run a twice-yearly engagement survey.",
          evidenceHint: "Employee-listening process with measurable action plans."
        ),
      ],
      questionsToAsk: [
        "How do managers currently experience the onboarding handoff?",
        "What would success look like for this role after six months?",
        "How does the People team measure the impact of its programmes?",
      ],
      preparationTips: [
        "Bring one measurable outcome for each stage of the employee lifecycle you improved.",
        "Re-read the advert's emphasis on manager enablement the morning of the interview.",
        "Prepare a 90-second version of the onboarding simplification story.",
      ],
      claimsRequiringConfirmation: [
        "Verify the three-region scope of the hybrid engagement initiatives."
      ]
    )

    struct SeedApp {
      let company: String
      let role: String
      let status: JobApplicationStatus
      let notes: String
      let updatedMinutesAgo: Double
      let createdDaysAgo: Double
      var analysis: AIJobMatchAnalysis?
      var plan: AIInterviewPlan?
      var activities: [(ApplicationActivityKind, String, String, Double)] = []
    }

    let seeds: [SeedApp] = [
      SeedApp(
        company: "Northwind Digital", role: "People Operations Manager",
        status: .saved, notes: "Referred by Sam — hiring manager values onboarding experience.",
        updatedMinutesAgo: 35, createdDaysAgo: 0.5
      ),
      SeedApp(
        company: "Evergreen Labs", role: "Senior People Operations Manager",
        status: .interview,
        notes: "Final round Friday. Panel: Jordan Lee (Director of People) and Priya Nair (COO).",
        updatedMinutesAgo: 130, createdDaysAgo: 9,
        analysis: evergreenAnalysis, plan: evergreenPlan,
        activities: [
          (.captured, "Opportunity saved", "Shared from Safari", 9 * 1440),
          (.applied, "Application submitted", "Tailored résumé v2 attached", 7 * 1440),
          (.interview, "Screening call completed", "30 min with talent team", 4 * 1440),
          (.statusChanged, "Moved to Interview", "Final round scheduled", 2 * 1440),
        ]
      ),
      SeedApp(
        company: "Solstice Studio", role: "Head of Employee Experience",
        status: .offer, notes: "Offer received — reviewing package against Evergreen timeline.",
        updatedMinutesAgo: 300, createdDaysAgo: 21,
        activities: [
          (.captured, "Opportunity saved", "", 21 * 1440),
          (.applied, "Application submitted", "", 18 * 1440),
          (.interview, "Panel interview", "Strong signal on programme design", 8 * 1440),
          (.offer, "Offer received", "Package shared by recruiter", 5 * 60),
        ]
      ),
      SeedApp(
        company: "Harbor & Finch", role: "People & Culture Lead",
        status: .applied, notes: "Applied with tailored profile emphasising retail workforce planning.",
        updatedMinutesAgo: 1_500, createdDaysAgo: 3
      ),
      SeedApp(
        company: "Atlas Health", role: "HR Business Partner",
        status: .applied, notes: "Follow up with recruiter next Tuesday if no response.",
        updatedMinutesAgo: 4_400, createdDaysAgo: 6
      ),
      SeedApp(
        company: "Meridian Retail Group", role: "People Analytics Manager",
        status: .rejected, notes: "Went with an internal candidate — recruiter open to future roles.",
        updatedMinutesAgo: 9_000, createdDaysAgo: 16
      ),
    ]

    // Insert oldest-updated first; the store prepends, and the pipeline sorts by
    // updatedAt anyway. Timestamps are back-dated so relative labels read naturally.
    for seed in seeds.reversed() {
      var application = JobApplication(
        company: seed.company,
        role: seed.role,
        jobDescription: "",
        sourceURL: "",
        status: seed.status,
        notes: seed.notes,
        baseResumeID: baseResumeID,
        tailoredResumeID: nil,
        matchAnalysis: seed.analysis,
        interviewPlan: seed.plan
      )
      application.createdAt = now.addingTimeInterval(-seed.createdDaysAgo * 86_400)
      application.updatedAt = now.addingTimeInterval(-seed.updatedMinutesAgo * 60)
      if !seed.activities.isEmpty {
        application.activities = seed.activities.map { kind, title, detail, minutesAgo in
          ApplicationActivity(
            kind: kind, title: title, detail: detail,
            occurredAt: now.addingTimeInterval(-minutesAgo * 60)
          )
        }
      }
      store.add(application)
    }

    let evergreenID = store.applications.first { $0.company == "Evergreen Labs" }?.id

    var tomorrow10 = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
    tomorrow10 = Calendar.current.date(
      bySettingHour: 10, minute: 0, second: 0, of: tomorrow10) ?? tomorrow10

    store.addInterview(
      InterviewEvent(
        applicationID: evergreenID,
        role: "Senior People Operations Manager",
        company: "Evergreen Labs",
        scheduledAt: tomorrow10,
        durationMinutes: 45,
        format: .video,
        locationOrLink: "meet.example.com/evergreen-final",
        interviewerNames: "Jordan Lee, Priya Nair",
        reminderEnabled: false,
        preparationNotes: "Lead with the manager toolkit story; ask about onboarding ownership.",
        outcome: .pending,
        selfRating: 0,
        whatWentWell: "",
        needsImprovement: "",
        followUpNotes: ""
      )
    )
    store.addInterview(
      InterviewEvent(
        applicationID: nil,
        role: "HR Business Partner",
        company: "Atlas Health",
        scheduledAt: Calendar.current.date(byAdding: .day, value: 6, to: tomorrow10) ?? tomorrow10,
        durationMinutes: 60,
        format: .panel,
        locationOrLink: "Atlas Health, 2nd floor",
        interviewerNames: "People team panel",
        reminderEnabled: false,
        preparationNotes: "",
        outcome: .pending,
        selfRating: 0,
        whatWentWell: "",
        needsImprovement: "",
        followUpNotes: ""
      )
    )
    store.addInterview(
      InterviewEvent(
        applicationID: nil,
        role: "Head of Employee Experience",
        company: "Solstice Studio",
        scheduledAt: now.addingTimeInterval(-3 * 86_400),
        durationMinutes: 60,
        format: .video,
        locationOrLink: "meet.example.com/solstice",
        interviewerNames: "Panel",
        reminderEnabled: false,
        preparationNotes: "",
        outcome: .progressed,
        selfRating: 4,
        whatWentWell: "Programme-design stories landed well.",
        needsImprovement: "Tighten the compensation philosophy answer.",
        followUpNotes: "Thank-you note sent."
      )
    )
  }

  private func seedCareerIntelligence(into store: CareerIntelligenceStore, resumeID: UUID) {
    let now = Date()

    let evidenceSeeds: [(CareerEvidenceKind, String, String, [String])] = [
      (
        .achievement, "Quarterly people-planning rhythm",
        "Connected hiring, development and retention priorities at Northstar Works.",
        ["Planning", "Strategy"]
      ),
      (
        .achievement, "Manager toolkit and coaching programme",
        "Improved manager confidence in performance conversations.",
        ["Coaching", "Enablement"]
      ),
      (
        .project, "Employee-listening process",
        "Turned recurring survey themes into measurable action plans.",
        ["Analytics", "Engagement"]
      ),
      (
        .achievement, "Onboarding simplification",
        "Reduced manual administration across the employee lifecycle.",
        ["Onboarding", "Process"]
      ),
      (
        .skill, "People analytics dashboards",
        "Monthly insight packs prepared for leadership reviews at Brightside Labs.",
        ["Analytics"]
      ),
      (
        .qualification, "Certificate in People Analytics",
        "Sample Learning Institute, 2021.",
        ["Qualification"]
      ),
    ]
    for (index, seed) in evidenceSeeds.enumerated() {
      var item = CareerEvidence(
        kind: seed.0,
        title: seed.1,
        detail: seed.2,
        source: "Résumé — Avery Sample",
        sourceResumeID: resumeID,
        tags: seed.3,
        isVerified: true
      )
      item.createdAt = now.addingTimeInterval(Double(-index) * 86_400)
      store.upsert(item)
    }

    let attemptSeeds: [(String, Int, Int, Double, [String])] = [
      (
        "Tell me about yourself and why this role is the right next step.",
        78, 126, 6 * 86_400, ["um", "like"]
      ),
      (
        "Describe a difficult problem you solved and the result.",
        84, 131, 3 * 86_400, ["um"]
      ),
      (
        "Tell me about a time you influenced someone without formal authority.",
        90, 134, 86_400, []
      ),
    ]
    for attempt in attemptSeeds {
      var value = VoicePracticeAttempt(
        applicationID: nil,
        question: attempt.0,
        transcript:
          "At Northstar Works I noticed managers were postponing performance conversations, so I built a practical toolkit and coaching programme…",
        durationSeconds: 82,
        wordsPerMinute: attempt.2,
        fillerWords: attempt.4,
        starCoverage: ["Situation", "Task", "Action", "Result"],
        strengths: [
          "Clear structure with a measurable result",
          "Confident, steady pacing",
        ],
        improvements: [
          "Name the business impact one sentence earlier"
        ],
        suggestedAnswerShape:
          "Open with the tension, then the toolkit decision, close with the adoption metric.",
        claimsRequiringConfirmation: []
      )
      value.createdAt = Date().addingTimeInterval(-attempt.3)
      value.deliveryScore = attempt.1
      store.add(value)
    }
  }

  private func seedCoach(into store: CareerCoachStore) {
    guard store.messages.isEmpty else { return }
    let now = Date()
    var welcome = CareerCoachMessage(
      role: .assistant,
      content:
        "Hi Avery — I'm your career coach. I can see your résumé, your six applications and tomorrow's interview, so ask me anything about your search."
    )
    welcome.createdAt = now.addingTimeInterval(-540)
    var question = CareerCoachMessage(
      role: .user,
      content: "I have my final interview at Evergreen Labs tomorrow. How should I prepare tonight?"
    )
    question.createdAt = now.addingTimeInterval(-480)
    var answer = CareerCoachMessage(
      role: .assistant,
      content: """
        You're well placed — Evergreen moved you to the final round quickly. Three things for tonight:

        1. Re-read the advert's manager-enablement focus. Your Northstar Works toolkit story is your strongest evidence — rehearse the 90-second version.
        2. Pick one measurable outcome per lifecycle stage you improved: planning, onboarding, listening.
        3. Prepare a closing question about how their People team measures onboarding success.

        Your voice practice this week scored 90 on delivery, so trust the pacing. Want a quick mock question from their job description?
        """
    )
    answer.createdAt = now.addingTimeInterval(-420)
    store.append(welcome)
    store.append(question)
    store.append(answer)
  }
}
