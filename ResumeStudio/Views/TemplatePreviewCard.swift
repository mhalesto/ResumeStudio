import SwiftUI

/// A miniature of a résumé template.
///
/// The thumbnail is a real render of the exported PDF — actual names, roles and
/// section headings — so you can tell the templates apart at a glance. The
/// original hand-drawn line art is still here, now serving as the skeleton shown
/// while that render is in flight.
struct TemplatePreviewCard: View {
  @Environment(\.appTabIsActive) private var appTabIsActive

  let template: ResumeTemplate
  let accent: ResumeAccent
  let isSelected: Bool

  /// The portrait and its framing, so the photo templates preview the real face
  /// exactly as it will be cropped in the PDF.
  var photo: Data?
  var photoCrop: PhotoCrop?
  var isPhotoVisible = true
  var width: CGFloat = 170

  /// A4 proportions. The card has to be page-shaped or the render gets cropped,
  /// and the first thing to go is the header — the very thing that distinguishes
  /// one template from another.
  private var height: CGFloat { width * 842 / 595 }

  @State private var thumbnail: UIImage?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ZStack {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(.white)

        if let thumbnail {
          Image(uiImage: thumbnail)
            .resizable()
            .scaledToFit()
            .transition(.opacity)
        } else {
          templateArtwork
            .padding(10)
        }
      }
      .frame(width: width, height: height)
      .task(id: TemplateKey(
        template: template, accent: accent, photo: photo, crop: photoCrop,
        isPhotoVisible: isPhotoVisible, isTabActive: appTabIsActive
      )) {
        guard appTabIsActive else { return }
        // Already rendered this session: show it instantly, no skeleton flash.
        if let ready = TemplateThumbnailRenderer.cached(
          template: template, accent: accent, photo: photo, crop: photoCrop,
          isPhotoVisible: isPhotoVisible
        ) {
          thumbnail = ready
          return
        }
        // Accent taps can arrive in quick succession. Let the selection paint
        // first and cancel superseded work instead of synchronously exporting a
        // full PDF for every colour the user's finger passes through.
        try? await Task.sleep(for: .milliseconds(220))
        guard !Task.isCancelled else { return }
        // Otherwise load from disk or render (off the main thread where possible,
        // serialised so a screenful of cards can't freeze the frame together).
        let image = await TemplateThumbnailRenderer.image(
          template: template, accent: accent, photo: photo, crop: photoCrop,
          isPhotoVisible: isPhotoVisible
        )
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.25)) { thumbnail = image }
      }
      // Some artwork (Contemporary Split's sidebar) is intrinsically wider than
      // the card and would otherwise bleed over its neighbour.
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .strokeBorder(
            isSelected ? accent.color : Theme.hairline,
            lineWidth: isSelected ? 3 : 1
          )
      }
      .overlay(alignment: .topTrailing) {
        if isSelected {
          ZStack {
            Circle().fill(accent.color)
            Image(systemName: "checkmark")
              .font(.system(size: 12, weight: .bold))
              .foregroundStyle(.white)
          }
          .frame(width: 26, height: 26)
          // Keep the complete badge inside the thumbnail. Horizontal carousels
          // clip content outside their viewport, which cut the top of the tick.
          .padding(7)
        }
      }
      .shadow(color: Theme.ink.opacity(0.10), radius: 10, y: 6)

      VStack(alignment: .leading, spacing: 3) {
        Text(template.title)
          .font(.subheadline.weight(.bold))
          .foregroundStyle(Theme.ink)
        Text(template.subtitle)
          .font(.caption2)
          .foregroundStyle(Theme.mutedInk)
          // Always reserve both lines: without it, one-line subtitles make their
          // card shorter and the row of thumbnails ends up staggered.
          .lineLimit(2, reservesSpace: true)
      }
      .frame(width: width, alignment: .leading)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(template.title). \(template.subtitle)")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  @ViewBuilder
  private var templateArtwork: some View {
    switch template {
    case .atlas:
      SidebarSkeleton(
        accent: accent.color,
        side: .leading,
        fill: Color(red: 0.17, green: 0.20, blue: 0.29),
        ink: .white,
        photo: true
      )
    case .verso:
      SidebarSkeleton(
        accent: accent.color,
        side: .trailing,
        fill: Color.black.opacity(0.06),
        ink: Color.black.opacity(0.55),
        photo: true
      )
    case .oxford:
      SidebarSkeleton(
        accent: accent.color,
        side: .leading,
        fill: accent.color,
        ink: .white,
        photo: true
      )
    case .chronicle:
      VStack(alignment: .leading, spacing: 8) {
        Capsule().fill(Color.black.opacity(0.78)).frame(width: 84, height: 8)
        HStack(spacing: 4) {
          Image(systemName: "phone.fill").font(.system(size: 5)).foregroundStyle(accent.color)
          Capsule().fill(Color.black.opacity(0.2)).frame(width: 32, height: 3)
          Image(systemName: "envelope.fill").font(.system(size: 5)).foregroundStyle(accent.color)
          Capsule().fill(Color.black.opacity(0.2)).frame(width: 38, height: 3)
        }
        Divider()
        HStack(alignment: .top, spacing: 8) {
          VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in
              Circle().fill(accent.color).frame(width: 7, height: 7)
              Rectangle().fill(accent.color.opacity(0.3)).frame(width: 1.5, height: 38)
            }
          }
          VStack(alignment: .leading, spacing: 9) {
            ForEach(0..<3, id: \.self) { _ in
              VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(Color.black.opacity(0.55)).frame(width: 64, height: 4)
                Capsule().fill(Color.black.opacity(0.15)).frame(height: 3)
                Capsule().fill(Color.black.opacity(0.15)).frame(width: 90, height: 3)
              }
            }
          }
        }
      }
      .padding(.horizontal, 4)
      .padding(.top, 4)
    case .gazette:
      VStack(alignment: .leading, spacing: 8) {
        Capsule().fill(Color.black.opacity(0.78)).frame(width: 88, height: 8)
        VStack(spacing: 2) {
          Rectangle().fill(Color.black.opacity(0.7)).frame(height: 1.2)
          Rectangle().fill(Color.black.opacity(0.3)).frame(height: 0.5)
        }
        ForEach(0..<4, id: \.self) { _ in
          HStack(alignment: .top, spacing: 8) {
            Capsule().fill(accent.color).frame(width: 26, height: 3)
            VStack(alignment: .leading, spacing: 4) {
              Capsule().fill(Color.black.opacity(0.55)).frame(width: 58, height: 4)
              Capsule().fill(Color.black.opacity(0.15)).frame(height: 3)
            }
          }
        }
      }
      .padding(.horizontal, 4)
      .padding(.top, 4)
    case .strata:
      VStack(alignment: .leading, spacing: 7) {
        Capsule().fill(Color.black.opacity(0.78)).frame(width: 80, height: 8)
        ForEach(0..<3, id: \.self) { _ in
          RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(accent.color.opacity(0.06))
            .frame(height: 40)
            .overlay {
              RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(accent.color.opacity(0.3), lineWidth: 0.8)
            }
            .overlay(alignment: .topLeading) {
              VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(Color.black.opacity(0.55)).frame(width: 52, height: 4)
                Capsule().fill(Color.black.opacity(0.15)).frame(width: 92, height: 3)
                Capsule().fill(Color.black.opacity(0.15)).frame(width: 74, height: 3)
              }
              .padding(7)
            }
        }
      }
      .padding(.horizontal, 4)
      .padding(.top, 4)
    case .duo, .concise:
      VStack(alignment: .leading, spacing: 8) {
        Capsule().fill(Color.black.opacity(0.78)).frame(width: 82, height: 8)
        Rectangle().fill(accent.color).frame(height: 2.5)
        VStack(alignment: .leading, spacing: 3) {
          Capsule().fill(Color.black.opacity(0.15)).frame(height: 3)
          Capsule().fill(Color.black.opacity(0.15)).frame(height: 3)
        }
        HStack(alignment: .top, spacing: 10) {
          VStack(alignment: .leading, spacing: 7) {
            ForEach(0..<3, id: \.self) { _ in
              VStack(alignment: .leading, spacing: 3) {
                Capsule().fill(accent.color).frame(width: 40, height: 3)
                Capsule().fill(Color.black.opacity(0.15)).frame(height: 3)
                Capsule().fill(Color.black.opacity(0.15)).frame(width: 60, height: 3)
              }
            }
          }
          VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<4, id: \.self) { index in
              Capsule()
                .fill(index.isMultiple(of: 2) ? accent.color.opacity(0.25) : Color.black.opacity(0.1))
                .frame(width: index.isMultiple(of: 2) ? 42 : 34, height: 6)
            }
          }
          .frame(width: 46)
        }
      }
      .padding(.horizontal, 4)
      .padding(.top, 4)
    case .signal:
      VStack(alignment: .leading, spacing: 8) {
        ZStack(alignment: .topLeading) {
          Rectangle().fill(Color.black.opacity(0.05)).frame(height: 42)
            .overlay(alignment: .bottom) { accent.color.frame(height: 3) }
          VStack(alignment: .leading, spacing: 5) {
            Capsule().fill(Color.black.opacity(0.78)).frame(width: 74, height: 8)
            HStack(spacing: 4) {
              Image(systemName: "phone.fill").font(.system(size: 5)).foregroundStyle(accent.color)
              Capsule().fill(Color.black.opacity(0.2)).frame(width: 30, height: 3)
              Image(systemName: "envelope.fill").font(.system(size: 5)).foregroundStyle(accent.color)
              Capsule().fill(Color.black.opacity(0.2)).frame(width: 34, height: 3)
            }
          }
          .padding(7)
        }
        .frame(height: 42)
        VStack(spacing: 6) {
          ForEach(0..<3, id: \.self) { _ in
            HStack(spacing: 6) {
              ForEach(0..<2, id: \.self) { _ in
                HStack(spacing: 4) {
                  Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(accent.color)
                  Capsule().fill(Color.black.opacity(0.15)).frame(height: 3)
                }
              }
            }
          }
        }
        MockResumeLines(accent: accent.color, centered: false)
      }
      .padding(.horizontal, 4)
    case .pivot:
      VStack(alignment: .leading, spacing: 8) {
        Rectangle()
          .fill(Color(red: 0.17, green: 0.20, blue: 0.29))
          .frame(height: 42)
          .overlay(alignment: .top) { accent.color.frame(height: 4) }
          .overlay(alignment: .leading) {
            VStack(alignment: .leading, spacing: 4) {
              Capsule().fill(.white).frame(width: 68, height: 7)
              Capsule().fill(accent.color).frame(width: 44, height: 3)
            }
            .padding(.leading, 8)
          }
        // Skills lead: the pills come before the roles.
        MockChips(accent: accent.color)
        VStack(alignment: .leading, spacing: 6) {
          ForEach(0..<2, id: \.self) { _ in
            VStack(alignment: .leading, spacing: 3) {
              Capsule().fill(accent.color).frame(width: 46, height: 3)
              Capsule().fill(Color.black.opacity(0.15)).frame(height: 3)
              Capsule().fill(Color.black.opacity(0.15)).frame(width: 96, height: 3)
            }
          }
        }
      }
    case .portrait:
      VStack(spacing: 8) {
        RoundedRectangle(cornerRadius: 3)
          .fill(Color(red: 0.17, green: 0.20, blue: 0.29))
          .frame(height: 48)
          .overlay(alignment: .leading) {
            HStack(spacing: 8) {
              Circle()
                .fill(accent.color.opacity(0.3))
                .frame(width: 28, height: 28)
                .overlay { Circle().stroke(accent.color, lineWidth: 2) }
              VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(.white).frame(width: 58, height: 6)
                Capsule().fill(accent.color).frame(width: 40, height: 3)
              }
            }
            .padding(.leading, 8)
          }
        MockResumeLines(accent: accent.color, centered: false)
      }
    case .spotlight:
      VStack(spacing: 7) {
        Circle()
          .fill(accent.color.opacity(0.18))
          .frame(width: 34, height: 34)
          .overlay { Circle().stroke(accent.color, lineWidth: 2) }
        Capsule().fill(Color.black.opacity(0.76)).frame(width: 84, height: 7)
        Capsule().fill(accent.color).frame(width: 50, height: 3)
        MockResumeLines(accent: accent.color, centered: true)
      }
      .padding(.top, 4)
    case .atelier:
      VStack(spacing: 12) {
        Rectangle()
          .fill(accent.color)
          .frame(height: 44)
          .overlay(alignment: .bottomTrailing) {
            Circle()
              .fill(Color(red: 0.17, green: 0.20, blue: 0.29))
              .frame(width: 30, height: 30)
              .overlay { Circle().stroke(.white, lineWidth: 2.5) }
              .offset(x: -4, y: 15)
          }
          .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 4) {
              Capsule().fill(.white).frame(width: 66, height: 7)
              Capsule().fill(.white.opacity(0.75)).frame(width: 44, height: 3)
            }
            .padding([.top, .leading], 8)
          }
        MockResumeLines(accent: accent.color, centered: false)
          .padding(.top, 4)
      }
    case .canvas:
      VStack(spacing: 9) {
        ZStack(alignment: .leading) {
          HStack(spacing: 0) {
            Rectangle().fill(accent.color).frame(width: 58)
            Rectangle().fill(Color.black.opacity(0.05))
          }
          .frame(height: 46)
          Circle()
            .fill(Color(red: 0.17, green: 0.20, blue: 0.29))
            .frame(width: 28, height: 28)
            .overlay { Circle().stroke(.white, lineWidth: 2.5) }
            .offset(x: 44)
          VStack(alignment: .leading, spacing: 4) {
            Capsule().fill(Color.black.opacity(0.75)).frame(width: 52, height: 6)
            Capsule().fill(accent.color).frame(width: 34, height: 3)
          }
          .offset(x: 80)
        }
        .frame(height: 46)
        MockResumeLines(accent: accent.color, centered: false)
      }
    case .modern:
      VStack(spacing: 8) {
        RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.17, green: 0.20, blue: 0.29)).frame(
          height: 43
        )
        .overlay(alignment: .leading) {
          VStack(alignment: .leading, spacing: 4) {
            Capsule().fill(accent.color).frame(width: 62, height: 7)
            Capsule().fill(.white.opacity(0.8)).frame(width: 88, height: 4)
          }
          .padding(.leading, 10)
        }
        MockResumeLines(accent: accent.color, centered: false)
      }
    case .classic:
      VStack(spacing: 9) {
        Capsule().fill(Color.black.opacity(0.75)).frame(width: 88, height: 8)
        Capsule().fill(accent.color).frame(width: 44, height: 2)
        MockResumeLines(accent: accent.color, centered: true)
      }
      .padding(.top, 7)
    case .minimal:
      HStack(spacing: 9) {
        Rectangle().fill(accent.color).frame(width: 5)
        VStack(alignment: .leading, spacing: 9) {
          Capsule().fill(Color.black.opacity(0.78)).frame(width: 88, height: 8)
          Capsule().fill(accent.color).frame(width: 58, height: 4)
          MockResumeLines(accent: accent.color, centered: false)
        }
        .padding(.vertical, 9)
      }
    case .contemporary:
      HStack(spacing: 0) {
        VStack(alignment: .leading, spacing: 7) {
          Capsule().fill(.white).frame(width: 55, height: 7)
          Capsule().fill(accent.color).frame(width: 34, height: 3)
          Spacer()
        }
        .padding(10)
        .frame(width: 68)
        .background(Color(red: 0.17, green: 0.20, blue: 0.29))
        VStack(alignment: .leading, spacing: 9) {
          Capsule().fill(accent.color).frame(width: 62, height: 5)
          MockResumeLines(accent: accent.color, centered: false)
        }
        .padding(10)
      }
    case .corporate:
      VStack(spacing: 7) {
        Rectangle().fill(accent.color).frame(height: 7)
        RoundedRectangle(cornerRadius: 2)
          .fill(Color(red: 0.17, green: 0.20, blue: 0.29))
          .frame(height: 38)
          .overlay(alignment: .leading) {
            Capsule().fill(.white).frame(width: 92, height: 7).padding(.leading, 10)
          }
        MockResumeLines(accent: accent.color, centered: false)
      }
    case .elegant:
      VStack(spacing: 7) {
        HStack {
          Divider()
          Circle().fill(accent.color).frame(width: 5, height: 5)
          Divider()
        }
        Capsule().fill(Color.black.opacity(0.76)).frame(width: 96, height: 8)
        Capsule().fill(Color.black.opacity(0.32)).frame(width: 70, height: 3)
        HStack {
          Divider()
          Circle().fill(accent.color).frame(width: 4, height: 4)
          Divider()
        }
        MockResumeLines(accent: accent.color, centered: true)
      }
      .padding(.top, 5)
    case .nordic:
      VStack(alignment: .leading, spacing: 11) {
        HStack(spacing: 8) {
          Circle().fill(accent.color.opacity(0.16)).frame(width: 31, height: 31)
            .overlay { Circle().fill(accent.color).frame(width: 8, height: 8) }
          VStack(alignment: .leading, spacing: 4) {
            Capsule().fill(Color.black.opacity(0.76)).frame(width: 76, height: 7)
            Capsule().fill(accent.color).frame(width: 48, height: 3)
          }
        }
        MockResumeLines(accent: accent.color, centered: false)
      }
      .padding(5)
    case .creative:
      VStack(spacing: 8) {
        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.17, green: 0.20, blue: 0.29))
          Circle().fill(accent.color).frame(width: 55, height: 55).offset(x: 105, y: -15)
          VStack(alignment: .leading, spacing: 4) {
            Capsule().fill(.white).frame(width: 87, height: 8)
            Capsule().fill(accent.color).frame(width: 55, height: 4)
          }
          .padding(10)
        }
        .frame(height: 50)
        MockResumeLines(accent: accent.color, centered: false)
      }
    case .technical:
      VStack(alignment: .leading, spacing: 7) {
        Rectangle().fill(accent.color).frame(height: 4)
        HStack(spacing: 7) {
          Text(verbatim: "</>").font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(accent.color)
          Capsule().fill(Color.black.opacity(0.75)).frame(width: 82, height: 7)
        }
        Divider()
        MockResumeLines(accent: accent.color, centered: false)
      }
      .padding(5)
    case .compact:
      VStack(alignment: .leading, spacing: 5) {
        HStack {
          Capsule().fill(Color.black.opacity(0.8)).frame(width: 82, height: 8)
          Spacer()
          VStack(spacing: 3) {
            Capsule().fill(accent.color).frame(width: 36, height: 3)
            Capsule().fill(Color.black.opacity(0.2)).frame(width: 36, height: 3)
          }
        }
        Rectangle().fill(accent.color).frame(height: 3)
        MockCompactLines(accent: accent.color)
      }
      .padding(.top, 5)
    case .academic:
      VStack(spacing: 7) {
        Text(verbatim: "CURRICULUM VITAE")
          .font(.system(size: 6, weight: .semibold, design: .serif))
          .foregroundStyle(accent.color)
        Capsule().fill(Color.black.opacity(0.78)).frame(width: 100, height: 8)
        HStack {
          Divider()
          Divider()
        }
        MockResumeLines(accent: accent.color, centered: false)
      }
      .padding(.top, 6)
    case .timeline:
      HStack(alignment: .top, spacing: 10) {
        VStack(spacing: 0) {
          ForEach(0..<4, id: \.self) { _ in
            Circle().fill(accent.color).frame(width: 7, height: 7)
            Rectangle().fill(accent.color.opacity(0.35)).frame(width: 2, height: 35)
          }
        }
        VStack(alignment: .leading, spacing: 10) {
          Capsule().fill(Color.black.opacity(0.78)).frame(width: 88, height: 8)
          MockResumeLines(accent: accent.color, centered: false)
        }
      }
      .padding(5)
    case .monochrome:
      VStack(spacing: 8) {
        Rectangle()
          .stroke(Color.black.opacity(0.78), lineWidth: 2)
          .frame(height: 43)
          .overlay {
            VStack(spacing: 4) {
              Capsule().fill(Color.black.opacity(0.82)).frame(width: 96, height: 8)
              Capsule().fill(Color.black.opacity(0.38)).frame(width: 64, height: 3)
            }
          }
        MockResumeLines(accent: .black, centered: false)
      }
    case .editorial:
      HStack(alignment: .top, spacing: 10) {
        Rectangle().fill(accent.color).frame(width: 5)
        VStack(alignment: .leading, spacing: 8) {
          Text(verbatim: "EDITORIAL PROFILE")
            .font(.system(size: 5, weight: .bold, design: .serif))
            .foregroundStyle(accent.color)
          Capsule().fill(Color.black.opacity(0.80)).frame(width: 104, height: 9)
          Capsule().fill(Color.black.opacity(0.30)).frame(width: 72, height: 3)
          Divider()
          MockResumeLines(accent: accent.color, centered: false)
        }
      }
      .padding(.vertical, 5)
    case .noir:
      VStack(alignment: .leading, spacing: 9) {
        HStack(spacing: 7) {
          Rectangle().fill(accent.color).frame(width: 4, height: 29)
          VStack(alignment: .leading, spacing: 4) {
            Capsule().fill(.white).frame(width: 86, height: 8)
            Capsule().fill(accent.color).frame(width: 54, height: 3)
          }
        }
        MockChips(accent: accent.color)
        MockResumeLines(accent: accent.color, centered: false)
      }
      .padding(9)
      .background(Color(red: 0.08, green: 0.09, blue: 0.11))
    case .gauge:
      SidebarSkeleton(
        accent: accent.color,
        side: .trailing,
        fill: Color(red: 0.12, green: 0.15, blue: 0.22),
        ink: .white,
        photo: false
      )
    case .folio:
      VStack(alignment: .leading, spacing: 9) {
        Capsule().fill(Color.black.opacity(0.80)).frame(width: 102, height: 9)
        ForEach(1..<4, id: \.self) { number in
          HStack(alignment: .top, spacing: 7) {
            Text(String(format: "%02d", number))
              .font(.system(size: 9, weight: .black, design: .serif))
              .foregroundStyle(accent.color)
              .frame(width: 18, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
              Capsule().fill(Color.black.opacity(0.55)).frame(width: 60, height: 4)
              Capsule().fill(Color.black.opacity(0.14)).frame(height: 3)
              Capsule().fill(Color.black.opacity(0.14)).frame(width: 82, height: 3)
            }
          }
        }
      }
      .padding(6)
    case .insignia:
      VStack(spacing: 8) {
        HStack(spacing: 9) {
          Circle().fill(accent.color).frame(width: 38, height: 38)
            .overlay {
              Text(verbatim: "RS")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            }
          VStack(alignment: .leading, spacing: 4) {
            Capsule().fill(Color.black.opacity(0.78)).frame(width: 76, height: 8)
            Capsule().fill(accent.color).frame(width: 48, height: 3)
          }
        }
        MockChips(accent: accent.color)
        MockResumeLines(accent: accent.color, centered: false)
      }
      .padding(.top, 4)
    case .marquee:
      VStack(alignment: .leading, spacing: 7) {
        Text(verbatim: "RESUME")
          .font(.system(size: 24, weight: .black, design: .rounded))
          .foregroundStyle(Color.black.opacity(0.82))
          .minimumScaleFactor(0.7)
        Rectangle().fill(accent.color).frame(width: 58, height: 5)
        MockChips(accent: accent.color)
        MockResumeLines(accent: accent.color, centered: false)
      }
      .padding(.horizontal, 4)
    case .metro:
      VStack(alignment: .leading, spacing: 7) {
        HStack(spacing: 3) {
          accent.color.frame(width: 42, height: 34)
          Color(red: 0.12, green: 0.15, blue: 0.23).frame(height: 34)
        }
        ForEach(0..<3, id: \.self) { index in
          RoundedRectangle(cornerRadius: 2)
            .fill(index.isMultiple(of: 2) ? accent.color.opacity(0.11) : Color.black.opacity(0.05))
            .frame(height: 31)
            .overlay(alignment: .leading) {
              Capsule().fill(Color.black.opacity(0.40)).frame(width: 66, height: 4)
                .padding(.leading, 8)
            }
        }
      }
    case .ivy:
      VStack(spacing: 8) {
        Rectangle().fill(Color.black.opacity(0.78)).frame(height: 1.5)
        Text(verbatim: "CURRICULUM VITAE")
          .font(.system(size: 7, weight: .bold, design: .serif))
          .tracking(1.2)
        Capsule().fill(Color.black.opacity(0.75)).frame(width: 96, height: 8)
        Rectangle().fill(Color.black.opacity(0.35)).frame(height: 0.7)
        MockResumeLines(accent: .black, centered: true)
      }
      .padding(7)
    case .crest:
      SidebarSkeleton(
        accent: accent.color,
        side: .leading,
        fill: accent.color.opacity(0.12),
        ink: Color.black.opacity(0.62),
        photo: true
      )
    case .geneva:
      HStack(spacing: 9) {
        VStack(alignment: .leading, spacing: 8) {
          Capsule().fill(Color.black.opacity(0.72)).frame(width: 38, height: 6)
          ForEach(0..<4, id: \.self) { index in
            VStack(alignment: .leading, spacing: 3) {
              Capsule().fill(Color.black.opacity(0.16)).frame(width: 34, height: 3)
              Capsule().fill(accent.color.opacity(0.85)).frame(width: CGFloat(22 + index * 4), height: 3)
            }
          }
          Spacer(minLength: 0)
        }
        .frame(width: 44)
        Divider()
        VStack(alignment: .leading, spacing: 8) {
          Capsule().fill(Color.black.opacity(0.78)).frame(width: 76, height: 8)
          MockResumeLines(accent: accent.color, centered: false)
        }
      }
      .padding(.vertical, 5)
    case .plinth:
      VStack(alignment: .leading, spacing: 8) {
        Capsule().fill(Color.black.opacity(0.78)).frame(width: 92, height: 9)
        Rectangle().fill(accent.color).frame(width: 50, height: 3)
        MockChips(accent: accent.color)
        MockResumeLines(accent: accent.color, centered: false)
        Spacer(minLength: 0)
        accent.color.frame(height: 12)
      }
    case .stockholm:
      VStack(alignment: .leading, spacing: 7) {
        VStack(alignment: .leading, spacing: 4) {
          Capsule().fill(Color.black.opacity(0.78)).frame(width: 84, height: 8)
          Capsule().fill(accent.color).frame(width: 52, height: 3)
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.color.opacity(0.08))
        .overlay(alignment: .bottom) { accent.color.frame(height: 1.5) }
        HStack(alignment: .top, spacing: 8) {
          MockResumeLines(accent: accent.color, centered: false)
          VStack(alignment: .leading, spacing: 5) {
            ForEach(0..<3, id: \.self) { _ in
              Capsule().fill(Color.black.opacity(0.6)).frame(width: 26, height: 3)
              Capsule().fill(accent.color.opacity(0.35)).frame(width: 38, height: 3)
            }
          }
          .frame(width: 42)
        }
        .padding(.horizontal, 5)
      }
    case .tandem:
      HStack(alignment: .top, spacing: 8) {
        VStack(alignment: .leading, spacing: 7) {
          Capsule().fill(Color.black.opacity(0.78)).frame(width: 72, height: 8)
          Capsule().fill(accent.color).frame(width: 44, height: 3)
          HStack(alignment: .top, spacing: 6) {
            VStack(spacing: 0) {
              ForEach(0..<3, id: \.self) { _ in
                Circle().fill(accent.color).frame(width: 6, height: 6)
                Rectangle().fill(accent.color.opacity(0.3)).frame(width: 1.5, height: 30)
              }
            }
            VStack(alignment: .leading, spacing: 8) {
              ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 3) {
                  Capsule().fill(Color.black.opacity(0.5)).frame(width: 48, height: 4)
                  Capsule().fill(Color.black.opacity(0.15)).frame(height: 3)
                }
              }
            }
          }
        }
        .padding(.vertical, 6)
        .padding(.leading, 5)
        VStack(alignment: .leading, spacing: 6) {
          ForEach(0..<4, id: \.self) { _ in
            Capsule().fill(Color.black.opacity(0.35)).frame(width: 30, height: 3)
            Capsule().fill(accent.color.opacity(0.4)).frame(width: 36, height: 3)
          }
          Spacer(minLength: 0)
        }
        .padding(7)
        .frame(width: 50)
        .background(Color.black.opacity(0.06))
      }
    case .varsity:
      VStack(alignment: .leading, spacing: 7) {
        HStack(spacing: 4) {
          Capsule().fill(Color.black.opacity(0.4)).frame(width: 40, height: 8)
          Capsule().fill(Color.black.opacity(0.85)).frame(width: 52, height: 8)
        }
        Rectangle().fill(Color.black.opacity(0.2)).frame(height: 0.7)
        HStack(alignment: .top, spacing: 9) {
          VStack(alignment: .leading, spacing: 5) {
            ForEach(0..<4, id: \.self) { _ in
              Capsule().fill(accent.color.opacity(0.85)).frame(width: 30, height: 3)
              Capsule().fill(Color.black.opacity(0.2)).frame(width: 38, height: 3)
            }
          }
          .frame(width: 42)
          VStack(alignment: .leading, spacing: 7) {
            MockResumeLines(accent: accent.color, centered: false)
          }
        }
      }
      .padding(.horizontal, 4)
      .padding(.top, 4)
    case .laureate:
      VStack(spacing: 8) {
        HStack(spacing: 4) {
          Capsule().fill(Color.black.opacity(0.55)).frame(width: 42, height: 8)
          Capsule().fill(accent.color).frame(width: 48, height: 8)
        }
        Capsule().fill(Color.black.opacity(0.25)).frame(width: 70, height: 3)
        Rectangle().fill(accent.color).frame(width: 30, height: 2)
        MockResumeLines(accent: accent.color, centered: true)
      }
      .padding(.top, 5)
    case .modena:
      VStack(alignment: .leading, spacing: 8) {
        Capsule().fill(Color.black.opacity(0.78)).frame(width: 88, height: 8)
        HStack(spacing: 0) {
          Rectangle().fill(accent.color).frame(width: 34, height: 3)
          Rectangle().fill(Color.black.opacity(0.15)).frame(height: 0.8)
        }
        ForEach(0..<3, id: \.self) { _ in
          HStack(alignment: .top, spacing: 7) {
            Capsule().fill(accent.color.opacity(0.7)).frame(width: 26, height: 3)
              .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
              Capsule().fill(Color.black.opacity(0.55)).frame(width: 56, height: 4)
              Capsule().fill(Color.black.opacity(0.14)).frame(height: 3)
              Capsule().fill(Color.black.opacity(0.14)).frame(width: 78, height: 3)
            }
          }
        }
      }
      .padding(6)
    case .nova:
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .center, spacing: 8) {
          VStack(alignment: .leading, spacing: 4) {
            Capsule().fill(.white).frame(width: 74, height: 8)
            Capsule().fill(.white.opacity(0.7)).frame(width: 48, height: 3)
          }
          Spacer(minLength: 0)
          RoundedRectangle(cornerRadius: 6)
            .fill(.white.opacity(0.25))
            .frame(width: 30, height: 30)
            .overlay { RoundedRectangle(cornerRadius: 6).stroke(.white, lineWidth: 1.5) }
        }
        .padding(8)
        .background(accent.color)
        .overlay(alignment: .bottom) { Color(red: 0.17, green: 0.20, blue: 0.29).frame(height: 2.5) }
        MockChips(accent: accent.color)
          .padding(.horizontal, 4)
        MockResumeLines(accent: accent.color, centered: false)
          .padding(.horizontal, 4)
      }
    case .prism:
      SidebarSkeleton(
        accent: accent.color,
        side: .trailing,
        fill: accent.color,
        ink: .white,
        photo: true
      )
    case .aurelia:
      VStack(spacing: 8) {
        Text(verbatim: "AURELIA")
          .font(.system(size: 12, weight: .semibold, design: .serif))
          .tracking(4)
          .foregroundStyle(Color.black.opacity(0.8))
        Capsule().fill(Color.black.opacity(0.25)).frame(width: 64, height: 3)
        HStack(spacing: 5) {
          Rectangle().fill(Color.black.opacity(0.2)).frame(height: 0.6)
          Diamond().fill(accent.color).frame(width: 7, height: 7)
          Rectangle().fill(Color.black.opacity(0.2)).frame(height: 0.6)
        }
        MockResumeLines(accent: accent.color, centered: true)
      }
      .padding(.horizontal, 6)
      .padding(.top, 6)
    case .nocturne:
      VStack(spacing: 8) {
        Capsule().fill(.white).frame(width: 84, height: 8)
        Capsule().fill(accent.color).frame(width: 52, height: 3)
        VStack(spacing: 2) {
          Rectangle().fill(.white.opacity(0.8)).frame(height: 1)
          Rectangle().fill(.white.opacity(0.35)).frame(height: 0.5)
        }
        VStack(spacing: 7) {
          ForEach(0..<3, id: \.self) { _ in
            HStack(spacing: 5) {
              Rectangle().fill(.white.opacity(0.25)).frame(height: 0.5)
              Diamond().fill(accent.color).frame(width: 6, height: 6)
              Rectangle().fill(.white.opacity(0.25)).frame(height: 0.5)
            }
            Capsule().fill(.white.opacity(0.35)).frame(height: 3)
            Capsule().fill(.white.opacity(0.25)).frame(width: 92, height: 3)
          }
        }
      }
      .padding(9)
      .background(Color(red: 0.08, green: 0.09, blue: 0.11))
    case .monarch:
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .center, spacing: 9) {
          RoundedRectangle(cornerRadius: 5)
            .fill(accent.color)
            .frame(width: 32, height: 32)
            .overlay {
              Text(verbatim: "RS")
                .font(.system(size: 9, weight: .bold, design: .serif))
                .foregroundStyle(.white)
            }
          VStack(alignment: .leading, spacing: 4) {
            Capsule().fill(.white).frame(width: 70, height: 8)
            Capsule().fill(accent.color).frame(width: 44, height: 3)
          }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.17, green: 0.20, blue: 0.29))
        .overlay(alignment: .bottom) { accent.color.frame(height: 2) }
        MockResumeLines(accent: accent.color, centered: false)
          .padding(.horizontal, 5)
      }
    case .horizon:
      VStack(spacing: 9) {
        HStack(spacing: 0) {
          VStack(alignment: .leading, spacing: 5) {
            Capsule().fill(Color.black.opacity(0.76)).frame(width: 82, height: 8)
            Capsule().fill(accent.color).frame(width: 54, height: 3)
          }
          .padding(9)
          .frame(maxWidth: .infinity, alignment: .leading)
          Color(red: 0.17, green: 0.20, blue: 0.29).frame(width: 50)
        }
        .frame(height: 48)
        .overlay(alignment: .bottom) { accent.color.frame(height: 4) }
        MockResumeLines(accent: accent.color, centered: false)
      }
    case .beacon:
      VStack(spacing: 9) {
        HStack(spacing: 10) {
          Circle().fill(accent.color).frame(width: 40, height: 40)
            .overlay { Circle().stroke(accent.color.opacity(0.3), lineWidth: 3) }
          VStack(alignment: .leading, spacing: 5) {
            Capsule().fill(Color.black.opacity(0.78)).frame(width: 70, height: 7)
            Capsule().fill(Color.black.opacity(0.28)).frame(width: 50, height: 3)
            Capsule().fill(accent.color).frame(width: 34, height: 4)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        MockResumeLines(accent: accent.color, centered: false)
      }
    case .harbor:
      VStack(spacing: 7) {
        Rectangle().fill(accent.color).frame(height: 30)
          .overlay(alignment: .bottom) {
            Circle()
              .fill(Color(red: 0.17, green: 0.20, blue: 0.29))
              .frame(width: 34, height: 34)
              .overlay { Circle().stroke(.white, lineWidth: 2.5) }
              .offset(y: 17)
          }
        Spacer().frame(height: 12)
        Capsule().fill(Color.black.opacity(0.76)).frame(width: 82, height: 7)
        Capsule().fill(accent.color).frame(width: 48, height: 3)
        MockResumeLines(accent: accent.color, centered: true)
      }
    case .bloom:
      VStack(spacing: 9) {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(accent.color.opacity(0.10))
          .frame(height: 52)
          .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .strokeBorder(accent.color.opacity(0.3), lineWidth: 1)
          }
          .overlay(alignment: .leading) {
            HStack(spacing: 9) {
              Circle().fill(accent.color.opacity(0.28)).frame(width: 32, height: 32)
                .overlay { Circle().stroke(.white, lineWidth: 2) }
              VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(Color.black.opacity(0.74)).frame(width: 56, height: 6)
                Capsule().fill(accent.color).frame(width: 38, height: 3)
              }
            }
            .padding(.leading, 9)
          }
        MockResumeLines(accent: accent.color, centered: false)
      }
    case .aurora:
      VStack(spacing: 8) {
        LinearGradient(
          colors: [accent.color, Color(red: 0.17, green: 0.20, blue: 0.29)],
          startPoint: .leading,
          endPoint: .trailing
        )
        .frame(height: 46)
        .overlay(alignment: .leading) {
          VStack(alignment: .leading, spacing: 4) {
            Capsule().fill(.white).frame(width: 70, height: 7)
            Capsule().fill(.white.opacity(0.7)).frame(width: 46, height: 3)
          }
          .padding(.leading, 9)
        }
        .overlay(alignment: .trailing) {
          Circle().fill(.white.opacity(0.25)).frame(width: 30, height: 30)
            .overlay { Circle().stroke(.white, lineWidth: 2) }
            .padding(.trailing, 8)
        }
        MockResumeLines(accent: accent.color, centered: false)
      }
    case .slate:
      VStack(spacing: 8) {
        Rectangle()
          .fill(Color(red: 0.09, green: 0.10, blue: 0.12))
          .frame(height: 46)
          .overlay(alignment: .bottom) { accent.color.frame(height: 4) }
          .overlay(alignment: .leading) {
            VStack(alignment: .leading, spacing: 4) {
              Capsule().fill(.white).frame(width: 66, height: 7)
              Capsule().fill(accent.color).frame(width: 44, height: 3)
            }
            .padding(.leading, 9)
          }
          .overlay(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 5)
              .fill(.white.opacity(0.16))
              .frame(width: 30, height: 30)
              .overlay {
                RoundedRectangle(cornerRadius: 5).stroke(accent.color, lineWidth: 1.5)
              }
              .padding(.trailing, 8)
          }
        MockResumeLines(accent: accent.color, centered: false)
      }
    case .onyx:
      VStack(spacing: 8) {
        Rectangle()
          .fill(Color(white: 0.07))
          .frame(height: 52)
          .overlay(alignment: .leading) {
            HStack(spacing: 7) {
              Rectangle().fill(accent.color).frame(width: 4, height: 26)
              VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(.white).frame(width: 74, height: 8)
                Capsule().fill(accent.color).frame(width: 42, height: 3)
              }
            }
            .padding(.leading, 8)
          }
        MockResumeLines(accent: accent.color, centered: false)
      }
    case .lumen:
      VStack(alignment: .leading, spacing: 8) {
        Divider()
        Capsule().fill(Color.black.opacity(0.60)).frame(width: 92, height: 7)
        HStack(spacing: 3) {
          ForEach(0..<7, id: \.self) { _ in
            Rectangle().fill(accent.color.opacity(0.8)).frame(width: 5, height: 2)
          }
        }
        Divider()
        MockResumeLines(accent: accent.color, centered: false)
      }
      .padding(.horizontal, 4)
      .padding(.top, 4)
    case .cascade:
      VStack(alignment: .leading, spacing: 7) {
        Capsule().fill(Color.black.opacity(0.78)).frame(width: 86, height: 8)
        Capsule().fill(accent.color.opacity(0.9)).frame(width: 52, height: 3)
        VStack(alignment: .leading, spacing: 3) {
          Rectangle().fill(accent.color).frame(width: 84, height: 3)
          Rectangle().fill(accent.color.opacity(0.55)).frame(width: 60, height: 3)
          Rectangle().fill(accent.color.opacity(0.3)).frame(width: 38, height: 3)
        }
        MockResumeLines(accent: accent.color, centered: false)
      }
      .padding(.horizontal, 4)
      .padding(.top, 4)
    case .vector:
      VStack(alignment: .leading, spacing: 8) {
        ZStack(alignment: .topLeading) {
          VStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { _ in
              HStack(spacing: 6) {
                ForEach(0..<14, id: \.self) { _ in
                  Circle().fill(Color.black.opacity(0.13)).frame(width: 1.5, height: 1.5)
                }
              }
            }
          }
          VStack(alignment: .leading, spacing: 5) {
            Capsule().fill(Color.black.opacity(0.76)).frame(width: 74, height: 7)
            Capsule().fill(accent.color).frame(width: 46, height: 3)
          }
          .padding(.top, 4)
        }
        .frame(height: 44)
        .overlay(alignment: .topTrailing) {
          Rectangle().fill(Color.black.opacity(0.08)).frame(width: 26, height: 26)
            .overlay { Rectangle().stroke(accent.color, lineWidth: 1.5) }
        }
        MockResumeLines(accent: accent.color, centered: false)
      }
      .padding(.horizontal, 4)
    case .mosaic:
      VStack(spacing: 8) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 5) {
            Capsule().fill(Color.black.opacity(0.78)).frame(width: 68, height: 8)
            Capsule().fill(accent.color).frame(width: 44, height: 3)
          }
          Spacer(minLength: 6)
          VStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { row in
              HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { column in
                  Rectangle()
                    .fill(accent.color.opacity(row == column ? 1 : 0.35))
                    .frame(width: 10, height: 10)
                }
              }
            }
          }
        }
        Rectangle().fill(Color(red: 0.17, green: 0.20, blue: 0.29)).frame(height: 3)
        MockResumeLines(accent: accent.color, centered: false)
      }
      .padding(.top, 4)
    case .vertex:
      VStack(spacing: 8) {
        ZStack(alignment: .topLeading) {
          Triangle().fill(accent.color).frame(width: 42, height: 42)
          VStack(alignment: .leading, spacing: 5) {
            Capsule().fill(Color.black.opacity(0.78)).frame(width: 70, height: 8)
            Capsule().fill(accent.color).frame(width: 44, height: 3)
          }
          .padding(.leading, 50)
          .padding(.top, 6)
        }
        .frame(height: 46)
        Rectangle().fill(Color(red: 0.17, green: 0.20, blue: 0.29)).frame(height: 2)
          .padding(.leading, 50)
        MockResumeLines(accent: accent.color, centered: false)
      }
    case .meridian:
      HStack(spacing: 10) {
        Rectangle().fill(accent.color).frame(width: 6)
        VStack(alignment: .leading, spacing: 8) {
          Capsule().fill(Color.black.opacity(0.78)).frame(width: 90, height: 8)
          Divider()
          Capsule().fill(Color.black.opacity(0.30)).frame(width: 64, height: 3)
          MockResumeLines(accent: accent.color, centered: false)
        }
        .padding(.vertical, 8)
      }
    case .linen:
      VStack(spacing: 7) {
        Rectangle()
          .fill(accent.color.opacity(0.09))
          .frame(height: 56)
          .overlay {
            VStack(spacing: 5) {
              Capsule().fill(Color.black.opacity(0.76)).frame(width: 94, height: 8)
              Capsule().fill(Color.black.opacity(0.28)).frame(width: 62, height: 3)
              Diamond().fill(accent.color).frame(width: 6, height: 6)
            }
          }
        MockResumeLines(accent: accent.color, centered: true)
      }
    case .ledger:
      VStack(spacing: 7) {
        Capsule().fill(Color.black.opacity(0.78)).frame(width: 96, height: 8)
        VStack(spacing: 2) {
          Rectangle().fill(Color.black.opacity(0.7)).frame(height: 1.5)
          Rectangle().fill(Color.black.opacity(0.35)).frame(height: 0.5)
        }
        Capsule().fill(Color.black.opacity(0.28)).frame(width: 62, height: 3)
        MockResumeLines(accent: accent.color, centered: true)
      }
      .padding(7)
      .overlay {
        Rectangle().stroke(Color.black.opacity(0.55), lineWidth: 1)
      }
    case .quill:
      VStack(alignment: .leading, spacing: 7) {
        Capsule().fill(Color.black.opacity(0.78)).frame(width: 90, height: 8)
        HStack(spacing: 5) {
          Diamond().fill(accent.color).frame(width: 6, height: 6)
          Capsule().fill(Color.black.opacity(0.30)).frame(width: 62, height: 3)
        }
        VStack(spacing: 2) {
          Rectangle().fill(Color.black.opacity(0.72)).frame(height: 1.2)
          Rectangle().fill(Color.black.opacity(0.32)).frame(height: 0.5)
        }
        MockResumeLines(accent: accent.color, centered: false)
      }
      .padding(.horizontal, 4)
      .padding(.top, 4)
    case .eclipse:
      VStack(alignment: .leading, spacing: 8) {
        ZStack(alignment: .topLeading) {
          Circle()
            .fill(accent.color)
            .frame(width: 118, height: 118)
            .overlay {
              Circle()
                .fill(.white.opacity(0.25))
                .overlay { Circle().strokeBorder(.white, lineWidth: 2) }
                .frame(width: 42, height: 42)
                .offset(x: -16, y: 16)
            }
            .offset(x: 86, y: -36)
          VStack(alignment: .leading, spacing: 5) {
            Capsule().fill(Color.black.opacity(0.78)).frame(width: 76, height: 8)
            Capsule().fill(accent.color).frame(width: 50, height: 3)
            HStack(spacing: 4) {
              Image(systemName: "phone.fill").font(.system(size: 5)).foregroundStyle(accent.color)
              Capsule().fill(Color.black.opacity(0.2)).frame(width: 30, height: 3)
            }
            .padding(.top, 2)
          }
          .padding(.top, 12)
        }
        .frame(height: 86)
        MockChips(accent: accent.color)
        MockResumeLines(accent: accent.color, centered: false)
      }
      .padding(.horizontal, 4)
    case .contour:
      VStack(alignment: .leading, spacing: 7) {
        Capsule().fill(Color.black.opacity(0.8)).frame(width: 64, height: 9)
        // The surname, hollow — the whole idea of the template.
        Capsule().strokeBorder(accent.color, lineWidth: 1.6).frame(width: 94, height: 9)
        Capsule().fill(Color.black.opacity(0.2)).frame(width: 72, height: 3)
        Rectangle()
          .fill(Color.black.opacity(0.12))
          .frame(height: 0.8)
          .overlay(alignment: .leading) { accent.color.frame(width: 26, height: 2.4) }
        MockChips(accent: accent.color)
        MockResumeLines(accent: accent.color, centered: false)
      }
      .padding(.horizontal, 4)
      .padding(.top, 6)
    case .axis:
      HStack(spacing: 9) {
        ZStack(alignment: .top) {
          accent.color
          Capsule()
            .fill(.white.opacity(0.85))
            .frame(width: 3, height: 96)
            .padding(.top, 26)
        }
        .frame(width: 16)
        VStack(alignment: .leading, spacing: 8) {
          Capsule().fill(Color.black.opacity(0.78)).frame(width: 74, height: 8)
          Rectangle().fill(accent.color).frame(width: 32, height: 4)
          MockChips(accent: accent.color)
          MockResumeLines(accent: accent.color, centered: false)
        }
        .padding(.vertical, 8)
      }
    case .terrace:
      VStack(alignment: .leading, spacing: 11) {
        HStack(alignment: .top, spacing: 8) {
          Rectangle()
            .fill(accent.color)
            .frame(width: 7, height: 7)
            .frame(width: 32, alignment: .leading)
          VStack(alignment: .leading, spacing: 5) {
            Capsule().fill(Color.black.opacity(0.78)).frame(width: 72, height: 8)
            Capsule().fill(accent.color).frame(width: 46, height: 3)
            Rectangle().fill(Color.black.opacity(0.7)).frame(height: 1)
          }
        }
        // The headings stay out in the margin, level with the text they open.
        ForEach(0..<3, id: \.self) { _ in
          HStack(alignment: .top, spacing: 8) {
            Capsule()
              .fill(Color.black.opacity(0.5))
              .frame(width: 26, height: 3)
              .frame(width: 32, alignment: .leading)
              .padding(.top, 3)
            VStack(alignment: .leading, spacing: 4) {
              Rectangle().fill(Color.black.opacity(0.18)).frame(height: 0.8)
              Capsule().fill(Color.black.opacity(0.15)).frame(height: 3)
              Capsule().fill(Color.black.opacity(0.15)).frame(width: 86, height: 3)
              Capsule().fill(Color.black.opacity(0.15)).frame(width: 68, height: 3)
            }
          }
        }
      }
      .padding(.horizontal, 4)
      .padding(.top, 4)
    case .vantage:
      VStack(spacing: 0) {
        VStack(alignment: .leading, spacing: 4) {
          Capsule().fill(.white).frame(width: 82, height: 8)
          Capsule().fill(accent.color).frame(width: 52, height: 3)
          Rectangle().fill(accent.color).frame(width: 18, height: 2.5).padding(.vertical, 2)
          // The summary, printed inside the panel.
          ForEach(0..<3, id: \.self) { index in
            Capsule()
              .fill(.white.opacity(0.45))
              .frame(width: index == 2 ? 72 : 110, height: 2.5)
          }
          HStack(spacing: 4) {
            Image(systemName: "phone.fill").font(.system(size: 5)).foregroundStyle(accent.color)
            Capsule().fill(.white.opacity(0.5)).frame(width: 30, height: 2.5)
          }
          .padding(.top, 4)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.09, green: 0.10, blue: 0.12))
        accent.color.frame(height: 3)
        MockResumeLines(accent: accent.color, centered: false)
          .padding(.top, 9)
          .padding(.horizontal, 5)
        Spacer(minLength: 0)
      }
    case .apex, .aperture, .arclight, .blueprint, .catalyst, .circuit, .continuum, .district,
      .ember, .facet, .gallery, .halo, .helix, .kinetic, .lattice, .nexus, .orbit, .panorama,
      .quantum, .ribbon, .runway, .sentinel, .spectrum, .summit, .tessera, .vault, .wave,
      .zenith, .alcove, .sovereign, .palisade, .volta, .obsidian, .radiant, .verge, .datum,
      .pinnacle, .cobalt, .equinox, .mirage, .parallax, .emblem, .cadence, .citadel, .atrium,
      .zephyr, .cinder, .keystone, .loom, .graphite, .stratus, .vellum,
      .salute, .couture, .medallion, .sable, .terracotta, .lozenge, .circlet, .vogue, .signet,
      .almanac, .kintsugi, .bauhaus, .terminal, .topograph, .passport, .transit, .cutline,
      .receipt, .constellation:
      if let style = template.advancedStyle {
        AdvancedTemplateSkeleton(
          style: style,
          accent: accent.color,
          hasSideColumn: template.plan.hasSideColumn,
          showsPortrait: isPhotoVisible && template.isPhotoLed
        )
      }
    }
  }
}

/// Immediate loading art for the Advanced Collection. Eight constructions by
/// four variants mirror the PDF renderer, including the portrait and column
/// decisions, so even a cold thumbnail never falls back to a generic document.
private struct AdvancedTemplateSkeleton: View {
  let style: AdvancedResumeStyle
  let accent: Color
  let hasSideColumn: Bool
  let showsPortrait: Bool

  private var darkHeader: Bool { [0, 2, 4, 5, 7, 8, 12, 28, 30, 34].contains(style.motif) }

  var body: some View {
    VStack(spacing: 8) {
      header
        .frame(height: 72 + CGFloat(style.variant * 3))
        .clipped()

      if hasSideColumn {
        HStack(alignment: .top, spacing: 7) {
          if style.variant.isMultiple(of: 2) { factColumn }
          MockResumeLines(accent: accent, centered: false)
          if !style.variant.isMultiple(of: 2) { factColumn }
        }
      } else {
        MockChips(accent: accent)
        MockResumeLines(accent: accent, centered: style.variant == 2)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 4)
    .padding(.top, 2)
  }

  @ViewBuilder private var header: some View {
    ZStack(alignment: style.variant == 2 ? .top : .topLeading) {
      switch style.motif {
      case 0:
        Color(red: 0.17, green: 0.20, blue: 0.29)
          .overlay(alignment: .trailing) {
            Triangle().fill(accent).frame(width: 72 + CGFloat(style.variant * 7))
          }
      case 1:
        accent.opacity(0.08)
          .overlay(alignment: .topTrailing) {
            ZStack {
              Circle().stroke(accent.opacity(0.35), lineWidth: 1).frame(width: 58, height: 58)
              Circle().stroke(accent, lineWidth: 2).frame(width: 38, height: 38)
            }
            .offset(x: 14, y: -10)
          }
      case 2:
        LinearGradient(
          colors: [Color(red: 0.17, green: 0.20, blue: 0.29), accent],
          startPoint: .leading,
          endPoint: .trailing
        )
        .overlay(alignment: .topTrailing) {
          Circle().stroke(.white.opacity(0.18), lineWidth: 10 + CGFloat(style.variant * 2))
            .frame(width: 86, height: 86)
            .offset(x: 20, y: -32)
        }
      case 3:
        Color.black.opacity(0.025)
          .overlay {
            VStack(spacing: 8 + CGFloat(style.variant)) {
              ForEach(0..<8, id: \.self) { _ in
                Rectangle().fill(accent.opacity(0.10)).frame(height: 0.5)
              }
            }
          }
          .overlay { Rectangle().stroke(accent.opacity(0.45), lineWidth: 1).padding(5) }
      case 4:
        Color(red: 0.09, green: 0.10, blue: 0.12)
          .overlay(alignment: .trailing) {
            accent.frame(width: 76 + CGFloat(style.variant * 9)).rotationEffect(.degrees(-8))
          }
      case 5:
        Color(red: 0.17, green: 0.20, blue: 0.29)
          .overlay(alignment: .topTrailing) {
            HStack(spacing: 0) {
              ForEach(0..<(3 + style.variant), id: \.self) { _ in
                Circle().fill(accent).frame(width: 5, height: 5)
                Rectangle().fill(accent.opacity(0.55)).frame(width: 13, height: 1)
              }
            }
            .padding(13)
          }
      case 6:
        Color(red: 0.985, green: 0.978, blue: 0.96)
          .overlay { Rectangle().stroke(Color.black.opacity(0.45), lineWidth: 0.8).padding(5) }
          .overlay { Rectangle().stroke(Color.black.opacity(0.18), lineWidth: 0.6).padding(8) }
      case 8: // duotone diagonal split
        Color(red: 0.17, green: 0.20, blue: 0.29)
          .overlay(alignment: .trailing) {
            Triangle().fill(accent).frame(width: 96 + CGFloat(style.variant * 8))
              .rotationEffect(.degrees(180))
          }
      case 9: // radial halo
        accent.opacity(0.07)
          .overlay(alignment: .leading) {
            Circle().fill(accent.opacity(0.20)).frame(width: 120, height: 120)
              .blur(radius: 18).offset(x: 6)
          }
          .overlay(alignment: .bottom) { accent.frame(height: 3) }
      case 10: // datum tiles
        Color(white: 0.98)
          .overlay(alignment: .topTrailing) {
            HStack(spacing: 5) {
              ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 3)
                  .fill(accent.opacity(0.12))
                  .overlay(alignment: .topLeading) {
                    Capsule().fill(accent).frame(width: 12, height: 3).padding(4)
                  }
                  .frame(width: 26, height: 22)
              }
            }
            .padding(9)
          }
      case 11: // emblem monogram
        Color(white: 0.985)
          .overlay(alignment: .leading) { accent.frame(width: 5) }
          .overlay(alignment: .trailing) {
            OrbitHexagon().stroke(accent.opacity(0.5), lineWidth: 1.4)
              .frame(width: 52, height: 52).padding(.trailing, 12)
          }
      case 12: // layered glass panels
        Color(red: 0.09, green: 0.10, blue: 0.12)
          .overlay(alignment: .topTrailing) {
            ZStack {
              ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 7)
                  .fill((index == style.variant ? accent : Color(red: 0.17, green: 0.20, blue: 0.29)).opacity(0.9 - Double(index) * 0.22))
                  .frame(width: 92, height: 54)
                  .offset(x: CGFloat(-index * 12) + 18, y: CGFloat(index * 10) - 18)
              }
            }
          }
      case 13: // cadence equaliser
        accent.opacity(0.05)
          .overlay(alignment: .bottomTrailing) {
            HStack(alignment: .bottom, spacing: 3) {
              ForEach(0..<10, id: \.self) { index in
                accent.opacity(index.isMultiple(of: 2) ? 0.75 : 0.35)
                  .frame(width: 4, height: 8 + CGFloat((index * 9) % 30))
              }
            }
            .padding(8)
          }
      case 14: // architected frame
        Color(red: 0.99, green: 0.985, blue: 0.965)
          .overlay { Rectangle().stroke(Color(red: 0.17, green: 0.20, blue: 0.29).opacity(0.7), lineWidth: 1).padding(5) }
          .overlay(alignment: .top) {
            Trapezoid().fill(accent).frame(width: 34, height: 18)
          }
      case 15: // stratus bands
        LinearGradient(
          colors: [accent.opacity(0.22), accent.opacity(0.04)],
          startPoint: .top, endPoint: .bottom
        )
        .overlay(alignment: .bottom) { accent.frame(height: 3) }
      case 26: // Kintsugi
        Color(red: 0.982, green: 0.963, blue: 0.918)
          .overlay(alignment: .trailing) {
            StudioCrack()
              .stroke(Color(red: 0.72, green: 0.52, blue: 0.20), lineWidth: 2)
              .frame(width: 70)
          }
      case 27: // Bauhaus
        Color(red: 0.97, green: 0.95, blue: 0.90)
          .overlay(alignment: .leading) {
            Color(red: 0.17, green: 0.20, blue: 0.29).frame(width: 20)
          }
          .overlay(alignment: .topTrailing) {
            Circle().fill(accent).frame(width: 76, height: 76).offset(x: 18, y: -25)
          }
          .overlay(alignment: .topLeading) {
            Circle().fill(Color.yellow.opacity(0.8)).frame(width: 14, height: 14)
              .padding(.leading, 29).padding(.top, 10)
          }
      case 28: // Terminal
        Color(red: 0.055, green: 0.067, blue: 0.075)
          .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 5) {
              Text("> whoami").font(.system(size: 5, design: .monospaced)).foregroundStyle(accent)
              Text("career --evidence").font(.system(size: 5, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
            }
            .padding(8)
          }
      case 29: // Topograph
        Color(red: 0.965, green: 0.972, blue: 0.947)
          .overlay(alignment: .topTrailing) {
            ZStack {
              ForEach(0..<5, id: \.self) { index in
                Ellipse().stroke(accent.opacity(0.24), lineWidth: 0.7)
                  .frame(width: 54 + CGFloat(index * 10), height: 38 + CGFloat(index * 8))
              }
            }
            .offset(x: 15, y: -10)
          }
      case 30: // Passport
        Color(red: 0.12, green: 0.27, blue: 0.24)
          .overlay { RoundedRectangle(cornerRadius: 3).stroke(.white.opacity(0.30), lineWidth: 0.7).padding(6) }
          .overlay(alignment: .bottomTrailing) {
            Ellipse().stroke(accent, lineWidth: 1).frame(width: 44, height: 24).padding(8)
          }
      case 31: // Transit
        Color(white: 0.985)
          .overlay {
            StudioTransitLine().stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
              .padding(8)
          }
          .overlay {
            HStack {
              Circle().fill(.white).stroke(accent, lineWidth: 2).frame(width: 10, height: 10)
              Spacer()
              Circle().fill(.white).stroke(accent, lineWidth: 2).frame(width: 10, height: 10)
            }
            .padding(.horizontal, 9)
          }
      case 32: // Cutline
        Color(white: 0.975)
          .overlay(alignment: .trailing) {
            Triangle().fill(Color(red: 0.17, green: 0.20, blue: 0.29))
              .frame(width: 90).rotationEffect(.degrees(180))
          }
          .overlay(alignment: .bottomLeading) { accent.frame(width: 58, height: 3).padding(9) }
      case 33: // Receipt
        Color(white: 0.985)
          .overlay {
            VStack(spacing: 17) {
              Rectangle().stroke(accent.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(height: 1)
              Rectangle().stroke(accent.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(height: 1)
            }
            .padding(.horizontal, 9)
          }
      case 34: // Constellation
        Color(red: 0.055, green: 0.067, blue: 0.105)
          .overlay {
            StudioConstellation().stroke(accent.opacity(0.55), lineWidth: 0.8).padding(7)
          }
          .overlay {
            Circle().fill(accent).frame(width: 5, height: 5).offset(x: 42, y: -20)
            Circle().fill(.white).frame(width: 3, height: 3).offset(x: -35, y: 20)
          }
      default:
        LinearGradient(
          colors: [Color(red: 0.09, green: 0.10, blue: 0.12), Color(red: 0.17, green: 0.20, blue: 0.29)],
          startPoint: .leading,
          endPoint: .trailing
        )
        .overlay(alignment: .topTrailing) {
          Circle().fill(accent.opacity(0.18)).frame(width: 88, height: 88).offset(x: 22, y: -34)
        }
      }

      VStack(alignment: style.variant == 2 ? .center : .leading, spacing: 4) {
        Capsule()
          .fill(darkHeader ? .white : Color.black.opacity(0.76))
          .frame(width: 72 + CGFloat(style.variant * 6), height: 8)
        Capsule().fill(accent).frame(width: 48, height: 3)
        HStack(spacing: 4) {
          Capsule().fill(darkHeader ? .white.opacity(0.42) : Color.black.opacity(0.2)).frame(width: 34, height: 2.5)
          Capsule().fill(darkHeader ? .white.opacity(0.42) : Color.black.opacity(0.2)).frame(width: 42, height: 2.5)
        }
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: style.variant == 2 ? .top : .topLeading)

      if showsPortrait {
        Circle()
          .fill(accent.opacity(darkHeader ? 0.95 : 0.14))
          .overlay { Circle().stroke(darkHeader ? .white : accent, lineWidth: 1.5) }
          .frame(width: 33 + CGFloat(style.variant * 2), height: 33 + CGFloat(style.variant * 2))
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
          .padding(8)
      }
    }
  }

  private var factColumn: some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(0..<4, id: \.self) { index in
        Capsule().fill(index.isMultiple(of: 2) ? accent : Color.black.opacity(0.16))
          .frame(width: 30, height: 3)
      }
    }
    .padding(6)
    .frame(width: 45, height: 96, alignment: .topLeading)
    .background(accent.opacity(0.08))
  }
}

/// The layout the structural templates are built on: a narrow column of facts
/// beside a wide column of story.
private struct SidebarSkeleton: View {
  let accent: Color
  let side: HorizontalEdge
  let fill: Color
  /// The marks on the band: white on the colour ones, ink on the quiet ones.
  let ink: Color
  let photo: Bool

  private var column: some View {
    VStack(alignment: .leading, spacing: 7) {
      if photo {
        Circle()
          .fill(ink.opacity(0.25))
          .frame(width: 30, height: 30)
          .overlay { Circle().stroke(ink.opacity(0.8), lineWidth: 1.5) }
          .frame(maxWidth: .infinity)
      }
      ForEach(0..<3, id: \.self) { _ in
        VStack(alignment: .leading, spacing: 4) {
          Capsule().fill(ink.opacity(0.9)).frame(width: 30, height: 3)
          ForEach(0..<2, id: \.self) { _ in
            Capsule().fill(ink.opacity(0.35)).frame(height: 3)
          }
        }
      }
      Spacer(minLength: 0)
    }
    .padding(7)
    .frame(width: 52)
    .background(fill)
  }

  private var main: some View {
    VStack(alignment: .leading, spacing: 9) {
      Capsule().fill(Color.black.opacity(0.78)).frame(width: 68, height: 8)
      Capsule().fill(accent).frame(width: 44, height: 3)
      MockResumeLines(accent: accent, centered: false)
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 7)
  }

  var body: some View {
    HStack(spacing: 0) {
      if side == .leading {
        column
        main
      } else {
        main
        column
      }
    }
  }
}

/// Skill pills, for the templates that set competencies as labels.
private struct MockChips: View {
  let accent: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(0..<2, id: \.self) { row in
        HStack(spacing: 4) {
          ForEach(0..<3, id: \.self) { column in
            Capsule()
              .fill(accent.opacity(0.12))
              .overlay { Capsule().stroke(accent.opacity(0.5), lineWidth: 0.6) }
              .frame(width: [30, 40, 24][(row + column) % 3], height: 9)
          }
        }
      }
    }
  }
}

/// The wedge in Vertex Angle's corner.
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

/// The monogram mark the Emblem skeleton sets on its right.
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

/// The keystone the architected-frame skeleton crowns itself with.
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

private struct StudioCrack: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.midX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.midX - 8, y: rect.height * 0.28))
    path.addLine(to: CGPoint(x: rect.midX + 10, y: rect.height * 0.48))
    path.addLine(to: CGPoint(x: rect.midX - 5, y: rect.height * 0.70))
    path.addLine(to: CGPoint(x: rect.midX + 12, y: rect.maxY))
    path.move(to: CGPoint(x: rect.midX + 10, y: rect.height * 0.48))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.35))
    return path
  }
}

private struct StudioTransitLine: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.height * 0.35))
    path.addLine(to: CGPoint(x: rect.width * 0.38, y: rect.height * 0.35))
    path.addCurve(
      to: CGPoint(x: rect.width * 0.56, y: rect.height * 0.68),
      control1: CGPoint(x: rect.width * 0.50, y: rect.height * 0.35),
      control2: CGPoint(x: rect.width * 0.44, y: rect.height * 0.68))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.68))
    return path
  }
}

private struct StudioConstellation: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let points = [
      CGPoint(x: rect.minX, y: rect.height * 0.30),
      CGPoint(x: rect.width * 0.24, y: rect.height * 0.55),
      CGPoint(x: rect.width * 0.46, y: rect.height * 0.22),
      CGPoint(x: rect.width * 0.68, y: rect.height * 0.64),
      CGPoint(x: rect.maxX, y: rect.height * 0.35),
    ]
    path.move(to: points[0])
    for point in points.dropFirst() { path.addLine(to: point) }
    return path
  }
}

/// The printer's ornament the manuscript templates set beside their type.
private struct Diamond: Shape {
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

/// Identity of a thumbnail, so the render re-runs when any of it changes.
private struct TemplateKey: Hashable {
  let template: ResumeTemplate
  let accent: ResumeAccent
  let photo: Data?
  let crop: PhotoCrop?
  let isPhotoVisible: Bool
  let isTabActive: Bool
}

private struct MockCompactLines: View {
  let accent: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(0..<6, id: \.self) { index in
        HStack(spacing: 5) {
          Rectangle().fill(accent).frame(width: 3, height: 3)
          Capsule().fill(Color.black.opacity(index.isMultiple(of: 2) ? 0.20 : 0.12))
            .frame(height: 3)
        }
      }
    }
  }
}

private struct MockResumeLines: View {
  let accent: Color
  let centered: Bool

  var body: some View {
    VStack(alignment: centered ? .center : .leading, spacing: 7) {
      ForEach(0..<4, id: \.self) { section in
        Capsule().fill(accent).frame(width: section.isMultiple(of: 2) ? 66 : 52, height: 4)
        Capsule().fill(Color.black.opacity(0.17)).frame(height: 3)
        Capsule().fill(Color.black.opacity(0.12)).frame(width: 118, height: 3)
      }
    }
    .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
  }
}

#Preview {
  HStack(spacing: 16) {
    TemplatePreviewCard(template: .modern, accent: .orange, isSelected: true)
    TemplatePreviewCard(template: .classic, accent: .orange, isSelected: false)
  }
  .padding()
  .background(Theme.paper)
}
