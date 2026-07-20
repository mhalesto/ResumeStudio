import AuthenticationServices
import SwiftUI

enum ResumeStudioLinks {
  static let marketing = URL(string: "https://www.halalisani.com/projects/resumestudio-ios/")!
  static let privacy = URL(string: "https://www.halalisani.com/projects/resumestudio-ios/privacy/")!
  static let dataCollection = URL(string: "https://www.halalisani.com/projects/resumestudio-ios/data-collection/")!
  static let support = URL(string: "https://www.halalisani.com/projects/resumestudio-ios/support/")!
  static let feedback = URL(string: "mailto:currenttech.co.za@gmail.com?subject=ResumeStudio%20feedback")!
}

struct SettingsView: View {
  @Environment(\.openURL) private var openURL
  @EnvironmentObject private var resumeStore: ResumeStore
  @EnvironmentObject private var cloudSync: ICloudSyncService
  @EnvironmentObject private var purchases: PurchaseManager
  @EnvironmentObject private var account: AccountStore
  @EnvironmentObject private var aiArtifacts: AIArtifactStore
  @StateObject private var answerVault = ApplicationAnswerVaultStore()
  @AppStorage("appAppearance") private var appearanceRawValue = AppAppearance.defaultChoice.rawValue
  @State private var isCloudConflictPresented = false

  private var appearance: Binding<AppAppearance> {
    Binding(
      get: { AppAppearance(rawValue: appearanceRawValue) ?? .defaultChoice },
      set: { appearanceRawValue = $0.rawValue }
    )
  }

  /// Settings rows state both of their colours outright rather than inheriting
  /// the list's tint. A reused row keeps whatever tint it was built with, which
  /// is what left icons changing colour a beat after the screen settled — and
  /// left `Link` titles on the system blue while their icons had already moved
  /// to the résumé accent.
  private func settingsLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
    Label {
      Text(title).foregroundStyle(Theme.ink)
    } icon: {
      Image(systemName: systemImage).foregroundStyle(resumeStore.document.accent.color)
    }
  }

  var body: some View {
    List {
      Section("ResumeStudio") {
        NavigationLink {
          AccountSettingsView()
        } label: {
          HStack {
            settingsLabel("Account and backup", systemImage: "person.crop.circle")
            Spacer()
            Text(account.isAnonymous ? "Guest" : "Signed in")
              .font(.caption.bold()).foregroundStyle(Theme.mutedInk)
          }
        }
        NavigationLink {
          AIHistoryView()
        } label: {
          HStack {
            settingsLabel("Saved AI work", systemImage: "sparkles.rectangle.stack")
            Spacer()
            Text("\(aiArtifacts.artifacts.count)")
              .font(.caption.bold()).foregroundStyle(Theme.mutedInk)
          }
        }
        NavigationLink {
          PlansView()
        } label: {
          HStack {
            settingsLabel("Plans and purchases", systemImage: "sparkles")
            Spacer()
            Text(purchases.plan.title)
              .font(.caption.bold())
              .foregroundStyle(Theme.mutedInk)
          }
        }
        LabeledContent("AI credits") {
          Text("\(purchases.displayedCreditBalance) of \(purchases.displayedCreditLimit)")
        }
        let imports = purchases.currentImportAllowance
        LabeledContent("AI imports today") {
          Text("\(imports.importsRemaining) of \(imports.importsLimit)")
        }
        switch purchases.accessSource {
        case .verified:
          Label("Access verified with the App Store", systemImage: "checkmark.shield.fill")
            .font(.caption).foregroundStyle(Theme.mutedInk)
        case .cached(let expiry):
          Label(
            expiry.map { "Offline access available until \($0.formatted(date: .abbreviated, time: .omitted))" }
              ?? "Offline Design Pack access available",
            systemImage: "lock.shield.fill"
          )
          .font(.caption).foregroundStyle(Theme.mutedInk)
        case .free:
          Label("Free tools remain available offline", systemImage: "wifi.slash")
            .font(.caption).foregroundStyle(Theme.mutedInk)
        }
        if purchases.plan == .free {
          Text("Free includes 5 AI-assisted résumé imports each day without spending credits, plus 10 AI credits in your first calendar month and 5 every month after that.")
            .font(.caption).foregroundStyle(Theme.mutedInk)
        }
      }

      Section {
        Picker("Appearance", selection: appearance) {
          ForEach(AppAppearance.allCases) { option in
            Label(option.title, systemImage: option.systemImage)
              .tag(option)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
      } header: {
        Text("Appearance")
      } footer: {
        Text("System follows your iPhone's current appearance.")
      }

      Section("iCloud") {
        Toggle("Sync documents", isOn: $cloudSync.isEnabled)
        Button {
          Task { await cloudSync.synchronize() }
        } label: {
          settingsLabel("Sync now", systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(!cloudSync.isEnabled || cloudSync.status == .syncing)
        cloudStatus
      }

      Section {
        // iOS builds the per-app language picker itself once the app ships more
        // than one localization; this only points at it, because a custom
        // in-app picker would have to override AppleLanguages and would then
        // fight the system setting.
        Button {
          if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
          }
        } label: {
          settingsLabel("Language", systemImage: "globe")
        }
      } header: {
        Text("Language")
      } footer: {
        Text("Opens iOS Settings, where you can set the language Resume Studio uses.")
      }

      Section("Integrations") {
        NavigationLink {
          ApplicationAnswerVaultView(store: answerVault)
        } label: {
          settingsLabel("Application Answer Vault", systemImage: "text.page.badge.magnifyingglass")
        }
        NavigationLink {
          PlatformIntegrationsView()
        } label: {
          settingsLabel("Calendar, Mail, Safari and Shortcuts", systemImage: "puzzlepiece.extension.fill")
        }
      }

      Section("Privacy") {
        NavigationLink {
          PrivacySettingsView()
        } label: {
          settingsLabel("Your data and AI", systemImage: "lock.shield")
        }
      }

      Section("Help and legal") {
        Link(destination: ResumeStudioLinks.marketing) { settingsLabel("ResumeStudio website", systemImage: "safari") }
        Link(destination: ResumeStudioLinks.support) { settingsLabel("Support", systemImage: "questionmark.circle") }
        Link(destination: ResumeStudioLinks.privacy) { settingsLabel("Privacy policy", systemImage: "hand.raised") }
        Link(destination: ResumeStudioLinks.dataCollection) { settingsLabel("Data collection", systemImage: "list.bullet.clipboard") }
        Button {
          ProductInsights.record(.feedbackOpened)
          openURL(ResumeStudioLinks.feedback)
        } label: {
          settingsLabel("Send feedback", systemImage: "envelope")
        }
      }
    }
    // Rows carry their own colours (see `settingsLabel`), so the tint here is
    // only for the controls that have no label of their own — toggles, the
    // segmented picker, the disclosure chevrons.
    .tint(resumeStore.document.accent.color)
    .scrollContentBackground(.hidden)
    .background(Theme.paper)
    .navigationTitle("Settings")
    .toolbarBackground(Theme.paper, for: .navigationBar)
    .sheet(isPresented: $isCloudConflictPresented) {
      CloudConflictResolutionView()
        .environmentObject(cloudSync)
    }
  }

  @ViewBuilder private var cloudStatus: some View {
    switch cloudSync.status {
    case .notConfigured:
      Label("Sync paused", systemImage: "pause.circle")
        .foregroundStyle(Theme.mutedInk)
    case .unavailable:
      Label("Sign into iCloud to sync", systemImage: "icloud.slash")
        .foregroundStyle(Theme.mutedInk)
    case .syncing:
      ProgressView("Syncing…")
    case .conflict:
      Button {
        isCloudConflictPresented = true
      } label: {
        Label("Choose or merge workspace versions", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
      }
      .foregroundStyle(.orange)
    case .synced(let date):
      Label("Synced \(date.formatted(.relative(presentation: .named)))", systemImage: "checkmark.icloud")
        .foregroundStyle(Theme.mutedInk)
    case .failed(let message):
      Label(message, systemImage: "exclamationmark.icloud")
        .foregroundStyle(.red)
    }
  }
}

private struct CloudConflictResolutionView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var cloudSync: ICloudSyncService
  @State private var isResolving = false

  var body: some View {
    NavigationStack {
      List {
        Section {
          Label("Edits were found on this device and in iCloud. Neither version has been overwritten.", systemImage: "checkmark.shield.fill")
            .foregroundStyle(Theme.ink)
        } footer: {
          Text("ResumeStudio saved automatic recovery snapshots before asking you to choose.")
        }

        if let conflict = cloudSync.conflict {
          Section("Versions") {
            LabeledContent("This device", value: conflict.deviceSavedAt.formatted(date: .abbreviated, time: .shortened))
            LabeledContent(conflict.cloudDeviceName, value: conflict.cloudSavedAt.formatted(date: .abbreviated, time: .shortened))
          }
        }

        Section("Recommended") {
          resolutionButton("Merge both versions", detail: "Keeps the newest copy of each résumé, application and career record.", systemImage: "arrow.triangle.merge", resolution: .merge)
        }

        Section("Use one version") {
          resolutionButton("Keep this device", detail: "Replaces the iCloud workspace after saving a snapshot.", systemImage: "iphone", resolution: .keepThisDevice)
          resolutionButton("Use the iCloud version", detail: "Replaces this device after saving a snapshot.", systemImage: "icloud", resolution: .useICloud)
        }
      }
      .navigationTitle("Resolve sync conflict")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() }.disabled(isResolving) } }
    }
    .interactiveDismissDisabled(isResolving)
  }

  private func resolutionButton(
    _ title: String,
    detail: String,
    systemImage: String,
    resolution: ICloudSyncService.ConflictResolution
  ) -> some View {
    Button {
      Task {
        isResolving = true
        await cloudSync.resolveConflict(resolution)
        isResolving = false
        if cloudSync.conflict == nil { dismiss() }
      }
    } label: {
      VStack(alignment: .leading, spacing: 5) {
        Label(title, systemImage: systemImage).font(.headline)
        Text(detail).font(.caption).foregroundStyle(Theme.mutedInk)
      }
    }
    .disabled(isResolving)
  }
}

private struct PrivacySettingsView: View {
  @AppStorage(CareerPrivacySetting.onDeviceAIKey) private var onDeviceAIEnabled = true
  @AppStorage(CareerPrivacySetting.connectedFallbackKey) private var connectedFallbackEnabled = false
  @AppStorage(ProductInsights.enabledKey) private var productInsightsEnabled = false

  var body: some View {
    List {
      Section("On this device") {
        Label("Your drafts are stored locally by default.", systemImage: "iphone")
        Label("You control whether document sync is enabled.", systemImage: "icloud")
        Label("Successful AI results are saved locally and to your private Firebase account.", systemImage: "sparkles.rectangle.stack")
      }

      Section("AI actions") {
        Label("AI runs only after you choose an AI action.", systemImage: "hand.tap")
        Label("Only the résumé text needed for that action is sent.", systemImage: "text.document")
        Toggle("Use on-device intelligence", isOn: $onDeviceAIEnabled)
        Toggle("Allow connected fallback on Free", isOn: $connectedFallbackEnabled)
          .disabled(!onDeviceAIEnabled)
          .accessibilityIdentifier("settings.connectedFallback")
        LabeledContent("Apple Intelligence", value: OnDeviceAIService.availabilityDescription)
          .font(.caption)
        Text("Free uses supported on-device intelligence first for lightweight writing and extraction. If you enable connected fallback, a failed on-device attempt may use the credits shown for that action. Go and Pro use the connected quality model first, with on-device intelligence as a private fallback when it can help.")
          .font(.caption).foregroundStyle(Theme.mutedInk)
      }

      Section("Anonymous product insights") {
        Toggle("Help improve ResumeStudio", isOn: $productInsightsEnabled)
        Text("Shares only aggregate event counters, plan, AI route and app version. It never includes your identity, résumé text, job data, URLs or a persistent device identifier.")
          .font(.caption).foregroundStyle(Theme.mutedInk)
        Link("Read the data-collection summary", destination: ResumeStudioLinks.dataCollection)
      }

      Section("Policies") {
        Link("Privacy policy", destination: ResumeStudioLinks.privacy)
        Link("Support", destination: ResumeStudioLinks.support)
      }
    }
    .scrollContentBackground(.hidden)
    .background(Theme.paper)
    .navigationTitle("Your data and AI")
    .navigationBarTitleDisplayMode(.inline)
    .onChange(of: productInsightsEnabled) { _, enabled in
      if enabled { ProductInsights.flushPending() }
    }
  }
}

private struct AccountSettingsView: View {
  @EnvironmentObject private var account: AccountStore
  @EnvironmentObject private var aiArtifacts: AIArtifactStore
  @EnvironmentObject private var resumeStore: ResumeStore
  @EnvironmentObject private var applicationStore: ApplicationStore
  @EnvironmentObject private var coverLetterStore: CoverLetterStore
  @EnvironmentObject private var careerStore: CareerIntelligenceStore
  @EnvironmentObject private var cloudSync: ICloudSyncService
  @State private var email = ""
  @State private var password = ""
  @State private var isDeletionPresented = false
  @State private var resetConfirmation: String?

  var body: some View {
    Form {
      Section {
        LabeledContent("Status", value: account.accountLabel)
        if case .failed(let message) = account.state {
          Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
      } footer: {
        Text("A protected guest account is created automatically so AI results can be backed up immediately. Sign in to keep the same account across devices and reinstalls.")
      }

      if account.isAnonymous {
        Section("Why create an account?") {
          Label("Keep your saved AI work across devices", systemImage: "icloud.and.arrow.up")
          Label("Claim 10 AI credits from a referral link", systemImage: "gift.fill")
          Label("Invite friends: they get 10 credits and you get 5", systemImage: "person.2.fill")
          Text("Referral rewards are available after Apple sign-in or email verification.")
            .font(.caption).foregroundStyle(Theme.mutedInk)
        }

        Section("Continue with Apple") {
          SignInWithAppleButton(.continue) { request in
            account.prepareAppleRequest(request)
          } onCompletion: { result in
            Task { await account.completeAppleAuthorization(result) }
          }
          .signInWithAppleButtonStyle(.black)
          .frame(height: 48)
        }

        Section("Continue with email") {
          TextField("Email", text: $email)
            .textInputAutocapitalization(.never).keyboardType(.emailAddress)
          SecureField("Password (6+ characters)", text: $password)
          Button("Create account", systemImage: "person.badge.plus") {
            Task { await account.submitEmail(email, password: password, createAccount: true) }
          }
          Button("Sign in to existing account", systemImage: "person.crop.circle.badge.checkmark") {
            Task { await account.submitEmail(email, password: password, createAccount: false) }
          }
          Button("Forgot password?", systemImage: "key.fill") {
            Task {
              await account.sendPasswordReset(to: email)
              if case .ready = account.state {
                resetConfirmation = "Password-reset instructions were sent if that email has a ResumeStudio account."
              }
            }
          }
          .disabled(!email.contains("@"))
        }
      } else {
        Section("Referral rewards") {
          NavigationLink {
            ReferralView()
          } label: {
            Label("Give 10 credits, get 5", systemImage: "gift.fill")
          }
        }
        Section {
          Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
            Task { await account.signOut() }
          }
          if account.canResetPassword, let accountEmail = account.email {
            Button("Send password-reset email", systemImage: "key.fill") {
              Task {
                await account.sendPasswordReset(to: accountEmail)
                if case .ready = account.state { resetConfirmation = "Password-reset instructions sent." }
              }
            }
          }
        }
      }

      Section("Backup") {
        LabeledContent("Saved AI results", value: "\(aiArtifacts.artifacts.count)")
        NavigationLink("Open saved AI work") { AIHistoryView() }
      }

      Section("Data control") {
        Button(
          account.isAnonymous ? "Erase workspace data" : "Delete account and data",
          systemImage: "trash", role: .destructive
        ) { isDeletionPresented = true }
        Text("You choose whether to remove server, on-device, and iCloud data. App Store subscriptions must be cancelled separately in your Apple Account.")
          .font(.caption).foregroundStyle(Theme.mutedInk)
      }
    }
    .scrollContentBackground(.hidden)
    .background(Theme.paper)
    .navigationTitle("Account and backup")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $isDeletionPresented) {
      AccountDeletionView(
        canDeleteAccount: !account.isAnonymous,
        account: account,
        resumeStore: resumeStore,
        applicationStore: applicationStore,
        coverLetterStore: coverLetterStore,
        careerStore: careerStore,
        aiArtifacts: aiArtifacts,
        cloudSync: cloudSync
      )
    }
    .alert("Email sent", isPresented: Binding(
      get: { resetConfirmation != nil },
      set: { if !$0 { resetConfirmation = nil } }
    )) { Button("OK") {} } message: { Text(resetConfirmation ?? "") }
  }
}

private struct AccountDeletionView: View {
  @Environment(\.dismiss) private var dismiss
  let canDeleteAccount: Bool
  let account: AccountStore
  let resumeStore: ResumeStore
  let applicationStore: ApplicationStore
  let coverLetterStore: CoverLetterStore
  let careerStore: CareerIntelligenceStore
  let aiArtifacts: AIArtifactStore
  let cloudSync: ICloudSyncService

  @State private var deleteAccount = true
  @State private var eraseDevice = true
  @State private var eraseICloud = false
  @State private var confirmation = ""
  @State private var isWorking = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      Form {
        Section("Choose what to erase") {
          if canDeleteAccount {
            Toggle("Account and server data", isOn: $deleteAccount)
            Text("Deletes Firebase sign-in, saved AI work, referral and credit records, and Review Rooms owned by this account.")
              .font(.caption).foregroundStyle(Theme.mutedInk)
          }
          Toggle("On-device workspace", isOn: $eraseDevice)
          Toggle("iCloud workspace archive", isOn: $eraseICloud)
        }
        Section("Confirmation") {
          TextField("Type DELETE", text: $confirmation)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
          Label("This cannot be undone. Export anything you need before continuing.", systemImage: "exclamationmark.triangle.fill")
            .font(.caption).foregroundStyle(.orange)
        }
        if let errorMessage {
          Section { Label(errorMessage, systemImage: "xmark.octagon.fill").foregroundStyle(.red) }
        }
      }
      .navigationTitle(canDeleteAccount ? "Delete account" : "Erase workspace")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isWorking) }
        ToolbarItem(placement: .confirmationAction) {
          Button(isWorking ? "Deleting…" : "Delete", role: .destructive) { Task { await performDeletion() } }
            .disabled(!canSubmit || isWorking)
        }
      }
    }
  }

  private var canSubmit: Bool {
    confirmation.uppercased() == "DELETE" && (eraseDevice || eraseICloud || (canDeleteAccount && deleteAccount))
  }

  @MainActor private func performDeletion() async {
    isWorking = true
    errorMessage = nil
    do {
      if canDeleteAccount && deleteAccount { try await account.deleteAccount() }
      if eraseICloud { cloudSync.isEnabled = false }
      if eraseDevice {
        resumeStore.resetLibrary()
        applicationStore.resetWorkspace()
        coverLetterStore.resetDocument()
        careerStore.resetCareerIntelligence()
        aiArtifacts.deleteAll()
      }
      if eraseICloud { try await cloudSync.eraseCloudWorkspace() }
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
    isWorking = false
  }
}

#Preview {
  NavigationStack { SettingsView() }
    .environmentObject(ResumeStore(initialDocument: .example))
    .environmentObject(ICloudSyncService())
    .environmentObject(PurchaseManager.shared)
    .environmentObject(AccountStore())
    .environmentObject(AIArtifactStore())
    .environmentObject(ReferralStore())
}
