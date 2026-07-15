import Foundation

// MARK: - Blocks

/// One piece of a coach reply, ready to draw.
///
/// The coach answers with a single markdown string. Put straight into a `Text`
/// that arrives as a wall of prose with literal `**` in it, and a multiple-choice
/// question becomes dead text the user has to answer by retyping a letter.
/// Splitting the reply up lets each piece get its own treatment — and turns the
/// options into buttons.
struct CoachBlock: Identifiable, Equatable {
  let id: Int
  let kind: Kind

  enum Kind: Equatable {
    /// Prose, with inline markdown already resolved.
    case paragraph(AttributedString)
    case heading(String)
    /// The development area the coach is steering towards.
    case focus(String)
    case question(CoachQuestion)
    /// Tappable answers. Always directly follows the question they belong to.
    case choices([CoachChoice])
    case bullets([CoachListItem])
    case steps([CoachListItem])
    case hint(AttributedString)
  }

  /// True for the blocks that read as the coach *talking*. Those sit beside the
  /// avatar; everything else is a card and spans the width of the bubble.
  var isSpeech: Bool {
    switch kind {
    case .paragraph, .heading: true
    default: false
    }
  }
}

struct CoachListItem: Identifiable, Equatable {
  let id: Int
  let marker: String
  let text: AttributedString
}

struct CoachQuestion: Equatable {
  let title: String
  let prompt: AttributedString

  var hasPrompt: Bool { !prompt.characters.isEmpty }
}

struct CoachChoice: Identifiable, Equatable {
  var id: String { letter }
  let letter: String
  /// Markdown stripped. This is what gets sent back, so it has to read as prose.
  let text: String
  let display: AttributedString

  /// What tapping the row sends. The letter is the answer the coach asked for;
  /// the text keeps the transcript meaningful when it is scrolled back to later.
  var reply: String { "\(letter) — \(text)" }

  /// The option a message answers, if it answers one at all.
  ///
  /// Which option was picked is read back out of the transcript rather than
  /// stored alongside it: the reply the user sent *is* the record of the choice.
  /// So a tapped answer still shows as picked after a relaunch, and typing "B"
  /// by hand counts exactly the same as tapping B.
  static func answered(in message: String, among choices: [CoachChoice]) -> String? {
    let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let first = trimmed.first else { return nil }
    let letter = String(first).uppercased()
    guard choices.contains(where: { $0.letter == letter }) else { return nil }

    // A message that is nothing but the letter answers with it, whichever case it
    // was typed in. A longer one has to be punctuated like an answer — "B.",
    // "B) …", "B — …" — so that a sentence merely opening with the letter ("But
    // why does that matter?") is not counted as picking it.
    let rest = trimmed.dropFirst().drop { $0 == " " }
    guard let next = rest.first else { return letter }
    guard first.isUppercase, Self.separators.contains(next) else { return nil }
    return letter
  }

  private static let separators: Set<Character> = [".", ")", ":", ",", "—", "–", "-"]
}

// MARK: - Parser

enum CoachReplyParser {

  static func parse(_ reply: String) -> [CoachBlock] {
    var parser = Parser()
    for line in reply.components(separatedBy: .newlines) {
      parser.consume(line)
    }
    parser.close()
    return parser.kinds.enumerated().map { CoachBlock(id: $0.offset, kind: $0.element) }
  }

  /// Resolves `**bold**`, `*italic*`, `` `code` `` and links.
  static func inline(_ markdown: String) -> AttributedString {
    let options = AttributedString.MarkdownParsingOptions(
      interpretedSyntax: .inlineOnlyPreservingWhitespace,
      failurePolicy: .returnPartiallyParsedIfPossible
    )
    return (try? AttributedString(markdown: balanced(markdown), options: options))
      ?? AttributedString(markdown)
  }

  /// The reply with its markdown resolved away — for copying, and for the text
  /// we send back when an option is tapped.
  static func plain(_ markdown: String) -> String {
    String(inline(markdown).characters)
  }

  /// Drops a stray `**` left over from a line whose emphasis we split across
  /// blocks, so it renders as emphasis rather than as two asterisks.
  private static func balanced(_ text: String) -> String {
    guard text.components(separatedBy: "**").count % 2 == 0 else { return text }
    if text.hasSuffix("**") { return String(text.dropLast(2)) }
    if text.hasPrefix("**") { return String(text.dropFirst(2)) }
    return text
  }

  // MARK: Line shapes

  /// `A. text`, `B) text`, `**C.** text`, `- D. text`.
  private static let choiceLine = #/^(?:[-*•]\s+)?(?:\*\*)?([A-H])(?:\*\*)?[.):](?:\*\*)?\s+(\S.*)$/#
  private static let questionLine =
    #/^(?:#{1,4}\s+)?(?:\*\*)?\s*Question\s+(\d+)\s*[:.)]?\s*(?:\*\*)?\s*(.*)$/#.ignoresCase()
  private static let hashHeading = #/^#{1,4}\s+(\S.*?)\s*$/#
  /// A line that is bold end to end — how models tend to write a subheading.
  private static let boldHeading = #/^\*\*(\S.*?)\*\*:?\s*$/#
  private static let bulletLine = #/^[-*•+]\s+(\S.*)$/#
  private static let stepLine = #/^(\d{1,2})[.)]\s+(\S.*)$/#
  private static let tipLine =
    #/^(?:\*\*)?(?:tip|hint|note|remember|pro tip)\s*:\s*(?:\*\*)?\s*(\S.*)$/#.ignoresCase()
  /// "Reply with A, B, C or D…" — an instruction, now that the options are buttons.
  private static let answerInstruction =
    #/^(?:\*\*)?(?:reply|respond|answer|choose|select|pick|tap)\b/#.ignoresCase()
  /// A standalone option letter. Case-sensitive on purpose: a lone lowercase "a"
  /// is the article, not an option.
  private static let optionLetter = #/\b[A-H]\b/#
  /// "…a likely development area based on your background: **people analytics**."
  /// The area itself cannot contain a `*`, so a paragraph that merely happens to
  /// have several bold runs in it does not read as one.
  private static let focusParagraph = #/^(.{3,300}?):\s*\*\*([^*]{2,70})\*\*[.!]?$/#
  private static let focusLeadIn =
    #/area|focus|topic|gap|weak|develop|improv|priorit|strength|skill/#.ignoresCase()

  // MARK: State machine

  private struct Parser {
    var kinds: [CoachBlock.Kind] = []

    private var paragraph: [String] = []
    private var bullets: [String] = []
    private var steps: [(String, String)] = []
    private var choices: [PendingChoice] = []
    private var questionTitle: String?
    private var questionPrompt: [String] = []
    private var lastLineWasChoice = false

    private struct PendingChoice {
      let letter: Character
      var text: String
      /// Kept so a run that turns out not to be an option list can go back to
      /// being prose, rather than being silently dropped.
      let source: String
    }

    mutating func consume(_ raw: String) {
      let line = raw.trimmingCharacters(in: .whitespaces)

      guard !line.isEmpty else {
        closeRun()
        // A question header on its own line is still waiting for its prompt, so
        // it only closes once it has one.
        if !questionPrompt.isEmpty { flushQuestion() }
        return
      }

      if let match = line.firstMatch(of: choiceLine), let letter = match.1.first {
        closeProse()
        choices.append(PendingChoice(letter: letter, text: String(match.2), source: line))
        lastLineWasChoice = true
        return
      }

      // An option long enough to be hard-wrapped by the model continues on the
      // next line. An instruction or a new block does not.
      if lastLineWasChoice, !choices.isEmpty, isContinuation(line) {
        choices[choices.count - 1].text += " " + line
        return
      }
      lastLineWasChoice = false
      flushChoices()

      if let match = line.firstMatch(of: tipLine) {
        closeProse()
        kinds.append(.hint(inline(String(match.1))))
        return
      }
      if isAnswerInstruction(line) {
        closeProse()
        kinds.append(.hint(inline(line)))
        return
      }
      if let match = line.firstMatch(of: questionLine) {
        closeProse()
        questionTitle = "Question \(match.1)"
        let prompt = String(match.2).trimmingCharacters(in: .whitespaces)
        if !prompt.isEmpty { questionPrompt = [prompt] }
        return
      }
      if let match = line.firstMatch(of: hashHeading) {
        closeProse()
        kinds.append(.heading(plain(String(match.1))))
        return
      }
      if let match = line.firstMatch(of: boldHeading) {
        closeProse()
        kinds.append(.heading(plain(String(match.1))))
        return
      }
      if let match = line.firstMatch(of: bulletLine) {
        flushParagraph()
        flushSteps()
        flushQuestion()
        bullets.append(String(match.1))
        return
      }
      if let match = line.firstMatch(of: stepLine) {
        flushParagraph()
        flushBullets()
        flushQuestion()
        steps.append((String(match.1), String(match.2)))
        return
      }

      // Prose. While a question is still waiting for its prompt, this is it.
      if questionTitle != nil {
        questionPrompt.append(line)
        return
      }
      flushBullets()
      flushSteps()
      paragraph.append(line)
    }

    mutating func close() {
      closeRun()
      flushQuestion()
    }

    /// Everything a blank line ends.
    private mutating func closeRun() {
      flushParagraph()
      flushBullets()
      flushSteps()
      flushChoices()
      lastLineWasChoice = false
    }

    /// Everything a new block of a different kind ends.
    private mutating func closeProse() {
      flushParagraph()
      flushBullets()
      flushSteps()
      flushQuestion()
    }

    private func isContinuation(_ line: String) -> Bool {
      line.firstMatch(of: tipLine) == nil
        && line.firstMatch(of: questionLine) == nil
        && line.firstMatch(of: hashHeading) == nil
        && line.firstMatch(of: boldHeading) == nil
        && line.firstMatch(of: bulletLine) == nil
        && line.firstMatch(of: stepLine) == nil
        && !isAnswerInstruction(line)
    }

    /// "Reply with A, B, C, or D" is an instruction. "Choose a role you want" is
    /// a sentence — so it takes two option letters to count, not just the verb.
    private func isAnswerInstruction(_ line: String) -> Bool {
      guard line.firstMatch(of: answerInstruction) != nil else { return false }
      return line.matches(of: optionLetter).count >= 2
    }

    private mutating func flushParagraph() {
      guard !paragraph.isEmpty else { return }
      let text = paragraph.joined(separator: " ")
      paragraph = []

      // "…based on your background: **people analytics**." reads better as a
      // sentence plus a card than as one line with a bold tail.
      if let match = text.firstMatch(of: focusParagraph), String(match.1).contains(focusLeadIn) {
        kinds.append(.paragraph(inline(String(match.1) + ".")))
        kinds.append(.focus(sentenceCased(plain(String(match.2)))))
        return
      }
      kinds.append(.paragraph(inline(text)))
    }

    private mutating func flushBullets() {
      guard !bullets.isEmpty else { return }
      kinds.append(
        .bullets(
          bullets.enumerated().map {
            CoachListItem(id: $0.offset, marker: "•", text: inline($0.element))
          }))
      bullets = []
    }

    private mutating func flushSteps() {
      guard !steps.isEmpty else { return }
      kinds.append(
        .steps(
          steps.enumerated().map {
            CoachListItem(id: $0.offset, marker: $0.element.0, text: inline($0.element.1))
          }))
      steps = []
    }

    private mutating func flushQuestion() {
      guard let title = questionTitle else { return }
      questionTitle = nil
      let prompt = questionPrompt.joined(separator: " ")
      questionPrompt = []
      kinds.append(.question(CoachQuestion(title: title, prompt: inline(prompt))))
    }

    private mutating func flushChoices() {
      guard !choices.isEmpty else { return }
      let pending = choices
      choices = []

      // Only a run that runs A, B, C… in order is an option list. Anything else
      // is prose that happens to start with a letter, and goes back to being prose.
      let expected = (0..<pending.count).map { Character(UnicodeScalar(UInt8(65 + $0))) }
      guard pending.count >= 2, pending.map(\.letter) == expected else {
        for choice in pending { kinds.append(.paragraph(inline(choice.source))) }
        return
      }

      kinds.append(
        .choices(
          pending.map {
            CoachChoice(
              letter: String($0.letter),
              text: plain($0.text),
              display: inline($0.text)
            )
          }))
    }

    private func sentenceCased(_ text: String) -> String {
      guard let first = text.first else { return text }
      return first.uppercased() + text.dropFirst()
    }
  }
}
