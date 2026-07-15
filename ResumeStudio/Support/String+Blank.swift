import Foundation

extension String {
  /// Empty once whitespace is discounted — a field the user hasn't really filled in.
  var isBlank: Bool {
    trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// The value, or `nil` when it's blank. Useful for `??` fallbacks in the UI.
  var nilIfBlank: String? {
    isBlank ? nil : self
  }
}
