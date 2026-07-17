import Foundation
import UIKit

enum CoverLetterPDFRenderer {
  @MainActor
  static func render(document: CoverLetterDocument) throws -> Data {
    let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
    let format = UIGraphicsPDFRendererFormat()
    format.documentInfo = [
      kCGPDFContextTitle as String: document.suggestedFilename,
      kCGPDFContextAuthor as String: document.senderName,
      kCGPDFContextCreator as String: "ResumeStudio",
    ]
    return UIGraphicsPDFRenderer(bounds: bounds, format: format).pdfData { context in
      CoverLetterLayout(context: context, bounds: bounds, document: document).render()
    }
  }
}

@MainActor
private final class CoverLetterLayout {
  private let context: UIGraphicsPDFRendererContext
  private let bounds: CGRect
  private let document: CoverLetterDocument
  private let margin: CGFloat = 54
  private let footerY: CGFloat = 810
  private var cursorY: CGFloat = 0
  private var page = 0

  private var accent: UIColor { document.accent.uiColor }
  private let ink = UIColor(red: 0.10, green: 0.12, blue: 0.17, alpha: 1)
  private let muted = UIColor(red: 0.38, green: 0.40, blue: 0.44, alpha: 1)
  private let lightGray = UIColor(white: 0.95, alpha: 1)
  private let navy = UIColor(red: 0.17, green: 0.20, blue: 0.29, alpha: 1)

  /// Noir and Nocturne write in light ink on a dark sheet; everything the
  /// letter's flow draws goes through these so the pair can swap the whole
  /// palette at one seam.
  private var darkPaper: Bool { document.template == .noir || document.template == .nocturne }
  private var paper: UIColor {
    darkPaper ? UIColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1) : .white
  }
  private var inkColor: UIColor { darkPaper ? UIColor(white: 0.93, alpha: 1) : ink }
  private var mutedColor: UIColor { darkPaper ? UIColor(white: 0.66, alpha: 1) : muted }

  /// The column the letter flows down. Sidebar Letterhead moves it over to clear
  /// the band; every other style runs it the full width of the page.
  private var bodyX: CGFloat = 54
  private var bodyWidth: CGFloat = 487

  init(
    context: UIGraphicsPDFRendererContext,
    bounds: CGRect,
    document: CoverLetterDocument
  ) {
    self.context = context
    self.bounds = bounds
    self.document = document
  }

  func render() {
    beginPage(first: true)
    drawLetterDetails()
    drawBody()
  }

  private func beginPage(first: Bool) {
    context.beginPage()
    page += 1
    paper.setFill()
    context.cgContext.fill(bounds)

    if document.template == .sidebar {
      ink.setFill()
      context.cgContext.fill(CGRect(x: 0, y: 0, width: 168, height: bounds.height))
    }

    if first {
      drawHeader()
    } else {
      drawContinuationHeader()
    }
    drawFooter()
  }

  private func drawHeader() {
    switch document.template {
    case .sidebar:
      drawSidebarHeader()
    case .iconic:
      drawIconicHeader()
    case .rail:
      drawRailHeader()
    case .cardstock:
      drawCardstockHeader()
    case .broadsheet:
      drawBroadsheetHeader()
    case .modern:
      drawModernHeader()
    case .gradient:
      drawGradientHeader()
    case .executive:
      drawExecutiveHeader()
    case .monogram:
      drawMonogramHeader()
    case .minimal:
      drawMinimalHeader()
    case .memo:
      drawMemoHeader()
    case .creative:
      drawCreativeHeader()
    case .portfolio:
      drawPortfolioHeader()
    case .classic:
      drawClassicHeader()
    case .letterpress:
      drawLetterpressHeader()
    case .signature:
      drawSignatureHeader()
    case .noir:
      drawNoirHeader()
    case .marquee:
      drawMarqueeHeader()
    case .crest:
      drawCrestHeader()
    case .ivy:
      drawIvyHeader()
    case .plinth:
      drawPlinthHeader()
    case .stockholm:
      drawStockholmHeader()
    case .laureate:
      drawLaureateHeader()
    case .nova:
      drawNovaHeader()
    case .aurelia:
      drawAureliaHeader()
    case .nocturne:
      drawNocturneHeader()
    case .eclipse:
      drawEclipseHeader()
    case .vantage:
      drawVantageHeader()
    case .zenith, .aperture, .sovereign, .blueprint, .spectrum, .halo, .volta, .obsidian, .radiant,
      .verge, .datum, .pinnacle, .emblem, .cadence, .citadel, .stratus, .mirage,
      .salute, .couture, .medallion, .sable, .terracotta, .lozenge, .circlet, .vogue, .signet,
      .almanac:
      if let ordinal = document.template.advancedOrdinal {
        drawAdvancedHeader(ordinal)
      }
    }
  }

  private func drawModernHeader() {
    drawText(document.senderName, x: margin, y: 38, width: 330, font: .boldSystemFont(ofSize: 27), color: ink)
    drawText(document.senderHeadline, x: margin, y: 73, width: 330, font: .systemFont(ofSize: 11, weight: .medium), color: accent)
    drawContact(alignment: .right, y: 43)
    accent.setFill()
    context.cgContext.fill(CGRect(x: margin, y: 105, width: bounds.width - margin * 2, height: 3))
    cursorY = 137
  }

  private func drawClassicHeader() {
    drawText(document.senderName, x: margin, y: 34, width: bounds.width - margin * 2, font: serif(26, bold: true), color: ink, alignment: .center)
    drawText(document.senderHeadline, x: margin, y: 68, width: bounds.width - margin * 2, font: serif(11, bold: false), color: muted, alignment: .center)
    drawContact(alignment: .center, y: 90)
    accent.setFill()
    context.cgContext.fill(CGRect(x: 250, y: 115, width: 95, height: 1.5))
    cursorY = 143
  }

  private func drawMinimalHeader() {
    drawText(document.senderName, x: margin, y: 43, width: 330, font: .systemFont(ofSize: 24, weight: .semibold), color: ink)
    drawContact(alignment: .right, y: 45)
    UIColor(white: 0.84, alpha: 1).setFill()
    context.cgContext.fill(CGRect(x: margin, y: 96, width: bounds.width - margin * 2, height: 0.7))
    cursorY = 126
  }

  private func drawExecutiveHeader() {
    ink.setFill()
    context.cgContext.fill(CGRect(x: 0, y: 0, width: bounds.width, height: 119))
    accent.setFill()
    context.cgContext.fill(CGRect(x: 0, y: 0, width: 12, height: 119))
    drawText(document.senderName, x: margin, y: 31, width: 340, font: .boldSystemFont(ofSize: 28), color: .white)
    drawText(document.senderHeadline.uppercased(), x: margin, y: 69, width: 340, font: .systemFont(ofSize: 9, weight: .semibold), color: accent)
    drawContact(alignment: .right, y: 39, color: .white)
    cursorY = 149
  }

  private func drawCreativeHeader() {
    accent.setFill()
    context.cgContext.fill(CGRect(x: 0, y: 0, width: 178, height: 128))
    accent.withAlphaComponent(0.12).setFill()
    context.cgContext.fill(CGRect(x: 178, y: 0, width: bounds.width - 178, height: 128))
    // Height for two lines: the panel is narrow enough to wrap a full name, and
    // at the default 42 the surname fell outside the box and was never drawn.
    drawText(document.senderName, x: 31, y: 30, width: 120, height: 62, font: .boldSystemFont(ofSize: 24), color: .white)
    drawText(document.senderHeadline, x: 207, y: 35, width: 330, font: .systemFont(ofSize: 13, weight: .semibold), color: ink)
    drawContact(alignment: .left, y: 67, x: 207, width: 330)
    cursorY = 158
  }

  private func drawSignatureHeader() {
    accent.setFill()
    context.cgContext.fill(CGRect(x: 34, y: 27, width: 8, height: 96))
    accent.withAlphaComponent(0.10).setFill()
    context.cgContext.fillEllipse(in: CGRect(x: 472, y: 20, width: 88, height: 88))

    drawText(
      "PERSONAL LETTER",
      x: 62,
      y: 29,
      width: 220,
      height: 14,
      font: .systemFont(ofSize: 8, weight: .bold),
      color: accent
    )
    drawText(
      document.senderName,
      x: 62,
      y: 48,
      width: 330,
      font: serif(29, bold: true),
      color: ink
    )
    drawText(
      document.senderHeadline,
      x: 62,
      y: 84,
      width: 330,
      font: serif(11, bold: false),
      color: muted
    )
    drawContact(alignment: .right, y: 43, x: 386, width: 150)
    ink.setFill()
    context.cgContext.fill(CGRect(x: 62, y: 119, width: bounds.width - 96, height: 1))
    cursorY = 149
  }

  /// Noir's letter: the same dark sheet, the letterhead in light ink.
  private func drawNoirHeader() {
    drawText(document.senderName, x: margin, y: 38, width: 330, font: .boldSystemFont(ofSize: 27), color: .white)
    drawText(document.senderHeadline.uppercased(), x: margin, y: 74, width: 330, font: .systemFont(ofSize: 9, weight: .semibold), color: accent)
    drawContact(alignment: .right, y: 43, color: UIColor(white: 0.78, alpha: 1))
    accent.setFill()
    context.cgContext.fill(CGRect(x: margin, y: 108, width: 54, height: 2.5))
    cursorY = 140
  }

  /// Marquee's letter: the name at poster size, first name in the accent.
  private func drawMarqueeHeader() {
    let words = document.senderName.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    let first = words.first.map(String.init) ?? document.senderName
    let rest = words.count > 1 ? String(words[1]) : ""

    drawText(first, x: margin, y: 26, width: bounds.width - margin * 2, height: 40, font: .boldSystemFont(ofSize: 31), color: accent)
    var detailY: CGFloat = 64
    if !rest.isEmpty {
      drawText(rest, x: margin, y: 62, width: bounds.width - margin * 2, height: 40, font: .boldSystemFont(ofSize: 31), color: ink)
      detailY = 100
    }
    drawText(document.senderHeadline.uppercased(), x: margin, y: detailY + 2, width: 340, height: 14, font: .systemFont(ofSize: 8.6, weight: .semibold), color: muted)
    drawContact(alignment: .right, y: 31)
    accent.setFill()
    context.cgContext.fill(CGRect(x: margin, y: detailY + 24, width: bounds.width - margin * 2, height: 3.5))
    cursorY = detailY + 52
  }

  /// Crest's letter: the same navy banner with the accent seam under it.
  private func drawCrestHeader() {
    navy.setFill()
    context.cgContext.fill(CGRect(x: 0, y: 0, width: bounds.width, height: 112))
    accent.setFill()
    context.cgContext.fill(CGRect(x: 0, y: 112, width: bounds.width, height: 4))

    drawText(document.senderName, x: margin, y: 30, width: 340, font: .boldSystemFont(ofSize: 26), color: .white)
    drawText(document.senderHeadline.uppercased(), x: margin, y: 66, width: 340, font: .systemFont(ofSize: 9, weight: .semibold), color: accent)
    drawContact(alignment: .right, y: 38, color: UIColor.white.withAlphaComponent(0.85))
    cursorY = 146
  }

  /// Ivy's letter: the career office's own — centred serif, one rule, no colour.
  private func drawIvyHeader() {
    let width = bounds.width - margin * 2
    drawText(document.senderName, x: margin, y: 36, width: width, font: serif(24, bold: true), color: ink, alignment: .center)
    drawText(document.senderHeadline, x: margin, y: 68, width: width, font: serif(10.5, bold: false), color: muted, alignment: .center)
    drawContact(alignment: .center, y: 88, x: margin, width: width)
    ink.setFill()
    context.cgContext.fill(CGRect(x: margin, y: 116, width: width, height: 1))
    cursorY = 144
  }

  /// Plinth's letter: the header stays clean because the footer band along the
  /// foot of the page is carrying the contact.
  private func drawPlinthHeader() {
    drawText(document.senderName, x: margin, y: 36, width: 400, font: .boldSystemFont(ofSize: 27), color: ink)
    drawText(document.senderHeadline.uppercased(), x: margin, y: 72, width: 340, font: .systemFont(ofSize: 9, weight: .semibold), color: accent)
    accent.setFill()
    context.cgContext.fill(CGRect(x: margin, y: 98, width: 44, height: 3))
    cursorY = 130
  }

  /// Stockholm's letter: the same quiet tinted band, the contact set small
  /// where the résumé's narrow column would carry it.
  private func drawStockholmHeader() {
    accent.withAlphaComponent(0.07).setFill()
    context.cgContext.fill(CGRect(x: 0, y: 0, width: bounds.width, height: 112))
    accent.setFill()
    context.cgContext.fill(CGRect(x: 0, y: 112, width: bounds.width, height: 2))

    drawText(document.senderName, x: margin, y: 34, width: 330, font: .boldSystemFont(ofSize: 26), color: ink)
    drawText(document.senderHeadline, x: margin, y: 70, width: 330, font: .systemFont(ofSize: 11, weight: .medium), color: accent)
    drawContact(alignment: .right, y: 40)
    cursorY = 142
  }

  /// Laureate's letter: the two-tone name — surname in the accent — centred
  /// over the same fine rule the résumé answers with.
  private func drawLaureateHeader() {
    let words = document.senderName.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    let first = words.first.map(String.init) ?? document.senderName
    let rest = words.count > 1 ? String(words[1]) : ""

    let firstAttributes: [NSAttributedString.Key: Any] = [
      .font: UIFont.systemFont(ofSize: 26, weight: .regular), .foregroundColor: ink,
    ]
    let restAttributes: [NSAttributedString.Key: Any] = [
      .font: UIFont.boldSystemFont(ofSize: 26), .foregroundColor: accent,
    ]
    let firstWidth = ceil(NSAttributedString(string: first, attributes: firstAttributes).size().width)
    let restWidth = rest.isEmpty
      ? 0 : ceil(NSAttributedString(string: rest, attributes: restAttributes).size().width) + 8
    let total = firstWidth + restWidth

    if !rest.isEmpty, total <= bounds.width - margin * 2 {
      let startX = (bounds.width - total) / 2
      NSAttributedString(string: first, attributes: firstAttributes)
        .draw(at: CGPoint(x: startX, y: 34))
      NSAttributedString(string: rest, attributes: restAttributes)
        .draw(at: CGPoint(x: startX + firstWidth + 8, y: 34))
    } else {
      drawText(document.senderName, x: margin, y: 34, width: bounds.width - margin * 2, font: .boldSystemFont(ofSize: 24), color: ink, alignment: .center)
    }

    drawText(document.senderHeadline.uppercased(), x: margin, y: 72, width: bounds.width - margin * 2, height: 14, font: .systemFont(ofSize: 8.6, weight: .semibold), color: muted, alignment: .center)
    drawContact(alignment: .center, y: 92, x: margin, width: bounds.width - margin * 2)
    accent.setFill()
    context.cgContext.fill(CGRect(x: (bounds.width - 56) / 2, y: 120, width: 56, height: 2))
    cursorY = 148
  }

  /// Nova's letter: the same colour banner and dark seam, the contact in
  /// white where the résumé sets its icon strip.
  private func drawNovaHeader() {
    accent.setFill()
    context.cgContext.fill(CGRect(x: 0, y: 0, width: bounds.width, height: 116))
    navy.setFill()
    context.cgContext.fill(CGRect(x: 0, y: 116, width: bounds.width, height: 4))

    drawText(document.senderName, x: margin, y: 32, width: 340, font: .boldSystemFont(ofSize: 26), color: .white)
    drawText(document.senderHeadline.uppercased(), x: margin, y: 68, width: 340, font: .systemFont(ofSize: 9, weight: .semibold), color: UIColor.white.withAlphaComponent(0.9))
    drawContact(alignment: .right, y: 38, color: .white)
    cursorY = 148
  }

  /// Aurelia's letter: wide-tracked serif between hairlines, with the
  /// stationer's diamond at the seam.
  private func drawAureliaHeader() {
    let width = bounds.width - margin * 2
    // Tracked, but gently: past ~1.2 the PDF's text layer starts reading the
    // gaps as word breaks, and the name stops being searchable.
    let nameAttributes: [NSAttributedString.Key: Any] = [
      .font: serif(22, bold: true), .foregroundColor: ink, .kern: 1.2,
    ]
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    var centred = nameAttributes
    centred[.paragraphStyle] = style
    // The name keeps its own case: capitals would read fine on the page but
    // stop matching the name anywhere the PDF's text is searched.
    NSAttributedString(string: document.senderName, attributes: centred).draw(
      with: CGRect(x: margin, y: 34, width: width, height: 34),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      context: nil
    )
    drawText(document.senderHeadline.uppercased(), x: margin, y: 72, width: width, height: 14, font: .systemFont(ofSize: 8.4, weight: .medium), color: muted, alignment: .center)

    let armWidth = (width - 26) / 2
    UIColor(white: 0.78, alpha: 1).setFill()
    context.cgContext.fill(CGRect(x: margin, y: 97, width: armWidth, height: 0.6))
    context.cgContext.fill(CGRect(x: margin + width - armWidth, y: 97, width: armWidth, height: 0.6))
    let diamond = UIBezierPath()
    diamond.move(to: CGPoint(x: bounds.midX, y: 94))
    diamond.addLine(to: CGPoint(x: bounds.midX + 3.5, y: 97.3))
    diamond.addLine(to: CGPoint(x: bounds.midX, y: 100.6))
    diamond.addLine(to: CGPoint(x: bounds.midX - 3.5, y: 97.3))
    diamond.close()
    accent.setFill()
    diamond.fill()

    drawContact(alignment: .center, y: 108, x: margin, width: width)
    cursorY = 148
  }

  /// Nocturne's letter: the book serif in light ink on the dark sheet, under
  /// a letterpress double rule.
  private func drawNocturneHeader() {
    let width = bounds.width - margin * 2
    drawText(document.senderName, x: margin, y: 34, width: width, font: serif(24, bold: true), color: .white, alignment: .center)
    drawText(document.senderHeadline.uppercased(), x: margin, y: 68, width: width, height: 14, font: .systemFont(ofSize: 8.8, weight: .semibold), color: accent, alignment: .center)
    UIColor(white: 1, alpha: 0.8).setFill()
    context.cgContext.fill(CGRect(x: margin, y: 92, width: width, height: 1))
    UIColor(white: 1, alpha: 0.35).setFill()
    context.cgContext.fill(CGRect(x: margin, y: 96, width: width, height: 0.5))
    drawContact(alignment: .center, y: 104, x: margin, width: width, color: UIColor(white: 0.75, alpha: 1))
    cursorY = 140
  }

  /// Eclipse turns the letterhead into an orbit: the accent disc bleeds beyond
  /// the page while a small monogram crosses its edge. The text stays on a clean
  /// white measure, so the gesture feels expressive without compromising the
  /// letter itself.
  private func drawEclipseHeader() {
    let halo = CGRect(x: bounds.width - 146, y: -76, width: 226, height: 226)
    accent.withAlphaComponent(0.12).setFill()
    context.cgContext.fillEllipse(in: halo)

    let disc = CGRect(x: bounds.width - 128, y: -58, width: 190, height: 190)
    accent.setFill()
    context.cgContext.fillEllipse(in: disc)

    let monogram = CGRect(x: bounds.width - 108, y: 31, width: 66, height: 66)
    UIColor.white.withAlphaComponent(0.18).setFill()
    context.cgContext.fillEllipse(in: monogram)
    context.cgContext.setStrokeColor(UIColor.white.cgColor)
    context.cgContext.setLineWidth(2.2)
    context.cgContext.strokeEllipse(in: monogram.insetBy(dx: 1.1, dy: 1.1))
    drawText(
      document.initials,
      x: monogram.minX,
      y: monogram.minY + 19,
      width: monogram.width,
      height: 30,
      font: .systemFont(ofSize: 19, weight: .bold),
      color: .white,
      alignment: .center
    )

    drawText(
      "APPLICATION LETTER",
      x: margin,
      y: 31,
      width: 250,
      height: 14,
      font: .systemFont(ofSize: 8, weight: .bold),
      color: accent
    )
    drawText(
      document.senderName,
      x: margin,
      y: 50,
      width: 340,
      height: 40,
      font: .systemFont(ofSize: 28, weight: .bold),
      color: ink
    )
    drawText(
      document.senderHeadline.uppercased(),
      x: margin,
      y: 88,
      width: 340,
      height: 14,
      font: .systemFont(ofSize: 8.7, weight: .semibold),
      color: muted
    )

    UIColor(white: 0.82, alpha: 1).setFill()
    context.cgContext.fill(CGRect(x: margin, y: 113, width: bounds.width - margin * 2, height: 0.7))
    accent.setFill()
    context.cgContext.fill(CGRect(x: margin, y: 112, width: 56, height: 2.8))
    drawContact(alignment: .left, y: 124, x: margin, width: 330)
    cursorY = 170
  }

  /// Vantage is an editorial masthead: deep ink, a translucent typographic mark
  /// and a sharp accent seam. It is intentionally bolder than the letter body,
  /// giving an application a memorable opening while the correspondence below
  /// remains calm and highly readable.
  private func drawVantageHeader() {
    let panelHeight: CGFloat = 158
    drawGradientBand(
      CGRect(x: 0, y: 0, width: bounds.width, height: panelHeight),
      from: ink,
      to: navy
    )

    accent.withAlphaComponent(0.16).setFill()
    context.cgContext.fillEllipse(
      in: CGRect(x: bounds.width - 172, y: -86, width: 238, height: 238))
    drawText(
      document.initials,
      x: bounds.width - 180,
      y: 35,
      width: 138,
      height: 86,
      font: .systemFont(ofSize: 57, weight: .black),
      color: UIColor.white.withAlphaComponent(0.10),
      alignment: .right
    )

    drawText(
      "CANDIDATE / APPLICATION",
      x: margin,
      y: 28,
      width: 280,
      height: 14,
      font: .systemFont(ofSize: 8, weight: .bold),
      color: accent
    )
    drawText(
      document.senderName,
      x: margin,
      y: 49,
      width: 355,
      height: 42,
      font: .systemFont(ofSize: 29, weight: .bold),
      color: .white
    )
    drawText(
      document.senderHeadline.uppercased(),
      x: margin,
      y: 88,
      width: 355,
      height: 15,
      font: .systemFont(ofSize: 8.7, weight: .semibold),
      color: accent
    )
    drawContact(
      alignment: .left,
      y: 113,
      x: margin,
      width: 360,
      color: UIColor.white.withAlphaComponent(0.80)
    )

    accent.setFill()
    context.cgContext.fill(CGRect(x: 0, y: panelHeight, width: bounds.width, height: 4))
    cursorY = 190
  }

  // MARK: - The matched letterheads
  //
  // Each of these is the letter half of a structural résumé: same colour, same
  // furniture, so the two documents arrive looking like one application.

  /// Atlas's column, in letter form. The band runs the height of the page and
  /// carries the contact details; the letter itself keeps to the wide column.
  /// Seven individually art-directed application letterheads. Each changes the
  /// hierarchy, geometry and type while the correspondence stays searchable.
  private func drawAdvancedHeader(_ ordinal: Int) {
    let width = bounds.width - margin * 2
    // The Showcase Collection letterheads (17-26) are self-contained, echoing the
    // matching Showcase résumé mastheads; the original seventeen stay untouched.
    if ordinal >= 17 {
      drawShowcaseLetterhead(ordinal)
      return
    }
    switch ordinal {
    case 0: // Zenith — crowned executive hero
      let height: CGFloat = 164
      drawGradientBand(CGRect(x: 0, y: 0, width: bounds.width, height: height), from: ink, to: navy)
      accent.setFill()
      context.cgContext.fill(CGRect(x: 0, y: height - 5, width: bounds.width, height: 5))
      accent.withAlphaComponent(0.18).setFill()
      context.cgContext.fillEllipse(in: CGRect(x: bounds.width - 178, y: -86, width: 250, height: 250))
      drawText(document.initials, x: bounds.width - 174, y: 36, width: 126, height: 72, font: .systemFont(ofSize: 52, weight: .black), color: UIColor.white.withAlphaComponent(0.10), alignment: .right)
      drawText("ZENITH / APPLICATION", x: margin, y: 27, width: 280, height: 14, font: .systemFont(ofSize: 8, weight: .bold), color: accent)
      drawText(document.senderName, x: margin, y: 48, width: 350, height: 42, font: .systemFont(ofSize: 29, weight: .bold), color: .white)
      drawText(document.senderHeadline.uppercased(), x: margin, y: 89, width: 350, height: 14, font: .systemFont(ofSize: 8.7, weight: .semibold), color: accent)
      drawContact(alignment: .left, y: 116, x: margin, width: 360, color: UIColor.white.withAlphaComponent(0.78))
      cursorY = height + 31

    case 1: // Aperture — cinematic rings and monogram lens
      accent.withAlphaComponent(0.065).setFill()
      context.cgContext.fill(CGRect(x: 0, y: 0, width: bounds.width, height: 168))
      let centre = CGPoint(x: bounds.width - 92, y: 72)
      for ring in 0..<5 {
        let diameter = 68 + CGFloat(ring * 24)
        context.cgContext.setStrokeColor(accent.withAlphaComponent(0.75 - CGFloat(ring) * 0.11).cgColor)
        context.cgContext.setLineWidth(ring == 1 ? 3 : 0.8)
        context.cgContext.strokeEllipse(in: CGRect(x: centre.x - diameter / 2, y: centre.y - diameter / 2, width: diameter, height: diameter))
      }
      accent.setFill()
      context.cgContext.fillEllipse(in: CGRect(x: centre.x - 31, y: centre.y - 31, width: 62, height: 62))
      drawText(document.initials, x: centre.x - 31, y: centre.y - 10, width: 62, height: 26, font: .systemFont(ofSize: 17, weight: .bold), color: .white, alignment: .center)
      drawText("CANDIDATE / FOCUS", x: margin, y: 27, width: 250, height: 14, font: .systemFont(ofSize: 8, weight: .bold), color: accent)
      drawText(document.senderName, x: margin, y: 49, width: 350, height: 42, font: .systemFont(ofSize: 28, weight: .bold), color: ink)
      drawText(document.senderHeadline, x: margin, y: 89, width: 350, height: 16, font: .systemFont(ofSize: 10.5, weight: .medium), color: muted)
      drawContact(alignment: .left, y: 117, x: margin, width: 340)
      accent.setFill()
      context.cgContext.fill(CGRect(x: margin, y: 145, width: width, height: 3))
      cursorY = 180

    case 2: // Sovereign — double-rule formal editorial
      UIColor(red: 0.988, green: 0.98, blue: 0.958, alpha: 1).setFill()
      context.cgContext.fill(CGRect(x: 0, y: 0, width: bounds.width, height: 174))
      context.cgContext.setStrokeColor(ink.withAlphaComponent(0.72).cgColor)
      context.cgContext.setLineWidth(1)
      context.cgContext.stroke(CGRect(x: 28, y: 20, width: bounds.width - 56, height: 133))
      context.cgContext.setLineWidth(0.5)
      context.cgContext.stroke(CGRect(x: 33, y: 25, width: bounds.width - 66, height: 123))
      drawText("SOVEREIGN CORRESPONDENCE", x: margin, y: 35, width: width, height: 13, font: serif(7.8, bold: false), color: accent, alignment: .center)
      drawText(document.senderName, x: margin, y: 57, width: width, height: 37, font: serif(27, bold: true), color: ink, alignment: .center)
      drawText(document.senderHeadline.uppercased(), x: margin, y: 93, width: width, height: 14, font: serif(8.5, bold: false), color: muted, alignment: .center)
      drawContact(alignment: .center, y: 119, x: margin, width: width)
      accent.setFill()
      context.cgContext.fill(CGRect(x: bounds.midX - 4, y: 145, width: 8, height: 8).insetBy(dx: 1.5, dy: 1.5))
      cursorY = 190

    case 3: // Blueprint — drafting grid and coordinate labels
      UIColor(red: 0.965, green: 0.978, blue: 0.992, alpha: 1).setFill()
      context.cgContext.fill(CGRect(x: 0, y: 0, width: bounds.width, height: 166))
      accent.withAlphaComponent(0.10).setFill()
      for x in stride(from: CGFloat(0), through: bounds.width, by: 15) {
        context.cgContext.fill(CGRect(x: x, y: 0, width: 0.55, height: 166))
      }
      for y in stride(from: CGFloat(0), through: CGFloat(166), by: 15) {
        context.cgContext.fill(CGRect(x: 0, y: y, width: bounds.width, height: 0.55))
      }
      context.cgContext.setStrokeColor(accent.withAlphaComponent(0.7).cgColor)
      context.cgContext.setLineWidth(1.1)
      context.cgContext.stroke(CGRect(x: margin, y: 24, width: width, height: 113))
      drawText("DOCUMENT 04 / APPLICATION", x: margin + 14, y: 34, width: 260, height: 13, font: .monospacedSystemFont(ofSize: 7.5, weight: .bold), color: accent)
      drawText(document.senderName, x: margin + 14, y: 56, width: 350, height: 37, font: .monospacedSystemFont(ofSize: 24, weight: .bold), color: ink)
      drawText(document.senderHeadline.uppercased(), x: margin + 14, y: 92, width: 350, height: 14, font: .monospacedSystemFont(ofSize: 8.2, weight: .medium), color: muted)
      drawContact(alignment: .right, y: 55, x: bounds.width - margin - 170, width: 156)
      drawText("X:595 / Y:842", x: bounds.width - margin - 130, y: 119, width: 116, height: 11, font: .monospacedSystemFont(ofSize: 6.8, weight: .regular), color: accent, alignment: .right)
      cursorY = 184

    case 4: // Spectrum — layered colour field
      drawGradientBand(CGRect(x: 0, y: 0, width: bounds.width, height: 171), from: accent, to: navy)
      for index in 0..<5 {
        UIColor.white.withAlphaComponent(0.055 + CGFloat(index) * 0.025).setFill()
        context.cgContext.fill(CGRect(x: CGFloat(index) * bounds.width / 5, y: 0, width: bounds.width / 5, height: 171))
      }
      UIColor.black.withAlphaComponent(0.16).setFill()
      context.cgContext.fill(CGRect(x: 0, y: 0, width: 214, height: 171))
      drawText("SPECTRUM / STATEMENT", x: margin, y: 29, width: 260, height: 14, font: .systemFont(ofSize: 8, weight: .bold), color: .white)
      drawText(document.senderName, x: margin, y: 51, width: 380, height: 42, font: .systemFont(ofSize: 29, weight: .black), color: .white)
      drawText(document.senderHeadline.uppercased(), x: margin, y: 92, width: 360, height: 14, font: .systemFont(ofSize: 8.8, weight: .semibold), color: UIColor.white.withAlphaComponent(0.86))
      drawContact(alignment: .left, y: 121, x: margin, width: 360, color: .white)
      cursorY = 191

    case 5: // Halo — orbiting monogram, quiet luxury
      let centre = CGPoint(x: bounds.midX, y: 69)
      accent.withAlphaComponent(0.06).setFill()
      context.cgContext.fill(CGRect(x: 0, y: 0, width: bounds.width, height: 178))
      for ring in 0..<3 {
        let diameter = 72 + CGFloat(ring * 23)
        context.cgContext.setStrokeColor(accent.withAlphaComponent(0.65 - CGFloat(ring) * 0.15).cgColor)
        context.cgContext.setLineWidth(ring == 0 ? 2 : 0.8)
        context.cgContext.strokeEllipse(in: CGRect(x: centre.x - diameter / 2, y: centre.y - diameter / 2, width: diameter, height: diameter))
      }
      accent.setFill()
      context.cgContext.fillEllipse(in: CGRect(x: centre.x - 26, y: centre.y - 26, width: 52, height: 52))
      drawText(document.initials, x: centre.x - 26, y: centre.y - 8, width: 52, height: 24, font: .systemFont(ofSize: 16, weight: .bold), color: .white, alignment: .center)
      drawText(document.senderName, x: margin, y: 121, width: width, height: 30, font: serif(22, bold: true), color: ink, alignment: .center)
      drawContact(alignment: .center, y: 151, x: margin, width: width)
      cursorY = 195

    case 7: // Obsidian — layered glass panels on midnight
      let height: CGFloat = 158
      UIColor(white: 0.10, alpha: 1).setFill()
      context.cgContext.fill(CGRect(x: 0, y: 0, width: bounds.width, height: height))
      for index in 0..<3 {
        let inset = CGFloat(index) * 15
        let panelColor = index == 1 ? accent : navy
        panelColor.withAlphaComponent(0.9 - CGFloat(index) * 0.24).setFill()
        UIBezierPath(
          roundedRect: CGRect(x: bounds.width - 252 + inset, y: -42 + inset, width: 268, height: 150),
          cornerRadius: 15
        ).fill()
      }
      accent.setFill()
      context.cgContext.fill(CGRect(x: 0, y: height - 4, width: bounds.width, height: 4))
      drawText("OBSIDIAN / APPLICATION", x: margin, y: 28, width: 280, height: 14, font: .systemFont(ofSize: 8, weight: .bold), color: accent)
      drawText(document.senderName, x: margin, y: 50, width: 340, height: 42, font: .systemFont(ofSize: 28, weight: .bold), color: .white)
      drawText(document.senderHeadline.uppercased(), x: margin, y: 91, width: 340, height: 14, font: .systemFont(ofSize: 8.7, weight: .semibold), color: accent)
      drawContact(alignment: .left, y: 118, x: margin, width: 340, color: UIColor.white.withAlphaComponent(0.8))
      cursorY = height + 30

    case 8: // Radiant — a soft halo of light
      let height: CGFloat = 160
      accent.withAlphaComponent(0.06).setFill()
      context.cgContext.fill(CGRect(x: 0, y: 0, width: bounds.width, height: height))
      let glowCentre = CGPoint(x: margin + 96, y: 78)
      for ring in (0..<5).reversed() {
        accent.withAlphaComponent(0.05 + CGFloat(4 - ring) * 0.035).setFill()
        let diameter = 60 + CGFloat(ring) * 46
        context.cgContext.fillEllipse(in: CGRect(x: glowCentre.x - diameter / 2, y: glowCentre.y - diameter / 2, width: diameter, height: diameter))
      }
      accent.setFill()
      context.cgContext.fill(CGRect(x: margin, y: height - 4, width: width, height: 4))
      drawText("RADIANT / HELLO", x: margin, y: 28, width: 250, height: 14, font: .systemFont(ofSize: 8, weight: .bold), color: accent)
      drawText(document.senderName, x: margin, y: 52, width: 350, height: 42, font: .systemFont(ofSize: 28, weight: .bold), color: ink)
      drawText(document.senderHeadline, x: margin, y: 92, width: 350, height: 16, font: .systemFont(ofSize: 10.5, weight: .medium), color: muted)
      drawContact(alignment: .right, y: 40, x: bounds.width - margin - 170, width: 156)
      cursorY = height + 30

    case 9: // Verge — two-tone diagonal split
      let height: CGFloat = 158
      navy.setFill()
      context.cgContext.fill(CGRect(x: 0, y: 0, width: bounds.width, height: height))
      let wedge = UIBezierPath()
      wedge.move(to: CGPoint(x: bounds.width * 0.54, y: 0))
      wedge.addLine(to: CGPoint(x: bounds.width, y: 0))
      wedge.addLine(to: CGPoint(x: bounds.width, y: height))
      wedge.addLine(to: CGPoint(x: bounds.width * 0.68, y: height))
      wedge.close()
      accent.setFill()
      wedge.fill()
      UIColor.white.withAlphaComponent(0.85).setStroke()
      let seam = UIBezierPath()
      seam.move(to: CGPoint(x: bounds.width * 0.54, y: 0))
      seam.addLine(to: CGPoint(x: bounds.width * 0.68, y: height))
      seam.lineWidth = 2
      seam.stroke()
      drawText("VERGE / APPLICATION", x: margin, y: 28, width: 260, height: 14, font: .systemFont(ofSize: 8, weight: .bold), color: accent)
      drawText(document.senderName, x: margin, y: 51, width: 300, height: 42, font: .systemFont(ofSize: 29, weight: .bold), color: .white)
      drawText(document.senderHeadline.uppercased(), x: margin, y: 92, width: 300, height: 14, font: .systemFont(ofSize: 8.7, weight: .semibold), color: UIColor.white.withAlphaComponent(0.85))
      drawContact(alignment: .left, y: 120, x: margin, width: 300, color: UIColor.white.withAlphaComponent(0.8))
      cursorY = height + 30

    case 10: // Datum — tiled metrics
      let height: CGFloat = 162
      UIColor(white: 0.98, alpha: 1).setFill()
      context.cgContext.fill(CGRect(x: 0, y: 0, width: bounds.width, height: height))
      for index in 0..<3 {
        let tileW: CGFloat = 44
        let tx = bounds.width - margin - CGFloat(3 - index) * (tileW + 8) + 8
        accent.withAlphaComponent(0.10).setFill()
        UIBezierPath(roundedRect: CGRect(x: tx, y: 30, width: tileW, height: 32), cornerRadius: 4).fill()
        accent.setFill()
        context.cgContext.fill(CGRect(x: tx + 9, y: 38, width: 16, height: 4))
        accent.withAlphaComponent(0.4).setFill()
        context.cgContext.fill(CGRect(x: tx + 9, y: 48, width: 26, height: 2))
      }
      drawText("DATUM / BRIEF", x: margin, y: 30, width: 250, height: 14, font: .systemFont(ofSize: 8, weight: .bold), color: accent)
      drawText(document.senderName, x: margin, y: 52, width: 340, height: 42, font: .systemFont(ofSize: 27, weight: .bold), color: ink)
      drawText(document.senderHeadline.uppercased(), x: margin, y: 92, width: 340, height: 14, font: .systemFont(ofSize: 8.5, weight: .semibold), color: muted)
      accent.setFill()
      context.cgContext.fill(CGRect(x: margin, y: 118, width: 54, height: 3))
      drawContact(alignment: .left, y: 130, x: margin, width: 340)
      cursorY = height + 28

    case 11: // Pinnacle — architected frame and keystone
      let height: CGFloat = 168
      UIColor(red: 0.99, green: 0.985, blue: 0.965, alpha: 1).setFill()
      context.cgContext.fill(CGRect(x: 0, y: 0, width: bounds.width, height: height))
      context.cgContext.setStrokeColor(navy.withAlphaComponent(0.75).cgColor)
      context.cgContext.setLineWidth(1)
      context.cgContext.stroke(CGRect(x: 24, y: 22, width: bounds.width - 48, height: height - 44))
      context.cgContext.setLineWidth(0.6)
      context.cgContext.stroke(CGRect(x: 29, y: 27, width: bounds.width - 58, height: height - 54))
      let keystone = UIBezierPath()
      let kcx = bounds.midX
      keystone.move(to: CGPoint(x: kcx - 18, y: 10))
      keystone.addLine(to: CGPoint(x: kcx + 18, y: 10))
      keystone.addLine(to: CGPoint(x: kcx + 11, y: 32))
      keystone.addLine(to: CGPoint(x: kcx - 11, y: 32))
      keystone.close()
      accent.setFill()
      keystone.fill()
      drawText(document.senderName, x: margin, y: 58, width: width, height: 38, font: serif(27, bold: true), color: ink, alignment: .center)
      drawText(document.senderHeadline.uppercased(), x: margin, y: 96, width: width, height: 14, font: serif(8.5, bold: false), color: muted, alignment: .center)
      drawContact(alignment: .center, y: 122, x: margin, width: width)
      cursorY = height + 28

    case 12: // Emblem — hexagon monogram
      let height: CGFloat = 160
      UIColor(white: 0.985, alpha: 1).setFill()
      context.cgContext.fill(CGRect(x: 0, y: 0, width: bounds.width, height: height))
      accent.setFill()
      context.cgContext.fill(CGRect(x: 0, y: 0, width: 10, height: height))
      let hexCentre = CGPoint(x: bounds.width - 84, y: 74)
      let hex = UIBezierPath()
      for corner in 0..<6 {
        let angle = CGFloat.pi / 3 * CGFloat(corner) - CGFloat.pi / 2
        let point = CGPoint(x: hexCentre.x + 46 * cos(angle), y: hexCentre.y + 46 * sin(angle))
        if corner == 0 { hex.move(to: point) } else { hex.addLine(to: point) }
      }
      hex.close()
      accent.withAlphaComponent(0.12).setFill()
      hex.fill()
      accent.setStroke()
      hex.lineWidth = 1.6
      hex.stroke()
      drawText(document.initials, x: hexCentre.x - 46, y: hexCentre.y - 13, width: 92, height: 26, font: .boldSystemFont(ofSize: 20), color: accent, alignment: .center)
      drawText("EMBLEM / APPLICATION", x: 26, y: 30, width: 260, height: 14, font: .systemFont(ofSize: 8, weight: .bold), color: accent)
      drawText(document.senderName, x: 26, y: 52, width: 320, height: 42, font: .systemFont(ofSize: 27, weight: .bold), color: ink)
      drawText(document.senderHeadline, x: 26, y: 92, width: 320, height: 16, font: .systemFont(ofSize: 10.5, weight: .medium), color: muted)
      drawContact(alignment: .left, y: 120, x: 26, width: 320)
      cursorY = height + 28

    case 13: // Cadence — equaliser of accent bars
      let height: CGFloat = 158
      accent.withAlphaComponent(0.05).setFill()
      context.cgContext.fill(CGRect(x: 0, y: 0, width: bounds.width, height: height))
      var barX = bounds.width * 0.52
      var barIndex = 0
      while barX < bounds.width - margin {
        let barHeight = 8 + CGFloat((barIndex * 11) % 34)
        accent.withAlphaComponent(barIndex.isMultiple(of: 2) ? 0.72 : 0.34).setFill()
        context.cgContext.fill(CGRect(x: barX, y: height - 12 - barHeight, width: 6, height: barHeight))
        barX += 11
        barIndex += 1
      }
      drawText("CADENCE / NOTE", x: margin, y: 28, width: 250, height: 14, font: .systemFont(ofSize: 8, weight: .bold), color: accent)
      drawText(document.senderName, x: margin, y: 51, width: 320, height: 42, font: .systemFont(ofSize: 28, weight: .bold), color: ink)
      drawText(document.senderHeadline.uppercased(), x: margin, y: 92, width: 320, height: 14, font: .systemFont(ofSize: 8.6, weight: .semibold), color: muted)
      accent.setFill()
      context.cgContext.fill(CGRect(x: margin, y: 118, width: 54, height: 3))
      drawContact(alignment: .left, y: 130, x: margin, width: 320)
      cursorY = height + 28

    case 14: // Citadel — commanding navy banner and inner frame
      let height: CGFloat = 164
      navy.setFill()
      context.cgContext.fill(CGRect(x: 0, y: 0, width: bounds.width, height: height))
      accent.setFill()
      context.cgContext.fill(CGRect(x: 0, y: height - 4, width: bounds.width, height: 4))
      context.cgContext.setStrokeColor(UIColor.white.withAlphaComponent(0.35).cgColor)
      context.cgContext.setLineWidth(0.8)
      context.cgContext.stroke(CGRect(x: 24, y: 20, width: bounds.width - 48, height: height - 44))
      drawText("CITADEL / DISPATCH", x: margin + 6, y: 34, width: 260, height: 14, font: serif(8, bold: false), color: accent)
      drawText(document.senderName, x: margin + 6, y: 56, width: 360, height: 40, font: serif(27, bold: true), color: .white)
      drawText(document.senderHeadline.uppercased(), x: margin + 6, y: 96, width: 360, height: 14, font: serif(8.6, bold: false), color: UIColor.white.withAlphaComponent(0.82))
      drawContact(alignment: .right, y: 40, x: bounds.width - margin - 172, width: 150, color: UIColor.white.withAlphaComponent(0.82))
      cursorY = height + 30

    case 15: // Stratus — drifting gradient bands
      let height: CGFloat = 158
      UIColor(white: 0.99, alpha: 1).setFill()
      context.cgContext.fill(CGRect(x: 0, y: 0, width: bounds.width, height: height))
      for index in 0..<5 {
        let bandY = CGFloat(index) * height / 5
        accent.withAlphaComponent(0.05 + CGFloat(5 - index) * 0.03).setFill()
        context.cgContext.fill(CGRect(x: 0, y: bandY, width: bounds.width, height: height / 5 + 1))
      }
      accent.setFill()
      context.cgContext.fill(CGRect(x: 0, y: height - 3, width: bounds.width, height: 3))
      drawText("STRATUS / STATEMENT", x: margin, y: 30, width: 260, height: 14, font: .systemFont(ofSize: 8, weight: .bold), color: accent)
      drawText(document.senderName, x: margin, y: 52, width: 340, height: 42, font: .systemFont(ofSize: 28, weight: .bold), color: ink)
      drawText(document.senderHeadline.uppercased(), x: margin, y: 92, width: 340, height: 14, font: .systemFont(ofSize: 8.6, weight: .semibold), color: muted)
      drawContact(alignment: .left, y: 120, x: margin, width: 340)
      cursorY = height + 28

    case 16: // Mirage — a shimmering horizontal gradient
      let height: CGFloat = 160
      drawGradientBand(CGRect(x: 0, y: 0, width: bounds.width, height: height), from: accent.withAlphaComponent(0.16), to: navy.withAlphaComponent(0.10))
      UIColor(white: 1, alpha: 0.5).setFill()
      context.cgContext.fill(CGRect(x: 0, y: 0, width: bounds.width, height: height))
      drawGradientBand(CGRect(x: 0, y: height - 46, width: bounds.width, height: 46), from: accent.withAlphaComponent(0.22), to: accent.withAlphaComponent(0))
      accent.setFill()
      context.cgContext.fill(CGRect(x: 0, y: height - 3, width: bounds.width, height: 3))
      drawText("MIRAGE / LETTER", x: margin, y: 30, width: 250, height: 14, font: .systemFont(ofSize: 8, weight: .bold), color: accent)
      drawText(document.senderName, x: margin, y: 52, width: 340, height: 42, font: .systemFont(ofSize: 28, weight: .bold), color: ink)
      drawText(document.senderHeadline.uppercased(), x: margin, y: 92, width: 340, height: 14, font: .systemFont(ofSize: 8.6, weight: .semibold), color: muted)
      drawContact(alignment: .right, y: 40, x: bounds.width - margin - 170, width: 156)
      cursorY = height + 28

    default: // Volta — electric spine and diagonal charge
      let height: CGFloat = 168
      ink.setFill()
      context.cgContext.fill(CGRect(x: 0, y: 0, width: bounds.width, height: height))
      accent.setFill()
      context.cgContext.fill(CGRect(x: 0, y: 0, width: 24, height: height))
      let bolt = UIBezierPath()
      bolt.move(to: CGPoint(x: bounds.width - 126, y: 0))
      bolt.addLine(to: CGPoint(x: bounds.width - 42, y: 0))
      bolt.addLine(to: CGPoint(x: bounds.width - 104, y: 76))
      bolt.addLine(to: CGPoint(x: bounds.width - 52, y: 76))
      bolt.addLine(to: CGPoint(x: bounds.width - 158, y: height))
      bolt.addLine(to: CGPoint(x: bounds.width - 112, y: 98))
      bolt.addLine(to: CGPoint(x: bounds.width - 172, y: 98))
      bolt.close()
      accent.setFill()
      bolt.fill()
      drawText("VOLTA / APPLICATION", x: margin, y: 28, width: 270, height: 14, font: .systemFont(ofSize: 8, weight: .bold), color: accent)
      drawText(document.senderName, x: margin, y: 51, width: 350, height: 42, font: .systemFont(ofSize: 29, weight: .heavy), color: .white)
      drawText(document.senderHeadline.uppercased(), x: margin, y: 92, width: 350, height: 14, font: .systemFont(ofSize: 8.8, weight: .semibold), color: UIColor.white.withAlphaComponent(0.82))
      drawContact(alignment: .left, y: 121, x: margin, width: 350, color: UIColor.white.withAlphaComponent(0.82))
      cursorY = height + 31
    }
  }

  // MARK: - Showcase Collection letterheads (ordinals 17-26)

  private func drawShowcaseLetterhead(_ ordinal: Int) {
    let cg = context.cgContext
    let w = bounds.width
    let name = document.senderName
    let headline = document.senderHeadline
    let warm = UIColor(red: 0.905, green: 0.865, blue: 0.795, alpha: 1)

    switch ordinal {
    case 17:  // Salute — warm hello and a round monogram
      accent.setFill()
      cg.fill(CGRect(x: margin, y: 34, width: 6, height: 6))
      accent.withAlphaComponent(0.45).setFill()
      cg.fill(CGRect(x: margin + 8, y: 34, width: 6, height: 6))
      cg.fill(CGRect(x: margin, y: 42, width: 6, height: 6))
      drawLetterMonogram(centre: CGPoint(x: w - margin - 34, y: 62), radius: 34, filled: true)
      drawText("HELLO", x: margin, y: 60, width: 200, height: 12, font: .systemFont(ofSize: 8, weight: .semibold), color: accent)
      drawText("Hi, I'm \(name).", x: margin, y: 74, width: w - margin * 2 - 90, height: 40, font: .systemFont(ofSize: 25, weight: .bold), color: ink)
      drawText(headline, x: margin, y: 114, width: 340, height: 16, font: .systemFont(ofSize: 10, weight: .medium), color: muted)
      drawContact(alignment: .left, y: 138, x: margin, width: 340)
      accent.setFill(); cg.fill(CGRect(x: margin, y: 166, width: 42, height: 3))
      cursorY = 190

    case 18:  // Couture — vertical name echo with a machine-readable byline
      accent.setFill(); cg.fill(CGRect(x: margin, y: 26, width: 3, height: 128))
      drawVerticalLetterText(name.uppercased(), x: margin + 26, bottom: 154, length: 128, font: .systemFont(ofSize: 20, weight: .bold), color: ink)
      drawVerticalLetterText("APPLICATION", x: margin + 10, bottom: 154, length: 112, font: .systemFont(ofSize: 7.5, weight: .semibold), color: accent)
      drawText(name, x: margin + 44, y: 40, width: w - margin * 2 - 44, height: 24, font: .systemFont(ofSize: 15, weight: .semibold), color: ink)
      drawText(headline, x: margin + 44, y: 62, width: 300, height: 16, font: .systemFont(ofSize: 10, weight: .medium), color: muted)
      drawContact(alignment: .left, y: 88, x: margin + 44, width: 300)
      cursorY = 178

    case 19:  // Medallion — a monogram seal beside the name
      drawText(name, x: margin, y: 54, width: w - margin * 2 - 96, height: 60, font: .systemFont(ofSize: 28, weight: .bold), color: ink)
      drawText(headline, x: margin, y: 116, width: 320, height: 16, font: .systemFont(ofSize: 9.6, weight: .medium), color: accent)
      drawLetterMonogram(centre: CGPoint(x: w - margin - 40, y: 62), radius: 32, filled: false)
      drawContact(alignment: .left, y: 140, x: margin, width: 320)
      accent.setFill(); cg.fill(CGRect(x: margin, y: 168, width: 40, height: 3))
      cursorY = 190

    case 20:  // Sable — a dark banner
      let h: CGFloat = 150
      navy.setFill(); cg.fill(CGRect(x: 0, y: 0, width: w, height: h))
      accent.setFill(); cg.fill(CGRect(x: 0, y: h - 4, width: w, height: 4))
      drawText("APPLICATION", x: margin, y: 30, width: 200, height: 12, font: .systemFont(ofSize: 8, weight: .bold), color: accent)
      drawText(name, x: margin, y: 48, width: w - margin * 2, height: 44, font: .systemFont(ofSize: 27, weight: .bold), color: .white)
      drawText(headline.uppercased(), x: margin, y: 92, width: w - margin * 2, height: 14, font: .systemFont(ofSize: 8.4, weight: .semibold), color: accent)
      drawContact(alignment: .left, y: 118, x: margin, width: 340, color: UIColor.white.withAlphaComponent(0.8))
      cursorY = h + 30

    case 21:  // Terracotta — an earthen band and a bold profile circle
      let h: CGFloat = 176
      warm.setFill(); cg.fill(CGRect(x: 0, y: 0, width: w, height: h))
      navy.setFill(); cg.fillEllipse(in: CGRect(x: -50, y: 26, width: 128, height: 128))
      drawText(document.initials, x: -50, y: 72, width: 128, height: 40, font: .systemFont(ofSize: 26, weight: .bold), color: warm, alignment: .center)
      let tx: CGFloat = 96
      drawText("Hello, I'm", x: tx, y: 50, width: w - tx - margin, height: 24, font: serif(19, bold: false), color: navy)
      drawText(name, x: tx, y: 74, width: w - tx - margin, height: 40, font: serif(28, bold: true), color: navy)
      drawText(headline.uppercased(), x: tx, y: 118, width: w - tx - margin, height: 14, font: .systemFont(ofSize: 8, weight: .semibold), color: accent)
      drawContact(alignment: .left, y: 140, x: tx, width: 300, color: navy.withAlphaComponent(0.72))
      cursorY = h + 26

    case 22:  // Lozenge — airy with capsule contact labels
      drawText(name, x: margin, y: 44, width: w - margin * 2, height: 42, font: .systemFont(ofSize: 29, weight: .bold), color: ink)
      drawText(headline.uppercased(), x: margin, y: 88, width: w - margin * 2, height: 14, font: .systemFont(ofSize: 8.4, weight: .semibold), color: accent)
      drawLetterContactPills(x: margin, y: 110)
      accent.withAlphaComponent(0.2).setFill(); cg.fill(CGRect(x: margin, y: 148, width: w - margin * 2, height: 1.4))
      cursorY = 172

    case 23:  // Circlet — a ringed monogram with orbiting dots
      let pc = CGPoint(x: bounds.midX, y: 60)
      let orbit: CGFloat = 46
      for i in 0..<12 {
        let a = CGFloat(i) / 12 * .pi * 2 - .pi / 2
        let filled = i < 7
        (filled ? accent : accent.withAlphaComponent(0.28)).setFill()
        let d: CGFloat = filled ? 5 : 3.4
        cg.fillEllipse(in: CGRect(x: pc.x + cos(a) * orbit - d / 2, y: pc.y + sin(a) * orbit - d / 2, width: d, height: d))
      }
      drawLetterMonogram(centre: pc, radius: 27, filled: true)
      drawText(name, x: margin, y: 116, width: w - margin * 2, height: 30, font: .systemFont(ofSize: 24, weight: .bold), color: ink, alignment: .center)
      drawText(headline.uppercased(), x: margin, y: 146, width: w - margin * 2, height: 14, font: .systemFont(ofSize: 8.2, weight: .semibold), color: accent, alignment: .center)
      drawContact(alignment: .center, y: 166, x: margin, width: w - margin * 2)
      cursorY = 196

    case 24:  // Vogue — an oversized serif editorial
      ink.withAlphaComponent(0.82).setFill(); cg.fill(CGRect(x: margin, y: 30, width: w - margin * 2, height: 1))
      drawText("CORRESPONDENCE", x: margin, y: 36, width: 300, height: 12, font: .systemFont(ofSize: 7.6, weight: .semibold), color: accent)
      drawText(name, x: margin, y: 52, width: w - margin * 2, height: 60, font: serif(42, bold: true), color: ink)
      drawText(headline, x: margin, y: 120, width: w - margin * 2, height: 16, font: .systemFont(ofSize: 10, weight: .medium), color: muted)
      ink.withAlphaComponent(0.82).setFill(); cg.fill(CGRect(x: margin, y: 148, width: w - margin * 2, height: 1))
      drawContact(alignment: .left, y: 156, x: margin, width: 340)
      cursorY = 184

    case 25:  // Signet — a pressed wax seal over a centred serif
      drawLetterSeal(centre: CGPoint(x: bounds.midX, y: 44), radius: 25)
      drawText(name, x: margin, y: 82, width: w - margin * 2, height: 34, font: serif(26, bold: true), color: ink, alignment: .center)
      drawText(headline.uppercased(), x: margin, y: 116, width: w - margin * 2, height: 14, font: .systemFont(ofSize: 8.2, weight: .semibold), color: accent, alignment: .center)
      ink.withAlphaComponent(0.7).setFill(); cg.fill(CGRect(x: bounds.midX - 56, y: 138, width: 112, height: 1))
      drawContact(alignment: .center, y: 150, x: margin, width: w - margin * 2)
      cursorY = 180

    default:  // 26 Almanac — an icon-led fact strip
      drawText(name, x: margin, y: 40, width: w - margin * 2, height: 40, font: .systemFont(ofSize: 27, weight: .bold), color: ink)
      drawText(headline, x: margin, y: 79, width: w - margin * 2, height: 16, font: .systemFont(ofSize: 9.6, weight: .medium), color: accent)
      drawLetterFactStrip(y: 104)
      accent.setFill(); cg.fill(CGRect(x: margin, y: 150, width: 44, height: 3))
      cursorY = 174
    }
  }

  /// A concentric-ring monogram, filled or hollow, for the Showcase letterheads.
  private func drawLetterMonogram(centre: CGPoint, radius: CGFloat, filled: Bool) {
    let cg = context.cgContext
    let box = CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
    if filled {
      accent.setFill()
      cg.fillEllipse(in: box)
      UIColor.white.withAlphaComponent(0.9).setStroke()
      let ring = UIBezierPath(ovalIn: box.insetBy(dx: 4, dy: 4))
      ring.lineWidth = 0.8
      ring.stroke()
      drawText(document.initials, x: box.minX, y: centre.y - 9, width: radius * 2, height: 20, font: .systemFont(ofSize: radius * 0.5, weight: .bold), color: .white, alignment: .center)
    } else {
      UIColor.white.setFill()
      cg.fillEllipse(in: box)
      accent.setStroke()
      let outer = UIBezierPath(ovalIn: box)
      outer.lineWidth = 1.4
      outer.stroke()
      accent.withAlphaComponent(0.5).setStroke()
      let inner = UIBezierPath(ovalIn: box.insetBy(dx: 5, dy: 5))
      inner.lineWidth = 0.6
      inner.stroke()
      drawText(document.initials, x: box.minX, y: centre.y - 9, width: radius * 2, height: 20, font: .systemFont(ofSize: radius * 0.5, weight: .bold), color: accent, alignment: .center)
      accent.setFill()
      cg.fillEllipse(in: CGRect(x: centre.x - 2, y: centre.y - radius - 2, width: 4, height: 4))
    }
  }

  /// A scalloped wax-seal monogram, for Signet.
  private func drawLetterSeal(centre: CGPoint, radius: CGFloat) {
    let cg = context.cgContext
    accent.withAlphaComponent(0.55).setFill()
    let scallops = 20
    for i in 0..<scallops {
      let a = CGFloat(i) / CGFloat(scallops) * .pi * 2
      let r = radius + 3
      cg.fillEllipse(in: CGRect(x: centre.x + cos(a) * r - 1.6, y: centre.y + sin(a) * r - 1.6, width: 3.2, height: 3.2))
    }
    accent.setFill()
    cg.fillEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
    UIColor.white.withAlphaComponent(0.9).setStroke()
    let ring = UIBezierPath(ovalIn: CGRect(x: centre.x - radius + 4, y: centre.y - radius + 4, width: (radius - 4) * 2, height: (radius - 4) * 2))
    ring.lineWidth = 0.8
    ring.stroke()
    drawText(document.initials, x: centre.x - radius, y: centre.y - 8, width: radius * 2, height: 18, font: .systemFont(ofSize: 13, weight: .bold), color: .white, alignment: .center)
  }

  /// Capsule contact labels, for Lozenge.
  private func drawLetterContactPills(x: CGFloat, y: CGFloat) {
    var cx = x
    let font = UIFont.systemFont(ofSize: 8.5, weight: .medium)
    for value in [document.senderPhone, document.senderEmail] where !value.isBlank {
      let textWidth = (value as NSString).size(withAttributes: [.font: font]).width
      let pillWidth = textWidth + 22
      let pill = UIBezierPath(roundedRect: CGRect(x: cx, y: y, width: pillWidth, height: 20), cornerRadius: 10)
      accent.withAlphaComponent(0.1).setFill()
      pill.fill()
      drawText(value, x: cx + 11, y: y + 5, width: textWidth + 4, height: 12, font: font, color: ink)
      cx += pillWidth + 8
    }
  }

  /// An icon-tile fact strip, for Almanac.
  private func drawLetterFactStrip(y: CGFloat) {
    let cg = context.cgContext
    let facts = [document.senderPhone, document.senderEmail, document.senderHeadline]
      .filter { !$0.isBlank }
    guard !facts.isEmpty else { return }
    let count = CGFloat(facts.count)
    let tileWidth = (bounds.width - margin * 2 - (count - 1) * 8) / count
    var tx = margin
    for value in facts {
      let tile = UIBezierPath(roundedRect: CGRect(x: tx, y: y, width: tileWidth, height: 32), cornerRadius: 7)
      accent.withAlphaComponent(0.08).setFill()
      tile.fill()
      accent.setFill()
      cg.fill(CGRect(x: tx + 10, y: y + 10, width: 12, height: 3))
      drawText(value, x: tx + 10, y: y + 15, width: tileWidth - 16, height: 14, font: .systemFont(ofSize: 7.2), color: ink)
      tx += tileWidth + 8
    }
  }

  /// Text rotated a quarter turn, running up the page — Couture's vertical name.
  private func drawVerticalLetterText(
    _ text: String, x: CGFloat, bottom: CGFloat, length: CGFloat, font: UIFont, color: UIColor
  ) {
    let cg = context.cgContext
    cg.saveGState()
    cg.translateBy(x: x, y: bottom)
    cg.rotate(by: -.pi / 2)
    drawText(text, x: 0, y: 0, width: length, height: font.pointSize + 4, font: font, color: color)
    cg.restoreGState()
  }

  private func drawSidebarHeader() {
    ink.setFill()
    context.cgContext.fill(CGRect(x: 0, y: 0, width: 168, height: bounds.height))

    drawText(
      document.senderName,
      x: 22,
      y: 46,
      width: 128,
      height: 62,
      font: .boldSystemFont(ofSize: 19),
      color: .white
    )
    drawText(
      document.senderHeadline,
      x: 22,
      y: 112,
      width: 128,
      height: 40,
      font: .systemFont(ofSize: 9, weight: .medium),
      color: accent
    )
    accent.setFill()
    context.cgContext.fill(CGRect(x: 22, y: 160, width: 30, height: 2))

    var rowY: CGFloat = 176
    for (icon, value) in contactDetails {
      drawIcon(icon, in: CGRect(x: 22, y: rowY + 1, width: 9, height: 9), color: accent)
      drawText(
        value,
        x: 37,
        y: rowY,
        width: 113,
        height: 30,
        font: .systemFont(ofSize: 8),
        color: UIColor.white.withAlphaComponent(0.85)
      )
      rowY += 26
    }

    // The letter moves over to clear the band.
    bodyX = 200
    bodyWidth = bounds.width - bodyX - margin
    cursorY = 56
  }

  /// Signal's contact strip: an icon beside each detail, run under the name.
  private func drawIconicHeader() {
    lightGray.setFill()
    context.cgContext.fill(CGRect(x: 0, y: 0, width: bounds.width, height: 126))
    accent.setFill()
    context.cgContext.fill(CGRect(x: 0, y: 122, width: bounds.width, height: 4))

    drawText(document.senderName, x: margin, y: 34, width: 340, font: .boldSystemFont(ofSize: 26), color: ink)
    drawText(document.senderHeadline.uppercased(), x: margin, y: 70, width: 340, font: .systemFont(ofSize: 9, weight: .semibold), color: accent)

    var cursorX = margin
    for (icon, value) in contactDetails {
      drawIcon(icon, in: CGRect(x: cursorX, y: 95, width: 9, height: 9), color: accent)
      cursorX += 14
      let attributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 8.6), .foregroundColor: muted,
      ]
      NSAttributedString(string: value, attributes: attributes).draw(at: CGPoint(x: cursorX, y: 93))
      cursorX += ceil(NSAttributedString(string: value, attributes: attributes).size().width) + 22
    }
    cursorY = 152
  }

  /// Chronicle's rail, with the letter as the first stop on it.
  private func drawRailHeader() {
    accent.withAlphaComponent(0.3).setFill()
    context.cgContext.fill(CGRect(x: margin + 5, y: 30, width: 1.5, height: 96))
    accent.setFill()
    context.cgContext.fillEllipse(in: CGRect(x: margin + 1, y: 38, width: 10, height: 10))

    let textX = margin + 26
    drawText(document.senderName, x: textX, y: 32, width: 320, font: .boldSystemFont(ofSize: 25), color: ink)
    drawText(document.senderHeadline, x: textX, y: 66, width: 320, font: .systemFont(ofSize: 10.5, weight: .medium), color: muted)
    drawContact(alignment: .right, y: 36)
    UIColor(white: 0.86, alpha: 1).setFill()
    context.cgContext.fill(CGRect(x: textX, y: 116, width: bounds.width - textX - margin, height: 0.7))
    cursorY = 146
  }

  /// Strata's card, holding the letterhead.
  private func drawCardstockHeader() {
    let card = CGRect(x: margin - 12, y: 28, width: bounds.width - (margin - 12) * 2, height: 100)
    let path = UIBezierPath(roundedRect: card, cornerRadius: 12)
    accent.withAlphaComponent(0.06).setFill()
    path.fill()
    accent.withAlphaComponent(0.3).setStroke()
    path.lineWidth = 0.8
    path.stroke()

    drawText(document.senderName, x: card.minX + 22, y: card.minY + 20, width: 300, font: .boldSystemFont(ofSize: 24), color: ink)
    drawText(document.senderHeadline.uppercased(), x: card.minX + 22, y: card.minY + 54, width: 300, font: .systemFont(ofSize: 8.6, weight: .semibold), color: accent)
    drawContact(alignment: .right, y: card.minY + 22, x: card.maxX - 172, width: 150)
    cursorY = 154
  }

  /// Gazette's rules and margin, in correspondence.
  private func drawBroadsheetHeader() {
    let width = bounds.width - margin * 2
    drawText(document.senderName, x: margin, y: 32, width: width, font: serif(27, bold: true), color: ink)
    drawText(document.senderHeadline, x: margin, y: 68, width: width, font: serif(10.5, bold: false), color: muted)
    drawContact(alignment: .right, y: 36)

    ink.setFill()
    context.cgContext.fill(CGRect(x: margin, y: 100, width: width, height: 1.2))
    ink.withAlphaComponent(0.45).setFill()
    context.cgContext.fill(CGRect(x: margin, y: 104, width: width, height: 0.5))
    cursorY = 128
  }

  private var contactDetails: [(String, String)] {
    [("phone.fill", document.senderPhone), ("envelope.fill", document.senderEmail)]
      .filter { !$0.1.isBlank }
  }

  private func drawIcon(_ name: String, in rect: CGRect, color: UIColor) {
    let configuration = UIImage.SymbolConfiguration(pointSize: rect.height, weight: .semibold)
    guard
      let symbol = UIImage(systemName: name, withConfiguration: configuration)?
        .withTintColor(color, renderingMode: .alwaysOriginal)
    else { return }
    let scale = min(rect.width / symbol.size.width, rect.height / symbol.size.height)
    let size = CGSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
    symbol.draw(
      in: CGRect(
        x: rect.midX - size.width / 2,
        y: rect.midY - size.height / 2,
        width: size.width,
        height: size.height
      ))
  }

  private func drawGradientHeader() {
    drawGradientBand(CGRect(x: 0, y: 0, width: bounds.width, height: 122), from: accent, to: ink)
    drawText(document.senderName, x: margin, y: 32, width: 330, font: .boldSystemFont(ofSize: 27), color: .white)
    drawText(document.senderHeadline.uppercased(), x: margin, y: 70, width: 330, font: .systemFont(ofSize: 9, weight: .semibold), color: UIColor.white.withAlphaComponent(0.9))
    drawContact(alignment: .right, y: 38, color: .white)
    cursorY = 152
  }

  /// The initials, set solid in the accent colour: the mark the letter is signed with.
  private func drawMonogramHeader() {
    let mark = CGRect(x: margin, y: 32, width: 64, height: 64)
    accent.setFill()
    context.cgContext.fill(mark)
    drawText(
      document.initials,
      x: mark.minX,
      y: mark.minY + 19,
      width: mark.width,
      height: 34,
      font: .boldSystemFont(ofSize: 26),
      color: .white,
      alignment: .center
    )

    let textX = mark.maxX + 20
    drawText(document.senderName, x: textX, y: 36, width: 260, font: .boldSystemFont(ofSize: 25), color: ink)
    drawText(document.senderHeadline, x: textX, y: 70, width: 260, font: .systemFont(ofSize: 10.5, weight: .medium), color: muted)
    drawContact(alignment: .right, y: 38, x: bounds.width - margin - 150, width: 150)
    UIColor(white: 0.84, alpha: 1).setFill()
    context.cgContext.fill(CGRect(x: margin, y: 114, width: bounds.width - margin * 2, height: 0.7))
    cursorY = 146
  }

  /// A ruled brief: who it is from, stated plainly, in a box.
  private func drawMemoHeader() {
    let box = CGRect(x: margin, y: 30, width: bounds.width - margin * 2, height: 84)
    UIColor(white: 0.96, alpha: 1).setFill()
    context.cgContext.fill(box)
    accent.setFill()
    context.cgContext.fill(CGRect(x: box.minX, y: box.minY, width: 6, height: box.height))

    drawText("FROM", x: box.minX + 20, y: box.minY + 14, width: 120, height: 12, font: .systemFont(ofSize: 7.5, weight: .bold), color: accent)
    drawText(document.senderName, x: box.minX + 20, y: box.minY + 28, width: 260, font: .systemFont(ofSize: 15, weight: .semibold), color: ink)
    drawText(document.senderHeadline, x: box.minX + 20, y: box.minY + 52, width: 260, height: 16, font: .systemFont(ofSize: 9.5), color: muted)

    drawText("CONTACT", x: box.maxX - 170, y: box.minY + 14, width: 150, height: 12, font: .systemFont(ofSize: 7.5, weight: .bold), color: accent, alignment: .right)
    drawContact(alignment: .right, y: box.minY + 28, x: box.maxX - 170, width: 150)
    cursorY = 142
  }

  private func drawPortfolioHeader() {
    let card = CGRect(x: margin - 10, y: 26, width: bounds.width - (margin - 10) * 2, height: 106)
    let path = UIBezierPath(roundedRect: card, cornerRadius: 16)
    accent.withAlphaComponent(0.08).setFill()
    path.fill()
    accent.withAlphaComponent(0.28).setStroke()
    path.lineWidth = 1
    path.stroke()

    // The rail, clipped to the card so it keeps the rounded corner.
    context.cgContext.saveGState()
    path.addClip()
    accent.setFill()
    context.cgContext.fill(CGRect(x: card.minX, y: card.minY, width: 9, height: card.height))
    context.cgContext.restoreGState()

    drawText(document.senderName, x: card.minX + 30, y: card.minY + 22, width: 300, font: .boldSystemFont(ofSize: 25), color: ink)
    drawText(document.senderHeadline, x: card.minX + 30, y: card.minY + 56, width: 300, font: .systemFont(ofSize: 10.5, weight: .medium), color: accent)
    drawContact(alignment: .right, y: card.minY + 24, x: card.maxX - 170, width: 150)
    cursorY = 160
  }

  /// Centred serif between a printed double rule, top and bottom.
  private func drawLetterpressHeader() {
    let width = bounds.width - margin * 2
    ink.setFill()
    context.cgContext.fill(CGRect(x: margin, y: 30, width: width, height: 1.4))
    ink.withAlphaComponent(0.5).setFill()
    context.cgContext.fill(CGRect(x: margin, y: 34, width: width, height: 0.5))

    drawText(document.senderName, x: margin, y: 46, width: width, font: serif(26, bold: true), color: ink, alignment: .center)
    drawText(document.senderHeadline, x: margin, y: 80, width: width, font: serif(10.5, bold: false), color: muted, alignment: .center)
    drawContact(alignment: .center, y: 100, x: margin, width: width)

    ink.withAlphaComponent(0.5).setFill()
    context.cgContext.fill(CGRect(x: margin, y: 128, width: width, height: 0.5))
    ink.setFill()
    context.cgContext.fill(CGRect(x: margin, y: 130, width: width, height: 1.4))
    cursorY = 156
  }

  private func drawGradientBand(_ rect: CGRect, from start: UIColor, to end: UIColor) {
    guard
      let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [start.cgColor, end.cgColor] as CFArray,
        locations: [0, 1]
      )
    else {
      start.setFill()
      context.cgContext.fill(rect)
      return
    }
    context.cgContext.saveGState()
    context.cgContext.clip(to: rect)
    context.cgContext.drawLinearGradient(
      gradient,
      start: CGPoint(x: rect.minX, y: rect.midY),
      end: CGPoint(x: rect.maxX, y: rect.midY),
      options: []
    )
    context.cgContext.restoreGState()
  }

  private func drawContinuationHeader() {
    if let ordinal = document.template.advancedOrdinal {
      let dark = [0, 4, 6, 7, 9, 14, 20].contains(ordinal)
      (dark ? ink : accent.withAlphaComponent(0.08)).setFill()
      context.cgContext.fill(CGRect(x: 0, y: 0, width: bounds.width, height: 70))
      accent.setFill()
      context.cgContext.fill(CGRect(x: 0, y: 70, width: bounds.width, height: 3))
      drawText(
        document.senderName,
        x: margin,
        y: 25,
        width: 360,
        font: .systemFont(ofSize: 14, weight: .semibold),
        color: dark ? .white : ink
      )
      drawText(
        "Cover Letter / \(ordinal + 1)",
        x: bounds.width - margin - 140,
        y: 27,
        width: 140,
        font: .systemFont(ofSize: 8.5, weight: .medium),
        color: dark ? accent : muted,
        alignment: .right
      )
      cursorY = 96
      return
    }

    if document.template == .vantage {
      ink.setFill()
      context.cgContext.fill(CGRect(x: 0, y: 0, width: bounds.width, height: 70))
      drawText(
        document.senderName,
        x: margin,
        y: 25,
        width: 360,
        font: .systemFont(ofSize: 14, weight: .semibold),
        color: .white
      )
      drawText(
        "Cover Letter",
        x: bounds.width - margin - 120,
        y: 27,
        width: 120,
        font: .systemFont(ofSize: 9, weight: .medium),
        color: accent,
        alignment: .right
      )
      accent.setFill()
      context.cgContext.fill(CGRect(x: 0, y: 70, width: bounds.width, height: 3))
      cursorY = 96
      return
    }

    if document.template == .eclipse {
      accent.setFill()
      context.cgContext.fillEllipse(
        in: CGRect(x: bounds.width - 62, y: -33, width: 92, height: 92))
    }
    drawText(document.senderName, x: bodyX, y: 31, width: 360, font: .systemFont(ofSize: 14, weight: .semibold), color: inkColor)
    drawText("Cover Letter", x: bounds.width - margin - 120, y: 33, width: 120, font: .systemFont(ofSize: 9, weight: .medium), color: mutedColor, alignment: .right)
    accent.setFill()
    context.cgContext.fill(CGRect(x: bodyX, y: 58, width: bodyWidth, height: 1.5))
    cursorY = 85
  }

  private func drawLetterDetails() {
    let dateText = document.date.formatted(.dateTime.day().month(.wide).year())
    drawFlowingText(dateText, font: .systemFont(ofSize: 10), color: mutedColor, spacingAfter: 20)

    let recipient = [
      document.recipientName,
      document.recipientTitle,
      document.companyName,
      document.companyAddress,
    ].filter { !$0.isBlank }.joined(separator: "\n")
    if !recipient.isEmpty {
      drawFlowingText(recipient, font: .systemFont(ofSize: 10.5), color: inkColor, lineHeight: 15, spacingAfter: 20)
    }

    let subject = document.subject.nilIfBlank ?? document.jobTitle.nilIfBlank.map { "Application for \($0)" }
    if let subject {
      // The accent is drawn for white paper; on the dark sheet the subject is
      // set in the ink instead, which reads where a dim accent would not.
      drawFlowingText(subject, font: .systemFont(ofSize: 11, weight: .bold), color: darkPaper ? .white : accent, spacingAfter: 20)
    }
    drawFlowingText(document.greeting.nilIfBlank ?? "Dear Hiring Manager,", font: .systemFont(ofSize: 10.5), color: inkColor, spacingAfter: 16)
  }

  private func drawBody() {
    for paragraph in document.bodyParagraphs where !paragraph.isBlank {
      drawFlowingText(paragraph, font: bodyFont, color: inkColor, lineHeight: 17, spacingAfter: 14)
    }
    drawFlowingText(document.closing.nilIfBlank ?? "Kind regards,", font: bodyFont, color: inkColor, spacingAfter: 24)
    drawFlowingText(document.senderName, font: .systemFont(ofSize: 11, weight: .semibold), color: inkColor, spacingAfter: 0)
  }

  private var bodyFont: UIFont {
    switch document.template {
    case .classic, .signature, .letterpress, .ivy, .aurelia, .nocturne, .sovereign, .halo:
      serif(10.8, bold: false)
    default: .systemFont(ofSize: 10.5)
    }
  }

  private func drawFlowingText(
    _ text: String,
    font: UIFont,
    color: UIColor,
    lineHeight: CGFloat? = nil,
    spacingAfter: CGFloat
  ) {
    let width = bodyWidth
    let style = NSMutableParagraphStyle()
    style.minimumLineHeight = lineHeight ?? font.lineHeight
    style.maximumLineHeight = lineHeight ?? font.lineHeight
    let attributed = NSAttributedString(
      string: text,
      attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style]
    )
    let height = ceil(
      attributed.boundingRect(
        with: CGSize(width: width, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        context: nil
      ).height
    )
    if cursorY + height > footerY - 22 {
      beginPage(first: false)
    }
    attributed.draw(
      with: CGRect(x: bodyX, y: cursorY, width: width, height: height + 2),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      context: nil
    )
    cursorY += height + spacingAfter
  }

  private func drawContact(
    alignment: NSTextAlignment,
    y: CGFloat,
    x: CGFloat? = nil,
    width: CGFloat? = nil,
    color: UIColor = UIColor(red: 0.38, green: 0.40, blue: 0.44, alpha: 1)
  ) {
    let contact = [document.senderPhone, document.senderEmail]
      .filter { !$0.isBlank }
      .joined(separator: "\n")
    drawText(
      contact,
      x: x ?? bounds.width - margin - 190,
      y: y,
      width: width ?? 190,
      height: 38,
      font: .systemFont(ofSize: 9),
      color: color,
      alignment: alignment
    )
  }

  private func drawFooter() {
    // Plinth's whole idea: the contact strip lives in a colour band along the
    // foot of every page.
    if document.template == .plinth {
      accent.setFill()
      context.cgContext.fill(CGRect(x: 0, y: 812, width: bounds.width, height: bounds.height - 812))
      let contact = [document.senderPhone, document.senderEmail]
        .filter { !$0.isBlank }
        .joined(separator: "   |   ")
      drawText(contact, x: margin, y: 821, width: 400, height: 14, font: .systemFont(ofSize: 8.5, weight: .medium), color: .white)
      drawText("\(page)", x: bounds.width - margin - 30, y: 821, width: 30, height: 14, font: .systemFont(ofSize: 8), color: .white, alignment: .right)
      return
    }
    drawText("\(page)", x: bounds.width - margin - 30, y: 817, width: 30, font: .systemFont(ofSize: 8), color: mutedColor, alignment: .right)
  }

  private func drawText(
    _ text: String,
    x: CGFloat,
    y: CGFloat,
    width: CGFloat,
    height: CGFloat = 42,
    font: UIFont,
    color: UIColor,
    alignment: NSTextAlignment = .left
  ) {
    let style = NSMutableParagraphStyle()
    style.alignment = alignment
    NSAttributedString(
      string: text,
      attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style]
    ).draw(
      with: CGRect(x: x, y: y, width: width, height: height),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      context: nil
    )
  }

  private func serif(_ size: CGFloat, bold: Bool) -> UIFont {
    let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
      .withDesign(.serif)?
      .withSymbolicTraits(bold ? .traitBold : [])
    return descriptor.map { UIFont(descriptor: $0, size: size) } ?? .systemFont(ofSize: size)
  }
}
