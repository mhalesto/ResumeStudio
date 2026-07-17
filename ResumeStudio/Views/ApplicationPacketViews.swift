import Charts
import SwiftUI

struct ApplicationPacketView: View {
  @EnvironmentObject private var applicationStore: ApplicationStore
  @EnvironmentObject private var resumeStore: ResumeStore
  let applicationID: UUID

  @State private var packet: ApplicationPacket?
  @State private var shareFiles: PacketShareFiles?
  @State private var errorMessage: String?
  @State private var isGeneratingLetter = false

  private var application: JobApplication? {
    applicationStore.applications.first { $0.id == applicationID }
  }

  private var resume: ResumeDocument {
    guard let packet,
      let draft = resumeStore.resumes.first(where: { $0.id == packet.resumeID })
    else { return resumeStore.document }
    return draft.document
  }

  var body: some View {
    Form {
      if let application, let binding = Binding($packet) {
        Section {
          HStack {
            VStack(alignment: .leading, spacing: 4) {
              Text("One guided application pack").font(.headline)
              Text("Every AI result is saved, then waits for your review.")
                .font(.caption).foregroundStyle(Theme.mutedInk)
            }
            Spacer()
            Text("\(workflowCompleted)/6").font(.title2.bold()).foregroundStyle(resumeStore.document.accent.color)
          }
          ProgressView(value: Double(workflowCompleted), total: 6)
            .tint(resumeStore.document.accent.color)
          LabeledContent("Maximum AI cost") { Text("19 credits").fontWeight(.semibold) }
          LabeledContent("Still needed") { Text("\(remainingCreditCost) credits").fontWeight(.semibold) }

          workflowLabel("Job captured", detail: application.role.nilIfBlank ?? "Opportunity saved", done: true, icon: "scope")
          workflowLabel("Résumé selected", detail: resumeStore.resumes.first(where: { $0.id == binding.wrappedValue.resumeID })?.title ?? "Active résumé", done: true, icon: "doc.text")
          NavigationLink(value: HomeRoute.jobTargetingApplication(applicationID)) {
            workflowLabel(
              application.matchAnalysis == nil ? "Analyse match and review tailoring" : "Review match or create tailored version",
              detail: application.tailoredResumeID == nil ? "Up to 8 credits" : "Tailored version saved",
              done: application.matchAnalysis != nil && application.tailoredResumeID != nil,
              icon: "wand.and.stars")
          }
          workflowLabel(
            "Cover letter and email", detail: letterIsReady ? "Draft saved" : "Generate below · 3 credits",
            done: letterIsReady, icon: "envelope.badge")
          DatePicker(
            "Application deadline",
            selection: Binding(
              get: { application.deadline ?? Calendar.current.date(byAdding: .day, value: 7, to: Date())! },
              set: { updateDeadline($0) }
            ),
            displayedComponents: [.date, .hourAndMinute]
          )
          NavigationLink(value: HomeRoute.interviewPrep(applicationID)) {
            workflowLabel(
              "Create interview plan", detail: application.interviewPlan == nil ? "5 credits" : "Plan saved",
              done: application.interviewPlan != nil, icon: "person.2.wave.2.fill")
          }
        } header: {
          Text("Application Pack workflow")
        } footer: {
          Text("Costs are shown before any AI action. Local edits and exports never consume credits.")
        }

        Section {
          LabeledContent("Target", value: [application.role, application.company].filter { !$0.isBlank }.joined(separator: " at "))
          Picker("Résumé version", selection: binding.resumeID) {
            ForEach(resumeStore.resumes) { Text($0.title).tag($0.id) }
          }
          Label("Résumé, cover letter, application email and follow-up stay tied to this job.", systemImage: "link.circle.fill")
            .font(.caption).foregroundStyle(Theme.mutedInk)
        } header: { Text("Application packet") }

        Section("Cover letter") {
          TextField("Subject", text: binding.coverLetter.subject)
          TextField("Greeting", text: binding.coverLetter.greeting)
          ForEach(binding.coverLetter.bodyParagraphs.indices, id: \.self) { index in
            TextField("Paragraph \(index + 1)", text: binding.coverLetter.bodyParagraphs[index], axis: .vertical)
              .lineLimit(3...8)
          }
          Button {
            Task { await generateCoverLetter(application: application) }
          } label: {
            if isGeneratingLetter { ProgressView("Writing cover letter…") }
            else { Label("Generate evidence-backed letter", systemImage: "sparkles") }
          }
          .disabled(application.jobDescription.isBlank || isGeneratingLetter)
          NavigationLink {
            CoverLetterPreviewView(document: binding.wrappedValue.coverLetter)
          } label: { Label("Preview cover letter", systemImage: "doc.richtext") }
        }

        Section("Application email") {
          TextField("Subject", text: binding.applicationEmailSubject)
          TextEditor(text: binding.applicationEmailBody).frame(minHeight: 120)
          Button("Open in Mail", systemImage: "envelope.fill") {
            PlatformIntegrationService.openMail(
              subject: binding.wrappedValue.applicationEmailSubject,
              body: binding.wrappedValue.applicationEmailBody)
          }
        }

        Section("Follow-up email") {
          TextField("Subject", text: binding.followUpEmailSubject)
          TextEditor(text: binding.followUpEmailBody).frame(minHeight: 120)
          Button("Open follow-up in Mail", systemImage: "paperplane.fill") {
            PlatformIntegrationService.openMail(
              subject: binding.wrappedValue.followUpEmailSubject,
              body: binding.wrappedValue.followUpEmailBody)
          }
        }

        Section("Interview checklist") {
          ForEach(binding.interviewChecklist.indices, id: \.self) { index in
            TextField("Preparation item", text: binding.interviewChecklist[index], axis: .vertical)
          }
          .onDelete { binding.interviewChecklist.wrappedValue.remove(atOffsets: $0) }
          Button("Add checklist item", systemImage: "plus") {
            binding.interviewChecklist.wrappedValue.append("")
          }
        }

        Section {
          Button("Share complete packet", systemImage: "square.and.arrow.up") {
            do {
              let files = try ApplicationPacketExporter.files(
                packet: binding.wrappedValue, application: application, resume: resume)
              shareFiles = PacketShareFiles(urls: files)
            } catch { errorMessage = error.localizedDescription }
          }
          .fontWeight(.semibold)
        } footer: {
          Text("Shares searchable résumé and letter PDFs plus editable email and preparation text files.")
        }
      } else {
        ContentUnavailableView("Application not found", systemImage: "briefcase.circle")
      }

      if let errorMessage {
        Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
      }
    }
    .navigationTitle("Application Packet")
    .navigationBarTitleDisplayMode(.inline)
    .supportsKeyboardDismissal()
    .onAppear(perform: loadPacket)
    .onDisappear {
      if let packet { applicationStore.updatePacket(packet) }
    }
    .onChange(of: packet) { _, updated in
      if let updated { applicationStore.updatePacket(updated) }
    }
    .sheet(item: $shareFiles) { item in ShareSheet(activityItems: item.urls) }
  }

  private func loadPacket() {
    guard let application else { return }
    packet = application.packet ?? applicationStore.ensurePacket(
      for: application.id,
      resumeID: application.tailoredResumeID ?? application.baseResumeID,
      resume: resumeStore.resumes.first(where: {
        $0.id == (application.tailoredResumeID ?? application.baseResumeID)
      })?.document ?? resumeStore.document
    )
  }

  private var letterIsReady: Bool {
    packet?.coverLetter.bodyParagraphs.contains(where: { !$0.isBlank }) == true
  }

  private var remainingCreditCost: Int {
    guard let application else { return 0 }
    var cost = 0
    if application.matchAnalysis == nil { cost += ResumeAIAction.analyzeJob.creditCost }
    if application.tailoredResumeID == nil { cost += ResumeAIAction.tailorResume.creditCost }
    if !letterIsReady { cost += ResumeAIAction.writeCoverLetter.creditCost }
    if application.interviewPlan == nil { cost += ResumeAIAction.interviewPrep.creditCost }
    return cost
  }

  private var workflowCompleted: Int {
    guard let application else { return 0 }
    return 2
      + (application.matchAnalysis != nil && application.tailoredResumeID != nil ? 1 : 0)
      + (letterIsReady ? 1 : 0)
      + (application.deadline != nil ? 1 : 0)
      + (application.interviewPlan != nil ? 1 : 0)
  }

  private func workflowLabel(_ title: String, detail: String, done: Bool, icon: String) -> some View {
    HStack(spacing: 11) {
      Image(systemName: done ? "checkmark.circle.fill" : icon)
        .foregroundStyle(done ? .green : resumeStore.document.accent.color)
        .frame(width: 24)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
        Text(detail).font(.caption).foregroundStyle(Theme.mutedInk)
      }
    }
  }

  private func updateDeadline(_ date: Date) {
    guard var application else { return }
    application.deadline = date
    applicationStore.update(application)
  }

  @MainActor
  private func generateCoverLetter(application: JobApplication) async {
    guard var value = packet else { return }
    isGeneratingLetter = true
    errorMessage = nil
    do {
      let generated = try await ResumeAIService.shared.writeCoverLetter(
        document: resume,
        jobDescription: application.jobDescription,
        jobTitle: application.role,
        company: application.company,
        recipientName: value.coverLetter.recipientName)
      value.coverLetter.subject = generated.subject
      value.coverLetter.greeting = generated.greeting
      value.coverLetter.bodyParagraphs = generated.bodyParagraphs
      value.coverLetter.closing = generated.closing
      value.updatedAt = Date()
      packet = value
      applicationStore.updatePacket(value)
    } catch { errorMessage = error.localizedDescription }
    isGeneratingLetter = false
  }
}

private struct PacketShareFiles: Identifiable {
  let id = UUID()
  let urls: [URL]
}

struct ApplicationAnalyticsView: View {
  @EnvironmentObject private var applicationStore: ApplicationStore
  @EnvironmentObject private var resumeStore: ResumeStore

  private var summary: ApplicationAnalyticsSummary {
    ApplicationAnalyticsService.summarize(applicationStore.applications)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        HStack(spacing: 10) {
          metric("\(summary.applicationToInterviewRate)%", "Application → interview", .orange)
          metric("\(summary.interviewToOfferRate)%", "Interview → offer", .green)
        }
        HStack(spacing: 10) {
          metric("\(summary.responses)", "Responses", .blue)
          metric(summary.averageDaysToResponse.map { String(format: "%.1f", $0) } ?? "—", "Days to response", .purple)
        }

        chartCard("Pipeline") {
          Chart([
            ("Tracked", summary.tracked), ("Applied", summary.applied),
            ("Interview", summary.interviews), ("Offer", summary.offers),
          ], id: \.0) { item in
            BarMark(x: .value("Stage", item.0), y: .value("Count", item.1))
              .foregroundStyle(resumeStore.document.accent.color.gradient)
          }
          .frame(height: 210)
        }

        if !summary.bySource.isEmpty {
          chartCard("Sources") {
            ForEach(summary.bySource.prefix(8)) { source in
              VStack(alignment: .leading, spacing: 5) {
                HStack { Text(source.name).font(.subheadline.bold()); Spacer(); Text("\(source.count) · \(source.interviews) interviews").font(.caption).foregroundStyle(Theme.mutedInk) }
                ProgressView(value: Double(source.interviews), total: Double(max(source.count, 1)))
                  .tint(resumeStore.document.accent.color)
              }
            }
          }
        }

        if !summary.byResume.isEmpty {
          chartCard("Résumé performance") {
            ForEach(summary.byResume) { metric in
              let title = resumeStore.resumes.first(where: { $0.id == metric.id })?.title ?? "Deleted version"
              HStack {
                VStack(alignment: .leading) { Text(title).font(.subheadline.bold()); Text("\(metric.count) applications").font(.caption).foregroundStyle(Theme.mutedInk) }
                Spacer()
                Text("\(metric.interviews) interviews").font(.caption.bold()).foregroundStyle(resumeStore.document.accent.color)
              }
            }
          }
        }

        Text("These are private, local correlations—not promises that a template caused an outcome.")
          .font(.caption).foregroundStyle(Theme.mutedInk)
      }
      .padding(20).padding(.bottom, 40).frame(maxWidth: 720).frame(maxWidth: .infinity)
    }
    .background(Theme.paper)
    .navigationTitle("Outcome Analytics")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func metric(_ value: String, _ label: String, _ color: Color) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(value).font(.title.bold()).foregroundStyle(color)
      Text(label).font(.caption).foregroundStyle(Theme.mutedInk)
    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).cardSurface(radius: 18)
  }

  private func chartCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 14) { Text(title).font(.title3.bold()); content() }
      .padding(18).cardSurface(radius: 22)
  }
}
