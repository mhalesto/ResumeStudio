import SwiftUI

struct OutcomeReviewRequest: Identifiable {
  let applicationID: UUID
  var id: UUID { applicationID }
}

struct OutcomeReviewSheet: View {
  @EnvironmentObject private var applicationStore: ApplicationStore
  @EnvironmentObject private var resumeStore: ResumeStore
  @Environment(\.dismiss) private var dismiss

  let applicationID: UUID

  @State private var reason: ApplicationOutcomeReason = .noFeedback
  @State private var feedbackSource: OutcomeFeedbackSource = .none
  @State private var feedback = ""
  @State private var whatWorked = ""
  @State private var nextChange = ""
  @State private var wantsFollowUp = false
  @State private var followUpAt = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
  @State private var hasLoaded = false

  private var application: JobApplication? {
    applicationStore.applications.first { $0.id == applicationID }
  }

  private var accent: Color { resumeStore.document.accent.color }

  var body: some View {
    NavigationStack {
      ScrollView {
        if let application {
          VStack(alignment: .leading, spacing: 20) {
            OutcomeReviewHero(application: application, accent: accent)

            VStack(alignment: .leading, spacing: 13) {
              Label("What was the clearest signal?", systemImage: "waveform.path.ecg")
                .font(.headline)
              LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(reasonChoices(for: application.status)) { option in
                  Button { reason = option } label: {
                    HStack(spacing: 8) {
                      Image(systemName: option.systemImage)
                      Text(option.title).lineLimit(2)
                      Spacer(minLength: 0)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(reason == option ? Color.white : Theme.ink)
                    .padding(11)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .background(reason == option ? accent : Theme.muted, in: RoundedRectangle(cornerRadius: 14))
                  }
                  .buttonStyle(.plain)
                }
              }
            }
            .padding(18)
            .cardSurface()

            VStack(alignment: .leading, spacing: 13) {
              Label("What did you hear?", systemImage: "quote.bubble.fill").font(.headline)
              Picker("Feedback source", selection: $feedbackSource) {
                ForEach(OutcomeFeedbackSource.allCases) { Text($0.title).tag($0) }
              }
              .pickerStyle(.menu)
              TextField(
                "Paste or summarise the feedback (optional)", text: $feedback,
                axis: .vertical
              )
              .lineLimit(3...7)
              .padding(12)
              .background(Theme.muted, in: RoundedRectangle(cornerRadius: 13))
            }
            .padding(18)
            .cardSurface()

            VStack(alignment: .leading, spacing: 13) {
              Label("Keep the learning specific", systemImage: "lightbulb.max.fill").font(.headline)
              TextField("What worked?", text: $whatWorked, axis: .vertical)
                .lineLimit(2...5)
                .padding(12)
                .background(Theme.muted, in: RoundedRectangle(cornerRadius: 13))
              TextField("What will you test next?", text: $nextChange, axis: .vertical)
                .lineLimit(2...5)
                .padding(12)
                .background(Theme.muted, in: RoundedRectangle(cornerRadius: 13))
            }
            .padding(18)
            .cardSurface()

            VStack(alignment: .leading, spacing: 12) {
              Toggle("Schedule a follow-up", isOn: $wantsFollowUp)
                .font(.headline)
                .tint(accent)
              if wantsFollowUp {
                DatePicker(
                  "Follow up", selection: $followUpAt,
                  in: Date()..., displayedComponents: [.date, .hourAndMinute]
                )
              }
            }
            .padding(18)
            .cardSurface()

            Label(
              "Your notes stay in the private career workspace. Connected AI receives only the selected signal category and a redacted résumé—not this free-form feedback.",
              systemImage: "lock.shield.fill"
            )
            .font(.caption)
            .foregroundStyle(Theme.mutedInk)
            .padding(.horizontal, 4)
          }
          .padding(20)
          .padding(.bottom, 34)
          .frame(maxWidth: 720)
          .frame(maxWidth: .infinity)
        } else {
          ContentUnavailableView("Application not found", systemImage: "briefcase.circle")
            .padding(.top, 80)
        }
      }
      .background(Theme.paper)
      .navigationTitle("Review outcome")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save", action: save).fontWeight(.bold).disabled(application == nil)
        }
      }
      .onAppear(perform: load)
    }
  }

  private func reasonChoices(for status: JobApplicationStatus) -> [ApplicationOutcomeReason] {
    let positive: [ApplicationOutcomeReason] = [
      .strongRoleFit, .strongEvidence, .skillsMatch, .referralOrSource,
    ]
    let improvement: [ApplicationOutcomeReason] = [
      .profileUnclear, .evidenceTooWeak, .skillsGap, .experienceGap, .roleMismatch,
      .timingOrCompetition, .compensationOrLocation, .noFeedback, .other,
    ]
    return status == .rejected ? improvement + positive : positive + improvement
  }

  private func load() {
    guard !hasLoaded, let application else { return }
    hasLoaded = true
    if let review = application.currentOutcomeReview {
      reason = review.reason
      feedbackSource = review.feedbackSource
      feedback = review.feedback
      whatWorked = review.whatWorked
      nextChange = review.nextChange
      wantsFollowUp = review.followUpAt != nil
      followUpAt = review.followUpAt ?? followUpAt
    } else {
      switch application.status {
      case .interview: reason = .strongRoleFit
      case .offer: reason = .strongEvidence
      case .rejected: reason = .noFeedback
      default: break
      }
    }
  }

  private func save() {
    guard let application else { return }
    let review = ApplicationOutcomeReview(
      stage: application.status,
      reason: reason,
      feedbackSource: feedbackSource,
      feedback: feedback.trimmingCharacters(in: .whitespacesAndNewlines),
      whatWorked: whatWorked.trimmingCharacters(in: .whitespacesAndNewlines),
      nextChange: nextChange.trimmingCharacters(in: .whitespacesAndNewlines),
      followUpAt: wantsFollowUp ? followUpAt : nil,
      resumeID: application.resumeUsedForOutcome,
      packetID: application.packet?.id
    )
    applicationStore.saveOutcomeReview(review, for: application.id)
    dismiss()
  }
}

private struct OutcomeReviewHero: View {
  let application: JobApplication
  let accent: Color

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      LinearGradient(
        colors: [Theme.heroTop, Theme.heroBottom],
        startPoint: .topLeading, endPoint: .bottomTrailing)
      Circle().fill(accent.opacity(0.34)).frame(width: 190, height: 190)
        .blur(radius: 35).offset(x: 190, y: -70)
      VStack(alignment: .leading, spacing: 8) {
        Label(
          String(localized: application.status.title).uppercased(),
          systemImage: application.status.systemImage)
          .eyebrow().foregroundStyle(accent)
        Text(application.role.nilIfBlank ?? "Application outcome")
          .displayFont(30).foregroundStyle(Theme.heroInk)
        Text(application.company.nilIfBlank ?? "Company not set")
          .font(.headline).foregroundStyle(Theme.heroMutedInk)
        Label("Usually takes about one minute", systemImage: "timer")
          .font(.caption.weight(.semibold)).foregroundStyle(Theme.heroMutedInk)
      }
      .padding(22)
    }
    .frame(minHeight: 210)
    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
  }
}

struct OutcomeRecommendationCard<Actions: View>: View {
  let summary: OutcomeLearningSummary
  let accent: Color
  @ViewBuilder let actions: () -> Actions

  private var recommendation: OutcomeLearningRecommendation { summary.recommendation }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top, spacing: 13) {
        Image(systemName: recommendation.focus.systemImage)
          .font(.title2)
          .foregroundStyle(accent)
          .frame(width: 52, height: 52)
          .background(accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 16))
        VStack(alignment: .leading, spacing: 5) {
          Text("WHAT TO CHANGE NEXT").eyebrow().foregroundStyle(accent)
          Text(recommendation.title).font(.title2.bold()).foregroundStyle(Theme.ink)
        }
      }
      Text(recommendation.detail).font(.subheadline).foregroundStyle(Theme.inkSoft)
      Label(recommendation.evidence, systemImage: "chart.xyaxis.line")
        .font(.caption).foregroundStyle(Theme.mutedInk)
      actions()
    }
    .padding(20)
    .background(
      LinearGradient(
        colors: [accent.opacity(0.12), Theme.card, Theme.card],
        startPoint: .topLeading, endPoint: .bottomTrailing),
      in: RoundedRectangle(cornerRadius: 24, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .strokeBorder(accent.opacity(0.24), lineWidth: 1)
    }
  }
}

struct OutcomeImprovementReviewView: View {
  @EnvironmentObject private var resumeStore: ResumeStore
  @EnvironmentObject private var applicationStore: ApplicationStore
  @EnvironmentObject private var careerStore: CareerIntelligenceStore
  @EnvironmentObject private var purchases: PurchaseManager
  @Environment(\.dismiss) private var dismiss

  let recommendation: OutcomeLearningRecommendation

  @State private var draft: AIOutcomeLearningDraft?
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var useProfile = true
  @State private var useCompetencies = true
  @State private var useExperience = true
  @State private var savedResumeTitle: String?

  private var sourceDraft: ResumeDraft? {
    recommendation.resumeID.flatMap { id in resumeStore.resumes.first { $0.id == id } }
      ?? resumeStore.activeDraft
  }

  private var accent: Color { resumeStore.document.accent.color }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          PremiumFeatureHero(
            eyebrow: "OUTCOME LEARNING",
            title: "Improve from real results.",
            subtitle: recommendation.detail,
            icon: "arrow.trianglehead.2.clockwise.rotate.90",
            accent: accent
          )

          VStack(alignment: .leading, spacing: 10) {
            Label(recommendation.evidence, systemImage: "lightbulb.fill")
              .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            Divider()
            Label(aiRouteTitle, systemImage: purchases.plan == .free ? "iphone.gen3" : "cloud.fill")
              .font(.headline).foregroundStyle(accent)
            Text(aiRouteDetail).font(.caption).foregroundStyle(Theme.mutedInk)
          }
          .padding(18)
          .cardSurface()

          if let sourceDraft {
            Label("Source: \(sourceDraft.title). A new version will be created; the résumé linked to the past application will stay unchanged.", systemImage: "doc.on.doc.fill")
              .font(.caption).foregroundStyle(Theme.mutedInk)
          }

          if draft == nil {
            Button { Task { await generate() } } label: {
              HStack {
                if isLoading { ProgressView().tint(.white) }
                else { Image(systemName: "sparkles") }
                Text(isLoading ? "Creating a safe draft…" : generateButtonTitle)
              }
              .font(.headline).foregroundStyle(.white)
              .frame(maxWidth: .infinity).padding(.vertical, 15)
              .background(accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isLoading || sourceDraft == nil)
          }

          if let draft {
            VStack(alignment: .leading, spacing: 7) {
              Text(draft.title.nilIfBlank ?? recommendation.title).font(.title2.bold())
              Text(draft.rationale).font(.subheadline).foregroundStyle(Theme.inkSoft)
            }

            if draft.hasProfileChange, let sourceDraft {
              reviewChange(
                title: "Professional profile",
                before: sourceDraft.document.professionalProfile,
                after: draft.proposedProfile,
                isOn: $useProfile
              )
            }
            if draft.hasCompetencyChanges, let sourceDraft {
              reviewChange(
                title: "Competencies to add",
                before: sourceDraft.document.competencies.joined(separator: " • "),
                after: draft.proposedCompetencies.joined(separator: " • "),
                isOn: $useCompetencies
              )
            }
            if draft.hasExperienceChange {
              reviewChange(
                title: "Experience evidence",
                before: draft.originalBullet,
                after: draft.proposedBullet,
                isOn: $useExperience
              )
            }

            if !draft.coachingSteps.isEmpty {
              VStack(alignment: .leading, spacing: 9) {
                Label("Next experiment", systemImage: "checklist").font(.headline)
                ForEach(Array(draft.coachingSteps.enumerated()), id: \.offset) { index, step in
                  Text("\(index + 1). \(step)").font(.subheadline).foregroundStyle(Theme.inkSoft)
                }
              }
              .padding(18).cardSurface()
            }

            if !draft.claimsRequiringConfirmation.isEmpty {
              VStack(alignment: .leading, spacing: 8) {
                Label("Confirm before applying", systemImage: "exclamationmark.shield.fill")
                  .font(.headline).foregroundStyle(.orange)
                ForEach(draft.claimsRequiringConfirmation, id: \.self) {
                  Text("• \($0)").font(.subheadline)
                }
              }
              .padding(18).cardSurface()
            }

            if draft.hasResumeChanges {
              Button("Save as a new résumé version", systemImage: "doc.badge.plus", action: apply)
                .buttonStyle(.borderedProminent).tint(.green)
                .frame(maxWidth: .infinity)
            }
          }

          if let focus = recommendation.focus.editorSection {
            NavigationLink {
              ResumeEditorView(focus: focus)
            } label: {
              Label("Open \(focus.title) manually", systemImage: "pencil.line")
                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
          }

          if let savedResumeTitle {
            Label("Saved \(savedResumeTitle). Your historical application still points to the original version.", systemImage: "checkmark.seal.fill")
              .font(.subheadline.weight(.semibold)).foregroundStyle(.green)
              .padding(16).cardSurface()
          }
          if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
              .font(.subheadline).foregroundStyle(.orange)
          }
        }
        .padding(20).padding(.bottom, 40)
        .frame(maxWidth: 720).frame(maxWidth: .infinity)
      }
      .background(Theme.paper)
      .navigationTitle("Review improvement")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
    }
  }

  private var aiRouteTitle: String {
    purchases.plan == .free ? "Private on-device draft" : "High-quality connected draft"
  }

  private var aiRouteDetail: String {
    if purchases.plan == .free {
      return "Free uses Apple Intelligence when available. \(OnDeviceAIService.availabilityDescription). Your private debrief text stays on this iPhone."
    }
    return "Go and Pro use the connected writing service first for quality. Only the redacted résumé and selected signal categories are sent; private debrief text stays on this iPhone."
  }

  private var generateButtonTitle: String {
    purchases.plan == .free ? "Create private draft" : "Create reviewed draft · 1 credit"
  }

  @ViewBuilder private func reviewChange(
    title: String,
    before: String,
    after: String,
    isOn: Binding<Bool>
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Toggle(title, isOn: isOn).font(.headline).tint(accent)
      VStack(alignment: .leading, spacing: 5) {
        Text("BEFORE").eyebrow().foregroundStyle(.red)
        Text(before.nilIfBlank ?? "Not present").font(.caption).foregroundStyle(Theme.mutedInk)
      }
      Divider()
      VStack(alignment: .leading, spacing: 5) {
        Text("PROPOSED").eyebrow().foregroundStyle(.green)
        Text(after).font(.subheadline).foregroundStyle(Theme.ink)
      }
    }
    .padding(18)
    .cardSurface()
  }

  @MainActor private func generate() async {
    guard let sourceDraft else { return }
    isLoading = true
    errorMessage = nil
    do {
      draft = try await ResumeAIService.shared.createOutcomeLearningDraft(
        document: sourceDraft.document,
        recommendation: recommendation,
        applications: applicationStore.applications
      )
    } catch {
      errorMessage = error.localizedDescription
    }
    isLoading = false
  }

  private func apply() {
    guard let sourceDraft, let draft else { return }
    guard purchases.canCreateResume(currentCount: resumeStore.resumes.count) else {
      errorMessage = "Your current plan's résumé-version limit is full. Delete an unused version or choose a plan with unlimited versions; the proposed change is still available for review."
      purchases.requestPlans()
      return
    }

    var document = sourceDraft.document
    var revisions: [(field: String, before: String, after: String)] = []
    if draft.hasProfileChange, useProfile {
      revisions.append(("Professional profile", document.professionalProfile, draft.proposedProfile))
      document.professionalProfile = draft.proposedProfile
    }
    if draft.hasCompetencyChanges, useCompetencies {
      let before = document.competencies.joined(separator: " • ")
      let existing = Set(document.competencies.map { $0.lowercased() })
      document.competencies.append(contentsOf: draft.proposedCompetencies.filter {
        !existing.contains($0.lowercased())
      })
      revisions.append(("Competencies", before, document.competencies.joined(separator: " • ")))
    }
    if draft.hasExperienceChange, useExperience,
      let entryID = UUID(uuidString: draft.experienceEntryID),
      let entryIndex = document.experience.firstIndex(where: { $0.id == entryID }),
      let bulletIndex = document.experience[entryIndex].highlights.firstIndex(of: draft.originalBullet)
    {
      document.experience[entryIndex].highlights[bulletIndex] = draft.proposedBullet
      revisions.append(("Experience bullet", draft.originalBullet, draft.proposedBullet))
    }
    guard !revisions.isEmpty else {
      errorMessage = "Select at least one proposed change before saving."
      return
    }

    let title = "\(sourceDraft.title) · Outcome test"
    let newID = resumeStore.createResume(title: title, from: document)
    for revision in revisions {
      careerStore.addRevision(AIRevision(
        resumeID: newID,
        field: revision.field,
        before: revision.before,
        after: revision.after,
        evidenceIDs: [],
        evidenceLabels: [recommendation.evidence],
        claimsRequiringConfirmation: draft.claimsRequiringConfirmation
      ))
    }
    savedResumeTitle = title
    errorMessage = nil
  }
}
