import SwiftUI

struct PlansView: View {
  @EnvironmentObject private var purchases: PurchaseManager
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        hero
        currentAllowance
        freePlanBenefits
        planCard(
          plan: .go,
          productID: ResumeStudioProduct.goMonthly,
          fallbackPrice: "R49.99",
          subtitle: "For occasional applications and focused improvements.",
          features: [
            "20 AI-assisted résumé imports every day",
            "35 AI credits every month",
            "All \(ResumeTemplate.allCases.count) résumé and \(CoverLetterTemplate.allCases.count) cover-letter templates",
            "Unlimited document versions",
            "One active hosted Review Room",
          ],
          color: .blue
        )
        planCard(
          plan: .pro,
          productID: ResumeStudioProduct.proMonthly,
          fallbackPrice: "R129.99",
          subtitle: "For an active job search across several opportunities.",
          features: [
            "30 AI-assisted résumé imports every day",
            "150 AI credits every month",
            "Everything included in Go",
            "Up to ten active Review Rooms",
            "Higher-volume tailoring, interview and voice practice",
          ],
          color: .purple
        )
        designPack
        freePromise

        if let error = purchases.purchaseError {
          Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.red)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        }

        Button("Restore purchases", systemImage: "arrow.clockwise") {
          Task { await purchases.restorePurchases() }
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)

        Text("Subscriptions renew monthly until cancelled in App Store settings. Monthly AI credits reset each billing period; résumé-import allowances reset daily at 00:00 UTC. The Design Pack is a one-time purchase.")
          .font(.caption2)
          .foregroundStyle(Theme.mutedInk)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
      }
      .padding(20)
      .padding(.bottom, 32)
      .frame(maxWidth: 720)
      .frame(maxWidth: .infinity)
    }
    .background(Theme.paper)
    .navigationTitle("Plans")
    .onAppear { ProductInsights.record(.plansPresented) }
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
    }
    .task {
      // Opening Plans is also an explicit entitlement repair point. This makes
      // an existing App Store subscription visible without another purchase.
      await purchases.refreshEntitlements()
    }
    .overlay {
      if purchases.isLoading {
        ZStack {
          Color.black.opacity(0.08).ignoresSafeArea()
          ProgressView().padding(22).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
      }
    }
  }

  private var hero: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("A PLAN FOR EVERY JOB SEARCH").eyebrow().foregroundStyle(.orange)
      Text("Pay for momentum,\nnot basic access.")
        .font(Theme.display(36))
        .foregroundStyle(Theme.heroInk)
      Text("Creating and exporting a professional résumé stays free. Upgrade for more AI, every design and hosted feedback.")
        .font(.subheadline)
        .foregroundStyle(Theme.heroMutedInk)
    }
    .padding(24)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      LinearGradient(colors: [Theme.heroTop, Theme.heroBottom], startPoint: .topLeading, endPoint: .bottomTrailing),
      in: RoundedRectangle(cornerRadius: 28, style: .continuous)
    )
  }

  private var currentAllowance: some View {
    HStack(spacing: 14) {
      Image(systemName: "sparkles")
        .font(.title2.bold())
        .foregroundStyle(.orange)
        .frame(width: 48, height: 48)
        .background(Color.orange.opacity(0.13), in: RoundedRectangle(cornerRadius: 15))
      VStack(alignment: .leading, spacing: 3) {
        Text("\(purchases.plan.title) plan").font(.headline)
        Text("\(purchases.displayedCreditBalance) of \(purchases.displayedCreditLimit) AI credits available")
          .font(.caption).foregroundStyle(Theme.mutedInk)
        let imports = purchases.currentImportAllowance
        Text("\(imports.importsRemaining) of \(imports.importsLimit) AI-assisted imports available today")
          .font(.caption).foregroundStyle(Theme.mutedInk)
        if let bonus = purchases.currentUsage?.bonusCreditsRemaining, bonus > 0 {
          Text("Includes \(bonus) referral bonus credits")
            .font(.caption.bold()).foregroundStyle(.green)
        }
      }
      Spacer()
      if purchases.hasDesignPack {
        Label("Design owned", systemImage: "checkmark.seal.fill")
          .font(.caption.bold()).foregroundStyle(.green)
      }
    }
    .padding(17)
    .cardSurface()
  }

  private var freePlanBenefits: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Included with Free", systemImage: "gift.fill")
        .font(.title3.bold()).foregroundStyle(.green)
      Label("10 AI credits in your first calendar month", systemImage: "sparkles")
      Label("Then 5 free AI credits every month", systemImage: "calendar")
      Label("5 separate AI-assisted résumé imports every day", systemImage: "doc.badge.arrow.up")
      Label("Unlimited on-device import previews", systemImage: "iphone")
      Label("No payment or subscription required", systemImage: "creditcard.trianglebadge.exclamationmark")
      Label("Referral rewards: give 10 credits and get 5", systemImage: "person.2.fill")
      NavigationLink {
        ReferralView()
      } label: {
        Text("View referral rewards")
      }
      Divider()
      Text("Résumé imports use the separate daily allowance. Small writing improvements cost 1 credit, career drafts and analysis cost 3, and full tailoring or interview actions cost 5.")
        .font(.caption).foregroundStyle(Theme.mutedInk)
    }
    .font(.subheadline)
    .padding(19)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
    .overlay {
      RoundedRectangle(cornerRadius: 24).strokeBorder(Color.green.opacity(0.22))
    }
  }

  private func planCard(
    plan: ResumeStudioPlan,
    productID: String,
    fallbackPrice: String,
    subtitle: String,
    features: [String],
    color: Color
  ) -> some View {
    VStack(alignment: .leading, spacing: 15) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 4) {
          Text(plan.title).font(.title2.bold()).foregroundStyle(Theme.ink)
          Text(subtitle).font(.caption).foregroundStyle(Theme.mutedInk)
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 1) {
          Text(purchases.localizedPrice(for: productID, fallback: fallbackPrice)).font(.title3.bold())
          Text("per month").font(.caption2).foregroundStyle(Theme.mutedInk)
        }
      }
      ForEach(features, id: \.self) { feature in
        Label(feature, systemImage: "checkmark.circle.fill")
          .font(.subheadline)
          .foregroundStyle(Theme.inkSoft)
          .labelStyle(PlanFeatureLabelStyle(color: color))
      }
      Button(buttonTitle(for: plan)) {
        Task { await purchases.purchase(productID: productID) }
      }
      .font(.headline)
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 13)
      .background(color, in: Capsule())
      .disabled(purchases.plan == plan || (purchases.plan == .pro && plan == .go))
      .opacity(purchases.plan == plan || (purchases.plan == .pro && plan == .go) ? 0.58 : 1)
    }
    .padding(19)
    .cardSurface(radius: 24)
  }

  private var designPack: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Design Pack Forever").font(.title3.bold())
          Text("Own the creative tools without subscribing.").font(.caption).foregroundStyle(Theme.mutedInk)
        }
        Spacer()
        VStack(alignment: .trailing) {
          Text(purchases.localizedPrice(for: ResumeStudioProduct.designForever, fallback: "R299.99"))
            .font(.title3.bold())
          Text("once-off").font(.caption2).foregroundStyle(Theme.mutedInk)
        }
      }
      Label("All current and future résumé and cover-letter templates", systemImage: "paintpalette.fill")
      Label("Unlimited local document versions", systemImage: "doc.on.doc.fill")
      Label("Free AI allowance remains available", systemImage: "sparkles")
      Button(purchases.hasDesignPack ? "Design Pack owned" : "Buy Design Pack") {
        Task { await purchases.purchase(productID: ResumeStudioProduct.designForever) }
      }
      .buttonStyle(.borderedProminent)
      .tint(.orange)
      .frame(maxWidth: .infinity)
      .disabled(purchases.hasDesignPack)
    }
    .font(.subheadline)
    .padding(19)
    .cardSurface(radius: 24)
  }

  private var freePromise: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Always free", systemImage: "heart.fill").font(.headline).foregroundStyle(.green)
      Text("Manual editing, ATS checks, application tracking, iCloud sync, privacy controls and unwatermarked PDF, DOCX and text exports remain free. AI-assisted import uses the included credits.")
        .font(.subheadline).foregroundStyle(Theme.mutedInk)
    }
    .padding(17)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
  }

  private func buttonTitle(for plan: ResumeStudioPlan) -> LocalizedStringResource {
    if purchases.plan == plan { return "Current plan" }
    if purchases.plan == .pro && plan == .go { return "Included with Pro" }
    // `plan.title` is resolved before interpolation. Interpolating a
    // LocalizedStringResource directly compiles, but prints its debug
    // description instead of the text.
    return purchases.plan == .go && plan == .pro
      ? "Upgrade to Pro"
      : "Choose \(String(localized: plan.title))"
  }
}

/// The premium mark on a locked template: a gold crown on a dark coin, so it
/// reads on white pages and colour sidebars alike.
struct PlanLockBadge: View {
  var body: some View {
    Image(systemName: "crown.fill")
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(
        LinearGradient(
          colors: [
            Color(red: 1.0, green: 0.87, blue: 0.45),
            Color(red: 0.85, green: 0.62, blue: 0.13),
          ],
          startPoint: .top,
          endPoint: .bottom
        )
      )
      .padding(7)
      .background(Color.black.opacity(0.72), in: Circle())
      .overlay {
        Circle().strokeBorder(
          Color(red: 0.93, green: 0.75, blue: 0.3).opacity(0.85), lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
      .accessibilityLabel("Available with Go, Pro, or the Design Pack")
  }
}

private struct PlanFeatureLabelStyle: LabelStyle {
  let color: Color
  func makeBody(configuration: Configuration) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 9) {
      configuration.icon.foregroundStyle(color)
      configuration.title
    }
  }
}

#Preview {
  NavigationStack { PlansView() }
    .environmentObject(PurchaseManager.shared)
}
