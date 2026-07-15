import SwiftUI
import UIKit

struct CareerCoachView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var resumeStore: ResumeStore
  @EnvironmentObject private var applicationStore: ApplicationStore
  @EnvironmentObject private var coverLetterStore: CoverLetterStore
  @ObservedObject var chatStore: CareerCoachStore

  @State private var isSending = false
  @State private var errorMessage: String?

  private var accent: Color { resumeStore.document.accent.color }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        transcript
        promptSuggestions
        CoachComposer(accent: accent, isSending: isSending, onSend: send)
      }
      .background(Theme.paper)
      .navigationTitle("Career Coach")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) { titleBar }
        ToolbarItem(placement: .topBarLeading) {
          Button("Close") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Button("Start a new conversation", systemImage: "arrow.counterclockwise") {
              chatStore.reset(welcome: welcomeMessage)
              errorMessage = nil
            }
          } label: {
            Image(systemName: "ellipsis.circle")
          }
        }
      }
      .onAppear {
        chatStore.ensureWelcome(welcomeMessage)
        if chatStore.suggestedPrompts.isEmpty {
          chatStore.suggestedPrompts = starterPrompts
        }
      }
    }
  }

  private var titleBar: some View {
    VStack(spacing: 1) {
      Text("Career Coach")
        .font(.headline)
        .foregroundStyle(Theme.ink)
      Text("Your AI career partner")
        .font(.caption2)
        .foregroundStyle(Theme.mutedInk)
    }
    .accessibilityElement(children: .combine)
  }

  // MARK: - Transcript

  private var transcript: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 16) {
          coachHeader

          ForEach(Array(chatStore.messages.enumerated()), id: \.element.id) { index, message in
            CoachMessageRow(
              message: message,
              accent: accent,
              // The next message, when the user sent one, is the answer to any
              // options this one is offering.
              followUp: followUp(after: index),
              isAnswerable: index == chatStore.messages.count - 1 && !isSending,
              onChoose: { send($0.reply) }
            )
            .id(message.id)
          }

          if isSending { thinkingRow }
          if let errorMessage { errorCard(errorMessage) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
      }
      .scrollDismissesKeyboard(.interactively)
      .onChange(of: chatStore.messages.count) { _, _ in
        if let id = chatStore.messages.last?.id {
          withAnimation { proxy.scrollTo(id, anchor: .bottom) }
        }
      }
      .onChange(of: isSending) { _, sending in
        if sending { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
      }
    }
  }

  private var coachHeader: some View {
    HStack(spacing: 12) {
      CareerCoachFace(accent: accent, size: 44)
      VStack(alignment: .leading, spacing: 2) {
        Text("Your work-focused AI coach")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Theme.ink)
        Text("Grounded in your saved career workspace")
          .font(.caption)
          .foregroundStyle(Theme.mutedInk)
      }
      Spacer(minLength: 8)
      Label("Private", systemImage: "lock.fill")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(accent)
    }
    .padding(14)
    .cardSurface(radius: 20)
  }

  private var thinkingRow: some View {
    HStack(spacing: 12) {
      CareerCoachFace(accent: accent, size: 34)
      HStack(spacing: 9) {
        CoachTypingDots(accent: accent)
        Text("Reading your career workspace…")
          .font(.caption)
          .foregroundStyle(Theme.mutedInk)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .background(Theme.card, in: Capsule())
      .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
      Spacer(minLength: 0)
    }
    .id("thinking")
    .transition(.opacity)
  }

  private func errorCard(_ message: String) -> some View {
    Label(message, systemImage: "exclamationmark.triangle.fill")
      .font(.caption)
      .foregroundStyle(.red)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(12)
      .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }

  /// The user's next message, which is what answers whatever the coach just asked.
  private func followUp(after index: Int) -> String? {
    let next = index + 1
    guard next < chatStore.messages.count, chatStore.messages[next].role == .user else { return nil }
    return chatStore.messages[next].content
  }

  // MARK: - Suggestions

  @ViewBuilder
  private var promptSuggestions: some View {
    if !chatStore.suggestedPrompts.isEmpty {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 10) {
          ForEach(chatStore.suggestedPrompts, id: \.self) { prompt in
            Button { send(prompt) } label: {
              HStack(spacing: 8) {
                Image(systemName: Self.icon(for: prompt))
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(accent)
                Text(prompt)
                  .font(.subheadline.weight(.medium))
                  .foregroundStyle(Theme.ink)
                  .lineLimit(1)
                Image(systemName: "chevron.right")
                  .font(.caption2.weight(.bold))
                  .foregroundStyle(Theme.mutedInk)
              }
              .padding(.horizontal, 12)
              .padding(.vertical, 10)
              .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
              .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                  .strokeBorder(Theme.hairline, lineWidth: 1)
              }
            }
            .buttonStyle(CoachPressStyle())
            .disabled(isSending)
            .opacity(isSending ? 0.5 : 1)
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
      }
      .background(Theme.paper)
    }
  }

  /// A glanceable cue for what a suggestion will do. Anything the map doesn't
  /// recognise still gets the coach's own mark, so no chip is left bare.
  private static func icon(for prompt: String) -> String {
    let text = prompt.lowercased()
    return switch true {
    case text.contains("quiz"), text.contains("test me"), text.contains("question"):
      "questionmark.bubble.fill"
    case text.contains("interview"): "person.2.fill"
    case text.contains("cover letter"): "envelope.fill"
    case text.contains("résumé"), text.contains("resume"), text.contains("cv"): "doc.text.fill"
    case text.contains("salary"), text.contains("negotiat"), text.contains("pay"): "banknote.fill"
    case text.contains("application"): "tray.full.fill"
    case text.contains("network"): "person.3.fill"
    case text.contains("job search"), text.contains("job hunt"), text.contains("plan"):
      "magnifyingglass"
    case text.contains("improve"), text.contains("weak"), text.contains("skill"):
      "chart.line.uptrend.xyaxis"
    default: "sparkles"
    }
  }

  // MARK: - Sending

  private var welcomeMessage: String {
    let firstName = resumeStore.document.personal.fullName
      .split(separator: " ").first.map(String.init)
    let greeting = firstName.map { "Hi \($0)!" } ?? "Hi!"
    if let next = applicationStore.upcomingInterviews.first {
      return
        "\(greeting) I’m your Career Coach. I can use your saved résumé, applications, interview practice and quiz results to help you move forward. Your next interview is for \(next.role) at \(next.company)—would you like a focused prep plan?"
    }
    if let application = applicationStore.applications.first {
      return
        "\(greeting) I’m your Career Coach. I can use your saved résumé, applications, interview practice and quiz results to give specific help. We can start with your \(application.role) application at \(application.company), or work on your wider job search."
    }
    return
      "\(greeting) I’m your Career Coach. I’ll use your saved résumé and career workspace to help with applications, interviews, workplace skills and your job search. What would you like to improve first?"
  }

  private var starterPrompts: [String] {
    var prompts = ["What should I improve next?", "Quiz me on my weak areas"]
    if applicationStore.upcomingInterviews.isEmpty {
      prompts.append("Help me plan my job search")
    } else {
      prompts.append("Prepare me for my next interview")
    }
    prompts.append("Review my saved applications")
    return prompts
  }

  private var context: CareerCoachContext {
    CareerCoachContext(
      resumeTitle: resumeStore.activeDraft?.title ?? "My Résumé",
      document: resumeStore.document,
      applications: applicationStore.applications,
      interviews: applicationStore.interviews,
      coverLetter: coverLetterStore.document
    )
  }

  private func send(_ rawMessage: String) {
    let message = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !message.isEmpty, !isSending else { return }
    errorMessage = nil
    chatStore.append(CareerCoachMessage(role: .user, content: message))
    isSending = true

    Task {
      do {
        let response = try await ResumeAIService.shared.careerCoach(
          context: context,
          messages: chatStore.messages
        )
        chatStore.append(CareerCoachMessage(role: .assistant, content: response.reply))
        chatStore.suggestedPrompts = response.suggestedPrompts
      } catch {
        errorMessage = error.localizedDescription
      }
      isSending = false
    }
  }
}

// MARK: - Messages

private struct CoachMessageRow: View {
  let message: CareerCoachMessage
  let accent: Color
  let followUp: String?
  let isAnswerable: Bool
  let onChoose: (CoachChoice) -> Void

  @ViewBuilder
  var body: some View {
    switch message.role {
    case .user: userBubble
    case .assistant: coachBubble
    }
  }

  private var userBubble: some View {
    HStack {
      Spacer(minLength: 48)
      VStack(alignment: .trailing, spacing: 3) {
        Text(message.content)
          .font(.body)
          .foregroundStyle(.white)
          .multilineTextAlignment(.leading)
          .textSelection(.enabled)
        Text(message.createdAt, style: .time)
          .font(.caption2)
          .foregroundStyle(Color.white.opacity(0.75))
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .background(accent, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
  }

  private var coachBubble: some View {
    let blocks = CoachReplyParser.parse(message.content)
    // What the coach says sits next to its face; the cards it lays out — the
    // focus area, the question, the options — take the full width beneath.
    let speech = blocks.prefix { $0.isSpeech }
    let cards = blocks.dropFirst(speech.count)

    return VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 12) {
        CareerCoachFace(accent: accent, size: 34)
        VStack(alignment: .leading, spacing: 10) {
          ForEach(Array(speech)) { view(for: $0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      ForEach(Array(cards)) { view(for: $0) }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardSurface(radius: 22)
    .contextMenu {
      Button("Copy", systemImage: "doc.on.doc") {
        UIPasteboard.general.string = CoachReplyParser.plain(message.content)
      }
    }
  }

  @ViewBuilder
  private func view(for block: CoachBlock) -> some View {
    switch block.kind {
    case .paragraph(let text):
      Text(text)
        .font(.body)
        .foregroundStyle(Theme.ink)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)

    case .heading(let text):
      Text(text)
        .font(.subheadline.weight(.bold))
        .foregroundStyle(Theme.ink)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)

    case .focus(let area):
      CoachFocusCard(area: area, accent: accent)

    case .question(let question):
      CoachQuestionCard(question: question, accent: accent)

    case .choices(let choices):
      CoachChoiceGroup(
        choices: choices,
        accent: accent,
        answered: followUp.flatMap { CoachChoice.answered(in: $0, among: choices) },
        isAnswerable: isAnswerable,
        onChoose: onChoose
      )

    case .bullets(let items):
      VStack(alignment: .leading, spacing: 7) {
        ForEach(items) { item in
          HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(item.marker)
              .font(.subheadline.weight(.bold))
              .foregroundStyle(accent)
            Text(item.text)
              .font(.subheadline)
              .foregroundStyle(Theme.inkSoft)
              .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
          }
        }
      }

    case .steps(let items):
      VStack(alignment: .leading, spacing: 9) {
        ForEach(items) { item in
          HStack(alignment: .top, spacing: 10) {
            Text(item.marker)
              .font(.caption2.weight(.bold))
              .foregroundStyle(accent)
              .frame(width: 22, height: 22)
              .background(accent.opacity(0.12), in: Circle())
            Text(item.text)
              .font(.subheadline)
              .foregroundStyle(Theme.inkSoft)
              .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
          }
        }
      }

    case .hint(let text):
      CoachHintCard(text: text, accent: accent)
    }
  }
}

// MARK: - Cards

private struct CoachFocusCard: View {
  let area: String
  let accent: Color

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      CoachBadge(symbol: "target", accent: accent)
      VStack(alignment: .leading, spacing: 2) {
        Text("Focus area")
          .eyebrow()
          .foregroundStyle(Theme.mutedInk)
        Text(area)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Theme.ink)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(12)
    .coachCard()
  }
}

private struct CoachQuestionCard: View {
  let question: CoachQuestion
  let accent: Color

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      CoachBadge(symbol: "questionmark", accent: accent)
      VStack(alignment: .leading, spacing: 4) {
        Text(question.title)
          .font(.subheadline.weight(.bold))
          .foregroundStyle(Theme.ink)
        if question.hasPrompt {
          Text(question.prompt)
            .font(.subheadline)
            .foregroundStyle(Theme.inkSoft)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(12)
    .coachCard()
  }
}

private struct CoachHintCard: View {
  let text: AttributedString
  let accent: Color

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "lightbulb.fill")
        .font(.footnote)
        .foregroundStyle(accent)
      Text(text)
        .font(.footnote)
        .foregroundStyle(Theme.inkSoft)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .padding(12)
    .background(
      accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}

private struct CoachBadge: View {
  let symbol: String
  let accent: Color

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: 14, weight: .bold))
      .foregroundStyle(accent)
      .frame(width: 32, height: 32)
      .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
}

// MARK: - Answers

private struct CoachChoiceGroup: View {
  let choices: [CoachChoice]
  let accent: Color
  let answered: String?
  let isAnswerable: Bool
  let onChoose: (CoachChoice) -> Void

  @Environment(\.dynamicTypeSize) private var typeSize

  /// Two columns only when every option is short enough to stay readable at half
  /// width — and never at an accessibility text size, where one column is the
  /// only thing that fits.
  private var isTwoColumn: Bool {
    !typeSize.isAccessibilitySize
      && choices.count >= 3
      && choices.allSatisfy { $0.text.count <= 46 }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(answered == nil ? "Choose your answer" : "Your answer")
        .eyebrow()
        .foregroundStyle(Theme.mutedInk)

      if isTwoColumn {
        LazyVGrid(
          columns: [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
          ],
          spacing: 8
        ) {
          ForEach(choices) { row($0) }
        }
      } else {
        VStack(spacing: 8) {
          ForEach(choices) { row($0) }
        }
      }
    }
  }

  private func row(_ choice: CoachChoice) -> some View {
    let isPicked = answered == choice.letter
    // Once it is answered, the option taken keeps its colour and the rest step
    // back. An older question nobody answered steps back entirely — it is no
    // longer live, and it should not look like it is.
    let isFaded = (answered != nil && !isPicked) || (answered == nil && !isAnswerable)

    return Button { onChoose(choice) } label: {
      HStack(alignment: .top, spacing: 10) {
        Text(choice.letter)
          .font(.footnote.weight(.bold))
          .foregroundStyle(isPicked ? Color.white : accent)
          .frame(width: 28, height: 28)
          .background(
            isPicked ? AnyShapeStyle(accent) : AnyShapeStyle(accent.opacity(0.12)),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
          )
        Text(choice.display)
          .font(.subheadline)
          .foregroundStyle(Theme.ink)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
        if isPicked {
          Image(systemName: "checkmark.circle.fill")
            .font(.footnote)
            .foregroundStyle(accent)
        }
      }
      .padding(10)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(
        isPicked ? AnyShapeStyle(accent.opacity(0.10)) : AnyShapeStyle(Theme.muted),
        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .strokeBorder(isPicked ? accent.opacity(0.55) : Theme.hairline, lineWidth: 1)
      }
      .opacity(isFaded ? 0.55 : 1)
      .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(CoachPressStyle())
    .disabled(!isAnswerable)
    .accessibilityLabel("Option \(choice.letter). \(choice.text)")
    .accessibilityAddTraits(isPicked ? [.isSelected] : [])
  }
}

// MARK: - Composer

/// Holds the draft itself, so a keystroke redraws the field rather than the
/// whole transcript above it.
private struct CoachComposer: View {
  let accent: Color
  let isSending: Bool
  let onSend: (String) -> Void

  @State private var draft = ""

  private var canSend: Bool { !draft.isBlank && !isSending }

  var body: some View {
    HStack(alignment: .bottom, spacing: 10) {
      TextField("Ask about your career or job hunt…", text: $draft, axis: .vertical)
        .lineLimit(1...5)
        .textFieldStyle(.plain)
        .submitLabel(.send)
        .onSubmit(send)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.muted, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Theme.hairline, lineWidth: 1)
        }

      Button(action: send) {
        Image(systemName: "arrow.up")
          .font(.system(size: 17, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 44, height: 44)
          .background(accent, in: Circle())
      }
      .buttonStyle(CoachPressStyle())
      .disabled(!canSend)
      .opacity(canSend ? 1 : 0.45)
      .accessibilityLabel("Send message")
    }
    .padding(.horizontal, 16)
    .padding(.top, 8)
    .padding(.bottom, 10)
    .background(Theme.card)
    .overlay(alignment: .top) { Divider().opacity(0.45) }
  }

  private func send() {
    let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !message.isEmpty, !isSending else { return }
    draft = ""
    onSend(message)
  }
}

// MARK: - Shared treatments

private struct CoachTypingDots: View {
  let accent: Color
  @State private var lit = 0

  var body: some View {
    HStack(spacing: 5) {
      ForEach(0..<3, id: \.self) { index in
        Circle()
          .fill(accent.opacity(lit == index ? 0.95 : 0.28))
          .frame(width: 7, height: 7)
          .scaleEffect(lit == index ? 1.15 : 0.85)
      }
    }
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(280))
        withAnimation(.easeInOut(duration: 0.25)) { lit = (lit + 1) % 3 }
      }
    }
    .accessibilityHidden(true)
  }
}

private struct CoachPressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
  }
}

extension View {
  /// A card *inside* the coach's bubble. No shadow: the bubble already casts one,
  /// and a second lift under it only muddies the stack.
  fileprivate func coachCard(radius: CGFloat = 16) -> some View {
    background(Theme.muted, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .strokeBorder(Theme.hairline, lineWidth: 1)
      }
  }
}

// MARK: - Entry point

struct FloatingCareerCoachButton: View {
  let accent: Color
  let showIntro: Bool
  let dismissIntro: () -> Void
  let action: () -> Void

  var body: some View {
    VStack(alignment: .trailing, spacing: 10) {
      if showIntro {
        HStack(spacing: 8) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Hi, I’m your Career Coach")
              .font(.caption.weight(.bold))
              .foregroundStyle(Theme.ink)
            Text("Ask me about work or your job hunt")
              .font(.caption2)
              .foregroundStyle(Theme.mutedInk)
          }
          Button(action: dismissIntro) {
            Image(systemName: "xmark")
              .font(.caption2.weight(.bold))
              .foregroundStyle(Theme.mutedInk)
          }
          .accessibilityLabel("Dismiss coach introduction")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Theme.hairline, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 14, y: 6)
        .transition(.move(edge: .trailing).combined(with: .opacity))
      }

      Button {
        dismissIntro()
        action()
      } label: {
        CareerCoachFace(accent: accent, size: 62)
          .overlay(alignment: .topTrailing) {
            Circle()
              .fill(Color.green)
              .frame(width: 13, height: 13)
              .overlay(Circle().stroke(Theme.paper, lineWidth: 2))
          }
          .shadow(color: accent.opacity(0.30), radius: 16, y: 8)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Open Career Coach")
      .accessibilityHint("Ask work and job-search questions using your saved career information")
    }
  }
}

struct CareerCoachFace: View {
  let accent: Color
  let size: CGFloat
  @State private var isBlinking = false

  var body: some View {
    ZStack {
      Circle()
        .fill(
          LinearGradient(
            colors: [accent, accent.opacity(0.72)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
      HStack(spacing: size * 0.17) {
        eye
        eye
      }
      .offset(y: -size * 0.10)
      SmileShape()
        .stroke(Color.white, style: StrokeStyle(lineWidth: max(2.5, size * 0.055), lineCap: .round))
        .frame(width: size * 0.38, height: size * 0.20)
        .offset(y: size * 0.14)
    }
    .frame(width: size, height: size)
    .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 1))
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(3))
        withAnimation(.easeInOut(duration: 0.10)) { isBlinking = true }
        try? await Task.sleep(for: .milliseconds(140))
        withAnimation(.easeInOut(duration: 0.10)) { isBlinking = false }
      }
    }
  }

  private var eye: some View {
    Capsule()
      .fill(Color.white)
      .frame(width: size * 0.10, height: isBlinking ? 2 : size * 0.16)
  }
}

private struct SmileShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX, y: rect.minY),
      control: CGPoint(x: rect.midX, y: rect.maxY)
    )
    return path
  }
}

#Preview {
  CareerCoachView(chatStore: CareerCoachStore())
    .environmentObject(ResumeStore(initialDocument: .example))
    .environmentObject(ApplicationStore())
    .environmentObject(CoverLetterStore(initialDocument: .example))
}
