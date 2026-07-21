import SwiftUI

/// "Back It Up" — every claim on the résumé, and what a reader can see behind it.
///
/// Sits alongside the ATS check and the recruiter scan as the third question:
/// will the human *believe* it? Free and on device, because it is matching
/// rather than generation and the input is the reader's whole career.
///
/// The screen never offers to rewrite anything. Each finding ends in one of
/// three moves the reader makes themselves — add the example, ask a referee, or
/// cut the line — because a tool that quietly rewrites the claim is the thing
/// hiring managers are now rejecting on sight.
struct ClaimAuditView: View {
  @EnvironmentObject private var store: ResumeStore
  @EnvironmentObject private var careerStore: CareerIntelligenceStore

  @State private var showsDefenceSheet = false

  private var accent: Color { store.document.accent.color }

  private var report: ClaimAuditReport {
    ClaimAuditService.audit(
      document: store.document,
      evidence: careerStore.evidence,
      attestations: careerStore.attestations)
  }

  var body: some View {
    List {
      scoreHeader
      if report.claims.isEmpty {
        emptyState
      } else {
        priorityFixes
        bucket(.provable)
        bucket(.assertable)
        interviewDefence
      }
      methodNote
    }
    .listStyle(.insetGrouped)
    .navigationTitle("Back It Up")
    .navigationBarTitleDisplayMode(.inline)
  }

  // MARK: - Header

  private var scoreHeader: some View {
    Section {
      HStack(spacing: 18) {
        ZStack {
          Circle().stroke(Theme.hairline, lineWidth: 9)
          Circle().trim(from: 0, to: Double(report.score) / 100)
            .stroke(accent, style: StrokeStyle(lineWidth: 9, lineCap: .round))
            .rotationEffect(.degrees(-90))
          Text("\(report.score)").font(.title.bold())
        }
        .frame(width: 88, height: 88)
        VStack(alignment: .leading, spacing: 5) {
          Text(report.verdict).font(.headline)
          Text(
            "How much of your résumé a reader can see the proof for — not a judgement about whether any of it is true."
          )
          .font(.caption)
          .foregroundStyle(Theme.mutedInk)
        }
      }
      .padding(.vertical, 6)
      // The ring carries the number visually; read apart they announce a bare
      // integer with no unit and no verdict.
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Backing score")
      .accessibilityValue("\(report.score) out of 100. \(String(localized: report.verdict))")

      HStack(spacing: 0) {
        tally(report.provableCount, .provable)
        tally(report.assertableCount, .assertable)
        tally(report.bareCount, .bare)
      }
    }
  }

  private func tally(_ count: Int, _ backing: ClaimBacking) -> some View {
    VStack(spacing: 3) {
      Text("\(count)").font(.title3.bold().monospacedDigit()).foregroundStyle(tint(for: backing))
      Text(backing.title).font(.caption2).foregroundStyle(Theme.mutedInk)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(backing.title)
    .accessibilityValue("\(count)")
  }

  // MARK: - Findings

  @ViewBuilder private var priorityFixes: some View {
    if !report.priorityFixes.isEmpty {
      Section {
        ForEach(report.priorityFixes) { claim in
          claimRow(claim)
        }
      } header: {
        Text("Fix these first")
      } footer: {
        Text(
          "A skill the rest of your résumé never mentions is the pattern hiring managers say they reject on. Either show it happening, or take it off."
        )
      }
    }
  }

  @ViewBuilder private func bucket(_ backing: ClaimBacking) -> some View {
    let claims = report.claims(backed: backing)
    if !claims.isEmpty {
      Section {
        ForEach(claims) { claim in
          claimRow(claim)
        }
      } header: {
        Label {
          Text(backing.title)
        } icon: {
          Image(systemName: backing.systemImage).foregroundStyle(tint(for: backing))
        }
      } footer: {
        Text(backing.detail)
      }
    }
  }

  private func claimRow(_ claim: AuditedClaim) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(claim.origin.label).eyebrow().foregroundStyle(Theme.mutedInk)
      Text(claim.text).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
      Text(claim.rationale).font(.caption).foregroundStyle(Theme.mutedInk)

      if claim.isConfirmedByReferee {
        Label("Confirmed by a referee", systemImage: "checkmark.seal.fill")
          .font(.caption.weight(.semibold)).foregroundStyle(.green)
      }

      if claim.backing != .provable {
        HStack(spacing: 12) {
          NavigationLink(value: HomeRoute.editor(claim.section)) {
            Label("Show it", systemImage: "square.and.pencil")
          }
          .buttonStyle(.borderless)

          NavigationLink(value: HomeRoute.evidenceVault) {
            Label("Evidence", systemImage: "tray.full")
          }
          .buttonStyle(.borderless)
        }
        .font(.caption.weight(.semibold))
        .tint(accent)
      }
    }
    .padding(.vertical, 3)
    // Read as separate elements this is four unlabelled fragments; as one it is
    // the finding a reader can act on.
    .accessibilityElement(children: .contain)
    .accessibilityLabel("\(String(localized: claim.backing.title)): \(claim.text)")
    .accessibilityHint(claim.rationale)
  }

  // MARK: - Interview defence

  @ViewBuilder private var interviewDefence: some View {
    if !report.interviewDefence.isEmpty {
      Section {
        Button {
          showsDefenceSheet = true
        } label: {
          Label("What you'll be asked to prove", systemImage: "person.bust")
        }
        .sheet(isPresented: $showsDefenceSheet) {
          NavigationStack {
            List {
              Section {
                ForEach(report.interviewDefence) { claim in
                  VStack(alignment: .leading, spacing: 4) {
                    Text(claim.text).font(.subheadline.weight(.medium))
                    Text(claim.origin.label).font(.caption).foregroundStyle(Theme.mutedInk)
                  }
                  .padding(.vertical, 2)
                }
              } footer: {
                Text(
                  "Every claim a reader can see support for. These are the lines an interviewer picks from — have the example ready for each."
                )
              }
            }
            .navigationTitle("Interview defence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
              ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { showsDefenceSheet = false }
              }
            }
          }
        }
      } footer: {
        Text("The same audit, read the other way round.")
      }
    }
  }

  // MARK: - Supporting

  private var emptyState: some View {
    Section {
      VStack(alignment: .leading, spacing: 8) {
        Text("Nothing to audit yet").font(.headline)
        Text("Add core competencies and a few experience bullets, then come back.")
          .font(.subheadline).foregroundStyle(Theme.mutedInk)
      }
      .padding(.vertical, 6)
    }
  }

  private var methodNote: some View {
    Section {
      Text(
        "Everything here is worked out on your device, costs no AI credits, and is never sent anywhere. A claim marked bare is one this résumé doesn't demonstrate — that is a statement about the page, not about you."
      )
      .font(.caption).foregroundStyle(Theme.mutedInk)
    }
  }

  private func tint(for backing: ClaimBacking) -> Color {
    switch backing {
    case .provable: .green
    case .assertable: accent
    case .bare: .orange
    }
  }
}
