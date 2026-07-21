import SwiftUI

/// A miniature of a cover letter template.
///
/// The thumbnail is a real render of the exported PDF — the actual letter, with
/// its date, address block and prose — so the styles are distinguishable at a
/// glance. The original line art remains as the skeleton shown while that render
/// is in flight.
struct CoverLetterTemplateCard: View {
  @Environment(\.appTabIsActive) private var appTabIsActive

  let template: CoverLetterTemplate
  let accent: ResumeAccent
  let isSelected: Bool
  var width: CGFloat = 154

  /// A4 proportions. The card has to be page-shaped or the render gets cropped,
  /// and the first thing to go is the letterhead — the very thing that tells the
  /// templates apart.
  private var height: CGFloat { width * 842 / 595 }

  @State private var thumbnail: UIImage?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ZStack {
        Color.white

        if let thumbnail {
          Image(uiImage: thumbnail)
            .resizable()
            .scaledToFit()
            .transition(.opacity)
        } else {
          preview
        }
      }
      .frame(width: width, height: height)
      .task(id: CoverLetterKey(
        template: template, accent: accent, isTabActive: appTabIsActive
      )) {
        guard appTabIsActive else { return }
        // Already rendered this session: show it instantly, no skeleton flash.
        if let ready = CoverLetterThumbnailRenderer.cached(template: template, accent: accent) {
          thumbnail = ready
          return
        }
        // Debounce accent changes so the swatch and selection state update before
        // the first uncached full-PDF preview render begins.
        try? await Task.sleep(for: .milliseconds(220))
        guard !Task.isCancelled else { return }
        // Otherwise load from disk or render, serialised through the shared gate.
        let image = await CoverLetterThumbnailRenderer.image(template: template, accent: accent)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.25)) { thumbnail = image }
      }
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(isSelected ? accent.color : Theme.hairline, lineWidth: isSelected ? 3 : 1)
      }
      .overlay(alignment: .topTrailing) {
        if isSelected {
          ZStack {
            Circle().fill(accent.color)
            Image(systemName: "checkmark")
              .font(.system(size: 11, weight: .bold))
              .foregroundStyle(.white)
          }
          .frame(width: 24, height: 24)
          // Keep the full selection control inside the thumbnail bounds. An
          // outward offset was clipped by the horizontal carousel's viewport.
          .padding(7)
        }
      }
      .shadow(color: Theme.ink.opacity(0.08), radius: 8, y: 4)

      VStack(alignment: .leading, spacing: 3) {
        // Selection now reads from the corner badge, as it does on the résumé
        // cards, so the tick beside the title would just be saying it twice.
        Text(template.title)
          .font(.caption.weight(.bold))
          .foregroundStyle(Theme.ink)
          .lineLimit(1)
        Text(template.subtitle)
          .font(.caption2)
          .foregroundStyle(Theme.mutedInk)
          .lineLimit(2, reservesSpace: true)
      }
      .frame(width: width, alignment: .leading)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(template.title). \(template.subtitle)")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  /// The original line art, now the loading skeleton.
  private var preview: some View {
    ZStack(alignment: .topLeading) {
      Color.white
      templateDecoration

      VStack(alignment: isCentred ? .center : .leading, spacing: 5) {
        if template != .creative {
          RoundedRectangle(cornerRadius: 2)
            .fill(hasDarkLetterhead ? Color.white : Color(red: 0.10, green: 0.12, blue: 0.17))
            .frame(width: 68, height: 7)
        }
        RoundedRectangle(cornerRadius: 2)
          .fill(hasDarkLetterhead ? accent.color : accent.color.opacity(0.85))
          .frame(width: 48, height: 3)

        Spacer().frame(height: template == .minimal ? 18 : 10)

        ForEach(0..<7, id: \.self) { index in
          RoundedRectangle(cornerRadius: 1)
            .fill(Color.black.opacity(index == 0 ? 0.48 : 0.18))
            .frame(width: index == 0 ? 72 : width - (index.isMultiple(of: 3) ? 62 : 38), height: index == 0 ? 4 : 2.5)
        }
      }
      .padding(.leading, bodyInset)
      .padding(.trailing, 18)
      .padding(.top, headerInset)
      .frame(maxWidth: .infinity, alignment: isCentred ? .center : .leading)
    }
  }

  /// The letterheads whose name sits on a dark ground, and so is set in white.
  private var hasDarkLetterhead: Bool {
    [.executive, .gradient, .noir, .nova, .nocturne, .vantage, .zenith, .spectrum, .volta,
     .obsidian, .verge, .citadel, .sable, .terminal, .passport, .constellation].contains(template)
  }

  private var isCentred: Bool {
    [.classic, .letterpress, .ivy, .laureate, .aurelia, .nocturne, .sovereign, .halo, .pinnacle,
     .circlet, .signet].contains(template)
  }

  private var headerInset: CGFloat {
    switch template {
    case .executive, .gradient: 22
    case .monogram, .memo, .portfolio, .letterpress, .cardstock, .iconic, .eclipse: 26
    default: 20
    }
  }

  /// Sidebar Letterhead's band takes the left of the page, so the letter itself
  /// starts further in.
  private var bodyInset: CGFloat {
    switch template {
    case .sidebar: 52
    case .rail: 30
    default: 18
    }
  }

  @ViewBuilder
  private var templateDecoration: some View {
    switch template {
    case .modern:
      VStack(spacing: 0) {
        Spacer().frame(height: 54)
        accent.color.frame(height: 3)
      }
    case .classic:
      VStack {
        Spacer().frame(height: 58)
        accent.color.opacity(0.8).frame(width: 50, height: 1)
      }
      .frame(maxWidth: .infinity)
    case .minimal:
      Rectangle().fill(Color.black.opacity(0.12)).frame(height: 1).padding(.horizontal, 18).padding(.top, 52)
    case .executive:
      Color(red: 0.10, green: 0.12, blue: 0.17).frame(height: 58)
    case .creative:
      HStack(spacing: 0) {
        accent.color.frame(width: 46, height: 62)
        accent.color.opacity(0.12).frame(height: 62)
      }
    case .signature:
      ZStack(alignment: .topLeading) {
        Rectangle().fill(accent.color).frame(width: 5, height: 55).padding(.leading, 11)
        Circle().fill(accent.color.opacity(0.12)).frame(width: 46, height: 46)
          .frame(maxWidth: .infinity, alignment: .trailing)
          .padding(.trailing, 7)
        Rectangle().fill(Color.black.opacity(0.70)).frame(height: 1)
          .padding(.horizontal, 18)
          .padding(.top, 58)
      }
    case .gradient:
      LinearGradient(
        colors: [accent.color, Color(red: 0.10, green: 0.12, blue: 0.17)],
        startPoint: .leading,
        endPoint: .trailing
      )
      .frame(height: 60)
    case .monogram:
      ZStack(alignment: .topLeading) {
        Rectangle().fill(accent.color).frame(width: 30, height: 30)
          .padding(.leading, 18)
          .padding(.top, 20)
        Rectangle().fill(Color.black.opacity(0.12)).frame(height: 1)
          .padding(.horizontal, 18)
          .padding(.top, 58)
      }
    case .memo:
      ZStack(alignment: .topLeading) {
        Rectangle().fill(Color.black.opacity(0.04)).frame(height: 46)
          .padding(.horizontal, 14)
          .padding(.top, 18)
        Rectangle().fill(accent.color).frame(width: 4, height: 46)
          .padding(.leading, 14)
          .padding(.top, 18)
      }
    case .portfolio:
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(accent.color.opacity(0.10))
        .frame(height: 56)
        .overlay(alignment: .leading) { accent.color.frame(width: 5) }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 16)
    case .letterpress:
      VStack(spacing: 0) {
        Spacer().frame(height: 18)
        Rectangle().fill(Color.black.opacity(0.75)).frame(height: 1.5)
        Spacer().frame(height: 42)
        Rectangle().fill(Color.black.opacity(0.75)).frame(height: 1.5)
      }
      .padding(.horizontal, 16)
    case .sidebar:
      HStack(spacing: 0) {
        Color(red: 0.10, green: 0.12, blue: 0.17).frame(width: 44)
        Spacer()
      }
    case .iconic:
      VStack(spacing: 0) {
        Color.black.opacity(0.05).frame(height: 52)
          .overlay(alignment: .bottom) { accent.color.frame(height: 3) }
        Spacer()
      }
    case .rail:
      ZStack(alignment: .topLeading) {
        Rectangle().fill(accent.color.opacity(0.35)).frame(width: 1.5, height: 46)
          .padding(.leading, 14)
          .padding(.top, 18)
        Circle().fill(accent.color).frame(width: 7, height: 7)
          .padding(.leading, 11)
          .padding(.top, 22)
      }
    case .cardstock:
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(accent.color.opacity(0.07))
        .frame(height: 52)
        .overlay {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(accent.color.opacity(0.3), lineWidth: 0.8)
        }
        .padding(.horizontal, 10)
        .padding(.top, 16)
    case .broadsheet:
      VStack(spacing: 2) {
        Spacer().frame(height: 54)
        Rectangle().fill(Color.black.opacity(0.7)).frame(height: 1.2)
        Rectangle().fill(Color.black.opacity(0.3)).frame(height: 0.5)
      }
      .padding(.horizontal, 18)
    case .noir:
      ZStack(alignment: .topLeading) {
        Color(red: 0.08, green: 0.09, blue: 0.11)
        Rectangle().fill(accent.color).frame(width: 5, height: 64)
          .padding(.leading, 15)
          .padding(.top, 16)
      }
    case .marquee:
      ZStack(alignment: .topLeading) {
        Text(verbatim: "Aa")
          .font(.system(size: 35, weight: .black, design: .rounded))
          .foregroundStyle(Color.black.opacity(0.08))
          .padding(.leading, 13)
          .padding(.top, 9)
        Rectangle().fill(accent.color).frame(width: 58, height: 4)
          .padding(.leading, 18)
          .padding(.top, 58)
      }
    case .crest:
      ZStack(alignment: .topLeading) {
        Color(red: 0.10, green: 0.14, blue: 0.25).frame(height: 64)
        RoundedRectangle(cornerRadius: 3, style: .continuous)
          .fill(accent.color)
          .frame(width: 25, height: 30)
          .padding(.leading, 18)
          .padding(.top, 17)
      }
    case .ivy:
      VStack(spacing: 3) {
        Spacer().frame(height: 17)
        Rectangle().fill(Color.black.opacity(0.75)).frame(height: 1.3)
        Spacer().frame(height: 38)
        Rectangle().fill(Color.black.opacity(0.3)).frame(height: 0.7)
      }
      .padding(.horizontal, 18)
    case .plinth:
      ZStack(alignment: .bottom) {
        Rectangle().fill(Color.black.opacity(0.10)).frame(height: 1)
          .padding(.horizontal, 18)
          .padding(.bottom, 57)
        accent.color.frame(height: 16)
      }
    case .stockholm:
      VStack(spacing: 0) {
        accent.color.opacity(0.08).frame(height: 54)
        accent.color.frame(height: 2)
        Spacer()
      }
    case .laureate:
      VStack(spacing: 0) {
        Spacer().frame(height: 56)
        accent.color.frame(width: 34, height: 2)
      }
      .frame(maxWidth: .infinity)
    case .nova:
      VStack(spacing: 0) {
        accent.color.frame(height: 54)
        Color(red: 0.17, green: 0.20, blue: 0.29).frame(height: 3)
        Spacer()
      }
    case .aurelia:
      VStack(spacing: 0) {
        Spacer().frame(height: 55)
        HStack(spacing: 4) {
          Rectangle().fill(Color.black.opacity(0.2)).frame(height: 0.6)
          OrnamentDiamond().fill(accent.color).frame(width: 6, height: 6)
          Rectangle().fill(Color.black.opacity(0.2)).frame(height: 0.6)
        }
        .padding(.horizontal, 16)
      }
    case .nocturne:
      ZStack(alignment: .top) {
        Color(red: 0.08, green: 0.09, blue: 0.11)
        VStack(spacing: 2) {
          Spacer().frame(height: 52)
          Rectangle().fill(.white.opacity(0.8)).frame(height: 1)
          Rectangle().fill(.white.opacity(0.35)).frame(height: 0.5)
        }
        .padding(.horizontal, 16)
      }
    case .eclipse:
      ZStack(alignment: .topTrailing) {
        Circle()
          .fill(accent.color.opacity(0.12))
          .frame(width: 94, height: 94)
          .offset(x: 28, y: -34)
        Circle()
          .fill(accent.color)
          .frame(width: 76, height: 76)
          .overlay {
            Circle()
              .fill(.white.opacity(0.18))
              .overlay { Circle().strokeBorder(.white, lineWidth: 1.5) }
              .frame(width: 28, height: 28)
              .offset(x: -18, y: 19)
          }
          .offset(x: 22, y: -29)
        Rectangle().fill(Color.black.opacity(0.16)).frame(height: 0.7)
          .padding(.horizontal, 18)
          .padding(.top, 62)
        Rectangle().fill(accent.color).frame(width: 30, height: 2.5)
          .padding(.trailing, width - 48)
          .padding(.top, 61)
      }
    case .vantage:
      ZStack(alignment: .topTrailing) {
        LinearGradient(
          colors: [Color(red: 0.09, green: 0.10, blue: 0.13), Color(red: 0.17, green: 0.20, blue: 0.29)],
          startPoint: .leading,
          endPoint: .trailing
        )
        .frame(height: 78)
        Circle()
          .fill(accent.color.opacity(0.18))
          .frame(width: 96, height: 96)
          .offset(x: 25, y: -38)
        accent.color.frame(height: 3).padding(.top, 78)
      }
    case .zenith, .aperture, .sovereign, .blueprint, .spectrum, .halo, .volta, .obsidian, .radiant,
      .verge, .datum, .pinnacle, .emblem, .cadence, .citadel, .stratus, .mirage,
      .salute, .couture, .medallion, .sable, .terracotta, .lozenge, .circlet, .vogue, .signet,
      .almanac, .kintsugi, .bauhaus, .terminal, .topograph, .passport, .transit, .cutline,
      .receipt, .constellation, .studioFolio:
      if let ordinal = template.advancedOrdinal {
        AdvancedLetterDecoration(ordinal: ordinal, accent: accent.color)
      }
    }
  }
}

private struct AdvancedLetterDecoration: View {
  let ordinal: Int
  let accent: Color

  @ViewBuilder var body: some View {
    switch ordinal {
    case 0:
      LinearGradient(
        colors: [Color(red: 0.09, green: 0.10, blue: 0.12), Color(red: 0.17, green: 0.20, blue: 0.29)],
        startPoint: .leading,
        endPoint: .trailing
      )
      .frame(height: 78)
      .overlay(alignment: .topTrailing) {
        Circle().fill(accent.opacity(0.2)).frame(width: 94, height: 94).offset(x: 24, y: -36)
      }
      .overlay(alignment: .bottom) { accent.frame(height: 3) }
    case 1:
      accent.opacity(0.06).frame(height: 76)
        .overlay(alignment: .topTrailing) {
          ZStack {
            Circle().stroke(accent.opacity(0.35), lineWidth: 1).frame(width: 70, height: 70)
            Circle().stroke(accent, lineWidth: 2).frame(width: 46, height: 46)
            Circle().fill(accent).frame(width: 28, height: 28)
          }
          .offset(x: 17, y: -10)
        }
    case 2:
      Color(red: 0.988, green: 0.98, blue: 0.958).frame(height: 78)
        .overlay { Rectangle().stroke(Color.black.opacity(0.55), lineWidth: 0.8).padding(7) }
        .overlay { Rectangle().stroke(Color.black.opacity(0.22), lineWidth: 0.5).padding(10) }
    case 3:
      Color.blue.opacity(0.035).frame(height: 76)
        .overlay {
          VStack(spacing: 7) {
            ForEach(0..<10, id: \.self) { _ in
              Rectangle().fill(accent.opacity(0.12)).frame(height: 0.5)
            }
          }
        }
        .overlay { Rectangle().stroke(accent.opacity(0.55), lineWidth: 1).padding(8) }
    case 4:
      LinearGradient(colors: [accent, Color(red: 0.17, green: 0.20, blue: 0.29)], startPoint: .leading, endPoint: .trailing)
        .frame(height: 80)
        .overlay {
          HStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { index in
              Color.white.opacity(0.05 + Double(index) * 0.04)
            }
          }
        }
    case 5:
      accent.opacity(0.05).frame(height: 82)
        .overlay {
          ZStack {
            Circle().stroke(accent.opacity(0.25), lineWidth: 1).frame(width: 74, height: 74)
            Circle().stroke(accent.opacity(0.5), lineWidth: 1).frame(width: 54, height: 54)
            Circle().fill(accent).frame(width: 34, height: 34)
          }
          .offset(y: -7)
        }
    case 6:
      Color(red: 0.09, green: 0.10, blue: 0.12).frame(height: 80)
        .overlay(alignment: .leading) { accent.frame(width: 12) }
        .overlay(alignment: .trailing) {
          ZStack {
            Rectangle().fill(accent).frame(width: 22, height: 112).rotationEffect(.degrees(35))
            Rectangle().fill(accent.opacity(0.55)).frame(width: 8, height: 112).rotationEffect(.degrees(35)).offset(x: -24)
          }
          .offset(x: -18, y: -20)
        }
    case 7: // Obsidian — layered glass panels
      Color(red: 0.10, green: 0.10, blue: 0.11).frame(height: 80)
        .overlay(alignment: .topTrailing) {
          ZStack {
            ForEach(0..<3, id: \.self) { index in
              RoundedRectangle(cornerRadius: 6)
                .fill((index == 1 ? accent : Color(red: 0.17, green: 0.20, blue: 0.29)).opacity(0.9 - Double(index) * 0.24))
                .frame(width: 84, height: 50)
                .offset(x: CGFloat(-index * 11) + 16, y: CGFloat(index * 9) - 16)
            }
          }
        }
        .overlay(alignment: .bottom) { accent.frame(height: 3) }
    case 8: // Radiant — soft halo
      accent.opacity(0.06).frame(height: 78)
        .overlay(alignment: .leading) {
          Circle().fill(accent.opacity(0.22)).frame(width: 116, height: 116)
            .blur(radius: 20).offset(x: 4)
        }
        .overlay(alignment: .bottom) { accent.frame(height: 3) }
    case 9: // Verge — duotone split
      Color(red: 0.17, green: 0.20, blue: 0.29).frame(height: 80)
        .overlay(alignment: .trailing) {
          Triangle().fill(accent).frame(width: 104).rotationEffect(.degrees(180))
        }
    case 10: // Datum — metric tiles
      Color(white: 0.98).frame(height: 78)
        .overlay(alignment: .topTrailing) {
          HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { _ in
              RoundedRectangle(cornerRadius: 3).fill(accent.opacity(0.12))
                .overlay(alignment: .topLeading) { Capsule().fill(accent).frame(width: 12, height: 3).padding(4) }
                .frame(width: 26, height: 22)
            }
          }
          .padding(9)
        }
    case 11: // Pinnacle — architected frame
      Color(red: 0.99, green: 0.985, blue: 0.965).frame(height: 80)
        .overlay { Rectangle().stroke(Color(red: 0.17, green: 0.20, blue: 0.29).opacity(0.7), lineWidth: 1).padding(7) }
        .overlay(alignment: .top) { Trapezoid().fill(accent).frame(width: 32, height: 16) }
    case 12: // Emblem — hexagon monogram
      Color(white: 0.985).frame(height: 78)
        .overlay(alignment: .leading) { accent.frame(width: 5) }
        .overlay(alignment: .trailing) {
          OrbitHexagon().stroke(accent.opacity(0.6), lineWidth: 1.4).frame(width: 50, height: 50).padding(.trailing, 14)
        }
    case 13: // Cadence — equaliser
      accent.opacity(0.05).frame(height: 78)
        .overlay(alignment: .bottomTrailing) {
          HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<10, id: \.self) { index in
              accent.opacity(index.isMultiple(of: 2) ? 0.72 : 0.34).frame(width: 4, height: 8 + CGFloat((index * 9) % 28))
            }
          }
          .padding(8)
        }
    case 14: // Citadel — navy banner and frame
      Color(red: 0.17, green: 0.20, blue: 0.29).frame(height: 80)
        .overlay { Rectangle().stroke(.white.opacity(0.35), lineWidth: 0.8).padding(7) }
        .overlay(alignment: .bottom) { accent.frame(height: 3) }
    case 15: // Stratus — gradient bands
      LinearGradient(colors: [accent.opacity(0.22), accent.opacity(0.04)], startPoint: .top, endPoint: .bottom)
        .frame(height: 78)
        .overlay(alignment: .bottom) { accent.frame(height: 3) }
    case 27: // Kintsugi
      Color(red: 0.982, green: 0.963, blue: 0.918).frame(height: 78)
        .overlay(alignment: .trailing) {
          StudioLetterCrack().stroke(Color(red: 0.72, green: 0.52, blue: 0.20), lineWidth: 2)
            .frame(width: 72)
        }
    case 28: // Bauhaus
      Color(red: 0.97, green: 0.95, blue: 0.90).frame(height: 80)
        .overlay(alignment: .leading) { Color(red: 0.17, green: 0.20, blue: 0.29).frame(width: 20) }
        .overlay(alignment: .topTrailing) { Circle().fill(accent).frame(width: 78, height: 78).offset(x: 18, y: -24) }
    case 29: // Terminal
      Color(red: 0.055, green: 0.067, blue: 0.075).frame(height: 80)
        .overlay(alignment: .topLeading) {
          Text("> compose --letter").font(.system(size: 5, design: .monospaced)).foregroundStyle(accent).padding(8)
        }
    case 30: // Topograph
      Color(red: 0.965, green: 0.972, blue: 0.947).frame(height: 80)
        .overlay(alignment: .topTrailing) {
          ZStack {
            ForEach(0..<5, id: \.self) { index in
              Ellipse().stroke(accent.opacity(0.24), lineWidth: 0.7)
                .frame(width: 54 + CGFloat(index * 10), height: 38 + CGFloat(index * 8))
            }
          }.offset(x: 14, y: -9)
        }
    case 31: // Passport
      Color(red: 0.12, green: 0.27, blue: 0.24).frame(height: 80)
        .overlay { RoundedRectangle(cornerRadius: 3).stroke(.white.opacity(0.30), lineWidth: 0.7).padding(6) }
        .overlay(alignment: .leading) { Circle().fill(accent).frame(width: 34, height: 34).padding(.leading, 12) }
    case 32: // Transit
      Color(white: 0.985).frame(height: 80)
        .overlay { StudioLetterTransit().stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)).padding(8) }
    case 33: // Cutline
      Color(white: 0.975).frame(height: 80)
        .overlay(alignment: .trailing) { Triangle().fill(Color(red: 0.17, green: 0.20, blue: 0.29)).frame(width: 96).rotationEffect(.degrees(180)) }
    case 34: // Receipt
      Color(white: 0.985).frame(height: 80)
        .overlay {
          VStack(spacing: 18) {
            Rectangle().stroke(accent.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(height: 1)
            Rectangle().stroke(accent.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(height: 1)
          }.padding(.horizontal, 9)
        }
    case 35: // Constellation
      Color(red: 0.055, green: 0.067, blue: 0.105).frame(height: 80)
        .overlay { StudioLetterConstellation().stroke(accent.opacity(0.55), lineWidth: 0.8).padding(7) }
    case 36: // Studio Folio
      Color(white: 0.985).frame(height: 80)
        .overlay { Rectangle().stroke(Color.black.opacity(0.42), lineWidth: 0.8).padding(7) }
        .overlay(alignment: .bottom) { accent.frame(width: 42, height: 2).padding(.bottom, 10) }
    default: // Mirage — shimmering gradient
      LinearGradient(colors: [accent.opacity(0.30), accent.opacity(0.02)], startPoint: .leading, endPoint: .trailing)
        .frame(height: 78)
        .overlay(alignment: .bottom) { accent.frame(height: 3) }
    }
  }
}

/// The stationer's diamond Aurelia sets at the seam of its ornament rule.
private struct OrnamentDiamond: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.midX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
    path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
    path.closeSubpath()
    return path
  }
}

/// Verge's duotone wedge.
private struct Triangle: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.closeSubpath()
    return path
  }
}

/// Emblem's monogram mark.
private struct OrbitHexagon: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let centre = CGPoint(x: rect.midX, y: rect.midY)
    let radius = min(rect.width, rect.height) / 2
    for corner in 0..<6 {
      let angle = CGFloat.pi / 3 * CGFloat(corner) - CGFloat.pi / 2
      let point = CGPoint(
        x: centre.x + radius * cos(angle), y: centre.y + radius * sin(angle))
      if corner == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
  }
}

/// Pinnacle's keystone.
private struct Trapezoid: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let inset = rect.width * 0.22
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
    path.closeSubpath()
    return path
  }
}

private struct StudioLetterCrack: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.midX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.midX - 8, y: rect.height * 0.28))
    path.addLine(to: CGPoint(x: rect.midX + 10, y: rect.height * 0.48))
    path.addLine(to: CGPoint(x: rect.midX - 5, y: rect.height * 0.70))
    path.addLine(to: CGPoint(x: rect.midX + 12, y: rect.maxY))
    return path
  }
}

private struct StudioLetterTransit: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.height * 0.34))
    path.addLine(to: CGPoint(x: rect.width * 0.38, y: rect.height * 0.34))
    path.addCurve(
      to: CGPoint(x: rect.width * 0.56, y: rect.height * 0.68),
      control1: CGPoint(x: rect.width * 0.50, y: rect.height * 0.34),
      control2: CGPoint(x: rect.width * 0.44, y: rect.height * 0.68))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.68))
    return path
  }
}

private struct StudioLetterConstellation: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let points = [
      CGPoint(x: rect.minX, y: rect.height * 0.28),
      CGPoint(x: rect.width * 0.24, y: rect.height * 0.55),
      CGPoint(x: rect.width * 0.47, y: rect.height * 0.22),
      CGPoint(x: rect.width * 0.69, y: rect.height * 0.64),
      CGPoint(x: rect.maxX, y: rect.height * 0.34),
    ]
    path.move(to: points[0])
    for point in points.dropFirst() { path.addLine(to: point) }
    return path
  }
}


/// Identity of a thumbnail, so the render re-runs when the style or accent changes.
private struct CoverLetterKey: Hashable {
  let template: CoverLetterTemplate
  let accent: ResumeAccent
  let isTabActive: Bool
}
