import SwiftUI

struct PrivacyCenterView: View {
  @EnvironmentObject private var careerStore: CareerIntelligenceStore
  @EnvironmentObject private var resumeStore: ResumeStore
  @AppStorage(CareerPrivacySetting.aiEnabledKey) private var aiEnabled = true
  @AppStorage(CareerPrivacySetting.shareVerifiedEvidenceKey) private var shareEvidence = true
  @AppStorage(CareerPrivacySetting.keepHistoryKey) private var keepHistory = true
  @AppStorage(CareerPrivacySetting.onDeviceAIKey) private var onDeviceAIEnabled = true
  @AppStorage(CareerPrivacySetting.connectedFallbackKey) private var connectedFallbackEnabled = false
  @AppStorage(CareerPrivacySetting.opportunityMonitoringKey)
  private var opportunityMonitoringEnabled = true
  @AppStorage(ProductInsights.enabledKey) private var productInsightsEnabled = false
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
        Toggle("Use on-device intelligence", isOn: $onDeviceAIEnabled).disabled(!aiEnabled)
        Toggle("Allow connected fallback on Free", isOn: $connectedFallbackEnabled)
          .disabled(!aiEnabled || !onDeviceAIEnabled)
          .accessibilityIdentifier("privacy.connectedFallback")
        Toggle("Keep a local processing history", isOn: $keepHistory)
        LabeledContent("Apple Intelligence", value: OnDeviceAIService.availabilityDescription)
          .font(.caption)
        Text("Free uses the private on-device model first for lightweight tasks. Connected fallback is optional and may use the credits shown before each action. Go and Pro keep the connected quality model first and use on-device intelligence mainly as a fallback.")
          .font(.caption).foregroundStyle(Theme.mutedInk)
      }

      Section("Anonymous product insights") {
        Toggle("Help improve ResumeStudio", isOn: $productInsightsEnabled)
        Text("Only aggregate counters, plan, AI route and app version are shared—never identity, document content, job details, URLs or a persistent device ID.")
          .font(.caption).foregroundStyle(Theme.mutedInk)
        Link("Data-collection summary", destination: ResumeStudioLinks.dataCollection)
      }

      Section("Opportunity Shield") {
        Toggle("Refresh saved public listings", isOn: $opportunityMonitoringEnabled)
        Text("When enabled, ResumeStudio rechecks up to four due saved-job URLs when the app returns online, no more than once per URL each day. The website can see your network address and ResumeStudio user agent. Résumé and personal-profile data are never sent with the request.")
          .font(.caption).foregroundStyle(Theme.mutedInk)
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
              if let provider = record.provider { AIRouteBadge(provider: provider) }
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
    .onChange(of: productInsightsEnabled) { _, enabled in
      if enabled { ProductInsights.flushPending() }
    }
    .sheet(item: $shareBundle) { ShareSheet(activityItems: [$0.url]) }
    .sheet(isPresented: $confirmsReset) {
      PremiumConfirmationSheet(
        title: "Erase career intelligence?",
        message: "This clears the private career workspace stored by ResumeStudio.",
        systemImage: "trash.fill",
        accent: resumeStore.document.accent.color,
        rows: [
          PremiumConfirmationRow(
            eyebrow: "WILL BE ERASED",
            title: "Career intelligence",
            detail: "Evidence, contacts, offers, reviews and practice history",
            systemImage: "brain.head.profile",
            tone: .destructive
          ),
          PremiumConfirmationRow(
            eyebrow: "WILL BE KEPT",
            title: "Résumé documents",
            detail: "Your saved résumé versions remain available",
            systemImage: "doc.text.fill",
            tone: .accent
          ),
        ],
        safetyNote: "Résumé documents are not affected. Erased career intelligence cannot be recovered.",
        confirmTitle: "Erase career intelligence",
        onConfirm: {
          careerStore.resetCareerIntelligence()
          confirmsReset = false
        },
        onCancel: { confirmsReset = false }
      )
      .premiumConfirmationPresentation()
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
