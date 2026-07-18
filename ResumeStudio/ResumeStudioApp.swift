import FirebaseAppCheck
import FirebaseCore
import SwiftUI
import TipKit

@main
struct ResumeStudioApp: App {
  private static var didConfigureFirebase = false
  @StateObject private var store = ResumeStore()
  @StateObject private var coverLetterStore = CoverLetterStore()
  @StateObject private var applicationStore = ApplicationStore()
  @StateObject private var careerIntelligenceStore = CareerIntelligenceStore()
  @StateObject private var cloudSync = ICloudSyncService()
  @StateObject private var purchases = PurchaseManager.shared
  @StateObject private var account = AccountStore()
  @StateObject private var aiArtifacts = AIArtifactStore.shared
  @StateObject private var referrals = ReferralStore()
  @StateObject private var network = NetworkMonitor.shared
  @StateObject private var smartLinks = SmartLinkStore()
  @StateObject private var personalProfile = PersonalProfileStore()

  init() {
    try? Tips.configure([
      .displayFrequency(.weekly),
      .datastoreLocation(.applicationDefault),
    ])
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(store)
        .environmentObject(coverLetterStore)
        .environmentObject(applicationStore)
        .environmentObject(careerIntelligenceStore)
        .environmentObject(cloudSync)
        .environmentObject(purchases)
        .environmentObject(account)
        .environmentObject(aiArtifacts)
        .environmentObject(referrals)
        .environmentObject(network)
        .environmentObject(smartLinks)
        .environmentObject(personalProfile)
        .tint(store.document.accent.color)
        .task {
          // Yield the first frame to SplashView before Firebase performs its
          // synchronous bootstrap work. The launch animation should begin as
          // soon as the process owns the window, not after SDK configuration.
          await Task.yield()
          configureFirebaseIfNeeded()
          ProductInsights.flushPending()
          aiArtifacts.configureFirebase()
          cloudSync.configure(
            resumeStore: store,
            applicationStore: applicationStore,
            coverLetterStore: coverLetterStore,
            careerIntelligenceStore: careerIntelligenceStore,
            aiArtifactStore: aiArtifacts
          )
          // Remote identity and StoreKit refresh independently. Local editing
          // and Free-tier access are already ready and never wait on either.
          Task { await account.start() }
          Task { await purchases.start() }
        }
    }
    .commands { ResumeStudioCommands(resumeStore: store) }

    WindowGroup("Résumé Version", id: "resume-version", for: UUID.self) { $resumeID in
      if let resumeID {
        ResumeVersionWindow(resumeID: resumeID)
          .environmentObject(store)
          .environmentObject(coverLetterStore)
          .environmentObject(applicationStore)
          .environmentObject(careerIntelligenceStore)
          .environmentObject(cloudSync)
          .environmentObject(purchases)
          .environmentObject(account)
          .environmentObject(aiArtifacts)
          .environmentObject(referrals)
          .environmentObject(network)
          .tint(store.document.accent.color)
      }
    }
  }

  private func configureFirebaseIfNeeded() {
    // Firebase's lookup APIs log a scary "not configured" message when the
    // absence is exactly what we are checking. Track this process locally so a
    // normal first launch stays clean in Console.
    guard !Self.didConfigureFirebase else { return }
    Self.didConfigureFirebase = true
    #if targetEnvironment(simulator)
      // App Attest cannot attest the simulator. Its debug token must be
      // registered once in Firebase for local simulator development.
      AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
    #else
      // Real iPhones—including Xcode debug installs and TestFlight—use the
      // production App Attest registration, which survives reinstalls without
      // asking the user to manage per-install debug tokens.
      AppCheck.setAppCheckProviderFactory(AppAttestProviderFactory())
    #endif
    FirebaseApp.configure()
    // Warm the attestation asynchronously while the splash animation is
    // playing. The first AI action then has a verified token ready instead of
    // making the user wait for App Attest after tapping the button.
    AppCheck.appCheck().token(forcingRefresh: false) { _, _ in }
  }
}
