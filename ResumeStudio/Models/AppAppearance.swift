import SwiftUI

/// How the app picks its appearance. Persisted in `@AppStorage("appAppearance")`.
///
/// New installs start with the app's soft light appearance. `system` remains an
/// explicit choice for anyone who wants ResumeStudio to follow iOS.
enum AppAppearance: String, CaseIterable, Identifiable {
  case system
  case light
  case dark

  static let defaultChoice: AppAppearance = .light

  var id: String { rawValue }

  var title: LocalizedStringResource {
    switch self {
    case .system: "System"
    case .light: "Light"
    case .dark: "Dark"
    }
  }

  var systemImage: String {
    switch self {
    case .system: "iphone"
    case .light: "sun.max.fill"
    case .dark: "moon.fill"
    }
  }

  /// `nil` hands the decision back to iOS.
  var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}
