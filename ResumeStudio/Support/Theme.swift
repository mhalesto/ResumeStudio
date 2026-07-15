import SwiftUI
import UIKit

/// The app's surface and type tokens, ported from the web prototype.
///
/// The prototype defines the palette in OKLCH; these are the exact sRGB
/// conversions, including its dark set — so every surface here adapts rather
/// than only working in light mode.
///
/// Deliberately *not* here: the brand colour. The UI is tinted with the user's
/// chosen `ResumeAccent`, so all four of their accents drive the new design
/// rather than a single hard-coded orange.
enum Theme {

  // MARK: - Surfaces

  /// The page. A warm off-white, rather than iOS's cool grouped grey.
  static let paper = Color.adaptive(
    light: Color(red: 0.988, green: 0.975, blue: 0.954),
    dark: Color(red: 0.045, green: 0.061, blue: 0.086)
  )

  /// Raised cards sitting on `paper`.
  static let card = Color.adaptive(
    light: Color(red: 1.000, green: 0.993, blue: 0.979),
    dark: Color(red: 0.085, green: 0.105, blue: 0.138)
  )

  /// Recessed surfaces — the privacy note, progress tracks.
  static let muted = Color.adaptive(
    light: Color(red: 0.939, green: 0.919, blue: 0.888),
    dark: Color(red: 0.128, green: 0.152, blue: 0.190)
  )

  static let hairline = Color.adaptive(
    light: Color(red: 0.888, green: 0.867, blue: 0.837),
    dark: Color.white.opacity(0.08)
  )

  // MARK: - Type

  static let ink = Color.adaptive(
    light: Color(red: 0.038, green: 0.069, blue: 0.121),
    dark: Color(red: 0.956, green: 0.946, blue: 0.931)
  )

  static let inkSoft = Color.adaptive(
    light: Color(red: 0.167, green: 0.201, blue: 0.256),
    dark: Color(red: 0.782, green: 0.767, blue: 0.741)
  )

  static let mutedInk = Color.adaptive(
    light: Color(red: 0.363, green: 0.391, blue: 0.435),
    dark: Color(red: 0.616, green: 0.594, blue: 0.557)
  )

  // MARK: - Hero

  /// The hero card stays dark in both appearances: in light mode a bold dark
  /// slab on warm paper, in dark mode a raised card.
  ///
  /// It has to lift *away* from the page in dark mode, so the gradient is a step
  /// lighter there — a card darker than its background reads as a hole.
  static let heroTop = Color.adaptive(
    light: Color(red: 0.085, green: 0.105, blue: 0.138),
    dark: Color(red: 0.118, green: 0.140, blue: 0.180)
  )
  static let heroBottom = Color.adaptive(
    light: Color(red: 0.031, green: 0.044, blue: 0.067),
    dark: Color(red: 0.063, green: 0.079, blue: 0.107)
  )
  static let heroInk = Color(red: 0.956, green: 0.946, blue: 0.931)
  static let heroMutedInk = Color(red: 0.616, green: 0.594, blue: 0.557)

  // MARK: - Geometry

  static let heroRadius: CGFloat = 28
  static let cardRadius: CGFloat = 22
  static let tileRadius: CGFloat = 16

  // MARK: - Type styles

  /// The display face. The prototype sets Instrument Serif and falls back to
  /// New York on Apple platforms — which is what `.serif` resolves to, so this
  /// is the prototype's own intended iOS typeface, with Dynamic Type for free.
  static func display(_ size: CGFloat) -> Font {
    .system(size: size, weight: .regular, design: .serif)
  }
}

// MARK: - Reusable treatments

extension View {
  /// A raised card on `Theme.paper`: warm fill, hairline edge, soft lift.
  func cardSurface(radius: CGFloat = Theme.cardRadius) -> some View {
    background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .strokeBorder(Theme.hairline, lineWidth: 1)
      }
      .shadow(color: Theme.ink.opacity(0.06), radius: 14, y: 8)
  }

  /// Small uppercase label with wide tracking, as used for the greeting and the
  /// hero's stat captions. Uses a text style rather than a fixed size so it grows
  /// with the reader's Dynamic Type setting.
  func eyebrow() -> some View {
    font(.caption2.weight(.semibold))
      .textCase(.uppercase)
      .tracking(1.4)
  }
}

extension Color {
  /// Resolves per appearance, so tokens work in light and dark without every
  /// call site branching.
  static func adaptive(light: Color, dark: Color) -> Color {
    Color(uiColor: UIColor { traits in
      traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
    })
  }
}
