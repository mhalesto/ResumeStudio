import AuthenticationServices
import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var cloudSync: ICloudSyncService
  @EnvironmentObject private var purchases: PurchaseManager
  @EnvironmentObject private var account: AccountStore
  @EnvironmentObject private var aiArtifacts: AIArtifactStore
  @AppStorage("appAppearance") private var appearanceRawValue = AppAppearance.system.rawValue

  private var appearance: Binding<AppAppearance> {
    Binding(
      get: { AppAppearance(rawValue: appearanceRawValue) ?? .system },
      set: { appearanceRawValue = $0.rawValue }
    )
  }

  var body: some View {
    List {
      Section("ResumeStudio") {
        NavigationLink {
          AccountSettingsView()
        } label: {
          HStack {
            Label("Account and backup", systemImage: "person.crop.circle")
            Spacer()
            Text(account.isAnonymous ? "Guest" : "Signed in")
              .font(.caption.bold()).foregroundStyle(Theme.mutedInk)
          }
        }
        NavigationLink {
          AIHistoryView()
        } label: {
          HStack {
            Label("Saved AI work", systemImage: "sparkles.rectangle.stack")
            Spacer()
            Text("\(aiArtifacts.artifacts.count)")
              .font(.caption.bold()).foregroundStyle(Theme.mutedInk)
          }
        }
        NavigationLink {
          PlansView()
        } label: {
          HStack {
            Label("Plans and purchases", systemImage: "sparkles")
            Spacer()
            Text(purchases.plan.title)
              .font(.caption.bold())
              .foregroundStyle(Theme.mutedInk)
          }
        }
        LabeledContent("AI credits") {
          Text("\(purchases.displayedCreditBalance) of \(purchases.displayedCreditLimit)")
        }
        if purchases.plan == .free {
          Text("Free includes 10 AI credits in your first calendar month, then 5 every month.")
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
        Button("Sync now", systemImage: "arrow.triangle.2.circlepath") {
          Task { await cloudSync.synchronize() }
        }
        .disabled(!cloudSync.isEnabled || cloudSync.status == .syncing)
        cloudStatus
      }

      Section("Integrations") {
        NavigationLink {
          PlatformIntegrationsView()
        } label: {
          Label("Calendar, Mail, Safari and Shortcuts", systemImage: "puzzlepiece.extension.fill")
        }
      }

      Section("Privacy") {
        NavigationLink {
          PrivacySettingsView()
        } label: {
          Label("Your data and AI", systemImage: "lock.shield")
        }
      }
    }
    .scrollContentBackground(.hidden)
    .background(Theme.paper)
    .navigationTitle("Settings")
    .toolbarBackground(Theme.paper, for: .navigationBar)
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
    case .synced(let date):
      Label("Synced \(date.formatted(.relative(presentation: .named)))", systemImage: "checkmark.icloud")
        .foregroundStyle(Theme.mutedInk)
    case .failed(let message):
      Label(message, systemImage: "exclamationmark.icloud")
        .foregroundStyle(.red)
    }
  }
}

private struct PrivacySettingsView: View {
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
      }
    }
    .scrollContentBackground(.hidden)
    .background(Theme.paper)
    .navigationTitle("Your data and AI")
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct AccountSettingsView: View {
  @EnvironmentObject private var account: AccountStore
  @EnvironmentObject private var aiArtifacts: AIArtifactStore
  @State private var email = ""
  @State private var password = ""

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
        }
      }

      Section("Backup") {
        LabeledContent("Saved AI results", value: "\(aiArtifacts.artifacts.count)")
        NavigationLink("Open saved AI work") { AIHistoryView() }
      }
    }
    .scrollContentBackground(.hidden)
    .background(Theme.paper)
    .navigationTitle("Account and backup")
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview {
  NavigationStack { SettingsView() }
    .environmentObject(ICloudSyncService())
    .environmentObject(PurchaseManager.shared)
    .environmentObject(AccountStore())
    .environmentObject(AIArtifactStore())
    .environmentObject(ReferralStore())
}
