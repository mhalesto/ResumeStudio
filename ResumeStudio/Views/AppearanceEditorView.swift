import SwiftUI

struct AppearanceEditorView: View {
  @Binding var template: ResumeTemplate
  @Binding var accent: ResumeAccent

  var body: some View {
    List {
      Section {
        ForEach(ResumeTemplate.allCases) { option in
          Button {
            template = option
          } label: {
            TemplateOptionRow(
              option: option,
              accent: accent,
              isSelected: template == option
            )
          }
          .buttonStyle(.plain)
        }
      } header: {
        Text("PDF Template")
      } footer: {
        Text(
          "Templates change the typography, header, section styling, and reference cards in the exported PDF."
        )
      }

      Section {
        ForEach(ResumeAccent.allCases) { option in
          Button {
            accent = option
          } label: {
            HStack(spacing: 14) {
              Circle()
                .fill(option.color)
                .frame(width: 28, height: 28)
                .overlay {
                  Circle().stroke(Color.primary.opacity(0.12), lineWidth: 1)
                }
              Text(option.title)
                .foregroundStyle(.primary)
              Spacer()
              if accent == option {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundStyle(option.color)
              }
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("\(option.title) accent colour")
          .accessibilityAddTraits(accent == option ? .isSelected : [])
        }
      } header: {
        Text("Accent Colour")
      } footer: {
        Text(
          "Each swatch uses its true export colour, so you can compare them before previewing the PDF."
        )
      }
    }
    .navigationTitle("Template & Colour")
    .navigationBarTitleDisplayMode(.inline)
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
  }
}
