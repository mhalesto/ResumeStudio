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
      case .contemporary: cursorY = 148
      case .corporate: cursorY = 153
      case .elegant: cursorY = 143
      case .nordic: cursorY = 138
      case .creative: cursorY = 152
      case .technical: cursorY = 146
      case .compact: cursorY = 122
      case .academic: cursorY = 143
      case .timeline: cursorY = 148
      case .monochrome: cursorY = 138
      }
    } else {
      drawContinuationHeader()
      switch template {
      case .modern, .corporate, .creative: cursorY = 96
      case .contemporary, .technical, .timeline: cursorY = 92
      case .classic, .minimal, .elegant, .nordic, .academic, .monochrome: cursorY = 88
      case .compact: cursorY = 82
      }
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
    case .contemporary:
      drawContemporaryPrimaryHeader()
    case .corporate:
      drawCorporatePrimaryHeader()
    case .elegant:
      drawElegantPrimaryHeader()
    case .nordic:
      drawNordicPrimaryHeader()
    case .creative:
      drawCreativePrimaryHeader()
    case .technical:
      drawTechnicalPrimaryHeader()
    case .compact:
      drawCompactPrimaryHeader()
    case .academic:
      drawAcademicPrimaryHeader()
    case .timeline:
      drawTimelinePrimaryHeader()
    case .monochrome:
      drawMonochromePrimaryHeader()
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

  private func drawContemporaryPrimaryHeader() {
    navy.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: 226, height: 128))
    accent.withAlphaComponent(0.12).setFill()
    rendererContext.cgContext.fill(CGRect(x: 226, y: 0, width: pageBounds.width - 226, height: 128))
    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: 226, y: 0, width: 8, height: 128))

    drawText(
      displayName,
      rect: CGRect(x: margin, y: 27, width: 170, height: 60),
      font: boldFont(27),
      color: .white,
      lineHeight: 30
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: 259, y: 31, width: 302, height: 34),
      font: boldFont(10),
      color: navy,
      lineHeight: 13
    )
    drawText(
      contactLine,
      rect: CGRect(x: 259, y: 78, width: 302, height: 30),
      font: regularFont(8.5),
      color: gray,
      lineHeight: 12
    )
  }

  private func drawCorporatePrimaryHeader() {
    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: 12))
    navy.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 12, width: pageBounds.width, height: 91))
    lightGray.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 103, width: pageBounds.width, height: 30))

    drawText(
      displayName,
      rect: CGRect(x: margin, y: 32, width: contentWidth, height: 34),
      font: boldFont(29),
      color: .white,
      lineHeight: 33
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: 70, width: contentWidth, height: 18),
      font: mediumFont(9.2),
      color: accent,
      lineHeight: 12
    )
    drawText(
      contactLine,
      rect: CGRect(x: margin, y: 112, width: contentWidth, height: 13),
      font: mediumFont(8.4),
      color: navy,
      lineHeight: 10
    )
  }

  private func drawElegantPrimaryHeader() {
    ruleGray.setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 19, width: contentWidth, height: 0.7))
    rendererContext.cgContext.fill(CGRect(x: margin, y: 116, width: contentWidth, height: 0.7))
    accent.setFill()
    rendererContext.cgContext.fillEllipse(
      in: CGRect(x: pageBounds.midX - 3, y: 17, width: 6, height: 6))

    drawText(
      displayName,
      rect: CGRect(x: margin, y: 34, width: contentWidth, height: 34),
      font: boldFont(28),
      color: charcoal,
      lineHeight: 32,
      alignment: .center
    )
    drawText(
      document.personal.headline,
      rect: CGRect(x: margin, y: 70, width: contentWidth, height: 18),
      font: mediumFont(9.5),
      color: accent,
      lineHeight: 12,
      alignment: .center
    )
    drawText(
      contactLine,
      rect: CGRect(x: margin, y: 96, width: contentWidth, height: 13),
      font: regularFont(8.4),
      color: gray,
      lineHeight: 10,
      alignment: .center
    )
  }

  private func drawNordicPrimaryHeader() {
    accent.withAlphaComponent(0.13).setFill()
    rendererContext.cgContext.fillEllipse(in: CGRect(x: margin, y: 26, width: 66, height: 66))
    accent.setFill()
    rendererContext.cgContext.fillEllipse(in: CGRect(x: margin + 27, y: 53, width: 12, height: 12))

    drawText(
      displayName,
      rect: CGRect(x: 122, y: 28, width: 439, height: 34),
      font: boldFont(28),
      color: navy,
      lineHeight: 32
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: 122, y: 65, width: 439, height: 16),
      font: mediumFont(8.8),
      color: accent,
      lineHeight: 11
    )
    drawText(
      contactLine,
      rect: CGRect(x: 122, y: 88, width: 439, height: 13),
      font: regularFont(8.2),
      color: gray,
      lineHeight: 10
    )
    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: 122, y: 113, width: 62, height: 2))
  }

  private func drawCreativePrimaryHeader() {
    navy.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: 132))
    accent.setFill()
    rendererContext.cgContext.fillEllipse(in: CGRect(x: 463, y: -58, width: 170, height: 170))
    accent.withAlphaComponent(0.32).setFill()
    rendererContext.cgContext.fill(CGRect(x: 413, y: 87, width: 182, height: 45))

    drawText(
      displayName,
      rect: CGRect(x: margin, y: 27, width: 390, height: 38),
      font: boldFont(31),
      color: .white,
      lineHeight: 35
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: 70, width: 370, height: 17),
      font: mediumFont(9.2),
      color: accent,
      lineHeight: 12
    )
    drawText(
      contactLine,
      rect: CGRect(x: margin, y: 101, width: 360, height: 13),
      font: regularFont(8.4),
      color: .white,
      lineHeight: 10
    )
  }

  private func drawTechnicalPrimaryHeader() {
    lightGray.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: 126))
    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: 6))
    for x in stride(from: margin, through: pageBounds.width - margin, by: 44) {
      ruleGray.withAlphaComponent(0.35).setFill()
      rendererContext.cgContext.fill(CGRect(x: x, y: 6, width: 0.4, height: 120))
    }

    drawText(
      "</>  \(displayName)",
      rect: CGRect(x: margin, y: 28, width: contentWidth, height: 35),
      font: boldFont(26),
      color: navy,
      lineHeight: 31
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: 68, width: contentWidth, height: 17),
      font: mediumFont(8.7),
      color: accent,
      lineHeight: 11
    )
    drawText(
      contactLine,
      rect: CGRect(x: margin, y: 99, width: contentWidth, height: 13),
      font: regularFont(8),
      color: charcoal,
      lineHeight: 10
    )
  }

  private func drawCompactPrimaryHeader() {
    drawText(
      displayName,
      rect: CGRect(x: margin, y: 21, width: 330, height: 31),
      font: boldFont(26),
      color: navy,
      lineHeight: 30
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: 55, width: 330, height: 28),
      font: mediumFont(8.4),
      color: accent,
      lineHeight: 11
    )
    drawText(
      contactLine.replacingOccurrences(of: "  |  ", with: "\n"),
      rect: CGRect(x: 400, y: 28, width: 161, height: 40),
      font: regularFont(8.2),
      color: gray,
      lineHeight: 12,
      alignment: .right
    )
    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 96, width: contentWidth, height: 4))
  }

  private func drawAcademicPrimaryHeader() {
    drawText(
      "CURRICULUM VITAE",
      rect: CGRect(x: margin, y: 20, width: contentWidth, height: 14),
      font: boldFont(8),
      color: accent,
      lineHeight: 10,
      alignment: .center
    )
    drawText(
      displayName,
      rect: CGRect(x: margin, y: 40, width: contentWidth, height: 34),
      font: boldFont(28),
      color: charcoal,
      lineHeight: 32,
      alignment: .center
    )
    drawText(
      document.personal.headline,
      rect: CGRect(x: margin, y: 75, width: contentWidth, height: 16),
      font: mediumFont(9.2),
      color: gray,
      lineHeight: 12,
      alignment: .center
    )
    rendererContext.cgContext.setStrokeColor(charcoal.cgColor)
    rendererContext.cgContext.setLineWidth(0.8)
    rendererContext.cgContext.stroke(CGRect(x: margin, y: 101, width: contentWidth, height: 1))
    drawText(
      contactLine,
      rect: CGRect(x: margin, y: 111, width: contentWidth, height: 12),
      font: regularFont(8.2),
      color: gray,
      lineHeight: 10,
      alignment: .center
    )
  }

  private func drawTimelinePrimaryHeader() {
    accent.withAlphaComponent(0.11).setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: 128))
    accent.withAlphaComponent(0.4).setFill()
    rendererContext.cgContext.fill(CGRect(x: 49, y: 0, width: 2, height: 128))
    accent.setFill()
    for y in [28, 63, 98] as [CGFloat] {
      rendererContext.cgContext.fillEllipse(in: CGRect(x: 43, y: y, width: 14, height: 14))
    }

    drawText(
      displayName,
      rect: CGRect(x: 78, y: 27, width: 483, height: 34),
      font: boldFont(28),
      color: navy,
      lineHeight: 32
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: 78, y: 68, width: 483, height: 16),
      font: mediumFont(8.8),
      color: accent,
      lineHeight: 11
    )
    drawText(
      contactLine,
      rect: CGRect(x: 78, y: 99, width: 483, height: 13),
      font: regularFont(8.2),
      color: gray,
      lineHeight: 10
    )
  }

  private func drawMonochromePrimaryHeader() {
    rendererContext.cgContext.setStrokeColor(charcoal.cgColor)
    rendererContext.cgContext.setLineWidth(2)
    rendererContext.cgContext.stroke(CGRect(x: margin, y: 21, width: contentWidth, height: 80))
    charcoal.setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 21, width: 13, height: 80))

    drawText(
      displayName,
      rect: CGRect(x: margin + 30, y: 35, width: contentWidth - 48, height: 31),
      font: boldFont(27),
      color: charcoal,
      lineHeight: 31
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin + 30, y: 69, width: contentWidth - 48, height: 14),
      font: mediumFont(8.5),
      color: gray,
      lineHeight: 11
    )
    drawText(
      contactLine,
      rect: CGRect(x: margin, y: 112, width: contentWidth, height: 13),
      font: regularFont(8.2),
      color: charcoal,
      lineHeight: 10,
      alignment: .center
    )
  }

  private func drawContinuationHeader() {
    switch template {
    case .modern:
      drawModernContinuationHeader()
    case .classic:
      drawClassicContinuationHeader()
    case .minimal:
      drawMinimalContinuationHeader()
    case .contemporary, .corporate, .elegant, .nordic, .creative, .technical, .compact, .academic,
      .timeline, .monochrome:
      drawStyledContinuationHeader()
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

  private func drawStyledContinuationHeader() {
    let headerHeight: CGFloat = template == .compact ? 62 : 72
    let nameColor: UIColor
    let pageColor: UIColor

    switch template {
    case .corporate, .creative:
      navy.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: 0, y: 0, width: pageBounds.width, height: headerHeight))
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: 5))
      nameColor = .white
      pageColor = .white
    case .contemporary:
      navy.setFill()
      rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: 184, height: headerHeight))
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: 184, y: 0, width: 6, height: headerHeight))
      nameColor = .white
      pageColor = gray
    case .technical:
      lightGray.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: 0, y: 0, width: pageBounds.width, height: headerHeight))
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: 4))
      nameColor = navy
      pageColor = accent
    case .timeline:
      accent.withAlphaComponent(0.11).setFill()
      rendererContext.cgContext.fill(
        CGRect(x: 0, y: 0, width: pageBounds.width, height: headerHeight))
      accent.setFill()
      rendererContext.cgContext.fillEllipse(in: CGRect(x: 28, y: 25, width: 12, height: 12))
      nameColor = navy
      pageColor = accent
    case .monochrome:
      rendererContext.cgContext.setStrokeColor(charcoal.cgColor)
      rendererContext.cgContext.setLineWidth(1.5)
      rendererContext.cgContext.stroke(
        CGRect(x: margin, y: 14, width: contentWidth, height: 42))
      nameColor = charcoal
      pageColor = charcoal
    case .elegant, .academic:
      ruleGray.setFill()
      rendererContext.cgContext.fill(CGRect(x: margin, y: 57, width: contentWidth, height: 0.7))
      accent.setFill()
      rendererContext.cgContext.fillEllipse(
        in: CGRect(x: pageBounds.midX - 2.5, y: 55, width: 5, height: 5))
      nameColor = charcoal
      pageColor = gray
    case .nordic:
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: margin, y: 56, width: 70, height: 2))
      nameColor = navy
      pageColor = gray
    case .compact:
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: margin, y: 52, width: contentWidth, height: 3))
      nameColor = navy
      pageColor = gray
    case .modern, .classic, .minimal:
      nameColor = navy
      pageColor = gray
    }

    let isCentered = template == .elegant || template == .academic
    let nameX: CGFloat = template == .timeline ? 53 : margin
    let nameWidth: CGFloat = isCentered ? contentWidth : (template == .contemporary ? 130 : 390)
    let alignment: NSTextAlignment = isCentered ? .center : .left
    drawText(
      template == .technical ? "</>  \(displayName)" : displayName,
      rect: CGRect(x: nameX, y: 20, width: nameWidth, height: 24),
      font: boldFont(template == .compact ? 16 : 18),
      color: nameColor,
      lineHeight: 22,
      alignment: alignment
    )
    drawText(
      "PAGE \(pageNumber)",
      rect: CGRect(x: 490, y: 25, width: 71, height: 12),
      font: mediumFont(7.5),
      color: pageColor,
      lineHeight: 9,
      alignment: .right
    )
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
    case .contemporary:
      accent.withAlphaComponent(0.09).setFill()
      rendererContext.cgContext.fill(cardRect)
      navy.setFill()
      rendererContext.cgContext.fill(CGRect(x: x, y: y, width: 8, height: height))
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: x + 8, y: y, width: width - 8, height: 3))
    case .corporate:
      lightGray.setFill()
      rendererContext.cgContext.fill(cardRect)
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: x, y: y, width: width, height: 5))
      navy.setFill()
      rendererContext.cgContext.fill(CGRect(x: x, y: y + height - 2, width: width, height: 2))
    case .elegant, .academic:
      UIColor.white.setFill()
      rendererContext.cgContext.fill(cardRect)
      rendererContext.cgContext.setStrokeColor(charcoal.withAlphaComponent(0.55).cgColor)
      rendererContext.cgContext.setLineWidth(0.7)
      rendererContext.cgContext.stroke(cardRect.insetBy(dx: 0.5, dy: 0.5))
      rendererContext.cgContext.stroke(cardRect.insetBy(dx: 4, dy: 4))
      accent.setFill()
      rendererContext.cgContext.fillEllipse(
        in: CGRect(x: x + width / 2 - 3, y: y + 5, width: 6, height: 6))
    case .nordic:
      UIColor.white.setFill()
      rendererContext.cgContext.fill(cardRect)
      accent.withAlphaComponent(0.16).setFill()
      rendererContext.cgContext.fillEllipse(in: CGRect(x: x + 9, y: y + 11, width: 14, height: 14))
      ruleGray.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: x, y: y + height - 0.7, width: width, height: 0.7))
    case .creative:
      accent.withAlphaComponent(0.12).setFill()
      rendererContext.cgContext.fill(cardRect)
      navy.setFill()
      rendererContext.cgContext.fill(CGRect(x: x + width - 26, y: y, width: 26, height: 26))
      accent.setFill()
      rendererContext.cgContext.fillEllipse(
        in: CGRect(x: x + width - 35, y: y + height - 24, width: 38, height: 38))
    case .technical:
      UIColor.white.setFill()
      rendererContext.cgContext.fill(cardRect)
      rendererContext.cgContext.setStrokeColor(ruleGray.cgColor)
      rendererContext.cgContext.setLineWidth(0.7)
      rendererContext.cgContext.stroke(cardRect.insetBy(dx: 0.5, dy: 0.5))
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: x, y: y, width: 12, height: 3))
      rendererContext.cgContext.fill(CGRect(x: x, y: y, width: 3, height: 12))
      rendererContext.cgContext.fill(
        CGRect(x: x + width - 12, y: y + height - 3, width: 12, height: 3))
      rendererContext.cgContext.fill(
        CGRect(x: x + width - 3, y: y + height - 12, width: 3, height: 12))
    case .compact:
      lightGray.setFill()
      rendererContext.cgContext.fill(cardRect)
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: x, y: y, width: width, height: 3))
    case .timeline:
      UIColor.white.setFill()
      rendererContext.cgContext.fill(cardRect)
      accent.withAlphaComponent(0.35).setFill()
      rendererContext.cgContext.fill(CGRect(x: x + 7, y: y, width: 2, height: height))
      accent.setFill()
      rendererContext.cgContext.fillEllipse(in: CGRect(x: x + 3, y: y + 15, width: 10, height: 10))
    case .monochrome:
      UIColor.white.setFill()
      rendererContext.cgContext.fill(cardRect)
      rendererContext.cgContext.setStrokeColor(charcoal.cgColor)
      rendererContext.cgContext.setLineWidth(1)
      rendererContext.cgContext.stroke(cardRect.insetBy(dx: 0.5, dy: 0.5))
      charcoal.setFill()
      rendererContext.cgContext.fill(CGRect(x: x, y: y, width: 5, height: height))
    }

    let isCentered = template == .classic || template == .elegant || template == .academic
    let insetX = isCentered ? x + 10 : x + 16
    let textWidth = isCentered ? width - 20 : width - 27
    let alignment: NSTextAlignment = isCentered ? .center : .left
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
    let labelColor = template == .monochrome ? charcoal : accent
    drawText(
      "CONTACT NUMBER",
      rect: CGRect(x: insetX, y: y + 53, width: textWidth, height: 10),
      font: boldFont(6.8),
      color: labelColor,
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
      color: labelColor,
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
    case .contemporary, .corporate, .elegant, .nordic, .creative, .technical, .compact, .academic,
      .timeline, .monochrome:
      drawStyledSectionTitle(title)
    }
  }

  private func drawStyledSectionTitle(_ title: String) {
    switch template {
    case .contemporary:
      accent.withAlphaComponent(0.12).setFill()
      rendererContext.cgContext.fill(CGRect(x: margin, y: cursorY, width: 192, height: 21))
      navy.setFill()
      rendererContext.cgContext.fill(CGRect(x: margin, y: cursorY, width: 5, height: 21))
      drawText(
        title.uppercased(),
        rect: CGRect(x: margin + 14, y: cursorY + 3, width: 174, height: 15),
        font: boldFont(10.2),
        color: navy,
        lineHeight: 12
      )
      cursorY += 29
    case .corporate:
      navy.setFill()
      rendererContext.cgContext.fill(CGRect(x: margin, y: cursorY, width: contentWidth, height: 22))
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: margin, y: cursorY, width: 7, height: 22))
      drawText(
        title.uppercased(),
        rect: CGRect(x: margin + 16, y: cursorY + 4, width: contentWidth - 20, height: 15),
        font: boldFont(10),
        color: .white,
        lineHeight: 12
      )
      cursorY += 31
    case .elegant:
      drawText(
        title,
        rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: 18),
        font: boldFont(11.3),
        color: charcoal,
        lineHeight: 15,
        alignment: .center
      )
      ruleGray.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: margin, y: cursorY + 22, width: contentWidth, height: 0.6))
      accent.setFill()
      rendererContext.cgContext.fillEllipse(
        in: CGRect(x: pageBounds.midX - 3, y: cursorY + 19, width: 6, height: 6))
      cursorY += 31
    case .nordic:
      drawText(
        title.uppercased(),
        rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: 16),
        font: boldFont(10.5),
        color: navy,
        lineHeight: 13
      )
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: margin, y: cursorY + 21, width: 68, height: 2))
      cursorY += 31
    case .creative:
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: margin, y: cursorY, width: 29, height: 24))
      accent.withAlphaComponent(0.15).setFill()
      rendererContext.cgContext.fill(
        CGRect(x: margin + 29, y: cursorY, width: contentWidth - 29, height: 24))
      drawText(
        title.uppercased(),
        rect: CGRect(x: margin + 41, y: cursorY + 4, width: contentWidth - 48, height: 16),
        font: boldFont(10.5),
        color: navy,
        lineHeight: 13
      )
      cursorY += 32
    case .technical:
      drawText(
        "[ \(title.uppercased()) ]",
        rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: 16),
        font: boldFont(9.5),
        color: accent,
        lineHeight: 13
      )
      ruleGray.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: margin, y: cursorY + 21, width: contentWidth, height: 0.6))
      cursorY += 28
    case .compact:
      drawText(
        title.uppercased(),
        rect: CGRect(x: margin, y: cursorY, width: 178, height: 15),
        font: boldFont(9.8),
        color: navy,
        lineHeight: 12
      )
      accent.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: margin + 184, y: cursorY + 7, width: contentWidth - 184, height: 2))
      cursorY += 23
    case .academic:
      drawText(
        title.uppercased(),
        rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: 17),
        font: boldFont(10.8),
        color: charcoal,
        lineHeight: 14
      )
      charcoal.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: margin, y: cursorY + 21, width: contentWidth, height: 1.3))
      ruleGray.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: margin, y: cursorY + 25, width: contentWidth, height: 0.5))
      cursorY += 32
    case .timeline:
      accent.withAlphaComponent(0.35).setFill()
      rendererContext.cgContext.fill(CGRect(x: margin + 6, y: cursorY, width: 2, height: 25))
      accent.setFill()
      rendererContext.cgContext.fillEllipse(
        in: CGRect(x: margin + 1, y: cursorY + 3, width: 12, height: 12))
      drawText(
        title.uppercased(),
        rect: CGRect(x: margin + 24, y: cursorY + 1, width: contentWidth - 24, height: 16),
        font: boldFont(10.5),
        color: navy,
        lineHeight: 13
      )
      cursorY += 29
    case .monochrome:
      charcoal.setFill()
      rendererContext.cgContext.fill(CGRect(x: margin, y: cursorY, width: 182, height: 21))
      drawText(
        title.uppercased(),
        rect: CGRect(x: margin + 10, y: cursorY + 3, width: 168, height: 15),
        font: boldFont(9.8),
        color: .white,
        lineHeight: 12
      )
      charcoal.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: margin + 190, y: cursorY + 10, width: contentWidth - 190, height: 1))
      cursorY += 29
    case .modern, .classic, .minimal:
      break
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
    drawBulletMarker(x: margin, y: cursorY, compact: false)
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
    drawBulletMarker(x: x, y: y, compact: true)
    drawText(
      text,
      rect: CGRect(x: x + 13, y: y, width: width - 13, height: height),
      font: regularFont(8.8),
      color: charcoal,
      lineHeight: 11
    )
  }

  private func drawBulletMarker(x: CGFloat, y: CGFloat, compact: Bool) {
    let markerX = x + (compact ? 2 : 3)
    let markerY = y + (compact ? 3.5 : 4)
    (template == .monochrome ? charcoal : accent).setFill()

    switch template {
    case .modern, .nordic:
      rendererContext.cgContext.fillEllipse(
        in: CGRect(x: markerX, y: markerY, width: 3.2, height: 3.2))
    case .classic, .elegant, .academic, .monochrome:
      rendererContext.cgContext.fill(
        CGRect(x: markerX - 1, y: markerY + 1, width: 6, height: 1.4))
    case .minimal, .corporate, .technical, .compact:
      rendererContext.cgContext.fill(
        CGRect(x: markerX, y: markerY, width: 3.5, height: 3.5))
    case .contemporary, .timeline:
      rendererContext.cgContext.fill(
        CGRect(x: markerX + 1, y: markerY - 1, width: 2, height: 6))
    case .creative:
      let path = UIBezierPath()
      path.move(to: CGPoint(x: markerX + 2, y: markerY - 1))
      path.addLine(to: CGPoint(x: markerX + 5, y: markerY + 2))
      path.addLine(to: CGPoint(x: markerX + 2, y: markerY + 5))
      path.addLine(to: CGPoint(x: markerX - 1, y: markerY + 2))
      path.close()
      path.fill()
    }
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
    case .modern, .contemporary, .corporate, .compact:
      UIFont(name: "HelveticaNeue", size: size) ?? .systemFont(ofSize: size)
    case .classic, .elegant, .academic:
      UIFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size)
    case .minimal, .nordic, .timeline:
      UIFont(name: "AvenirNext-Regular", size: size) ?? .systemFont(ofSize: size)
    case .creative:
      UIFont(name: "Futura-Medium", size: size) ?? .systemFont(ofSize: size)
    case .technical:
      UIFont(name: "Menlo-Regular", size: size)
        ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    case .monochrome:
      UIFont(name: "HelveticaNeue-Condensed", size: size) ?? .systemFont(ofSize: size)
    }
  }

  private func mediumFont(_ size: CGFloat) -> UIFont {
    switch template {
    case .modern, .contemporary, .corporate, .compact:
      UIFont(name: "HelveticaNeue-Medium", size: size) ?? .systemFont(ofSize: size, weight: .medium)
    case .classic, .elegant, .academic:
      UIFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size, weight: .medium)
    case .minimal, .nordic, .timeline:
      UIFont(name: "AvenirNext-Medium", size: size) ?? .systemFont(ofSize: size, weight: .medium)
    case .creative:
      UIFont(name: "Futura-Medium", size: size) ?? .systemFont(ofSize: size, weight: .medium)
    case .technical:
      UIFont(name: "Menlo-Bold", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .medium)
    case .monochrome:
      UIFont(name: "HelveticaNeue-CondensedBold", size: size)
        ?? .systemFont(ofSize: size, weight: .medium)
    }
  }

  private func boldFont(_ size: CGFloat) -> UIFont {
    switch template {
    case .modern, .contemporary, .corporate, .compact:
      UIFont(name: "HelveticaNeue-Bold", size: size) ?? .systemFont(ofSize: size, weight: .bold)
    case .classic, .elegant, .academic:
      UIFont(name: "Georgia-Bold", size: size) ?? .systemFont(ofSize: size, weight: .bold)
    case .minimal, .nordic, .timeline:
      UIFont(name: "AvenirNext-DemiBold", size: size)
        ?? .systemFont(ofSize: size, weight: .semibold)
    case .creative:
      UIFont(name: "Futura-Bold", size: size) ?? .systemFont(ofSize: size, weight: .bold)
    case .technical:
      UIFont(name: "Menlo-Bold", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .bold)
    case .monochrome:
      UIFont(name: "HelveticaNeue-CondensedBold", size: size)
        ?? .systemFont(ofSize: size, weight: .bold)
    }
  }
}
