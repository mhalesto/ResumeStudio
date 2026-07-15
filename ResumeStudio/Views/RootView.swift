import SwiftUI

struct RootView: View {
  @AppStorage("appAppearance") private var appearanceRawValue = AppAppearance.system.rawValue
  @State private var isSplashComplete = false

  private var appearance: AppAppearance {
    AppAppearance(rawValue: appearanceRawValue) ?? .system
  }

  var body: some View {
    ZStack {
      AppShellView()
        // The app is already laid out behind the splash, so it settles into place
        // rather than appearing cold.
        .opacity(isSplashComplete ? 1 : 0)
        .scaleEffect(isSplashComplete ? 1 : 0.96)

      if !isSplashComplete {
        SplashView {
          withAnimation(.easeInOut(duration: 0.55)) { isSplashComplete = true }
        }
        .transition(.opacity.combined(with: .scale(scale: 1.08)))
        .zIndex(1)
      }
    }
    // Keep the app chrome edge-to-edge from launch onward.
    .statusBarHidden(true)
    // Constant for the app's lifetime, so it can't flip during the hand-off.
    .preferredColorScheme(appearance.colorScheme)
  }
}

private enum AppTab: String, CaseIterable, Identifiable {
  case home
  case documents
  case templates
  case settings

  var id: String { rawValue }

  var title: String {
    switch self {
    case .home: "Home"
    case .documents: "Documents"
    case .templates: "Templates"
    case .settings: "Settings"
    }
  }

  var systemImage: String {
    switch self {
    case .home: "house"
    case .documents: "doc.text"
    case .templates: "rectangle.split.2x1"
    case .settings: "gearshape"
    }
  }
}

private struct AppShellView: View {
  /// Space after the final row in every tab-owned scroll view. The footer itself
  /// is 88 points including its vertical padding; the remainder keeps the last
  /// card or text editor visibly separated from it at the end of a scroll.
  private static let footerScrollClearance: CGFloat = 104

  @EnvironmentObject private var store: ResumeStore
  @EnvironmentObject private var applicationStore: ApplicationStore
  @EnvironmentObject private var purchases: PurchaseManager
  @EnvironmentObject private var referralStore: ReferralStore
  @StateObject private var careerCoachStore = CareerCoachStore()
  @AppStorage("careerCoachIntroDismissed") private var coachIntroDismissed = false
  @State private var selectedTab = AppTab.home
  @State private var isCareerCoachPresented = false
  @State private var isPlansPresented = false
  @State private var isReferralPresented = false

  var body: some View {
    ZStack {
      tabPage(.home) { HomeView() }
      tabPage(.documents) {
        NavigationStack { ResumeLibraryView() }
      }
      tabPage(.templates) {
        NavigationStack { TemplateGalleryView() }
      }
      tabPage(.settings) {
        NavigationStack { SettingsView() }
      }
    }
    .background(Theme.paper.ignoresSafeArea())
    .safeAreaInset(edge: .bottom, spacing: 0) {
      AppFooter(selection: $selectedTab, accent: store.document.accent.color)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Theme.paper)
    }
    .overlay(alignment: .bottomTrailing) {
      FloatingCareerCoachButton(
        accent: store.document.accent.color,
        showIntro: !coachIntroDismissed,
        dismissIntro: {
          withAnimation(.easeInOut(duration: 0.2)) { coachIntroDismissed = true }
        },
        action: { isCareerCoachPresented = true }
      )
      .padding(.trailing, 22)
      .padding(.bottom, 96)
    }
    .sheet(isPresented: $isCareerCoachPresented) {
      CareerCoachView(chatStore: careerCoachStore)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    .fullScreenCover(isPresented: $isPlansPresented) {
      NavigationStack { PlansView() }
    }
    .sheet(isPresented: $isReferralPresented) {
      NavigationStack { ReferralView() }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    .onReceive(NotificationCenter.default.publisher(for: .presentPlans)) { _ in
      isPlansPresented = true
    }
    .onOpenURL { url in
      guard url.scheme == "resumestudio" else { return }
      switch url.host {
      case "capture-job":
        selectedTab = .home
        NotificationCenter.default.post(name: .openSharedJobCapture, object: nil)
      case "applications":
        selectedTab = .home
        NotificationCenter.default.post(name: .openHomeRoute, object: HomeRoute.applications)
      case "ats":
        selectedTab = .home
        NotificationCenter.default.post(name: .openHomeRoute, object: HomeRoute.atsChecker)
      case "interviews":
        selectedTab = .home
        NotificationCenter.default.post(name: .openHomeRoute, object: HomeRoute.interviewCenter)
      case "templates":
        selectedTab = .templates
      case "plans":
        isPlansPresented = true
      case "referral":
        referralStore.accept(url: url)
        isReferralPresented = true
      default:
        break
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .resumeLibraryDidSave)) { _ in
      publishSharedSnapshot()
    }
    .onReceive(NotificationCenter.default.publisher(for: .applicationStoreDidSave)) { _ in
      publishSharedSnapshot()
    }
    .onReceive(NotificationCenter.default.publisher(for: .shortcutRouteQueued)) { _ in
      consumeShortcutRoute()
    }
    .onAppear {
      consumeShortcutRoute()
    }
  }

  private func publishSharedSnapshot() {
    PlatformIntegrationService.publishWidgetSnapshot(
      applications: applicationStore.applications,
      interviews: applicationStore.interviews,
      resume: store.document)
  }

  private func consumeShortcutRoute() {
    guard let route = ShortcutRouteStore.consume() else { return }
    switch route {
    case "applications":
      selectedTab = .home
      NotificationCenter.default.post(name: .openHomeRoute, object: HomeRoute.applications)
    case "ats":
      selectedTab = .home
      NotificationCenter.default.post(name: .openHomeRoute, object: HomeRoute.atsChecker)
    case "templates":
      selectedTab = .templates
    default:
      break
    }
  }

  private func tabPage<Content: View>(
    _ tab: AppTab,
    @ViewBuilder content: () -> Content
  ) -> some View {
    content()
      .contentMargins(.bottom, Self.footerScrollClearance, for: .scrollContent)
      .opacity(selectedTab == tab ? 1 : 0)
      .allowsHitTesting(selectedTab == tab)
      .accessibilityHidden(selectedTab != tab)
      .zIndex(selectedTab == tab ? 1 : 0)
  }
}

extension Notification.Name {
  static let openHomeRoute = Notification.Name("ResumeStudio.openHomeRoute")
}

private struct AppFooter: View {
  @Binding var selection: AppTab
  let accent: Color

  var body: some View {
    HStack(spacing: 0) {
      ForEach(AppTab.allCases) { tab in
        Button {
          withAnimation(.easeInOut(duration: 0.2)) { selection = tab }
        } label: {
          VStack(spacing: 5) {
            Image(systemName: tab.systemImage)
              .font(.system(size: 19, weight: .medium))
              .frame(height: 22)
            Text(tab.title)
              .font(.caption2.weight(.medium))
              .lineLimit(1)
              .minimumScaleFactor(0.85)
          }
          .foregroundStyle(selection == tab ? accent : Theme.mutedInk)
          .frame(maxWidth: .infinity)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
      }
    }
    .padding(.horizontal, 8)
    .frame(height: 72)
    .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 26, style: .continuous)
        .strokeBorder(Theme.hairline, lineWidth: 1)
    }
    .shadow(color: Theme.ink.opacity(0.10), radius: 18, y: 8)
  }
}

#Preview {
  RootView()
    .environmentObject(ResumeStore(initialDocument: .example))
    .environmentObject(CoverLetterStore(initialDocument: .example))
    .environmentObject(ApplicationStore())
    .environmentObject(CareerIntelligenceStore())
    .environmentObject(ICloudSyncService())
    .environmentObject(PurchaseManager.shared)
    .environmentObject(AccountStore())
    .environmentObject(AIArtifactStore())
    .environmentObject(ReferralStore())
}
