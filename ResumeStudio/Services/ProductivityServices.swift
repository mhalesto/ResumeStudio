import Foundation
import PDFKit

enum TemplateRecommendationEngine {
  static func recommendations(
    preferences: TemplateFinderPreferences,
    unlocked: (ResumeTemplate) -> Bool = { _ in true }
  ) -> [TemplateRecommendation] {
    ResumeTemplate.allCases.compactMap { template in
      if preferences.freeOnly && !unlocked(template) { return nil }
      // This is a compatibility score, not a probability. Keep the weights
      // deliberately below 100 in ordinary cases so several broad tag matches
      // do not all collapse into a misleading perfect score.
      var score = 32
      var rankedReasons: [(priority: Int, text: String)] = []
      let tags = template.styleTags
      let plan = template.plan

      func reward(_ points: Int, _ reason: String? = nil, priority: Int = 0) {
        score += points
        if let reason { rankedReasons.append((priority, reason)) }
      }

      func penalize(_ points: Int) {
        score -= points
      }

      if preferences.strictATS {
        if !plan.hasSideColumn && !template.isPhotoLed {
          reward(18, "Single-column, photo-free ATS structure", priority: 100)
        } else {
          if plan.hasSideColumn { penalize(12) }
          if template.isPhotoLed { penalize(10) }
        }
        if tags.contains(.ats) {
          reward(8, "Explicitly tagged for ATS-friendly parsing", priority: 96)
        } else if tags.contains(.clean) {
          reward(4, "Clean structure supports parser readability", priority: 72)
        }
      }

      if preferences.wantsPhoto == template.isPhotoLed {
        reward(
          7,
          preferences.wantsPhoto ? "Designed around a portrait" : "Keeps the focus on your evidence",
          priority: 70)
      } else if preferences.wantsPhoto, !template.isPhotoLed {
        penalize(6)
      } else if !preferences.wantsPhoto, template.isPhotoLed {
        penalize(7)
      }

      switch preferences.seniority {
      case .earlyCareer:
        if tags.contains(.clean) {
          reward(7, "Clean hierarchy suits an early-career résumé", priority: 64)
        }
        if tags.contains(.modern) { reward(3) }
      case .experienced:
        if tags.contains(.structured) {
          reward(7, "Structured hierarchy suits experienced candidates", priority: 66)
        }
        if tags.contains(.modern) { reward(4) }
        if tags.contains(.clean) { reward(2) }
      case .leadership:
        if tags.contains(.bold) {
          reward(7, "Confident presentation supports a leadership profile", priority: 66)
        }
        if tags.contains(.structured) { reward(6) }
        if tags.contains(.classic) { reward(2) }
      case .executive:
        if tags.contains(.classic) {
          reward(8, "Classic hierarchy suits an executive résumé", priority: 68)
        }
        if tags.contains(.bold) { reward(6) }
        if tags.contains(.structured) { reward(3) }
      }

      let role = preferences.role.lowercased()
      let isCreativeRole = ["design", "creative", "brand", "art", "media", "fashion"].contains { role.contains($0) }
      let isTechnicalRole = ["engineer", "developer", "data", "security", "technical", "product"].contains { role.contains($0) }
      let isTraditionalRole = [
        "account", "bank", "compliance", "finance", "government", "legal", "research",
      ].contains { role.contains($0) }
      let isPeopleRole = [
        "customer", "human resources", "operations", "people", "recruit", "sales",
      ].contains { role.contains($0) }
      if isCreativeRole {
        if tags.contains(.creative) {
          reward(9, "Creative presentation matches the target role", priority: 88)
        }
        if tags.contains(.bold) || tags.contains(.showcase) { reward(3) }
      }
      if isTechnicalRole {
        if tags.contains(.ats) { reward(6) }
        if tags.contains(.clean) { reward(4) }
        if tags.contains(.structured) { reward(3) }
        if tags.contains(.ats) || tags.contains(.clean) || tags.contains(.structured) {
          rankedReasons.append((86, "Clear technical information hierarchy"))
        }
      }
      if isTraditionalRole {
        if tags.contains(.classic) { reward(6) }
        if tags.contains(.ats) { reward(5) }
        if tags.contains(.classic) || tags.contains(.ats) {
          rankedReasons.append((84, "Conventional hierarchy matches the target field"))
        }
      }
      if isPeopleRole {
        if tags.contains(.structured) { reward(5) }
        if tags.contains(.clean) { reward(3) }
        if tags.contains(.structured) || tags.contains(.clean) {
          rankedReasons.append((82, "Scannable hierarchy supports a people-focused role"))
        }
      }

      switch preferences.targetPages {
      case .automatic:
        break
      case .one:
        if plan.density <= 0.9 {
          reward(6, "Compact spacing supports a one-page target", priority: 78)
        } else if plan.density < 1 {
          reward(4, "Efficient spacing supports a one-page target", priority: 76)
        } else {
          reward(2)
        }
        if tags.contains(.clean) { reward(2) }
        switch plan.competencies {
        case .columns, .iconGrid: reward(2)
        case .chips: reward(1)
        default: break
        }
        if plan.hasSideColumn, !preferences.strictATS { reward(2) }
      case .two:
        if plan.density >= 1 {
          reward(4, "Generous spacing suits a two-page résumé", priority: 74)
        }
        if plan.hasSideColumn { reward(2) }
      }

      if [.unitedStates, .canada, .unitedKingdom].contains(preferences.market) {
        if template.isPhotoLed {
          penalize(12)
        } else {
          reward(3)
        }
        if tags.contains(.ats) { reward(3, "Matches common market screening conventions", priority: 80) }
      }

      var seenReasons: Set<String> = []
      var reasons = rankedReasons
        .sorted { lhs, rhs in
          lhs.priority == rhs.priority ? lhs.text < rhs.text : lhs.priority > rhs.priority
        }
        .compactMap { item -> String? in
          seenReasons.insert(item.text).inserted ? item.text : nil
        }
      if reasons.isEmpty { reasons = [template.subtitle] }
      reasons = Array(reasons.prefix(unlocked(template) ? 2 : 3))
      if unlocked(template) { reasons.append("Available on your current plan") }
      return TemplateRecommendation(template: template, score: score, reasons: reasons)
    }
    .sorted { lhs, rhs in
      lhs.score == rhs.score ? lhs.template.title < rhs.template.title : lhs.score > rhs.score
    }
  }
}

enum ApplicationAnalyticsService {
  static func summarize(_ applications: [JobApplication]) -> ApplicationAnalyticsSummary {
    guard !applications.isEmpty else { return .empty }
    let appliedItems = applications.filter { $0.status != .saved }
    let interviewItems = applications.filter { $0.status == .interview || $0.status == .offer }
    let offerItems = applications.filter { $0.status == .offer }
    let responseItems = applications.filter { [.interview, .offer, .rejected].contains($0.status) }
    let responseDays = responseItems.compactMap { application -> Double? in
      let response = application.activityTimeline
        .filter { [.interview, .offer, .statusChanged].contains($0.kind) }
        .map(\.occurredAt).min()
      guard let response else { return nil }
      return max(0, response.timeIntervalSince(application.createdAt) / 86_400)
    }

    let sourceGroups = Dictionary(grouping: applications) { application -> String in
      guard let url = URL(string: application.sourceURL), let host = url.host() else {
        return application.sourceURL.nilIfBlank == nil ? "Direct / manual" : "Other"
      }
      return host.replacingOccurrences(of: "www.", with: "")
    }
    let resumeGroups = Dictionary(grouping: applications) {
      $0.tailoredResumeID ?? $0.baseResumeID
    }

    return ApplicationAnalyticsSummary(
      tracked: applications.count,
      applied: appliedItems.count,
      interviews: interviewItems.count,
      offers: offerItems.count,
      responses: responseItems.count,
      applicationToInterviewRate: percentage(interviewItems.count, appliedItems.count),
      interviewToOfferRate: percentage(offerItems.count, interviewItems.count),
      averageDaysToResponse: responseDays.isEmpty ? nil : responseDays.reduce(0, +) / Double(responseDays.count),
      bySource: sourceGroups.map { name, values in
        ApplicationSourceMetric(
          name: name,
          count: values.count,
          interviews: values.count { $0.status == .interview || $0.status == .offer })
      }.sorted { $0.count > $1.count },
      byResume: resumeGroups.map { id, values in
        ApplicationResumeMetric(
          id: id,
          count: values.count,
          interviews: values.count { $0.status == .interview || $0.status == .offer })
      }.sorted { $0.count > $1.count }
    )
  }

  private static func percentage(_ numerator: Int, _ denominator: Int) -> Int {
    denominator == 0 ? 0 : Int((Double(numerator) / Double(denominator) * 100).rounded())
  }
}

enum ResumeAutoFitService {
  struct Result {
    var document: ResumeDocument
    var pageCount: Int
    var reachedTarget: Bool
  }

  @MainActor
  static func fit(_ source: ResumeDocument, target: ResumePageTarget) throws -> Result {
    guard let targetCount = target.pageCount else {
      let pages = PDFDocument(data: try ResumePDFRenderer.render(document: source))?.pageCount ?? 0
      return Result(document: source, pageCount: pages, reachedTarget: true)
    }

    var candidate = source
    var scale = min(source.layout.fontScale, 1)
    var lastPages = Int.max
    while scale >= 0.82 {
      candidate.layout.fontScale = scale
      let data = try ResumePDFRenderer.render(document: candidate)
      lastPages = PDFDocument(data: data)?.pageCount ?? Int.max
      if lastPages <= targetCount {
        return Result(document: candidate, pageCount: lastPages, reachedTarget: true)
      }
      scale = (scale - 0.03).rounded(toPlaces: 2)
    }
    candidate.layout.fontScale = 0.82
    return Result(document: candidate, pageCount: lastPages, reachedTarget: false)
  }
}

enum ApplicationPacketExporter {
  @MainActor
  static func files(packet: ApplicationPacket, application: JobApplication, resume: ResumeDocument) throws -> [URL] {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("ResumeStudio Packet \(packet.id.uuidString)", isDirectory: true)
    try? FileManager.default.removeItem(at: root)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let resumeURL = root.appendingPathComponent(resume.suggestedFilename).appendingPathExtension("pdf")
    try ResumePDFRenderer.render(document: resume).write(to: resumeURL, options: .atomic)
    let letterURL = root.appendingPathComponent(packet.coverLetter.suggestedFilename).appendingPathExtension("pdf")
    try CoverLetterPDFRenderer.render(document: packet.coverLetter).write(to: letterURL, options: .atomic)
    let emailURL = root.appendingPathComponent("Application Email.txt")
    try "Subject: \(packet.applicationEmailSubject)\n\n\(packet.applicationEmailBody)"
      .write(to: emailURL, atomically: true, encoding: .utf8)
    let followUpURL = root.appendingPathComponent("Follow-up Email.txt")
    try "Subject: \(packet.followUpEmailSubject)\n\n\(packet.followUpEmailBody)"
      .write(to: followUpURL, atomically: true, encoding: .utf8)
    let notesURL = root.appendingPathComponent("Application Notes.txt")
    let checklist = packet.interviewChecklist.map { "- \($0)" }.joined(separator: "\n")
    try "\(application.role) at \(application.company)\n\nSource: \(application.sourceURL)\n\nInterview checklist\n\(checklist)"
      .write(to: notesURL, atomically: true, encoding: .utf8)
    return [resumeURL, letterURL, emailURL, followUpURL, notesURL]
  }
}

enum ResumeMarketLocalizationService {
  static func apply(market: ResumeMarket, language: String, to document: inout ResumeDocument) {
    document.layout.paperSize = [.unitedStates, .canada].contains(market) ? .letter : .a4
    let headings = localizedHeadings(language: language)
    if !headings.isEmpty { document.layout.customHeadings.merge(headings) { _, new in new } }
  }

  static func localizedHeadings(language: String) -> [String: String] {
    let key = language.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    let values: [ResumeContentBlock: String]
    switch key {
    case "afrikaans":
      values = [.profile: "Professionele Profiel", .competencies: "Kernvaardighede", .experience: "Werkservaring", .education: "Opleiding", .references: "Verwysings"]
    case "isizulu", "zulu":
      values = [.profile: "Iphrofayela Yomsebenzi", .competencies: "Amakhono Abalulekile", .experience: "Ulwazi Lomsebenzi", .education: "Imfundo", .references: "Izinkomba"]
    case "french", "français", "francais":
      values = [.profile: "Profil Professionnel", .competencies: "Compétences Clés", .experience: "Expérience Professionnelle", .education: "Formation", .references: "Références"]
    case "german", "deutsch":
      values = [.profile: "Berufsprofil", .competencies: "Kernkompetenzen", .experience: "Berufserfahrung", .education: "Ausbildung", .references: "Referenzen"]
    case "spanish", "español", "espanol":
      values = [.profile: "Perfil Profesional", .competencies: "Competencias Clave", .experience: "Experiencia Profesional", .education: "Formación", .references: "Referencias"]
    case "portuguese", "português", "portugues":
      values = [.profile: "Perfil Profissional", .competencies: "Competências Principais", .experience: "Experiência Profissional", .education: "Formação", .references: "Referências"]
    default:
      return [:]
    }
    return Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) })
  }
}

private extension Double {
  func rounded(toPlaces places: Int) -> Double {
    let divisor = pow(10, Double(places))
    return (self * divisor).rounded() / divisor
  }
}
