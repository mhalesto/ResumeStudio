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
