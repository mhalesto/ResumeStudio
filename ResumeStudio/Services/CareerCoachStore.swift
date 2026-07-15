import Combine
import Foundation

@MainActor
final class CareerCoachStore: ObservableObject {
  @Published private(set) var messages: [CareerCoachMessage] = [] {
    didSet { save() }
  }
  @Published var suggestedPrompts: [String] = []

  private let fileURL: URL

  init(fileURL: URL? = nil) {
    self.fileURL = fileURL ?? Self.defaultURL
    guard let data = try? Data(contentsOf: self.fileURL) else { return }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    messages = (try? decoder.decode([CareerCoachMessage].self, from: data)) ?? []
  }

  func ensureWelcome(_ text: String) {
    guard messages.isEmpty else { return }
    messages = [CareerCoachMessage(role: .assistant, content: text)]
  }

  func append(_ message: CareerCoachMessage) {
    messages.append(message)
    if messages.count > 60 {
      messages.removeFirst(messages.count - 60)
    }
  }

  func reset(welcome: String) {
    suggestedPrompts = []
    messages = [CareerCoachMessage(role: .assistant, content: welcome)]
  }

  private func save() {
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .secondsSince1970
      try encoder.encode(messages).write(to: fileURL, options: .atomic)
    } catch {
      // Chat persistence is a convenience; a failed local save must not block coaching.
    }
  }

  private static var defaultURL: URL {
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return root.appendingPathComponent("ResumeStudio", isDirectory: true)
      .appendingPathComponent("career-coach-chat.json")
  }
}
