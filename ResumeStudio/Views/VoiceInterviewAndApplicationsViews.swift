import SwiftUI

struct VoiceInterviewStudioView: View {
  @EnvironmentObject private var resumeStore: ResumeStore
  @EnvironmentObject private var applicationStore: ApplicationStore
  @EnvironmentObject private var careerStore: CareerIntelligenceStore
  @StateObject private var recorder = SpeechInterviewRecorder()
  @StateObject private var audioPlayer = AudioPreviewPlayer()
  @State private var applicationID: UUID?
  @State private var selectedQuestion = "Tell me about yourself and why this role is the right next step."
  @State private var feedback: AIVoiceInterviewFeedback?
  @State private var isEvaluating = false
  @State private var errorMessage: String?
  @State private var seniority = "Mid-level"
  @State private var adaptiveQuestions: [String] = []
  @State private var panelMode = false
  @State private var timeLimitSeconds = 120.0

  private var application: JobApplication? {
    applicationID.flatMap { id in applicationStore.applications.first { $0.id == id } }
  }

  private var questions: [String] {
    let generated = application?.interviewPlan?.questions.map(\.question) ?? []
    if !generated.isEmpty { return adaptiveQuestions + generated }
    var values = [
        "Tell me about yourself and why this role is the right next step.",
        "Describe a difficult problem you solved and the result.",
        "Tell me about a time you influenced someone without formal authority.",
        "What would your first 90 days in this role look like?",
      ]
    if seniority == "Senior" || seniority == "Executive" {
      values.append("Describe a decision where you balanced business risk, people and long-term outcomes.")
      values.append("How do you set direction when the available evidence is incomplete?")
    }
    let role = application?.role.lowercased() ?? ""
    if role.contains("manager") || role.contains("lead") { values.append("Tell me about a team you developed and how you measured progress.") }
    if role.contains("sales") { values.append("Walk me through how you built and converted a difficult pipeline.") }
    if role.contains("engineer") || role.contains("developer") { values.append("Explain a technical trade-off you made and its impact.") }
    return adaptiveQuestions + values
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        PremiumFeatureHero(
          eyebrow: "VOICE MOCK INTERVIEW",
          title: "Practise out loud. Improve with evidence.",
          subtitle: "Your answer is transcribed on the device where supported, then reviewed against the role and your verified career evidence.",
          icon: "waveform.and.mic",
          accent: resumeStore.document.accent.color
        )

        VStack(alignment: .leading, spacing: 13) {
          Label("Interview context", systemImage: "briefcase.fill").font(.headline)
          Picker("Application", selection: $applicationID) {
            Text("General practice").tag(Optional<UUID>.none)
            ForEach(applicationStore.applications) { application in
              Text([application.role, application.company].filter { !$0.isBlank }.joined(separator: " — "))
                .tag(Optional(application.id))
            }
          }
          Picker("Seniority", selection: $seniority) {
            ForEach(["Entry-level", "Mid-level", "Senior", "Executive"], id: \.self) { Text($0) }
          }
          Picker("Question", selection: $selectedQuestion) {
            ForEach(questions, id: \.self) { Text($0).tag($0) }
          }
          .pickerStyle(.menu)
          Toggle("Timed panel-interview mode", isOn: $panelMode)
          if panelMode {
            Picker("Answer time", selection: $timeLimitSeconds) {
              Text("60 seconds").tag(60.0)
              Text("90 seconds").tag(90.0)
              Text("2 minutes").tag(120.0)
            }
            .pickerStyle(.segmented)
            Label("Recording stops automatically; follow-ups adapt to the answer you just gave.", systemImage: "timer")
              .font(.caption).foregroundStyle(Theme.mutedInk)
          }
          Text(selectedQuestion).font(.title3.weight(.semibold)).foregroundStyle(Theme.ink).padding(.top, 4)
        }.padding(18).cardSurface()

        VoiceRecorderCard(
          recorder: recorder,
          accent: resumeStore.document.accent.color,
          timeLimitSeconds: panelMode ? timeLimitSeconds : nil)

        if !recorder.transcript.isBlank {
          VStack(alignment: .leading, spacing: 10) {
            HStack {
              Label("Transcript", systemImage: "text.quote").font(.headline)
              Spacer()
              Text("\(wordsPerMinute) wpm").font(.caption.weight(.bold)).foregroundStyle(resumeStore.document.accent.color)
            }
            TextEditor(text: Binding(
              get: { recorder.transcript },
              set: { recorder.replaceTranscript($0) }
            ))
            .frame(minHeight: 150).padding(8).background(Theme.muted, in: RoundedRectangle(cornerRadius: 14))
            if !fillerWords.isEmpty {
              Text("Filler words: \(fillerWords.joined(separator: ", "))")
                .font(.caption).foregroundStyle(.orange)
            }
            HStack(spacing: 8) {
              deliveryMetric("\(wordsPerMinute)", "WPM")
              deliveryMetric("\(recorder.pauseCount)", "Long pauses")
              deliveryMetric(String(format: "%.1fs", recorder.longestPauseSeconds), "Longest")
              deliveryMetric("\(Int(recorder.durationSeconds))s", "Length")
            }
            if let url = recorder.lastRecordingURL {
              Button(audioPlayer.isPlaying ? "Stop playback" : "Play my answer", systemImage: audioPlayer.isPlaying ? "stop.fill" : "play.fill") {
                audioPlayer.toggle(url: url)
              }.buttonStyle(.bordered)
            }
          }.padding(18).cardSurface()

          Button { Task { await evaluate() } } label: {
            HStack {
              if isEvaluating { ProgressView().tint(.white) } else { Image(systemName: "sparkles") }
              Text(isEvaluating ? "Reviewing your answer…" : "Coach this answer")
            }
            .font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 15)
            .background(resumeStore.document.accent.color, in: Capsule())
          }.buttonStyle(.plain).disabled(isEvaluating)
        }

        if let feedback { VoiceFeedbackCard(feedback: feedback, accent: resumeStore.document.accent.color) }
        if let message = recorder.errorMessage ?? errorMessage {
          Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }

        if !careerStore.voiceAttempts.isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            Text("Recent practice").font(.title3.bold())
            PracticeTrendView(attempts: Array(careerStore.voiceAttempts.prefix(8)), accent: resumeStore.document.accent.color)
            ForEach(careerStore.voiceAttempts.prefix(3)) { attempt in
              HStack {
                ZStack { Circle().fill(Color.pink.opacity(0.14)); Image(systemName: "waveform").foregroundStyle(.pink) }
                  .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 3) {
                  Text(attempt.question).font(.subheadline.weight(.semibold)).lineLimit(1)
                  Text("\(attempt.wordsPerMinute) wpm · \(Int(attempt.durationSeconds)) sec").font(.caption).foregroundStyle(Theme.mutedInk)
                  if let score = attempt.deliveryScore { Text("Delivery \(score)/100").font(.caption.bold()).foregroundStyle(resumeStore.document.accent.color) }
                }
                if let file = attempt.audioFilename {
                  Button { audioPlayer.toggle(url: URL(fileURLWithPath: file)) } label: { Image(systemName: "play.circle.fill") }
                    .buttonStyle(.plain)
                }
              }
            }
          }.padding(18).cardSurface()
        }
      }.padding(20).padding(.bottom, 40).frame(maxWidth: 720).frame(maxWidth: .infinity)
    }
    .background(Theme.paper)
    .navigationTitle("Voice Interview")
    .navigationBarTitleDisplayMode(.inline)
    .onChange(of: applicationID) { _, _ in selectedQuestion = questions.first ?? selectedQuestion; feedback = nil }
    .onDisappear { recorder.stop() }
  }

  private var wordsPerMinute: Int {
    let words = recorder.transcript.split(whereSeparator: \.isWhitespace).count
    guard recorder.durationSeconds > 1 else { return 0 }
    return Int((Double(words) / recorder.durationSeconds * 60).rounded())
  }

  private var fillerWords: [String] {
    let words = recorder.transcript.lowercased().split { !$0.isLetter }.map(String.init)
    let candidates = ["um", "uh", "like", "basically", "actually"]
    return candidates.compactMap { filler in
      let count = words.count { $0 == filler }
      return count > 0 ? "\(filler) ×\(count)" : nil
    }
  }

  @MainActor private func evaluate() async {
    isEvaluating = true; errorMessage = nil
    do {
      let result = try await ResumeAIService.shared.evaluateInterviewAnswer(
        document: resumeStore.document,
        evidence: careerStore.verifiedEvidence,
        application: application,
        question: selectedQuestion,
        transcript: recorder.transcript,
        durationSeconds: recorder.durationSeconds,
        wordsPerMinute: wordsPerMinute,
        fillerWords: fillerWords
      )
      feedback = result
      careerStore.add(VoicePracticeAttempt(
        applicationID: applicationID,
        question: selectedQuestion,
        transcript: recorder.transcript,
        durationSeconds: recorder.durationSeconds,
        wordsPerMinute: wordsPerMinute,
        fillerWords: fillerWords,
        starCoverage: result.starCoverage,
        strengths: result.strengths,
        improvements: result.improvements,
        suggestedAnswerShape: result.suggestedAnswerShape,
        claimsRequiringConfirmation: result.claimsRequiringConfirmation,
        deliveryScore: deliveryScore(result: result),
        audioFilename: recorder.lastRecordingURL?.path,
        pauseCount: recorder.pauseCount,
        longestPauseSeconds: recorder.longestPauseSeconds
      ))
      let followUp = adaptiveFollowUp(from: result)
      adaptiveQuestions.removeAll { $0 == followUp }
      adaptiveQuestions.insert(followUp, at: 0)
      if panelMode { selectedQuestion = followUp }
    } catch { errorMessage = error.localizedDescription }
    isEvaluating = false
  }

  private func deliveryScore(result: AIVoiceInterviewFeedback) -> Int {
    let pacePenalty = min(25, abs(wordsPerMinute - 135) / 3)
    let fillerPenalty = min(25, fillerWords.reduce(0) { partial, value in
      partial + (Int(value.split(separator: "×").last ?? "0") ?? 0) * 3
    })
    let structureBonus = min(20, result.starCoverage.count * 5)
    return max(0, min(100, 80 - pacePenalty - fillerPenalty + structureBonus))
  }

  private func adaptiveFollowUp(from feedback: AIVoiceInterviewFeedback) -> String {
    if let improvement = feedback.improvements.first {
      return "You mentioned that answer could strengthen \(improvement.lowercased()). What specific example would you add?"
    }
    if feedback.starCoverage.count < 3 {
      return "What was the measurable result, and what did you personally do to achieve it?"
    }
    return "What did you learn from that experience, and what would you do differently now?"
  }

  private func deliveryMetric(_ value: String, _ label: String) -> some View {
    VStack(spacing: 2) {
      Text(value).font(.caption.bold()).monospacedDigit()
      Text(label).font(.system(size: 9)).foregroundStyle(Theme.mutedInk)
    }
    .frame(maxWidth: .infinity).padding(.vertical, 7)
    .background(Theme.muted, in: RoundedRectangle(cornerRadius: 9))
  }
}

private struct PracticeTrendView: View {
  let attempts: [VoicePracticeAttempt]
  let accent: Color
  var body: some View {
    HStack(alignment: .bottom, spacing: 7) {
      ForEach(attempts.reversed()) { attempt in
        VStack(spacing: 4) {
          RoundedRectangle(cornerRadius: 5)
            .fill(accent.gradient)
            .frame(height: max(8, CGFloat(attempt.deliveryScore ?? 50) * 0.7))
          Text("\(attempt.deliveryScore ?? 0)").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.mutedInk)
        }.frame(maxWidth: .infinity)
      }
    }.frame(height: 90).padding(10).background(Theme.muted, in: RoundedRectangle(cornerRadius: 14))
  }
}

private struct VoiceRecorderCard: View {
  @ObservedObject var recorder: SpeechInterviewRecorder
  let accent: Color
  let timeLimitSeconds: Double?
  @State private var pulses = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    VStack(spacing: 18) {
      ZStack {
        ForEach(0..<3, id: \.self) { ring in
          Circle().stroke(accent.opacity(0.22 - Double(ring) * 0.05), lineWidth: 2)
            .frame(width: CGFloat(104 + ring * 28), height: CGFloat(104 + ring * 28))
            .scaleEffect(recorder.isRecording && pulses && !reduceMotion ? 1.08 : 0.92)
        }
        Circle().fill(LinearGradient(colors: [accent, accent.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
          .frame(width: 92, height: 92)
          .shadow(color: accent.opacity(0.35), radius: 22, y: 10)
        Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
          .font(.system(size: 33, weight: .semibold)).foregroundStyle(.white)
      }
      .onAppear {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { pulses = true }
      }

      Text(recorder.isRecording ? "Listening · \(Int(recorder.durationSeconds)) sec" : "Tap to answer")
        .font(.headline).foregroundStyle(Theme.ink)
      Button {
        if recorder.isRecording { recorder.stop() } else { Task { await recorder.start(timeLimitSeconds: timeLimitSeconds) } }
      } label: {
        Text(recorder.isRecording ? "Finish answer" : "Start recording")
          .font(.headline).foregroundStyle(recorder.isRecording ? .red : accent)
          .padding(.horizontal, 24).padding(.vertical, 12)
          .background(Theme.muted, in: Capsule())
      }.buttonStyle(.plain)
    }.padding(.vertical, 25).frame(maxWidth: .infinity).cardSurface()
  }
}

private struct VoiceFeedbackCard: View {
  let feedback: AIVoiceInterviewFeedback
  let accent: Color
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label("Interview coach review", systemImage: "sparkles").font(.title3.bold()).foregroundStyle(accent)
      feedbackSection("What worked", icon: "checkmark.circle.fill", color: .green, items: feedback.strengths)
      feedbackSection("Strengthen next", icon: "arrow.up.circle.fill", color: .orange, items: feedback.improvements)
      if !feedback.starCoverage.isEmpty { FlowTagCloud(items: feedback.starCoverage, accent: accent) }
      Text("Suggested shape").font(.headline)
      Text(feedback.suggestedAnswerShape).font(.subheadline).foregroundStyle(Theme.inkSoft)
      ForEach(feedback.claimsRequiringConfirmation, id: \.self) {
        Label($0, systemImage: "exclamationmark.shield.fill").font(.caption).foregroundStyle(.orange)
      }
    }.padding(19).cardSurface()
  }

  private func feedbackSection(_ title: String, icon: String, color: Color, items: [String]) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Label(title, systemImage: icon).font(.headline).foregroundStyle(color)
      ForEach(items, id: \.self) { Text("• \($0)").font(.subheadline).foregroundStyle(Theme.inkSoft) }
    }
  }
}

struct ApplicationCommandCenterView: View {
  @EnvironmentObject private var applicationStore: ApplicationStore
  @EnvironmentObject private var careerStore: CareerIntelligenceStore
  @EnvironmentObject private var resumeStore: ResumeStore
  @State private var selectedStatus: JobApplicationStatus?
  @State private var outcomeReviewRequest: OutcomeReviewRequest?

  private var applications: [JobApplication] {
    let values: [JobApplication]
    if let selectedStatus { values = applicationStore.applications(with: selectedStatus) }
    else { values = applicationStore.applications }
    return values.sorted { $0.updatedAt > $1.updatedAt }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        pipelineHero
        metrics
        stageStrip

        HStack {
          Text(selectedStatus?.title ?? "All applications").font(.title2.bold()).foregroundStyle(Theme.ink)
          Spacer()
          NavigationLink(value: HomeRoute.jobCapture) {
            Label("Capture", systemImage: "plus").font(.subheadline.bold())
          }
        }

        if applications.isEmpty {
          PremiumEmptyState(
            image: .pipelineEmptyState,
            title: "Your next opportunity starts here",
            detail: "Share a vacancy from Safari or capture an advert to build your first connected application."
          )
        } else {
          ForEach(applications) { application in
            NavigationLink(value: HomeRoute.applicationDetail(application.id)) {
              CommandApplicationCard(application: application, accent: resumeStore.document.accent.color)
            }
            .buttonStyle(.plain)
            .draggable(application.id.uuidString)
          }
        }

        if !careerStore.contacts.filter({ $0.followUpAt != nil }).isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            Label("Follow-ups", systemImage: "bell.badge.fill").font(.title3.bold())
            ForEach(careerStore.contacts.filter { $0.followUpAt != nil }.prefix(5)) { contact in
              HStack {
                Circle().fill(resumeStore.document.accent.color.opacity(0.13)).frame(width: 42, height: 42)
                  .overlay { Text(String(contact.name.prefix(1))).font(.headline).foregroundStyle(resumeStore.document.accent.color) }
                VStack(alignment: .leading) {
                  Text(contact.name).font(.headline)
                  Text(contact.followUpAt?.formatted(date: .abbreviated, time: .omitted) ?? "Follow up").font(.caption).foregroundStyle(Theme.mutedInk)
                }
              }
            }
          }.padding(18).cardSurface()
        }
      }.padding(20).padding(.bottom, 40).frame(maxWidth: 720).frame(maxWidth: .infinity)
    }
    .background(Theme.paper)
    .navigationTitle("Applications")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        NavigationLink(value: HomeRoute.applicationAnalytics) {
          Image(systemName: "chart.xyaxis.line")
        }
        .accessibilityLabel("Outcome analytics")
        NavigationLink(value: HomeRoute.jobCapture) { Image(systemName: "plus") }
      }
    }
    .sheet(item: $outcomeReviewRequest) { request in
      OutcomeReviewSheet(applicationID: request.applicationID)
    }
  }

  private var pipelineHero: some View {
    ZStack(alignment: .bottomLeading) {
      LinearGradient(colors: [Theme.heroTop, Theme.heroBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
      Circle().fill(resumeStore.document.accent.color.opacity(0.34)).frame(width: 230, height: 230).blur(radius: 40).offset(x: 175, y: -80)
      VStack(alignment: .leading, spacing: 8) {
        Text("APPLICATION COMMAND CENTER").eyebrow().foregroundStyle(resumeStore.document.accent.color)
        Text("Know what is moving\nand what needs you.").font(Theme.display(31)).foregroundStyle(Theme.heroInk)
        Text("Every opportunity, document, interview and contact in one connected timeline.").font(.subheadline).foregroundStyle(Theme.heroMutedInk)
      }.padding(22)
    }.frame(minHeight: 220).clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
  }

  private var metrics: some View {
    HStack(spacing: 10) {
      metric("\(applicationStore.applications.count)", "Tracked", .blue)
      metric("\(applicationStore.applications(with: .interview).count)", "Interview", .orange)
      metric("\(applicationStore.applications(with: .offer).count)", "Offers", .green)
    }
  }

  private func metric(_ value: String, _ label: String, _ color: Color) -> some View {
    VStack(spacing: 4) {
      Text(value).font(.title.bold()).foregroundStyle(color)
      Text(label).font(.caption).foregroundStyle(Theme.mutedInk)
    }.padding(.vertical, 14).frame(maxWidth: .infinity).cardSurface(radius: 17)
  }

  private var stageStrip: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        stageChip(nil, title: "All")
        ForEach(JobApplicationStatus.allCases) { status in stageChip(status, title: status.title) }
      }.padding(.vertical, 2)
    }
  }

  private func stageChip(_ status: JobApplicationStatus?, title: String) -> some View {
    Button { withAnimation(.easeInOut(duration: 0.2)) { selectedStatus = status } } label: {
      HStack(spacing: 6) {
        if let status { Image(systemName: status.systemImage) }
        Text(title)
        Text("\(status.map { applicationStore.applications(with: $0).count } ?? applicationStore.applications.count)").opacity(0.7)
      }.font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 9)
    }
    .foregroundStyle(selectedStatus == status ? Color.white : Theme.ink)
    .background(selectedStatus == status ? resumeStore.document.accent.color : Theme.muted, in: Capsule())
    .dropDestination(for: String.self) { values, _ in
      guard let status, let raw = values.first, let id = UUID(uuidString: raw) else { return false }
      withAnimation(.snappy) { applicationStore.move(id, to: status) }
      if let application = applicationStore.applications.first(where: { $0.id == id }),
        application.needsCurrentOutcomeReview
      {
        outcomeReviewRequest = OutcomeReviewRequest(applicationID: id)
      }
      return true
    } isTargeted: { targeted in
      if targeted, let status { selectedStatus = status }
    }
  }
}

private struct CommandApplicationCard: View {
  let application: JobApplication
  let accent: Color
  var body: some View {
    HStack(spacing: 14) {
      ZStack {
        RoundedRectangle(cornerRadius: 15).fill(accent.opacity(0.12))
        Image(systemName: application.status.systemImage).font(.title3).foregroundStyle(accent)
      }.frame(width: 54, height: 54)
      VStack(alignment: .leading, spacing: 4) {
        Text(application.role.nilIfBlank ?? "Untitled role").font(.headline).foregroundStyle(Theme.ink)
        Text(application.company.nilIfBlank ?? "Company not set").font(.subheadline).foregroundStyle(Theme.mutedInk)
        HStack(spacing: 7) {
          Text(application.status.title).font(.caption.weight(.bold)).foregroundStyle(accent)
          Text("·")
          Text(application.updatedAt, style: .relative).font(.caption).foregroundStyle(Theme.mutedInk)
        }
      }
      Spacer()
      Image(systemName: "chevron.right").foregroundStyle(Theme.mutedInk)
    }.padding(16).cardSurface(radius: 20)
  }
}
