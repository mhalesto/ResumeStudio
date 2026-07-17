import SwiftUI

struct PremiumConfirmationRow: Identifiable {
  enum Tone { case neutral, accent, destructive }

  let id = UUID()
  let eyebrow: String
  let title: String
  let detail: String
  let systemImage: String
  var tone: Tone = .neutral

  fileprivate func tint(accent: Color) -> Color {
    switch tone {
    case .neutral: Theme.mutedInk
    case .accent: accent
    case .destructive: .red
    }
  }
}

struct PremiumConfirmationSheet: View {
  enum ActionRole: Equatable { case primary, destructive }

  let title: String
  let message: String
  let systemImage: String
  let accent: Color
  var iconIsDestructive = true
  var rows: [PremiumConfirmationRow] = []
  let safetyNote: String
  let confirmTitle: String
  var cancelTitle = "Cancel"
  var actionRole: ActionRole = .destructive
  var isWorking = false
  let onConfirm: () -> Void
  let onCancel: () -> Void

  private var actionColor: Color { actionRole == .destructive ? .red : accent }
  private var iconColor: Color { iconIsDestructive ? .red : accent }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top, spacing: 14) {
        Image(systemName: systemImage)
          .font(.system(size: 22, weight: .semibold))
          .foregroundStyle(iconColor)
          .frame(width: 50, height: 50)
          .background(iconColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 15))
        VStack(alignment: .leading, spacing: 4) {
          Text(title).font(.title2.bold()).foregroundStyle(Theme.ink)
          Text(message).font(.subheadline).foregroundStyle(Theme.mutedInk)
        }
      }

      if !rows.isEmpty {
        VStack(spacing: 0) {
          ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            confirmationRow(row)
            if index < rows.count - 1 { Divider().padding(.leading, 52) }
          }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(accent.opacity(0.18))
        }
      }

      Label(safetyNote, systemImage: "checkmark.shield.fill")
        .font(.caption.weight(.medium))
        .foregroundStyle(Theme.mutedInk)

      Spacer(minLength: 0)

      Button(role: actionRole == .destructive ? .destructive : nil, action: onConfirm) {
        HStack(spacing: 9) {
          if isWorking { ProgressView().tint(.white) }
          Text(confirmTitle).font(.headline)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(actionColor, in: Capsule())
      }
      .buttonStyle(.plain)
      .disabled(isWorking)

      Button(cancelTitle, action: onCancel)
        .font(.subheadline.bold())
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity)
        .disabled(isWorking)
    }
    .padding(.horizontal, 22)
    .padding(.top, 10)
    .padding(.bottom, 18)
  }

  private func confirmationRow(_ row: PremiumConfirmationRow) -> some View {
    let tint = row.tint(accent: accent)
    return HStack(spacing: 13) {
      Image(systemName: row.systemImage)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(tint)
        .frame(width: 38, height: 38)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
      VStack(alignment: .leading, spacing: 2) {
        Text(row.eyebrow).font(.caption2.bold()).tracking(0.7).foregroundStyle(tint)
        Text(row.title).font(.subheadline.bold()).foregroundStyle(Theme.ink).lineLimit(1)
        Text(row.detail).font(.caption).foregroundStyle(Theme.mutedInk).lineLimit(1)
      }
      Spacer()
    }
    .padding(13)
  }
}

extension View {
  func premiumConfirmationPresentation(initialFraction: CGFloat = 0.58) -> some View {
    presentationDetents([.fraction(initialFraction), .large])
      .presentationDragIndicator(.visible)
      .presentationCornerRadius(30)
      .presentationBackground(Theme.paper)
      .presentationCompactAdaptation(.sheet)
  }
}
