import Foundation

@MainActor
final class ApplicationAnswerVaultStore: ObservableObject {
  @Published private(set) var answers: [ApplicationAnswer] = []
  @Published private(set) var lastSaveError: String?

  private let defaults: UserDefaults
  private let storageKey: String

  init(
    defaults: UserDefaults = .standard,
    storageKey: String = "applicationAnswerVault.v1"
  ) {
    self.defaults = defaults
    self.storageKey = storageKey
    if let data = defaults.data(forKey: storageKey),
      let saved = try? JSONDecoder().decode([ApplicationAnswer].self, from: data)
    {
      answers = saved
    } else {
      answers = ApplicationAnswer.starterEntries
      save()
    }
  }

  var publishableAnswers: [ApplicationAnswer] {
    answers.filter(\.canPublish)
  }

  func upsert(_ answer: ApplicationAnswer) {
    var updated = answer
    updated.updatedAt = Date()
    if let index = answers.firstIndex(where: { $0.id == answer.id }) {
      answers[index] = updated
    } else {
      answers.insert(updated, at: 0)
    }
    save()
  }

  func setEnabled(_ enabled: Bool, id: UUID) {
    guard let index = answers.firstIndex(where: { $0.id == id }) else { return }
    guard !enabled || !answers[index].answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    answers[index].isEnabled = enabled
    answers[index].updatedAt = Date()
    save()
  }

  func delete(at offsets: IndexSet) {
    for index in offsets.sorted(by: >) where answers.indices.contains(index) {
      answers.remove(at: index)
    }
    save()
  }

  func restoreStarterQuestions() {
    let existing = Set(answers.map(\.category))
    let missing = ApplicationAnswer.starterEntries.filter { !existing.contains($0.category) }
    guard !missing.isEmpty else { return }
    answers.append(contentsOf: missing)
    save()
  }

  private func save() {
    do {
      defaults.set(try JSONEncoder().encode(answers), forKey: storageKey)
      lastSaveError = nil
    } catch {
      lastSaveError = error.localizedDescription
    }
  }
}
