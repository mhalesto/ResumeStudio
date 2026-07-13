import Foundation
import UIKit

enum ResumePDFRenderer {
  @MainActor
  static func render(document: ResumeDocument) throws -> Data {
    let pageBounds = CGRect(x: 0, y: 0, width: 595, height: 842)
    let format = UIGraphicsPDFRendererFormat()
    format.documentInfo = [
      kCGPDFContextTitle as String: document.suggestedFilename,
      kCGPDFContextAuthor as String: document.personal.fullName,
      kCGPDFContextCreator as String: "ResumeStudio",
    ]

    let renderer = UIGraphicsPDFRenderer(bounds: pageBounds, format: format)
    return renderer.pdfData { rendererContext in
      let layout = ResumePDFLayout(
        rendererContext: rendererContext,
        pageBounds: pageBounds,
        document: document
      )
      layout.render()
    }
  }
}

@MainActor
private final class ResumePDFLayout {
  private let rendererContext: UIGraphicsPDFRendererContext
  private let pageBounds: CGRect
  private let document: ResumeDocument

  private let margin: CGFloat = 34
  private let footerTop: CGFloat = 810
  private var cursorY: CGFloat = 0
  private var pageNumber = 0

  private let navy = UIColor(red: 0.17, green: 0.20, blue: 0.29, alpha: 1)
  private let charcoal = UIColor(red: 0.09, green: 0.10, blue: 0.12, alpha: 1)
  private let gray = UIColor(red: 0.36, green: 0.38, blue: 0.41, alpha: 1)
  private let lightGray = UIColor(red: 0.94, green: 0.95, blue: 0.96, alpha: 1)
  private let ruleGray = UIColor(red: 0.76, green: 0.78, blue: 0.81, alpha: 1)

  private var accent: UIColor { document.accent.uiColor }
  private var template: ResumeTemplate { document.template }
  private var contentWidth: CGFloat { pageBounds.width - (margin * 2) }

  init(
    rendererContext: UIGraphicsPDFRendererContext,
    pageBounds: CGRect,
    document: ResumeDocument
  ) {
    self.rendererContext = rendererContext
    self.pageBounds = pageBounds
    self.document = document
  }

  func render() {
    beginPage(isFirst: true)
    drawProfessionalProfile()
    drawCompetencies()
    drawExperience()
    drawEducation()
    drawReferences()
  }

  private func beginPage(isFirst: Bool) {
    rendererContext.beginPage()
    pageNumber += 1

    UIColor.white.setFill()
    rendererContext.cgContext.fill(pageBounds)

    if isFirst {
      drawPrimaryHeader()
      switch template {
      case .modern: cursorY = 145
      case .classic: cursorY = 137
      case .minimal: cursorY = 132
      }
    } else {
      drawContinuationHeader()
      cursorY = template == .modern ? 96 : 88
    }

    drawFooter()
  }

  private func drawPrimaryHeader() {
    switch template {
    case .modern:
      drawModernPrimaryHeader()
    case .classic:
      drawClassicPrimaryHeader()
    case .minimal:
      drawMinimalPrimaryHeader()
    }
  }

  private func drawModernPrimaryHeader() {
    navy.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: 124))

    let rawName = document.personal.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
    let displayName = rawName.isEmpty ? "Your Name" : rawName
    let parts = displayName.split(separator: " ", maxSplits: 1).map(String.init)
    let firstName = parts.first ?? displayName
    let lastName = parts.count > 1 ? " \(parts[1])" : ""

    let firstAttributes = textAttributes(font: boldFont(30), color: accent, lineHeight: 34)
    NSAttributedString(string: firstName, attributes: firstAttributes).draw(
      at: CGPoint(x: margin, y: 27))
    let firstWidth = singleLineWidth(firstName, attributes: firstAttributes)
    NSAttributedString(
      string: lastName,
      attributes: textAttributes(font: boldFont(30), color: .white, lineHeight: 34)
    ).draw(at: CGPoint(x: margin + firstWidth, y: 27))

    let headline = document.personal.headline.trimmingCharacters(in: .whitespacesAndNewlines)
    if !headline.isEmpty {
      drawText(
        headline.uppercased(),
        rect: CGRect(x: margin, y: 67, width: contentWidth, height: 18),
        font: mediumFont(9.5),
        color: .white,
        lineHeight: 12
      )
    }

    var contactX = margin
    let contactY: CGFloat = 94
    for value in [document.personal.phone, document.personal.email] {
      let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !clean.isEmpty else { continue }

      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: contactX, y: contactY + 3, width: 4, height: 4))
      contactX += 12

      let attributes = textAttributes(font: regularFont(9), color: .white, lineHeight: 11)
      NSAttributedString(string: clean, attributes: attributes).draw(
        at: CGPoint(x: contactX, y: contactY))
      contactX += singleLineWidth(clean, attributes: attributes) + 30
    }
  }

  private func drawClassicPrimaryHeader() {
    let name = displayName
    drawText(
      name,
      rect: CGRect(x: margin, y: 24, width: contentWidth, height: 36),
      font: boldFont(29),
      color: navy,
      lineHeight: 33,
      alignment: .center
    )

    let headline = document.personal.headline.trimmingCharacters(in: .whitespacesAndNewlines)
    if !headline.isEmpty {
      drawText(
        headline.uppercased(),
        rect: CGRect(x: margin, y: 61, width: contentWidth, height: 16),
        font: mediumFont(9.2),
        color: accent,
        lineHeight: 12,
        alignment: .center
      )
    }

    accent.setFill()
    rendererContext.cgContext.fill(
      CGRect(x: (pageBounds.width - 76) / 2, y: 84, width: 76, height: 2)
    )

    let contacts = contactLine
    if !contacts.isEmpty {
      drawText(
        contacts,
        rect: CGRect(x: margin, y: 97, width: contentWidth, height: 14),
        font: regularFont(8.6),
        color: gray,
        lineHeight: 11,
        alignment: .center
      )
    }
  }

  private func drawMinimalPrimaryHeader() {
    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: 9, height: 117))

    drawText(
      displayName,
      rect: CGRect(x: margin, y: 23, width: contentWidth, height: 36),
      font: boldFont(29),
      color: navy,
      lineHeight: 33
    )

    let headline = document.personal.headline.trimmingCharacters(in: .whitespacesAndNewlines)
    if !headline.isEmpty {
      drawText(
        headline.uppercased(),
        rect: CGRect(x: margin, y: 61, width: contentWidth, height: 15),
        font: mediumFont(9),
        color: accent,
        lineHeight: 11
      )
    }

    let contacts = contactLine
    if !contacts.isEmpty {
      drawText(
        contacts,
        rect: CGRect(x: margin, y: 84, width: contentWidth, height: 14),
        font: regularFont(8.5),
        color: gray,
        lineHeight: 11
      )
    }

    ruleGray.setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 112, width: contentWidth, height: 0.7))
  }

  private func drawContinuationHeader() {
    switch template {
    case .modern:
      drawModernContinuationHeader()
    case .classic:
      drawClassicContinuationHeader()
    case .minimal:
      drawMinimalContinuationHeader()
    }
  }

  private func drawModernContinuationHeader() {
    navy.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: 72))

    let rawName = document.personal.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
    drawText(
      rawName.isEmpty ? "Your Resume" : rawName,
      rect: CGRect(x: margin, y: 20, width: 350, height: 25),
      font: boldFont(20),
      color: .white,
      lineHeight: 23
    )

    let headline = document.personal.headline.trimmingCharacters(in: .whitespacesAndNewlines)
    if !headline.isEmpty {
      drawText(
        headline.uppercased(),
        rect: CGRect(x: margin, y: 46, width: 420, height: 15),
        font: mediumFont(8),
        color: .white,
        lineHeight: 10
      )
    }

    drawText(
      "PAGE \(pageNumber)",
      rect: CGRect(x: 495, y: 30, width: 66, height: 12),
      font: mediumFont(8),
      color: .white,
      lineHeight: 10,
      alignment: .right
    )
  }

  private func drawClassicContinuationHeader() {
    drawText(
      displayName,
      rect: CGRect(x: margin, y: 19, width: contentWidth, height: 24),
      font: boldFont(17),
      color: navy,
      lineHeight: 21,
      alignment: .center
    )
    accent.setFill()
    rendererContext.cgContext.fill(
      CGRect(x: (pageBounds.width - 58) / 2, y: 51, width: 58, height: 1.5)
    )
    drawText(
      "PAGE \(pageNumber)",
      rect: CGRect(x: 500, y: 23, width: 61, height: 12),
      font: mediumFont(7.5),
      color: gray,
      lineHeight: 9,
      alignment: .right
    )
  }

  private func drawMinimalContinuationHeader() {
    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: 7, height: 70))
    drawText(
      displayName,
      rect: CGRect(x: margin, y: 18, width: 370, height: 24),
      font: boldFont(18),
      color: navy,
      lineHeight: 22
    )
    drawText(
      "PAGE \(pageNumber)",
      rect: CGRect(x: 500, y: 24, width: 61, height: 12),
      font: mediumFont(7.5),
      color: gray,
      lineHeight: 9,
      alignment: .right
    )
    ruleGray.setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 59, width: contentWidth, height: 0.7))
  }

  private var displayName: String {
    let rawName = document.personal.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
    return rawName.isEmpty ? "Your Name" : rawName
  }

  private var contactLine: String {
    [document.personal.phone, document.personal.email]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: "  |  ")
  }

  private func drawFooter() {
    let name = document.personal.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
    drawText(
      name.isEmpty ? "RESUME STUDIO" : "\(name.uppercased())  |  RESUME",
      rect: CGRect(x: margin, y: 819, width: 390, height: 10),
      font: mediumFont(7),
      color: gray,
      lineHeight: 9
    )
    drawText(
      "\(pageNumber)",
      rect: CGRect(x: 535, y: 819, width: 26, height: 10),
      font: mediumFont(7),
      color: gray,
      lineHeight: 9,
      alignment: .right
    )
  }

  private func drawProfessionalProfile() {
    let profile = document.professionalProfile.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !profile.isEmpty else { return }

    drawSectionTitle("Professional Profile")
    let height = measuredHeight(
      profile,
      width: contentWidth,
      font: regularFont(9.3),
      lineHeight: 12.5
    )
    ensureSpace(height + 13)
    drawText(
      profile,
      rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: height),
      font: regularFont(9.3),
      color: charcoal,
      lineHeight: 12.5
    )
    cursorY += height + 13
  }

  private func drawCompetencies() {
    let items = document.competencies
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard !items.isEmpty else { return }

    drawSectionTitle("Core Competencies")
    let gap: CGFloat = 18
    let columnWidth = (contentWidth - gap) / 2

    for index in stride(from: 0, to: items.count, by: 2) {
      let left = items[index]
      let right = index + 1 < items.count ? items[index + 1] : nil
      let leftHeight = measuredHeight(
        left, width: columnWidth - 14, font: regularFont(8.8), lineHeight: 11)
      let rightHeight =
        right.map {
          measuredHeight($0, width: columnWidth - 14, font: regularFont(8.8), lineHeight: 11)
        } ?? 0
      let rowHeight = max(leftHeight, rightHeight) + 5
      ensureSpace(rowHeight, continuationTitle: "Core Competencies - Continued")

      drawCompactBullet(left, x: margin, y: cursorY, width: columnWidth, height: leftHeight)
      if let right {
        drawCompactBullet(
          right,
          x: margin + columnWidth + gap,
          y: cursorY,
          width: columnWidth,
          height: rightHeight
        )
      }
      cursorY += rowHeight
    }
    cursorY += 8
  }

  private func drawExperience() {
    let entries = document.experience.filter {
      !$0.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !$0.company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    guard !entries.isEmpty else { return }

    drawSectionTitle("Professional Experience")
    for entry in entries {
      drawExperienceEntry(entry)
    }
  }

  private func drawExperienceEntry(_ entry: ExperienceEntry) {
    let highlights = entry.highlights
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    let role = entry.role.trimmingCharacters(in: .whitespacesAndNewlines)
    let metadata = [entry.company, entry.period]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: "  |  ")

    let roleHeight = measuredHeight(role, width: contentWidth, font: boldFont(11.2), lineHeight: 14)
    let metaHeight = measuredHeight(
      metadata, width: contentWidth, font: mediumFont(8.6), lineHeight: 11)
    let firstBulletHeight =
      highlights.first.map {
        measuredHeight($0, width: contentWidth - 18, font: regularFont(8.8), lineHeight: 11.2)
      } ?? 0

    let brokeBeforeEntry = ensureSpace(
      roleHeight + metaHeight + firstBulletHeight + 24,
      continuationTitle: "Professional Experience - Continued"
    )
    if brokeBeforeEntry {
      cursorY += 1
    }

    drawText(
      role,
      rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: roleHeight),
      font: boldFont(11.2),
      color: navy,
      lineHeight: 14
    )
    cursorY += roleHeight + 2

    if !metadata.isEmpty {
      drawText(
        metadata,
        rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: metaHeight),
        font: mediumFont(8.6),
        color: gray,
        lineHeight: 11
      )
      cursorY += metaHeight + 6
    }

    for highlight in highlights {
      let height = measuredHeight(
        highlight,
        width: contentWidth - 18,
        font: regularFont(8.8),
        lineHeight: 11.2
      )
      let brokeInsideEntry = ensureSpace(
        height + 5,
        continuationTitle: "Professional Experience - Continued"
      )
      if brokeInsideEntry {
        let continued = role.isEmpty ? "Experience Continued" : "\(role) - Continued"
        let continuedHeight = measuredHeight(
          continued,
          width: contentWidth,
          font: boldFont(10.5),
          lineHeight: 13
        )
        drawText(
          continued,
          rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: continuedHeight),
          font: boldFont(10.5),
          color: navy,
          lineHeight: 13
        )
        cursorY += continuedHeight + 7
      }
      drawBullet(highlight, height: height)
    }
    cursorY += 11
  }

  private func drawEducation() {
    let entries = document.education.filter {
      !$0.qualification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !$0.institution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    guard !entries.isEmpty else { return }

    ensureSpace(40, continuationTitle: nil)
    drawSectionTitle("Education")
    for entry in entries {
      let qualification = entry.qualification.trimmingCharacters(in: .whitespacesAndNewlines)
      let institutionLine = [entry.institution, entry.period]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "  |  ")
      let details = entry.details.trimmingCharacters(in: .whitespacesAndNewlines)

      let qualificationHeight = measuredHeight(
        qualification,
        width: contentWidth,
        font: boldFont(10),
        lineHeight: 12.5
      )
      let institutionHeight = measuredHeight(
        institutionLine,
        width: contentWidth,
        font: mediumFont(8.5),
        lineHeight: 10.5
      )
      let detailsHeight =
        details.isEmpty
        ? 0
        : measuredHeight(
          details,
          width: contentWidth,
          font: regularFont(8.5),
          lineHeight: 11
        )
      ensureSpace(
        qualificationHeight + institutionHeight + detailsHeight + 16,
        continuationTitle: "Education - Continued"
      )

      drawText(
        qualification,
        rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: qualificationHeight),
        font: boldFont(10),
        color: navy,
        lineHeight: 12.5
      )
      cursorY += qualificationHeight + 2
      drawText(
        institutionLine,
        rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: institutionHeight),
        font: mediumFont(8.5),
        color: gray,
        lineHeight: 10.5
      )
      cursorY += institutionHeight + 3

      if !details.isEmpty {
        drawText(
          details,
          rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: detailsHeight),
          font: regularFont(8.5),
          color: charcoal,
          lineHeight: 11
        )
        cursorY += detailsHeight + 3
      }
      cursorY += 8
    }
  }

  private func drawReferences() {
    let references = document.references.filter {
      !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    guard !references.isEmpty else { return }

    ensureSpace(42, continuationTitle: nil)
    drawSectionTitle("References")

    let gap: CGFloat = 14
    let cardWidth = (contentWidth - gap) / 2
    let cardHeight: CGFloat = 112

    for index in stride(from: 0, to: references.count, by: 2) {
      ensureSpace(cardHeight + 10, continuationTitle: "References - Continued")
      drawReferenceCard(
        references[index], x: margin, y: cursorY, width: cardWidth, height: cardHeight)
      if index + 1 < references.count {
        drawReferenceCard(
          references[index + 1],
          x: margin + cardWidth + gap,
          y: cursorY,
          width: cardWidth,
          height: cardHeight
        )
      }
      cursorY += cardHeight + 10
    }
  }

  private func drawReferenceCard(
    _ reference: ReferenceEntry,
    x: CGFloat,
    y: CGFloat,
    width: CGFloat,
    height: CGFloat
  ) {
    let cardRect = CGRect(x: x, y: y, width: width, height: height)
    switch template {
    case .modern:
      lightGray.setFill()
      rendererContext.cgContext.fill(cardRect)
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: x, y: y, width: 4, height: height))
    case .classic:
      UIColor.white.setFill()
      rendererContext.cgContext.fill(cardRect)
      rendererContext.cgContext.setStrokeColor(ruleGray.cgColor)
      rendererContext.cgContext.setLineWidth(0.7)
      rendererContext.cgContext.stroke(cardRect.insetBy(dx: 0.5, dy: 0.5))
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: x, y: y, width: width, height: 2.5))
    case .minimal:
      UIColor.white.setFill()
      rendererContext.cgContext.fill(cardRect)
      accent.withAlphaComponent(0.1).setFill()
      rendererContext.cgContext.fill(CGRect(x: x, y: y, width: width, height: 28))
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: x, y: y, width: 3, height: height))
    }

    let isClassic = template == .classic
    let insetX = isClassic ? x + 10 : x + 16
    let textWidth = isClassic ? width - 20 : width - 27
    let alignment: NSTextAlignment = isClassic ? .center : .left
    drawText(
      reference.name,
      rect: CGRect(x: insetX, y: y + 13, width: textWidth, height: 16),
      font: boldFont(10.2),
      color: navy,
      lineHeight: 13,
      alignment: alignment
    )
    drawText(
      reference.company,
      rect: CGRect(x: insetX, y: y + 31, width: textWidth, height: 14),
      font: mediumFont(8.3),
      color: gray,
      lineHeight: 11,
      alignment: alignment
    )
    drawText(
      "CONTACT NUMBER",
      rect: CGRect(x: insetX, y: y + 53, width: textWidth, height: 10),
      font: boldFont(6.8),
      color: accent,
      lineHeight: 9,
      alignment: alignment
    )
    drawText(
      reference.phone,
      rect: CGRect(x: insetX, y: y + 65, width: textWidth, height: 13),
      font: regularFont(8.3),
      color: charcoal,
      lineHeight: 10,
      alignment: alignment
    )
    drawText(
      "EMAIL ADDRESS",
      rect: CGRect(x: insetX, y: y + 82, width: textWidth, height: 10),
      font: boldFont(6.8),
      color: accent,
      lineHeight: 9,
      alignment: alignment
    )
    drawText(
      reference.email,
      rect: CGRect(x: insetX, y: y + 94, width: textWidth, height: 13),
      font: regularFont(7.7),
      color: charcoal,
      lineHeight: 9.5,
      alignment: alignment
    )
  }

  private func drawSectionTitle(_ title: String) {
    if cursorY + 30 > footerTop {
      beginPage(isFirst: false)
    }

    switch template {
    case .modern:
      drawText(
        title.uppercased(),
        rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: 16),
        font: boldFont(11.2),
        color: accent,
        lineHeight: 14
      )
      navy.setStroke()
      let path = UIBezierPath()
      path.lineWidth = 0.7
      path.move(to: CGPoint(x: margin, y: cursorY + 21))
      path.addLine(to: CGPoint(x: margin + contentWidth, y: cursorY + 21))
      path.stroke()
      cursorY += 29
    case .classic:
      drawText(
        title.uppercased(),
        rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: 17),
        font: boldFont(11),
        color: navy,
        lineHeight: 14,
        alignment: .center
      )
      accent.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: (pageBounds.width - 48) / 2, y: cursorY + 22, width: 48, height: 1.5)
      )
      cursorY += 31
    case .minimal:
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: margin, y: cursorY + 1, width: 4, height: 15))
      drawText(
        title.uppercased(),
        rect: CGRect(x: margin + 12, y: cursorY, width: contentWidth - 12, height: 17),
        font: boldFont(10.8),
        color: navy,
        lineHeight: 14
      )
      ruleGray.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: margin + 12, y: cursorY + 21, width: contentWidth - 12, height: 0.6)
      )
      cursorY += 28
    }
  }

  @discardableResult
  private func ensureSpace(_ requiredHeight: CGFloat, continuationTitle: String? = nil) -> Bool {
    guard cursorY + requiredHeight > footerTop else { return false }
    beginPage(isFirst: false)
    if let continuationTitle {
      drawSectionTitle(continuationTitle)
    }
    return true
  }

  private func drawBullet(_ text: String, height: CGFloat) {
    accent.setFill()
    switch template {
    case .modern:
      rendererContext.cgContext.fillEllipse(
        in: CGRect(x: margin + 3, y: cursorY + 4, width: 3.2, height: 3.2))
    case .classic:
      rendererContext.cgContext.fill(CGRect(x: margin + 2, y: cursorY + 5, width: 6, height: 1.4))
    case .minimal:
      rendererContext.cgContext.fill(CGRect(x: margin + 3, y: cursorY + 4, width: 3.5, height: 3.5))
    }
    drawText(
      text,
      rect: CGRect(x: margin + 16, y: cursorY, width: contentWidth - 16, height: height),
      font: regularFont(8.8),
      color: charcoal,
      lineHeight: 11.2
    )
    cursorY += height + 4
  }

  private func drawCompactBullet(
    _ text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat
  ) {
    accent.setFill()
    switch template {
    case .modern:
      rendererContext.cgContext.fillEllipse(in: CGRect(x: x + 2, y: y + 3.5, width: 3, height: 3))
    case .classic:
      rendererContext.cgContext.fill(CGRect(x: x + 1, y: y + 4.5, width: 6, height: 1.3))
    case .minimal:
      rendererContext.cgContext.fill(CGRect(x: x + 2, y: y + 3.5, width: 3.2, height: 3.2))
    }
    drawText(
      text,
      rect: CGRect(x: x + 13, y: y, width: width - 13, height: height),
      font: regularFont(8.8),
      color: charcoal,
      lineHeight: 11
    )
  }

  private func drawText(
    _ text: String,
    rect: CGRect,
    font: UIFont,
    color: UIColor,
    lineHeight: CGFloat,
    alignment: NSTextAlignment = .left
  ) {
    let attributes = textAttributes(
      font: font,
      color: color,
      lineHeight: lineHeight,
      alignment: alignment
    )
    NSAttributedString(string: text, attributes: attributes).draw(
      with: rect,
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      context: nil
    )
  }

  private func measuredHeight(
    _ text: String,
    width: CGFloat,
    font: UIFont,
    lineHeight: CGFloat
  ) -> CGFloat {
    guard !text.isEmpty else { return 0 }
    let attributes = textAttributes(font: font, color: charcoal, lineHeight: lineHeight)
    let bounds = NSAttributedString(string: text, attributes: attributes).boundingRect(
      with: CGSize(width: width, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      context: nil
    )
    return ceil(bounds.height) + 1
  }

  private func singleLineWidth(_ text: String, attributes: [NSAttributedString.Key: Any]) -> CGFloat
  {
    ceil(NSAttributedString(string: text, attributes: attributes).size().width)
  }

  private func textAttributes(
    font: UIFont,
    color: UIColor,
    lineHeight: CGFloat,
    alignment: NSTextAlignment = .left
  ) -> [NSAttributedString.Key: Any] {
    let style = NSMutableParagraphStyle()
    style.minimumLineHeight = lineHeight
    style.maximumLineHeight = lineHeight
    style.lineBreakMode = .byWordWrapping
    style.alignment = alignment
    return [
      .font: font,
      .foregroundColor: color,
      .paragraphStyle: style,
    ]
  }

  private func regularFont(_ size: CGFloat) -> UIFont {
    switch template {
    case .modern:
      UIFont(name: "HelveticaNeue", size: size) ?? .systemFont(ofSize: size)
    case .classic:
      UIFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size)
    case .minimal:
      UIFont(name: "AvenirNext-Regular", size: size) ?? .systemFont(ofSize: size)
    }
  }

  private func mediumFont(_ size: CGFloat) -> UIFont {
    switch template {
    case .modern:
      UIFont(name: "HelveticaNeue-Medium", size: size) ?? .systemFont(ofSize: size, weight: .medium)
    case .classic:
      UIFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size, weight: .medium)
    case .minimal:
      UIFont(name: "AvenirNext-Medium", size: size) ?? .systemFont(ofSize: size, weight: .medium)
    }
  }

  private func boldFont(_ size: CGFloat) -> UIFont {
    switch template {
    case .modern:
      UIFont(name: "HelveticaNeue-Bold", size: size) ?? .systemFont(ofSize: size, weight: .bold)
    case .classic:
      UIFont(name: "Georgia-Bold", size: size) ?? .systemFont(ofSize: size, weight: .bold)
    case .minimal:
      UIFont(name: "AvenirNext-DemiBold", size: size)
        ?? .systemFont(ofSize: size, weight: .semibold)
    }
  }
}
