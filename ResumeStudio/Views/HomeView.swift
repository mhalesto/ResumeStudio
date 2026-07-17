import SwiftUI

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
}

struct HomeView: View {
  @EnvironmentObject private var store: ResumeStore
  @EnvironmentObject private var coverLetterStore: CoverLetterStore
  @EnvironmentObject private var applicationStore: ApplicationStore
  @EnvironmentObject private var careerStore: CareerIntelligenceStore
  @EnvironmentObject private var purchases: PurchaseManager
  @EnvironmentObject private var smartLinks: SmartLinkStore
  @State private var path: [HomeRoute] = []
  @State private var pendingStart: StartChoice?
  @State private var showWelcome = false
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
      ScrollView {
        VStack(alignment: .leading, spacing: 30) {
          hero
          today
          quickStart
          workspace
          templates
          coverLetters
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
        }
      }
      .sheet(isPresented: $showWelcome, onDismiss: { hasSeenWelcome = true }) {
        WelcomeSheet(
          accent: accent,
          templateCount: ResumeTemplate.allCases.count,
          onExample: {
            showWelcome = false
            path = [.editor(nil)]
          },
          onBlank: {
            store.startBlankResume()
            showWelcome = false
            path = [.editor(store.document.incompleteSections.first)]
          },
          onImport: {
            showWelcome = false
            path = [.importResume]
          }
        )
      }
      .onAppear {
        // First launch only: point people at a starting move before they face
        // the full home screen. The flag is set when the sheet is dismissed, so
        // a launch where presentation is pre-empted doesn't burn the one chance.
        if allowsWelcome && !hasSeenWelcome { showWelcome = true }
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
            path.append(.editor(store.document.incompleteSections.first))
          },
          secondaryButton: .cancel()
        )
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .openSharedJobCapture)) { _ in
      guard acceptsExternalRoutes else { return }
      path = [.jobCapture]
    }
    .onReceive(NotificationCenter.default.publisher(for: .openHomeRoute)) { notification in
      guard acceptsExternalRoutes else { return }
      if let route = notification.object as? HomeRoute { path = [route] }
    }
  }

  private var accent: Color { store.document.accent.color }

  private struct TodayAction: Identifiable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
    let route: HomeRoute
  }

  private var todayActions: [TodayAction] {
    var actions: [TodayAction] = []
    if let read = smartLinks.mostRecentUnseenLink {
      let who = read.company.nilIfBlank ?? "Someone"
      actions.append(TodayAction(
        id: "smart-link-\(read.id)", title: "\(who) read your résumé",
        detail: read.lastSeenAt.map { "Opened \($0.formatted(.relative(presentation: .named))). Follow up while you're on their mind." }
          ?? "Your trackable link has new opens.",
        systemImage: "eye.fill", route: .smartLinks))
    }
    let tomorrow = Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date()
    if let interview = applicationStore.upcomingInterviews.first(where: { $0.scheduledAt <= tomorrow }) {
      actions.append(TodayAction(
        id: "interview-\(interview.id)", title: "Prepare for \(interview.company)",
        detail: "Your \(interview.format.title.lowercased()) interview is \(interview.scheduledAt.formatted(.relative(presentation: .named))).",
        systemImage: "person.2.wave.2.fill", route: .interviewPrep(interview.applicationID)))
    }
    if let application = applicationStore.applications.first(where: {
      $0.status == .applied && Date().timeIntervalSince($0.updatedAt) >= 6 * 86_400
    }) {
      actions.append(TodayAction(
        id: "follow-up-\(application.id)", title: "Follow up with \(application.company.nilIfBlank ?? "the employer")",
        detail: "This application has been waiting for about a week.", systemImage: "paperplane.circle.fill",
        route: .applicationPacket(application.id)))
    }
    if let application = applicationStore.applications.first(where: { $0.status == .saved && $0.matchAnalysis == nil }) {
      actions.append(TodayAction(
        id: "match-\(application.id)", title: "Finish \(application.role.nilIfBlank ?? "your application")",
        detail: "Analyse the match, tailor the résumé and prepare the application pack.",
        systemImage: "wand.and.stars", route: .applicationPacket(application.id)))
    }
    let soon = Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date()
    if let review = careerStore.reviewRequests.first(where: {
      $0.hostedURL != nil && $0.status != .closed && $0.status != .revoked && $0.expiresAt <= soon
    }) {
      actions.append(TodayAction(
        id: "review-\(review.id)", title: "Close or refresh a Review Room",
        detail: "The link for \(review.reviewerName.nilIfBlank ?? "your reviewer") expires soon.",
        systemImage: "person.2.badge.gearshape.fill", route: .reviewRoom))
    }
    let atsReport = ATSReadinessService.analyze(document: store.document, jobDescription: "")
    if atsReport.actionCount > 0 {
      actions.append(TodayAction(
        id: "ats-evidence", title: "Resolve missing ATS evidence",
        detail: "\(atsReport.actionCount) readiness item\(atsReport.actionCount == 1 ? " needs" : "s need") your attention.",
        systemImage: "checkmark.shield", route: .atsChecker))
    }
    if !store.document.incompleteSections.isEmpty {
      actions.append(TodayAction(
        id: "resume-incomplete", title: "Complete your résumé",
        detail: "Add \(store.document.incompleteSections.count) missing section\(store.document.incompleteSections.count == 1 ? "" : "s") before applying.",
        systemImage: "doc.badge.ellipsis", route: .editor(store.document.incompleteSections.first)))
    }
    if actions.isEmpty {
      actions.append(TodayAction(
        id: "capture", title: "Capture your next opportunity",
        detail: "Start one guided workflow from job advert to interview plan.",
        systemImage: "scope", route: .jobCapture))
    }
    return Array(actions.prefix(3))
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
          .padding(15).cardSurface(radius: 19)
        }
        .buttonStyle(.plain)
      }
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
      }

      VStack(alignment: .leading, spacing: 12) {
        Text("Build a résumé\nthat feels like you.")
          .font(Theme.display(heroTitleSize))
          .foregroundStyle(Theme.heroInk)
          .lineSpacing(2)
          .fixedSize(horizontal: false, vertical: true)

        Text("Edit your story, choose a style, and export a polished PDF in minutes.")
          .font(.subheadline)
          .foregroundStyle(Theme.heroMutedInk)
          .fixedSize(horizontal: false, vertical: true)
      }

      continueButton
      completionBar
      nextStep

      HStack(spacing: 0) {
        HeroStat(value: "\(ResumeTemplate.allCases.count)", label: "Templates")
        statDivider
        HeroStat(value: "\(ResumeAccent.allCases.count)", label: "Accents")
        statDivider
        HeroStat(value: "PDF", label: "Export")
      }
      .padding(.top, 2)
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
          Text(next?.prompt ?? "Preview and share your PDF")
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

  private var statDivider: some View {
    Rectangle()
      .fill(.white.opacity(0.10))
      .frame(width: 1, height: 34)
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

  private var greeting: String {
    guard let name = store.document.personal.fullName.nilIfBlank,
      let first = name.split(separator: " ").first
    else { return "Welcome" }
    return "Welcome back, \(first)"
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
  let accent: Color
  let templateCount: Int
  let onExample: () -> Void
  let onBlank: () -> Void
  let onImport: () -> Void

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
          Text("\(templateCount) templates, private on-device drafts, and a polished PDF in minutes. How would you like to start?")
            .font(.subheadline)
            .foregroundStyle(Theme.mutedInk)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)

        VStack(spacing: 12) {
          WelcomeChoice(
            title: "Start with an example",
            subtitle: "A complete sample you can edit into your own",
            systemImage: "sparkles",
            accent: accent,
            prominent: true,
            action: onExample
          )
          WelcomeChoice(
            title: "Start blank",
            subtitle: "Build every section yourself",
            systemImage: "plus",
            accent: accent,
            prominent: false,
            action: onBlank
          )
          WelcomeChoice(
            title: "Import a résumé",
            subtitle: "Bring in a PDF, DOCX or LinkedIn export",
            systemImage: "square.and.arrow.down",
            accent: accent,
            prominent: false,
            action: onImport
          )
        }
        .padding(.top, 26)
      }
      .padding(.horizontal, 24)
      .padding(.top, 16)
      .padding(.bottom, 28)
    }
    .presentationDetents([.fraction(0.7), .large])
    .presentationDragIndicator(.hidden)
  }
}

private struct WelcomeChoice: View {
  let title: String
  let subtitle: String
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

private struct HeroStat: View {
  let value: String
  let label: String
  // Scales with Dynamic Type; the shrink guards keep three across from clipping
  // at the largest accessibility sizes.
  @ScaledMetric(relativeTo: .title3) private var valueSize: CGFloat = 20

  var body: some View {
    VStack(spacing: 3) {
      Text(value)
        .font(.system(size: valueSize, weight: .bold))
        .foregroundStyle(Theme.heroInk)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
      Text(label)
        .eyebrow()
        .foregroundStyle(Theme.heroMutedInk)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
    .frame(maxWidth: .infinity)
  }
}

private struct SectionHeading: View {
  let title: String
  let subtitle: String?

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
  let title: String
  let subtitle: String
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
