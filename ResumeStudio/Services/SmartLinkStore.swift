import Foundation
import UserNotifications

/// The user's trackable links: locally persisted, refreshed against the
/// backend, and the source of "your résumé was just read" moments. New opens
/// discovered by a refresh become a local notification and a Today-queue
/// nudge, so the payoff arrives without the user staring at the list.
@MainActor
final class SmartLinkStore: ObservableObject {
  @Published private(set) var links: [SmartLink] = []
  @Published private(set) var lastRefreshError: String?
  @Published private(set) var isRefreshing = false

  private let fileURL: URL
  private let service = SmartLinkService()

  init(fileURL: URL? = nil) {
    self.fileURL = fileURL ?? Self.defaultURL
    if let data = try? Data(contentsOf: self.fileURL),
      let saved = try? Self.decoder.decode([SmartLink].self, from: data) {
      links = saved
    }
    // The refresh that discovers new opens runs while the app is frontmost,
    // so without a foreground-presentation delegate the alerts would never
    // be seen at all.
    UNUserNotificationCenter.current().delegate = SmartLinkNotificationPresenter.shared
  }

  var activeCount: Int { links.count(where: \.isActive) }

  /// Opens the user has not yet been shown, across every link — drives the
  /// Today queue and the links row badge.
  var unseenOpens: Int { links.reduce(0) { $0 + $1.unseenOpens } }

  /// The most recently read link with unseen activity, for the Today queue's
  /// "follow up while you're on their mind" nudge.
  var mostRecentUnseenLink: SmartLink? {
    links.filter { $0.unseenOpens > 0 }
      .max { ($0.lastSeenAt ?? .distantPast) < ($1.lastSeenAt ?? .distantPast) }
  }

  func add(_ link: SmartLink) {
    links.insert(link, at: 0)
    save()
    Task { await Self.requestNotificationAuthorization() }
  }

  func acknowledge(_ id: UUID) {
    guard let index = links.firstIndex(where: { $0.id == id }) else { return }
    links[index].acknowledgedOpens = links[index].totalOpens
    save()
  }

  func revoke(_ id: UUID) async throws {
    guard let index = links.firstIndex(where: { $0.id == id }) else { return }
    try await service.revoke(token: links[index].token)
    links[index].status = .revoked
    save()
  }

  func delete(_ id: UUID) async {
    guard let index = links.firstIndex(where: { $0.id == id }) else { return }
    // Best-effort remote delete; the local record goes regardless, and an
    // already-deleted remote link is not an error worth surfacing.
    try? await service.delete(token: links[index].token)
    links.removeAll { $0.id == id }
    save()
  }

  /// Pulls fresh activity for every open link and announces genuinely new
  /// opens. Throttled so screens can call it freely.
  func refresh(force: Bool = false) async {
    guard !isRefreshing else { return }
    let due = links.contains { link in
      link.status == .open &&
        (force || (link.lastRefreshedAt ?? .distantPast) < Date(timeIntervalSinceNow: -60))
    }
    guard due else { return }
    isRefreshing = true
    defer { isRefreshing = false }
    lastRefreshError = nil

    for index in links.indices where links[index].status == .open {
      guard force || (links[index].lastRefreshedAt ?? .distantPast) < Date(timeIntervalSinceNow: -60)
      else { continue }
      do {
        let activity = try await service.activity(token: links[index].token)
        let previousOpens = links[index].totalOpens
        links[index].views = activity.views
        links[index].status = SmartLinkStatus(rawValue: activity.status) ?? links[index].status
        links[index].lastRefreshedAt = Date()
        let newOpens = links[index].totalOpens - previousOpens
        if newOpens > 0 {
          await Self.notify(link: links[index], newOpens: newOpens)
        }
      } catch {
        lastRefreshError = error.localizedDescription
      }
    }
    save()
  }

  // MARK: - Notifications

  static func requestNotificationAuthorization() async {
    let center = UNUserNotificationCenter.current()
    _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
  }

  private static func notify(link: SmartLink, newOpens: Int) async {
    let center = UNUserNotificationCenter.current()
    var status = await center.notificationSettings().authorizationStatus
    if status == .notDetermined {
      // First discovery is exactly the moment the permission makes sense.
      _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
      status = await center.notificationSettings().authorizationStatus
    }
    guard status == .authorized else { return }
    let content = UNMutableNotificationContent()
    content.title = link.company.isBlank
      ? "Your résumé was just opened"
      : "\(link.company) opened your résumé"
    let minutes = link.totalSeconds / 60
    let readTime = minutes > 0 ? "\(minutes)m read so far. " : ""
    content.body = "\(link.title) · \(link.totalOpens) open\(link.totalOpens == 1 ? "" : "s"). \(readTime)Follow up while you're on their mind."
    content.sound = .default
    let request = UNNotificationRequest(
      identifier: "smart-link-\(link.id.uuidString)",
      content: content,
      trigger: nil
    )
    try? await center.add(request)
  }

  // MARK: - Persistence

  private func save() {
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Self.encoder.encode(links).write(to: fileURL, options: .atomic)
    } catch {
      lastRefreshError = error.localizedDescription
    }
  }

  private static var defaultURL: URL {
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return root.appendingPathComponent("ResumeStudio", isDirectory: true)
      .appendingPathComponent("smart-links.json")
  }

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()

  private static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()
}

/// Lets notifications banner while the app is open — link alerts fire from
/// foreground refreshes, and the scheduled career reminders lose nothing by
/// being visible in the foreground too.
final class SmartLinkNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
  static let shared = SmartLinkNotificationPresenter()

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound, .badge]
  }
}
