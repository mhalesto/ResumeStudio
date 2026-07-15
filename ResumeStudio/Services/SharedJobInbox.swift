import Foundation

enum SharedJobInbox {
  static let appGroupID = "group.com.halalisanimbanjwa.ResumeStudio"
  static let pendingKey = "pendingJobCapture"

  static func consume() -> SharedJobCapture? {
    guard let defaults = UserDefaults(suiteName: appGroupID),
      let data = defaults.data(forKey: pendingKey),
      let capture = try? JSONDecoder().decode(SharedJobCapture.self, from: data)
    else { return nil }
    defaults.removeObject(forKey: pendingKey)
    return capture
  }
}

extension Notification.Name {
  static let openSharedJobCapture = Notification.Name("ResumeStudio.openSharedJobCapture")
}
