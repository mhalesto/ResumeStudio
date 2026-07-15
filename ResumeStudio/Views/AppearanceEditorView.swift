import SwiftUI

struct AppearanceEditorView: View {
  @Binding var template: ResumeTemplate
  @Binding var accent: ResumeAccent
  @EnvironmentObject private var purchases: PurchaseManager
  @AppStorage("appAppearance") private var appearanceRawValue = AppAppearance.system.rawValue

  /// The template catalogue is long enough that the accent swatches used to sit a
  /// hundred-odd rows down. This switch keeps both one tap away.
  @State private var section = ExportSection.template

  private enum ExportSection: String, CaseIterable, Identifiable {
    case template
    case colour

    var id: String { rawValue }
    var title: String { self == .template ? "Template" : "Colour" }
  }

  private var appAppearance: Binding<AppAppearance> {
    Binding(
      get: { AppAppearance(rawValue: appearanceRawValue) ?? .system },
      set: { appearanceRawValue = $0.rawValue }
    )
  }

  var body: some View {
    List {
      Section("Advanced layout") {
        NavigationLink {
          LayoutStudioView()
        } label: {
          Label("Layout Studio", systemImage: "slider.horizontal.3")
        }
      }
      Section {
        Picker("App Appearance", selection: appAppearance) {
          ForEach(AppAppearance.allCases) { option in
            Label(option.title, systemImage: option.systemImage)
              .tag(option)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
      } header: {
        Text("App Appearance")
      } footer: {
        Text(
          "Choose how Resume Studio looks. System follows your device. This doesn't affect the exported PDF, which is always printed on white."
        )
      }

      Section {
        Picker("Section", selection: $section) {
          ForEach(ExportSection.allCases) { option in
            Text(option.title).tag(option)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
      } header: {
        Text("Exported PDF")
      }

      if section == .template {
        templateSection
      } else {
        accentSection
      }
    }
    .navigationTitle("Template & Colour")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var templateSection: some View {
    Section {
        ForEach(ResumeTemplate.allCases) { option in
          let unlocked = purchases.canUse(option)
          Button {
            guard unlocked else {
              purchases.requestPlans()
              return
            }
            template = option
          } label: {
            HStack(spacing: 10) {
              TemplateOptionRow(
                option: option,
                accent: accent,
                isSelected: template == option
              )
              if !unlocked { PlanLockBadge() }
            }
          }
          .buttonStyle(.plain)
          .accessibilityHint(unlocked ? "" : "Available with Go, Pro, or the Design Pack")
        }
      } header: {
        Text("PDF Template")
      } footer: {
        Text(
          "Templates change the typography, header, section styling, and reference cards in the exported PDF."
        )
      }
  }

  private var accentSection: some View {
    Section {
        ForEach(ResumeAccent.allCases) { option in
          let unlocked = purchases.canUse(option)
          Button {
            guard unlocked else {
              purchases.requestPlans()
              return
            }
            accent = option
          } label: {
            HStack(spacing: 14) {
              Circle()
                .fill(option.color)
                .frame(width: 28, height: 28)
                .overlay {
                  Circle().stroke(Color.primary.opacity(0.12), lineWidth: 1)
                }
                .overlay {
                  if !unlocked {
                    Image(systemName: "lock.fill")
                      .font(.system(size: 11, weight: .bold))
                      .foregroundStyle(.white)
                      .shadow(color: .black.opacity(0.35), radius: 1)
                  }
                }
              Text(option.title)
                .foregroundStyle(.primary)
              if option.isPremium {
                Text("Premium")
                  .font(.caption2.weight(.semibold))
                  .foregroundStyle(.secondary)
                  .padding(.horizontal, 7)
                  .padding(.vertical, 2)
                  .background(Color.secondary.opacity(0.14), in: Capsule())
              }
              Spacer()
              if accent == option {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundStyle(option.color)
              } else if !unlocked {
                PlanLockBadge()
              }
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(
            "\(option.title) accent colour\(option.isPremium ? ", premium" : "")")
          .accessibilityHint(unlocked ? "" : "Available with Go, Pro, or the Design Pack")
          .accessibilityAddTraits(accent == option ? .isSelected : [])
        }
      } header: {
        Text("Accent Colour")
      } footer: {
        Text(
          "Each swatch uses its true export colour, so you can compare them before previewing the PDF. The five jewel tones are part of a subscription."
        )
      }
  }
}

private struct TemplateOptionRow: View {
  let option: ResumeTemplate
  let accent: ResumeAccent
  let isSelected: Bool

  var body: some View {
    HStack(spacing: 14) {
      ZStack {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(accent.color.opacity(0.12))
        Image(systemName: option.systemImage)
          .foregroundStyle(accent.color)
      }
      .frame(width: 46, height: 52)

      VStack(alignment: .leading, spacing: 4) {
        Text(option.title)
          .font(.body.weight(.semibold))
          .foregroundStyle(.primary)
        Text(option.subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer()
      if isSelected {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(accent.color)
      }
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
  }
}

#Preview {
  @Previewable @State var template = ResumeTemplate.modern
  @Previewable @State var accent = ResumeAccent.orange

  NavigationStack {
    AppearanceEditorView(template: $template, accent: $accent)
      .environmentObject(PurchaseManager.shared)
  }
}
