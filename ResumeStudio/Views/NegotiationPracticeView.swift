import SwiftUI

struct NegotiationPracticeView: View {
  @EnvironmentObject private var resumeStore: ResumeStore
  @EnvironmentObject private var careerStore: CareerIntelligenceStore
  @EnvironmentObject private var applicationStore: ApplicationStore
  @StateObject private var recorder = SpeechInterviewRecorder()

  @State private var selectedOfferID: UUID?
  @State private var customRole = ""
  @State private var customCompany = ""
  @State private var customOfferSummary = ""
  @State private var persona = NegotiationPersona.formalRecruiter
  @State private var difficulty = NegotiationDifficulty.realistic
  @State private var goal = "Improve the base salary while keeping the relationship warm."
  @AppStorage("negotiationLiveNudges") private var liveNudges = true

  @State private var activeSession: NegotiationPracticeSession?
  @State private var composer = ""
  @State private var isWaiting = false
  @State private var counterpartClosed = false
  @State private var errorMessage: String?
  @State private var reviewingSession: NegotiationPracticeSession?

  init(offerID: UUID? = nil) {
    _selectedOfferID = State(initialValue: offerID)
  }

  private var accent: Color { resumeStore.document.accent.color }
  private var selectedOffer: JobOffer? {
    selectedOfferID.flatMap { id in careerStore.offers.first { $0.id == id } }
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          if let session = activeSession {
            if session.debrief != nil {
              reviewPhase(session)
            } else {
              livePhase(session, proxy: proxy)
            }
          } else {
            setupPhase
          }
        }
        .padding(20).padding(.bottom, 40).frame(maxWidth: 720).frame(maxWidth: .infinity)
      }
    }
    .background(Theme.paper)
    .navigationTitle("Negotiation Rehearsal")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $reviewingSession) { session in
      NegotiationSessionSheet(session: session, accent: accent)
    }
    .onChange(of: recorder.isRecording) { _, recording in
      guard !recording, !recorder.transcript.isBlank else { return }
      composer = [composer, recorder.transcript]
        .filter { !$0.isBlank }.joined(separator: " ")
      recorder.replaceTranscript("")
    }
    .onDisappear { recorder.stop() }
  }

  // MARK: - Setup

  private var setupPhase: some View {
    Group {
      PremiumFeatureHero(
        eyebrow: "SAY THE NUMBER OUT LOUD",
        title: "Rehearse the conversation that pays for itself.",
        subtitle: "Negotiate with a realistic counterpart before you face the real one. Every reply is grounded in your offer — nothing about the market is invented.",
        icon: "person.line.dotted.person.fill",
        accent: accent
      )

      VStack(alignment: .leading, spacing: 13) {
        Label("The offer on the table", systemImage: "scale.3d").font(.headline)
        if careerStore.offers.isEmpty {
          Text("No saved offers — describe the offer, or add one in the Offers workspace first.")
            .font(.caption).foregroundStyle(Theme.mutedInk)
        } else {
          Picker("Offer", selection: $selectedOfferID) {
            ForEach(careerStore.offers) { offer in
              Text([offer.role, offer.company].filter { !$0.isBlank }.joined(separator: " — "))
                .tag(Optional(offer.id))
            }
            Text("Describe it myself").tag(Optional<UUID>.none)
          }
        }
        if selectedOffer == nil {
          TextField("Role", text: $customRole)
          TextField("Company", text: $customCompany)
          TextField(
            "The offer — salary, bonus, leave, anything negotiable…",
            text: $customOfferSummary, axis: .vertical
          ).lineLimit(2...5)
        } else if let offer = selectedOffer {
          Text(offer.negotiationSummary).font(.caption).foregroundStyle(Theme.mutedInk)
        }
        TextField("What do you want out of this conversation?", text: $goal, axis: .vertical)
          .lineLimit(2...4)
      }.padding(18).cardSurface()

      VStack(alignment: .leading, spacing: 13) {
        Label("Who is across the table?", systemImage: "person.crop.circle.badge.questionmark.fill")
          .font(.headline)
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 10) {
            ForEach(NegotiationPersona.allCases) { value in
              Button { persona = value } label: {
                PersonaCard(persona: value, selected: persona == value, accent: accent)
              }.buttonStyle(.plain)
            }
          }.padding(.vertical, 2)
        }
        Picker("Difficulty", selection: $difficulty) {
          ForEach(NegotiationDifficulty.allCases) { Text($0.title).tag($0) }
        }.pickerStyle(.segmented)
        Toggle("Live coaching hints", isOn: $liveNudges)
        Label(
          "Each exchange uses 1 AI credit; a full rehearsal is usually 8–12.",
          systemImage: "sparkles"
        ).font(.caption).foregroundStyle(Theme.mutedInk)
      }.padding(18).cardSurface()

      Button { Task { await start() } } label: {
        HStack {
          if isWaiting { ProgressView().tint(.white) } else { Image(systemName: "bubble.left.and.bubble.right.fill") }
          Text(isWaiting ? "Setting up the call…" : "Start the rehearsal")
        }
        .font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 15)
        .background(canStart ? accent : Color.gray.opacity(0.5), in: Capsule())
      }.buttonStyle(.plain).disabled(!canStart || isWaiting)

      if let errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
      }

      if !careerStore.negotiationSessions.isEmpty {
        VStack(alignment: .leading, spacing: 12) {
          Text("Past rehearsals").font(.title3.bold())
          ForEach(careerStore.negotiationSessions) { session in
            Button {
              if session.isCompleted { reviewingSession = session } else { activeSession = session }
            } label: {
              SessionRow(session: session, accent: accent)
            }.buttonStyle(.plain).contextMenu {
              Button("Delete", systemImage: "trash", role: .destructive) {
                careerStore.deleteNegotiationSession(session.id)
              }
            }
          }
        }.padding(18).cardSurface()
      }
    }
  }

  private var canStart: Bool {
    if selectedOffer != nil { return !goal.isBlank }
    return !customOfferSummary.isBlank && !goal.isBlank
  }

  // MARK: - Live conversation

  private func livePhase(_ session: NegotiationPracticeSession, proxy: ScrollViewProxy) -> some View {
    Group {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Image(systemName: session.persona.systemImage).font(.title2).foregroundStyle(accent)
          VStack(alignment: .leading, spacing: 2) {
            Text(session.persona.title).font(.headline)
            Text([session.role, session.company].filter { !$0.isBlank }.joined(separator: " · "))
              .font(.caption).foregroundStyle(Theme.mutedInk)
          }
          Spacer()
          Text(session.difficulty.title).font(.caption.bold()).foregroundStyle(accent)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(accent.opacity(0.12), in: Capsule())
        }
        Text("Goal: \(session.goal)").font(.caption).foregroundStyle(Theme.inkSoft)
      }.padding(16).cardSurface()

      VStack(alignment: .leading, spacing: 12) {
        ForEach(session.messages) { message in
          MessageBubble(message: message, personaImage: session.persona.systemImage, accent: accent)
        }
        if isWaiting {
          HStack(spacing: 8) {
            Image(systemName: session.persona.systemImage).foregroundStyle(Theme.mutedInk)
            ProgressView()
            Text("Considering…").font(.caption).foregroundStyle(Theme.mutedInk)
          }.padding(12)
        }
        Color.clear.frame(height: 1).id("conversationEnd")
      }
      .onChange(of: session.messages.count) { _, _ in
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("conversationEnd", anchor: .bottom) }
      }

      if counterpartClosed {
        Label(
          "The conversation reached a natural close — get your review below.",
          systemImage: "flag.checkered"
        ).font(.subheadline).foregroundStyle(accent)
      }

      if let errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        if awaitingCounterpart(session) {
          Button("Try again", systemImage: "arrow.clockwise") { Task { await retryCounterpart() } }
            .buttonStyle(.bordered).disabled(isWaiting)
        }
      }

      composerBar(session)

      if session.messages.contains(where: { $0.kind == .user }) {
        Button { Task { await finishAndReview() } } label: {
          HStack {
            if isWaiting { ProgressView().tint(.white) } else { Image(systemName: "checkmark.seal.fill") }
            Text("End rehearsal & get my review")
          }
          .font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 14)
          .background(counterpartClosed ? accent : Color.orange, in: Capsule())
        }.buttonStyle(.plain).disabled(isWaiting)
      }
    }
  }

  private func composerBar(_ session: NegotiationPracticeSession) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      if recorder.isRecording {
        HStack(spacing: 8) {
          Image(systemName: "waveform").foregroundStyle(.red)
          Text(recorder.transcript.nilIfBlank ?? "Listening — say your reply…")
            .font(.caption).foregroundStyle(Theme.inkSoft).lineLimit(2)
          Spacer()
          Text("\(Int(recorder.durationSeconds))s").font(.caption.monospacedDigit())
            .foregroundStyle(Theme.mutedInk)
        }
      }
      if let message = recorder.errorMessage {
        Label(message, systemImage: "mic.slash.fill").font(.caption).foregroundStyle(.orange)
      }
      HStack(spacing: 10) {
        Button {
          if recorder.isRecording { recorder.stop() } else { Task { await recorder.start() } }
        } label: {
          Image(systemName: recorder.isRecording ? "stop.circle.fill" : "mic.fill")
            .font(.title3)
            .foregroundStyle(recorder.isRecording ? .red : accent)
            .frame(width: 40, height: 40)
            .background(Theme.muted, in: Circle())
        }.buttonStyle(.plain).disabled(isWaiting)
          .accessibilityLabel(recorder.isRecording ? "Stop dictating" : "Dictate your reply")
        TextField("Your reply — say it like you would on the call…", text: $composer, axis: .vertical)
          .lineLimit(1...4)
          .disabled(isWaiting || recorder.isRecording)
        Button { Task { await send() } } label: {
          Image(systemName: "arrow.up.circle.fill")
            .font(.title)
            .foregroundStyle(composer.isBlank || isWaiting ? Theme.mutedInk : accent)
        }.buttonStyle(.plain).disabled(composer.isBlank || isWaiting || recorder.isRecording)
          .accessibilityLabel("Send reply")
      }
    }.padding(14).cardSurface()
  }

  // MARK: - Review

  private func reviewPhase(_ session: NegotiationPracticeSession) -> some View {
    Group {
      if let debrief = session.debrief {
        NegotiationDebriefCard(debrief: debrief, accent: accent)
      }
      DisclosureGroup {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(session.messages) { message in
            MessageBubble(message: message, personaImage: session.persona.systemImage, accent: accent)
          }
        }.padding(.top, 10)
      } label: {
        Label("Read the conversation back", systemImage: "text.bubble.fill").font(.headline)
      }.padding(16).cardSurface()

      Button {
        activeSession = nil
        counterpartClosed = false
        errorMessage = nil
      } label: {
        Text("Rehearse again")
          .font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 15)
          .background(accent, in: Capsule())
      }.buttonStyle(.plain)
    }
  }

  // MARK: - Conversation engine

  @MainActor private func start() async {
    errorMessage = nil
    counterpartClosed = false
    let offer = selectedOffer
    let application = offer?.applicationID
      .flatMap { id in applicationStore.applications.first { $0.id == id } }
    let session = NegotiationPracticeSession(
      offerID: offer?.id,
      applicationID: offer?.applicationID,
      company: offer?.company ?? customCompany,
      role: offer?.role ?? (customRole.nilIfBlank ?? application?.role ?? ""),
      persona: persona,
      difficulty: difficulty,
      goal: goal,
      offerSummary: offer?.negotiationSummary ?? customOfferSummary,
      messages: []
    )
    activeSession = session
    guard let turn = await performExchange(for: session) else { return }
    absorb(turn, into: session)
  }

  @MainActor private func send() async {
    guard var session = activeSession else { return }
    let text = composer.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    session.messages.append(NegotiationSessionMessage(kind: .user, content: text))
    activeSession = session
    composer = ""
    guard let turn = await performExchange(for: session) else {
      // Roll back the optimistic line so a retry does not send it twice.
      session.messages.removeLast()
      activeSession = session
      composer = text
      return
    }
    absorb(turn, into: session)
  }

  /// Whether the conversation is missing the counterpart's turn — nudges are
  /// asides, so only the last *spoken* line decides whose turn it is.
  private func awaitingCounterpart(_ session: NegotiationPracticeSession) -> Bool {
    session.messages.last(where: { $0.kind != .nudge })?.kind != .counterpart
  }

  /// Re-asks for the counterpart's turn after a failed opening or reply.
  @MainActor private func retryCounterpart() async {
    guard let session = activeSession else { return }
    guard awaitingCounterpart(session) else { return }
    guard let turn = await performExchange(for: session) else { return }
    absorb(turn, into: session)
  }

  /// Applies an exchange result: the counterpart's line, the optional private
  /// nudge, and the natural-close flag — then persists the session.
  @MainActor private func absorb(_ turn: AINegotiationTurn, into session: NegotiationPracticeSession) {
    var updated = session
    if !turn.reply.isBlank {
      updated.messages.append(NegotiationSessionMessage(kind: .counterpart, content: turn.reply))
    }
    if liveNudges, !turn.coachingNudge.isBlank {
      updated.messages.append(NegotiationSessionMessage(kind: .nudge, content: turn.coachingNudge))
    }
    counterpartClosed = turn.conversationComplete
    activeSession = updated
    careerStore.upsert(updated)
  }

  @MainActor private func finishAndReview() async {
    guard var session = activeSession else { return }
    guard let turn = await performExchange(for: session, stage: "debrief") else { return }
    session.debrief = NegotiationDebrief(
      outcomeSummary: turn.outcomeSummary,
      strengths: turn.strengths,
      improvements: turn.improvements,
      strongerLines: turn.strongerLines,
      tacticsObserved: turn.tacticsObserved,
      missedOpportunities: turn.missedOpportunities
    )
    activeSession = session
    careerStore.upsert(session)
  }

  @MainActor private func performExchange(
    for session: NegotiationPracticeSession, stage: String = "exchange"
  ) async -> AINegotiationTurn? {
    isWaiting = true
    errorMessage = nil
    defer { isWaiting = false }
    do {
      return try await ResumeAIService.shared.negotiationPractice(
        stage: stage,
        persona: session.persona,
        difficulty: session.difficulty,
        goal: session.goal,
        offerSummary: session.offerSummary,
        role: session.role,
        company: session.company,
        document: resumeStore.document,
        evidence: careerStore.verifiedEvidence,
        messages: session.messages
          .filter { $0.kind != .nudge }
          .map {
            AINegotiationWireMessage(
              speaker: $0.kind == .user ? "user" : "counterpart", content: $0.content)
          }
      )
    } catch {
      errorMessage = error.localizedDescription
      return nil
    }
  }
}

// MARK: - Components

private struct PersonaCard: View {
  let persona: NegotiationPersona
  let selected: Bool
  let accent: Color
  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      ZStack {
        Circle().fill(selected ? accent : accent.opacity(0.13)).frame(width: 44, height: 44)
        Image(systemName: persona.systemImage).foregroundStyle(selected ? .white : accent)
      }
      Text(persona.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
      Text(persona.blurb).font(.caption).foregroundStyle(Theme.mutedInk)
    }.padding(12).frame(width: 150, alignment: .leading)
      .background(Theme.muted.opacity(selected ? 1 : 0.55), in: RoundedRectangle(cornerRadius: 16))
      .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? accent : Color.clear, lineWidth: 2) }
  }
}

private struct MessageBubble: View {
  let message: NegotiationSessionMessage
  let personaImage: String
  let accent: Color
  var body: some View {
    switch message.kind {
    case .user:
      HStack {
        Spacer(minLength: 40)
        Text(message.content)
          .font(.subheadline).foregroundStyle(.white)
          .padding(.horizontal, 14).padding(.vertical, 10)
          .background(accent, in: RoundedRectangle(cornerRadius: 18))
      }
    case .counterpart:
      HStack(alignment: .bottom, spacing: 8) {
        Image(systemName: personaImage).font(.callout).foregroundStyle(Theme.mutedInk)
        Text(message.content)
          .font(.subheadline).foregroundStyle(Theme.ink)
          .padding(.horizontal, 14).padding(.vertical, 10)
          .background(Theme.muted, in: RoundedRectangle(cornerRadius: 18))
        Spacer(minLength: 40)
      }
    case .nudge:
      Label(message.content, systemImage: "lightbulb.fill")
        .font(.caption.italic()).foregroundStyle(.orange)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    }
  }
}

private struct SessionRow: View {
  let session: NegotiationPracticeSession
  let accent: Color
  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        Circle().fill(accent.opacity(0.13)).frame(width: 42, height: 42)
        Image(systemName: session.persona.systemImage).foregroundStyle(accent)
      }
      VStack(alignment: .leading, spacing: 3) {
        Text([session.role, session.company].filter { !$0.isBlank }.joined(separator: " · ").nilIfBlank ?? "Practice negotiation")
          .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1)
        Text(session.goal).font(.caption).foregroundStyle(Theme.mutedInk).lineLimit(1)
        Text(session.createdAt, style: .relative).font(.caption2).foregroundStyle(Theme.mutedInk)
      }
      Spacer()
      Text(session.isCompleted ? "Reviewed" : "Resume")
        .font(.caption.bold())
        .foregroundStyle(session.isCompleted ? Color.green : accent)
    }.padding(.vertical, 4)
  }
}

private struct NegotiationDebriefCard: View {
  let debrief: NegotiationDebrief
  let accent: Color
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label("Negotiation review", systemImage: "checkmark.seal.fill").font(.title3.bold()).foregroundStyle(accent)
      if !debrief.outcomeSummary.isBlank {
        Text(debrief.outcomeSummary).font(.subheadline).foregroundStyle(Theme.inkSoft)
      }
      section("What worked", icon: "checkmark.circle.fill", color: .green, items: debrief.strengths)
      section("Strengthen next", icon: "arrow.up.circle.fill", color: .orange, items: debrief.improvements)
      if !debrief.strongerLines.isEmpty {
        Text("Say it stronger next time").font(.headline)
        ForEach(debrief.strongerLines, id: \.self) { line in
          Text("“\(line)”")
            .font(.subheadline.italic()).foregroundStyle(Theme.ink)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
      }
      if !debrief.tacticsObserved.isEmpty {
        Text("Tactics you used").font(.headline)
        FlowTagCloud(items: debrief.tacticsObserved, accent: accent)
      }
      if !debrief.missedOpportunities.isEmpty {
        section("Left on the table", icon: "arrow.uturn.down.circle.fill", color: .orange, items: debrief.missedOpportunities)
      }
    }.padding(19).cardSurface()
  }

  private func section(_ title: LocalizedStringKey, icon: String, color: Color, items: [String]) -> some View {
    Group {
      if !items.isEmpty {
        VStack(alignment: .leading, spacing: 7) {
          Label(title, systemImage: icon).font(.headline).foregroundStyle(color)
          ForEach(items, id: \.self) { Text("• \($0)").font(.subheadline).foregroundStyle(Theme.inkSoft) }
        }
      }
    }
  }
}

/// Read-only replay of a finished rehearsal from the history list.
private struct NegotiationSessionSheet: View {
  let session: NegotiationPracticeSession
  let accent: Color
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          if let debrief = session.debrief {
            NegotiationDebriefCard(debrief: debrief, accent: accent)
          }
          VStack(alignment: .leading, spacing: 12) {
            ForEach(session.messages) { message in
              MessageBubble(message: message, personaImage: session.persona.systemImage, accent: accent)
            }
          }.padding(16).cardSurface()
        }.padding(16)
      }
      .background(Theme.paper)
      .navigationTitle([session.role, session.company].filter { !$0.isBlank }.joined(separator: " · ").nilIfBlank ?? "Rehearsal")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
  }
}
