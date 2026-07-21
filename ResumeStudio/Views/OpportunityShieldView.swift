import SwiftUI

struct OpportunityShieldCard: View {
  let report: OpportunitySignalReport
  let accent: Color
  var isRefreshing = false
  var onRefresh: (() -> Void)? = nil

  private var bandColor: Color {
    switch report.band {
    case .strong: .green
    case .verify: .orange
    case .highRisk: .red
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 15) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: report.band.systemImage)
          .font(.title2)
          .foregroundStyle(bandColor)
          .frame(width: 46, height: 46)
          .background(bandColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        VStack(alignment: .leading, spacing: 3) {
          Text("OPPORTUNITY SHIELD")
            .font(.caption2.weight(.black))
            .tracking(0.6)
            .foregroundStyle(accent)
          Text(report.band.title)
            .font(.title3.bold())
            .foregroundStyle(Theme.ink)
          Text(report.confidence.title)
            .font(.caption)
            .foregroundStyle(Theme.mutedInk)
        }
        Spacer(minLength: 0)
      }

      Text(report.band.guidance)
        .font(.subheadline)
        .foregroundStyle(Theme.inkSoft)
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 8) {
        Label(report.pageStatus.title, systemImage: pageStatusImage)
        if report.repostCount > 0 {
          Label("Reposted \(report.repostCount)×", systemImage: "arrow.triangle.2.circlepath")
        }
      }
      .font(.caption.weight(.semibold))
      .foregroundStyle(Theme.mutedInk)

      ForEach(OpportunitySignalCategory.allCases) { category in
        let findings = report.findings(in: category)
        if !findings.isEmpty {
          DisclosureGroup {
            VStack(alignment: .leading, spacing: 11) {
              ForEach(findings) { finding in
                HStack(alignment: .top, spacing: 9) {
                  Image(systemName: finding.severity.systemImage)
                    .foregroundStyle(color(for: finding.severity))
                    .frame(width: 18)
                  VStack(alignment: .leading, spacing: 2) {
                    Text(finding.title)
                      .font(.subheadline.weight(.semibold))
                      .foregroundStyle(Theme.ink)
                    Text(finding.detail)
                      .font(.caption)
                      .foregroundStyle(Theme.mutedInk)
                      .fixedSize(horizontal: false, vertical: true)
                  }
                }
              }
            }
            .padding(.top, 8)
          } label: {
            Label(category.title, systemImage: category.systemImage)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(Theme.ink)
          }
          .tint(accent)
        }
      }

      if let onRefresh {
        Button(action: onRefresh) {
          if isRefreshing {
            Label("Checking public page…", systemImage: "arrow.triangle.2.circlepath")
          } else {
            Label("Refresh public-page signals", systemImage: "arrow.clockwise")
          }
        }
        .font(.subheadline.weight(.semibold))
        .disabled(isRefreshing)
      }

      Text("This is an explainable pre-apply check, not proof that a job is real or fake. Verify the role with the employer before sending money or sensitive identity information.")
        .font(.caption2)
        .foregroundStyle(Theme.mutedInk)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(19)
    .cardSurface(radius: 22)
    .accessibilityElement(children: .contain)
  }

  private var pageStatusImage: String {
    switch report.pageStatus {
    case .notChecked: "network.slash"
    case .live: "checkmark.circle.fill"
    case .removed: "xmark.circle.fill"
    case .inconclusive: "questionmark.circle.fill"
    case .unreachable: "wifi.exclamationmark"
    }
  }

  private func color(for severity: OpportunitySignalSeverity) -> Color {
    switch severity {
    case .positive: .green
    case .information: accent
    case .caution: .orange
    case .danger: .red
    }
  }
}
