import SwiftUI

struct AITextSuggestionsView: View {
  let title: String
  let guidance: String
  let load: () async throws -> AITextAlternatives
  let onApply: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var result: AITextAlternatives?
  @State private var errorMessage: String?
  @State private var isOffline = false
  @State private var isLoading = true
  @State private var provider: ProductInsightSource?

  var body: some View {
    NavigationStack {
      Group {
        if isLoading {
          ProgressView("Preparing suggestions…")
        } else if let errorMessage {
          AIErrorUnavailableView(message: errorMessage, isOffline: isOffline) {
            Task { await generate() }
          }
        } else if let result {
          List {
            Section {
              Text(guidance)
                .font(.footnote)
                .foregroundStyle(Theme.mutedInk)
              if let provider { AIRouteBadge(provider: provider) }
            }

            Section("Choose a version") {
              ForEach(Array(result.alternatives.enumerated()), id: \.offset) { _, alternative in
                Button {
                  onApply(alternative)
                  dismiss()
                } label: {
                  VStack(alignment: .leading, spacing: 10) {
                    Text(alternative)
                      .foregroundStyle(Theme.ink)
                    Label("Use this version", systemImage: "checkmark.circle.fill")
                      .font(.caption.weight(.semibold))
                      .foregroundStyle(.tint)
                  }
                  .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
              }
            }

            if !result.claimsRequiringConfirmation.isEmpty {
              Section("Please verify") {
                ForEach(result.claimsRequiringConfirmation, id: \.self) { claim in
                  Label(claim, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                }
              }
            }
          }
        }
      }
      .background(Theme.paper)
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
      .task { await generate() }
      .onReceive(NotificationCenter.default.publisher(for: .aiRequestDidComplete)) { note in
        guard let raw = note.userInfo?["provider"] as? String else { return }
        provider = ProductInsightSource(rawValue: raw)
      }
    }
  }

  @MainActor
  private func generate() async {
    isLoading = true
    errorMessage = nil
    do {
      result = try await load()
    } catch {
      let aiError = ResumeAIError.from(error)
      errorMessage = aiError.localizedDescription
      isOffline = aiError == .offline
    }
    isLoading = false
  }
}

struct AICompetencySuggestionsView: View {
  let document: ResumeDocument
  let onApply: ([String]) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var result: AICompetencySuggestions?
  @State private var selected: Set<String> = []
  @State private var errorMessage: String?
  @State private var isOffline = false
  @State private var isLoading = true
  @State private var provider: ProductInsightSource?

  var body: some View {
    NavigationStack {
      Group {
        if isLoading {
          ProgressView("Finding supported skills…")
        } else if let errorMessage {
          AIErrorUnavailableView(message: errorMessage, isOffline: isOffline) {
            Task { await generate() }
          }
        } else if let result {
          List {
            if !result.rationale.isBlank {
              Section {
                Text(result.rationale)
                  .font(.footnote)
                  .foregroundStyle(Theme.mutedInk)
              }
            }
            if let provider {
              Section("Processing") { AIRouteBadge(provider: provider) }
            }
            Section("Select competencies") {
              ForEach(result.suggestions, id: \.self) { suggestion in
                Button {
                  if selected.contains(suggestion) {
                    selected.remove(suggestion)
                  } else {
                    selected.insert(suggestion)
                  }
                } label: {
                  HStack {
                    Text(suggestion).foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: selected.contains(suggestion) ? "checkmark.circle.fill" : "circle")
                      .foregroundStyle(selected.contains(suggestion) ? Color.accentColor : Theme.mutedInk)
                  }
                }
                .buttonStyle(.plain)
              }
            }
          }
        }
      }
      .navigationTitle("AI Competencies")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Add \(selected.count)") {
            onApply(Array(selected).sorted())
            dismiss()
          }
          .disabled(selected.isEmpty)
        }
      }
      .task { await generate() }
      .onReceive(NotificationCenter.default.publisher(for: .aiRequestDidComplete)) { note in
        guard let raw = note.userInfo?["provider"] as? String else { return }
        provider = ProductInsightSource(rawValue: raw)
      }
    }
  }

  @MainActor
  private func generate() async {
    isLoading = true
    errorMessage = nil
    do {
      let response = try await ResumeAIService.shared.suggestCompetencies(for: document)
      result = response
      selected = Set(response.suggestions)
    } catch {
      let aiError = ResumeAIError.from(error)
      errorMessage = aiError.localizedDescription
      isOffline = aiError == .offline
    }
    isLoading = false
  }
}

/// A calm, offline-aware failure state shared by the AI surfaces: a network drop
/// gets the "you're offline" treatment and a retry, anything else the generic one.
struct AIErrorUnavailableView: View {
  let message: String
  let isOffline: Bool
  var retry: (() -> Void)?

  var body: some View {
    ContentUnavailableView {
      Label(
        isOffline ? "You’re offline" : "Something went wrong",
        systemImage: isOffline ? "wifi.slash" : "exclamationmark.triangle"
      )
    } description: {
      Text(message)
    } actions: {
      if let retry {
        Button("Try again", action: retry)
          .buttonStyle(.borderedProminent)
      }
    }
  }
}

struct JobTargetingView: View {
  @EnvironmentObject private var store: ResumeStore
  @EnvironmentObject private var applicationStore: ApplicationStore
  @EnvironmentObject private var purchases: PurchaseManager
  @EnvironmentObject private var network: NetworkMonitor

  @State private var role = ""
  @State private var company = ""
  @State private var sourceURL = ""
  @State private var jobDescription = ""
  @State private var allowLimitedAdvert = false
  @State private var analysis: AIJobMatchAnalysis?
  @State private var tailored: AITailoredResume?
  @State private var applicationID: UUID?
  @State private var baseResumeID: UUID?
  @State private var isLoading = false
  @State private var errorMessage: String?
  @FocusState private var isJobDescriptionFocused: Bool

  private let existingApplicationID: UUID?

  init(applicationID: UUID? = nil) {
    existingApplicationID = applicationID
    _applicationID = State(initialValue: applicationID)
  }

  private var quality: JobDescriptionQuality { JobDescriptionAnalyzer.analyze(jobDescription) }
  private var canRun: Bool {
    !jobDescription.isBlank && (quality.isDetailedEnough || allowLimitedAdvert)
  }

  var body: some View {
    Form {
      Section("Job") {
        TextField("Role", text: $role)
        TextField("Company", text: $company)
        TextField("Source URL (optional)", text: $sourceURL)
          .textInputAutocapitalization(.never).keyboardType(.URL)
      }

      Section {
        JobSpecImportButton(jobDescription: $jobDescription, errorMessage: $errorMessage)
        TextEditor(text: $jobDescription)
          .frame(minHeight: 190)
          .focused($isJobDescriptionFocused)
          .accessibilityLabel("Job description")
      } header: { Text("Job description") }
        footer: { Text("Upload or paste the full advert, then edit the extracted text if needed. Contact details, references and your photo are never sent.") }

      Section("Advert quality") {
        HStack {
          Label(quality.isDetailedEnough ? "Ready to analyse" : "More detail recommended", systemImage: quality.isDetailedEnough ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .foregroundStyle(quality.isDetailedEnough ? .green : .orange)
          Spacer(); Text("\(quality.score)/100").monospacedDigit().foregroundStyle(Theme.mutedInk)
        }
        ForEach(quality.blockingIssues + quality.suggestions, id: \.self) {
          Text($0).font(.footnote).foregroundStyle(Theme.mutedInk)
        }
        if !quality.isDetailedEnough {
          Toggle("Continue with limited advert", isOn: $allowLimitedAdvert)
        }
      }

      Section("AI actions") {
        Button { dismissKeyboard(); Task { await analyze() } } label: {
          Label("Review job match", systemImage: "checklist")
        }.disabled(!canRun || isLoading || !network.isOnline)
        Button { dismissKeyboard(); Task { await tailor() } } label: {
          Label("Create tailored version", systemImage: "wand.and.stars")
        }.disabled(!canRun || isLoading || !network.isOnline)
        if isLoading { ProgressView("Working from your résumé evidence…") }
        if !network.isOnline {
          Label("You’re offline — reconnect to run AI actions.", systemImage: "wifi.slash")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }

      if let errorMessage {
        Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
      }
      if let analysis { analysisSections(analysis) }
    }
    .supportsKeyboardDismissal()
    .scrollContentBackground(.hidden)
    .background(Theme.paper)
    .navigationTitle("Target a job")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: loadExistingApplication)
    .sheet(isPresented: Binding(
      get: { tailored != nil },
      set: { if !$0 { tailored = nil } }
    )) {
      if let tailored {
        TailoredResumeReviewView(
          original: store.document,
          proposed: tailored,
          role: role,
          company: company
        ) { reviewedDocument in
          let versionID = store.createResume(title: versionTitle, from: reviewedDocument)
          upsertApplication(tailoredResumeID: versionID)
          self.tailored = nil
        }
      }
    }
  }

  private var versionTitle: String {
    let target = [role, company].filter { !$0.isBlank }.joined(separator: " — ")
    return target.isBlank ? "Tailored Résumé" : target
  }

  private func loadExistingApplication() {
    guard let existingApplicationID,
      let application = applicationStore.applications.first(where: { $0.id == existingApplicationID }),
      jobDescription.isBlank
    else { return }
    role = application.role
    company = application.company
    sourceURL = application.sourceURL
    jobDescription = application.jobDescription
    analysis = application.matchAnalysis
    baseResumeID = application.baseResumeID
  }

  private func dismissKeyboard() { isJobDescriptionFocused = false; AppKeyboard.dismiss() }

  @ViewBuilder private func analysisSections(_ value: AIJobMatchAnalysis) -> some View {
    Section("Match summary") { Text(value.summary) }
    keywordSection(title: "Demonstrated matches", values: value.matchedKeywords, color: .green)
    keywordSection(title: "Missing or unproven", values: value.missingKeywords, color: .orange)
    Section("Recommended edits") {
      ForEach(value.recommendations, id: \.self) { Label($0, systemImage: "arrow.right.circle.fill") }
    }
    if !value.claimsRequiringConfirmation.isEmpty {
      Section("Please verify") {
        ForEach(value.claimsRequiringConfirmation, id: \.self) { Label($0, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
      }
    }
  }

  @ViewBuilder private func keywordSection(title: String, values: [String], color: Color) -> some View {
    if !values.isEmpty {
      Section(title) { ForEach(values, id: \.self) { Label($0, systemImage: "circle.fill").foregroundStyle(color) } }
    }
  }

  @MainActor private func analyze() async {
    isLoading = true; errorMessage = nil
    if baseResumeID == nil { baseResumeID = store.activeResumeID }
    do {
      analysis = try await ResumeAIService.shared.analyzeJob(document: store.document, jobDescription: jobDescription)
      upsertApplication(tailoredResumeID: nil)
    } catch { errorMessage = error.localizedDescription }
    isLoading = false
  }

  @MainActor private func tailor() async {
    guard purchases.canCreateResume(currentCount: store.resumes.count) else {
      purchases.requestPlans()
      return
    }
    isLoading = true; errorMessage = nil
    if baseResumeID == nil { baseResumeID = store.activeResumeID }
    do {
      tailored = try await ResumeAIService.shared.tailorResume(document: store.document, jobDescription: jobDescription)
    } catch { errorMessage = error.localizedDescription }
    isLoading = false
  }

  private func upsertApplication(tailoredResumeID: UUID?) {
    if let applicationID, var existing = applicationStore.applications.first(where: { $0.id == applicationID }) {
      existing.company = company; existing.role = role; existing.jobDescription = jobDescription
      existing.sourceURL = sourceURL; existing.matchAnalysis = analysis
      if let tailoredResumeID { existing.tailoredResumeID = tailoredResumeID }
      applicationStore.update(existing)
    } else {
      let application = JobApplication(
        company: company, role: role, jobDescription: jobDescription, sourceURL: sourceURL,
        status: .saved, notes: "", baseResumeID: baseResumeID ?? store.activeResumeID,
        tailoredResumeID: tailoredResumeID, matchAnalysis: analysis, interviewPlan: nil
      )
      applicationID = application.id
      applicationStore.add(application)
    }
  }
}

private struct TailoredResumeReviewView: View {
  let original: ResumeDocument
  let proposed: AITailoredResume
  let role: String
  let company: String
  let onApply: (ResumeDocument) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var useHeadline = true
  @State private var useProfile = true
  @State private var useCompetencies = true
  @State private var selectedExperienceIDs: Set<String> = []

  var body: some View {
    NavigationStack {
      List {
        Section {
          Text("Choose each change. Your original résumé stays untouched; accepted edits create a new version.")
            .font(.footnote).foregroundStyle(Theme.mutedInk)
        }
        changeSection("Headline", old: original.personal.headline, new: proposed.headline, isOn: $useHeadline)
        changeSection("Professional profile", old: original.professionalProfile, new: proposed.professionalProfile, isOn: $useProfile)
        changeSection("Competencies", old: original.competencies.joined(separator: " • "), new: proposed.competencies.joined(separator: " • "), isOn: $useCompetencies)
        Section("Experience highlights") {
          ForEach(proposed.experience) { rewrite in
            let originalEntry = original.experience.first { $0.id.uuidString == rewrite.id }
            Button {
              if selectedExperienceIDs.contains(rewrite.id) { selectedExperienceIDs.remove(rewrite.id) }
              else { selectedExperienceIDs.insert(rewrite.id) }
            } label: {
              VStack(alignment: .leading, spacing: 7) {
                HStack {
                  Image(systemName: selectedExperienceIDs.contains(rewrite.id) ? "checkmark.circle.fill" : "circle")
                  Text(originalEntry?.role.nilIfBlank ?? "Experience").fontWeight(.semibold)
                }
                Text(rewrite.highlights.joined(separator: "\n• ")).font(.caption).foregroundStyle(Theme.mutedInk)
              }
            }.buttonStyle(.plain)
          }
        }
        if !proposed.claimsRequiringConfirmation.isEmpty {
          Section("Verify before accepting") {
            ForEach(proposed.claimsRequiringConfirmation, id: \.self) { Label($0, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
          }
        }
      }
      .navigationTitle("Review changes")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Create version") { onApply(reviewedDocument); dismiss() }.fontWeight(.semibold)
        }
      }
      .onAppear { selectedExperienceIDs = Set(proposed.experience.map(\.id)) }
    }
  }

  private func changeSection(_ title: String, old: String, new: String, isOn: Binding<Bool>) -> some View {
    Section {
      Toggle("Use proposed change", isOn: isOn)
      DisclosureGroup("Current") { Text(old).font(.footnote).foregroundStyle(Theme.mutedInk) }
      Text(new).font(.footnote)
    } header: { Text(title) }
  }

  private var reviewedDocument: ResumeDocument {
    var document = original
    if useHeadline { document.personal.headline = proposed.headline }
    if useProfile { document.professionalProfile = proposed.professionalProfile }
    if useCompetencies { document.competencies = proposed.competencies }
    let rewrites = Dictionary(uniqueKeysWithValues: proposed.experience.map { ($0.id, $0.highlights) })
    for index in document.experience.indices {
      let id = document.experience[index].id.uuidString
      if selectedExperienceIDs.contains(id), let highlights = rewrites[id] { document.experience[index].highlights = highlights }
    }
    return document
  }
}
