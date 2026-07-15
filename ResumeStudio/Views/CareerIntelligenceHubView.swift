import SwiftUI

struct CareerIntelligencePromoCard: View {
  let accent: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      ZStack(alignment: .bottomLeading) {
        LinearGradient(
          colors: [Theme.heroTop, Theme.heroBottom],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        Circle().fill(accent.opacity(0.34)).frame(width: 190, height: 190).blur(radius: 30).offset(x: 160, y: -55)
        Circle().fill(Color.indigo.opacity(0.24)).frame(width: 150, height: 150).blur(radius: 34).offset(x: -90, y: 70)

        HStack(spacing: 18) {
          CareerOrbitGraphic(accent: accent)
            .frame(width: 94, height: 94)

          VStack(alignment: .leading, spacing: 6) {
            Text("Career Intelligence")
              .font(.headline)
              .foregroundStyle(Theme.heroInk)
            Text("Evidence vault, job capture, voice interviews and the tools behind every application.")
              .font(.caption)
              .foregroundStyle(Theme.heroMutedInk)
              .fixedSize(horizontal: false, vertical: true)
            Label("Open career studio", systemImage: "arrow.right")
              .font(.caption.weight(.bold))
              .foregroundStyle(accent)
              .padding(.top, 3)
          }
          Spacer(minLength: 0)
        }
        .padding(19)
      }
      .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
      }
      .shadow(color: Theme.ink.opacity(0.14), radius: 22, y: 12)
    }
    .buttonStyle(.plain)
  }
}

struct CareerIntelligenceHubView: View {
  @EnvironmentObject private var resumeStore: ResumeStore
  @EnvironmentObject private var careerStore: CareerIntelligenceStore
  @EnvironmentObject private var applicationStore: ApplicationStore

  private let columns = [GridItem(.flexible()), GridItem(.flexible())]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        hero
        HStack(spacing: 10) {
          IntelligenceStat(value: "\(careerStore.verifiedEvidence.count)", label: "Verified facts")
          IntelligenceStat(value: "\(applicationStore.applications.count)", label: "Applications")
          IntelligenceStat(value: "\(careerStore.voiceAttempts.count)", label: "Practices")
        }

        Text("Build your advantage")
          .font(Theme.display(28))
          .foregroundStyle(Theme.ink)

        LazyVGrid(columns: columns, spacing: 14) {
          tool("Evidence Vault", "Your verified career memory", "checkmark.seal.fill", .evidenceVault, .orange)
          tool("Capture a Job", "Link, advert or job pack", "square.and.arrow.down.fill", .jobCapture, .blue)
          tool("Review AI Changes", "Sources before acceptance", "arrow.left.arrow.right.circle.fill", .aiChangeReview, .purple)
          tool("Voice Interview", "Speak, replay and improve", "waveform.and.mic", .voiceInterview, .pink)
          tool("Applications", "Pipeline and outcomes", "rectangle.3.group.fill", .applications, .teal)
          tool("LinkedIn Studio", "Headline, About and keywords", "person.crop.rectangle.stack.fill", .linkedInStudio, .blue)
          tool("Networking", "People and follow-ups", "person.2.wave.2.fill", .networking, .indigo)
          tool("Offers", "Compare and negotiate", "scale.3d", .offers, .green)
          tool("Review Room", "Private feedback workflow", "person.2.badge.gearshape.fill", .reviewRoom, .mint)
          tool("Market Guide", "Local conventions", "globe.africa.fill", .marketGuidance, .cyan)
          tool("Privacy Centre", "AI controls and processing history", "lock.shield.fill", .privacyCenter, .green)
        }
      }
      .padding(20)
      .padding(.bottom, 40)
      .frame(maxWidth: 720)
      .frame(maxWidth: .infinity)
    }
    .background(Theme.paper)
    .navigationTitle("Career Intelligence")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var hero: some View {
    ZStack(alignment: .bottomLeading) {
      Image("CareerIntelligenceHero")
        .resizable()
        .scaledToFill()
      LinearGradient(
        colors: [BrandPalette.fieldBottom.opacity(0.98), BrandPalette.fieldBottom.opacity(0.76), .clear],
        startPoint: .leading,
        endPoint: .trailing
      )
      LinearGradient(colors: [.clear, BrandPalette.fieldBottom.opacity(0.48)], startPoint: .top, endPoint: .bottom)

      VStack(alignment: .leading, spacing: 8) {
        Text("ONE CAREER. EVERY MOVE.").eyebrow().foregroundStyle(resumeStore.document.accent.color)
        Text("Turn your experience\ninto momentum.")
          .font(Theme.display(34))
          .foregroundStyle(Theme.heroInk)
        Text("ResumeStudio remembers the evidence, keeps every application connected and helps you prepare without inventing facts.")
          .font(.subheadline)
          .foregroundStyle(Theme.heroMutedInk)
          .frame(maxWidth: 340, alignment: .leading)
      }
      .padding(24)
    }
    .frame(minHeight: 270)
    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    .overlay { RoundedRectangle(cornerRadius: 30).strokeBorder(Color.white.opacity(0.08)) }
    .shadow(color: Theme.ink.opacity(0.18), radius: 28, y: 16)
  }

  private func tool(
    _ title: String, _ subtitle: String, _ icon: String, _ route: HomeRoute, _ color: Color
  ) -> some View {
    NavigationLink(value: route) {
      VStack(alignment: .leading, spacing: 14) {
        ZStack {
          RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(LinearGradient(colors: [color.opacity(0.28), color.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
          Image(systemName: icon).font(.system(size: 23, weight: .semibold)).foregroundStyle(color)
        }
        .frame(width: 52, height: 52)
        Text(title).font(.headline).foregroundStyle(Theme.ink)
        Text(subtitle).font(.caption).foregroundStyle(Theme.mutedInk).fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
        Image(systemName: "arrow.up.right").font(.caption.weight(.bold)).foregroundStyle(color)
      }
      .padding(17)
      .frame(maxWidth: .infinity, minHeight: 186, alignment: .leading)
      .cardSurface(radius: 22)
    }
    .buttonStyle(.plain)
  }
}

private struct IntelligenceStat: View {
  let value: String
  let label: String
  var body: some View {
    VStack(spacing: 3) {
      Text(value).font(.title2.bold()).foregroundStyle(Theme.ink)
      Text(label).font(.caption2).foregroundStyle(Theme.mutedInk).lineLimit(1).minimumScaleFactor(0.7)
    }
    .padding(.vertical, 13)
    .frame(maxWidth: .infinity)
    .cardSurface(radius: 17)
  }
}

private struct CareerOrbitGraphic: View {
  let accent: Color
  @State private var rotates = false

  var body: some View {
    GeometryReader { proxy in
      let size = min(proxy.size.width, proxy.size.height)
      ZStack {
        Circle().stroke(Color.white.opacity(0.12), lineWidth: 1)
        Circle().stroke(accent.opacity(0.45), style: StrokeStyle(lineWidth: 2, dash: [4, 7]))
          .padding(size * 0.13)
          .rotationEffect(.degrees(rotates ? 360 : 0))
        RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
          .fill(.ultraThinMaterial)
          .frame(width: size * 0.46, height: size * 0.56)
          .overlay {
            VStack(spacing: size * 0.045) {
              Capsule().fill(accent).frame(width: size * 0.24, height: size * 0.035)
              ForEach(0..<3, id: \.self) { index in
                Capsule().fill(Color.white.opacity(0.68 - Double(index) * 0.12)).frame(width: size * (0.3 - CGFloat(index) * 0.035), height: size * 0.025)
              }
            }
          }
        Image(systemName: "sparkles").foregroundStyle(accent).offset(x: size * 0.33, y: -size * 0.26)
        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).offset(x: -size * 0.34, y: size * 0.23)
      }
      .onAppear {
        withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) { rotates = true }
      }
    }
  }
}
