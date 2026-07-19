import SwiftUI
import TipKit

/// Where the home screen can take you.
enum HomeRoute: Hashable {
  /// Opens the editor, optionally scrolled straight to a section.
  case editor(ResumeSection?)
  case preview
  case gallery
  case jobTargeting
  case jobTargetingApplication(UUID)
  case coverLetterEditor
  case coverLetterPreview
  case resumeLibrary
  case applications
  case atsChecker
  case importResume
  case applicationDetail(UUID)
  case applicationPacket(UUID)
  case applicationAnalytics
  case interviewPrep(UUID?)
  case interviewCenter
  case interviewEditor(interviewID: UUID?, applicationID: UUID?)
  case careerIntelligence
  case evidenceVault
  case jobCapture
  case aiChangeReview
  case voiceInterview
  case linkedInStudio
  case networking
  case offers
  case reviewRoom
  case marketGuidance
  case marketLocalization
  case layoutStudio
  case versionComparison
  case integrations
  case privacyCenter
  case recruiterScan
  case smartLinks
  case personalProfile
  case campaign
}

struct HomeView: View {
  @EnvironmentObject private var store: ResumeStore
  @EnvironmentObject private var coverLetterStore: CoverLetterStore
  @EnvironmentObject private var applicationStore: ApplicationStore
  @EnvironmentObject private var careerStore: CareerIntelligenceStore
  @EnvironmentObject private var purchases: PurchaseManager
  @EnvironmentObject private var smartLinks: SmartLinkStore
  @EnvironmentObject private var personalProfile: PersonalProfileStore
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var path: [HomeRoute] = []
  @State private var pendingStart: StartChoice?
  @State private var showWelcome = false
  @State private var welcomeDestination: HomeRoute?
  @State private var navigationRequestID: UUID?
  @State private var isWelcomePresentationQueued = false
  @State private var showAccentPicker = false
  @State private var isExportingPDF = false
  @State private var exportShare: HomeShareItem?
  @State private var exportError: String?
  /// Set by a hero library shortcut to scroll the page to the section it counts.
  /// Each tap carries a fresh id so repeat taps still fire, which saves clearing
  /// the state from inside its own change handler — a second write in the same
  /// frame that SwiftUI complains about.
  @State private var scrollRequest: ScrollRequest?
  private static let coverLettersAnchor = "home.section.coverLetters"

  private struct ScrollRequest: Equatable {
    let id = UUID()
    let anchor: String
  }
  @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
  // Scales the serif display headline with the reader's text-size setting instead
  // of pinning it at 38pt.
  @ScaledMetric(relativeTo: .largeTitle) private var heroTitleSize: CGFloat = 38
  private let allowsWelcome: Bool
  private let acceptsExternalRoutes: Bool

  init(
    initialRoute: HomeRoute? = nil,
    allowsWelcome: Bool = true,
    acceptsExternalRoutes: Bool = true
  ) {
    _path = State(initialValue: initialRoute.map { [$0] } ?? [])
    self.allowsWelcome = allowsWelcome
    self.acceptsExternalRoutes = acceptsExternalRoutes
  }

  var body: some View {
    NavigationStack(path: $path) {
      ScrollViewReader { scroll in
        ScrollView {
          VStack(alignment: .leading, spacing: 30) {
            hero
            today
            campaign
            quickStart
            workspace
            templates
            coverLetters.id(Self.coverLettersAnchor)
            recentlyEdited
            privacyNote
          }
          .padding(.horizontal, 20)
          .padding(.top, 12)
          .padding(.bottom, 40)
          // The design is phone-shaped. On iPad, hold it to a readable column rather
          // than stretching the hero and the progress bars across the whole display.
          .frame(maxWidth: 680)
          .frame(maxWidth: .infinity)
        }
        .onChange(of: scrollRequest) { _, request in
          guard let request else { return }
          withAnimation(.easeInOut(duration: 0.45)) {
            scroll.scrollTo(request.anchor, anchor: .top)
          }
        }
      }
      .background(Theme.paper)
      .task(id: ResumeThumbnailWarmKey(
        accent: store.document.accent,
        photo: store.document.photo,
        crop: store.document.photoCrop,
        isPhotoVisible: store.document.isPhotoVisible
      )) { await warmThumbnails() }
      .navigationTitle("Resume Studio")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(Theme.paper, for: .navigationBar)
      .toolbar {
        // The PDF is the point of the app; it shouldn't be buried in the editor.
        // Spelled out rather than an icon — this is the action people came for.
        Button("Preview") {
          path.append(.preview)
        }
        .font(.subheadline.weight(.semibold))
        .tint(accent)
      }
      .navigationDestination(for: HomeRoute.self) { route in
        switch route {
        case .editor(let section):
          ResumeEditorView(focus: section)
        case .preview:
          ResumePreviewView(document: store.document)
        case .gallery:
          TemplateGalleryView()
        case .jobTargeting:
          JobTargetingView()
        case .jobTargetingApplication(let id):
          JobTargetingView(applicationID: id)
        case .coverLetterEditor:
          CoverLetterEditorView()
        case .coverLetterPreview:
          CoverLetterPreviewView(document: coverLetterStore.document)
        case .resumeLibrary:
          ResumeLibraryView()
        case .applications:
          ApplicationCommandCenterView()
        case .atsChecker:
          ATSCheckerView()
        case .importResume:
          ResumeImportView()
        case .applicationDetail(let id):
          ApplicationDetailView(applicationID: id)
        case .applicationPacket(let id):
          ApplicationPacketView(applicationID: id)
        case .applicationAnalytics:
          ApplicationAnalyticsView()
        case .interviewPrep(let id):
          InterviewPrepView(applicationID: id)
        case .interviewCenter:
          InterviewCenterView()
        case .interviewEditor(let interviewID, let applicationID):
          InterviewEditorView(interviewID: interviewID, applicationID: applicationID)
        case .careerIntelligence:
          CareerIntelligenceHubView()
        case .evidenceVault:
          EvidenceVaultView()
        case .jobCapture:
          JobCaptureView()
        case .aiChangeReview:
          AIChangeReviewView()
        case .voiceInterview:
          VoiceInterviewStudioView()
        case .linkedInStudio:
          LinkedInStudioView()
        case .networking:
          NetworkingStudioView()
        case .offers:
          OfferComparisonView()
        case .reviewRoom:
          ReviewRoomView()
        case .marketGuidance:
          MarketGuidanceView()
        case .marketLocalization:
          MarketLocalizationStudioView()
        case .layoutStudio:
          LayoutStudioView()
        case .versionComparison:
          ResumeVersionComparisonView()
        case .integrations:
          PlatformIntegrationsView()
        case .privacyCenter:
          PrivacyCenterView()
        case .recruiterScan:
          RecruiterScanView(document: store.document)
        case .smartLinks:
          SmartLinksView()
        case .personalProfile:
          PersonalProfileView()
        case .campaign:
          CareerCampaignView(
            applicationsThisWeek: applicationsThisWeek,
            networkingThisWeek: networkingThisWeek,
            practiceThisWeek: practiceThisWeek
          )
        }
      }
      .sheet(isPresented: $showWelcome, onDismiss: finishWelcome) {
        WelcomeSheet(
          accent: accent,
          templateCount: ResumeTemplate.allCases.count,
          onExample: {
            welcomeDestination = .editor(nil)
            showWelcome = false
          },
          onBlank: {
            store.startBlankResume()
            welcomeDestination = .editor(store.document.incompleteSections.first)
            showWelcome = false
          },
          onImport: {
            welcomeDestination = .importResume
            showWelcome = false
          },
          onTailor: {
            welcomeDestination = .jobCapture
            showWelcome = false
          },
          onOrganize: {
            welcomeDestination = .applications
            showWelcome = false
          }
        )
      }
      .sheet(isPresented: $showAccentPicker) {
        AccentPickerSheet(
          selection: $store.document.accent,
          canUse: { purchases.canUse($0) },
          onLocked: { purchases.requestPlans() }
        )
      }
      .sheet(item: $exportShare) { item in
        ShareSheet(activityItems: [item.url])
      }
      .alert(
        "Couldn’t create the PDF",
        isPresented: Binding(
          get: { exportError != nil },
          set: { if !$0 { exportError = nil } }
        ),
        presenting: exportError
      ) { _ in
        Button("OK", role: .cancel) {}
      } message: { message in
        Text(message)
      }
      .onAppear {
        // First launch only: point people at a starting move before they face
        // the full home screen. The flag is set when the sheet is dismissed, so
        // a launch where presentation is pre-empted doesn't burn the one chance.
        queueWelcomeIfNeeded()
      }
      .alert(item: $pendingStart) { choice in
        Alert(
          title: Text("Replace current draft?"),
          message: Text("Your current on-device draft will be replaced."),
          primaryButton: .destructive(Text("Replace")) {
            switch choice {
            case .example:
              store.loadSample()
            case .blank:
              store.startBlankResume()
            }
            // A blank draft has nothing to show, so land on the first thing to fill in.
            replacePath(afterPresentation: .editor(store.document.incompleteSections.first))
          },
          secondaryButton: .cancel()
        )
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .openSharedJobCapture)) { _ in
      guard acceptsExternalRoutes else { return }
      handleExternalRoute(.jobCapture)
    }
    .onReceive(NotificationCenter.default.publisher(for: .openHomeRoute)) { notification in
      guard acceptsExternalRoutes else { return }
      if let route = notification.object as? HomeRoute { handleExternalRoute(route) }
    }
  }

  /// Present only after NavigationStack has completed its first layout pass.
  /// The extra guard also prevents repeated onAppear callbacks from queuing
  /// competing sheet presentations.
  private func queueWelcomeIfNeeded() {
    guard allowsWelcome, !hasSeenWelcome, !showWelcome, !isWelcomePresentationQueued else { return }
    isWelcomePresentationQueued = true
    Task { @MainActor in
      await Task.yield()
      isWelcomePresentationQueued = false
      guard allowsWelcome, !hasSeenWelcome, !showWelcome else { return }
      showWelcome = true
    }
  }

  /// Coalesces route requests and moves the NavigationStack mutation to the
  /// next render pass. This is used when a sheet, tab, notification, or alert
  /// is also changing presentation state.
  private func replacePath(afterPresentation route: HomeRoute) {
    let requestID = UUID()
    navigationRequestID = requestID
    Task { @MainActor in
      await Task.yield()
      guard navigationRequestID == requestID else { return }
      navigationRequestID = nil
      path = [route]
    }
  }

  private func handleExternalRoute(_ route: HomeRoute) {
    // A deep link is already a deliberate starting choice. Suppress a queued
    // first-launch sheet, or dismiss the visible one before changing the path.
    hasSeenWelcome = true
    isWelcomePresentationQueued = false
    if showWelcome {
      welcomeDestination = route
      showWelcome = false
    } else {
      replacePath(afterPresentation: route)
    }
  }

  private func finishWelcome() {
    hasSeenWelcome = true
    guard let destination = welcomeDestination else { return }
    welcomeDestination = nil
    replacePath(afterPresentation: destination)
  }

  private var accent: Color { store.document.accent.color }

  private var weekStart: Date {
    Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? .distantPast
  }

  private var campaignProgress: WeeklyCampaignProgress {
    WeeklyCampaignService.progress(
      applications: applicationStore.applications,
      contacts: careerStore.contacts,
      voiceAttempts: careerStore.voiceAttempts,
      since: weekStart
    )
  }

  private var applicationsThisWeek: Int { campaignProgress.applications }
  private var networkingThisWeek: Int { campaignProgress.networking }
  private var practiceThisWeek: Int { campaignProgress.practice }

  private struct TodayAction: Identifiable {
    let id: String
    // Copy, not data: call sites pass literals that interpolate names and counts,
    // so each one keys as e.g. "Follow up with %@" and translates as a whole.
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    let systemImage: String
    let route: HomeRoute
    let priority: TodayActionPriority
    var onComplete: (() -> Void)? = nil
  }

  private var todayActions: [TodayAction] {
    var actions: [TodayAction] = []
    if let read = smartLinks.mostRecentUnseenLink {
      let who = read.company.nilIfBlank ?? "Someone"
      actions.append(TodayAction(
        id: "smart-link-\(read.id)", title: "\(who) read your résumé",
        detail: read.lastSeenAt.map { "Opened \($0.formatted(.relative(presentation: .named))). Follow up while you're on their mind." }
          ?? "Your trackable link has new opens.",
        systemImage: "eye.fill", route: .smartLinks, priority: .smartLink))
    }
    if let contact = careerStore.contacts
      .filter({ ($0.followUpAt ?? .distantFuture) <= Date() })
      .sorted(by: { ($0.followUpAt ?? .distantFuture) < ($1.followUpAt ?? .distantFuture) })
      .first
    {
      actions.append(TodayAction(
        id: "contact-\(contact.id)",
        title: "Follow up with \(contact.name.nilIfBlank ?? "a career contact")",
        detail: "This relationship follow-up is due. Open Networking to draft a thoughtful message.",
        systemImage: "person.crop.circle.badge.clock", route: .networking,
        priority: .dueFollowUp,
        onComplete: {
          var updated = contact
          updated.followUpAt = nil
          careerStore.upsert(updated)
        }
      ))
    }
    let dueOutcomeFollowUps: [(
      application: JobApplication, review: ApplicationOutcomeReview, followUpAt: Date
    )] = applicationStore.applications.flatMap { application in
      application.outcomeReviewList.compactMap { review in
        guard let followUpAt = review.followUpAt, followUpAt <= Date() else { return nil }
        return (application: application, review: review, followUpAt: followUpAt)
      }
    }
    if let due = dueOutcomeFollowUps.sorted(by: { $0.followUpAt < $1.followUpAt }).first {
      actions.append(TodayAction(
        id: "outcome-follow-up-\(due.review.id)",
        title: "Follow up on \(due.application.role.nilIfBlank ?? "an application")",
        detail: "You scheduled this while reviewing the \(String(localized: due.review.stage.title).lowercased()) outcome.",
        systemImage: "arrowshape.turn.up.right.circle.fill",
        route: .applicationPacket(due.application.id),
        priority: .dueFollowUp,
        onComplete: {
          var completed = due.review
          completed.followUpAt = nil
          applicationStore.saveOutcomeReview(completed, for: due.application.id)
        }
      ))
    }
    let tomorrow = Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date()
    if let interview = applicationStore.upcomingInterviews.first(where: { $0.scheduledAt <= tomorrow }) {
      actions.append(TodayAction(
        id: "interview-\(interview.id)", title: "Prepare for \(interview.company)",
        detail: "Your \(String(localized: interview.format.title).lowercased()) interview is \(interview.scheduledAt.formatted(.relative(presentation: .named))).",
        systemImage: "person.2.wave.2.fill", route: .interviewPrep(interview.applicationID),
        priority: .imminentInterview))
    }
    if let application = applicationStore.applications
      .filter(\.needsCurrentOutcomeReview)
      .sorted(by: { $0.updatedAt > $1.updatedAt })
      .first
    {
      actions.append(TodayAction(
        id: "outcome-review-\(application.id)",
        title: "Learn from \(application.role.nilIfBlank ?? "an application outcome")",
        detail: "Add a one-minute private debrief, then ResumeStudio will recommend one next improvement.",
        systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
        route: .applicationDetail(application.id),
        priority: .outcomeReview
      ))
    }
    if let application = applicationStore.applications.first(where: {
      $0.status == .applied && Date().timeIntervalSince($0.updatedAt) >= 6 * 86_400
    }) {
      actions.append(TodayAction(
        id: "follow-up-\(application.id)", title: "Follow up with \(application.company.nilIfBlank ?? "the employer")",
        detail: "This application has been waiting for about a week.", systemImage: "paperplane.circle.fill",
        route: .applicationPacket(application.id), priority: .application))
    }
    if let application = applicationStore.applications.first(where: { $0.status == .saved && $0.matchAnalysis == nil }) {
      actions.append(TodayAction(
        id: "match-\(application.id)", title: "Finish \(application.role.nilIfBlank ?? "your application")",
        detail: "Analyse the match, tailor the résumé and prepare the application pack.",
        systemImage: "wand.and.stars", route: .applicationPacket(application.id),
        priority: .application))
    }
    let soon = Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date()
    if let review = careerStore.reviewRequests.first(where: {
      $0.hostedURL != nil && $0.status != .closed && $0.status != .revoked && $0.expiresAt <= soon
    }) {
      actions.append(TodayAction(
        id: "review-\(review.id)", title: "Close or refresh a Review Room",
        detail: "The link for \(review.reviewerName.nilIfBlank ?? "your reviewer") expires soon.",
        systemImage: "person.2.badge.gearshape.fill", route: .reviewRoom,
        priority: .expiringHostedWork))
    }
    let atsReport = ATSReadinessService.analyze(document: store.document, jobDescription: "")
    if atsReport.actionCount > 0 {
      actions.append(TodayAction(
        id: "ats-evidence", title: "Resolve missing ATS evidence",
        detail: "\(atsReport.actionCount) readiness item\(atsReport.actionCount == 1 ? " needs" : "s need") your attention.",
        systemImage: "checkmark.shield", route: .atsChecker, priority: .resumeReadiness))
    }
    if !store.document.incompleteSections.isEmpty {
      actions.append(TodayAction(
        id: "resume-incomplete", title: "Complete your résumé",
        detail: "Add \(store.document.incompleteSections.count) missing section\(store.document.incompleteSections.count == 1 ? "" : "s") before applying.",
        systemImage: "doc.badge.ellipsis", route: .editor(store.document.incompleteSections.first),
        priority: .resumeReadiness))
    }
    if let campaignAction { actions.append(campaignAction) }
    if actions.isEmpty {
      actions.append(TodayAction(
        id: "capture", title: "Capture your next opportunity",
        detail: "Start one guided workflow from job advert to interview plan.",
        systemImage: "scope", route: .jobCapture, priority: .campaign))
    }
    return Array(actions.sorted {
      if $0.priority != $1.priority { return $0.priority > $1.priority }
      return $0.id < $1.id
    }.prefix(3))
  }

  private var campaignAction: TodayAction? {
    let gaps: [(ratio: Double, action: TodayAction?)] = [
      (
        Double(max(0, weeklyApplicationGoal - applicationsThisWeek)) / Double(max(weeklyApplicationGoal, 1)),
        applicationsThisWeek < weeklyApplicationGoal ? TodayAction(
          id: "campaign-application", title: "Move your weekly campaign forward",
          detail: "Capture or progress \(weeklyApplicationGoal - applicationsThisWeek) more opportunit\(weeklyApplicationGoal - applicationsThisWeek == 1 ? "y" : "ies") this week.",
          systemImage: "scope", route: .jobCapture, priority: .campaign) : nil
      ),
      (
        Double(max(0, weeklyNetworkingGoal - networkingThisWeek)) / Double(max(weeklyNetworkingGoal, 1)),
        networkingThisWeek < weeklyNetworkingGoal ? TodayAction(
          id: "campaign-networking", title: "Strengthen one career relationship",
          detail: "You have \(weeklyNetworkingGoal - networkingThisWeek) networking touchpoint\(weeklyNetworkingGoal - networkingThisWeek == 1 ? "" : "s") left this week.",
          systemImage: "person.2.wave.2", route: .networking, priority: .campaign) : nil
      ),
      (
        Double(max(0, weeklyPracticeGoal - practiceThisWeek)) / Double(max(weeklyPracticeGoal, 1)),
        practiceThisWeek < weeklyPracticeGoal ? TodayAction(
          id: "campaign-practice", title: "Practise one interview answer",
          detail: "A short voice attempt keeps interview preparation moving.",
          systemImage: "waveform.and.mic", route: .voiceInterview, priority: .campaign) : nil
      ),
    ]
    return gaps.filter { $0.action != nil }.max { $0.ratio < $1.ratio }?.action
  }

  private var today: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("TODAY").eyebrow().foregroundStyle(accent)
          Text("What should I do next?").font(.title2.bold()).foregroundStyle(Theme.ink)
        }
        Spacer()
        Button("Applications") { path.append(.applications) }
          .font(.subheadline.bold()).foregroundStyle(accent)
      }
      ForEach(todayActions) { action in
        HStack(spacing: 0) {
          Button { path.append(action.route) } label: {
            HStack(spacing: 14) {
              Image(systemName: action.systemImage)
                .font(.title3).foregroundStyle(accent)
                .frame(width: 46, height: 46)
                .background(accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 14))
              VStack(alignment: .leading, spacing: 4) {
                Text(action.title).font(.headline).foregroundStyle(Theme.ink)
                Text(action.detail).font(.caption).foregroundStyle(Theme.mutedInk).multilineTextAlignment(.leading)
              }
              Spacer()
              Image(systemName: "chevron.right").foregroundStyle(Theme.mutedInk)
            }
            .padding(15)
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("today.action.\(action.id)")
          if let onComplete = action.onComplete {
            Button(action: onComplete) {
              Image(systemName: "checkmark.circle.fill")
                .font(.title2).foregroundStyle(.green)
                .padding(.trailing, 15)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark follow-up complete")
            .accessibilityIdentifier("today.complete.\(action.id)")
          }
        }
        .cardSurface(radius: 19)
      }
    }
  }

  @AppStorage("campaign.weeklyApplicationGoal") private var weeklyApplicationGoal = 4
  @AppStorage("campaign.weeklyNetworkingGoal") private var weeklyNetworkingGoal = 3
  @AppStorage("campaign.weeklyPracticeGoal") private var weeklyPracticeGoal = 1

  private var campaign: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button { path.append(.campaign) } label: {
        VStack(alignment: .leading, spacing: 14) {
          HStack {
            Label("WEEKLY CAMPAIGN", systemImage: "chart.line.uptrend.xyaxis")
              .eyebrow().foregroundStyle(accent)
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Theme.mutedInk)
          }
          campaignProgress("Opportunities", value: applicationsThisWeek, goal: weeklyApplicationGoal)
          campaignProgress("Relationships", value: networkingThisWeek, goal: weeklyNetworkingGoal)
          campaignProgress("Practice", value: practiceThisWeek, goal: weeklyPracticeGoal)
        }
        .padding(18).cardSurface(radius: 20)
      }
      .buttonStyle(.plain)

      TipView(CaptureJobTip()) { _ in path.append(.jobCapture) }
        .tint(accent)
    }
  }

  private func campaignProgress(_ title: LocalizedStringResource, value: Int, goal: Int)
    -> some View
  {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
        Spacer()
        Text("\(min(value, goal))/\(goal)").font(.caption.bold()).foregroundStyle(Theme.mutedInk)
      }
      ProgressView(value: Double(min(value, goal)), total: Double(max(goal, 1))).tint(accent)
    }
  }

  /// Render the first stretch of template and cover-letter previews ahead of
  /// being scrolled to, so the carousels and gallery are warm even on the very
  /// first launch. Re-runs when the accent changes so the quick-pick swatches
  /// preview instantly. The gate keeps this from competing with visible cards.
  private func warmThumbnails() async {
    // Just beyond what the carousels show at rest — enough that a first scroll or
    // an accent change lands on warm cards, without speculatively rendering the
    // whole catalogue on every accent tap.
    let doc = store.document
    await TemplateThumbnailRenderer.prewarm(
      templates: Array(ResumeTemplate.allCases.prefix(8)),
      accent: doc.accent, photo: doc.photo, crop: doc.photoCrop,
      isPhotoVisible: doc.isPhotoVisible
    )
    await CoverLetterThumbnailRenderer.prewarm(
      templates: Array(CoverLetterTemplate.allCases.prefix(6)),
      accent: doc.accent)
  }

  /// A row of accent swatches under the template header. Colour lived only in the
  /// editor's Template & Colour screen; here it recolours the preview cards live
  /// while you browse looks. Shared with the full gallery.
  private var accentQuickPick: some View {
    AccentQuickPickRow(
      selection: $store.document.accent,
      canUse: { purchases.canUse($0) },
      onLocked: { purchases.requestPlans() }
    )
  }

  // MARK: - Hero

  private var hero: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 8) {
        Circle()
          .fill(accent)
          .frame(width: 7, height: 7)
        Text(greeting)
          .eyebrow()
          .foregroundStyle(Theme.heroMutedInk)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
        Spacer(minLength: 12)
        PDFExportWandButton(accent: accent, isWorking: isExportingPDF) {
          exportResumePDF()
        }
      }

      VStack(alignment: .leading, spacing: 12) {
        Text("Build a résumé\nthat feels like you.")
          .font(Theme.display(heroTitleSize))
          .foregroundStyle(Theme.heroInk)
          .lineSpacing(2)
          // The headline is a two-line composition. Translations run longer —
          // German needs about 15% more width — so hold it at two lines and let
          // it scale down, rather than wrapping to three and crowding the
          // subtitle. A third line is only reachable at accessibility sizes.
          .lineLimit(2)
          .minimumScaleFactor(0.7)
          .fixedSize(horizontal: false, vertical: true)

        Text("Edit your story, choose a style, and export a polished PDF in minutes.")
          .font(.subheadline)
          .foregroundStyle(Theme.heroMutedInk)
          .fixedSize(horizontal: false, vertical: true)
      }

      continueButton
      completionBar
      nextStep

      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline) {
          Text("Design library")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.heroInk)
          Spacer()
          Text("Tap to explore")
            .font(.caption2)
            .foregroundStyle(accent.opacity(0.88))
        }

        LazyVGrid(columns: heroLibraryColumns, spacing: 8) {
          HeroLibraryShortcut(
            value: "\(ResumeTemplate.allCases.count)",
            label: "Templates",
            systemImage: "square.grid.2x2.fill",
            accent: accent
          ) { path.append(.gallery) }
            .accessibilityIdentifier("home.stat.templates")

          HeroLibraryShortcut(
            value: "\(ResumeAccent.allCases.count)",
            label: "Accents",
            systemImage: "paintpalette.fill",
            accent: accent
          ) { showAccentPicker = true }
            .accessibilityIdentifier("home.stat.accents")

          HeroLibraryShortcut(
            value: "\(CoverLetterTemplate.allCases.count)",
            label: "Cover letters",
            systemImage: "envelope.open.fill",
            accent: accent
          ) { scrollRequest = ScrollRequest(anchor: Self.coverLettersAnchor) }
            .accessibilityIdentifier("home.stat.coverLetters")
        }
      }
      .padding(.top, 4)
    }
    .padding(24)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      ZStack {
        LinearGradient(
          colors: [Theme.heroTop, Theme.heroBottom],
          startPoint: .top,
          endPoint: .bottom
        )
        // Warm light bleeding in behind the headline. Kept faint on purpose:
        // accent over a near-black card desaturates to brown very quickly.
        Circle()
          .fill(accent.opacity(0.13))
          .frame(width: 190, height: 190)
          .blur(radius: 55)
          .offset(x: 140, y: -105)
        Circle()
          .fill(accent.opacity(0.06))
          .frame(width: 160, height: 160)
          .blur(radius: 55)
          .offset(x: -145, y: 155)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: Theme.heroRadius, style: .continuous))
    .overlay {
      // Keeps the card's edge legible in dark mode, where it sits on near-black.
      RoundedRectangle(cornerRadius: Theme.heroRadius, style: .continuous)
        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
    }
    .shadow(color: Theme.ink.opacity(0.16), radius: 24, y: 14)
  }

  /// One tap from the hero to a shareable PDF. The preview screen still offers
  /// the ATS variant, DOCX and print; this is the straight line to the file.
  private func exportResumePDF() {
    guard !isExportingPDF else { return }
    isExportingPDF = true
    Task { @MainActor in
      defer { isExportingPDF = false }
      do {
        // One frame for the button's working state to land before UIKit takes
        // the main actor for the PDF context.
        await Task.yield()
        let data = try ResumePDFRenderer.render(document: store.document)
        let url = FileManager.default.temporaryDirectory
          .appendingPathComponent(store.document.suggestedFilename)
          .appendingPathExtension("pdf")
        try data.write(to: url, options: .atomic)
        exportShare = HomeShareItem(url: url)
        ProductInsights.record(.documentExported, once: true)
      } catch {
        exportError = error.localizedDescription
      }
    }
  }

  private var continueButton: some View {
    Button {
      path.append(.editor(nil))
    } label: {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Continue editing")
            .font(.headline)
          Text("\(draftName) · \(store.document.template.title)")
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.82))
            .lineLimit(1)
        }
        Spacer(minLength: 8)
        Image(systemName: "arrow.right")
          .font(.headline)
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 20)
      .padding(.vertical, 15)
      .frame(maxWidth: .infinity)
      .background(accent, in: Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Continue editing \(draftName)")
  }

  private var completionBar: some View {
    VStack(spacing: 8) {
      HStack {
        Text("Résumé complete")
          .font(.subheadline)
          .foregroundStyle(Theme.heroMutedInk)
        Spacer()
        Text("\(store.document.completionPercentage)%")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Theme.heroInk)
      }

      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          Capsule()
            .fill(.white.opacity(0.10))
          Capsule()
            .fill(accent)
            .frame(width: geometry.size.width * store.document.completion)
        }
      }
      .frame(height: 5)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Résumé \(store.document.completionPercentage) percent complete")
  }

  private var heroLibraryColumns: [GridItem] {
    let count = dynamicTypeSize.isAccessibilitySize ? 1 : 3
    return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
  }

  /// The hero always offers the next move: the first gap to fill while the draft
  /// is incomplete, and the PDF once it isn't.
  @ViewBuilder
  private var nextStep: some View {
    let next = store.document.incompleteSections.first

    Button {
      path.append(next.map { HomeRoute.editor($0) } ?? .preview)
    } label: {
      HStack(spacing: 10) {
        Image(systemName: next?.systemImage ?? "checkmark.seal.fill")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(accent)
          .frame(width: 20)

        VStack(alignment: .leading, spacing: 1) {
          Text(next == nil ? "Ready to export" : "Next up")
            .eyebrow()
            .foregroundStyle(Theme.heroMutedInk)
          // Split rather than `??` — coalescing with a model String types the
          // whole expression as String, which skips the string catalogue and
          // left this line in English on a translated build.
          Group {
            if let prompt = next?.prompt {
              Text(prompt)
            } else {
              Text("Preview and share your PDF")
            }
          }
          .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.heroInk)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        }

        Spacer(minLength: 8)

        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(Theme.heroMutedInk)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 11)
      .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  // MARK: - Start creating

  private var quickStart: some View {
    VStack(alignment: .leading, spacing: 14) {
      SectionHeading(
        title: "Start creating",
        subtitle: "Use example content or begin with a clean page."
      )

      HStack(spacing: 12) {
        QuickStartCard(
          title: "Example Résumé",
          subtitle: "A complete, fictional sample",
          systemImage: "doc.text.fill",
          badge: accent,
          badgeForeground: .white
        ) {
          pendingStart = .example
        }

        QuickStartCard(
          title: "Blank Résumé",
          subtitle: "Build every section yourself",
          systemImage: "plus",
          // Inverted rather than a fixed dark: a navy badge vanishes on a dark card.
          badge: Theme.ink,
          badgeForeground: Theme.paper
        ) {
          pendingStart = .blank
        }
      }
    }
  }

  private var workspace: some View {
    VStack(alignment: .leading, spacing: 14) {
      SectionHeading(
        title: "Career workspace",
        subtitle: "Keep every résumé version and application connected."
      )

      VStack(spacing: 12) {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
          WorkspaceCard(
            title: "My résumés",
            detail: "\(store.resumes.count) version\(store.resumes.count == 1 ? "" : "s")",
            systemImage: "doc.on.doc.fill",
            artworkName: "WorkspaceResumes",
            accent: accent
          ) { path.append(.resumeLibrary) }
          WorkspaceCard(
            title: "Applications",
            detail: "\(applicationStore.applications.count) tracked",
            systemImage: "rectangle.3.group.fill",
            artworkName: "WorkspaceApplications",
            accent: accent
          ) { path.append(.applications) }
          WorkspaceCard(
            title: "Interview prep",
            detail: applicationStore.upcomingInterviews.isEmpty
              ? "Practice and plan" : "\(applicationStore.upcomingInterviews.count) upcoming",
            systemImage: "person.wave.2.fill",
            artworkName: "WorkspaceInterview",
            accent: accent
          ) { path.append(.interviewCenter) }
          WorkspaceCard(
            title: "ATS check",
            detail: "Evidence-based review",
            systemImage: "checkmark.shield.fill",
            artworkName: "WorkspaceATS",
            accent: accent
          ) { path.append(.atsChecker) }
        }

        Button {
          path.append(.smartLinks)
        } label: {
          HStack(spacing: 16) {
            ZStack {
              RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(accent.opacity(0.14))
              Image(systemName: "link")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(accent)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 4) {
              Text("Trackable links")
                .font(.headline)
                .foregroundStyle(Theme.ink)
              Text(smartLinks.links.isEmpty
                ? "Know when a recruiter reads your résumé"
                : "\(smartLinks.activeCount) live · know when you're read")
                .font(.caption)
                .foregroundStyle(Theme.mutedInk)
            }

            Spacer()

            if smartLinks.unseenOpens > 0 {
              Text("\(smartLinks.unseenOpens) new")
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(accent, in: Capsule())
                .foregroundStyle(.white)
            }
            Image(systemName: "chevron.right")
              .font(.footnote.weight(.semibold))
              .foregroundStyle(Theme.mutedInk)
          }
          .padding(14)
          .cardSurface(radius: Theme.tileRadius)
          // Pin the tap target to the visible card. Without this the adjacent
          // Import card's hit frame (its artwork fills past its bounds) bleeds
          // up over this row and steals the tap — routing "Trackable links"
          // into the importer.
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        Button {
          path.append(.personalProfile)
        } label: {
          HStack(spacing: 16) {
            ZStack {
              RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(accent.opacity(0.14))
              Image(systemName: "globe")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(accent)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 4) {
              Text("CV page")
                .font(.headline)
                .foregroundStyle(Theme.ink)
              Text(personalProfile.profile.map { "Live · /p/\($0.handle)" }
                ?? "A permanent link for your résumé")
                .font(.caption)
                .foregroundStyle(Theme.mutedInk)
                .lineLimit(1)
                .truncationMode(.middle)
            }

            Spacer()

            if personalProfile.profile != nil {
              Text("Live")
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(accent, in: Capsule())
                .foregroundStyle(.white)
            }
            Image(systemName: "chevron.right")
              .font(.footnote.weight(.semibold))
              .foregroundStyle(Theme.mutedInk)
          }
          .padding(14)
          .cardSurface(radius: Theme.tileRadius)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        WorkspaceCard(
          title: "Import résumé",
          detail: "PDF, DOCX or LinkedIn",
          systemImage: "square.and.arrow.down.fill",
          artworkName: "WorkspaceImport",
          accent: accent,
          isWide: true
        ) { path.append(.importResume) }
      }
      .frame(maxWidth: .infinity)
    }
  }

  // MARK: - AI career tools

  private var aiCareerTools: some View {
    VStack(alignment: .leading, spacing: 14) {
      SectionHeading(
        title: "AI career tools",
        subtitle: "Write stronger content without losing control of your facts."
      )

      CareerIntelligencePromoCard(accent: accent) {
        path.append(.careerIntelligence)
      }

      Button {
        path.append(.jobTargeting)
      } label: {
        HStack(spacing: 16) {
          ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
              .fill(accent.opacity(0.14))
            Image(systemName: "wand.and.stars")
              .font(.system(size: 21, weight: .semibold))
              .foregroundStyle(accent)
          }
          .frame(width: 54, height: 54)

          VStack(alignment: .leading, spacing: 4) {
            Text("Target a job")
              .font(.headline)
              .foregroundStyle(Theme.ink)
            Text("Match the advert, find gaps, and create a reviewed tailored draft.")
              .font(.caption)
              .foregroundStyle(Theme.mutedInk)
              .fixedSize(horizontal: false, vertical: true)
          }

          Spacer(minLength: 4)
          Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.mutedInk)
        }
        .padding(17)
        .cardSurface()
      }
      .buttonStyle(.plain)
    }
  }

  // MARK: - Templates

  private var templates: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .firstTextBaseline) {
        SectionHeading(
          title: "Choose your look",
          subtitle: "Every template exports as a searchable PDF."
        )
        Spacer(minLength: 12)
        Button {
          path.append(.gallery)
        } label: {
          Text("See all \(ResumeTemplate.allCases.count)")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(accent)
        }
      }

      accentQuickPick

      ScrollView(.horizontal, showsIndicators: false) {
        // Lazy: each card renders a real PDF to make its thumbnail, and the
        // catalogue is now long enough that doing all of them up front would
        // stall the home screen.
        LazyHStack(alignment: .top, spacing: 16) {
          ForEach(ResumeTemplate.allCases) { template in
            Button {
              guard purchases.canUse(template) else {
                purchases.requestPlans()
                return
              }
              // Choosing a look changes the look. It used to shove you into the
              // text editor, which is not what this section offers.
              withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                store.document.template = template
              }
            } label: {
              ZStack(alignment: .topTrailing) {
                TemplatePreviewCard(
                  template: template,
                  accent: store.document.accent,
                  isSelected: store.document.template == template,
                  photo: store.document.photo,
                  photoCrop: store.document.photoCrop,
                  isPhotoVisible: store.document.isPhotoVisible
                )
                if !purchases.canUse(template) { PlanLockBadge().padding(8) }
              }
            }
            .buttonStyle(.plain)
            .templatePreviewShareMenu(
              template: template,
              accent: store.document.accent,
              photo: store.document.photo,
              crop: store.document.photoCrop,
              isPhotoVisible: store.document.isPhotoVisible
            )
          }
        }
        .padding(.vertical, 6)
      }
      .contentMargins(.horizontal, 1, for: .scrollContent)
      .sensoryFeedback(.selection, trigger: store.document.template)

      Button {
        path.append(.editor(nil))
      } label: {
        Label("Use this look", systemImage: "pencil.and.outline")
          .font(.headline)
          .foregroundStyle(accent)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 13)
          .background(Theme.card, in: Capsule())
          .overlay {
            CenterOutCapsuleOutline(
              color: accent,
              trigger: store.document.template.id
            )
          }
      }
      .buttonStyle(.plain)
      .accessibilityHint("Opens the résumé editor with the selected template")
    }
  }

  // MARK: - Cover letters

  private var coverLetters: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .firstTextBaseline) {
        SectionHeading(
          title: "Cover letter templates",
          subtitle: "\(CoverLetterTemplate.allCases.count) editable styles with PDF export."
        )
        Spacer(minLength: 12)
        Button("Create") { openCoverLetterEditor() }
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(accent)
      }

      ScrollView(.horizontal, showsIndicators: false) {
        LazyHStack(alignment: .top, spacing: 16) {
          ForEach(CoverLetterTemplate.allCases) { template in
            Button {
              guard purchases.canUse(template) else {
                purchases.requestPlans()
                return
              }
              withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                coverLetterStore.document.template = template
                coverLetterStore.document.accent = store.document.accent
              }
            } label: {
              ZStack(alignment: .topTrailing) {
                CoverLetterTemplateCard(
                  template: template,
                  accent: store.document.accent,
                  isSelected: coverLetterStore.document.template == template
                )
                if !purchases.canUse(template) { PlanLockBadge().padding(8) }
              }
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.vertical, 6)
      }
      .contentMargins(.horizontal, 1, for: .scrollContent)

      Button {
        openCoverLetterEditor()
      } label: {
        Label("Edit cover letter", systemImage: "envelope.open.fill")
          .font(.headline)
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
          .background(accent, in: Capsule())
      }
      .buttonStyle(.plain)
    }
  }

  private func openCoverLetterEditor() {
    if coverLetterStore.document.senderName.isBlank {
      coverLetterStore.syncContact(from: store.document)
    }
    path.append(.coverLetterEditor)
  }

  // MARK: - Recently edited

  private var recentlyEdited: some View {
    VStack(alignment: .leading, spacing: 14) {
      SectionHeading(title: "Recently edited", subtitle: nil)

      Button {
        path.append(.editor(nil))
      } label: {
        HStack(spacing: 14) {
          ZStack {
            Circle().fill(accent.opacity(0.14))
            Image(systemName: "doc.text.fill")
              .font(.system(size: 17, weight: .semibold))
              .foregroundStyle(accent)
          }
          .frame(width: 46, height: 46)

          VStack(alignment: .leading, spacing: 5) {
            Text(draftName)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(Theme.ink)
              .lineLimit(1)
            Text("\(store.document.template.title) · \(store.document.accent.title)")
              .font(.caption)
              .foregroundStyle(Theme.mutedInk)
              .lineLimit(1)

            GeometryReader { geometry in
              ZStack(alignment: .leading) {
                Capsule().fill(Theme.muted)
                Capsule()
                  .fill(accent)
                  .frame(width: geometry.size.width * store.document.completion)
              }
            }
            .frame(height: 3)
            .padding(.top, 1)
          }

          VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 4) {
              Image(systemName: "clock")
              Text(editedRelativeTime)
            }
            .font(.caption2)
            .foregroundStyle(Theme.mutedInk)

            Image(systemName: "chevron.right")
              .font(.caption.weight(.semibold))
              .foregroundStyle(Theme.mutedInk.opacity(0.7))
          }
        }
        .padding(16)
        .cardSurface(radius: 26)
      }
      .buttonStyle(.plain)
    }
  }

  // MARK: - Privacy

  private var privacyNote: some View {
    HStack(spacing: 14) {
      ZStack {
        Circle().fill(accent.opacity(0.14))
        Image(systemName: "lock.shield.fill")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(accent)
      }
      .frame(width: 40, height: 40)

      VStack(alignment: .leading, spacing: 3) {
        Text("Private by default")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Theme.ink)
        Text("Drafts stay on this device. Only the résumé text needed for an AI action is sent after you tap it.")
          .font(.caption)
          .foregroundStyle(Theme.mutedInk)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(16)
    .background(Theme.muted, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
  }

  // MARK: - Derived copy

  private var draftName: String {
    store.document.personal.fullName.nilIfBlank ?? "Untitled Résumé"
  }

  private var greeting: LocalizedStringResource {
    guard let name = store.document.personal.fullName.nilIfBlank,
      let first = name.split(separator: " ").first
    else { return "Welcome" }
    return "Welcome back, \(String(first))"
  }

  private var editedRelativeTime: String {
    let elapsed = Date().timeIntervalSince(store.lastEditedAt)
    guard elapsed >= 60 else { return "just now" }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: store.lastEditedAt, relativeTo: Date())
  }
}

private enum StartChoice: String, Identifiable {
  case example
  case blank

  var id: String { rawValue }
}

/// The first-run welcome. Deliberately a single decision — how do you want to
/// start — rather than a multi-screen tour, so it gets out of the way fast.
private struct WelcomeSheet: View {
  @Environment(\.dismiss) private var dismiss
  @ScaledMetric(relativeTo: .title) private var titleSize: CGFloat = 28
  @State private var isBuildingResume = false
  @AppStorage("career.onboardingGoal") private var selectedGoal = ""
  @AppStorage(ProductInsights.enabledKey) private var productInsightsEnabled = false
  let accent: Color
  let templateCount: Int
  let onExample: () -> Void
  let onBlank: () -> Void
  let onImport: () -> Void
  let onTailor: () -> Void
  let onOrganize: () -> Void

  var body: some View {
    // Scrolls if it ever has to (large text sizes), and the close button gets a
    // clear top row of its own — the previous layout was taller than the medium
    // detent, so the button sat jammed under the grabber until you expanded it.
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Spacer()
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 28))
              .symbolRenderingMode(.hierarchical)
              .foregroundStyle(Theme.mutedInk)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Close")
        }

        VStack(alignment: .leading, spacing: 12) {
          ZStack {
            Circle().fill(accent.opacity(0.14))
            Image(systemName: "doc.text.fill")
              .font(.system(size: 26, weight: .semibold))
              .foregroundStyle(accent)
          }
          .frame(width: 58, height: 58)

          Text("Welcome to Resume Studio")
            .font(Theme.display(titleSize))
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
          Text(isBuildingResume
            ? "Choose how to start your résumé. You can change templates at any time."
            : "What would you most like ResumeStudio to help you accomplish first?")
            .font(.subheadline)
            .foregroundStyle(Theme.mutedInk)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)

        VStack(spacing: 12) {
          if isBuildingResume {
            WelcomeChoice(
              title: "Start with an example",
              identifier: "start-with-an-example",
              subtitle: "A complete sample you can edit into your own",
              systemImage: "sparkles", accent: accent, prominent: true, action: onExample)
            WelcomeChoice(
              title: "Start blank", identifier: "start-blank",
              subtitle: "Build every section yourself",
              systemImage: "plus", accent: accent, prominent: false, action: onBlank)
            WelcomeChoice(
              title: "Import a résumé", identifier: "import-a-résumé",
              subtitle: "Bring in a PDF, DOCX or LinkedIn export",
              systemImage: "square.and.arrow.down", accent: accent, prominent: false, action: onImport)
            Button("Back to goals", systemImage: "chevron.left") { isBuildingResume = false }
              .font(.subheadline.weight(.semibold))
          } else {
            WelcomeChoice(
              title: "Build or refresh my résumé",
              identifier: "build-or-refresh-my-résumé",
              subtitle: "Start with one of \(templateCount) templates, a blank page, or an import",
              systemImage: "doc.text.fill", accent: accent, prominent: true
            ) { selectGoal("build"); isBuildingResume = true }
            WelcomeChoice(
              title: "Tailor for a specific role",
              identifier: "tailor-for-a-specific-role",
              subtitle: "Capture a job advert and turn it into a focused application workflow",
              systemImage: "scope", accent: accent, prominent: false
            ) { selectGoal("tailor"); onTailor() }
            WelcomeChoice(
              title: "Organise my job search",
              identifier: "organise-my-job-search",
              subtitle: "Track applications, interviews, follow-ups and next actions",
              systemImage: "rectangle.3.group.fill", accent: accent, prominent: false
            ) { selectGoal("organize"); onOrganize() }
          }
        }
        .padding(.top, 26)

        if !isBuildingResume {
          Toggle(isOn: $productInsightsEnabled) {
            VStack(alignment: .leading, spacing: 3) {
              Text("Share anonymous product insights").font(.subheadline.weight(.semibold))
              Text("Optional aggregate counters only—never résumé text, identity, job details, links or a device ID.")
                .font(.caption).foregroundStyle(Theme.mutedInk)
            }
          }
          .accessibilityIdentifier("onboarding.productInsights")
          .padding(.top, 18)
          .onChange(of: productInsightsEnabled) { _, enabled in
            if enabled { ProductInsights.flushPending() }
          }
        }
      }
      .padding(.horizontal, 24)
      .padding(.top, 16)
      .padding(.bottom, 28)
    }
    .presentationDetents([.fraction(0.7), .large])
    .presentationDragIndicator(.hidden)
  }

  private func selectGoal(_ goal: String) {
    selectedGoal = goal
    ProductInsights.record(.onboardingGoalSelected, once: true, goal: goal)
  }
}

private struct CaptureJobTip: Tip {
  var title: Text { Text("Save a job advert from Safari") }
  var message: Text? { Text("Share a job page to ResumeStudio to begin tailoring without copying it by hand.") }
  var image: Image? { Image(systemName: "safari.fill") }
}

private struct CareerCampaignView: View {
  @EnvironmentObject private var resumeStore: ResumeStore
  @AppStorage("campaign.targetRole") private var targetRole = ""
  @AppStorage("campaign.weeklyApplicationGoal") private var applicationGoal = 4
  @AppStorage("campaign.weeklyNetworkingGoal") private var networkingGoal = 3
  @AppStorage("campaign.weeklyPracticeGoal") private var practiceGoal = 1
  let applicationsThisWeek: Int
  let networkingThisWeek: Int
  let practiceThisWeek: Int

  var body: some View {
    List {
      Section {
        PremiumFeatureHero(
          eyebrow: "FOCUSED MOMENTUM",
          title: "Run a calmer weekly job-search campaign.",
          subtitle: "Choose a direction and let Today turn it into small, useful next actions.",
          icon: "chart.line.uptrend.xyaxis", accent: resumeStore.document.accent.color)
        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
      }
      Section("Direction") {
        TextField("Target role or career direction", text: $targetRole)
          .textInputAutocapitalization(.words)
      }
      goalSection("Opportunities", systemImage: "scope", value: applicationsThisWeek, goal: $applicationGoal, range: 1...12)
      goalSection("Relationships", systemImage: "person.2.wave.2", value: networkingThisWeek, goal: $networkingGoal, range: 1...10)
      goalSection("Interview practice", systemImage: "waveform.and.mic", value: practiceThisWeek, goal: $practiceGoal, range: 1...7)
      Section {
        Text("Counts reset each calendar week. ResumeStudio keeps these goals and activity records on your device unless you enable iCloud sync.")
          .font(.caption).foregroundStyle(Theme.mutedInk)
      }
    }
    .scrollContentBackground(.hidden).background(Theme.paper)
    .navigationTitle("Weekly campaign")
  }

  private func goalSection(
    _ title: String, systemImage: String, value: Int, goal: Binding<Int>, range: ClosedRange<Int>
  ) -> some View {
    Section {
      HStack {
        Label(title, systemImage: systemImage)
        Spacer()
        Text("\(min(value, goal.wrappedValue))/\(goal.wrappedValue)").font(.subheadline.bold())
      }
      ProgressView(value: Double(min(value, goal.wrappedValue)), total: Double(max(goal.wrappedValue, 1)))
        .tint(resumeStore.document.accent.color)
      Stepper("Weekly goal: \(goal.wrappedValue)", value: goal, in: range)
        .accessibilityIdentifier("campaign.goal.\(title.lowercased())")
    }
  }
}

private struct WelcomeChoice: View {
  let title: LocalizedStringResource
  /// Stable across languages — the accessibility identifier below is a test
  /// hook, so it can't be derived from translated display copy.
  let identifier: String
  let subtitle: LocalizedStringResource
  let systemImage: String
  let accent: Color
  let prominent: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 14) {
        ZStack {
          RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(prominent ? Color.white.opacity(0.18) : accent.opacity(0.14))
          Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(prominent ? .white : accent)
        }
        .frame(width: 44, height: 44)

        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(prominent ? .white : Theme.ink)
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(prominent ? .white.opacity(0.85) : Theme.mutedInk)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 8)
        Image(systemName: "arrow.right")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(prominent ? .white : accent)
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        prominent ? AnyShapeStyle(accent) : AnyShapeStyle(Theme.card),
        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
      )
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("onboarding.choice.\(identifier)")
  }
}

private struct WorkspaceCard: View {
  var title: String
  var detail: String
  var systemImage: String
  var artworkName: String
  var accent: Color
  var isWide = false
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      Group {
        if isWide {
          ZStack {
            Image(artworkName)
              .resizable()
              .scaledToFill()
              .frame(maxWidth: .infinity, maxHeight: 82, alignment: .trailing)
              .clipped()
              .mask {
                LinearGradient(
                  colors: [.clear, .clear, .black.opacity(0.92)],
                  startPoint: .leading,
                  endPoint: .trailing
                )
              }
              .opacity(0.88)

            HStack(spacing: 14) {
              Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 42, height: 42)
                .background(accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 13))
              VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Text(detail).font(.caption).foregroundStyle(Theme.mutedInk).lineLimit(2)
              }
              Spacer()
              Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.mutedInk)
            }
          }
          .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        } else {
          VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .bottomLeading) {
              Image(artworkName)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 76)
                .clipped()

              LinearGradient(
                colors: [.clear, Theme.card.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
              )

              Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding(7)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            Text(detail).font(.caption).foregroundStyle(Theme.mutedInk).lineLimit(2)
          }
          .frame(maxWidth: .infinity, minHeight: 145, alignment: .topLeading)
        }
      }
      .padding(14)
      .cardSurface(radius: 24)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Pieces

private struct ResumeThumbnailWarmKey: Hashable {
  let accent: ResumeAccent
  let photo: Data?
  let crop: PhotoCrop?
  let isPhotoVisible: Bool
}

private struct HeroLibraryShortcut: View {
  let value: String
  // Localizable: `value` is a formatted number and stays a String, but the label
  // is UI copy and has to reach the string catalogue.
  let label: LocalizedStringResource
  let systemImage: String
  let accent: Color
  let action: () -> Void
  @ScaledMetric(relativeTo: .title2) private var valueSize: CGFloat = 24

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Image(systemName: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(accent)
            .frame(width: 30, height: 30)
            .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

          Spacer(minLength: 4)

          Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Theme.heroMutedInk.opacity(0.75))
        }

        Spacer(minLength: 10)

        Text(value)
          .font(.system(size: valueSize, weight: .bold))
          .foregroundStyle(Theme.heroInk)
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.6)

        Text(label)
          .font(.caption.weight(.medium))
          .foregroundStyle(accent)
          .lineLimit(2)
          .minimumScaleFactor(0.75)
      }
      .padding(11)
      .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
      .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .strokeBorder(.white.opacity(0.075), lineWidth: 1)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(HeroLibraryButtonStyle())
    .accessibilityLabel("\(label), \(value) available")
    .accessibilityAddTraits(.isButton)
  }
}

private struct HeroLibraryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .opacity(configuration.isPressed ? 0.82 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

/// The PDF export, kept separate from the design library in the hero's top-right
/// corner where it reads as the card's one action. The sparkles orbit behind the
/// pill and twinkle out of step with each other; Reduce Motion gets the same
/// scatter, held still.
private struct PDFExportWandButton: View {
  let accent: Color
  let isWorking: Bool
  let action: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isOrbiting = false
  @State private var isGlowing = false

  private struct Sparkle: Identifiable {
    let id = UUID()
    /// Where the sparkle sits on the orbit, in degrees.
    let angle: Double
    let size: CGFloat
    let delay: Double
    let restingOpacity: Double
  }

  // Deliberately uneven spacing — evenly spaced sparkles read as a loading
  // spinner rather than as scattered light.
  private let sparkles: [Sparkle] = [
    Sparkle(angle: -74, size: 9, delay: 0, restingOpacity: 0.9),
    Sparkle(angle: -18, size: 6, delay: 0.55, restingOpacity: 0.65),
    Sparkle(angle: 62, size: 7.5, delay: 1.1, restingOpacity: 0.8),
    Sparkle(angle: 128, size: 5.5, delay: 0.35, restingOpacity: 0.6),
    Sparkle(angle: 206, size: 8, delay: 1.45, restingOpacity: 0.85),
  ]

  private let orbitRadius: CGFloat = 33

  var body: some View {
    Button(action: action) {
      pill
        // A background so the orbit spills past the pill without widening the
        // greeting row, and so a sparkle crossing the label passes behind it.
        .background { sparkleField }
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .disabled(isWorking)
    .accessibilityLabel("Export PDF")
    .accessibilityHint("Renders your résumé and opens the share sheet")
    .accessibilityIdentifier("home.export.pdf")
    .onAppear {
      guard !reduceMotion else { return }
      withAnimation(.linear(duration: 16).repeatForever(autoreverses: false)) {
        isOrbiting = true
      }
      withAnimation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true)) {
        isGlowing = true
      }
    }
  }

  private var pill: some View {
    HStack(spacing: 6) {
      Group {
        if isWorking {
          ProgressView().controlSize(.mini).tint(accent)
        } else {
          Image(systemName: "wand.and.stars")
            .font(.system(size: 14, weight: .semibold))
        }
      }
      .frame(width: 16)
      Text("PDF")
        .font(.caption.weight(.bold))
        .tracking(0.6)
    }
    .foregroundStyle(accent)
    .padding(.horizontal, 13)
    .padding(.vertical, 8)
    .background {
      Capsule()
        .fill(accent.opacity(0.16))
        .overlay { Capsule().strokeBorder(accent.opacity(0.45), lineWidth: 1) }
    }
    .shadow(color: accent.opacity(isGlowing ? 0.5 : 0.18), radius: isGlowing ? 13 : 6)
  }

  private var sparkleField: some View {
    ZStack {
      ForEach(sparkles) { sparkle in
        SparkleMote(
          sparkle: sparkle,
          accent: accent,
          radius: orbitRadius,
          isAnimated: !reduceMotion
        )
      }
    }
    .rotationEffect(.degrees(isOrbiting ? 360 : 0))
    .allowsHitTesting(false)
  }

  private struct SparkleMote: View {
    let sparkle: Sparkle
    let accent: Color
    let radius: CGFloat
    let isAnimated: Bool

    @State private var isLit = false

    var body: some View {
      Image(systemName: "sparkle")
        .font(.system(size: sparkle.size, weight: .semibold))
        .foregroundStyle(accent)
        .opacity(isLit ? sparkle.restingOpacity : 0.12)
        .scaleEffect(isLit ? 1 : 0.55)
        .offset(
          x: radius * cos(sparkle.angle * .pi / 180),
          y: radius * sin(sparkle.angle * .pi / 180)
        )
        // Cancels the field's rotation so each sparkle stays upright as it travels.
        .rotationEffect(.degrees(-sparkle.angle))
        .onAppear {
          guard isAnimated else {
            isLit = true
            return
          }
          withAnimation(
            .easeInOut(duration: 1.4)
              .repeatForever(autoreverses: true)
              .delay(sparkle.delay)
          ) {
            isLit = true
          }
        }
    }
  }
}

/// The full accent palette, opened from the hero's Accents shortcut. The quick-pick
/// row under the templates only shows swatches; this names them and marks what
/// the plan covers.
private struct AccentPickerSheet: View {
  @Binding var selection: ResumeAccent
  let canUse: (ResumeAccent) -> Bool
  let onLocked: () -> Void

  @Environment(\.dismiss) private var dismiss

  private let columns = [GridItem(.adaptive(minimum: 104), spacing: 14)]

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVGrid(columns: columns, spacing: 14) {
          ForEach(ResumeAccent.allCases) { option in
            swatch(option)
          }
        }
        .padding(20)
      }
      .background(Theme.paper)
      .navigationTitle("Accent colour")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(Theme.paper, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }.tint(selection.color)
        }
      }
    }
  }

  private func swatch(_ option: ResumeAccent) -> some View {
    let unlocked = canUse(option)
    let selected = selection == option
    return Button {
      guard unlocked else {
        onLocked()
        return
      }
      withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { selection = option }
    } label: {
      VStack(spacing: 10) {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(option.color)
          .frame(height: 58)
          .overlay {
            if !unlocked {
              Image(systemName: "lock.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 1)
            } else if selected {
              Image(systemName: "checkmark")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 1)
            }
          }
        Text(option.title)
          .font(.footnote.weight(.medium))
          .foregroundStyle(Theme.ink)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
      .padding(10)
      .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .strokeBorder(selected ? option.color : Color.clear, lineWidth: 2)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(option.title) accent\(option.isPremium ? ", premium" : "")")
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

/// A rendered PDF on its way to the share sheet from the home screen.
private struct HomeShareItem: Identifiable {
  let url: URL
  var id: URL { url }
}

private struct SectionHeading: View {
  let title: LocalizedStringResource
  let subtitle: LocalizedStringResource?

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.title3.weight(.bold))
        .foregroundStyle(Theme.ink)
      if let subtitle {
        Text(subtitle)
          .font(.subheadline)
          .foregroundStyle(Theme.mutedInk)
      }
    }
  }
}

private struct QuickStartCard: View {
  let title: LocalizedStringResource
  let subtitle: LocalizedStringResource
  let systemImage: String
  let badge: Color
  let badgeForeground: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 14) {
        ZStack {
          Circle().fill(badge)
          Image(systemName: systemImage)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(badgeForeground)
        }
        .frame(width: 44, height: 44)

        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Theme.ink)
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(Theme.mutedInk)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
      .padding(18)
      .cardSurface()
    }
    .buttonStyle(.plain)
  }
}

#Preview {
  NavigationStack {
    HomeView()
      .environmentObject(ResumeStore(initialDocument: .example))
      .environmentObject(CoverLetterStore(initialDocument: .example))
  }
}
