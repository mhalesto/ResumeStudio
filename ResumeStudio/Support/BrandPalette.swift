import SwiftUI

/// Brand surfaces shared by the app icon, the launch screen and the splash.
///
/// These values mirror the artwork in `Assets.xcassets/AppIcon.appiconset`.
/// Keep them in step: the launch screen and `SplashView` sit the rendered icon
/// tile on this field, so drift here shows up as a visible mismatch between the
/// icon a user taps and the screen they land on.
enum BrandPalette {
  /// The flat navy of the static launch screen (the `LaunchBackground` colour
  /// set). `SplashView` opens on this exact colour so the hand-off has no seam.
  static let launch = Color(red: 0.10, green: 0.12, blue: 0.22)

  static let fieldTop = Color(red: 0.16, green: 0.20, blue: 0.34)
  static let fieldBottom = Color(red: 0.05, green: 0.06, blue: 0.13)

  /// Cool light behind the page. The field stays cool so the orange band is the
  /// only warm note, and carries all of the pop. Warm light over navy desaturates
  /// straight to brown, so there is deliberately none of it in the background.
  static let spotlight = Color(red: 0.55, green: 0.68, blue: 1.00)

  /// Deeper indigo, for the drifting haze in the splash's lower half.
  static let haze = Color(red: 0.35, green: 0.42, blue: 0.95)

  static let bandTop = Color(red: 0.90, green: 0.33, blue: 0.05)
  static let bandBottom = Color(red: 0.99, green: 0.57, blue: 0.16)

  static let ink = Color(red: 0.16, green: 0.19, blue: 0.29)

  /// The home hero's navy, a touch lighter than the splash field.
  static let heroTop = Color(red: 0.12, green: 0.15, blue: 0.24)
  static let heroBottom = Color(red: 0.20, green: 0.23, blue: 0.34)
}
