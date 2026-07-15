import SwiftUI
import UIKit

/// The launch animation.
///
/// The mark is the app icon's résumé sheet, rebuilt in SwiftUI: it lands, its
/// second page fans out behind it, and the content writes itself in line by
/// line. The first frame is a flat `BrandPalette.launch` field — the same colour
/// as the static launch screen — so the hand-off from the system launch screen
/// has no visible seam.
struct SplashView: View {
  /// Called once the animation has played out; the host fades the splash away.
  let onFinish: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var fieldIn = false
  @State private var fannedOut = false
  @State private var glowIn = false
  @State private var bloomed = false
  @State private var written = Array(repeating: false, count: SheetRow.all.count)
  @State private var wordmarkIn = false
  @State private var taglineIn = false
  @State private var shimmerIn = false
  @State private var drifting = false

  var body: some View {
    ZStack {
      field
      orbs

      // The native launch image is centred in the full screen at 132 x 162.
      // Keep this mark in its own layout layer so the initially hidden type
      // below it cannot pull it upward during the launch-screen hand-off.
      ZStack {
        glow
        mark
      }

      VStack(spacing: 12) {
        wordmark
        tagline
      }
      .offset(y: 149)
    }
    .ignoresSafeArea()
    .task { await play() }
  }

  // MARK: - Choreography

  private func play() async {
    guard !reduceMotion else {
      withAnimation(.easeOut(duration: 0.45)) {
        fieldIn = true
        fannedOut = true
        glowIn = true
        written = written.map { _ in true }
        wordmarkIn = true
        taglineIn = true
      }
      try? await Task.sleep(for: .milliseconds(1_150))
      onFinish()
      return
    }

    // Warmed up front so the tap lands with the sheet rather than trailing it.
    let landing = UIImpactFeedbackGenerator(style: .soft)
    landing.prepare()

    withAnimation(.easeOut(duration: 0.9)) { fieldIn = true }
    withAnimation(.easeOut(duration: 0.85).delay(0.24)) { glowIn = true }
    withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) { drifting = true }

    // The sheet lands: haptic, the second page fans out, and the light blooms.
    try? await Task.sleep(for: .milliseconds(340))
    landing.impactOccurred(intensity: 0.75)
    withAnimation(.spring(response: 0.55, dampingFraction: 0.55)) { fannedOut = true }
    withAnimation(.easeOut(duration: 0.28)) { bloomed = true }

    // The résumé writes itself in.
    for index in written.indices {
      withAnimation(.spring(response: 0.42, dampingFraction: 0.80).delay(Double(index) * 0.055)) {
        written[index] = true
      }
    }

    try? await Task.sleep(for: .milliseconds(360))
    withAnimation(.easeOut(duration: 1.1)) { bloomed = false }  // The bloom settles back.
    withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) { wordmarkIn = true }
    withAnimation(.easeInOut(duration: 1.0).delay(0.20)) { shimmerIn = true }

    try? await Task.sleep(for: .milliseconds(180))
    withAnimation(.easeOut(duration: 0.5)) { taglineIn = true }

    try? await Task.sleep(for: .milliseconds(820))
    onFinish()
  }

  // MARK: - Field

  private var field: some View {
    ZStack {
      BrandPalette.launch

      Image("SplashCareerBackground")
        .resizable()
        .scaledToFill()
        .saturation(0.82)
        .overlay(BrandPalette.launch.opacity(0.24))
        .opacity(fieldIn ? 0.82 : 0)
        .accessibilityHidden(true)

      LinearGradient(
        colors: [
          BrandPalette.fieldTop.opacity(0.48),
          BrandPalette.fieldBottom.opacity(0.78),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .opacity(fieldIn ? 1 : 0)

      RadialGradient(
        colors: [BrandPalette.spotlight.opacity(0.22), .clear],
        center: UnitPoint(x: 0.5, y: 0.42),
        startRadius: 0,
        endRadius: 380
      )
      .blendMode(.plusLighter)
      .opacity(fieldIn ? 1 : 0)
    }
  }

  private var orbs: some View {
    ZStack {
      Circle()
        .fill(BrandPalette.spotlight.opacity(0.12))
        .frame(width: 320, height: 320)
        .blur(radius: 70)
        .offset(x: drifting ? -118 : -86, y: drifting ? -250 : -290)

      Circle()
        .fill(BrandPalette.haze.opacity(0.14))
        .frame(width: 280, height: 280)
        .blur(radius: 70)
        .offset(x: drifting ? 132 : 100, y: drifting ? 268 : 308)
    }
    .opacity(fieldIn ? 1 : 0)
  }

  // MARK: - Mark

  /// The page is lit from behind, and the light blooms as it lands.
  private var glow: some View {
    Circle()
      .fill(
        RadialGradient(
          colors: [BrandPalette.spotlight.opacity(0.40), .clear],
          center: .center,
          startRadius: 0,
          endRadius: 150
        )
      )
      .frame(width: 300, height: 300)
      .blur(radius: 24)
      .blendMode(.plusLighter)
      .scaleEffect(glowIn ? (bloomed ? 1.22 : 1) : 0.5)
      .opacity(glowIn ? (bloomed ? 1 : 0.75) : 0)
  }

  private var mark: some View {
    ZStack {
      // The second page, fanning out from behind the first once it lands.
      RoundedRectangle(cornerRadius: SheetRow.cornerRadius, style: .continuous)
        .fill(.white.opacity(0.28))
        .frame(width: SheetRow.sheetWidth, height: SheetRow.sheetHeight)
        .scaleEffect(0.96)
        .rotationEffect(.degrees(fannedOut ? -8 : 0))

      sheet
    }
    // This front page intentionally has no initial transform: it exactly
    // matches the native launch image's size, rotation and screen position.
  }

  private var sheet: some View {
    ZStack(alignment: .topLeading) {
      Rectangle()
        .fill(.white)

      Rectangle()
        .fill(
          LinearGradient(
            colors: [BrandPalette.bandTop, BrandPalette.bandBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
        .frame(height: SheetRow.bandHeight)

      ForEach(SheetRow.all) { row in
        Capsule()
          .fill(row.color)
          .frame(width: row.width, height: row.height)
          .scaleEffect(x: written[row.id] ? 1 : 0, anchor: .leading)
          .opacity(written[row.id] ? 1 : 0)
          .offset(x: SheetRow.margin, y: row.y)
      }
    }
    .frame(width: SheetRow.sheetWidth, height: SheetRow.sheetHeight)
    .clipShape(RoundedRectangle(cornerRadius: SheetRow.cornerRadius, style: .continuous))
    .shadow(color: .black.opacity(0.35), radius: 22, y: 14)
  }

  // MARK: - Type

  private var wordmark: some View {
    let title = "Resume Studio"
    // The same display serif the home hero uses, so the launch and the app read
    // as one piece of typography.
    let font = Theme.display(36)

    return Text(title)
      .font(font)
      .foregroundStyle(.white)
      .overlay(
        // A light sweep across the glyphs, clipped to them by the mask below.
        LinearGradient(
          colors: [.white.opacity(0), .white.opacity(0.85), .white.opacity(0)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        .frame(width: 90)
        .offset(x: shimmerIn ? 150 : -150)
        .blendMode(.plusLighter)
      )
      .mask(Text(title).font(font))
      .opacity(wordmarkIn ? 1 : 0)
      .offset(y: wordmarkIn ? 0 : 14)
  }

  private var tagline: some View {
    Text("CRAFT · STYLE · EXPORT")
      .font(.system(size: 11, weight: .semibold, design: .rounded))
      .tracking(2.6)
      .foregroundStyle(.white.opacity(0.45))
      .opacity(taglineIn ? 1 : 0)
  }
}

/// One row of the mark's résumé sheet, laid out to match the app icon's artwork
/// scaled to `sheetWidth` (the icon draws the same sheet at 440pt wide).
private struct SheetRow: Identifiable {
  let id: Int
  let y: CGFloat
  let width: CGFloat
  let height: CGFloat
  let color: Color

  static let sheetWidth: CGFloat = 132
  static let sheetHeight: CGFloat = 162
  static let bandHeight: CGFloat = 49
  static let cornerRadius: CGFloat = 26
  static let margin: CGFloat = 12

  static let all: [SheetRow] = [
    // Name and headline, sitting on the orange band.
    SheetRow(id: 0, y: 17, width: 67, height: 8, color: .white.opacity(0.95)),
    SheetRow(id: 1, y: 30, width: 42, height: 5, color: .white.opacity(0.60)),
    // First section.
    SheetRow(id: 2, y: 62, width: 45, height: 7, color: BrandPalette.ink.opacity(0.92)),
    SheetRow(id: 3, y: 76, width: 108, height: 6, color: BrandPalette.ink.opacity(0.22)),
    SheetRow(id: 4, y: 87, width: 90, height: 6, color: BrandPalette.ink.opacity(0.14)),
    // Second section, headed by the brand accent.
    SheetRow(id: 5, y: 104, width: 38, height: 7, color: BrandPalette.bandTop),
    SheetRow(id: 6, y: 118, width: 108, height: 6, color: BrandPalette.ink.opacity(0.22)),
    SheetRow(id: 7, y: 129, width: 99, height: 6, color: BrandPalette.ink.opacity(0.14)),
    SheetRow(id: 8, y: 140, width: 72, height: 6, color: BrandPalette.ink.opacity(0.14)),
  ]
}

#Preview {
  SplashView {}
}
