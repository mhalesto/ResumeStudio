import SwiftUI
import UIKit

/// The launch animation.
///
/// The mark is the app icon itself — the rendered `LaunchMark` tile, the same
/// image the static launch screen centres — so the icon a user taps and the
/// screen they land on are pixel-identical. It settles onto a `BrandPalette`
/// field, a light sweep scans across it (echoing the icon's magnifier), and the
/// wordmark writes in. The first frame matches the system launch screen exactly,
/// so the hand-off has no visible seam.
struct SplashView: View {
  /// Called once the animation has played out; the host fades the splash away.
  let onFinish: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var fieldIn = false
  @State private var glowIn = false
  @State private var bloomed = false
  @State private var scanned = false
  @State private var wordmarkIn = false
  @State private var taglineIn = false
  @State private var shimmerIn = false
  @State private var drifting = false

  var body: some View {
    ZStack {
      field
      orbs

      // The native launch image is centred in the full screen at 132 x 132.
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
      .offset(y: 134)
    }
    .ignoresSafeArea()
    .task { await play() }
  }

  // MARK: - Choreography

  private func play() async {
    guard !reduceMotion else {
      withAnimation(.easeOut(duration: 0.45)) {
        fieldIn = true
        glowIn = true
        scanned = true
        wordmarkIn = true
        taglineIn = true
      }
      try? await Task.sleep(for: .milliseconds(1_150))
      onFinish()
      return
    }

    // Warmed up front so the tap lands with the tile rather than trailing it.
    let landing = UIImpactFeedbackGenerator(style: .soft)
    landing.prepare()

    withAnimation(.easeOut(duration: 0.9)) { fieldIn = true }
    withAnimation(.easeOut(duration: 0.85).delay(0.24)) { glowIn = true }
    withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) { drifting = true }

    // The tile settles: haptic, and the light blooms behind it.
    try? await Task.sleep(for: .milliseconds(340))
    landing.impactOccurred(intensity: 0.75)
    withAnimation(.easeOut(duration: 0.28)) { bloomed = true }

    // A light sweep passes over the tile, like the lens scanning the page.
    withAnimation(.easeInOut(duration: 0.9).delay(0.08)) { scanned = true }

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
    Image("LaunchMark")
      .resizable()
      .interpolation(.high)
      .frame(width: Tile.size, height: Tile.size)
      .overlay {
        // A single light sweep across the tile, like the lens passing over the
        // page. Off-screen at rest, so the first frame matches the launch image.
        LinearGradient(
          colors: [.white.opacity(0), .white.opacity(0.45), .white.opacity(0)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        .frame(width: 64)
        .offset(x: scanned ? Tile.size : -Tile.size)
        .blendMode(.plusLighter)
      }
      .clipShape(RoundedRectangle(cornerRadius: Tile.cornerRadius, style: .continuous))
      .shadow(color: .black.opacity(0.32), radius: 18, y: 12)
    // No initial transform: the tile exactly matches the native launch image's
    // size and screen position, so the launch-screen hand-off has no seam.
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

/// The mark's tile — the `LaunchMark` image sized to match the native launch
/// screen (centred at 132pt), with the home-screen mask radius so it reads as
/// the tapped icon.
private enum Tile {
  static let size: CGFloat = 132
  static let cornerRadius: CGFloat = 29.5
}

#Preview {
  SplashView {}
}
