import Network
import SwiftUI

/// Tracks whether the device currently has a usable network route, so the AI
/// surfaces can disable their actions and explain themselves before a request
/// fails, rather than looking broken.
@MainActor
final class NetworkMonitor: ObservableObject {
  static let shared = NetworkMonitor()

  // Start conservatively. NWPathMonitor publishes the real state immediately;
  // assuming online during that window can incorrectly discard cached access.
  @Published private(set) var isOnline = false

  private let monitor = NWPathMonitor()
  private let queue = DispatchQueue(label: "com.resumestudio.networkmonitor")

  init() {
    if ProcessInfo.processInfo.environment["RESUMESTUDIO_FORCE_OFFLINE"] == "1" {
      isOnline = false
      return
    }
    monitor.pathUpdateHandler = { [weak self] path in
      let online = path.status == .satisfied
      Task { @MainActor in self?.isOnline = online }
    }
    monitor.start(queue: queue)
  }

  deinit {
    monitor.cancel()
  }
}
