import SwiftUI
import UIKit

/// The app's surface and type tokens. The light surfaces use a soft cream-white
/// palette so the workspace feels warm without reading as beige; the dark set
/// keeps the deeper navy treatment. Every surface adapts with the system theme.
///
/// Deliberately *not* here: the brand colour. The UI is tinted with the user's
/// chosen `ResumeAccent`, so all four of their accents drive the new design
/// rather than a single hard-coded orange.
enum Theme {

  // MARK: - Surfaces

  /// The page. A dreamy cream-white, rather than a bright or cool system white.
  static let paper = Color.adaptive(
    light: Color(red: 0.965, green: 0.941, blue: 0.910),
    dark: Color(red: 0.045, green: 0.061, blue: 0.086)
  )

  /// Raised cards stay gently lighter than the page without becoming stark white.
  static let card = Color.adaptive(
    light: Color(red: 0.988, green: 0.973, blue: 0.945),
    dark: Color(red: 0.085, green: 0.105, blue: 0.138)
  )

  /// Recessed surfaces — the privacy note, progress tracks.
  static let muted = Color.adaptive(
    light: Color(red: 0.918, green: 0.882, blue: 0.839),
    dark: Color(red: 0.128, green: 0.152, blue: 0.190)
  )

  static let hairline = Color.adaptive(
    light: Color(red: 0.871, green: 0.827, blue: 0.773),
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

  /// The display face at a **fixed** point size. The prototype sets Instrument
  /// Serif and falls back to New York on Apple platforms — which is what
  /// `.serif` resolves to, so this is the prototype's own intended iOS typeface.
  ///
  /// This does *not* respond to Dynamic Type: `Font.system(size:)` is a fixed
  /// size, unlike the text-style fonts (`.body`, `.title`…). Prefer the
  /// `displayFont(_:)` view modifier below, which scales the same face with the
  /// reader's text-size setting. This overload remains for the few places that
  /// need a concrete `Font` value rather than a modifier — measuring text, or
  /// drawing at a size that is deliberately absolute.
  static func display(_ size: CGFloat) -> Font {
    .system(size: size, weight: .regular, design: .serif)
  }
}

// MARK: - Dynamic Type

/// Applies a system font at a point size that grows with the reader's text-size
/// setting.
///
/// `Font.system(size:)` is fixed — a 14pt label stays 14pt at every Dynamic Type
/// setting, including the accessibility sizes. `@ScaledMetric` is the piece that
/// makes a specific size responsive, and because it reads the environment
/// SwiftUI re-evaluates the body when the setting changes. It has to live in a
/// `View`, which is why this is a modifier rather than a `Font` factory.
///
/// `relativeTo` picks the curve the size follows: a caption-sized label should
/// scale like a caption, a title like a title.
private struct ScaledFontModifier: ViewModifier {
  @ScaledMetric private var size: CGFloat
  private let weight: Font.Weight
  private let design: Font.Design
  private let maxSize: CGFloat?

  init(
    size: CGFloat,
    relativeTo textStyle: Font.TextStyle,
    weight: Font.Weight,
    design: Font.Design,
    maxSize: CGFloat?
  ) {
    _size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
    self.weight = weight
    self.design = design
    self.maxSize = maxSize
  }

  func body(content: Content) -> some View {
    content.font(.system(size: min(size, maxSize ?? .greatestFiniteMagnitude), weight: weight, design: design))
  }
}

extension View {
  /// A system font at `size`, scaled for Dynamic Type. Use in place of
  /// `.font(.system(size:))` on anything a reader has to actually read.
  ///
  /// Decorative glyphs — background watermarks, bullet dots, the miniature type
  /// inside a template preview — should keep a fixed size and stay on
  /// `.font(.system(size:))`, because they represent artwork rather than text.
  ///
  /// `maxSize` caps growth for large display type, where the accessibility sizes
  /// would otherwise push a heading past anything the layout can hold.
  func scaledFont(
    _ size: CGFloat,
    relativeTo textStyle: Font.TextStyle = .body,
    weight: Font.Weight = .regular,
    design: Font.Design = .default,
    maxSize: CGFloat? = nil
  ) -> some View {
    modifier(ScaledFontModifier(size: size, relativeTo: textStyle, weight: weight, design: design, maxSize: maxSize))
  }

  /// The serif display face at a Dynamic Type-aware size — the scaling
  /// counterpart to `Theme.display(_:)`, and the one screen titles should use.
  ///
  /// Display type is capped at 1.6× its designed size. Left uncapped, a 58pt
  /// score at the largest accessibility setting renders around 150pt and drives
  /// everything beneath it off the screen; 1.6× keeps the heading clearly
  /// responsive while the body text around it carries on scaling to full size.
  func displayFont(
    _ size: CGFloat,
    relativeTo textStyle: Font.TextStyle = .largeTitle,
    weight: Font.Weight = .regular
  ) -> some View {
    scaledFont(size, relativeTo: textStyle, weight: weight, design: .serif, maxSize: size * 1.6)
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
