import SwiftUI

/// Ask someone who was there to confirm one claim, then show what they said.
///
/// The screen is careful about what it promises. A confirmation is somebody
/// else's word, recorded and dated, which is worth far more than a self-tick —
/// and it is still only somebody's word, so the limitation is on the screen
/// rather than in a help article.
struct EvidenceAttestationView: View {
  let evidence: CareerEvidence

  @EnvironmentObject private var resumeStore: ResumeStore
  @EnvironmentObject private var careerStore: CareerIntelligenceStore
  @EnvironmentObject private var network: NetworkMonitor
  @Environment(\.dismiss) private var dismiss

  @State private var context: String = ""
  @State private var isWorking = false
  @State private var errorMessage: String?
  @State private var shareURL: URL?

  private var accent: Color { resumeStore.document.accent.color }
  private var existing: EvidenceAttestation? { careerStore.attestation(for: evidence.id) }

  var body: some View {
    NavigationStack {
      Form {
        Section("The claim") {
          Text(evidence.title.nilIfBlank ?? String(localized: evidence.kind.title))
            .font(.headline)
            .foregroundStyle(Theme.ink)
          Text(evidence.detail)
            .font(.subheadline)
            .foregroundStyle(Theme.inkSoft)
        }

        if let existing {
          Section("Status") {
            Label {
              Text(existing.status.title).foregroundStyle(Theme.ink)
            } icon: {
              Image(systemName: existing.status.systemImage)
                .foregroundStyle(existing.isConfirmed ? .green : accent)
            }
            if existing.isConfirmed {
              Text(existing.attributionText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
              if !existing.comment.isBlank {
                Text("“\(existing.comment)”")
                  .font(.subheadline)
                  .foregroundStyle(Theme.inkSoft)
              }
            }
            if existing.status.isOpen {
              Button("Check for a reply") { Task { await refresh(existing) } }
                .disabled(isWorking || !network.isOnline)
              ShareLink(item: shareLink(for: existing)) {
                Label("Send the link again", systemImage: "square.and.arrow.up")
              }
              Button("Withdraw request", role: .destructive) {
                Task { await revoke(existing) }
              }
              .disabled(isWorking || !network.isOnline)
            }
          }
        } else {
          Section("Who are you asking?") {
            TextField("Their relationship to this claim", text: $context)
              .textInputAutocapitalization(.sentences)
            Text("Shown on the page they open, so they know why they were asked. Example: “You managed this project at Northstar Works.”")
              .font(.caption)
              .foregroundStyle(Theme.mutedInk)
          }

          Section {
            Button {
              Task { await createRequest() }
            } label: {
              HStack {
                if isWorking { ProgressView() }
                Text("Create confirmation link")
              }
            }
            .disabled(isWorking || !network.isOnline || evidence.detail.count < 8)
          } footer: {
            Text("You send the link yourself, however you like. They answer once, and the answer is final.")
          }
        }

        if let shareURL {
          Section("Send this link") {
            ShareLink(item: shareURL) {
              Label("Share confirmation link", systemImage: "square.and.arrow.up")
            }
            Text(shareURL.absoluteString)
              .font(.caption)
              .foregroundStyle(Theme.mutedInk)
              .textSelection(.enabled)
          }
        }

        if let errorMessage {
          Section {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
              .font(.caption)
              .foregroundStyle(.orange)
          }
        }

        Section {
          Text(EvidenceAttestation.assuranceNote)
            .font(.caption)
            .foregroundStyle(Theme.mutedInk)
        }
      }
      .navigationTitle("Ask for confirmation")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }

  private func shareLink(for attestation: EvidenceAttestation) -> URL {
    shareURL ?? URL(string: "https://europe-west1-resumestudio-4addf.cloudfunctions.net/api/a/\(attestation.token)")!
  }

  private func createRequest() async {
    errorMessage = nil
    isWorking = true
    defer { isWorking = false }
    do {
      let created = try await EvidenceAttestationService().requestConfirmation(
        claim: evidence.detail, context: context)
      careerStore.upsert(EvidenceAttestation(
        evidenceID: evidence.id,
        token: created.token,
        claim: evidence.detail,
        context: context,
        status: .pending,
        verifierName: "",
        verifierRole: "",
        comment: "",
        respondedAt: nil,
        expiresAt: created.expiresAt
      ))
      shareURL = created.shareURL
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func refresh(_ attestation: EvidenceAttestation) async {
    errorMessage = nil
    isWorking = true
    defer { isWorking = false }
    do {
      let remote = try await EvidenceAttestationService().status(token: attestation.token)
      var updated = attestation
      updated.status = remote.status
      updated.verifierName = remote.verifierName
      updated.verifierRole = remote.verifierRole
      updated.comment = remote.comment
      updated.respondedAt = remote.respondedAt
      updated.expiresAt = remote.expiresAt
      careerStore.upsert(updated)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func revoke(_ attestation: EvidenceAttestation) async {
    errorMessage = nil
    isWorking = true
    defer { isWorking = false }
    do {
      try await EvidenceAttestationService().revoke(token: attestation.token)
      var updated = attestation
      updated.status = .revoked
      careerStore.upsert(updated)
      shareURL = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
