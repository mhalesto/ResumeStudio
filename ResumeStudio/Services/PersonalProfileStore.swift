import Foundation

/// Holds the one hosted CV page this installation owns. Loaded on launch and
/// after every publish/withdraw so the Home entry and editor always reflect the
/// live state.
@MainActor
final class PersonalProfileStore: ObservableObject {
  @Published private(set) var profile: PersonalProfile?
  @Published private(set) var isLoading = false
  @Published private(set) var loadError: String?

  private let service = PersonalProfileService()

  var isPublished: Bool { profile != nil }

  /// Fetches the current page. Failures are surfaced but non-fatal — the editor
  /// still works, it just cannot show a previously published state.
  func load() async {
    guard !isLoading else { return }
    isLoading = true
    loadError = nil
    defer { isLoading = false }
    do { profile = try await service.fetch() }
    catch { loadError = error.localizedDescription }
  }

  func apply(_ profile: PersonalProfile?) {
    self.profile = profile
    self.loadError = nil
  }
}
