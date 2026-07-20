import Foundation

enum JobDescriptionAnalyzer {
  static func analyze(_ text: String) -> JobDescriptionQuality {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let words = trimmed.split(whereSeparator: \.isWhitespace)
    let lower = trimmed.lowercased()
    var blockers: [String] = []
    var suggestions: [String] = []

    if words.count < 40 {
      blockers.append("Paste the full job advert—not only the job title.")
    }
    if !lower.contains("responsib") && !lower.contains("duties") && !lower.contains("you will") {
      suggestions.append("Include the responsibilities or duties section.")
    }
    if !lower.contains("require") && !lower.contains("qualification") && !lower.contains("experience") {
      suggestions.append("Include required experience, qualifications and skills.")
    }
    if !lower.contains("company") && words.count < 100 {
      suggestions.append("Add company context so recommendations can match its priorities.")
    }
    let score = min(100, max(10, words.count * 2) - blockers.count * 20 - suggestions.count * 8)
    return JobDescriptionQuality(score: score, blockingIssues: blockers, suggestions: suggestions)
  }
}

enum ATSReadinessService {
  /// The share of an advert's meaningful language a résumé must already contain
  /// before the keyword check passes. Adverts carry a lot of words no résumé
  /// will ever mirror, so this sits well below a half. Opportunity ranking is
  /// anchored to the same number so the two features cannot disagree about what
  /// counts as a good match.
  static let jobLanguagePassThreshold = 0.18

  static func analyze(document: ResumeDocument, jobDescription: String = "") -> ATSReadinessReport {
    var items: [ATSCheckItem] = []
    func add(_ id: String, _ title: String, _ detail: String, _ severity: ATSIssueSeverity, _ section: ResumeSection? = nil) {
      items.append(ATSCheckItem(id: id, title: title, detail: detail, severity: severity, section: section))
    }

    add("contact", "Contact information",
        document.personal.email.isBlank || document.personal.phone.isBlank
          ? "Add both an email address and phone number." : "Email and phone are present.",
        document.personal.email.isBlank || document.personal.phone.isBlank ? .action : .pass, .personal)
    add("profile", "Professional profile",
        document.professionalProfile.split(whereSeparator: \.isWhitespace).count < 25
          ? "Use a focused 3–5 line profile grounded in your experience." : "Profile has useful detail.",
        document.professionalProfile.split(whereSeparator: \.isWhitespace).count < 25 ? .warning : .pass, .profile)
    add("experience", "Experience evidence",
        document.experience.flatMap(\.highlights).filter { !$0.isBlank }.count < 3
          ? "Add at least three evidence-based achievement or responsibility bullets." : "Experience includes supporting bullets.",
        document.experience.flatMap(\.highlights).filter { !$0.isBlank }.count < 3 ? .action : .pass, .experience)
    let longBullets = document.experience.flatMap(\.highlights).filter { $0.count > 220 }.count
    add("length", "Readable bullet length", longBullets == 0 ? "Bullets are concise." : "Shorten \(longBullets) bullet(s) longer than 220 characters.", longBullets == 0 ? .pass : .warning, .experience)
    let weakStarts = ["responsible for", "helped", "worked on", "tasked with"]
    let weakCount = document.experience.flatMap(\.highlights).filter { bullet in
      weakStarts.contains { bullet.lowercased().hasPrefix($0) }
    }.count
    add("verbs", "Strong opening verbs", weakCount == 0 ? "No common weak openings found." : "Rewrite \(weakCount) bullet(s) that begin with passive wording.", weakCount == 0 ? .pass : .warning, .experience)
    add(
      "format",
      "ATS-safe structure",
      document.showsPortrait
        ? "For conservative ATS portals, turn off Show in CV under Personal Details or use an ATS-safe preview. Your saved photo will not be deleted."
        : "This résumé prints no profile photo.",
      document.showsPortrait ? .warning : .pass,
      .personal
    )
    // Two columns of real text stay selectable and searchable, but some parsers
    // read them in the wrong order. Worth saying before an application vanishes.
    add("columns", "Single-column parsing", document.template.plan.hasSideColumn ? "This template puts contact details and skills in a second column. It stays selectable, but some applicant-tracking systems read columns out of order — keep a single-column version for the strictest portals." : "A single column of text, which every parser reads in order.", document.template.plan.hasSideColumn ? .warning : .pass)

    if !jobDescription.isBlank {
      let resumeWords = Set(AIResumeSnapshot(document: document).searchableText.meaningfulWords)
      let jobWords = Set(jobDescription.meaningfulWords)
      let overlap = jobWords.isEmpty ? 0 : Double(jobWords.intersection(resumeWords).count) / Double(jobWords.count)
      add("keywords", "Job-language evidence", overlap >= jobLanguagePassThreshold ? "The résumé demonstrates a useful share of the advert’s terminology." : "Review missing requirements and add only keywords supported by real evidence.", overlap >= jobLanguagePassThreshold ? .pass : .action, .competencies)
      return ATSReadinessReport(
        items: items,
        matchedKeywords: Array(jobWords.intersection(resumeWords)).sorted(),
        missingKeywords: Array(jobWords.subtracting(resumeWords)).sorted()
      )
    }
    return ATSReadinessReport(items: items)
  }

  static func keywordSuggestions(document: ResumeDocument, jobDescription: String) -> [ATSKeywordSuggestion] {
    let resumeWords = Set(AIResumeSnapshot(document: document).searchableText.meaningfulWords)
    let counts = Dictionary(grouping: jobDescription.meaningfulWords, by: { $0 }).mapValues(\.count)
    return counts.filter { !resumeWords.contains($0.key) }
      .sorted { lhs, rhs in lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value }
      .prefix(12)
      .map { keyword, _ in
        let section: ResumeSection = keyword.count < 18 ? .competencies : .experience
        return ATSKeywordSuggestion(
          keyword: keyword,
          section: section,
          guidance: section == .competencies
            ? "Add only if this is a skill you can demonstrate."
            : "Connect this language to a truthful responsibility or outcome."
        )
      }
  }
}

private extension AIResumeSnapshot {
  var searchableText: String {
    ([headline, professionalProfile] + competencies + experience.flatMap { [$0.role, $0.company] + $0.highlights }).joined(separator: " ")
  }
}

private extension String {
  var words: [String] {
    lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }
  }

  var meaningfulWords: [String] {
    let stop: Set<String> = ["about", "after", "again", "also", "and", "are", "been", "being", "company", "from", "have", "into", "more", "must", "our", "role", "that", "the", "their", "this", "through", "with", "will", "work", "your", "years"]
    return words.filter { $0.count > 3 && !stop.contains($0) }
  }
}
