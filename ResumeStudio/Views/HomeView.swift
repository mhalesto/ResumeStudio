import SwiftUI

struct HomeView: View {
  @EnvironmentObject private var store: ResumeStore
  @State private var showEditor = false
  @State private var pendingStart: StartChoice?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        hero
        quickStart
        templates
        privacyNote
      }
      .padding(.horizontal, 20)
      .padding(.top, 12)
      .padding(.bottom, 36)
    }
    .background(Color(uiColor: .systemGroupedBackground))
    .navigationTitle("Resume Studio")
    .navigationBarTitleDisplayMode(.inline)
    .navigationDestination(isPresented: $showEditor) {
      ResumeEditorView()
    }
    .alert(item: $pendingStart) { choice in
      Alert(
        title: Text("Replace current draft?"),
        message: Text("Your current on-device draft will be replaced."),
        primaryButton: .destructive(Text("Replace")) {
          switch choice {
          case .example:
            store.loadSample()
          case .blank:
            store.startBlankResume()
          }
          showEditor = true
        },
        secondaryButton: .cancel()
      )
    }
  }

  private var hero: some View {
    ZStack(alignment: .topTrailing) {
      LinearGradient(
        colors: [
          Color(red: 0.12, green: 0.15, blue: 0.24), Color(red: 0.20, green: 0.23, blue: 0.34),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )

      Circle()
        .fill(store.document.accent.color.opacity(0.22))
        .frame(width: 190, height: 190)
        .offset(x: 62, y: -74)

      Circle()
        .stroke(.white.opacity(0.08), lineWidth: 24)
        .frame(width: 140, height: 140)
        .offset(x: 82, y: 130)

      VStack(alignment: .leading, spacing: 16) {
        ZStack {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(store.document.accent.color)
          Image(systemName: "doc.text.fill")
            .font(.title2.weight(.bold))
            .foregroundStyle(.white)
        }
        .frame(width: 54, height: 54)

        VStack(alignment: .leading, spacing: 7) {
          Text("Build a resume that feels like you.")
            .font(.system(.largeTitle, design: .rounded, weight: .bold))
            .foregroundStyle(.white)
          Text("Edit your story, choose a style, and export a polished PDF in minutes.")
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.76))
            .fixedSize(horizontal: false, vertical: true)
        }

        Button {
          showEditor = true
        } label: {
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text("Continue Editing")
                .font(.headline)
              Text(draftName)
                .font(.caption)
                .opacity(0.72)
            }
            Spacer()
            Image(systemName: "arrow.right")
              .font(.headline)
          }
          .foregroundStyle(.white)
          .padding(.horizontal, 17)
          .padding(.vertical, 14)
          .background(
            store.document.accent.color, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)

        HStack(spacing: 18) {
          FeatureMetric(value: "3", label: "Templates")
          FeatureMetric(value: "4", label: "Colours")
          FeatureMetric(value: "PDF", label: "Ready")
        }
      }
      .padding(24)
    }
    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    .shadow(color: .black.opacity(0.16), radius: 18, y: 10)
  }

  private var quickStart: some View {
    VStack(alignment: .leading, spacing: 12) {
      HomeSectionTitle(
        title: "Start creating", subtitle: "Use example content or begin with a clean page.")

      HStack(spacing: 12) {
        QuickStartCard(
          title: "Example Resume",
          subtitle: "See a complete fictional example",
          systemImage: "doc.text.fill",
          color: store.document.accent.color
        ) {
          pendingStart = .example
        }

        QuickStartCard(
          title: "Blank Resume",
          subtitle: "Build every section yourself",
          systemImage: "plus.rectangle.on.rectangle",
          color: .blue
        ) {
          pendingStart = .blank
        }
      }
    }
  }

  private var templates: some View {
    VStack(alignment: .leading, spacing: 12) {
      HomeSectionTitle(
        title: "Choose your look", subtitle: "Every template exports as a searchable PDF.")

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 14) {
          ForEach(ResumeTemplate.allCases) { template in
            Button {
              store.document.template = template
              showEditor = true
            } label: {
              TemplatePreviewCard(
                template: template,
                accent: store.document.accent,
                isSelected: store.document.template == template
              )
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.vertical, 4)
      }
      .contentMargins(.horizontal, 1, for: .scrollContent)
    }
  }

  private var privacyNote: some View {
    HStack(spacing: 12) {
      Image(systemName: "lock.shield.fill")
        .font(.title3)
        .foregroundStyle(store.document.accent.color)
      VStack(alignment: .leading, spacing: 2) {
        Text("Private by default")
          .font(.subheadline.weight(.semibold))
        Text("Your draft stays on this device. No account is required.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
    }
    .padding(16)
    .background(
      Color(uiColor: .secondarySystemGroupedBackground),
      in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }

  private var draftName: String {
    let value = store.document.personal.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? "Untitled Resume" : value
  }
}

private enum StartChoice: String, Identifiable {
  case example
  case blank

  var id: String { rawValue }
}

private struct FeatureMetric: View {
  let value: String
  let label: String

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(value)
        .font(.headline.weight(.bold))
        .foregroundStyle(.white)
      Text(label)
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.58))
    }
  }
}

private struct HomeSectionTitle: View {
  let title: String
  let subtitle: String

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.title3.weight(.bold))
      Text(subtitle)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }
}

private struct QuickStartCard: View {
  let title: String
  let subtitle: String
  let systemImage: String
  let color: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 13) {
        Image(systemName: systemImage)
          .font(.title2.weight(.semibold))
          .foregroundStyle(color)
          .frame(width: 42, height: 42)
          .background(
            color.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.primary)
          Text(subtitle)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
      .padding(16)
      .background(
        Color(uiColor: .secondarySystemGroupedBackground),
        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}

private struct TemplatePreviewCard: View {
  let template: ResumeTemplate
  let accent: ResumeAccent
  let isSelected: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ZStack {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(.white)
        templateArtwork
          .padding(10)
      }
      .frame(width: 170, height: 208)
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(
            isSelected ? accent.color : Color.black.opacity(0.08), lineWidth: isSelected ? 3 : 1)
      }
      .shadow(color: .black.opacity(0.08), radius: 8, y: 5)

      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(template.title)
            .font(.subheadline.weight(.bold))
          if isSelected {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(accent.color)
          }
        }
        Text(template.subtitle)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .frame(width: 170, alignment: .leading)
      }
    }
  }

  @ViewBuilder
  private var templateArtwork: some View {
    switch template {
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
  NavigationStack {
    HomeView()
      .environmentObject(ResumeStore(initialDocument: .example))
  }
}
