import Foundation

/// Jobs shared from Safari, waiting to be turned into applications.
///
/// A queue rather than a single slot, because sharing is how someone works
/// through a board: three roles go across in a minute, long before the app is
/// opened to deal with any of them. Holding one meant the first two vanished
/// without ever being seen.
///
/// Kept in a file in the shared container rather than in `UserDefaults`, and
/// every touch of it goes through `NSFileCoordinator`. Two processes write this
/// queue — the app as it drains, the share extension as it fills — and read,
/// change, write back is not atomic. With defaults there was a window, however
/// narrow, where a share landing at the wrong moment overwrote one being taken,
/// or was itself lost. Coordination closes it.
enum SharedJobInbox {
  static let appGroupID = "group.com.halalisanimbanjwa.ResumeStudio"
  /// Where builds before the queue kept a single capture, and where the queue
  /// itself first lived. Both are drained on the way past so nothing shared
  /// before an update is stranded.
  static let legacyKey = "pendingJobCapture"
  static let legacyQueueKey = "pendingJobCaptures"
  /// Enough for a long browse; past this the oldest go, because a capture
  /// nobody has dealt with in twenty shares is not the one being waited on.
  static let limit = 20

  static var fileURL: URL? {
    FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
      .appendingPathComponent("pending-job-captures.json")
  }

  /// Everything waiting, oldest first.
  static func pending() -> [SharedJobCapture] {
    migrateLegacyStorageIfNeeded()
    guard let url = fileURL else { return [] }
    var captures: [SharedJobCapture] = []
    coordinateReading(url) { captures = decode(at: $0) }
    return captures
  }

  static var pendingCount: Int { pending().count }

  /// The same count, off the main thread. Reading the queue means coordinated
  /// file access, which is not something to do while a view is laying out — done
  /// synchronously on every navigation change it both stuttered and set state
  /// mid-update, which SwiftUI complains about as updating twice in a frame.
  static func pendingCountOffMainThread() async -> Int {
    await Task.detached(priority: .utility) { pendingCount }.value
  }

  /// Taking one is a coordinated write, so it does not belong on the main thread
  /// either — the capture screen was doing it as it appeared.
  static func consumeOffMainThread() async -> SharedJobCapture? {
    await Task.detached(priority: .userInitiated) { consume() }.value
  }

  /// Takes the oldest waiting capture, in the order they were shared.
  static func consume() -> SharedJobCapture? {
    // Flattened: `mutate` returns nothing when there is no container to reach,
    // and the change itself returns nothing when the queue is empty.
    mutate { queue -> SharedJobCapture? in
      queue.isEmpty ? nil : queue.removeFirst()
    } ?? nil
  }

  /// Adds one to the back of the queue.
  static func enqueue(_ capture: SharedJobCapture) {
    mutate { queue in queue.append(capture) }
  }

  /// Drops one without acting on it — the reader looked and decided against it.
  static func discard(_ capture: SharedJobCapture) {
    mutate { queue in queue.removeAll { $0 == capture } }
  }

  static func discardAll() {
    mutate { queue in queue.removeAll() }
    let defaults = UserDefaults(suiteName: appGroupID)
    defaults?.removeObject(forKey: legacyKey)
    defaults?.removeObject(forKey: legacyQueueKey)
  }

  // MARK: - Coordinated access

  /// Read, change and write back as one coordinated step, so a share arriving
  /// mid-change waits rather than lands on top.
  @discardableResult
  private static func mutate<T>(_ body: (inout [SharedJobCapture]) -> T) -> T? {
    migrateLegacyStorageIfNeeded()
    guard let url = fileURL else { return nil }
    var result: T?
    coordinateWriting(url) { url in
      var queue = decode(at: url)
      result = body(&queue)
      // Sorting on the way out rather than the way in: the two processes append
      // independently, so arrival order is only settled once both are seen.
      queue.sort { $0.receivedAt < $1.receivedAt }
      encode(Array(queue.suffix(limit)), to: url)
    }
    return result
  }

  private static func coordinateReading(_ url: URL, _ body: (URL) -> Void) {
    var error: NSError?
    NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { body($0) }
  }

  private static func coordinateWriting(_ url: URL, _ body: (URL) -> Void) {
    var error: NSError?
    NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &error) { body($0) }
  }

  private static func decode(at url: URL) -> [SharedJobCapture] {
    guard let data = try? Data(contentsOf: url),
      let queue = try? JSONDecoder().decode([SharedJobCapture].self, from: data)
    else { return [] }
    return queue
  }

  private static func encode(_ queue: [SharedJobCapture], to url: URL) {
    guard let data = try? JSONEncoder().encode(queue) else { return }
    // Readable by the extension whenever the device has been unlocked once,
    // which is the weakest condition under which either process ever runs.
    try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }

  // MARK: - Migration

  /// Runs the migration the first time anything touches the inbox, and never
  /// again in this process. Opening app-group defaults is a round trip to
  /// `cfprefsd` that logs a complaint each time; doing it on every read — and
  /// the count is read on every foreground — turned a one-off into a permanent
  /// cost. A `static let` is initialised lazily and exactly once, under a lock.
  private static let legacyStorageMigrated: Void = migrateLegacyStorage()

  private static func migrateLegacyStorageIfNeeded() { _ = legacyStorageMigrated }

  /// Moves anything left in `UserDefaults` by an earlier build into the file.
  ///
  /// Not private so it can be exercised directly: the automatic path runs once
  /// per process, which is right in the app and useless in a test that needs to
  /// set the old storage up more than once.
  static func migrateLegacyStorage() {
    guard let defaults = UserDefaults(suiteName: appGroupID), let url = fileURL else { return }
    let queued = defaults.data(forKey: legacyQueueKey)
    let single = defaults.data(forKey: legacyKey)
    guard queued != nil || single != nil else { return }

    var carried: [SharedJobCapture] = []
    if let queued, let decoded = try? JSONDecoder().decode([SharedJobCapture].self, from: queued) {
      carried += decoded
    }
    if let single, let decoded = try? JSONDecoder().decode(SharedJobCapture.self, from: single) {
      carried.append(decoded)
    }
    defaults.removeObject(forKey: legacyQueueKey)
    defaults.removeObject(forKey: legacyKey)
    guard !carried.isEmpty else { return }

    coordinateWriting(url) { url in
      var queue = decode(at: url) + carried
      queue.sort { $0.receivedAt < $1.receivedAt }
      encode(Array(queue.suffix(limit)), to: url)
    }
  }
}

extension Notification.Name {
  static let openSharedJobCapture = Notification.Name("ResumeStudio.openSharedJobCapture")
}
