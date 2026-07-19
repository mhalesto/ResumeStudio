import Combine
import Foundation
import Security
import StoreKit

@MainActor
final class PurchaseManager: ObservableObject {
  enum AccessSource: Equatable {
    case verified
    case cached(until: Date?)
    case free
  }

  static let shared = PurchaseManager()

  @Published private(set) var products: [Product] = []
  @Published private(set) var plan: ResumeStudioPlan = .free
  @Published private(set) var hasDesignPack = false
  @Published private(set) var usage: AIUsageSnapshot?
  @Published private(set) var importAllowance: DailyImportAllowance?
  @Published private(set) var isLoading = false
  @Published private(set) var purchaseError: String?
  @Published private(set) var accessSource: AccessSource = .free

  private var signedTransactions: [String: String] = [:]
  private var signedAppTransaction: String?
  private var updatesTask: Task<Void, Never>?
  private var hasStarted = false
  private var cachedEntitlements: OfflineEntitlements?
  private var networkCancellable: AnyCancellable?
  private var isRefreshingEntitlements = false
  private var entitlementRefreshRequested = false

  private init() {
    cachedEntitlements = OfflineEntitlementCache.load()
    applyCachedAccess()
    networkCancellable = NetworkMonitor.shared.$isOnline
      .removeDuplicates()
      .filter { $0 }
      .sink { [weak self] _ in
        Task { @MainActor [weak self] in
          guard let self, self.hasStarted else { return }
          self.beginTransactionListener()
          await self.refreshEntitlements()
          await self.loadProducts()
        }
      }
    if let data = UserDefaults.standard.data(forKey: "latestAIUsage"),
      let saved = try? JSONDecoder.purchaseDecoder.decode(AIUsageSnapshot.self, from: data)
    {
      usage = saved
    }
    if let data = UserDefaults.standard.data(forKey: "latestDailyImportAllowance"),
      let saved = try? JSONDecoder.purchaseDecoder.decode(DailyImportAllowance.self, from: data),
      saved.resetAt > Date()
    {
      importAllowance = saved
    }
  }

  deinit {
    updatesTask?.cancel()
    networkCancellable?.cancel()
  }

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
  var currentImportAllowance: DailyImportAllowance {
    if let importAllowance,
      importAllowance.resetAt > Date(),
      importAllowance.tier == plan,
      importAllowance.importsLimit == plan.dailyAIImportLimit
    {
      return importAllowance
    }
    return DailyImportAllowance(
      tier: plan,
      importsUsed: 0,
      importsLimit: plan.dailyAIImportLimit,
      importsRemaining: plan.dailyAIImportLimit,
      resetAt: Self.startOfNextUTCDay()
    )
  }

  private static func startOfNextUTCDay(from date: Date = Date()) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    let start = calendar.startOfDay(for: date)
    return calendar.date(byAdding: .day, value: 1, to: start) ?? date.addingTimeInterval(86_400)
  }

  private var defaultCreditAllowance: Int {
    if plan != .free { return plan.monthlyAICredits }
    return UserDefaults.standard.bool(forKey: "hasReceivedAIUsage") ? plan.monthlyAICredits : 10
  }

  func start() async {
    guard !hasStarted else { return }
    hasStarted = true
    // StoreKit's local receipt and Xcode StoreKit configuration work without a
    // network route. Never gate paid access behind NWPathMonitor.
    beginTransactionListener()
    await refreshEntitlements()
    await loadProducts()
  }

  private func beginTransactionListener() {
    guard updatesTask == nil else { return }
    updatesTask = Task { [weak self] in
      for await verification in Transaction.updates {
        guard let self else { return }
        if case .verified(let transaction) = verification {
          await transaction.finish()
        }
        await self.refreshEntitlements()
      }
    }
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
    // A returning subscriber can reach this screen before the launch refresh
    // completes. Resolve ownership first so we do not ask StoreKit to sell an
    // already-active subscription again.
    await refreshEntitlements()
    if alreadyOwns(productID) {
      purchaseError = nil
      return
    }
    if products.isEmpty { await loadProducts() }
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
    // StoreKit updates, foregrounding, network recovery and a purchase can all
    // request a refresh together. Coalesce them so an older empty result cannot
    // race a newer verified result and put the UI back on Free.
    if isRefreshingEntitlements {
      entitlementRefreshRequested = true
      return
    }

    isRefreshingEntitlements = true
    repeat {
      entitlementRefreshRequested = false
      await performEntitlementRefresh()
    } while entitlementRefreshRequested
    isRefreshingEntitlements = false
  }

  private func performEntitlementRefresh() async {
    var resolvedPlan = ResumeStudioPlan.free
    var resolvedDesignPack = false
    var resolvedTransactions: [String: String] = [:]
    var subscriptionExpiry: Date?
    var authoritativeProductIDs: Set<String> = []

    func accept(_ verification: VerificationResult<Transaction>) {
      guard case .verified(let transaction) = verification else { return }
      authoritativeProductIDs.insert(transaction.productID)
      guard transaction.revocationDate == nil,
        transaction.expirationDate.map({ $0 > Date() }) ?? true
      else { return }

      resolvedTransactions[transaction.productID] = verification.jwsRepresentation
      switch transaction.productID {
      case ResumeStudioProduct.proMonthly:
        resolvedPlan = .pro
        subscriptionExpiry = maxDate(subscriptionExpiry, transaction.expirationDate)
      case ResumeStudioProduct.goMonthly where resolvedPlan != .pro:
        resolvedPlan = .go
        subscriptionExpiry = maxDate(subscriptionExpiry, transaction.expirationDate)
      case ResumeStudioProduct.designForever:
        resolvedDesignPack = true
      default:
        break
      }
    }

    for await verification in Transaction.currentEntitlements {
      accept(verification)
    }

    // `currentEntitlements` can briefly be empty after launch or when a local
    // StoreKit subscription is already active. The latest verified transaction
    // is an independent source of truth and includes its real expiry/revocation.
    for productID in ResumeStudioProduct.allIDs where resolvedTransactions[productID] == nil {
      if let latest = await Transaction.latest(for: productID) {
        accept(latest)
      }
    }

    if let appVerification = try? await AppTransaction.shared,
      case .verified = appVerification
    {
      signedAppTransaction = appVerification.jwsRepresentation
    }

    var usedCachedAccess = false
    if let cache = cachedEntitlements {
      let cachedDecision = OfflineAccessPolicy.resolve(cache, now: Date())
      if EntitlementContinuityPolicy.shouldRetainCachedSubscription(
        cachedDecision,
        resolvedPlan: resolvedPlan,
        authoritativeProductIDs: authoritativeProductIDs
      ) {
        // No transaction is inconclusive (common during StoreKit startup), so
        // retain access until its verified expiry. A verified expired or revoked
        // latest transaction is authoritative and is not retained.
        resolvedPlan = cachedDecision.plan
        subscriptionExpiry = cachedDecision.subscriptionExpiry
        usedCachedAccess = true
      }
      if EntitlementContinuityPolicy.shouldRetainCachedDesignPack(
        cachedDecision,
        resolvedDesignPack: resolvedDesignPack,
        authoritativeProductIDs: authoritativeProductIDs
      ) {
        resolvedDesignPack = true
        usedCachedAccess = true
      }
    }

    if resolvedPlan != .free || resolvedDesignPack {
      // A cached subscription is valid offline until its verified expiry, but
      // hosted services still need the signed StoreKit proof. Keep the last
      // verified JWS alongside the access decision instead of replacing it
      // with an empty refresh during a network/StoreKit startup gap.
      let proofTransactions = resolvedTransactions.isEmpty
        ? (cachedEntitlements?.signedTransactions ?? signedTransactions)
        : resolvedTransactions
      let proofAppTransaction = signedAppTransaction
        ?? cachedEntitlements?.signedAppTransaction
      let cache = OfflineEntitlements(
        plan: resolvedPlan,
        subscriptionExpiry: subscriptionExpiry,
        hasDesignPack: resolvedDesignPack,
        verifiedAt: Date(),
        signedTransactions: proofTransactions,
        signedAppTransaction: proofAppTransaction
      )
      cachedEntitlements = cache
      OfflineEntitlementCache.save(cache)
      apply(
        plan: resolvedPlan,
        designPack: resolvedDesignPack,
        source: usedCachedAccess ? .cached(until: subscriptionExpiry) : .verified
      )
      signedTransactions = proofTransactions
      signedAppTransaction = proofAppTransaction
    } else {
      cachedEntitlements = nil
      OfflineEntitlementCache.clear()
      signedTransactions = [:]
      apply(plan: .free, designPack: false, source: .free)
    }
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

  func updateImportAllowance(_ snapshot: DailyImportAllowance) {
    importAllowance = snapshot
    if let data = try? JSONEncoder.purchaseEncoder.encode(snapshot) {
      UserDefaults.standard.set(data, forKey: "latestDailyImportAllowance")
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

  private func alreadyOwns(_ productID: String) -> Bool {
    switch productID {
    case ResumeStudioProduct.proMonthly:
      plan == .pro
    case ResumeStudioProduct.goMonthly:
      plan == .go || plan == .pro
    case ResumeStudioProduct.designForever:
      hasDesignPack
    default:
      false
    }
  }

  private func applyCachedAccess() {
    let decision = OfflineAccessPolicy.resolve(cachedEntitlements, now: Date())
    signedTransactions = cachedEntitlements?.signedTransactions ?? [:]
    signedAppTransaction = cachedEntitlements?.signedAppTransaction
    let hasAccess = decision.plan != .free || decision.hasDesignPack
    apply(
      plan: decision.plan,
      designPack: decision.hasDesignPack,
      source: hasAccess ? .cached(until: decision.subscriptionExpiry) : .free
    )
  }

  private func apply(plan newPlan: ResumeStudioPlan, designPack: Bool, source: AccessSource) {
    plan = newPlan
    hasDesignPack = designPack
    accessSource = source
    if usage?.tier != newPlan { usage = nil }
    if importAllowance?.tier != newPlan { importAllowance = nil }
  }

  private func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
    switch (lhs, rhs) {
    case let (left?, right?): max(left, right)
    case let (left?, nil): left
    case let (nil, right?): right
    case (nil, nil): nil
    }
  }

}

struct OfflineEntitlements: Codable {
  let plan: ResumeStudioPlan
  let subscriptionExpiry: Date?
  let hasDesignPack: Bool
  let verifiedAt: Date
  /// Server-verifiable StoreKit proofs are cached with the access decision so
  /// paid hosted features do not silently fall back to Free while offline.
  let signedTransactions: [String: String]?
  let signedAppTransaction: String?

  init(
    plan: ResumeStudioPlan,
    subscriptionExpiry: Date?,
    hasDesignPack: Bool,
    verifiedAt: Date,
    signedTransactions: [String: String]? = nil,
    signedAppTransaction: String? = nil
  ) {
    self.plan = plan
    self.subscriptionExpiry = subscriptionExpiry
    self.hasDesignPack = hasDesignPack
    self.verifiedAt = verifiedAt
    self.signedTransactions = signedTransactions
    self.signedAppTransaction = signedAppTransaction
  }

  var hasUsableAccess: Bool {
    hasDesignPack || (plan != .free && subscriptionExpiry.map { $0 > Date() } == true)
  }
}

struct OfflineAccessDecision: Equatable {
  let plan: ResumeStudioPlan
  let hasDesignPack: Bool
  let subscriptionExpiry: Date?
}

enum OfflineAccessPolicy {
  static func resolve(_ cache: OfflineEntitlements?, now: Date) -> OfflineAccessDecision {
    guard let cache else {
      return OfflineAccessDecision(plan: .free, hasDesignPack: false, subscriptionExpiry: nil)
    }
    let subscriptionIsActive = cache.plan != .free && cache.subscriptionExpiry.map { $0 > now } == true
    return OfflineAccessDecision(
      plan: subscriptionIsActive ? cache.plan : .free,
      hasDesignPack: cache.hasDesignPack,
      subscriptionExpiry: subscriptionIsActive ? cache.subscriptionExpiry : nil
    )
  }
}

enum EntitlementContinuityPolicy {
  static func shouldRetainCachedSubscription(
    _ cache: OfflineAccessDecision,
    resolvedPlan: ResumeStudioPlan,
    authoritativeProductIDs: Set<String>
  ) -> Bool {
    guard resolvedPlan == .free, cache.plan != .free else { return false }
    let productID = cache.plan == .pro
      ? ResumeStudioProduct.proMonthly : ResumeStudioProduct.goMonthly
    return !authoritativeProductIDs.contains(productID)
  }

  static func shouldRetainCachedDesignPack(
    _ cache: OfflineAccessDecision,
    resolvedDesignPack: Bool,
    authoritativeProductIDs: Set<String>
  ) -> Bool {
    cache.hasDesignPack && !resolvedDesignPack
      && !authoritativeProductIDs.contains(ResumeStudioProduct.designForever)
  }
}

private enum OfflineEntitlementCache {
  private static let service = "com.halalisanimbanjwa.ResumeStudio.entitlements"
  private static let account = "verified-access-v1"

  static func load() -> OfflineEntitlements? {
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(OfflineEntitlements.self, from: data)
  }

  static func save(_ value: OfflineEntitlements) {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(value) else { return }
    let attributes = [kSecValueData as String: data]
    if SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
      var query = baseQuery
      query[kSecValueData as String] = data
      query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      SecItemAdd(query as CFDictionary, nil)
    }
  }

  static func clear() {
    SecItemDelete(baseQuery as CFDictionary)
  }

  private static var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
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
