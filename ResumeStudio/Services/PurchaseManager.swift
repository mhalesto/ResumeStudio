import Foundation
import StoreKit

@MainActor
final class PurchaseManager: ObservableObject {
  static let shared = PurchaseManager()

  @Published private(set) var products: [Product] = []
  @Published private(set) var plan: ResumeStudioPlan = .free
  @Published private(set) var hasDesignPack = false
  @Published private(set) var usage: AIUsageSnapshot?
  @Published private(set) var isLoading = false
  @Published private(set) var purchaseError: String?

  private var signedTransactions: [String: String] = [:]
  private var signedAppTransaction: String?
  private var updatesTask: Task<Void, Never>?
  private var hasStarted = false

  private init() {
    if let data = UserDefaults.standard.data(forKey: "latestAIUsage"),
      let saved = try? JSONDecoder.purchaseDecoder.decode(AIUsageSnapshot.self, from: data)
    {
      usage = saved
    }
  }

  deinit { updatesTask?.cancel() }

  var unlocksAllTemplates: Bool { plan != .free || hasDesignPack }
  var resumeVersionLimit: Int? { plan == .free && !hasDesignPack ? 3 : nil }
  var hostedReviewRoomLimit: Int { plan.hostedReviewRoomLimit }
  var currentUsage: AIUsageSnapshot? {
    guard let usage else { return nil }
    guard usage.resetAt.map({ $0 > Date() }) ?? true else { return nil }
    return usage
  }
  var displayedCreditBalance: Int { currentUsage?.creditsRemaining ?? defaultCreditAllowance }
  var displayedCreditLimit: Int { currentUsage?.creditsLimit ?? defaultCreditAllowance }

  private var defaultCreditAllowance: Int {
    if plan != .free { return plan.monthlyAICredits }
    return UserDefaults.standard.bool(forKey: "hasReceivedAIUsage") ? plan.monthlyAICredits : 10
  }

  func start() async {
    guard !hasStarted else { return }
    hasStarted = true
    updatesTask = Task { [weak self] in
      for await verification in Transaction.updates {
        guard let self else { return }
        if case .verified(let transaction) = verification {
          await transaction.finish()
        }
        await self.refreshEntitlements()
      }
    }
    await loadProducts()
    await refreshEntitlements()
  }

  func loadProducts() async {
    isLoading = true
    defer { isLoading = false }
    do {
      products = try await Product.products(for: ResumeStudioProduct.allIDs)
        .sorted { productOrder($0.id) < productOrder($1.id) }
      purchaseError = nil
    } catch {
      purchaseError = "Plans are temporarily unavailable. \(error.localizedDescription)"
    }
  }

  func purchase(productID: String) async {
    guard let product = products.first(where: { $0.id == productID }) else {
      purchaseError = "This plan is not available from the App Store yet."
      return
    }
    isLoading = true
    purchaseError = nil
    defer { isLoading = false }
    do {
      switch try await product.purchase() {
      case .success(let verification):
        guard case .verified(let transaction) = verification else {
          purchaseError = "The App Store could not verify this purchase."
          return
        }
        await transaction.finish()
        await refreshEntitlements()
      case .pending:
        purchaseError = "The purchase is waiting for approval."
      case .userCancelled:
        break
      @unknown default:
        purchaseError = "The App Store returned an unknown purchase status."
      }
    } catch {
      purchaseError = error.localizedDescription
    }
  }

  func restorePurchases() async {
    isLoading = true
    purchaseError = nil
    defer { isLoading = false }
    do {
      try await AppStore.sync()
      await refreshEntitlements()
    } catch {
      purchaseError = error.localizedDescription
    }
  }

  func refreshEntitlements() async {
    var resolvedPlan = ResumeStudioPlan.free
    var resolvedDesignPack = false
    var resolvedTransactions: [String: String] = [:]

    for await verification in Transaction.currentEntitlements {
      guard case .verified(let transaction) = verification,
        transaction.revocationDate == nil,
        transaction.expirationDate.map({ $0 > Date() }) ?? true
      else { continue }

      resolvedTransactions[transaction.productID] = verification.jwsRepresentation
      switch transaction.productID {
      case ResumeStudioProduct.proMonthly:
        resolvedPlan = .pro
      case ResumeStudioProduct.goMonthly where resolvedPlan != .pro:
        resolvedPlan = .go
      case ResumeStudioProduct.designForever:
        resolvedDesignPack = true
      default:
        break
      }
    }

    if let appVerification = try? await AppTransaction.shared,
      case .verified = appVerification
    {
      signedAppTransaction = appVerification.jwsRepresentation
    }

    plan = resolvedPlan
    hasDesignPack = resolvedDesignPack
    signedTransactions = resolvedTransactions
    if usage?.tier != resolvedPlan { usage = nil }
  }

  func entitlementProof() -> MonetizationEntitlementProof {
    let transaction: String?
    switch plan {
    case .pro: transaction = signedTransactions[ResumeStudioProduct.proMonthly]
    case .go: transaction = signedTransactions[ResumeStudioProduct.goMonthly]
    case .free: transaction = nil
    }
    return MonetizationEntitlementProof(
      signedTransaction: transaction,
      signedAppTransaction: signedAppTransaction
    )
  }

  func updateUsage(_ snapshot: AIUsageSnapshot) {
    usage = snapshot
    UserDefaults.standard.set(true, forKey: "hasReceivedAIUsage")
    if let data = try? JSONEncoder.purchaseEncoder.encode(snapshot) {
      UserDefaults.standard.set(data, forKey: "latestAIUsage")
    }
  }

  func addReferralCredits(_ amount: Int) {
    guard amount > 0 else { return }
    var snapshot = currentUsage ?? AIUsageSnapshot(
      tier: plan,
      creditsUsed: 0,
      creditsLimit: defaultCreditAllowance,
      creditsRemaining: defaultCreditAllowance,
      resetAt: nil
    )
    snapshot.creditsLimit += amount
    snapshot.creditsRemaining += amount
    snapshot.bonusCreditsRemaining = (snapshot.bonusCreditsRemaining ?? 0) + amount
    updateUsage(snapshot)
  }

  func canUse(_ template: ResumeTemplate) -> Bool {
    unlocksAllTemplates || MonetizationCatalog.freeResumeTemplates.contains(template)
  }

  func canUse(_ template: CoverLetterTemplate) -> Bool {
    unlocksAllTemplates || MonetizationCatalog.freeCoverLetterTemplates.contains(template)
  }

  func canUse(_ accent: ResumeAccent) -> Bool {
    unlocksAllTemplates || MonetizationCatalog.freeAccents.contains(accent)
  }

  func canCreateResume(currentCount: Int) -> Bool {
    resumeVersionLimit.map { currentCount < $0 } ?? true
  }

  func requestPlans() {
    NotificationCenter.default.post(name: .presentPlans, object: nil)
  }

  func localizedPrice(for productID: String, fallback: String) -> String {
    products.first(where: { $0.id == productID })?.displayPrice ?? fallback
  }

  private func productOrder(_ id: String) -> Int {
    switch id {
    case ResumeStudioProduct.goMonthly: 0
    case ResumeStudioProduct.proMonthly: 1
    case ResumeStudioProduct.designForever: 2
    default: 3
    }
  }
}

private extension JSONEncoder {
  static let purchaseEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()
}

private extension JSONDecoder {
  static let purchaseDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()
}

enum MonetizationIdentity {
  static var installationID: String {
    let key = "aiInstallationID"
    if let stored = UserDefaults.standard.string(forKey: key) { return stored }
    let value = UUID().uuidString
    UserDefaults.standard.set(value, forKey: key)
    return value
  }
}
