import Foundation
import PDFKit
import UIKit
import Vision
import ZIPFoundation

enum ResumeDOCXRenderer {
  static func render(document: ResumeDocument) throws -> Data {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let word = root.appendingPathComponent("word", isDirectory: true)
    let rels = root.appendingPathComponent("_rels", isDirectory: true)
    let wordRels = word.appendingPathComponent("_rels", isDirectory: true)
    try FileManager.default.createDirectory(at: word, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: rels, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: wordRels, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try xmlContentTypes.write(to: root.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)
    try packageRelationships.write(to: rels.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)
    try documentRelationships.write(to: wordRels.appendingPathComponent("document.xml.rels"), atomically: true, encoding: .utf8)
    try stylesXML(accent: document.accent).write(to: word.appendingPathComponent("styles.xml"), atomically: true, encoding: .utf8)
    try documentXML(document).write(to: word.appendingPathComponent("document.xml"), atomically: true, encoding: .utf8)

    let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("docx")
    defer { try? FileManager.default.removeItem(at: destination) }
    try FileManager.default.zipItem(at: root, to: destination, shouldKeepParent: false)
    return try Data(contentsOf: destination)
  }

  private static func documentXML(_ document: ResumeDocument) -> String {
    var body: [String] = []
    func paragraph(_ text: String, style: String? = nil) {
      guard !text.isBlank else { return }
      let styleXML = style.map { "<w:pPr><w:pStyle w:val=\"\($0)\"/></w:pPr>" } ?? ""
      body.append("<w:p>\(styleXML)<w:r><w:t xml:space=\"preserve\">\(text.xmlEscaped)</w:t></w:r></w:p>")
    }
    func heading(_ value: String) { paragraph(value.uppercased(), style: "Heading1") }
    func bullet(_ value: String) { paragraph("• \(value)", style: "Bullet") }

    paragraph(document.personal.fullName, style: "Title")
    paragraph(document.personal.headline, style: "Subtitle")
    paragraph([document.personal.phone, document.personal.email].filter { !$0.isBlank }.joined(separator: "  |  "))
    heading("Professional Profile"); paragraph(document.professionalProfile)
    heading("Core Competencies"); document.competencies.filter { !$0.isBlank }.forEach(bullet)
    heading("Professional Experience")
    for entry in document.experience where !entry.role.isBlank || !entry.company.isBlank {
      paragraph(entry.role, style: "Heading2")
      paragraph([entry.company, entry.period].filter { !$0.isBlank }.joined(separator: "  |  "))
      entry.highlights.filter { !$0.isBlank }.forEach(bullet)
    }
    heading("Education")
    for entry in document.education where !entry.qualification.isBlank || !entry.institution.isBlank {
      paragraph(entry.qualification, style: "Heading2")
      paragraph([entry.institution, entry.period].filter { !$0.isBlank }.joined(separator: "  |  "))
      paragraph(entry.details)
    }
    for section in document.additionalSections where !section.title.isBlank {
      heading(section.title); section.items.filter { !$0.isBlank }.forEach(bullet)
    }
    if !document.references.isEmpty {
      heading("References")
      for reference in document.references where !reference.name.isBlank {
        paragraph(reference.name, style: "Heading2")
        paragraph([reference.company, reference.phone, reference.email].filter { !$0.isBlank }.joined(separator: "  |  "))
      }
    }

    return """
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
      \(body.joined())
      <w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134"/></w:sectPr>
      </w:body></w:document>
      """
  }

  private static func stylesXML(accent: ResumeAccent) -> String {
    let color: String
    switch accent {
    case .orange: color = "D1470A"
    case .blue: color = "1C61B3"
    case .teal: color = "0D7878"
    case .burgundy: color = "8C1A36"
    case .emerald: color = "0F734F"
    case .amethyst: color = "734299"
    case .sapphire: color = "213D94"
    case .rose: color = "C95270"
    case .midnight: color = "242E47"
    case .bronze: color = "A1702E"
    case .graphite: color = "424A54"
    case .plum: color = "6B2E61"
    case .steel: color = "476B87"
    case .terracotta: color = "BF6347"
    case .champagne: color = "9B6E24"
    case .peacock: color = "0A6670"
    case .mulberry: color = "89335E"
    case .moss: color = "5C6B3B"
    case .cobalt: color = "334FA3"
    case .cocoa: color = "6B473D"
    }
    return """
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:rPr><w:rFonts w:ascii="Aptos"/><w:sz w:val="20"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:rPr><w:b/><w:color w:val="\(color)"/><w:sz w:val="36"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Subtitle"><w:name w:val="Subtitle"/><w:rPr><w:b/><w:sz w:val="23"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="Heading 1"/><w:pPr><w:spacing w:before="220" w:after="80"/></w:pPr><w:rPr><w:b/><w:color w:val="\(color)"/><w:sz w:val="23"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="Heading 2"/><w:rPr><w:b/><w:sz w:val="21"/></w:rPr></w:style>
      <w:style w:type="paragraph" w:styleId="Bullet"><w:name w:val="Bullet"/><w:pPr><w:ind w:left="360" w:hanging="180"/></w:pPr></w:style>
      </w:styles>
      """
  }

  private static let xmlContentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>
    """
  private static let packageRelationships = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
    """
  private static let documentRelationships = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>
    """
}

enum ResumeImportService {
  /// Extracts readable source text locally. The original file never leaves the
  /// device; this text is what the explicit AI import action sends for structuring.
  static func extractText(from urls: [URL]) throws -> String {
    var sources: [String] = []
    for url in urls {
      let accessed = url.startAccessingSecurityScopedResource()
      defer { if accessed { url.stopAccessingSecurityScopedResource() } }
      let heading = "SOURCE FILE: \(url.lastPathComponent)"
      switch url.pathExtension.lowercased() {
      case "pdf":
        guard let pdf = PDFDocument(url: url) else { throw CocoaError(.fileReadCorruptFile) }
        let text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
        sources.append("\(heading)\n\(text)")
      case "docx":
        sources.append("\(heading)\n\(try extractDOCX(url))")
      case "csv":
        sources.append("\(heading)\n\(try String(contentsOf: url, encoding: .utf8))")
      case "zip":
        let csvs = try extractCSVs(url)
        sources.append(contentsOf: csvs.map { "SOURCE FILE: \($0.0)\n\($0.1)" })
      default:
        sources.append("\(heading)\n\(try String(contentsOf: url, encoding: .utf8))")
      }
    }
    return sources.joined(separator: "\n\n")
  }

  static func importDocuments(from urls: [URL]) throws -> ResumeDocument {
    var texts: [String] = []
    var csvs: [(String, String)] = []
    for url in urls {
      let accessed = url.startAccessingSecurityScopedResource()
      defer { if accessed { url.stopAccessingSecurityScopedResource() } }
      switch url.pathExtension.lowercased() {
      case "pdf":
        guard let pdf = PDFDocument(url: url) else { throw CocoaError(.fileReadCorruptFile) }
        texts.append((0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n"))
      case "docx": texts.append(try extractDOCX(url))
      case "csv": csvs.append((url.lastPathComponent, try String(contentsOf: url, encoding: .utf8)))
      case "zip": csvs.append(contentsOf: try extractCSVs(url))
      default: texts.append(try String(contentsOf: url, encoding: .utf8))
      }
    }
    if !csvs.isEmpty { return parseLinkedIn(csvs) }
    return parseResumeText(texts.joined(separator: "\n"))
  }

  static func extractText(fromImageData data: Data) async throws -> String {
    guard let image = UIImage(data: data), let cgImage = image.cgImage else {
      throw ResumePhotoImportError.unreadableImage
    }
    let orientation = CGImagePropertyOrientation(image.imageOrientation)
    let text = try await Task.detached(priority: .userInitiated) {
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      request.automaticallyDetectsLanguage = true
      try VNImageRequestHandler(
        cgImage: cgImage,
        orientation: orientation,
        options: [:]
      ).perform([request])
      return (request.results ?? [])
        .sorted { left, right in
          let verticalDifference = abs(left.boundingBox.midY - right.boundingBox.midY)
          if verticalDifference > 0.02 { return left.boundingBox.midY > right.boundingBox.midY }
          return left.boundingBox.minX < right.boundingBox.minX
        }
        .compactMap { $0.topCandidates(1).first?.string }
        .joined(separator: "\n")
    }.value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isBlank else { throw ResumePhotoImportError.noReadableText }
    return text
  }

  private static func extractDOCX(_ url: URL) throws -> String {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.unzipItem(at: url, to: folder)
    let xml = try String(contentsOf: folder.appendingPathComponent("word/document.xml"), encoding: .utf8)
    return xml.replacingOccurrences(of: "</w:p>", with: "\n")
      .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
      .xmlDecoded
  }

  private static func extractCSVs(_ url: URL) throws -> [(String, String)] {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.unzipItem(at: url, to: folder)
    let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?
      .compactMap { $0 as? URL }.filter { $0.pathExtension.lowercased() == "csv" } ?? []
    return try files.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
  }

  static func parseResumeText(_ text: String) -> ResumeDocument {
    let lines = text.components(separatedBy: .newlines)
      .map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression) }
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    var result = ResumeDocument.blank
    result.personal.fullName = lines.first ?? ""
    if lines.count > 1 { result.personal.headline = lines[1] }
    if let match = text.firstMatch(#"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#) { result.personal.email = match }
    if let match = text.firstMatch(#"\+?[0-9][0-9 ()-]{7,}[0-9]"#) { result.personal.phone = match }

    var sections: [ImportedSection: [String]] = [:]
    var currentSection: ImportedSection?
    for line in lines {
      if let heading = importedSection(for: line) {
        currentSection = heading
        continue
      }
      if isRepeatedPageFurniture(
        line,
        name: result.personal.fullName,
        headline: result.personal.headline
      ) {
        continue
      }
      if let currentSection {
        sections[currentSection, default: []].append(line)
      }
    }

    result.professionalProfile = joinedParagraphs(sections[.profile] ?? []).joined(separator: " ")
    result.experience = parseExperience(sections[.experience] ?? [])
    result.education = parseEducation(sections[.education] ?? [])
    result.competencies = parseCompetencies(sections[.competencies] ?? [])
    result.references = parseReferences(sections[.references] ?? [])

    let additional: [(ImportedSection, String)] = [
      (.certifications, "Certifications"),
      (.projects, "Projects"),
      (.languages, "Languages"),
    ]
    result.additionalSections = additional.compactMap { section, title in
      let items = joinedParagraphs(sections[section] ?? [])
      return items.isEmpty ? nil : ResumeAdditionalSection(title: title, items: items)
    }
    return result
  }

  private enum ImportedSection: Hashable {
    case profile
    case experience
    case education
    case competencies
    case references
    case certifications
    case projects
    case languages
  }

  /// PDFKit can append a footer and the next column's heading to the same line,
  /// so headings are recognised as suffixes as well as standalone lines.
  private static func importedSection(for line: String) -> ImportedSection? {
    let value = line.uppercased()
      .replacingOccurrences(of: #"[^A-Z ]"#, with: " ", options: .regularExpression)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespaces)

    let aliases: [(ImportedSection, [String])] = [
      (.profile, ["PROFESSIONAL PROFILE", "CAREER PROFILE", "PROFILE", "SUMMARY"]),
      (.experience, ["PROFESSIONAL EXPERIENCE", "WORK EXPERIENCE", "EMPLOYMENT HISTORY", "EXPERIENCE"]),
      (.competencies, ["CORE COMPETENCIES", "KEY COMPETENCIES", "CORE SKILLS", "KEY SKILLS", "SKILLS"]),
      (.education, ["EDUCATION", "ACADEMIC BACKGROUND", "QUALIFICATIONS"]),
      (.references, ["REFERENCES", "REFEREES"]),
      (.certifications, ["CERTIFICATIONS", "CERTIFICATES"]),
      (.projects, ["PROJECTS"]),
      (.languages, ["LANGUAGES"]),
    ]
    for (section, names) in aliases {
      if names.contains(where: {
        value == $0
          || value == $0 + " CONTINUED"
          || (value.contains(" RESUME ") && value.hasSuffix(" " + $0))
      }) {
        return section
      }
    }
    return nil
  }

  private static func isRepeatedPageFurniture(
    _ line: String,
    name: String,
    headline: String
  ) -> Bool {
    if line.caseInsensitiveCompare(name) == .orderedSame
      || line.caseInsensitiveCompare(headline) == .orderedSame
    {
      return true
    }
    let uppercase = line.uppercased()
    return uppercase.contains("| RESUME")
      || uppercase.range(of: #"^PAGE\s+\d+(\s+OF\s+\d+)?$"#, options: .regularExpression) != nil
      || uppercase.range(of: #"^\d+\s*/\s*\d+$"#, options: .regularExpression) != nil
      || uppercase == "CONTINUED"
      || line == "-"
  }

  private static func parseExperience(_ lines: [String]) -> [ExperienceEntry] {
    let metadataIndexes = lines.indices.filter { isRoleMetadata(lines[$0]) }
    if metadataIndexes.isEmpty, let role = lines.first.map(cleanImportedItem), !role.isBlank {
      return [ExperienceEntry(
        role: role,
        company: "",
        period: "",
        highlights: joinedParagraphs(Array(lines.dropFirst()))
      )]
    }
    return metadataIndexes.enumerated().compactMap { offset, metadataIndex in
      guard metadataIndex > lines.startIndex else { return nil }
      let role = cleanImportedItem(lines[metadataIndex - 1])
      let parts = lines[metadataIndex].split(separator: "|", maxSplits: 1).map {
        String($0).trimmingCharacters(in: .whitespaces)
      }
      let nextMetadataIndex = metadataIndexes.indices.contains(offset + 1)
        ? metadataIndexes[offset + 1]
        : lines.endIndex
      let highlightsEnd = nextMetadataIndex == lines.endIndex
        ? lines.endIndex
        : max(metadataIndex + 1, nextMetadataIndex - 1)
      let highlights = joinedParagraphs(Array(lines[(metadataIndex + 1)..<highlightsEnd]))
      return ExperienceEntry(
        role: role,
        company: parts.first ?? "",
        period: parts.count > 1 ? parts[1] : "",
        highlights: highlights
      )
    }
  }

  private static func isRoleMetadata(_ line: String) -> Bool {
    guard line.contains("|") else { return false }
    return line.range(
      of: #"(?i)\b(Jan(uary)?|Feb(ruary)?|Mar(ch)?|Apr(il)?|May|Jun(e)?|Jul(y)?|Aug(ust)?|Sep(tember)?|Oct(ober)?|Nov(ember)?|Dec(ember)?|19\d{2}|20\d{2}|Present|Current)\b"#,
      options: .regularExpression
    ) != nil
  }

  private static func parseEducation(_ lines: [String]) -> [EducationEntry] {
    let institutionIndexes = lines.indices.filter { index in
      lines[index].range(
        of: #"(?i)\b(university|college|school|institute|academy|polytechnic)\b"#,
        options: .regularExpression
      ) != nil
    }
    var entries: [EducationEntry] = []
    var cursor = lines.startIndex

    for institutionIndex in institutionIndexes {
      var qualificationLines = Array(lines[cursor..<institutionIndex])
      if !entries.isEmpty {
        let detailCount = qualificationLines.prefix { isSentenceLike($0) }.count
        if detailCount > 0 {
          let details = qualificationLines.prefix(detailCount).joined(separator: " ")
          entries[entries.count - 1].details = [entries.last?.details ?? "", details]
            .filter { !$0.isBlank }.joined(separator: " ")
          qualificationLines.removeFirst(detailCount)
        }
      }

      let parts = lines[institutionIndex].split(separator: "|", maxSplits: 1).map {
        String($0).trimmingCharacters(in: .whitespaces)
      }
      let qualification = qualificationLines.map(cleanImportedItem).joined(separator: " ")
      if !qualification.isBlank {
        entries.append(EducationEntry(
          qualification: qualification,
          institution: parts.first ?? "",
          period: parts.count > 1 ? parts[1] : "",
          details: ""
        ))
      }
      cursor = institutionIndex + 1
    }

    if !entries.isEmpty, cursor < lines.endIndex {
      let details = lines[cursor...].map(cleanImportedItem).joined(separator: " ")
      entries[entries.count - 1].details = details
    }
    return entries
  }

  private static func parseCompetencies(_ lines: [String]) -> [String] {
    var competencies: [String] = []
    for rawLine in lines {
      let line = cleanImportedItem(rawLine)
      guard !line.isBlank else { continue }
      if line.split(separator: " ").count <= 2,
        let previous = competencies.last,
        previous.split(separator: " ").count >= 3,
        !isSentenceLike(previous)
      {
        competencies[competencies.count - 1] += " " + line
      } else {
        competencies.append(line)
      }
    }
    var seen: Set<String> = []
    return competencies.filter { seen.insert($0.lowercased()).inserted }
  }

  private static func parseReferences(_ lines: [String]) -> [ReferenceEntry] {
    var references: [ReferenceEntry] = []
    var chunk: [String] = []
    for line in lines {
      chunk.append(line)
      if line.firstMatch(#"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#) != nil {
        let values = chunk.filter {
          let uppercase = $0.uppercased()
          return uppercase != "CONTACT NUMBER"
            && uppercase != "EMAIL ADDRESS"
            && $0.firstMatch(#"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#) == nil
            && $0.firstMatch(#"\+?[0-9][0-9 ()-]{7,}[0-9]"#) == nil
        }
        references.append(ReferenceEntry(
          name: values.first ?? "",
          company: values.dropFirst().first ?? "",
          phone: chunk.joined(separator: " ").firstMatch(#"\+?[0-9][0-9 ()-]{7,}[0-9]"#) ?? "",
          email: line.firstMatch(#"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#) ?? ""
        ))
        chunk.removeAll()
      }
    }
    return references.filter { !$0.name.isBlank }
  }

  /// PDFKit returns wrapped visual lines, not bullets. A sentence-ending line
  /// closes one item; wrapped lines are joined back into the same item.
  private static func joinedParagraphs(_ lines: [String]) -> [String] {
    var items: [String] = []
    var current = ""
    for rawLine in lines {
      let line = cleanImportedItem(rawLine)
      guard !line.isBlank else { continue }
      current = current.isBlank ? line : current + " " + line
      if isSentenceLike(line) {
        items.append(current)
        current = ""
      }
    }
    if !current.isBlank { items.append(current) }
    return items
  }

  private static func isSentenceLike(_ line: String) -> Bool {
    guard let last = line.last else { return false }
    return ".!?;".contains(last)
  }

  private static func cleanImportedItem(_ line: String) -> String {
    line.trimmingCharacters(in: CharacterSet(charactersIn: "•·-–— ").union(.whitespacesAndNewlines))
  }

  private static func parseLinkedIn(_ files: [(String, String)]) -> ResumeDocument {
    var result = ResumeDocument.blank
    for (name, content) in files {
      let rows = CSV.parse(content)
      guard let header = rows.first else { continue }
      func value(_ row: [String], _ keys: [String]) -> String {
        for key in keys {
          if let index = header.firstIndex(where: { $0.localizedCaseInsensitiveContains(key) }), row.indices.contains(index) { return row[index] }
        }
        return ""
      }
      let lower = name.lowercased()
      if lower.contains("profile"), let row = rows.dropFirst().first {
        result.personal.fullName = [value(row, ["First Name"]), value(row, ["Last Name"])].filter { !$0.isBlank }.joined(separator: " ")
        result.personal.headline = value(row, ["Headline"])
      } else if lower.contains("position") {
        result.experience += rows.dropFirst().map { row in
          ExperienceEntry(role: value(row, ["Title"]), company: value(row, ["Company Name", "Company"]), period: [value(row, ["Started On"]), value(row, ["Finished On"])].filter { !$0.isBlank }.joined(separator: " – "), highlights: [value(row, ["Description"])].filter { !$0.isBlank })
        }
      } else if lower.contains("education") {
        result.education += rows.dropFirst().map { row in
          EducationEntry(qualification: value(row, ["Degree Name", "Degree"]), institution: value(row, ["School Name", "School"]), period: [value(row, ["Start Date"]), value(row, ["End Date"])].filter { !$0.isBlank }.joined(separator: " – "), details: value(row, ["Notes", "Activities"]))
        }
      } else if lower.contains("skill") {
        result.competencies += rows.dropFirst().compactMap { value($0, ["Name"]).nilIfBlank }
      } else if lower.contains("certification") || lower.contains("project") {
        result.additionalSections.append(ResumeAdditionalSection(title: lower.contains("project") ? "Projects" : "Certifications", items: rows.dropFirst().map { $0.filter { !$0.isBlank }.joined(separator: " — ") }))
      }
    }
    return result
  }
}

enum ResumePhotoImportError: LocalizedError {
  case unreadableImage
  case noReadableText

  var errorDescription: String? {
    switch self {
    case .unreadableImage:
      "One of the selected photos could not be read. Choose a JPG, PNG, or HEIC image."
    case .noReadableText:
      "No readable résumé text was found in one of the photos. Retake it in good light and keep the page straight."
    }
  }
}

private extension CGImagePropertyOrientation {
  init(_ orientation: UIImage.Orientation) {
    switch orientation {
    case .up: self = .up
    case .upMirrored: self = .upMirrored
    case .down: self = .down
    case .downMirrored: self = .downMirrored
    case .left: self = .left
    case .leftMirrored: self = .leftMirrored
    case .right: self = .right
    case .rightMirrored: self = .rightMirrored
    @unknown default: self = .up
    }
  }
}

private enum CSV {
  static func parse(_ text: String) -> [[String]] {
    var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
    let characters = Array(text)
    var index = 0
    while index < characters.count {
      let character = characters[index]
      if character == "\"" {
        if quoted && index + 1 < characters.count && characters[index + 1] == "\"" { field.append("\""); index += 1 }
        else { quoted.toggle() }
      } else if character == "," && !quoted { row.append(field); field = "" }
      else if character == "\n" && !quoted { row.append(field.trimmingCharacters(in: .newlines)); rows.append(row); row = []; field = "" }
      else if character != "\r" { field.append(character) }
      index += 1
    }
    if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
    return rows
  }
}

private extension String {
  var xmlEscaped: String { replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;") }
  var xmlDecoded: String { replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"") }
  func firstMatch(_ pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive), let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)), let range = Range(match.range, in: self) else { return nil }
    return String(self[range])
  }
}
