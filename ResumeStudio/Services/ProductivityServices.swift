import Foundation
import PDFKit

enum TemplateRecommendationEngine {
  static func recommendations(
    preferences: TemplateFinderPreferences,
    unlocked: (ResumeTemplate) -> Bool = { _ in true }
  ) -> [TemplateRecommendation] {
    ResumeTemplate.allCases.compactMap { template in
      if preferences.freeOnly && !unlocked(template) { return nil }
      var score = 50
      var reasons: [String] = []
      let tags = template.styleTags

      if preferences.strictATS {
        if !template.plan.hasSideColumn && !template.isPhotoLed {
          score += 24
          reasons.append("Single-column, photo-free ATS structure")
        } else {
          score -= 18
        }
        if tags.contains(.ats) || tags.contains(.clean) { score += 10 }
      }

      if preferences.wantsPhoto == template.isPhotoLed {
        score += 16
        reasons.append(preferences.wantsPhoto ? "Designed around a portrait" : "Keeps the focus on your evidence")
      } else if preferences.wantsPhoto, !template.isPhotoLed {
        score -= 5
      }

      switch preferences.seniority {
      case .earlyCareer:
        if tags.contains(.clean) || tags.contains(.modern) { score += 10 }
      case .experienced:
        if tags.contains(.modern) || tags.contains(.structured) { score += 10 }
      case .leadership:
        if tags.contains(.bold) || tags.contains(.structured) { score += 12 }
      case .executive:
        if tags.contains(.classic) || tags.contains(.bold) { score += 14 }
      }

      let role = preferences.role.lowercased()
      let isCreativeRole = ["design", "creative", "brand", "art", "media", "fashion"].contains { role.contains($0) }
      let isTechnicalRole = ["engineer", "developer", "data", "security", "technical", "product"].contains { role.contains($0) }
      if isCreativeRole, tags.contains(.creative) {
        score += 14
        reasons.append("Creative presentation matches the target role")
      }
      if isTechnicalRole, tags.contains(.ats) || isTechnicalRole && tags.contains(.clean) {
        score += 12
        reasons.append("Clear technical information hierarchy")
      }

      if preferences.targetPages == .one {
        if template.plan.density < 1 || tags.contains(.clean) { score += 10 }
        if template.plan.hasSideColumn { score += 4 }
      }

      if [.unitedStates, .canada, .unitedKingdom].contains(preferences.market), template.isPhotoLed {
        score -= 14
      }
      if reasons.isEmpty { reasons.append(template.subtitle) }
      if unlocked(template) { reasons.append("Available on your current plan") }
      return TemplateRecommendation(template: template, score: score, reasons: Array(reasons.prefix(3)))
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
