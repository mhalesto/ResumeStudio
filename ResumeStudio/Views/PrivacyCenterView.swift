import SwiftUI

struct PrivacyCenterView: View {
  @EnvironmentObject private var careerStore: CareerIntelligenceStore
  @EnvironmentObject private var resumeStore: ResumeStore
  @AppStorage(CareerPrivacySetting.aiEnabledKey) private var aiEnabled = true
  @AppStorage(CareerPrivacySetting.shareVerifiedEvidenceKey) private var shareEvidence = true
  @AppStorage(CareerPrivacySetting.keepHistoryKey) private var keepHistory = true
  @State private var shareBundle: PrivacyExportBundle?
  @State private var confirmsReset = false
  @State private var errorMessage: String?

  var body: some View {
    List {
      Section {
        PremiumFeatureHero(
          eyebrow: "YOUR DATA, YOUR RULES",
          title: "See exactly what leaves this iPhone.",
          subtitle: "Pause AI, control verified evidence, inspect processing history and export or erase career intelligence at any time.",
          icon: "lock.shield.fill",
          accent: resumeStore.document.accent.color
        )
        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
      }

      Section("AI controls") {
        Toggle("Allow AI career tools", isOn: $aiEnabled)
        Toggle("Include verified Evidence Vault items", isOn: $shareEvidence).disabled(!aiEnabled)
        Toggle("Keep a local processing history", isOn: $keepHistory)
      }

      Section("Never included in writing requests") {
        privacyRow("Phone number and email", "person.crop.circle.badge.xmark")
        privacyRow("References and their contact details", "person.2.slash")
        privacyRow("Profile photograph", "photo.badge.shield.checkmark")
        privacyRow("Attached source files and private source links", "paperclip.badge.ellipsis")
      }

      Section("Recent AI processing") {
        if careerStore.processingRecords.isEmpty {
          Text("No AI requests recorded on this device.").foregroundStyle(Theme.mutedInk)
        }
        ForEach(careerStore.processingRecords.prefix(30)) { record in
          HStack {
            Image(systemName: "sparkles").foregroundStyle(resumeStore.document.accent.color)
            VStack(alignment: .leading) {
              Text(record.purpose).font(.headline)
              Text("Verified evidence \(record.includedVerifiedEvidence ? "included" : "not included") · \(record.completedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(Theme.mutedInk)
            }
          }
        }
        if !careerStore.processingRecords.isEmpty {
          Button("Clear processing history", systemImage: "clock.badge.xmark", role: .destructive) {
            careerStore.deleteProcessingHistory()
          }
        }
      }

      Section("Portability and deletion") {
        Button("Export career intelligence", systemImage: "square.and.arrow.up") { exportData() }
        Button("Erase career intelligence", systemImage: "trash", role: .destructive) { confirmsReset = true }
        Text("Erasing removes evidence, contacts, offers, review metadata, voice-practice history and AI revisions. Résumé documents remain untouched.")
          .font(.caption).foregroundStyle(Theme.mutedInk)
      }

      if let errorMessage { Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) } }
    }
    .navigationTitle("Privacy Centre")
    .sheet(item: $shareBundle) { ShareSheet(activityItems: [$0.url]) }
    .confirmationDialog("Erase all career intelligence?", isPresented: $confirmsReset, titleVisibility: .visible) {
      Button("Erase career intelligence", role: .destructive) { careerStore.resetCareerIntelligence() }
      Button("Cancel", role: .cancel) {}
    }
  }

  private func privacyRow(_ title: String, _ icon: String) -> some View {
    Label(title, systemImage: icon).foregroundStyle(.green)
  }

  private func exportData() {
    do {
      let data = try careerStore.exportData()
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("ResumeStudio-Career-Intelligence.json")
      try data.write(to: url, options: .atomic)
      shareBundle = PrivacyExportBundle(url: url)
    } catch { errorMessage = error.localizedDescription }
  }
}

private struct PrivacyExportBundle: Identifiable { let id = UUID(); let url: URL }
