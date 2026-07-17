import SwiftUI
import UIKit

/// A horizontal row of accent swatches, each the true export colour, so a colour
/// can be tried live while browsing looks. Shared by the Home screen and the full
/// gallery so the two stay consistent.
struct AccentQuickPickRow: View {
  @Binding var selection: ResumeAccent
  let canUse: (ResumeAccent) -> Bool
  let onLocked: () -> Void

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 12) {
        ForEach(ResumeAccent.allCases) { option in
          let selected = selection == option
          let unlocked = canUse(option)
          Button {
            guard unlocked else {
              onLocked()
              return
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
              selection = option
            }
          } label: {
            ZStack {
              if selected {
                Circle()
                  .strokeBorder(option.color, lineWidth: 2)
                  .frame(width: 38, height: 38)
              }
              Circle()
                .fill(option.color)
                .frame(width: 26, height: 26)
                .overlay { Circle().strokeBorder(Color.primary.opacity(0.10), lineWidth: 1) }
                .overlay {
                  if !unlocked {
                    Image(systemName: "lock.fill")
                      .font(.system(size: 10, weight: .bold))
                      .foregroundStyle(.white)
                      .shadow(color: .black.opacity(0.35), radius: 1)
                  }
                }
            }
            .frame(width: 40, height: 40)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("\(option.title) accent\(option.isPremium ? ", premium" : "")")
          .accessibilityAddTraits(selected ? .isSelected : [])
        }
      }
      .padding(.horizontal, 1)
    }
    .contentMargins(.horizontal, 1, for: .scrollContent)
    .sensoryFeedback(.selection, trigger: selection)
  }
}

/// A rendered template preview on its way to the share sheet.
struct PreviewShareItem: Identifiable {
  let id = UUID()
  let image: UIImage
}

/// Adds a "Share preview" context menu to a template card. Holds its own share
/// state so the affordance can be dropped onto any card — Home or the gallery —
/// without the surrounding screen having to manage it.
struct TemplatePreviewShareMenu: ViewModifier {
  let template: ResumeTemplate
  let accent: ResumeAccent
  var photo: Data?
  var crop: PhotoCrop?
  var isPhotoVisible = true

  @State private var shareItem: PreviewShareItem?

  func body(content: Content) -> some View {
    content
      .contextMenu {
        Button {
          Task {
            if let image = await TemplateThumbnailRenderer.shareImage(
              template: template, accent: accent, photo: photo, crop: crop,
              isPhotoVisible: isPhotoVisible
            ) {
              shareItem = PreviewShareItem(image: image)
            }
          }
        } label: {
          Label("Share preview", systemImage: "square.and.arrow.up")
        }
      }
      .sheet(item: $shareItem) { item in
        ShareSheet(activityItems: [item.image])
      }
  }
}

extension View {
  /// Long-press to share a higher-resolution preview image of the template.
  func templatePreviewShareMenu(
    template: ResumeTemplate, accent: ResumeAccent, photo: Data? = nil, crop: PhotoCrop? = nil,
    isPhotoVisible: Bool = true
  ) -> some View {
    modifier(
      TemplatePreviewShareMenu(
        template: template, accent: accent, photo: photo, crop: crop,
        isPhotoVisible: isPhotoVisible
      )
    )
  }
}
