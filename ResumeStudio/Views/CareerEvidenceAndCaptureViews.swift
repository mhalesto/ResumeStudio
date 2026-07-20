import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct EvidenceVaultView: View {
  @EnvironmentObject private var resumeStore: ResumeStore
  @EnvironmentObject private var careerStore: CareerIntelligenceStore
  @State private var editingItem: CareerEvidence?
  @State private var attestingItem: CareerEvidence?
  @State private var importMessage: String?
  @State private var filter: CareerEvidenceKind?

  private var visibleEvidence: [CareerEvidence] {
    guard let filter else { return careerStore.evidence }
    return careerStore.evidence.filter { $0.kind == filter }
  }

  var body: some View {
    List {
      Section {
        VaultHero(
          verifiedCount: careerStore.verifiedEvidence.count,
          totalCount: careerStore.evidence.count,
          accent: resumeStore.document.accent.color
        )
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
      }

      Section {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            filterChip("All", value: nil)
            ForEach(CareerEvidenceKind.allCases) { kind in filterChip(kind.title, value: kind) }
          }
          .padding(.vertical, 2)
        }
      }

      Section("Verified career evidence") {
        if visibleEvidence.isEmpty {
          ContentUnavailableView(
            "Your evidence vault is empty",
            systemImage: "checkmark.seal",
            description: Text("Import verified facts from your résumé or add an achievement yourself.")
          )
        }
        ForEach(visibleEvidence) { item in
          Button { editingItem = item } label: {
            EvidenceRow(
              item: item,
              attestation: careerStore.attestation(for: item.id),
              accent: resumeStore.document.accent.color)
          }
          .buttonStyle(.plain)
          .swipeActions(edge: .leading) {
            Button {
              attestingItem = item
            } label: {
              Label("Ask a referee", systemImage: "person.badge.shield.checkmark")
            }
            .tint(.green)
          }
        }
        .onDelete { offsets in
          let ids = Set(offsets.compactMap { index in
            visibleEvidence.indices.contains(index) ? visibleEvidence[index].id : nil
          })
          careerStore.deleteEvidence(ids: ids)
        }
      }

      Section {
        Button("Import from active résumé", systemImage: "arrow.down.doc.fill") { importFromResume() }
        Text("Imported facts are marked verified because they already appear in your saved résumé. You can edit or unverify any item.")
          .font(.caption).foregroundStyle(Theme.mutedInk)
      }
    }
    .navigationTitle("Evidence Vault")
    .toolbar {
      Button("Add evidence", systemImage: "plus") {
        editingItem = CareerEvidence(
          kind: .achievement, title: "", detail: "", source: "", tags: [], isVerified: false
        )
      }
    }
    .sheet(item: $editingItem) { item in
      EvidenceEditorView(item: item) { careerStore.upsert($0) }
    }
    .sheet(item: $attestingItem) { item in
      EvidenceAttestationView(evidence: item)
    }
    .alert("Evidence imported", isPresented: Binding(
      get: { importMessage != nil }, set: { if !$0 { importMessage = nil } }
    )) { Button("Done", role: .cancel) { importMessage = nil } } message: {
      Text(importMessage ?? "")
    }
  }

  private func filterChip(_ title: LocalizedStringResource, value: CareerEvidenceKind?) -> some View {
    Button(title) { withAnimation(.easeInOut(duration: 0.2)) { filter = value } }
      .font(.caption.weight(.semibold))
      .foregroundStyle(filter == value ? Color.white : Theme.ink)
      .padding(.horizontal, 13).padding(.vertical, 8)
      .background(filter == value ? resumeStore.document.accent.color : Theme.muted, in: Capsule())
  }

  private func importFromResume() {
    let count = careerStore.importEvidence(
      from: resumeStore.document,
      resumeID: resumeStore.activeResumeID,
      sourceTitle: resumeStore.activeDraft?.title ?? "Active résumé"
    )
    importMessage = count == 0
      ? "Your current résumé evidence is already in the vault."
      : "Added \(count) verified item\(count == 1 ? "" : "s") from your active résumé."
  }
}

private struct VaultHero: View {
  let verifiedCount: Int
  let totalCount: Int
  let accent: Color
  var body: some View {
    ZStack(alignment: .bottomLeading) {
      LinearGradient(colors: [Theme.heroTop, Theme.heroBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
      Circle().fill(accent.opacity(0.3)).frame(width: 190, height: 190).blur(radius: 38).offset(x: 150, y: -60)
      Image(systemName: "checkmark.seal.fill")
        .font(.system(size: 100, weight: .thin)).foregroundStyle(accent.opacity(0.24))
        .offset(x: 235, y: -30)
      VStack(alignment: .leading, spacing: 7) {
        Text("THE FACTS BEHIND YOUR STORY").eyebrow().foregroundStyle(accent)
        Text("Your career memory")
          .font(Theme.display(31)).foregroundStyle(Theme.heroInk)
        Text("\(verifiedCount) verified · \(totalCount) total")
          .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.heroMutedInk)
      }.padding(22)
    }
    .frame(height: 190)
    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
  }
}

private struct EvidenceRow: View {
  let item: CareerEvidence
  /// A referee's answer, when one has been asked for. Kept separate from
  /// `item.isVerified`, which only means the owner ticked it themselves.
  let attestation: EvidenceAttestation?
  let accent: Color
  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      ZStack {
        RoundedRectangle(cornerRadius: 12).fill(accent.opacity(0.12))
        Image(systemName: item.kind.systemImage).foregroundStyle(accent)
      }.frame(width: 42, height: 42)
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(item.title.nilIfBlank ?? String(localized: item.kind.title)).font(.headline).foregroundStyle(Theme.ink)
          if item.isVerified { Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(.green) }
        }
        Text(item.detail).font(.subheadline).foregroundStyle(Theme.inkSoft).lineLimit(3)
        if !item.source.isBlank { Text(item.source).font(.caption).foregroundStyle(Theme.mutedInk) }
        if let attestation {
          Label(
            attestation.isConfirmed
              ? attestation.attributionText
              : String(localized: attestation.status.title),
            systemImage: attestation.status.systemImage
          )
          .font(.caption.weight(.semibold))
          .foregroundStyle(attestation.isConfirmed ? .green : Theme.mutedInk)
        }
      }
      Spacer(minLength: 0)
    }.padding(.vertical, 4)
  }
}

private struct EvidenceEditorView: View {
  @Environment(\.dismiss) private var dismiss
  @State var item: CareerEvidence
  let onSave: (CareerEvidence) -> Void
  @State private var isImportingSource = false
  @State private var sourceError: String?

  var body: some View {
    NavigationStack {
      Form {
        Section("Evidence") {
          Picker("Type", selection: $item.kind) {
            ForEach(CareerEvidenceKind.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
          }
          TextField("Short title", text: $item.title)
          TextField("What happened, what you did, and the result", text: $item.detail, axis: .vertical)
            .lineLimit(4...10)
          TextField("Source — role, project, certificate…", text: $item.source)
          TextField("Source web link", text: Binding(
            get: { item.sourceURL ?? "" }, set: { item.sourceURL = $0.nilIfBlank }
          )).textInputAutocapitalization(.never).keyboardType(.URL)
          Button("Attach source file", systemImage: "paperclip") { isImportingSource = true }
          if let file = item.sourceFileName { Label(file, systemImage: "doc.fill").font(.caption) }
          if let sourceError { Label(sourceError, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange) }
          TextField("Tags separated by commas", text: Binding(
            get: { item.tags.joined(separator: ", ") },
            set: { item.tags = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
          ))
        }
        Section {
          Toggle("I have verified this fact", isOn: $item.isVerified)
          Text("Only verified evidence is supplied to AI writing tools as an established fact.")
            .font(.caption).foregroundStyle(Theme.mutedInk)
        }
      }
      .navigationTitle("Career evidence")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { onSave(item); dismiss() }.disabled(item.title.isBlank && item.detail.isBlank)
        }
      }
      .fileImporter(isPresented: $isImportingSource, allowedContentTypes: [.pdf, .data, .image, .plainText]) { result in
        do {
          let url = try result.get()
          let stored = try EvidenceSourceService.importFile(url, evidenceID: item.id)
          item.sourceFileName = url.lastPathComponent
          item.sourceURL = stored.absoluteString
          sourceError = nil
        } catch { sourceError = error.localizedDescription }
      }
    }
  }
}

struct JobCaptureView: View {
  @EnvironmentObject private var resumeStore: ResumeStore
  @EnvironmentObject private var applicationStore: ApplicationStore
  @Environment(\.dismiss) private var dismiss
  @State private var sourceURL = ""
  @State private var content = ""
  @State private var captured: AIJobCapture?
  @State private var isWorking = false
  @State private var errorMessage: String?
  @State private var didCreate = false
  @State private var provider: ProductInsightSource?

  private var duplicateApplication: JobApplication? {
    guard let captured else { return nil }
    return applicationStore.applications.first { existing in
      (!sourceURL.isBlank && existing.sourceURL.caseInsensitiveCompare(sourceURL) == .orderedSame)
        || (!captured.role.isBlank && !captured.company.isBlank
          && existing.role.caseInsensitiveCompare(captured.role) == .orderedSame
          && existing.company.caseInsensitiveCompare(captured.company) == .orderedSame)
    }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        PremiumFeatureHero(
          eyebrow: "ONE-TAP OPPORTUNITY CAPTURE",
          title: "Keep the job before it disappears.",
          subtitle: "Paste a link, paste an advert or upload the employer's job pack. ResumeStudio turns it into a connected application.",
          icon: "square.and.arrow.down.fill",
          accent: resumeStore.document.accent.color
        )

        VStack(alignment: .leading, spacing: 13) {
          Label("Job link", systemImage: "link").font(.headline)
          TextField("https://company.com/jobs/…", text: $sourceURL)
            .textInputAutocapitalization(.never).keyboardType(.URL).textFieldStyle(.roundedBorder)
          HStack {
            Button("Paste", systemImage: "doc.on.clipboard") {
              sourceURL = UIPasteboard.general.string ?? ""
            }
            Spacer()
            if !sourceURL.isBlank {
              Button("Load page", systemImage: "arrow.down.circle") { Task { await loadPage() } }
            }
          }.font(.subheadline.weight(.semibold))
        }.padding(18).cardSurface()

        VStack(alignment: .leading, spacing: 12) {
          Label("Advert or job specification", systemImage: "doc.text.fill").font(.headline)
          TextEditor(text: $content)
            .frame(minHeight: 180)
            .padding(8)
            .background(Theme.muted, in: RoundedRectangle(cornerRadius: 14))
          JobSpecImportButton(jobDescription: $content, errorMessage: $errorMessage)
        }.padding(18).cardSurface()

        Button { Task { await analyse() } } label: {
          HStack {
            if isWorking { ProgressView().tint(.white) }
            else { Image(systemName: "sparkles") }
            Text(isWorking ? "Reading opportunity…" : "Capture this job")
          }
          .font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 16)
          .background(resumeStore.document.accent.color, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).count < 40 || isWorking)

        if captured != nil {
          if let provider { AIRouteBadge(provider: provider) }
          JobCaptureReviewCard(result: Binding(
            get: { captured! },
            set: { captured = $0 }
          ), accent: resumeStore.document.accent.color)
        }

        if let captured {
          Button { createApplication(captured) } label: {
            Label(
              didCreate ? "Application saved" : duplicateApplication == nil ? "Create connected application" : "Already in your pipeline",
              systemImage: didCreate ? "checkmark.circle.fill" : duplicateApplication == nil ? "rectangle.3.group.fill" : "exclamationmark.circle.fill"
            )
              .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
          }
          .buttonStyle(.borderedProminent).tint(duplicateApplication == nil ? .green : .orange)
          .disabled(didCreate || duplicateApplication != nil)
        }

        if let errorMessage { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
      }
      .padding(20).padding(.bottom, 40).frame(maxWidth: 700).frame(maxWidth: .infinity)
    }
    .background(Theme.paper)
    .navigationTitle("Capture a Job")
    .navigationBarTitleDisplayMode(.inline)
    .task { await consumeSharedCaptureIfNeeded() }
    .onReceive(NotificationCenter.default.publisher(for: .aiRequestDidComplete)) { note in
      guard let raw = note.userInfo?["provider"] as? String else { return }
      provider = ProductInsightSource(rawValue: raw)
    }
    .sensoryFeedback(.success, trigger: didCreate)
  }

  @MainActor private func consumeSharedCaptureIfNeeded() async {
    guard let shared = SharedJobInbox.consume() else { return }
    sourceURL = shared.url
    content = shared.text
    if content.trimmingCharacters(in: .whitespacesAndNewlines).count < 40, !sourceURL.isBlank {
      await loadPage()
    }
  }

  @MainActor private func loadPage() async {
    isWorking = true; errorMessage = nil
    do { content = try await JobCaptureService.text(from: sourceURL) }
    catch { errorMessage = error.localizedDescription }
    isWorking = false
  }

  @MainActor private func analyse() async {
    isWorking = true; errorMessage = nil; didCreate = false
    do { captured = try await ResumeAIService.shared.captureJob(content: content, sourceURL: sourceURL) }
    catch { errorMessage = error.localizedDescription }
    isWorking = false
  }

  private func createApplication(_ result: AIJobCapture) {
    guard duplicateApplication == nil else { return }
    let deadline = Self.parseDate(result.closingDate)
    let application = JobApplication(
      company: result.company,
      role: result.role,
      jobDescription: result.jobDescription,
      sourceURL: result.sourceURL.nilIfBlank ?? sourceURL,
      status: .saved,
      notes: [result.location, result.salary, result.closingDate].filter { !$0.isBlank }.joined(separator: " · "),
      baseResumeID: resumeStore.activeResumeID,
      capturedOpportunity: CapturedJobSnapshot(
        location: result.location, salary: result.salary, closingDate: result.closingDate,
        responsibilities: result.responsibilities, requirements: result.requirements,
        warnings: result.warnings, originalContent: content
      ),
      deadline: deadline,
      activities: [ApplicationActivity(
        kind: .captured, title: "Opportunity captured",
        detail: [result.role, result.company].filter { !$0.isBlank }.joined(separator: " at ")
      )]
    )
    applicationStore.add(application)
    ProductInsights.record(.jobCaptured, once: true)
    didCreate = true
    NotificationCenter.default.post(name: .openHomeRoute, object: HomeRoute.applicationPacket(application.id))
  }

  private static func parseDate(_ value: String) -> Date? {
    let formats = ["yyyy-MM-dd", "d MMMM yyyy", "d MMM yyyy", "MMMM d, yyyy", "MMM d, yyyy"]
    for format in formats {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.dateFormat = format
      if let date = formatter.date(from: value.trimmingCharacters(in: .whitespacesAndNewlines)) { return date }
    }
    return nil
  }
}

private struct JobCaptureReviewCard: View {
  @Binding var result: AIJobCapture
  let accent: Color
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label("Review every extracted field", systemImage: "slider.horizontal.3")
        .font(.headline).foregroundStyle(accent)
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 4) {
          TextField("Role", text: $result.role).font(.title3.bold())
          TextField("Company", text: $result.company).foregroundStyle(Theme.mutedInk)
        }
        Spacer()
        Image(systemName: "checkmark.seal.fill").font(.title2).foregroundStyle(accent)
      }
      TextField("Location", text: $result.location)
      TextField("Salary or range", text: $result.salary)
      TextField("Closing date", text: $result.closingDate)
      TextField("Clean job description", text: $result.jobDescription, axis: .vertical).lineLimit(5...12)
      if !result.responsibilities.isEmpty {
        Text("Key responsibilities").font(.headline)
        ForEach(result.responsibilities.indices, id: \.self) { index in
          TextField("Responsibility", text: $result.responsibilities[index], axis: .vertical)
        }
      }
      if !result.requirements.isEmpty {
        Text("Requirements").font(.headline)
        ForEach(result.requirements.indices, id: \.self) { index in
          TextField("Requirement", text: $result.requirements[index], axis: .vertical)
        }
      }
      ForEach(result.warnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
    }.padding(19).cardSurface()
  }
}

struct AIChangeReviewView: View {
  @EnvironmentObject private var resumeStore: ResumeStore
  @EnvironmentObject private var careerStore: CareerIntelligenceStore
  @State private var suggestions: AITextAlternatives?
  @State private var selectedText: String?
  @State private var isLoading = false
  @State private var errorMessage: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        PremiumFeatureHero(
          eyebrow: "TRANSPARENT AI",
          title: "Nothing changes behind your back.",
          subtitle: "See the original, the proposed wording, the evidence behind it and every claim that needs your confirmation.",
          icon: "arrow.left.arrow.right.circle.fill",
          accent: resumeStore.document.accent.color
        )

        VStack(alignment: .leading, spacing: 10) {
          Label("Current profile", systemImage: "doc.text").font(.headline)
          Text(resumeStore.document.professionalProfile.nilIfBlank ?? "No professional profile yet.")
            .font(.subheadline).foregroundStyle(Theme.inkSoft)
        }.padding(18).cardSurface()

        if !careerStore.aiRevisions.isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            Label("Reversible AI history", systemImage: "clock.arrow.circlepath").font(.headline)
            ForEach(careerStore.aiRevisions.prefix(5)) { revision in
              VStack(alignment: .leading, spacing: 7) {
                HStack {
                  Text(revision.field).font(.subheadline.bold())
                  Spacer()
                  Text(revision.status == .applied ? "Applied" : "Reverted")
                    .font(.caption.bold()).foregroundStyle(revision.status == .applied ? .green : .orange)
                }
                Text(revision.after).font(.caption).foregroundStyle(Theme.inkSoft).lineLimit(3)
                if revision.status == .applied {
                  Button("Restore previous wording", systemImage: "arrow.uturn.backward") { revert(revision) }
                    .font(.caption.bold())
                }
              }
              if revision.id != careerStore.aiRevisions.prefix(5).last?.id { Divider() }
            }
          }.padding(18).cardSurface()
        }

        Button { Task { await generate() } } label: {
          Label(isLoading ? "Generating reviewed options…" : "Generate sourced alternatives", systemImage: "sparkles")
            .font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 15)
            .background(resumeStore.document.accent.color, in: Capsule())
        }.buttonStyle(.plain).disabled(isLoading)

        if let suggestions {
          ForEach(Array(suggestions.alternatives.enumerated()), id: \.offset) { index, option in
            AIChangeOptionCard(
              number: index + 1,
              original: resumeStore.document.professionalProfile,
              proposed: option,
              isSelected: selectedText == option,
              accent: resumeStore.document.accent.color
            ) { selectedText = option }
          }

          VStack(alignment: .leading, spacing: 10) {
            Label("Evidence consulted", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(.green)
            if careerStore.verifiedEvidence.isEmpty {
              Text("No Evidence Vault items yet. This suggestion uses only the active résumé.")
                .font(.caption).foregroundStyle(Theme.mutedInk)
            } else {
              ForEach(careerStore.verifiedEvidence.prefix(8)) { item in
                HStack(alignment: .top) {
                  Image(systemName: item.kind.systemImage).foregroundStyle(resumeStore.document.accent.color).frame(width: 20)
                  VStack(alignment: .leading) {
                    Text(item.title).font(.subheadline.weight(.semibold))
                    Text(item.source).font(.caption).foregroundStyle(Theme.mutedInk)
                  }
                }
              }
            }
            if let sentenceSources = suggestions.sentenceSources, !sentenceSources.isEmpty {
              Divider()
              Text("Sentence-level provenance").font(.headline)
              ForEach(sentenceSources.prefix(12)) { item in
                VStack(alignment: .leading, spacing: 3) {
                  Text(item.sentence).font(.caption.weight(.semibold))
                  Label(item.source, systemImage: "link.circle.fill").font(.caption2).foregroundStyle(Theme.mutedInk)
                }
              }
            }
          }.padding(18).cardSurface()

          if !suggestions.claimsRequiringConfirmation.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
              Label("Confirm before applying", systemImage: "exclamationmark.shield.fill").font(.headline).foregroundStyle(.orange)
              ForEach(suggestions.claimsRequiringConfirmation, id: \.self) { Text("• \($0)").font(.subheadline) }
            }.padding(18).cardSurface()
          }

          Button("Apply selected change", systemImage: "checkmark.circle.fill") { apply() }
            .buttonStyle(.borderedProminent).tint(.green).frame(maxWidth: .infinity)
            .disabled(selectedText == nil)
        }

        if let errorMessage { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
      }.padding(20).padding(.bottom, 40).frame(maxWidth: 720).frame(maxWidth: .infinity)
    }
    .background(Theme.paper)
    .navigationTitle("Review AI Changes")
    .navigationBarTitleDisplayMode(.inline)
  }

  @MainActor private func generate() async {
    isLoading = true; errorMessage = nil; selectedText = nil
    do { suggestions = try await ResumeAIService.shared.writeProfile(for: resumeStore.document, evidence: careerStore.verifiedEvidence) }
    catch { errorMessage = error.localizedDescription }
    isLoading = false
  }

  private func apply() {
    guard let selectedText else { return }
    let before = resumeStore.document.professionalProfile
    resumeStore.document.professionalProfile = selectedText
    careerStore.addRevision(AIRevision(
      resumeID: resumeStore.activeResumeID,
      field: "Professional profile",
      before: before,
      after: selectedText,
      evidenceIDs: careerStore.verifiedEvidence.map(\.id),
      evidenceLabels: suggestions?.evidenceSources ?? careerStore.verifiedEvidence.prefix(8).map(\.title),
      claimsRequiringConfirmation: suggestions?.claimsRequiringConfirmation ?? []
    ))
    self.selectedText = nil
  }

  private func revert(_ revision: AIRevision) {
    guard revision.field == "Professional profile" else { return }
    resumeStore.document.professionalProfile = revision.before
    careerStore.markRevisionReverted(revision.id)
  }
}

private struct AIChangeOptionCard: View {
  let number: Int
  let original: String
  let proposed: String
  let isSelected: Bool
  let accent: Color
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("Option \(number)").font(.headline).foregroundStyle(Theme.ink)
          Spacer()
          Image(systemName: isSelected ? "checkmark.circle.fill" : "circle").foregroundStyle(isSelected ? accent : Theme.mutedInk)
        }
        Text(proposed).font(.subheadline).foregroundStyle(Theme.inkSoft).multilineTextAlignment(.leading)
        HStack(spacing: 8) {
          Label("Before", systemImage: "minus.circle").foregroundStyle(.red)
          Image(systemName: "arrow.right").foregroundStyle(Theme.mutedInk)
          Label("After", systemImage: "plus.circle").foregroundStyle(.green)
        }.font(.caption.weight(.semibold))
      }
      .padding(18)
      .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
      .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(isSelected ? accent : Theme.hairline, lineWidth: isSelected ? 2 : 1) }
    }.buttonStyle(.plain)
  }
}

struct PremiumFeatureHero: View {
  let eyebrow: LocalizedStringResource
  let title: LocalizedStringResource
  let subtitle: String
  let icon: String
  let accent: Color
  var body: some View {
    ZStack(alignment: .bottomLeading) {
      LinearGradient(colors: [Theme.heroTop, Theme.heroBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
      Circle().fill(accent.opacity(0.34)).frame(width: 220, height: 220).blur(radius: 42).offset(x: 170, y: -70)
      Image(systemName: icon).font(.system(size: 106, weight: .thin)).foregroundStyle(accent.opacity(0.22)).offset(x: 220, y: -28)
      VStack(alignment: .leading, spacing: 8) {
        Text(eyebrow).eyebrow().foregroundStyle(accent)
        Text(title).font(Theme.display(31)).foregroundStyle(Theme.heroInk).frame(maxWidth: 380, alignment: .leading)
        Text(subtitle).font(.subheadline).foregroundStyle(Theme.heroMutedInk).frame(maxWidth: 400, alignment: .leading)
      }.padding(22)
    }
    .frame(minHeight: 225)
    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(Color.white.opacity(0.08)) }
  }
}

struct FlowTagCloud: View {
  let items: [String]
  let accent: Color
  var body: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 7)], alignment: .leading, spacing: 7) {
      ForEach(items, id: \.self) { item in
        Text(item).font(.caption.weight(.semibold)).foregroundStyle(accent)
          .padding(.horizontal, 10).padding(.vertical, 7)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(accent.opacity(0.1), in: Capsule())
      }
    }
  }
}
