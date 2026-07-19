import SwiftUI

/// How the app picks its appearance. Persisted in `@AppStorage("appAppearance")`.
///
/// `system` follows iOS, which is the default; the explicit options let someone
/// pin the app light or dark regardless of the device setting.
enum AppAppearance: String, CaseIterable, Identifiable {
  case system
  case light
  case dark

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
