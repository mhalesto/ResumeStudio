import SwiftUI

struct ReferralView: View {
  @EnvironmentObject private var account: AccountStore
  @EnvironmentObject private var store: ReferralStore

  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 10) {
          Text("Give 10. Get 5.").font(Theme.display(30))
          Text("A new ResumeStudio member gets 10 AI credits when they create an account with your link. You receive 5 credits after their account is verified.")
            .foregroundStyle(Theme.mutedInk)
        }.padding(.vertical, 8)
      }

      if account.isAnonymous {
        Section("Create your free account") {
          Label("Protect saved AI work across devices", systemImage: "icloud.and.arrow.up")
          Label("Claim 10 credits from a friend's referral", systemImage: "gift.fill")
          Label("Unlock your own referral link", systemImage: "link")
          Text("Return to Account and backup to continue with Apple or email.")
            .font(.caption).foregroundStyle(Theme.mutedInk)
        }
      } else {
        if let email = account.email, !account.isEmailVerified {
          Section("Verify \(email)") {
            Text("Email accounts must be verified before referral rewards can be claimed. Apple accounts are verified automatically.")
              .font(.subheadline).foregroundStyle(Theme.mutedInk)
            Button("Send verification email", systemImage: "envelope.badge") {
              Task { await account.sendVerificationEmail() }
            }
            Button("I've verified my email", systemImage: "arrow.clockwise") {
              Task { await account.refreshAccount(); await store.load() }
            }
          }
        }

        Section("Claim a referral") {
          TextField("Referral code", text: Binding(
            get: { store.pendingCode }, set: { store.setPendingCode($0) }
          ))
          .textInputAutocapitalization(.characters).autocorrectionDisabled()
          Button("Claim 10 AI credits", systemImage: "gift.fill") {
            Task { await store.redeem() }
          }
          .disabled(store.pendingCode.isBlank || store.isLoading || !account.isEmailVerified && account.email != nil)
        }

        if let profile = store.profile {
          Section("Your referral link") {
            Text(profile.code).font(.title2.bold()).monospaced().textSelection(.enabled)
            ShareLink(
              item: profile.shareURL,
              subject: Text("Try ResumeStudio"),
              message: Text("Create your free ResumeStudio account with my link and get 10 AI credits. I’ll get 5 too.")
            ) { Label("Share referral link", systemImage: "square.and.arrow.up") }
            LabeledContent("Successful referrals", value: "\(profile.successfulReferrals) of \(profile.limits.rolling)")
            LabeledContent("Rewards left today", value: "\(profile.remainingToday)")
            LabeledContent("Rewards left this 90 days", value: "\(profile.remainingInWindow)")
            if profile.bonusCredits > 0 {
              LabeledContent("Unused referral credits", value: "\(profile.bonusCredits)")
            }
          }
        }
      }

      if store.isLoading { Section { ProgressView("Updating referrals…") } }
      if let message = store.message {
        Section { Label(message, systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
      }
      if let error = store.errorMessage {
        Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
      }

      Section {
        Text("Rewards are limited to 3 successful referrals per day and 20 in a rolling 90-day period. Each new account can claim one referral, and self-referrals are not allowed.")
          .font(.caption).foregroundStyle(Theme.mutedInk)
      }
    }
    .scrollContentBackground(.hidden)
    .background(Theme.paper)
    .navigationTitle("Referral rewards")
    .navigationBarTitleDisplayMode(.inline)
    .task { await store.load() }
  }
}
