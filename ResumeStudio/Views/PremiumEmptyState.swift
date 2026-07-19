import SwiftUI

struct PremiumEmptyState: View {
  let image: ImageResource
  let title: LocalizedStringResource
  let detail: LocalizedStringResource

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Image(image)
        .resizable()
        .scaledToFill()
        .frame(height: 180)
        .frame(maxWidth: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityHidden(true)
      Text(title).font(.title3.bold()).foregroundStyle(Theme.ink)
      Text(detail).font(.subheadline).foregroundStyle(Theme.mutedInk)
    }
    .padding(14)
    .cardSurface(radius: 24)
  }
}
