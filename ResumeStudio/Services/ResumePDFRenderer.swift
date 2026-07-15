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
    let a4Data = renderer.pdfData { rendererContext in
      let layout = ResumePDFLayout(
        rendererContext: rendererContext,
        pageBounds: pageBounds,
        document: document
      )
      layout.render()
    }
    guard document.layout.paperSize == .letter else { return a4Data }
    return try convert(a4Data, to: CGRect(x: 0, y: 0, width: 612, height: 792))
  }

  private static func convert(_ data: Data, to targetBounds: CGRect) throws -> Data {
    guard let provider = CGDataProvider(data: data as CFData),
      let source = CGPDFDocument(provider)
    else { throw CocoaError(.fileReadCorruptFile) }
    let output = NSMutableData()
    guard let consumer = CGDataConsumer(data: output as CFMutableData) else {
      throw CocoaError(.fileWriteUnknown)
    }
    var mediaBox = targetBounds
    guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
      throw CocoaError(.fileWriteUnknown)
    }
    for index in 1...source.numberOfPages {
      guard let page = source.page(at: index) else { continue }
      let sourceBounds = page.getBoxRect(.mediaBox)
      let scale = min(targetBounds.width / sourceBounds.width, targetBounds.height / sourceBounds.height)
      let x = (targetBounds.width - sourceBounds.width * scale) / 2
      let y = (targetBounds.height - sourceBounds.height * scale) / 2
      context.beginPDFPage(nil)
      context.saveGState()
      context.translateBy(x: x, y: y)
      context.scaleBy(x: scale, y: scale)
      context.drawPDFPage(page)
      context.restoreGState()
      context.endPDFPage()
    }
    context.closePDF()
    return output as Data
  }
}

@MainActor
private final class ResumePDFLayout {
  private let rendererContext: UIGraphicsPDFRendererContext
  private let pageBounds: CGRect
  private let document: ResumeDocument

  private var margin: CGFloat { CGFloat(document.layout.marginPoints) }
  private let footerTop: CGFloat = 810
  private var cursorY: CGFloat = 0
  private var pageNumber = 0

  /// The column the body flows down. The original catalogue runs it the full
  /// width of the page; the structural templates narrow it and put a second
  /// column alongside — see `SideColumn`.
  private var bodyX: CGFloat = 34
  private var bodyWidth: CGFloat = 527
  private var bodyMidX: CGFloat { bodyX + bodyWidth / 2 }

  /// The narrow column, and the queue of blocks waiting to go into it.
  private var sideColumn: SideColumn?
  private var sideX: CGFloat = 0
  private var sideWidth: CGFloat = 0
  private var sideBand: CGRect = .zero
  private var sideQueue: [SideBlock] = []
  private var sideY: CGFloat = 0
  private var sideOpen = false

  /// How far the timeline rail has been drawn down the current page.
  private var railY: CGFloat?

  /// Which section the page is up to, for the plans that count them off.
  private var sectionNumber = 0

  /// The margin Terrace hangs its section titles in, to the left of the text.
  private let headingGutter: CGFloat = 116

  /// Where the letterhead actually finished.
  ///
  /// Most letterheads are a fixed height, and `firstPageTop` simply states it.
  /// The art-led ones grow with what they are given — a name that wraps to two
  /// lines, a summary printed inside the masthead — so they measure themselves as
  /// they draw and leave the answer here. `beginPage` asks for the header before
  /// it asks where the body starts, so by then this is set.
  private var measuredHeaderBottom: CGFloat?

  private struct SideBlock {
    let height: CGFloat
    let draw: (CGFloat) -> Void
  }

  private var plan: TemplatePlan { template.plan }

  private let navy = UIColor(red: 0.17, green: 0.20, blue: 0.29, alpha: 1)
  private let charcoal = UIColor(red: 0.09, green: 0.10, blue: 0.12, alpha: 1)
  private let gray = UIColor(red: 0.36, green: 0.38, blue: 0.41, alpha: 1)
  private let lightGray = UIColor(red: 0.94, green: 0.95, blue: 0.96, alpha: 1)
  private let ruleGray = UIColor(red: 0.76, green: 0.78, blue: 0.81, alpha: 1)

  /// The body's ink, resolved against the paper. The white-paper templates read
  /// exactly as they always did; the dark-paper ones swap every body colour at
  /// this one seam rather than at a hundred call sites.
  private var paper: UIColor {
    plan.darkPaper ? UIColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1) : .white
  }
  private var ink: UIColor { plan.darkPaper ? UIColor(white: 0.92, alpha: 1) : charcoal }
  private var headingInk: UIColor { plan.darkPaper ? .white : navy }
  private var mutedInk: UIColor { plan.darkPaper ? UIColor(white: 0.64, alpha: 1) : gray }
  private var faintFill: UIColor { plan.darkPaper ? UIColor(white: 1, alpha: 0.10) : lightGray }
  private var hairlineInk: UIColor { plan.darkPaper ? UIColor(white: 1, alpha: 0.24) : ruleGray }

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
    bodyX = CGFloat(document.layout.marginPoints)
    bodyWidth = pageBounds.width - CGFloat(document.layout.marginPoints * 2)
  }

  func render() {
    if case .side(let column) = plan.body {
      renderWithSideColumn(column)
    } else {
      narrowBodyColumn()
      beginPage(isFirst: true)
      renderMainSections()
    }
  }

  /// The one-column templates that still give up part of the page: the spine runs
  /// down the left of every sheet, the hanging headings claim a margin of their
  /// own. Both simply move the column over — the flow beneath is unchanged.
  private func narrowBodyColumn() {
    let inset = plan.bodyInset + (plan.hangingHeadings ? headingGutter + 22 : 0)
    guard inset > 0 else { return }
    bodyX = margin + inset
    bodyWidth = pageBounds.width - bodyX - margin
  }

  private func renderMainSections() {
    // Vantage sets the summary inside its hero panel, so the body opens on the
    // skills instead of printing it twice.
    let summaryIsInTheHeader = plan.profileInHeader && heroCarriesProfile

    var order = document.layout.sectionOrder
    if order.isEmpty { order = ResumeContentBlock.allCases }
    if plan.skillsFirst, order == ResumeContentBlock.allCases,
      let profile = order.firstIndex(of: .profile),
      let skills = order.firstIndex(of: .competencies)
    {
      order.swapAt(profile, skills)
    }
    for block in order {
      switch block {
      case .profile:
        if !summaryIsInTheHeader { drawProfessionalProfile() }
      case .competencies: drawCompetencies()
      case .experience: drawExperience()
      case .education: drawEducation()
      case .additional: drawAdditionalSections()
      case .references: drawReferences()
      }
    }
  }

  /// The two-column templates.
  ///
  /// The narrow column is a queue of measured blocks, drained into whatever room
  /// each page leaves it; the wide column flows as it always has. Building it this
  /// way — rather than laying the page out twice — means the narrow column simply
  /// continues onto the next page when it runs out of room, instead of silently
  /// losing whatever did not fit.
  private func renderWithSideColumn(_ column: SideColumn) {
    configureColumns(column)
    buildSideBlocks(column)

    if column.startsBelowProfile {
      // The summary runs the full width of the page; the split opens beneath it.
      beginPage(isFirst: true)
      let mainX = bodyX
      let mainWidth = bodyWidth
      bodyX = margin
      bodyWidth = contentWidth
      drawProfessionalProfile()
      bodyX = mainX
      bodyWidth = mainWidth

      sideOpen = true
      sideY = cursorY
      drainSideColumn()
    } else {
      sideOpen = true
      beginPage(isFirst: true)
      drawProfessionalProfile()
    }

    // Skills, education and the extras live in the narrow column, so the wide one
    // carries the summary, the roles and the references.
    drawExperience()
    drawReferences()

    // Whatever the narrow column could not fit gets pages of its own rather than
    // being dropped.
    var continuationPageCount = 0
    while !sideQueue.isEmpty, continuationPageCount < 50 {
      let countBeforePage = sideQueue.count
      beginPage(isFirst: false)
      continuationPageCount += 1
      // A malformed import can contain a single enormous unbroken sidebar item.
      // Never let it turn PDF generation into an infinite page loop.
      if sideQueue.count == countBeforePage {
        sideQueue.removeFirst()
      }
    }
  }

  private func beginPage(isFirst: Bool) {
    rendererContext.beginPage()
    pageNumber += 1

    paper.setFill()
    rendererContext.cgContext.fill(pageBounds)
    drawSideBand()
    drawPageFurniture()

    if isFirst {
      drawPrimaryHeader()
      cursorY = firstPageTop + portraitLift
    } else {
      drawContinuationHeader()
      cursorY = continuationTop
    }

    drawFooter()

    // The rail restarts at the top of the column on a new page.
    if railY != nil {
      railY = cursorY
    }
    if sideOpen, !(pageNumber == 1 && sideColumn?.startsBelowProfile == true) {
      sideY = isFirst ? sideFirstPageTop : continuationTop
      drainSideColumn()
    }
  }

  /// Where the body starts on page one. The stacked-portrait templates push it
  /// further down by `portraitLift` — see `drawPrimaryHeader`.
  private var firstPageTop: CGFloat {
    if let style = template.advancedStyle {
      return measuredHeaderBottom ?? style.headerHeight + 24
    }
    return switch template {
    case .atlas: 118
    case .verso: 120
    case .oxford: 124
    case .chronicle: 148
    case .gazette: 142
    case .strata: 146
    case .duo: 140
    case .signal: 152
    case .concise: 100
    case .pivot: 140
    case .portrait: 172
    case .spotlight: 222
    case .beacon: 172
    case .harbor: 236
    case .bloom: 190
    case .atelier: 214
    case .canvas: 186
    case .modern: 145
    case .aurora: 158
    case .slate: 150
    case .onyx: 172
    case .minimal: 132
    case .lumen: 146
    case .nordic: 138
    case .cascade: 156
    case .contemporary: 148
    case .horizon: 148
    case .vector: 150
    case .technical: 146
    case .creative: 152
    case .mosaic: 150
    case .vertex: 152
    case .timeline: 148
    case .compact: 122
    case .corporate: 153
    case .meridian: 150
    case .classic: 137
    case .elegant: 143
    case .linen: 150
    case .ledger: 148
    case .quill: 146
    case .academic: 143
    case .monochrome: 138
    case .editorial: 150
    case .noir: 152
    case .gauge: 118
    case .folio: 152
    case .insignia: 138
    case .marquee: 178
    case .metro: 150
    case .ivy: 126
    case .crest: 156
    case .geneva: 128
    case .plinth: 134
    case .stockholm: 132
    case .tandem: 126
    case .varsity: 104
    case .laureate: 128
    case .modena: 136
    case .nova: 152
    case .prism: 122
    case .aurelia: 132
    case .nocturne: 136
    case .monarch: 178
    // The art-led five measure their own letterhead as they draw it.
    case .eclipse, .contour, .axis, .terrace, .vantage:
      measuredHeaderBottom ?? 160
    default:
      measuredHeaderBottom ?? 166
    }
  }

  private var continuationTop: CGFloat {
    if template.advancedStyle != nil { return 92 }
    return switch template {
    case .portrait, .modern, .horizon, .corporate, .creative, .aurora, .slate, .onyx, .beacon,
      .vertex, .mosaic, .pivot, .noir, .metro, .crest, .marquee, .nova, .monarch, .vantage:
      96
    case .contemporary, .technical, .timeline, .vector:
      92
    case .compact, .concise:
      82
    case .spotlight, .atelier, .canvas, .harbor, .bloom, .classic, .minimal, .elegant, .editorial,
      .nordic, .academic, .monochrome, .meridian, .linen, .ledger, .quill, .lumen, .cascade,
      .atlas, .verso, .oxford, .chronicle, .gazette, .strata, .duo, .signal, .gauge, .folio,
      .insignia, .ivy, .geneva, .plinth, .stockholm, .tandem, .varsity, .laureate, .modena,
      .prism, .aurelia, .nocturne, .eclipse, .contour, .axis, .terrace:
      88
    default:
      92
    }
  }

  /// Where the narrow column starts on page one. The filled bands begin near the
  /// top of the page — the portrait belongs at the head of the column, not level
  /// with the body text.
  private var sideFirstPageTop: CGFloat {
    if template.advancedStyle != nil, let column = sideColumn, column.fill != .none {
      return 40
    }
    return switch template {
    case .atlas, .verso, .oxford, .gauge, .prism: 40
    default: firstPageTop
    }
  }

  // MARK: - The narrow column

  private func configureColumns(_ column: SideColumn) {
    sideColumn = column
    let padding: CGFloat = column.fill == .none ? 0 : 18
    let gutter: CGFloat = column.fill == .none ? 26 : 22

    switch column.edge {
    case .leading:
      sideBand = CGRect(x: 0, y: 0, width: column.width, height: pageBounds.height)
      // An unfilled leading column is simply the left of the page, so it keeps
      // the page margin; the painted bands run to the edge and pad inward.
      sideX = column.fill == .none ? margin : padding
      bodyX = (column.fill == .none ? margin : 0) + column.width + gutter
      bodyWidth = pageBounds.width - bodyX - margin
    case .trailing:
      let bandX = pageBounds.width - column.width
      sideBand = CGRect(x: bandX, y: 0, width: column.width, height: pageBounds.height)
      sideX = column.fill == .none ? pageBounds.width - margin - column.width : bandX + padding
      bodyX = margin
      bodyWidth = sideX - margin - gutter
    }
    sideWidth = column.fill == .none ? column.width : column.width - padding * 2
  }

  private func drawSideBand() {
    guard let column = sideColumn else { return }
    if column.divider, column.fill == .none {
      // The Swiss rule: a hairline down the seam instead of a painted band.
      hairlineInk.setFill()
      let seamX = column.edge == .leading ? bodyX - 14 : bodyX + bodyWidth + 14
      let seamTop = pageNumber <= 1 ? firstPageTop : continuationTop
      rendererContext.cgContext.fill(
        CGRect(x: seamX, y: seamTop, width: 0.7, height: footerTop - seamTop - 4))
    }
    let fill: UIColor? =
      switch column.fill {
      case .dark: navy
      case .accent: accent
      case .tint: lightGray
      case .none: nil
      }
    guard let fill else { return }
    fill.setFill()
    rendererContext.cgContext.fill(sideBand)
  }

  /// White type on the colour bands, ink on the quiet ones.
  private var sideInk: UIColor {
    sideColumn?.prefersLightInk == true ? .white : charcoal
  }

  private var sideMutedInk: UIColor {
    sideColumn?.prefersLightInk == true ? UIColor.white.withAlphaComponent(0.72) : gray
  }

  /// The accent has to give way on an accent-coloured band, or it disappears
  /// into it.
  private var sideAccent: UIColor {
    sideColumn?.fill == .accent ? .white : accent
  }

  private func drainSideColumn() {
    guard sideOpen else { return }
    while let block = sideQueue.first, sideY + block.height <= footerTop - 8 {
      block.draw(sideY)
      sideY += block.height
      sideQueue.removeFirst()
    }
  }

  /// Everything a recruiter scans for — contact, skills, education, references —
  /// measured up front so each block can be placed on whichever page has room.
  private func buildSideBlocks(_ column: SideColumn) {
    // Legacy split templates place the portrait at the head of their painted
    // column. Advanced templates already draw it in their masthead, so adding
    // another here would duplicate the same photo in the sidebar.
    let mastheadAlreadyOwnsPortrait = template.advancedStyle != nil
    if showsPortrait, column.fill != .none, !mastheadAlreadyOwnsPortrait {
      let diameter = min(sideWidth, 104)
      sideQueue.append(
        SideBlock(height: diameter + 22) { y in
          self.drawPortrait(
            in: CGRect(
              x: self.sideX + (self.sideWidth - diameter) / 2,
              y: y,
              width: diameter,
              height: diameter
            ),
            ring: self.sideColumn?.fill == .accent ? .white : self.accent,
            ringWidth: 3,
            emptyFill: UIColor.white.withAlphaComponent(0.16),
            emptyText: .white
          )
        })
    }

    if plan.contact == .iconRows {
      let details = [
        ("phone.fill", document.personal.phone),
        ("envelope.fill", document.personal.email),
      ].filter { !$0.1.isBlank }

      if !details.isEmpty {
        appendSideSection("Contact") { y in
          var rowY = y
          for (icon, value) in details {
            rowY += self.drawIconRow(icon, value, x: self.sideX, y: rowY, width: self.sideWidth)
          }
          return rowY - y
        } measure: {
          details.reduce(0) { total, detail in
            total
              + self.measuredHeight(
                detail.1, width: self.sideWidth - 15, font: self.regularFont(8), lineHeight: 10.5)
              + 7
          }
        }
      }
    }

    let competencies = document.competencies.filter { !$0.isBlank }
    if !competencies.isEmpty {
      appendSideSection(plan.competencies == .bullets ? "Core Competencies" : "Skills") { y in
        switch self.plan.competencies {
        case .chips:
          return self.drawChips(
            competencies, x: self.sideX, y: y, width: self.sideWidth, onBand: true)
        case .meters:
          var rowY = y
          for (index, item) in competencies.enumerated() {
            rowY +=
              self.drawMeter(
                item, index: index, x: self.sideX, y: rowY, width: self.sideWidth,
                ink: self.sideInk, track: self.sideMeterTrack, fill: self.sideAccent) + 7
          }
          return rowY - y
        case .dots:
          var rowY = y
          for (index, item) in competencies.enumerated() {
            let height = self.measuredHeight(
              item, width: self.sideWidth, font: self.regularFont(8.2), lineHeight: 10.6)
            self.drawText(
              item,
              rect: CGRect(x: self.sideX, y: rowY, width: self.sideWidth, height: height),
              font: self.regularFont(8.2), color: self.sideInk, lineHeight: 10.6)
            let dots = 5
            let dotDiameter: CGFloat = 5
            let dotGap: CGFloat = 3.5
            let filled = max(1, min(dots, Int((self.meterLevel(index) * CGFloat(dots)).rounded())))
            for dot in 0..<dots {
              (dot < filled ? self.sideAccent : self.sideMeterTrack).setFill()
              self.rendererContext.cgContext.fillEllipse(
                in: CGRect(
                  x: self.sideX + CGFloat(dot) * (dotDiameter + dotGap), y: rowY + height + 2,
                  width: dotDiameter, height: dotDiameter))
            }
            rowY += height + dotDiameter + 8
          }
          return rowY - y
        case .bullets, .iconGrid, .columns:
          var rowY = y
          for item in competencies {
            let height = self.measuredHeight(
              item, width: self.sideWidth - 11, font: self.regularFont(8.2), lineHeight: 10.6)
            self.drawText(
              item,
              rect: CGRect(x: self.sideX + 11, y: rowY, width: self.sideWidth - 11, height: height),
              font: self.regularFont(8.2),
              color: self.sideInk,
              lineHeight: 10.6
            )
            self.sideAccent.setFill()
            self.rendererContext.cgContext.fillEllipse(
              in: CGRect(x: self.sideX + 1, y: rowY + 3.4, width: 3.2, height: 3.2))
            rowY += height + 4
          }
          return rowY - y
        }
      } measure: {
        return switch self.plan.competencies {
        case .chips:
          self.chipsHeight(competencies, width: self.sideWidth)
        case .meters:
          competencies.reduce(0) { $0 + self.meterHeight($1, width: self.sideWidth) + 7 }
        case .dots:
          competencies.reduce(0) {
            $0
              + self.measuredHeight(
                $1, width: self.sideWidth, font: self.regularFont(8.2), lineHeight: 10.6) + 13
          }
        case .bullets, .iconGrid, .columns:
          competencies.reduce(0) {
            $0
              + self.measuredHeight(
                $1, width: self.sideWidth - 11, font: self.regularFont(8.2), lineHeight: 10.6) + 4
          }
        }
      }
    }

    let education = document.education.filter { !$0.qualification.isBlank || !$0.institution.isBlank }
    if !education.isEmpty {
      appendSideSection("Education") { y in
        var rowY = y
        for entry in education {
          rowY += self.drawSideEducation(entry, y: rowY)
        }
        return rowY - y
      } measure: {
        education.reduce(0) { $0 + self.sideEducationHeight($1) }
      }
    }

    for section in document.additionalSections {
      let items = section.items.filter { !$0.isBlank }
      guard !section.title.isBlank, !items.isEmpty else { continue }
      appendSideSection(section.title) { y in
        var rowY = y
        for item in items {
          let height = self.measuredHeight(
            item, width: self.sideWidth - 11, font: self.regularFont(8), lineHeight: 10.4)
          self.drawText(
            item,
            rect: CGRect(x: self.sideX + 11, y: rowY, width: self.sideWidth - 11, height: height),
            font: self.regularFont(8),
            color: self.sideInk,
            lineHeight: 10.4
          )
          self.sideAccent.setFill()
          self.rendererContext.cgContext.fill(
            CGRect(x: self.sideX + 1, y: rowY + 4, width: 5, height: 1.2))
          rowY += height + 4
        }
        return rowY - y
      } measure: {
        items.reduce(0) {
          $0
            + self.measuredHeight(
              $1, width: self.sideWidth - 11, font: self.regularFont(8), lineHeight: 10.4) + 4
        }
      }
    }

    // References stay in the wide column. They are the one thing here that does
    // not fit the narrow one — the column fills up, they spill onto a second page
    // of their own, and the page they land on has nothing beside them.
  }

  /// A titled block for the narrow column. The title travels with the first of
  /// its content, so a heading is never stranded at the foot of a page.
  private func appendSideSection(
    _ title: String,
    draw: @escaping (CGFloat) -> CGFloat,
    measure: @escaping () -> CGFloat
  ) {
    let titleHeight: CGFloat = 24
    let naturalHeight = titleHeight + measure() + 14
    let maximumPageHeight = footerTop - continuationTop - 8
    let blockHeight = min(naturalHeight, maximumPageHeight)
    sideQueue.append(
      SideBlock(height: blockHeight) { y in
        if naturalHeight > maximumPageHeight {
          // Preserve all text from unusually large imported sections while
          // guaranteeing forward progress. Normal résumé sections never enter
          // this branch; it is a safety net for malformed, unbroken source text.
          let scale = maximumPageHeight / naturalHeight
          self.rendererContext.cgContext.saveGState()
          self.rendererContext.cgContext.translateBy(x: 0, y: y)
          self.rendererContext.cgContext.scaleBy(x: 1, y: scale)
          self.rendererContext.cgContext.translateBy(x: 0, y: -y)
          self.drawSideTitle(title, y: y)
          _ = draw(y + titleHeight)
          self.rendererContext.cgContext.restoreGState()
        } else {
          self.drawSideTitle(title, y: y)
          _ = draw(y + titleHeight)
        }
      })
  }

  private func drawSideTitle(_ title: String, y: CGFloat) {
    drawText(
      title.uppercased(),
      rect: CGRect(x: sideX, y: y, width: sideWidth, height: 14),
      font: boldFont(8.6),
      color: sideInk,
      lineHeight: 11,
      kern: 0.8
    )
    sideAccent.setFill()
    rendererContext.cgContext.fill(CGRect(x: sideX, y: y + 15, width: 26, height: 2))
  }

  private func drawIconRow(_ icon: String, _ text: String, x: CGFloat, y: CGFloat, width: CGFloat)
    -> CGFloat
  {
    let height = measuredHeight(text, width: width - 15, font: regularFont(8), lineHeight: 10.5)
    drawIcon(icon, in: CGRect(x: x, y: y + 0.5, width: 9, height: 9), color: sideAccent)
    drawText(
      text,
      rect: CGRect(x: x + 15, y: y, width: width - 15, height: height),
      font: regularFont(8),
      color: sideInk,
      lineHeight: 10.5
    )
    return height + 7
  }

  private func sideEducationHeight(_ entry: EducationEntry) -> CGFloat {
    let qualification = measuredHeight(
      entry.qualification, width: sideWidth, font: boldFont(8.4), lineHeight: 10.8)
    let institution = measuredHeight(
      entry.institution, width: sideWidth, font: regularFont(8), lineHeight: 10.4)
    return qualification + institution + (entry.period.isBlank ? 0 : 11) + 10
  }

  private func drawSideEducation(_ entry: EducationEntry, y: CGFloat) -> CGFloat {
    var rowY = y
    let qualification = measuredHeight(
      entry.qualification, width: sideWidth, font: boldFont(8.4), lineHeight: 10.8)
    drawText(
      entry.qualification,
      rect: CGRect(x: sideX, y: rowY, width: sideWidth, height: qualification),
      font: boldFont(8.4),
      color: sideInk,
      lineHeight: 10.8
    )
    rowY += qualification + 1

    let institution = measuredHeight(
      entry.institution, width: sideWidth, font: regularFont(8), lineHeight: 10.4)
    drawText(
      entry.institution,
      rect: CGRect(x: sideX, y: rowY, width: sideWidth, height: institution),
      font: regularFont(8),
      color: sideMutedInk,
      lineHeight: 10.4
    )
    rowY += institution

    if !entry.period.isBlank {
      drawText(
        entry.period,
        rect: CGRect(x: sideX, y: rowY, width: sideWidth, height: 11),
        font: mediumFont(7.6),
        color: sideAccent,
        lineHeight: 10
      )
      rowY += 11
    }
    return rowY - y + 10
  }

  // MARK: - Chips, icons and grids

  private func chipsHeight(_ items: [String], width: CGFloat) -> CGFloat {
    layoutChips(items, x: 0, y: 0, width: width, draw: false)
  }

  @discardableResult
  private func drawChips(
    _ items: [String], x: CGFloat, y: CGFloat, width: CGFloat, onBand: Bool = false
  ) -> CGFloat {
    layoutChips(items, x: x, y: y, width: width, draw: true, onBand: onBand)
  }

  /// Pills that wrap. Measuring and drawing share this so the space reserved is
  /// exactly the space used.
  private func layoutChips(
    _ items: [String],
    x: CGFloat,
    y: CGFloat,
    width: CGFloat,
    draw: Bool,
    onBand: Bool = false
  ) -> CGFloat {
    let font = mediumFont(7.6)
    let height: CGFloat = 15
    let gap: CGFloat = 4
    var cursor = CGPoint(x: x, y: y)

    for item in items {
      let attributes = textAttributes(font: font, color: .black, lineHeight: 10)
      let chipWidth = min(singleLineWidth(item, attributes: attributes) + 16, width)
      if cursor.x + chipWidth > x + width, cursor.x > x {
        cursor = CGPoint(x: x, y: cursor.y + height + gap)
      }

      if draw {
        let rect = CGRect(x: cursor.x, y: cursor.y, width: chipWidth, height: height)
        let pill = UIBezierPath(roundedRect: rect, cornerRadius: height / 2)
        if onBand, sideColumn?.prefersLightInk == true {
          UIColor.white.withAlphaComponent(0.16).setFill()
          pill.fill()
          UIColor.white.withAlphaComponent(0.4).setStroke()
        } else {
          accent.withAlphaComponent(0.1).setFill()
          pill.fill()
          accent.withAlphaComponent(0.55).setStroke()
        }
        pill.lineWidth = 0.7
        pill.stroke()
        drawText(
          item,
          rect: CGRect(x: rect.minX, y: rect.minY + 3, width: rect.width, height: 11),
          font: font,
          color: onBand && sideColumn?.prefersLightInk == true ? .white : ink,
          lineHeight: 10,
          alignment: .center
        )
      }
      cursor.x += chipWidth + gap
    }
    return cursor.y + height - y
  }

  /// The ranked bar under a skill. The level comes from the position in the
  /// list — the order chosen in the editor is the ranking — so the bars claim
  /// nothing the person didn't put there themselves.
  private func meterLevel(_ index: Int) -> CGFloat {
    max(0.55, 0.94 - CGFloat(index) * 0.055)
  }

  private func meterHeight(_ item: String, width: CGFloat) -> CGFloat {
    measuredHeight(item, width: width, font: regularFont(8.2), lineHeight: 10.6) + 6
  }

  @discardableResult
  private func drawMeter(
    _ item: String,
    index: Int,
    x: CGFloat,
    y: CGFloat,
    width: CGFloat,
    ink textInk: UIColor,
    track: UIColor,
    fill: UIColor
  ) -> CGFloat {
    let height = measuredHeight(item, width: width, font: regularFont(8.2), lineHeight: 10.6)
    drawText(
      item,
      rect: CGRect(x: x, y: y, width: width, height: height),
      font: regularFont(8.2),
      color: textInk,
      lineHeight: 10.6
    )
    let barY = y + height + 3
    track.setFill()
    rendererContext.cgContext.fill(CGRect(x: x, y: barY, width: width, height: 3))
    fill.setFill()
    rendererContext.cgContext.fill(
      CGRect(x: x, y: barY, width: width * meterLevel(index), height: 3))
    return height + 6
  }

  /// The meter's empty length, resolved against whatever it is drawn on.
  private var sideMeterTrack: UIColor {
    sideColumn?.prefersLightInk == true
      ? UIColor.white.withAlphaComponent(0.22)
      : accent.withAlphaComponent(0.16)
  }

  /// SF Symbols, drawn as images. The type around them stays real text, so the
  /// page is still searchable and still selectable.
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

  /// The contact strip: an icon beside each detail, run across the letterhead.
  private func drawContactStrip(x: CGFloat, y: CGFloat, color: UIColor, iconColor: UIColor) {
    var cursorX = x
    for (icon, value) in [
      ("phone.fill", document.personal.phone),
      ("envelope.fill", document.personal.email),
    ] where !value.isBlank {
      drawIcon(icon, in: CGRect(x: cursorX, y: y + 0.5, width: 9, height: 9), color: iconColor)
      cursorX += 14
      let attributes = textAttributes(font: regularFont(8.4), color: color, lineHeight: 11)
      NSAttributedString(string: value, attributes: attributes).draw(at: CGPoint(x: cursorX, y: y))
      cursorX += singleLineWidth(value, attributes: attributes) + 22
    }
  }

  /// Decoration that belongs to the page rather than the letterhead: it repeats
  /// on every page and sits behind everything else.
  private func drawPageFurniture() {
    if let style = template.advancedStyle {
      drawAdvancedPageFurniture(style)
    }
    switch template {
    case .axis:
      // The spine: a full-height band with the job title set up it, so every page
      // is unmistakably one document. The body clears it by `plan.bodyInset`.
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: 56, height: pageBounds.height))

      let headline = document.personal.headline.trimmingCharacters(in: .whitespacesAndNewlines)
      if !headline.isEmpty {
        drawVerticalText(
          headline.uppercased(),
          x: 21,
          bottom: 776,
          length: 714,
          font: mediumFont(8.6),
          color: UIColor.white.withAlphaComponent(0.92),
          lineHeight: 11,
          kern: 2.6
        )
      }
      UIColor.white.withAlphaComponent(0.55).setFill()
      rendererContext.cgContext.fill(CGRect(x: 22, y: 800, width: 13, height: 1))
    case .meridian:
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: 14, height: pageBounds.height))
    case .ledger:
      // Stops short of the footer, so the page number sits below the rule rather
      // than being struck through by it.
      rendererContext.cgContext.setStrokeColor(charcoal.withAlphaComponent(0.6).cgColor)
      rendererContext.cgContext.setLineWidth(0.8)
      rendererContext.cgContext.stroke(
        CGRect(x: 18, y: 18, width: pageBounds.width - 36, height: 794))
    default:
      break
    }
  }

  // MARK: - Advanced Collection

  /// Repeating page architecture for the new collection. The two inset-led
  /// designs receive a real spine; every other design gets a discreet catalogue
  /// code, making continuation pages recognisably part of the same system.
  private func drawAdvancedPageFurniture(_ style: AdvancedResumeStyle) {
    if plan.bodyInset > 0 {
      let spineWidth = max(plan.bodyInset, 24)
      (style.variant.isMultiple(of: 2) ? accent : navy).setFill()
      rendererContext.cgContext.fill(
        CGRect(x: 0, y: 0, width: spineWidth, height: pageBounds.height))
      accent.withAlphaComponent(0.45).setFill()
      rendererContext.cgContext.fill(
        CGRect(x: spineWidth - 4, y: 0, width: 4, height: pageBounds.height))
      drawVerticalText(
        String(format: "ADVANCED / %02d", style.ordinal + 1),
        x: max(spineWidth / 2 - 4, 7),
        bottom: 780,
        length: 640,
        font: mediumFont(7.2),
        color: .white,
        lineHeight: 9,
        kern: 2.1
      )
      return
    }

    guard sideColumn == nil else { return }
    let edgeX = style.variant.isMultiple(of: 2) ? 13.0 : pageBounds.width - 16
    accent.withAlphaComponent(0.18).setFill()
    rendererContext.cgContext.fill(
      CGRect(x: edgeX, y: 228, width: 2, height: 340))
    drawVerticalText(
      String(format: "%02d / ADV", style.ordinal + 1),
      x: edgeX - 3,
      bottom: 704,
      length: 100,
      font: mediumFont(5.8),
      color: mutedInk.withAlphaComponent(0.62),
      lineHeight: 7,
      kern: 1.4
    )
  }

  /// One art-directed renderer, eight different constructions and four variants
  /// of each. The motif controls the geometry; the variant changes alignment,
  /// ornament density, portrait frame and typographic voice.
  private func drawAdvancedPrimaryHeader(_ style: AdvancedResumeStyle) {
    // The Showcase Collection (mastheads 16-25) is self-contained: each draws its
    // own background, name, portrait and contact, so the original sixteen motifs
    // below are untouched.
    if style.motif >= 16 {
      drawShowcaseMasthead(style)
      return
    }
    let carriesProfile = plan.profileInHeader && heroCarriesProfile
    let profileHeight = carriesProfile ? heroProfileHeight : 0
    let headerHeight = max(
      style.headerHeight,
      carriesProfile ? 148 + profileHeight : style.headerHeight
    )
    let context = rendererContext.cgContext
    let darkHeader = [0, 2, 4, 5, 7, 8, 12].contains(style.motif) || plan.darkPaper
    let headerInk: UIColor = darkHeader ? .white : headingInk
    let detailInk: UIColor = darkHeader ? UIColor.white.withAlphaComponent(0.78) : mutedInk
    let variantOffset = CGFloat(style.variant * 8)

    switch style.motif {
    case 0: // faceted command banner
      navy.setFill()
      context.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: headerHeight))
      let peak = UIBezierPath()
      peak.move(to: CGPoint(x: pageBounds.width * 0.58, y: 0))
      peak.addLine(to: CGPoint(x: pageBounds.width, y: 0))
      peak.addLine(to: CGPoint(x: pageBounds.width, y: headerHeight))
      peak.addLine(to: CGPoint(x: pageBounds.width * (0.72 - CGFloat(style.variant) * 0.04), y: headerHeight))
      peak.close()
      accent.setFill()
      peak.fill()
      accent.withAlphaComponent(0.25).setFill()
      context.fill(CGRect(x: 0, y: headerHeight - 8, width: pageBounds.width, height: 8))
    case 1: // aperture and orbit
      accent.withAlphaComponent(0.075 + CGFloat(style.variant) * 0.025).setFill()
      context.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: headerHeight))
      let centre = CGPoint(x: pageBounds.width - 72 - variantOffset, y: 54 + variantOffset / 2)
      for ring in 0..<4 {
        let diameter = 58 + CGFloat(ring * 24)
        context.setStrokeColor(accent.withAlphaComponent(0.68 - CGFloat(ring) * 0.12).cgColor)
        context.setLineWidth(ring == style.variant ? 3 : 0.8)
        context.strokeEllipse(
          in: CGRect(
            x: centre.x - diameter / 2, y: centre.y - diameter / 2,
            width: diameter, height: diameter))
      }
      accent.setFill()
      context.fill(CGRect(x: margin, y: headerHeight - 4, width: contentWidth, height: 4))
    case 2: // arclight gradient
      drawGradientBand(
        CGRect(x: 0, y: 0, width: pageBounds.width, height: headerHeight),
        from: navy,
        to: accent.withAlphaComponent(0.88)
      )
      context.setStrokeColor(UIColor.white.withAlphaComponent(0.18).cgColor)
      context.setLineWidth(18 + CGFloat(style.variant * 4))
      context.strokeEllipse(
        in: CGRect(x: pageBounds.width - 170, y: -108 + variantOffset, width: 248, height: 248))
      UIColor.white.withAlphaComponent(0.22).setFill()
      for index in 0..<(3 + style.variant) {
        context.fillEllipse(
          in: CGRect(x: 420 + CGFloat(index * 20), y: headerHeight - 27, width: 5, height: 5))
      }
    case 3: // blueprint grid
      UIColor(white: 0.975, alpha: 1).setFill()
      context.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: headerHeight))
      accent.withAlphaComponent(0.10).setFill()
      let grid = CGFloat(14 + style.variant * 2)
      for x in stride(from: CGFloat(0), through: pageBounds.width, by: grid) {
        context.fill(CGRect(x: x, y: 0, width: 0.55, height: headerHeight))
      }
      for y in stride(from: CGFloat(0), through: headerHeight, by: grid) {
        context.fill(CGRect(x: 0, y: y, width: pageBounds.width, height: 0.55))
      }
      drawCornerTicks(
        around: CGRect(x: margin, y: 24, width: contentWidth, height: headerHeight - 48),
        arm: 14 + CGFloat(style.variant * 2),
        thickness: 1.2
      )
    case 4: // kinetic ribbon
      charcoal.setFill()
      context.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: headerHeight))
      let ribbon = UIBezierPath()
      let startX = 330 - variantOffset
      ribbon.move(to: CGPoint(x: startX, y: 0))
      ribbon.addLine(to: CGPoint(x: pageBounds.width, y: 0))
      ribbon.addLine(to: CGPoint(x: pageBounds.width, y: headerHeight))
      ribbon.addLine(to: CGPoint(x: startX - 82, y: headerHeight))
      ribbon.close()
      accent.setFill()
      ribbon.fill()
      UIColor.white.withAlphaComponent(0.12).setFill()
      for index in 0..<(2 + style.variant) {
        context.fill(
          CGRect(x: startX + CGFloat(index * 24), y: 21 + CGFloat(index * 13), width: 54, height: 3))
      }
    case 5: // connected circuit panel
      navy.setFill()
      context.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: headerHeight))
      let path = UIBezierPath()
      path.move(to: CGPoint(x: 350, y: 28 + variantOffset))
      path.addLine(to: CGPoint(x: 430, y: 28 + variantOffset))
      path.addLine(to: CGPoint(x: 430, y: 82))
      path.addLine(to: CGPoint(x: 520, y: 82))
      path.addLine(to: CGPoint(x: 520, y: headerHeight - 28))
      accent.withAlphaComponent(0.72).setStroke()
      path.lineWidth = 2
      path.stroke()
      for point in [CGPoint(x: 350, y: 28 + variantOffset), CGPoint(x: 430, y: 82), CGPoint(x: 520, y: headerHeight - 28)] {
        accent.setFill()
        context.fillEllipse(in: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
      }
    case 6: // editorial frame
      let warm = UIColor(red: 0.985, green: 0.978, blue: 0.96, alpha: 1)
      warm.setFill()
      context.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: headerHeight))
      context.setStrokeColor(headingInk.withAlphaComponent(0.7).cgColor)
      context.setLineWidth(0.8 + CGFloat(style.variant) * 0.2)
      context.stroke(CGRect(x: 22, y: 18, width: pageBounds.width - 44, height: headerHeight - 36))
      context.stroke(CGRect(x: 27, y: 23, width: pageBounds.width - 54, height: headerHeight - 46))
      drawDiamond(
        centeredAt: CGPoint(x: pageBounds.midX, y: headerHeight - 23),
        size: 7 + CGFloat(style.variant),
        color: accent
      )
    case 8: // duotone diagonal split
      navy.setFill()
      context.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: headerHeight))
      let topX = pageBounds.width * (0.54 - CGFloat(style.variant) * 0.05)
      let botX = pageBounds.width * (0.68 - CGFloat(style.variant) * 0.05)
      let wedge = UIBezierPath()
      wedge.move(to: CGPoint(x: topX, y: 0))
      wedge.addLine(to: CGPoint(x: pageBounds.width, y: 0))
      wedge.addLine(to: CGPoint(x: pageBounds.width, y: headerHeight))
      wedge.addLine(to: CGPoint(x: botX, y: headerHeight))
      wedge.close()
      accent.setFill()
      wedge.fill()
      UIColor.white.withAlphaComponent(0.85).setStroke()
      let seam = UIBezierPath()
      seam.move(to: CGPoint(x: topX, y: 0))
      seam.addLine(to: CGPoint(x: botX, y: headerHeight))
      seam.lineWidth = 2
      seam.stroke()
    case 9: // radial halo, orbiting the portrait
      accent.withAlphaComponent(0.05).setFill()
      context.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: headerHeight))
      // Centred on the portrait so the rings read as a halo around it and the
      // name keeps a clean field to the left.
      let haloCentre = CGPoint(x: pageBounds.width - margin - 41, y: 74)
      drawRadialGlow(
        centre: haloCentre,
        radius: 132 + variantOffset,
        color: accent.withAlphaComponent(0.18))
      for ring in 0..<3 {
        context.setStrokeColor(accent.withAlphaComponent(0.32 - CGFloat(ring) * 0.09).cgColor)
        context.setLineWidth(ring == 0 ? 1.6 : 0.8)
        let diameter = 106 + CGFloat(ring) * 32
        context.strokeEllipse(
          in: CGRect(
            x: haloCentre.x - diameter / 2, y: haloCentre.y - diameter / 2,
            width: diameter, height: diameter))
      }
      accent.setFill()
      context.fill(CGRect(x: margin, y: headerHeight - 4, width: contentWidth, height: 4))
    case 10: // datum metric tiles
      UIColor(white: 0.98, alpha: 1).setFill()
      context.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: headerHeight))
      let tileW: CGFloat = 40
      let tileGap: CGFloat = 7
      for index in 0..<3 {
        let tx = pageBounds.width - margin - CGFloat(3 - index) * (tileW + tileGap) + tileGap
        let tile = UIBezierPath(
          roundedRect: CGRect(x: tx, y: 24, width: tileW, height: 30), cornerRadius: 4)
        accent.withAlphaComponent(0.10).setFill()
        tile.fill()
        accent.setFill()
        context.fill(CGRect(x: tx + 8, y: 31, width: 15, height: 4))
        accent.withAlphaComponent(0.4).setFill()
        context.fill(CGRect(x: tx + 8, y: 41, width: 24, height: 2))
      }
      accent.setFill()
      context.fill(CGRect(x: margin, y: 96, width: 54, height: 3))
      accent.withAlphaComponent(0.2).setFill()
      context.fill(CGRect(x: margin, y: headerHeight - 4, width: contentWidth, height: 4))
    case 11: // emblem monogram watermark
      UIColor(white: 0.985, alpha: 1).setFill()
      context.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: headerHeight))
      accent.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 10, height: headerHeight))
      let hexCentre = CGPoint(x: pageBounds.width - 76, y: headerHeight / 2 - 6)
      let hexRadius: CGFloat = 52 + CGFloat(style.variant * 3)
      accent.withAlphaComponent(0.09).setFill()
      hexagonPath(centre: hexCentre, radius: hexRadius).fill()
      accent.withAlphaComponent(0.5).setStroke()
      let hexOutline = hexagonPath(centre: hexCentre, radius: hexRadius)
      hexOutline.lineWidth = 1.4
      hexOutline.stroke()
      drawText(
        document.initials,
        rect: CGRect(x: hexCentre.x - hexRadius, y: hexCentre.y - 13, width: hexRadius * 2, height: 26),
        font: boldFont(21),
        color: accent.withAlphaComponent(0.6),
        lineHeight: 25,
        alignment: .center
      )
      accent.setFill()
      context.fill(CGRect(x: 10, y: headerHeight - 4, width: pageBounds.width - 10, height: 4))
    case 12: // layered glass panels
      charcoal.setFill()
      context.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: headerHeight))
      for index in 0..<3 {
        let inset = CGFloat(index) * 15
        let panelColor = index == style.variant ? accent : navy
        panelColor.withAlphaComponent(0.92 - CGFloat(index) * 0.24).setFill()
        UIBezierPath(
          roundedRect: CGRect(
            x: pageBounds.width - 252 + inset, y: -42 + inset, width: 268, height: 150),
          cornerRadius: 15
        ).fill()
      }
      accent.setFill()
      context.fill(CGRect(x: 0, y: headerHeight - 4, width: pageBounds.width, height: 4))
    case 13: // cadence equaliser
      accent.withAlphaComponent(0.05).setFill()
      context.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: headerHeight))
      let base = headerHeight - 12
      let barW: CGFloat = 6
      let barGap: CGFloat = 5
      let startX = pageBounds.width * 0.5
      var index = 0
      var barX = startX
      while barX < pageBounds.width - margin {
        let barHeight = 8 + CGFloat((index * 11 + style.variant * 7) % 34)
        accent.withAlphaComponent(index.isMultiple(of: 2) ? 0.75 : 0.35).setFill()
        context.fill(CGRect(x: barX, y: base - barHeight, width: barW, height: barHeight))
        barX += barW + barGap
        index += 1
      }
      accent.setFill()
      context.fill(CGRect(x: margin, y: headerHeight - 4, width: 54, height: 4))
    case 14: // architected frame with keystone
      UIColor(red: 0.99, green: 0.985, blue: 0.965, alpha: 1).setFill()
      context.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: headerHeight))
      context.setStrokeColor(navy.withAlphaComponent(0.75).cgColor)
      context.setLineWidth(1)
      context.stroke(CGRect(x: 20, y: 16, width: pageBounds.width - 40, height: headerHeight - 32))
      context.setLineWidth(0.6)
      context.stroke(CGRect(x: 25, y: 21, width: pageBounds.width - 50, height: headerHeight - 42))
      let keystone = UIBezierPath()
      let cx = pageBounds.midX
      keystone.move(to: CGPoint(x: cx - 17, y: 4))
      keystone.addLine(to: CGPoint(x: cx + 17, y: 4))
      keystone.addLine(to: CGPoint(x: cx + 10, y: 24))
      keystone.addLine(to: CGPoint(x: cx - 10, y: 24))
      keystone.close()
      accent.setFill()
      keystone.fill()
    default: // panoramic hero (motif 7) and stratus bands (motif 15)
      if style.motif == 15 {
        UIColor(white: 0.99, alpha: 1).setFill()
        context.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: headerHeight))
        let bands = 5
        for index in 0..<bands {
          let bandY = CGFloat(index) * headerHeight / CGFloat(bands)
          let bandHeight = headerHeight / CGFloat(bands) + 1
          accent.withAlphaComponent(0.05 + CGFloat(bands - index) * 0.03).setFill()
          context.fill(CGRect(x: 0, y: bandY, width: pageBounds.width, height: bandHeight))
        }
        accent.setFill()
        context.fill(CGRect(x: 0, y: headerHeight - 3, width: pageBounds.width, height: 3))
        break
      }
      drawGradientBand(
        CGRect(x: 0, y: 0, width: pageBounds.width, height: headerHeight),
        from: charcoal,
        to: navy
      )
      accent.setFill()
      context.fill(CGRect(x: 0, y: headerHeight - 5, width: pageBounds.width, height: 5))
      for index in 0..<(3 + style.variant) {
        accent.withAlphaComponent(0.08 + CGFloat(index) * 0.035).setFill()
        context.fillEllipse(
          in: CGRect(
            x: pageBounds.width - 176 + CGFloat(index * 18),
            y: -72 + CGFloat(index * 10),
            width: 210 - CGFloat(index * 16),
            height: 210 - CGFloat(index * 16)))
      }
    }

    let portraitSize: CGFloat = showsPortrait ? 78 + CGFloat(style.variant * 4) : 0
    let portraitX = pageBounds.width - margin - portraitSize
    let nameX: CGFloat = style.variant == 2 && !showsPortrait ? 118 : margin
    let nameWidth = max(
      (showsPortrait ? portraitX - nameX - 26 : pageBounds.width - nameX - margin),
      210
    )
    let nameAlignment: NSTextAlignment = style.variant == 2 && !showsPortrait ? .center : .left
    let label = ["ADVANCED / LEADERSHIP", "PROFILE / SELECTED", "CAREER / EDITION", "STUDIO / SERIES"][style.variant]
    drawText(
      label,
      rect: CGRect(x: nameX, y: 27, width: nameWidth, height: 13),
      font: mediumFont(7.4),
      color: darkHeader ? accent : accent,
      lineHeight: 10,
      alignment: nameAlignment,
      kern: 1.8
    )
    drawText(
      displayName,
      rect: CGRect(x: nameX, y: 48, width: nameWidth, height: 55),
      font: boldFont(27 + CGFloat(style.variant)),
      color: headerInk,
      lineHeight: 31 + CGFloat(style.variant),
      alignment: nameAlignment
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: nameX, y: 104, width: nameWidth, height: 15),
      font: mediumFont(8.2),
      color: detailInk,
      lineHeight: 11,
      alignment: nameAlignment,
      kern: 1.1
    )

    if showsPortrait {
      let shape: PortraitShape =
        switch style.variant {
        case 0: .circle
        case 1: .rounded(12)
        case 2: .square
        default: .rounded(portraitSize / 2)
        }
      drawPortrait(
        in: CGRect(x: portraitX, y: 34, width: portraitSize, height: portraitSize),
        ring: darkHeader ? .white : accent,
        ringWidth: 3,
        emptyFill: darkHeader ? accent : accent.withAlphaComponent(0.12),
        emptyText: darkHeader ? .white : accent,
        shape: shape,
        outerRing: accent.withAlphaComponent(0.35),
        outerRingWidth: 1.2
      )
    }

    let profileY: CGFloat = 132
    if carriesProfile {
      drawText(
        document.professionalProfile.trimmingCharacters(in: .whitespacesAndNewlines),
        rect: CGRect(x: margin, y: profileY, width: contentWidth, height: profileHeight),
        font: regularFont(9.2),
        color: detailInk,
        lineHeight: 13.2
      )
    }
    let contactY = carriesProfile ? profileY + profileHeight + 12 : headerHeight - 28
    drawContactStrip(
      x: margin,
      y: contactY,
      color: detailInk,
      iconColor: darkHeader ? accent : accent
    )
    measuredHeaderBottom = headerHeight + 24
  }

  private func drawAdvancedContinuationHeader(_ style: AdvancedResumeStyle) {
    if style.motif >= 16 {
      drawShowcaseContinuation(style)
      return
    }
    let context = rendererContext.cgContext
    let dark = [0, 2, 4, 5, 7, 8, 12].contains(style.motif) || plan.darkPaper
    if dark {
      (style.motif == 2 ? accent : navy).setFill()
      context.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: 70))
      accent.setFill()
      context.fill(CGRect(x: 0, y: 70, width: pageBounds.width, height: 3))
    } else {
      accent.withAlphaComponent(0.07 + CGFloat(style.variant) * 0.02).setFill()
      context.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: 70))
      accent.setFill()
      context.fill(CGRect(x: bodyX, y: 56, width: min(bodyWidth, 110 + CGFloat(style.motif * 14)), height: 2.5))
    }
    drawText(
      displayName,
      rect: CGRect(x: bodyX, y: 20, width: min(bodyWidth - 80, 390), height: 24),
      font: boldFont(18),
      color: dark ? .white : headingInk,
      lineHeight: 22
    )
    drawText(
      String(format: "%02d / PAGE %02d", style.ordinal + 1, pageNumber),
      rect: CGRect(x: pageBounds.width - margin - 110, y: 25, width: 110, height: 12),
      font: mediumFont(7.4),
      color: dark ? UIColor.white.withAlphaComponent(0.75) : mutedInk,
      lineHeight: 9,
      alignment: .right,
      kern: 1
    )
  }

  // MARK: - Showcase Collection (mastheads 16-25)

  /// The portfolio-grade letterheads. Each is fully self-contained — background,
  /// name, portrait and contact — so it can restructure the header rather than
  /// sit behind the shared name block the first sixteen motifs use.
  private func drawShowcaseMasthead(_ style: AdvancedResumeStyle) {
    let context = rendererContext.cgContext
    let w = pageBounds.width
    let name = displayName
    let headline = document.personal.headline.trimmingCharacters(in: .whitespacesAndNewlines)
    let warm = UIColor(red: 0.905, green: 0.865, blue: 0.795, alpha: 1)
    var headerHeight: CGFloat = 176

    switch style.motif {
    case 16:  // Salute — a warm hello and a round portrait
      headerHeight = 172
      accent.setFill()
      context.fill(CGRect(x: margin, y: 40, width: 7, height: 7))
      accent.withAlphaComponent(0.45).setFill()
      context.fill(CGRect(x: margin + 9, y: 40, width: 7, height: 7))
      context.fill(CGRect(x: margin, y: 49, width: 7, height: 7))
      let pSize: CGFloat = 82
      if showsPortrait {
        drawPortrait(
          in: CGRect(x: w - margin - pSize, y: 34, width: pSize, height: pSize),
          ring: accent, ringWidth: 3,
          emptyFill: accent.withAlphaComponent(0.12), emptyText: accent, shape: .circle,
          outerRing: accent.withAlphaComponent(0.22), outerRingWidth: 5)
      }
      let textW = w - margin * 2 - (showsPortrait ? pSize + 26 : 0)
      drawText(
        "Hi, I'm", rect: CGRect(x: margin, y: 64, width: textW, height: 28),
        font: boldFont(23), color: headingInk, lineHeight: 27)
      drawText(
        "\(name).", rect: CGRect(x: margin, y: 91, width: textW, height: 32),
        font: boldFont(23), color: accent, lineHeight: 27)
      if !headline.isEmpty {
        drawText(
          headline, rect: CGRect(x: margin, y: 130, width: textW + 40, height: 15),
          font: mediumFont(9.4), color: mutedInk, lineHeight: 13)
      }
      drawContactStrip(x: margin, y: headerHeight - 22, color: mutedInk, iconColor: accent)

    case 17:  // Couture — the name up the page beside a fashion portrait
      headerHeight = 216
      let pW: CGFloat = 152, pH: CGFloat = 190
      if showsPortrait {
        drawPortrait(
          in: CGRect(x: w - margin - pW, y: 12, width: pW, height: pH),
          ring: accent, ringWidth: 2,
          emptyFill: navy, emptyText: .white, shape: .rounded(6))
      }
      accent.setFill()
      context.fill(CGRect(x: margin, y: 14, width: 3, height: 168))
      drawVerticalText(
        name.uppercased(), x: margin + 28, bottom: 184, length: 168,
        font: boldFont(22), color: headingInk, lineHeight: 26, kern: 0.5)
      if !headline.isEmpty {
        drawVerticalText(
          headline.uppercased(), x: margin + 11, bottom: 184, length: 152,
          font: mediumFont(7.6), color: accent, lineHeight: 10, kern: 2.2)
      }
      // A horizontal byline keeps the name machine-readable (a rotated line is not)
      // and carries the contacts the single column has nowhere else to put.
      drawText(
        name, rect: CGRect(x: margin, y: 190, width: w - pW - margin * 2 - 12, height: 15),
        font: mediumFont(10), color: headingInk, lineHeight: 13)
      drawContactStrip(x: margin, y: headerHeight - 15, color: mutedInk, iconColor: accent)

    case 18:  // Medallion — a monogram seal between the name and a big portrait
      headerHeight = 190
      let pW: CGFloat = 150, pH: CGFloat = 170
      if showsPortrait {
        drawPortrait(
          in: CGRect(x: w - margin - pW, y: 12, width: pW, height: pH),
          ring: UIColor(white: 0.86, alpha: 1), ringWidth: 0.8,
          emptyFill: UIColor(white: 0.9, alpha: 1), emptyText: navy, shape: .square)
      }
      drawText(
        name.uppercased(),
        rect: CGRect(x: margin, y: 56, width: w - pW - margin * 2 - 26, height: 66),
        font: boldFont(30), color: headingInk, lineHeight: 33)
      if !headline.isEmpty {
        drawText(
          headline, rect: CGRect(x: margin, y: 124, width: 240, height: 16),
          font: mediumFont(9.6), color: accent, lineHeight: 13, kern: 0.6)
      }
      drawMonogramBadge(centre: CGPoint(x: w - margin - pW - 2, y: 150), radius: 30)
      accent.setFill()
      context.fill(CGRect(x: margin, y: headerHeight - 6, width: 40, height: 3))
      drawContactStrip(x: margin, y: headerHeight - 24, color: mutedInk, iconColor: accent)

    case 19:  // Sable — a dark banner meeting the dark facts column
      headerHeight = 150
      navy.setFill()
      context.fill(CGRect(x: 0, y: 0, width: w, height: headerHeight + 24))
      accent.setFill()
      context.fill(CGRect(x: 0, y: headerHeight - 4, width: w, height: 4))
      let pSize: CGFloat = 96
      if showsPortrait {
        drawPortrait(
          in: CGRect(x: margin, y: 27, width: pSize, height: pSize),
          ring: .white, ringWidth: 2,
          emptyFill: accent, emptyText: .white, shape: .square)
      }
      let tx = margin + (showsPortrait ? pSize + 20 : 0)
      drawText(
        name.uppercased(), rect: CGRect(x: tx, y: 42, width: w - tx - margin, height: 48),
        font: boldFont(26), color: .white, lineHeight: 29)
      if !headline.isEmpty {
        drawText(
          headline.uppercased(), rect: CGRect(x: tx, y: 94, width: w - tx - margin, height: 14),
          font: mediumFont(8.4), color: accent, lineHeight: 12, kern: 1.6)
      }

    case 20:  // Terracotta — an earthen band and a bold profile circle
      headerHeight = 182
      warm.setFill()
      context.fill(CGRect(x: 0, y: 0, width: w, height: headerHeight))
      navy.setFill()
      context.fillEllipse(in: CGRect(x: -46, y: 28, width: 132, height: 132))
      let pSize: CGFloat = 74
      if showsPortrait {
        drawPortrait(
          in: CGRect(x: 6, y: 54, width: pSize, height: pSize),
          ring: warm, ringWidth: 3,
          emptyFill: accent, emptyText: .white, shape: .circle)
      }
      let tx: CGFloat = 108
      drawText(
        "Hello, I'm", rect: CGRect(x: tx, y: 50, width: w - tx - margin, height: 24),
        font: boldFont(20), color: navy, lineHeight: 24)
      drawText(
        name, rect: CGRect(x: tx, y: 74, width: w - tx - margin, height: 42),
        font: boldFont(30), color: navy, lineHeight: 34)
      if !headline.isEmpty {
        drawText(
          headline.uppercased(), rect: CGRect(x: tx, y: 122, width: w - tx - margin, height: 14),
          font: mediumFont(8.2), color: accent, lineHeight: 12, kern: 1.8)
      }
      drawContactStrip(
        x: tx, y: headerHeight - 26, color: navy.withAlphaComponent(0.72), iconColor: accent)

    case 21:  // Lozenge — airy, with capsule contact labels
      headerHeight = 168
      let pSize: CGFloat = 72
      if showsPortrait {
        drawPortrait(
          in: CGRect(x: w - margin - pSize, y: 30, width: pSize, height: pSize),
          ring: accent, ringWidth: 2,
          emptyFill: accent.withAlphaComponent(0.12), emptyText: accent, shape: .rounded(16))
      }
      let textW = w - margin * 2 - (showsPortrait ? pSize + 24 : 0)
      drawText(
        name, rect: CGRect(x: margin, y: 46, width: textW, height: 42),
        font: boldFont(30), color: headingInk, lineHeight: 34)
      if !headline.isEmpty {
        drawText(
          headline.uppercased(), rect: CGRect(x: margin, y: 90, width: textW, height: 14),
          font: mediumFont(8.6), color: accent, lineHeight: 12, kern: 2)
      }
      drawContactPills(x: margin, y: 112)
      accent.withAlphaComponent(0.2).setFill()
      context.fill(CGRect(x: margin, y: headerHeight - 3, width: contentWidth, height: 1.4))

    case 22:  // Circlet — a ringed portrait with orbiting rated dots
      headerHeight = 198
      let pSize: CGFloat = 96
      let pc = CGPoint(x: w / 2, y: 62)
      let orbit = pSize / 2 + 15
      for i in 0..<12 {
        let a = CGFloat(i) / 12 * .pi * 2 - .pi / 2
        let filled = i < 7
        (filled ? accent : accent.withAlphaComponent(0.28)).setFill()
        let d: CGFloat = filled ? 5 : 3.4
        context.fillEllipse(
          in: CGRect(x: pc.x + cos(a) * orbit - d / 2, y: pc.y + sin(a) * orbit - d / 2, width: d, height: d))
      }
      if showsPortrait {
        drawPortrait(
          in: CGRect(x: pc.x - pSize / 2, y: pc.y - pSize / 2, width: pSize, height: pSize),
          ring: accent, ringWidth: 3,
          emptyFill: accent.withAlphaComponent(0.12), emptyText: accent, shape: .circle,
          outerRing: accent.withAlphaComponent(0.3), outerRingWidth: 1)
      }
      drawText(
        name, rect: CGRect(x: margin, y: 128, width: contentWidth, height: 34),
        font: boldFont(26), color: headingInk, lineHeight: 30, alignment: .center)
      if !headline.isEmpty {
        drawText(
          headline.uppercased(), rect: CGRect(x: margin, y: 160, width: contentWidth, height: 14),
          font: mediumFont(8.4), color: accent, lineHeight: 12, alignment: .center, kern: 2)
      }
      drawCentredContact(y: headerHeight - 20)

    case 23:  // Vogue — an oversized serif editorial
      headerHeight = 178
      headingInk.withAlphaComponent(0.82).setFill()
      context.fill(CGRect(x: margin, y: 30, width: contentWidth, height: 1))
      drawText(
        String(format: "PORTFOLIO / %02d", style.ordinal + 1),
        rect: CGRect(x: margin, y: 36, width: contentWidth, height: 12),
        font: mediumFont(7.6), color: accent, lineHeight: 10, kern: 3)
      drawText(
        name, rect: CGRect(x: margin, y: 54, width: contentWidth, height: 72),
        font: boldFont(46), color: headingInk, lineHeight: 48)
      if !headline.isEmpty {
        drawText(
          headline, rect: CGRect(x: margin, y: 130, width: contentWidth, height: 16),
          font: mediumFont(10), color: mutedInk, lineHeight: 14)
      }
      headingInk.withAlphaComponent(0.82).setFill()
      context.fill(CGRect(x: margin, y: headerHeight - 22, width: contentWidth, height: 1))
      drawContactStrip(x: margin, y: headerHeight - 16, color: mutedInk, iconColor: accent)

    case 24:  // Signet — a pressed wax seal over a centred classic
      headerHeight = 184
      drawSealBadge(centre: CGPoint(x: w / 2, y: 46), radius: 26)
      drawText(
        name, rect: CGRect(x: margin, y: 84, width: contentWidth, height: 36),
        font: boldFont(28), color: headingInk, lineHeight: 32, alignment: .center)
      if !headline.isEmpty {
        drawText(
          headline.uppercased(), rect: CGRect(x: margin, y: 120, width: contentWidth, height: 14),
          font: mediumFont(8.4), color: accent, lineHeight: 12, alignment: .center, kern: 2.4)
      }
      headingInk.withAlphaComponent(0.7).setFill()
      context.fill(CGRect(x: w / 2 - 60, y: 140, width: 120, height: 1))
      drawCentredContact(y: headerHeight - 20)

    default:  // 25 Almanac — an icon-led fact strip
      headerHeight = 176
      drawText(
        name.uppercased(), rect: CGRect(x: margin, y: 40, width: contentWidth, height: 40),
        font: boldFont(28), color: headingInk, lineHeight: 31)
      if !headline.isEmpty {
        drawText(
          headline, rect: CGRect(x: margin, y: 79, width: contentWidth, height: 16),
          font: mediumFont(9.6), color: accent, lineHeight: 13)
      }
      drawFactStrip(y: 104)
      accent.setFill()
      context.fill(CGRect(x: margin, y: headerHeight - 5, width: 44, height: 3))
    }

    measuredHeaderBottom = headerHeight + 24
  }

  private func drawShowcaseContinuation(_ style: AdvancedResumeStyle) {
    let context = rendererContext.cgContext
    let dark = style.motif == 19  // Sable is the dark one
    if dark {
      navy.setFill()
      context.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: 64))
      accent.setFill()
      context.fill(CGRect(x: 0, y: 64, width: pageBounds.width, height: 3))
    } else {
      accent.withAlphaComponent(0.08).setFill()
      context.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: 60))
      accent.setFill()
      context.fill(CGRect(x: bodyX, y: 48, width: 46, height: 2.5))
    }
    drawText(
      displayName, rect: CGRect(x: bodyX, y: 20, width: bodyWidth - 90, height: 22),
      font: boldFont(17), color: dark ? .white : headingInk, lineHeight: 21)
    drawText(
      String(format: "%02d / PAGE %02d", style.ordinal + 1, pageNumber),
      rect: CGRect(x: pageBounds.width - margin - 110, y: 24, width: 110, height: 12),
      font: mediumFont(7.4),
      color: dark ? UIColor.white.withAlphaComponent(0.75) : mutedInk,
      lineHeight: 9, alignment: .right, kern: 1)
  }

  /// A concentric-ring monogram seal, initials centred, for Medallion.
  private func drawMonogramBadge(centre: CGPoint, radius: CGFloat) {
    let context = rendererContext.cgContext
    UIColor.white.setFill()
    context.fillEllipse(
      in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
    accent.setStroke()
    let outer = UIBezierPath(
      ovalIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
    outer.lineWidth = 1.4
    outer.stroke()
    accent.withAlphaComponent(0.5).setStroke()
    let inner = UIBezierPath(
      ovalIn: CGRect(
        x: centre.x - radius + 5, y: centre.y - radius + 5, width: (radius - 5) * 2,
        height: (radius - 5) * 2))
    inner.lineWidth = 0.6
    inner.stroke()
    drawText(
      document.initials,
      rect: CGRect(x: centre.x - radius, y: centre.y - 9, width: radius * 2, height: 20),
      font: boldFont(15), color: accent, lineHeight: 18, alignment: .center)
    accent.setFill()
    context.fillEllipse(in: CGRect(x: centre.x - 2, y: centre.y - radius - 2, width: 4, height: 4))
  }

  /// A scalloped wax-seal monogram, for Signet.
  private func drawSealBadge(centre: CGPoint, radius: CGFloat) {
    let context = rendererContext.cgContext
    accent.withAlphaComponent(0.55).setFill()
    let scallops = 20
    for i in 0..<scallops {
      let a = CGFloat(i) / CGFloat(scallops) * .pi * 2
      let r = radius + 3
      context.fillEllipse(
        in: CGRect(x: centre.x + cos(a) * r - 1.6, y: centre.y + sin(a) * r - 1.6, width: 3.2, height: 3.2))
    }
    accent.setFill()
    context.fillEllipse(
      in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
    UIColor.white.withAlphaComponent(0.9).setStroke()
    let ring = UIBezierPath(
      ovalIn: CGRect(
        x: centre.x - radius + 4, y: centre.y - radius + 4, width: (radius - 4) * 2,
        height: (radius - 4) * 2))
    ring.lineWidth = 0.8
    ring.stroke()
    drawText(
      document.initials,
      rect: CGRect(x: centre.x - radius, y: centre.y - 8, width: radius * 2, height: 18),
      font: boldFont(14), color: .white, lineHeight: 17, alignment: .center)
  }

  /// Capsule contact labels, for Lozenge.
  private func drawContactPills(x: CGFloat, y: CGFloat) {
    var cx = x
    for (icon, value) in [
      ("phone.fill", document.personal.phone),
      ("envelope.fill", document.personal.email),
    ] where !value.isBlank {
      let attributes = textAttributes(font: mediumFont(8), color: headingInk, lineHeight: 10)
      let textWidth = singleLineWidth(value, attributes: attributes)
      let pillWidth = textWidth + 32
      let pill = UIBezierPath(
        roundedRect: CGRect(x: cx, y: y, width: pillWidth, height: 20), cornerRadius: 10)
      accent.withAlphaComponent(0.1).setFill()
      pill.fill()
      drawIcon("\(icon)", in: CGRect(x: cx + 9, y: y + 5.5, width: 9, height: 9), color: accent)
      NSAttributedString(string: value, attributes: attributes).draw(at: CGPoint(x: cx + 23, y: y + 5))
      cx += pillWidth + 8
    }
  }

  /// An icon-tile fact strip, for Almanac.
  private func drawFactStrip(y: CGFloat) {
    let facts: [(String, String)] = [
      ("phone.fill", document.personal.phone),
      ("envelope.fill", document.personal.email),
      ("briefcase.fill", document.personal.headline),
    ].filter { !$0.1.isBlank }
    guard !facts.isEmpty else { return }
    let count = CGFloat(facts.count)
    let tileWidth = (contentWidth - (count - 1) * 8) / count
    var tx = margin
    for (icon, value) in facts {
      let tile = UIBezierPath(
        roundedRect: CGRect(x: tx, y: y, width: tileWidth, height: 34), cornerRadius: 7)
      accent.withAlphaComponent(0.08).setFill()
      tile.fill()
      drawIcon(icon, in: CGRect(x: tx + 9, y: y + 11, width: 12, height: 12), color: accent)
      drawText(
        value, rect: CGRect(x: tx + 26, y: y + 9, width: tileWidth - 30, height: 18),
        font: regularFont(7.4), color: ink, lineHeight: 8.6)
      tx += tileWidth + 8
    }
  }

  /// A centred "phone · email" line, for the symmetric mastheads.
  private func drawCentredContact(y: CGFloat) {
    let contact = [document.personal.phone, document.personal.email]
      .filter { !$0.isBlank }
      .joined(separator: "    ·    ")
    guard !contact.isEmpty else { return }
    drawText(
      contact, rect: CGRect(x: margin, y: y, width: contentWidth, height: 12),
      font: regularFont(8.6), color: mutedInk, lineHeight: 11, alignment: .center)
  }

  private func drawPrimaryHeader() {
    // The centred letterheads stack the portrait above themselves and slide down
    // to make room, which lets their art keep its own coordinates.
    let lift = portraitLift
    if lift > 0 {
      drawStackedPortrait()
      rendererContext.cgContext.saveGState()
      rendererContext.cgContext.translateBy(x: 0, y: lift)
    }

    if let style = template.advancedStyle {
      drawAdvancedPrimaryHeader(style)
    } else {
      switch template {
    case .atlas: drawAtlasPrimaryHeader()
    case .verso: drawVersoPrimaryHeader()
    case .oxford: drawOxfordPrimaryHeader()
    case .chronicle: drawChroniclePrimaryHeader()
    case .gazette: drawGazettePrimaryHeader()
    case .strata: drawStrataPrimaryHeader()
    case .duo: drawDuoPrimaryHeader()
    case .signal: drawSignalPrimaryHeader()
    case .concise: drawConcisePrimaryHeader()
    case .pivot: drawPivotPrimaryHeader()
    case .portrait: drawPortraitPrimaryHeader()
    case .spotlight: drawSpotlightPrimaryHeader()
    case .beacon: drawBeaconPrimaryHeader()
    case .harbor: drawHarborPrimaryHeader()
    case .bloom: drawBloomPrimaryHeader()
    case .atelier: drawAtelierPrimaryHeader()
    case .canvas: drawCanvasPrimaryHeader()
    case .modern: drawModernPrimaryHeader()
    case .aurora: drawAuroraPrimaryHeader()
    case .slate: drawSlatePrimaryHeader()
    case .onyx: drawOnyxPrimaryHeader()
    case .minimal: drawMinimalPrimaryHeader()
    case .lumen: drawLumenPrimaryHeader()
    case .nordic: drawNordicPrimaryHeader()
    case .cascade: drawCascadePrimaryHeader()
    case .contemporary: drawContemporaryPrimaryHeader()
    case .horizon: drawHorizonPrimaryHeader()
    case .vector: drawVectorPrimaryHeader()
    case .technical: drawTechnicalPrimaryHeader()
    case .creative: drawCreativePrimaryHeader()
    case .mosaic: drawMosaicPrimaryHeader()
    case .vertex: drawVertexPrimaryHeader()
    case .timeline: drawTimelinePrimaryHeader()
    case .compact: drawCompactPrimaryHeader()
    case .corporate: drawCorporatePrimaryHeader()
    case .meridian: drawMeridianPrimaryHeader()
    case .classic: drawClassicPrimaryHeader()
    case .elegant: drawElegantPrimaryHeader()
    case .linen: drawLinenPrimaryHeader()
    case .ledger: drawLedgerPrimaryHeader()
    case .quill: drawQuillPrimaryHeader()
    case .academic: drawAcademicPrimaryHeader()
    case .monochrome: drawMonochromePrimaryHeader()
    case .editorial: drawEditorialPrimaryHeader()
    case .noir: drawNoirPrimaryHeader()
    case .gauge: drawGaugePrimaryHeader()
    case .folio: drawFolioPrimaryHeader()
    case .insignia: drawInsigniaPrimaryHeader()
    case .marquee: drawMarqueePrimaryHeader()
    case .metro: drawMetroPrimaryHeader()
    case .ivy: drawIvyPrimaryHeader()
    case .crest: drawCrestPrimaryHeader()
    case .geneva: drawGenevaPrimaryHeader()
    case .plinth: drawPlinthPrimaryHeader()
    case .stockholm: drawStockholmPrimaryHeader()
    case .tandem: drawTandemPrimaryHeader()
    case .varsity: drawVarsityPrimaryHeader()
    case .laureate: drawLaureatePrimaryHeader()
    case .modena: drawModenaPrimaryHeader()
    case .nova: drawNovaPrimaryHeader()
    case .prism: drawPrismPrimaryHeader()
    case .aurelia: drawAureliaPrimaryHeader()
    case .nocturne: drawNocturnePrimaryHeader()
    case .monarch: drawMonarchPrimaryHeader()
    case .eclipse: drawEclipsePrimaryHeader()
    case .contour: drawContourPrimaryHeader()
    case .axis: drawAxisPrimaryHeader()
    case .terrace: drawTerracePrimaryHeader()
      case .vantage: drawVantagePrimaryHeader()
      default: break
      }
    }

    if lift > 0 {
      rendererContext.cgContext.restoreGState()
    }
  }

  /// Whether this résumé prints a portrait at all: always for the photo-led
  /// templates, and only once a photo exists for every other one.
  private var showsPortrait: Bool { document.showsPortrait }

  /// The room a centred letterhead gives up to the portrait sitting above it.
  /// Zero for the rest — they set the portrait beside their text instead, so the
  /// header never grows and a résumé without a photo is unchanged.
  private var portraitLift: CGFloat {
    guard showsPortrait else { return 0 }
    return switch template {
    case .classic, .elegant, .academic, .linen, .ivy, .laureate, .aurelia, .nocturne: 78
    // Further down, so the portrait sits inside the ruled frame rather than on it.
    case .ledger: 96
    default: 0
    }
  }

  /// The horizontal room the header text gives up to a portrait beside it. Zero
  /// without a photo, which is what keeps those layouts exactly as they were.
  private func portraitGutter(_ width: CGFloat) -> CGFloat {
    showsPortrait ? width : 0
  }

  private func drawStackedPortrait() {
    let diameter: CGFloat = 70
    let top: CGFloat = template == .ledger ? 32 : 16
    drawPortrait(
      in: CGRect(x: (pageBounds.width - diameter) / 2, y: top, width: diameter, height: diameter),
      ring: accent,
      ringWidth: 2.5,
      emptyFill: accent.withAlphaComponent(0.14),
      emptyText: accent
    )
  }

  /// The portrait's outline. Most templates ring it in a circle; the grid-led
  /// ones square it off, which is rather the point of how they look.
  private enum PortraitShape {
    case circle
    case rounded(CGFloat)
    case square
  }

  private func portraitPath(_ rect: CGRect, shape: PortraitShape) -> UIBezierPath {
    switch shape {
    case .circle: UIBezierPath(ovalIn: rect)
    case .rounded(let radius): UIBezierPath(roundedRect: rect, cornerRadius: radius)
    case .square: UIBezierPath(rect: rect)
    }
  }

  /// The portrait: the photo — or the person's initials when they haven't picked
  /// one — inside a frame drawn in the accent colour, so it always matches the
  /// palette they chose.
  private func drawPortrait(
    in rect: CGRect,
    ring: UIColor,
    ringWidth: CGFloat,
    emptyFill: UIColor,
    emptyText: UIColor,
    shape: PortraitShape = .circle,
    outerRing: UIColor? = nil,
    outerRingWidth: CGFloat = 1.5
  ) {
    let context = rendererContext.cgContext
    let portrait = document.croppedPhotoImage

    context.saveGState()
    portraitPath(rect, shape: shape).addClip()
    if let portrait {
      // Already square, cropped to whatever the user framed, so it fills exactly.
      portrait.draw(in: rect)
    } else {
      emptyFill.setFill()
      context.fill(rect)
    }
    context.restoreGState()

    if portrait == nil {
      let size = rect.width * 0.32
      let attributes = textAttributes(
        font: boldFont(size),
        color: emptyText,
        lineHeight: size * 1.15,
        alignment: .center
      )
      let initials = NSAttributedString(string: document.initials, attributes: attributes)
      let height = initials.size().height
      initials.draw(
        with: CGRect(
          x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height),
        options: [.usesLineFragmentOrigin],
        context: nil
      )
    }

    // The frame sits just outside the image, so it reads as a border rather than
    // a stroke cutting into the face.
    ring.setStroke()
    let framePath = portraitPath(
      rect.insetBy(dx: -ringWidth / 2, dy: -ringWidth / 2), shape: shape)
    framePath.lineWidth = ringWidth
    framePath.stroke()

    // A second, outer frame for the templates whose portrait straddles two
    // backgrounds — a white ring alone would vanish against the white half.
    if let outerRing {
      let offset = ringWidth + outerRingWidth / 2
      outerRing.setStroke()
      let outerPath = portraitPath(rect.insetBy(dx: -offset, dy: -offset), shape: shape)
      outerPath.lineWidth = outerRingWidth
      outerPath.stroke()
    }
  }

  /// A left-to-right blend, for the templates whose letterhead is a gradient
  /// rather than a flat band.
  private func drawGradientBand(_ rect: CGRect, from start: UIColor, to end: UIColor) {
    let context = rendererContext.cgContext
    guard
      let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [start.cgColor, end.cgColor] as CFArray,
        locations: [0, 1]
      )
    else {
      start.setFill()
      context.fill(rect)
      return
    }
    context.saveGState()
    context.clip(to: rect)
    context.drawLinearGradient(
      gradient,
      start: CGPoint(x: rect.minX, y: rect.midY),
      end: CGPoint(x: rect.maxX, y: rect.midY),
      options: []
    )
    context.restoreGState()
  }

  /// Designer-leaning: the accent as a full-bleed colour block, with the portrait
  /// hanging off its bottom edge.
  private func drawAtelierPrimaryHeader() {
    let blockHeight: CGFloat = 150
    accent.setFill()
    rendererContext.cgContext.fill(
      CGRect(x: 0, y: 0, width: pageBounds.width, height: blockHeight))

    drawText(
      displayName,
      rect: CGRect(x: margin, y: 34, width: 380, height: 40),
      font: boldFont(30),
      color: .white,
      lineHeight: 34
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: 78, width: 380, height: 16),
      font: mediumFont(9),
      color: UIColor.white.withAlphaComponent(0.88),
      lineHeight: 12
    )
    UIColor.white.withAlphaComponent(0.55).setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 100, width: 46, height: 1.5))
    drawText(
      contactLine,
      rect: CGRect(x: margin, y: 110, width: 380, height: 13),
      font: regularFont(8.2),
      color: UIColor.white.withAlphaComponent(0.92),
      lineHeight: 10
    )

    // Straddles the block's bottom edge — half on the colour, half on the page.
    let diameter: CGFloat = 96
    drawPortrait(
      in: CGRect(
        x: pageBounds.width - margin - diameter,
        y: blockHeight - diameter / 2,
        width: diameter,
        height: diameter
      ),
      ring: .white,
      ringWidth: 5,
      emptyFill: navy,
      emptyText: .white,
      outerRing: navy.withAlphaComponent(0.14),
      outerRingWidth: 1
    )
  }

  /// Two-tone: an accent panel butted against the page, portrait sitting on the seam.
  private func drawCanvasPrimaryHeader() {
    let headerHeight: CGFloat = 160
    let seam: CGFloat = 205

    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: seam, height: headerHeight))
    lightGray.setFill()
    rendererContext.cgContext.fill(
      CGRect(x: seam, y: 0, width: pageBounds.width - seam, height: headerHeight))

    let diameter: CGFloat = 92
    drawPortrait(
      in: CGRect(
        x: seam - diameter / 2, y: (headerHeight - diameter) / 2,
        width: diameter, height: diameter
      ),
      ring: .white,
      ringWidth: 4,
      emptyFill: navy,
      emptyText: .white,
      outerRing: accent,
      outerRingWidth: 1.5
    )

    let textX = seam + diameter / 2 + 26
    let textWidth = pageBounds.width - textX - margin

    drawText(
      displayName,
      rect: CGRect(x: textX, y: 44, width: textWidth, height: 32),
      font: boldFont(24),
      color: navy,
      lineHeight: 28
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: textX, y: 78, width: textWidth, height: 15),
      font: mediumFont(8.6),
      color: accent,
      lineHeight: 11
    )
    drawText(
      contactLine,
      rect: CGRect(x: textX, y: 100, width: textWidth, height: 26),
      font: regularFont(8.2),
      color: gray,
      lineHeight: 12
    )
  }

  private func drawPortraitPrimaryHeader() {
    navy.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: 150))

    drawPortrait(
      in: CGRect(x: margin, y: 32, width: 86, height: 86),
      ring: accent,
      ringWidth: 3,
      emptyFill: accent.withAlphaComponent(0.22),
      emptyText: .white
    )

    let textX = margin + 86 + 24

    drawText(
      displayName,
      rect: CGRect(x: textX, y: 38, width: pageBounds.width - textX - margin, height: 34),
      font: boldFont(27),
      color: .white,
      lineHeight: 31
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: textX, y: 74, width: pageBounds.width - textX - margin, height: 16),
      font: mediumFont(9),
      color: accent,
      lineHeight: 12
    )
    drawText(
      contactLine,
      rect: CGRect(x: textX, y: 96, width: pageBounds.width - textX - margin, height: 13),
      font: regularFont(8.2),
      color: .white,
      lineHeight: 10
    )

    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: textX, y: 118, width: 54, height: 2.5))
  }

  private func drawSpotlightPrimaryHeader() {
    accent.withAlphaComponent(0.07).setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: 205))

    let diameter: CGFloat = 84
    let photoRect = CGRect(
      x: (pageBounds.width - diameter) / 2, y: 26, width: diameter, height: diameter)

    // A soft outer halo, then the ring itself — the "double frame" look.
    accent.withAlphaComponent(0.28).setStroke()
    rendererContext.cgContext.setLineWidth(1)
    rendererContext.cgContext.strokeEllipse(in: photoRect.insetBy(dx: -8, dy: -8))

    drawPortrait(
      in: photoRect,
      ring: accent,
      ringWidth: 3,
      emptyFill: accent.withAlphaComponent(0.16),
      emptyText: accent
    )

    drawText(
      displayName,
      rect: CGRect(x: margin, y: 126, width: contentWidth, height: 32),
      font: boldFont(25),
      color: navy,
      lineHeight: 29,
      alignment: .center
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: 158, width: contentWidth, height: 15),
      font: mediumFont(8.8),
      color: accent,
      lineHeight: 11,
      alignment: .center
    )
    drawText(
      contactLine,
      rect: CGRect(x: margin, y: 177, width: contentWidth, height: 13),
      font: regularFont(8.2),
      color: gray,
      lineHeight: 10,
      alignment: .center
    )

    accent.setFill()
    rendererContext.cgContext.fill(
      CGRect(x: (pageBounds.width - 54) / 2, y: 194, width: 54, height: 2))
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
        rect: CGRect(
          x: margin, y: 67, width: contentWidth - portraitGutter(94), height: 18),
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

    if showsPortrait {
      drawPortrait(
        in: CGRect(x: pageBounds.width - margin - 76, y: 24, width: 76, height: 76),
        ring: accent,
        ringWidth: 3,
        emptyFill: accent.withAlphaComponent(0.22),
        emptyText: .white
      )
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

    let textWidth = contentWidth - portraitGutter(88)

    drawText(
      displayName,
      rect: CGRect(x: margin, y: 23, width: textWidth, height: 36),
      font: boldFont(29),
      color: navy,
      lineHeight: 33
    )

    let headline = document.personal.headline.trimmingCharacters(in: .whitespacesAndNewlines)
    if !headline.isEmpty {
      drawText(
        headline.uppercased(),
        rect: CGRect(x: margin, y: 61, width: textWidth, height: 15),
        font: mediumFont(9),
        color: accent,
        lineHeight: 11
      )
    }

    let contacts = contactLine
    if !contacts.isEmpty {
      drawText(
        contacts,
        rect: CGRect(x: margin, y: 84, width: textWidth, height: 14),
        font: regularFont(8.5),
        color: gray,
        lineHeight: 11
      )
    }

    if showsPortrait {
      drawPortrait(
        in: CGRect(x: pageBounds.width - margin - 72, y: 20, width: 72, height: 72),
        ring: accent,
        ringWidth: 2.5,
        emptyFill: accent.withAlphaComponent(0.14),
        emptyText: accent
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

    let sideWidth = 302 - portraitGutter(84)

    // Tall enough for the two lines the narrow panel wraps a full name onto:
    // at exactly 60 the second line fell outside the box and the surname was
    // dropped from the page.
    drawText(
      displayName,
      rect: CGRect(x: margin, y: 27, width: 170, height: 70),
      font: boldFont(27),
      color: .white,
      lineHeight: 30
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: 259, y: 31, width: sideWidth, height: 34),
      font: boldFont(10),
      color: navy,
      lineHeight: 13
    )
    drawText(
      contactLine,
      rect: CGRect(x: 259, y: 78, width: sideWidth, height: 30),
      font: regularFont(8.5),
      color: gray,
      lineHeight: 12
    )

    if showsPortrait {
      drawPortrait(
        in: CGRect(x: pageBounds.width - margin - 70, y: 29, width: 70, height: 70),
        ring: navy,
        ringWidth: 2.5,
        emptyFill: accent.withAlphaComponent(0.2),
        emptyText: navy
      )
    }
  }

  private func drawCorporatePrimaryHeader() {
    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: 12))
    navy.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 12, width: pageBounds.width, height: 91))
    lightGray.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 103, width: pageBounds.width, height: 30))

    let textWidth = contentWidth - portraitGutter(90)

    drawText(
      displayName,
      rect: CGRect(x: margin, y: 32, width: textWidth, height: 34),
      font: boldFont(29),
      color: .white,
      lineHeight: 33
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: 70, width: textWidth, height: 18),
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

    if showsPortrait {
      drawPortrait(
        in: CGRect(x: pageBounds.width - margin - 74, y: 18, width: 74, height: 74),
        ring: .white,
        ringWidth: 3,
        emptyFill: accent,
        emptyText: .white,
        outerRing: accent,
        outerRingWidth: 1.5
      )
    }
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
    // The quiet circle in the corner is exactly where the portrait belongs, so a
    // photo takes its place rather than being bolted on somewhere else.
    if showsPortrait {
      drawPortrait(
        in: CGRect(x: margin, y: 26, width: 66, height: 66),
        ring: accent,
        ringWidth: 2.5,
        emptyFill: accent.withAlphaComponent(0.13),
        emptyText: accent
      )
    } else {
      accent.withAlphaComponent(0.13).setFill()
      rendererContext.cgContext.fillEllipse(in: CGRect(x: margin, y: 26, width: 66, height: 66))
      accent.setFill()
      rendererContext.cgContext.fillEllipse(
        in: CGRect(x: margin + 27, y: 53, width: 12, height: 12))
    }

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

    // Framed by the accent disc it already had in the corner.
    if showsPortrait {
      drawPortrait(
        in: CGRect(x: 478, y: 18, width: 76, height: 76),
        ring: .white,
        ringWidth: 3,
        emptyFill: navy,
        emptyText: .white
      )
    }
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

    let textWidth = contentWidth - portraitGutter(90)

    drawText(
      "</>  \(displayName)",
      rect: CGRect(x: margin, y: 28, width: textWidth, height: 35),
      font: boldFont(26),
      color: navy,
      lineHeight: 31
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: 68, width: textWidth, height: 17),
      font: mediumFont(8.7),
      color: accent,
      lineHeight: 11
    )
    drawText(
      contactLine,
      rect: CGRect(x: margin, y: 99, width: textWidth, height: 13),
      font: regularFont(8),
      color: charcoal,
      lineHeight: 10
    )

    // Squared off, to sit with the grid rather than against it.
    if showsPortrait {
      drawPortrait(
        in: CGRect(x: pageBounds.width - margin - 74, y: 26, width: 74, height: 74),
        ring: accent,
        ringWidth: 2,
        emptyFill: .white,
        emptyText: navy,
        shape: .square
      )
    }
  }

  private func drawCompactPrimaryHeader() {
    // The contact block is already pinned to the right, so the portrait leads
    // from the left and the name steps aside for it.
    let gutter = portraitGutter(78)
    if showsPortrait {
      drawPortrait(
        in: CGRect(x: margin, y: 18, width: 64, height: 64),
        ring: accent,
        ringWidth: 2.5,
        emptyFill: accent.withAlphaComponent(0.16),
        emptyText: accent
      )
    }

    drawText(
      displayName,
      rect: CGRect(x: margin + gutter, y: 21, width: 330 - gutter, height: 31),
      font: boldFont(26),
      color: navy,
      lineHeight: 30
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin + gutter, y: 55, width: 330 - gutter, height: 28),
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

    let textWidth = 483 - portraitGutter(88)

    drawText(
      displayName,
      rect: CGRect(x: 78, y: 27, width: textWidth, height: 34),
      font: boldFont(28),
      color: navy,
      lineHeight: 32
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: 78, y: 68, width: textWidth, height: 16),
      font: mediumFont(8.8),
      color: accent,
      lineHeight: 11
    )
    drawText(
      contactLine,
      rect: CGRect(x: 78, y: 99, width: textWidth, height: 13),
      font: regularFont(8.2),
      color: gray,
      lineHeight: 10
    )

    if showsPortrait {
      drawPortrait(
        in: CGRect(x: pageBounds.width - margin - 72, y: 28, width: 72, height: 72),
        ring: accent,
        ringWidth: 2.5,
        emptyFill: accent.withAlphaComponent(0.16),
        emptyText: accent
      )
    }
  }

  private func drawMonochromePrimaryHeader() {
    rendererContext.cgContext.setStrokeColor(charcoal.cgColor)
    rendererContext.cgContext.setLineWidth(2)
    rendererContext.cgContext.stroke(CGRect(x: margin, y: 21, width: contentWidth, height: 80))
    charcoal.setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 21, width: 13, height: 80))

    let textWidth = contentWidth - 48 - portraitGutter(78)

    drawText(
      displayName,
      rect: CGRect(x: margin + 30, y: 35, width: textWidth, height: 31),
      font: boldFont(27),
      color: charcoal,
      lineHeight: 31
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin + 30, y: 69, width: textWidth, height: 14),
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

    // Inside the rule box, and in ink rather than accent: this template has no
    // colour in it and a photo is no reason to introduce some.
    if showsPortrait {
      drawPortrait(
        in: CGRect(x: margin + contentWidth - 76, y: 30, width: 62, height: 62),
        ring: charcoal,
        ringWidth: 2,
        emptyFill: lightGray,
        emptyText: charcoal
      )
    }
  }

  private func drawEditorialPrimaryHeader() {
    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 22, width: 7, height: 101))

    let textGutter = portraitGutter(86)

    drawText(
      "EDITORIAL PROFILE",
      rect: CGRect(x: margin + 24, y: 22, width: 180, height: 13),
      font: mediumFont(8),
      color: accent,
      lineHeight: 10
    )
    drawText(
      displayName,
      rect: CGRect(x: margin + 24, y: 41, width: 360 - textGutter, height: 39),
      font: boldFont(31),
      color: charcoal,
      lineHeight: 35
    )
    drawText(
      document.personal.headline,
      rect: CGRect(x: margin + 24, y: 82, width: 355 - textGutter, height: 17),
      font: mediumFont(10),
      color: gray,
      lineHeight: 13
    )
    drawText(
      contactLine,
      rect: CGRect(x: margin + 24, y: 106, width: contentWidth - 24, height: 14),
      font: regularFont(8.3),
      color: charcoal,
      lineHeight: 10
    )

    if showsPortrait {
      drawPortrait(
        in: CGRect(x: pageBounds.width - margin - 70, y: 26, width: 70, height: 70),
        ring: accent,
        ringWidth: 2.5,
        emptyFill: lightGray,
        emptyText: charcoal
      )
    }

    ruleGray.setFill()
    rendererContext.cgContext.fill(
      CGRect(x: margin + 24, y: 129, width: contentWidth - 24, height: 0.7))
  }

  private func drawHorizonPrimaryHeader() {
    lightGray.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: 422, height: 126))
    navy.setFill()
    rendererContext.cgContext.fill(CGRect(x: 422, y: 0, width: 173, height: 126))
    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 119, width: pageBounds.width, height: 7))

    // The contact panel owns the right-hand side, so the portrait leads from the
    // left and the letterhead steps across for it.
    let gutter = portraitGutter(90)
    if showsPortrait {
      drawPortrait(
        in: CGRect(x: margin, y: 24, width: 74, height: 74),
        ring: navy,
        ringWidth: 3,
        emptyFill: accent.withAlphaComponent(0.2),
        emptyText: navy
      )
    }

    drawText(
      displayName,
      rect: CGRect(x: margin + gutter, y: 29, width: 355 - gutter, height: 36),
      font: boldFont(29),
      color: navy,
      lineHeight: 33
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin + gutter, y: 70, width: 350 - gutter, height: 16),
      font: mediumFont(9),
      color: accent,
      lineHeight: 11
    )
    drawText(
      "CONTACT",
      rect: CGRect(x: 448, y: 28, width: 112, height: 13),
      font: boldFont(7.5),
      color: accent,
      lineHeight: 10
    )
    drawText(
      [document.personal.phone, document.personal.email]
        .filter { !$0.isBlank }
        .joined(separator: "\n"),
      rect: CGRect(x: 448, y: 48, width: 112, height: 50),
      font: regularFont(8.1),
      color: .white,
      lineHeight: 13
    )
  }

  // MARK: - The structural letterheads
  //
  // These sit in the wide column: the narrow one is holding the portrait, the
  // contact details and the skills, so the letterhead has only the name to carry.

  private func drawAtlasPrimaryHeader() {
    drawText(
      displayName,
      rect: CGRect(x: bodyX, y: 36, width: bodyWidth, height: 36),
      font: boldFont(26),
      color: navy,
      lineHeight: 30
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: bodyX, y: 72, width: bodyWidth, height: 26),
      font: mediumFont(8.8),
      color: accent,
      lineHeight: 11
    )
    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: bodyX, y: 104, width: 54, height: 2.5))
  }

  private func drawVersoPrimaryHeader() {
    drawText(
      displayName,
      rect: CGRect(x: bodyX, y: 34, width: bodyWidth, height: 36),
      font: boldFont(27),
      color: navy,
      lineHeight: 31
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: bodyX, y: 72, width: bodyWidth, height: 26),
      font: mediumFont(8.8),
      color: accent,
      lineHeight: 11
    )
    ruleGray.setFill()
    rendererContext.cgContext.fill(CGRect(x: bodyX, y: 102, width: bodyWidth, height: 0.7))
  }

  private func drawOxfordPrimaryHeader() {
    drawText(
      displayName,
      rect: CGRect(x: bodyX, y: 36, width: bodyWidth, height: 36),
      font: boldFont(27),
      color: charcoal,
      lineHeight: 32
    )
    drawText(
      document.personal.headline,
      rect: CGRect(x: bodyX, y: 74, width: bodyWidth, height: 28),
      font: mediumFont(9.6),
      color: gray,
      lineHeight: 12
    )
    charcoal.setFill()
    rendererContext.cgContext.fill(CGRect(x: bodyX, y: 106, width: bodyWidth, height: 1.2))
    charcoal.withAlphaComponent(0.45).setFill()
    rendererContext.cgContext.fill(CGRect(x: bodyX, y: 109.6, width: bodyWidth, height: 0.5))
  }

  private func drawChroniclePrimaryHeader() {
    let textWidth = contentWidth - portraitGutter(96)

    drawText(
      displayName,
      rect: CGRect(x: margin, y: 32, width: textWidth, height: 38),
      font: boldFont(28),
      color: navy,
      lineHeight: 33
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: 72, width: textWidth, height: 16),
      font: mediumFont(8.8),
      color: accent,
      lineHeight: 11
    )
    drawContactStrip(x: margin, y: 98, color: charcoal, iconColor: accent)

    ruleGray.setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 126, width: contentWidth, height: 0.7))

    if showsPortrait {
      drawPortrait(
        in: CGRect(x: pageBounds.width - margin - 76, y: 30, width: 76, height: 76),
        ring: accent,
        ringWidth: 2.5,
        emptyFill: accent.withAlphaComponent(0.14),
        emptyText: accent
      )
    }
  }

  private func drawGazettePrimaryHeader() {
    let textWidth = contentWidth - portraitGutter(92)

    drawText(
      displayName,
      rect: CGRect(x: margin, y: 30, width: textWidth, height: 38),
      font: boldFont(28),
      color: charcoal,
      lineHeight: 33
    )
    drawText(
      document.personal.headline,
      rect: CGRect(x: margin, y: 68, width: textWidth, height: 18),
      font: mediumFont(10),
      color: gray,
      lineHeight: 13
    )
    drawText(
      contactLine,
      rect: CGRect(x: margin, y: 92, width: textWidth, height: 13),
      font: regularFont(8.4),
      color: charcoal,
      lineHeight: 10
    )

    if showsPortrait {
      drawPortrait(
        in: CGRect(x: pageBounds.width - margin - 74, y: 28, width: 74, height: 74),
        ring: charcoal,
        ringWidth: 2,
        emptyFill: lightGray,
        emptyText: charcoal
      )
    }

    charcoal.setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 116, width: contentWidth, height: 1.2))
    charcoal.withAlphaComponent(0.45).setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 120, width: contentWidth, height: 0.5))
  }

  private func drawStrataPrimaryHeader() {
    accent.withAlphaComponent(0.07).setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: 124))

    let textWidth = contentWidth - portraitGutter(96)

    drawText(
      displayName,
      rect: CGRect(x: margin, y: 32, width: textWidth, height: 38),
      font: boldFont(28),
      color: navy,
      lineHeight: 33
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: 72, width: textWidth, height: 16),
      font: mediumFont(8.8),
      color: accent,
      lineHeight: 11
    )
    drawText(
      contactLine,
      rect: CGRect(x: margin, y: 96, width: textWidth, height: 13),
      font: regularFont(8.3),
      color: gray,
      lineHeight: 10
    )

    if showsPortrait {
      drawPortrait(
        in: CGRect(x: pageBounds.width - margin - 78, y: 24, width: 78, height: 78),
        ring: accent,
        ringWidth: 2.5,
        emptyFill: .white,
        emptyText: accent,
        shape: .rounded(10)
      )
    }
  }

  private func drawDuoPrimaryHeader() {
    let textWidth = contentWidth - portraitGutter(96)

    drawText(
      displayName,
      rect: CGRect(x: margin, y: 30, width: textWidth, height: 40),
      font: boldFont(30),
      color: navy,
      lineHeight: 34
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: 70, width: textWidth, height: 16),
      font: mediumFont(9),
      color: accent,
      lineHeight: 11
    )
    drawText(
      contactLine,
      rect: CGRect(x: margin, y: 94, width: textWidth, height: 13),
      font: regularFont(8.3),
      color: gray,
      lineHeight: 10
    )

    if showsPortrait {
      drawPortrait(
        in: CGRect(x: pageBounds.width - margin - 78, y: 26, width: 78, height: 78),
        ring: accent,
        ringWidth: 2.5,
        emptyFill: accent.withAlphaComponent(0.14),
        emptyText: accent
      )
    }

    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 116, width: contentWidth, height: 3))
  }

  private func drawSignalPrimaryHeader() {
    lightGray.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: 130))
    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 126, width: pageBounds.width, height: 4))

    let textWidth = contentWidth - portraitGutter(96)

    drawText(
      displayName,
      rect: CGRect(x: margin, y: 30, width: textWidth, height: 38),
      font: boldFont(28),
      color: navy,
      lineHeight: 33
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: 70, width: textWidth, height: 16),
      font: mediumFont(8.8),
      color: accent,
      lineHeight: 11
    )
    drawContactStrip(x: margin, y: 96, color: charcoal, iconColor: accent)

    if showsPortrait {
      drawPortrait(
        in: CGRect(x: pageBounds.width - margin - 76, y: 26, width: 76, height: 76),
        ring: accent,
        ringWidth: 2.5,
        emptyFill: .white,
        emptyText: accent
      )
    }
  }

  private func drawConcisePrimaryHeader() {
    let textWidth = 330 - portraitGutter(70)

    drawText(
      displayName,
      rect: CGRect(x: margin, y: 24, width: textWidth, height: 30),
      font: boldFont(24),
      color: navy,
      lineHeight: 28
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: 54, width: textWidth, height: 24),
      font: mediumFont(8),
      color: accent,
      lineHeight: 10
    )
    drawText(
      contactLine.replacingOccurrences(of: "  |  ", with: "\n"),
      rect: CGRect(x: 400, y: 26, width: 161, height: 36),
      font: regularFont(8),
      color: gray,
      lineHeight: 11,
      alignment: .right
    )

    if showsPortrait {
      drawPortrait(
        in: CGRect(x: 366, y: 22, width: 58, height: 58),
        ring: accent,
        ringWidth: 2,
        emptyFill: accent.withAlphaComponent(0.14),
        emptyText: accent
      )
    }

    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 84, width: contentWidth, height: 3))
  }

  private func drawPivotPrimaryHeader() {
    navy.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: 118))
    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: 6))

    let textWidth = contentWidth - portraitGutter(94)

    drawText(
      displayName,
      rect: CGRect(x: margin, y: 26, width: textWidth, height: 38),
      font: boldFont(28),
      color: .white,
      lineHeight: 33
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: 66, width: textWidth, height: 16),
      font: mediumFont(8.8),
      color: accent,
      lineHeight: 11
    )
    drawText(
      contactLine,
      rect: CGRect(x: margin, y: 90, width: textWidth, height: 13),
      font: regularFont(8.3),
      color: UIColor.white.withAlphaComponent(0.85),
      lineHeight: 10
    )

    if showsPortrait {
      drawPortrait(
        in: CGRect(x: pageBounds.width - margin - 76, y: 22, width: 76, height: 76),
        ring: accent,
        ringWidth: 3,
        emptyFill: UIColor.white.withAlphaComponent(0.12),
        emptyText: .white
      )
    }
  }

  /// Photo-led: an oversized accent badge holds the portrait, and the letterhead
  /// hangs off it.
  private func drawBeaconPrimaryHeader() {
    drawPortrait(
      in: CGRect(x: margin, y: 22, width: 104, height: 104),
      ring: accent.withAlphaComponent(0.25),
      ringWidth: 6,
      emptyFill: accent,
      emptyText: .white
    )

    let textX = margin + 104 + 26
    let textWidth = pageBounds.width - textX - margin

    drawText(
      displayName.uppercased(),
      rect: CGRect(x: textX, y: 34, width: textWidth, height: 34),
      font: boldFont(24),
      color: navy,
      lineHeight: 28
    )
    drawText(
      document.personal.headline,
      rect: CGRect(x: textX, y: 70, width: textWidth, height: 16),
      font: mediumFont(9.4),
      color: gray,
      lineHeight: 12
    )
    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: textX, y: 94, width: 118, height: 5))
    drawText(
      contactLine,
      rect: CGRect(x: textX, y: 110, width: textWidth, height: 13),
      font: regularFont(8.3),
      color: charcoal,
      lineHeight: 10
    )
  }

  /// Photo-led: a flat colour horizon with the portrait sitting astride it.
  private func drawHarborPrimaryHeader() {
    let horizon: CGFloat = 96
    accent.setFill()
    rendererContext.cgContext.fill(
      CGRect(x: 0, y: 0, width: pageBounds.width, height: horizon))

    let diameter: CGFloat = 92
    drawPortrait(
      in: CGRect(
        x: (pageBounds.width - diameter) / 2,
        y: horizon - diameter / 2,
        width: diameter,
        height: diameter
      ),
      ring: .white,
      ringWidth: 4,
      emptyFill: navy,
      emptyText: .white,
      outerRing: accent.withAlphaComponent(0.35),
      outerRingWidth: 1.5
    )

    drawText(
      displayName,
      rect: CGRect(x: margin, y: 152, width: contentWidth, height: 32),
      font: boldFont(25),
      color: navy,
      lineHeight: 29,
      alignment: .center
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: 184, width: contentWidth, height: 15),
      font: mediumFont(8.8),
      color: accent,
      lineHeight: 11,
      alignment: .center
    )
    drawText(
      contactLine,
      rect: CGRect(x: margin, y: 203, width: contentWidth, height: 13),
      font: regularFont(8.2),
      color: gray,
      lineHeight: 10,
      alignment: .center
    )
    accent.setFill()
    rendererContext.cgContext.fill(
      CGRect(x: (pageBounds.width - 54) / 2, y: 220, width: 54, height: 2))
  }

  /// Photo-led: a soft rounded card, friendlier than a hard colour band.
  private func drawBloomPrimaryHeader() {
    let card = CGRect(x: 24, y: 20, width: pageBounds.width - 48, height: 146)
    let cardPath = UIBezierPath(roundedRect: card, cornerRadius: 20)
    accent.withAlphaComponent(0.08).setFill()
    cardPath.fill()
    accent.withAlphaComponent(0.28).setStroke()
    cardPath.lineWidth = 1
    cardPath.stroke()

    drawPortrait(
      in: CGRect(x: 44, y: 50, width: 86, height: 86),
      ring: .white,
      ringWidth: 3,
      emptyFill: accent.withAlphaComponent(0.22),
      emptyText: accent,
      outerRing: accent.withAlphaComponent(0.4),
      outerRingWidth: 1
    )

    let textX: CGFloat = 148
    let textWidth = card.maxX - textX - 20

    drawText(
      displayName,
      rect: CGRect(x: textX, y: 52, width: textWidth, height: 32),
      font: boldFont(25),
      color: navy,
      lineHeight: 29
    )
    drawText(
      document.personal.headline,
      rect: CGRect(x: textX, y: 84, width: textWidth, height: 16),
      font: mediumFont(9.2),
      color: accent,
      lineHeight: 12
    )
    drawText(
      contactLine,
      rect: CGRect(x: textX, y: 108, width: textWidth, height: 13),
      font: regularFont(8.4),
      color: gray,
      lineHeight: 10
    )
  }

  private func drawAuroraPrimaryHeader() {
    drawGradientBand(
      CGRect(x: 0, y: 0, width: pageBounds.width, height: 138),
      from: accent,
      to: navy
    )

    let textWidth = contentWidth - portraitGutter(104)

    drawText(
      displayName,
      rect: CGRect(x: margin, y: 30, width: textWidth, height: 40),
      font: boldFont(29),
      color: .white,
      lineHeight: 34
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: 72, width: textWidth, height: 16),
      font: mediumFont(9),
      color: UIColor.white.withAlphaComponent(0.9),
      lineHeight: 12
    )
    UIColor.white.withAlphaComponent(0.55).setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 94, width: 46, height: 1.5))
    drawText(
      contactLine,
      rect: CGRect(x: margin, y: 104, width: textWidth, height: 13),
      font: regularFont(8.3),
      color: UIColor.white.withAlphaComponent(0.92),
      lineHeight: 10
    )

    if showsPortrait {
      drawPortrait(
        in: CGRect(x: pageBounds.width - margin - 84, y: 27, width: 84, height: 84),
        ring: .white,
        ringWidth: 3,
        emptyFill: navy,
        emptyText: .white,
        outerRing: UIColor.white.withAlphaComponent(0.3),
        outerRingWidth: 1
      )
    }
  }

  private func drawSlatePrimaryHeader() {
    charcoal.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: 128))
    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 124, width: pageBounds.width, height: 4))

    let textWidth = contentWidth - portraitGutter(96)

    drawText(
      displayName,
      rect: CGRect(x: margin, y: 30, width: textWidth, height: 36),
      font: boldFont(28),
      color: .white,
      lineHeight: 32
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: 70, width: textWidth, height: 16),
      font: mediumFont(9),
      color: accent,
      lineHeight: 12
    )
    drawText(
      contactLine,
      rect: CGRect(x: margin, y: 98, width: textWidth, height: 13),
      font: regularFont(8.3),
      color: UIColor.white.withAlphaComponent(0.85),
      lineHeight: 10
    )

    if showsPortrait {
      drawPortrait(
        in: CGRect(x: pageBounds.width - margin - 80, y: 24, width: 80, height: 80),
        ring: accent,
        ringWidth: 2.5,
        emptyFill: UIColor.white.withAlphaComponent(0.12),
        emptyText: .white,
        shape: .rounded(10)
      )
    }
  }

  private func drawOnyxPrimaryHeader() {
    let ink = UIColor(white: 0.07, alpha: 1)
    ink.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: 150))
    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 34, width: 6, height: 64))

    let textX = margin + 20
    let textWidth = pageBounds.width - textX - margin - portraitGutter(102)

    drawText(
      displayName.uppercased(),
      rect: CGRect(x: textX, y: 34, width: textWidth, height: 42),
      font: boldFont(33),
      color: .white,
      lineHeight: 37
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: textX, y: 80, width: textWidth, height: 15),
      font: mediumFont(9),
      color: accent,
      lineHeight: 11
    )
    drawText(
      contactLine,
      rect: CGRect(x: textX, y: 106, width: textWidth, height: 13),
      font: regularFont(8.4),
      color: UIColor.white.withAlphaComponent(0.8),
      lineHeight: 10
    )

    if showsPortrait {
      drawPortrait(
        in: CGRect(x: pageBounds.width - margin - 88, y: 31, width: 88, height: 88),
        ring: accent,
        ringWidth: 3,
        emptyFill: UIColor.white.withAlphaComponent(0.1),
        emptyText: .white
      )
    }
  }

  private func drawLumenPrimaryHeader() {
    ruleGray.setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 22, width: contentWidth, height: 0.6))

    let textWidth = contentWidth - portraitGutter(96)

    // Lighter than every other name on the page, and tracked out: the whole point
    // of this one is that it whispers.
    drawText(
      displayName,
      rect: CGRect(x: margin, y: 40, width: textWidth, height: 40),
      font: mediumFont(31),
      color: charcoal,
      lineHeight: 36,
      kern: 0.8
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: 82, width: textWidth, height: 15),
      font: regularFont(8.4),
      color: accent,
      lineHeight: 11,
      kern: 2.4
    )
    drawText(
      contactLine,
      rect: CGRect(x: margin, y: 104, width: textWidth, height: 13),
      font: regularFont(8.3),
      color: gray,
      lineHeight: 10
    )

    if showsPortrait {
      drawPortrait(
        in: CGRect(x: pageBounds.width - margin - 76, y: 30, width: 76, height: 76),
        ring: accent.withAlphaComponent(0.5),
        ringWidth: 1.5,
        emptyFill: lightGray,
        emptyText: gray
      )
    }

    ruleGray.setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 126, width: contentWidth, height: 0.6))
  }

  private func drawCascadePrimaryHeader() {
    let textWidth = contentWidth - portraitGutter(104)

    drawText(
      displayName,
      rect: CGRect(x: margin, y: 28, width: textWidth, height: 38),
      font: boldFont(30),
      color: navy,
      lineHeight: 34
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: 68, width: textWidth, height: 16),
      font: mediumFont(9),
      color: accent,
      lineHeight: 11
    )

    // The steps: each one shorter and paler than the last.
    let steps: [(width: CGFloat, alpha: CGFloat)] = [(240, 1), (168, 0.55), (104, 0.3)]
    for (index, step) in steps.enumerated() {
      accent.withAlphaComponent(step.alpha).setFill()
      rendererContext.cgContext.fill(
        CGRect(x: margin, y: 92 + CGFloat(index) * 8, width: step.width, height: 4))
    }

    drawText(
      contactLine,
      rect: CGRect(x: margin, y: 122, width: textWidth, height: 13),
      font: regularFont(8.3),
      color: gray,
      lineHeight: 10
    )

    if showsPortrait {
      drawPortrait(
        in: CGRect(x: pageBounds.width - margin - 84, y: 26, width: 84, height: 84),
        ring: accent,
        ringWidth: 3,
        emptyFill: accent.withAlphaComponent(0.14),
        emptyText: accent
      )
    }
  }

  private func drawVectorPrimaryHeader() {
    let headerHeight: CGFloat = 126

    // The grid this template is named for.
    ruleGray.withAlphaComponent(0.5).setFill()
    for x in stride(from: margin, through: pageBounds.width - margin, by: 14) {
      for y in stride(from: 18, through: headerHeight - 8, by: 14) {
        rendererContext.cgContext.fillEllipse(in: CGRect(x: x, y: y, width: 1.4, height: 1.4))
      }
    }

    let textWidth = contentWidth - portraitGutter(96)

    drawText(
      displayName,
      rect: CGRect(x: margin, y: 34, width: textWidth, height: 34),
      font: boldFont(27),
      color: navy,
      lineHeight: 31
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: 74, width: textWidth, height: 15),
      font: mediumFont(8.7),
      color: accent,
      lineHeight: 11
    )
    drawText(
      contactLine,
      rect: CGRect(x: margin, y: 98, width: textWidth, height: 13),
      font: regularFont(8.2),
      color: charcoal,
      lineHeight: 10
    )

    if showsPortrait {
      let frame = CGRect(x: pageBounds.width - margin - 78, y: 24, width: 78, height: 78)
      drawPortrait(
        in: frame,
        ring: navy,
        ringWidth: 1.5,
        emptyFill: lightGray,
        emptyText: navy,
        shape: .square
      )
      drawCornerTicks(around: frame.insetBy(dx: -5, dy: -5), arm: 9, thickness: 2)
    } else {
      drawCornerTicks(
        around: CGRect(x: margin, y: 18, width: contentWidth, height: headerHeight - 18),
        arm: 12,
        thickness: 2
      )
    }
  }

  private func drawMosaicPrimaryHeader() {
    let textWidth = contentWidth - portraitGutter(110)

    drawText(
      displayName,
      rect: CGRect(x: margin, y: 30, width: textWidth, height: 38),
      font: boldFont(29),
      color: navy,
      lineHeight: 34
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: 72, width: textWidth, height: 16),
      font: mediumFont(8.8),
      color: accent,
      lineHeight: 11
    )
    drawText(
      contactLine,
      rect: CGRect(x: margin, y: 98, width: textWidth, height: 13),
      font: regularFont(8.2),
      color: gray,
      lineHeight: 10
    )

    // The tiles, and where a photo goes: it takes the whole block rather than
    // sitting awkwardly beside it.
    let block = CGRect(x: 455, y: 20, width: 86, height: 86)
    if showsPortrait {
      drawPortrait(
        in: block,
        ring: accent,
        ringWidth: 3,
        emptyFill: accent.withAlphaComponent(0.18),
        emptyText: accent,
        shape: .rounded(6)
      )
    } else {
      let alphas: [CGFloat] = [1, 0.35, 0.7, 0.5, 0.85, 0.2, 0.3, 0.6, 1]
      for (index, alpha) in alphas.enumerated() {
        let column = CGFloat(index % 3)
        let row = CGFloat(index / 3)
        accent.withAlphaComponent(alpha).setFill()
        rendererContext.cgContext.fill(
          CGRect(x: block.minX + column * 30, y: block.minY + row * 30, width: 26, height: 26))
      }
    }

    navy.setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 124, width: contentWidth, height: 4))
  }

  private func drawVertexPrimaryHeader() {
    let wedge = UIBezierPath()
    wedge.move(to: CGPoint(x: 0, y: 0))
    wedge.addLine(to: CGPoint(x: 150, y: 0))
    wedge.addLine(to: CGPoint(x: 0, y: 150))
    wedge.close()
    accent.setFill()
    wedge.fill()

    let textX: CGFloat = 170
    let textWidth = pageBounds.width - margin - textX - portraitGutter(96)

    drawText(
      displayName,
      rect: CGRect(x: textX, y: 34, width: textWidth, height: 38),
      font: boldFont(29),
      color: navy,
      lineHeight: 34
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: textX, y: 74, width: textWidth, height: 16),
      font: mediumFont(9),
      color: accent,
      lineHeight: 11
    )
    drawText(
      contactLine,
      rect: CGRect(x: textX, y: 100, width: textWidth, height: 13),
      font: regularFont(8.3),
      color: gray,
      lineHeight: 10
    )

    if showsPortrait {
      drawPortrait(
        in: CGRect(x: pageBounds.width - margin - 76, y: 28, width: 76, height: 76),
        ring: navy,
        ringWidth: 2.5,
        emptyFill: accent.withAlphaComponent(0.16),
        emptyText: navy
      )
    }

    navy.setFill()
    rendererContext.cgContext.fill(
      CGRect(x: textX, y: 128, width: pageBounds.width - margin - textX, height: 3))
  }

  private func drawMeridianPrimaryHeader() {
    // The rail itself is page furniture — it runs the whole height of every page.
    let textX: CGFloat = 48
    let textWidth = pageBounds.width - margin - textX - portraitGutter(96)

    drawText(
      displayName,
      rect: CGRect(x: textX, y: 34, width: textWidth, height: 40),
      font: boldFont(30),
      color: charcoal,
      lineHeight: 35
    )
    ruleGray.setFill()
    rendererContext.cgContext.fill(
      CGRect(x: textX, y: 80, width: pageBounds.width - margin - textX, height: 0.7))
    drawText(
      document.personal.headline,
      rect: CGRect(x: textX, y: 90, width: textWidth, height: 17),
      font: mediumFont(10),
      color: gray,
      lineHeight: 13
    )
    drawText(
      contactLine,
      rect: CGRect(x: textX, y: 114, width: textWidth, height: 13),
      font: regularFont(8.4),
      color: charcoal,
      lineHeight: 10
    )

    if showsPortrait {
      drawPortrait(
        in: CGRect(x: pageBounds.width - margin - 76, y: 30, width: 76, height: 76),
        ring: accent,
        ringWidth: 2.5,
        emptyFill: lightGray,
        emptyText: charcoal
      )
    }
  }

  /// Centred, and stacked under the portrait when there is one — the tint runs up
  /// behind it so the photo sits *on* the letterhead rather than above it.
  private func drawLinenPrimaryHeader() {
    let lift = portraitLift
    accent.withAlphaComponent(0.07).setFill()
    rendererContext.cgContext.fill(
      CGRect(x: 0, y: -lift, width: pageBounds.width, height: 132 + lift))

    drawText(
      displayName,
      rect: CGRect(x: margin, y: 30, width: contentWidth, height: 38),
      font: boldFont(30),
      color: charcoal,
      lineHeight: 35,
      alignment: .center
    )
    drawText(
      document.personal.headline,
      rect: CGRect(x: margin, y: 70, width: contentWidth, height: 17),
      font: mediumFont(10),
      color: gray,
      lineHeight: 13,
      alignment: .center
    )
    drawDiamond(centeredAt: CGPoint(x: pageBounds.midX, y: 96), size: 7, color: accent)
    drawText(
      contactLine,
      rect: CGRect(x: margin, y: 106, width: contentWidth, height: 13),
      font: regularFont(8.4),
      color: charcoal,
      lineHeight: 10,
      alignment: .center
    )
  }

  private func drawLedgerPrimaryHeader() {
    drawText(
      displayName,
      rect: CGRect(x: margin, y: 30, width: contentWidth, height: 36),
      font: boldFont(28),
      color: charcoal,
      lineHeight: 33,
      alignment: .center
    )

    // A printed double rule, thick over thin.
    charcoal.setFill()
    rendererContext.cgContext.fill(
      CGRect(x: margin + 8, y: 72, width: contentWidth - 16, height: 1.3))
    charcoal.withAlphaComponent(0.6).setFill()
    rendererContext.cgContext.fill(
      CGRect(x: margin + 8, y: 76, width: contentWidth - 16, height: 0.5))

    drawText(
      document.personal.headline,
      rect: CGRect(x: margin, y: 86, width: contentWidth, height: 16),
      font: mediumFont(10),
      color: gray,
      lineHeight: 13,
      alignment: .center
    )
    drawText(
      contactLine,
      rect: CGRect(x: margin, y: 108, width: contentWidth, height: 13),
      font: regularFont(8.3),
      color: charcoal,
      lineHeight: 10,
      alignment: .center
    )
    accent.setFill()
    rendererContext.cgContext.fill(
      CGRect(x: (pageBounds.width - 64) / 2, y: 128, width: 64, height: 2))
  }

  private func drawQuillPrimaryHeader() {
    let textWidth = contentWidth - portraitGutter(92)

    drawText(
      displayName,
      rect: CGRect(x: margin, y: 28, width: textWidth, height: 40),
      font: boldFont(30),
      color: charcoal,
      lineHeight: 35
    )
    drawDiamond(centeredAt: CGPoint(x: margin + 4, y: 76), size: 7, color: accent)
    drawText(
      document.personal.headline,
      rect: CGRect(x: margin + 18, y: 68, width: textWidth - 18, height: 17),
      font: mediumFont(10),
      color: gray,
      lineHeight: 13
    )
    drawText(
      contactLine,
      rect: CGRect(x: margin, y: 96, width: textWidth, height: 13),
      font: regularFont(8.3),
      color: charcoal,
      lineHeight: 10
    )

    if showsPortrait {
      drawPortrait(
        in: CGRect(x: pageBounds.width - margin - 72, y: 26, width: 72, height: 72),
        ring: charcoal,
        ringWidth: 2,
        emptyFill: lightGray,
        emptyText: charcoal
      )
    }

    charcoal.setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 120, width: contentWidth, height: 1.2))
    charcoal.withAlphaComponent(0.5).setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 124, width: contentWidth, height: 0.5))
  }

  /// A printer's ornament — the lozenge the manuscript templates set beside their
  /// type instead of a rule.
  // MARK: - The standout letterheads
  //
  // Ten more, drawn from the layouts the template sites actually rank: the dark
  // page, the metered sidebar, the numbered folio, the monogram tile, the
  // headline name, the colour blocks, the recruiter's plain serif, the banner
  // over a column, the Swiss split, and the footer that carries the contact.

  /// The dark page. The letterhead is light type on the paper itself — the
  /// drama is the sheet, so the header stays quiet.
  private func drawNoirPrimaryHeader() {
    let textWidth = contentWidth - portraitGutter(96)

    drawText(
      displayName,
      rect: CGRect(x: margin, y: 34, width: textWidth, height: 38),
      font: boldFont(28),
      color: .white,
      lineHeight: 33
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: 74, width: textWidth, height: 16),
      font: mediumFont(8.8),
      color: accent,
      lineHeight: 11
    )
    drawContactStrip(
      x: margin, y: 100, color: UIColor(white: 0.78, alpha: 1), iconColor: accent)
    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 126, width: 54, height: 2.5))

    if showsPortrait {
      drawPortrait(
        in: CGRect(x: pageBounds.width - margin - 76, y: 30, width: 76, height: 76),
        ring: accent,
        ringWidth: 2.5,
        emptyFill: UIColor.white.withAlphaComponent(0.12),
        emptyText: .white
      )
    }
  }

  /// The metered sidebar's letterhead: the dark band is carrying the portrait,
  /// the icons and the bars, so the name keeps the wide column to itself.
  private func drawGaugePrimaryHeader() {
    drawText(
      displayName,
      rect: CGRect(x: bodyX, y: 34, width: bodyWidth, height: 36),
      font: boldFont(26),
      color: navy,
      lineHeight: 30
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: bodyX, y: 72, width: bodyWidth, height: 26),
      font: mediumFont(8.8),
      color: accent,
      lineHeight: 11
    )
    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: bodyX, y: 102, width: 54, height: 2.5))
  }

  /// The numbered folio: a bookish serif letterhead over sections that count
  /// themselves off down the page.
  private func drawFolioPrimaryHeader() {
    let textWidth = contentWidth - portraitGutter(92)

    drawText(
      displayName,
      rect: CGRect(x: margin, y: 30, width: textWidth, height: 40),
      font: boldFont(29),
      color: charcoal,
      lineHeight: 34
    )
    drawText(
      document.personal.headline,
      rect: CGRect(x: margin, y: 70, width: textWidth, height: 18),
      font: mediumFont(10),
      color: gray,
      lineHeight: 13
    )
    drawText(
      contactLine,
      rect: CGRect(x: margin, y: 94, width: textWidth, height: 13),
      font: regularFont(8.4),
      color: charcoal,
      lineHeight: 10
    )

    if showsPortrait {
      drawPortrait(
        in: CGRect(x: pageBounds.width - margin - 74, y: 28, width: 74, height: 74),
        ring: accent,
        ringWidth: 2,
        emptyFill: accent.withAlphaComponent(0.14),
        emptyText: accent
      )
    }

    charcoal.setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 120, width: contentWidth, height: 1.2))
    charcoal.withAlphaComponent(0.45).setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 124, width: contentWidth, height: 0.5))
  }

  /// The monogram as a logo: initials on a solid accent tile until a photo
  /// replaces them, the way the design sites brand a résumé's corner.
  private func drawInsigniaPrimaryHeader() {
    drawPortrait(
      in: CGRect(x: margin, y: 26, width: 76, height: 76),
      ring: accent,
      ringWidth: 2,
      emptyFill: accent,
      emptyText: .white,
      shape: .rounded(14)
    )

    let textX = margin + 76 + 22
    let textWidth = pageBounds.width - textX - margin

    drawText(
      displayName,
      rect: CGRect(x: textX, y: 30, width: textWidth, height: 34),
      font: boldFont(25),
      color: navy,
      lineHeight: 29
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: textX, y: 64, width: textWidth, height: 16),
      font: mediumFont(8.8),
      color: accent,
      lineHeight: 11
    )
    drawText(
      contactLine,
      rect: CGRect(x: textX, y: 86, width: textWidth, height: 13),
      font: regularFont(8.3),
      color: gray,
      lineHeight: 10
    )
    ruleGray.setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 118, width: contentWidth, height: 0.7))
  }

  /// The headline name: the letterhead is the type itself, set at poster size —
  /// first name in the accent, surname in ink.
  private func drawMarqueePrimaryHeader() {
    let words = displayName.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    let first = words.first.map(String.init) ?? displayName
    let rest = words.count > 1 ? String(words[1]) : ""

    drawText(
      first.uppercased(),
      rect: CGRect(x: margin, y: 22, width: contentWidth, height: 46),
      font: boldFont(38),
      color: accent,
      lineHeight: 42
    )
    let detailY: CGFloat
    if rest.isEmpty {
      detailY = 74
    } else {
      drawText(
        rest.uppercased(),
        rect: CGRect(x: margin, y: 66, width: contentWidth, height: 46),
        font: boldFont(38),
        color: navy,
        lineHeight: 42
      )
      detailY = 118
    }

    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: detailY, width: contentWidth, height: 15),
      font: mediumFont(9),
      color: gray,
      lineHeight: 11
    )
    drawContactStrip(x: margin, y: detailY + 22, color: charcoal, iconColor: accent)
    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 164, width: contentWidth, height: 4))
  }

  /// The colour blocks: a navy slab for the name, an accent slab for the
  /// contact, and the portrait straddling the pair of them.
  private func drawMetroPrimaryHeader() {
    navy.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: 92))
    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 92, width: pageBounds.width, height: 30))

    let textWidth = contentWidth - portraitGutter(94)

    drawText(
      displayName,
      rect: CGRect(x: margin, y: 24, width: textWidth, height: 36),
      font: boldFont(26),
      color: .white,
      lineHeight: 30
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: 60, width: textWidth, height: 16),
      font: mediumFont(8.8),
      color: UIColor.white.withAlphaComponent(0.85),
      lineHeight: 11
    )
    drawContactStrip(x: margin, y: 101, color: .white, iconColor: navy)

    if showsPortrait {
      drawPortrait(
        in: CGRect(x: pageBounds.width - margin - 82, y: 24, width: 82, height: 82),
        ring: .white,
        ringWidth: 3,
        emptyFill: accent,
        emptyText: .white,
        shape: .rounded(12)
      )
    }
  }

  /// The career office's own format: name centred in a book serif, one rule,
  /// and not a drop of colour anywhere on the page.
  private func drawIvyPrimaryHeader() {
    drawText(
      displayName,
      rect: CGRect(x: margin, y: 28, width: contentWidth, height: 30),
      font: boldFont(23),
      color: charcoal,
      lineHeight: 27,
      alignment: .center
    )
    drawText(
      document.personal.headline,
      rect: CGRect(x: margin, y: 58, width: contentWidth, height: 16),
      font: regularFont(10),
      color: gray,
      lineHeight: 13,
      alignment: .center
    )
    drawText(
      contactLine,
      rect: CGRect(x: margin, y: 78, width: contentWidth, height: 13),
      font: regularFont(8.6),
      color: charcoal,
      lineHeight: 11,
      alignment: .center
    )
    charcoal.setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 100, width: contentWidth, height: 1))
  }

  /// The banner over the column: a navy letterhead across the whole sheet, with
  /// the tinted column resuming beneath it. The column carries the contact.
  private func drawCrestPrimaryHeader() {
    navy.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: 118))
    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 118, width: pageBounds.width, height: 5))

    let textWidth = contentWidth - portraitGutter(94)

    drawText(
      displayName,
      rect: CGRect(x: margin, y: 32, width: textWidth, height: 38),
      font: boldFont(27),
      color: .white,
      lineHeight: 32
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: 72, width: textWidth, height: 16),
      font: mediumFont(8.8),
      color: accent,
      lineHeight: 11
    )
    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 94, width: 44, height: 3))

    if showsPortrait {
      drawPortrait(
        in: CGRect(x: pageBounds.width - margin - 78, y: 20, width: 78, height: 78),
        ring: accent,
        ringWidth: 3,
        emptyFill: UIColor.white.withAlphaComponent(0.12),
        emptyText: .white
      )
    }
  }

  /// The Swiss split: a wide letterhead, a hairline seam, and nothing that
  /// could be mistaken for decoration.
  private func drawGenevaPrimaryHeader() {
    let textWidth = contentWidth - portraitGutter(84)

    drawText(
      displayName,
      rect: CGRect(x: margin, y: 30, width: textWidth, height: 34),
      font: boldFont(25),
      color: charcoal,
      lineHeight: 29,
      kern: 0.4
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: 68, width: textWidth, height: 15),
      font: mediumFont(8.8),
      color: gray,
      lineHeight: 11,
      kern: 1.6
    )
    ruleGray.setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 98, width: contentWidth, height: 0.7))

    if showsPortrait {
      drawPortrait(
        in: CGRect(x: pageBounds.width - margin - 64, y: 22, width: 64, height: 64),
        ring: charcoal,
        ringWidth: 1.5,
        emptyFill: lightGray,
        emptyText: charcoal
      )
    }
  }

  /// The footer plinth's letterhead: big, clean, and deliberately without the
  /// contact line — the colour band along the foot of every page carries it.
  private func drawPlinthPrimaryHeader() {
    let textWidth = contentWidth - portraitGutter(90)

    drawText(
      displayName,
      rect: CGRect(x: margin, y: 30, width: textWidth, height: 40),
      font: boldFont(29),
      color: navy,
      lineHeight: 34
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: 72, width: textWidth, height: 16),
      font: mediumFont(9),
      color: accent,
      lineHeight: 11
    )
    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 100, width: 44, height: 3))

    if showsPortrait {
      drawPortrait(
        in: CGRect(x: pageBounds.width - margin - 74, y: 26, width: 74, height: 74),
        ring: accent,
        ringWidth: 2.5,
        emptyFill: accent.withAlphaComponent(0.14),
        emptyText: accent
      )
    }
  }

  /// The duet the builder sites made famous: a quiet tinted letterhead, and the
  /// contact details living in the narrow column rather than under the name.
  private func drawStockholmPrimaryHeader() {
    accent.withAlphaComponent(0.07).setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: 108))
    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 108, width: pageBounds.width, height: 2))

    let textWidth = contentWidth - portraitGutter(86)
    drawText(
      displayName,
      rect: CGRect(x: margin, y: 26, width: textWidth, height: 36),
      font: boldFont(26),
      color: charcoal,
      lineHeight: 30
    )
    drawText(
      document.personal.headline,
      rect: CGRect(x: margin, y: 64, width: textWidth, height: 16),
      font: mediumFont(10.5),
      color: accent,
      lineHeight: 13
    )

    if showsPortrait {
      drawPortrait(
        in: CGRect(x: pageBounds.width - margin - 74, y: 17, width: 74, height: 74),
        ring: accent,
        ringWidth: 2.5,
        emptyFill: accent.withAlphaComponent(0.14),
        emptyText: accent
      )
    }
  }

  /// The double column with the rail: the letterhead stays light so the dotted
  /// timeline running through the roles carries the look.
  private func drawTandemPrimaryHeader() {
    drawText(
      displayName,
      rect: CGRect(x: bodyX, y: 30, width: bodyWidth, height: 36),
      font: boldFont(26),
      color: navy,
      lineHeight: 30
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: bodyX, y: 68, width: bodyWidth, height: 15),
      font: mediumFont(9),
      color: accent,
      lineHeight: 11,
      kern: 1.2
    )
    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: bodyX, y: 94, width: 54, height: 2.5))
  }

  /// The campus one-pager: surname set bold against the first name, one
  /// hairline, and the asymmetric split beginning immediately below.
  private func drawVarsityPrimaryHeader() {
    let words = displayName.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    let first = words.first.map(String.init) ?? displayName
    let rest = words.count > 1 ? String(words[1]) : ""
    let nameWidth = contentWidth - portraitGutter(76)

    let firstAttributes = textAttributes(font: regularFont(26), color: charcoal, lineHeight: 30)
    let restAttributes = textAttributes(font: boldFont(26), color: charcoal, lineHeight: 30)
    let firstWidth = singleLineWidth(first, attributes: firstAttributes)
    let restWidth = rest.isEmpty ? 0 : singleLineWidth(rest, attributes: restAttributes) + 8

    if !rest.isEmpty, firstWidth + restWidth <= nameWidth {
      NSAttributedString(string: first, attributes: firstAttributes)
        .draw(at: CGPoint(x: margin, y: 22))
      NSAttributedString(string: rest, attributes: restAttributes)
        .draw(at: CGPoint(x: margin + firstWidth + 8, y: 22))
    } else {
      // A name too long for the two-tone line keeps to one weight and wraps.
      drawText(
        displayName,
        rect: CGRect(x: margin, y: 22, width: nameWidth, height: 34),
        font: boldFont(22),
        color: charcoal,
        lineHeight: 26
      )
    }

    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: 58, width: nameWidth, height: 14),
      font: mediumFont(8.6),
      color: accent,
      lineHeight: 11,
      kern: 1.6
    )
    drawText(
      contactLine,
      rect: CGRect(x: margin, y: 76, width: nameWidth, height: 12),
      font: regularFont(8.2),
      color: gray,
      lineHeight: 10
    )
    ruleGray.setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 94, width: contentWidth, height: 0.7))

    if showsPortrait {
      drawPortrait(
        in: CGRect(x: pageBounds.width - margin - 62, y: 18, width: 62, height: 62),
        ring: charcoal,
        ringWidth: 1.5,
        emptyFill: lightGray,
        emptyText: charcoal
      )
    }
  }

  /// The award-list CV: a centred two-tone name — surname in the accent — over
  /// rules that answer the section titles below.
  private func drawLaureatePrimaryHeader() {
    let words = displayName.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    let first = words.first.map(String.init) ?? displayName
    let rest = words.count > 1 ? String(words[1]) : ""

    let firstAttributes = textAttributes(font: regularFont(27), color: charcoal, lineHeight: 31)
    let restAttributes = textAttributes(font: boldFont(27), color: accent, lineHeight: 31)
    let firstWidth = singleLineWidth(first, attributes: firstAttributes)
    let restWidth = rest.isEmpty ? 0 : singleLineWidth(rest, attributes: restAttributes) + 8
    let total = firstWidth + restWidth

    if !rest.isEmpty, total <= contentWidth {
      let startX = margin + (contentWidth - total) / 2
      NSAttributedString(string: first, attributes: firstAttributes)
        .draw(at: CGPoint(x: startX, y: 26))
      NSAttributedString(string: rest, attributes: restAttributes)
        .draw(at: CGPoint(x: startX + firstWidth + 8, y: 26))
    } else {
      drawText(
        displayName,
        rect: CGRect(x: margin, y: 26, width: contentWidth, height: 34),
        font: boldFont(24),
        color: charcoal,
        lineHeight: 28,
        alignment: .center
      )
    }

    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: 64, width: contentWidth, height: 14),
      font: mediumFont(8.8),
      color: gray,
      lineHeight: 11,
      alignment: .center,
      kern: 2
    )
    drawText(
      contactLine,
      rect: CGRect(x: margin, y: 84, width: contentWidth, height: 12),
      font: regularFont(8.4),
      color: charcoal,
      lineHeight: 10,
      alignment: .center
    )
    accent.setFill()
    rendererContext.cgContext.fill(
      CGRect(x: (pageBounds.width - 56) / 2, y: 106, width: 56, height: 2))
  }

  /// The scholar's margin: a plain letterhead over roles whose dates hang in
  /// the left gutter, the accent box finishing the rule the LaTeX way.
  private func drawModenaPrimaryHeader() {
    let textWidth = contentWidth - portraitGutter(84)
    drawText(
      displayName,
      rect: CGRect(x: margin, y: 28, width: textWidth, height: 36),
      font: boldFont(26),
      color: navy,
      lineHeight: 30
    )
    drawText(
      document.personal.headline,
      rect: CGRect(x: margin, y: 66, width: textWidth, height: 16),
      font: mediumFont(10),
      color: gray,
      lineHeight: 13
    )
    drawText(
      contactLine,
      rect: CGRect(x: margin, y: 88, width: textWidth, height: 13),
      font: regularFont(8.4),
      color: charcoal,
      lineHeight: 10
    )
    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 112, width: 84, height: 3))
    ruleGray.setFill()
    rendererContext.cgContext.fill(
      CGRect(x: margin + 84, y: 113.2, width: contentWidth - 84, height: 0.8))

    if showsPortrait {
      drawPortrait(
        in: CGRect(x: pageBounds.width - margin - 72, y: 26, width: 72, height: 72),
        ring: accent,
        ringWidth: 2,
        emptyFill: accent.withAlphaComponent(0.14),
        emptyText: accent
      )
    }
  }

  /// The colour banner: name and icon strip on a full accent band, a squared
  /// portrait on its right — the look every builder site leads with.
  private func drawNovaPrimaryHeader() {
    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: 122))
    navy.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 122, width: pageBounds.width, height: 4))

    let textWidth = contentWidth - portraitGutter(96)
    drawText(
      displayName,
      rect: CGRect(x: margin, y: 26, width: textWidth, height: 36),
      font: boldFont(27),
      color: .white,
      lineHeight: 31
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: 64, width: textWidth, height: 15),
      font: mediumFont(9),
      color: UIColor.white.withAlphaComponent(0.9),
      lineHeight: 11,
      kern: 1.4
    )
    drawContactStrip(x: margin, y: 96, color: .white, iconColor: navy)

    drawPortrait(
      in: CGRect(x: pageBounds.width - margin - 84, y: 19, width: 84, height: 84),
      ring: .white,
      ringWidth: 3,
      emptyFill: UIColor.white.withAlphaComponent(0.18),
      emptyText: .white,
      shape: .rounded(10)
    )
  }

  /// The accent panel's letterhead: the band is carrying the portrait, icons
  /// and chips, so the name keeps the wide column, set in poster type.
  private func drawPrismPrimaryHeader() {
    drawText(
      displayName,
      rect: CGRect(x: bodyX, y: 30, width: bodyWidth, height: 40),
      font: boldFont(27),
      color: navy,
      lineHeight: 32
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: bodyX, y: 72, width: bodyWidth, height: 15),
      font: mediumFont(8.8),
      color: accent,
      lineHeight: 11,
      kern: 1.4
    )
    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: bodyX, y: 98, width: 54, height: 3))
  }

  /// The fine serif: wide letterspacing, an ornament rule, and not one pixel
  /// more — the letterhead the stationery shops sell by the thousand.
  private func drawAureliaPrimaryHeader() {
    // Tracked, but gently: past ~1.2 the PDF's text layer starts reading the
    // gaps as word breaks, and the name stops being searchable.
    drawText(
      displayName.uppercased(),
      rect: CGRect(x: margin, y: 28, width: contentWidth, height: 32),
      font: boldFont(22),
      color: charcoal,
      lineHeight: 27,
      alignment: .center,
      kern: 1.2
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: 64, width: contentWidth, height: 14),
      font: mediumFont(8.4),
      color: gray,
      lineHeight: 11,
      alignment: .center,
      kern: 2.6
    )

    // The ornament rule: hairline, diamond, hairline.
    let armWidth = (contentWidth - 26) / 2
    ruleGray.setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 91, width: armWidth, height: 0.6))
    rendererContext.cgContext.fill(
      CGRect(x: margin + contentWidth - armWidth, y: 91, width: armWidth, height: 0.6))
    drawDiamond(centeredAt: CGPoint(x: pageBounds.midX, y: 91.3), size: 6, color: accent)

    drawText(
      contactLine,
      rect: CGRect(x: margin, y: 104, width: contentWidth, height: 12),
      font: regularFont(8.4),
      color: charcoal,
      lineHeight: 10,
      alignment: .center
    )
  }

  /// The book serif on the dark sheet: a letterpress double rule in light ink,
  /// with the accent kept for the headline alone.
  private func drawNocturnePrimaryHeader() {
    drawText(
      displayName,
      rect: CGRect(x: margin, y: 28, width: contentWidth, height: 34),
      font: boldFont(25),
      color: .white,
      lineHeight: 29,
      alignment: .center,
      kern: 0.6
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: 66, width: contentWidth, height: 14),
      font: mediumFont(8.8),
      color: accent,
      lineHeight: 11,
      alignment: .center,
      kern: 2.4
    )
    UIColor(white: 1, alpha: 0.8).setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 92, width: contentWidth, height: 1))
    UIColor(white: 1, alpha: 0.35).setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: 96, width: contentWidth, height: 0.5))
    drawText(
      contactLine,
      rect: CGRect(x: margin, y: 106, width: contentWidth, height: 12),
      font: regularFont(8.4),
      color: UIColor(white: 0.75, alpha: 1),
      lineHeight: 10,
      alignment: .center
    )
  }

  /// The boardroom letterhead: a squared portrait on a navy band, the name in
  /// a book serif beside it. Initials fill the frame until a photo does.
  private func drawMonarchPrimaryHeader() {
    navy.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: 150))
    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 150, width: pageBounds.width, height: 3))

    drawPortrait(
      in: CGRect(x: margin, y: 28, width: 94, height: 94),
      ring: accent,
      ringWidth: 2.5,
      emptyFill: accent,
      emptyText: .white,
      shape: .rounded(6)
    )

    let textX = margin + 94 + 24
    let textWidth = pageBounds.width - textX - margin
    drawText(
      displayName,
      rect: CGRect(x: textX, y: 36, width: textWidth, height: 36),
      font: boldFont(25),
      color: .white,
      lineHeight: 30
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: textX, y: 76, width: textWidth, height: 15),
      font: mediumFont(8.8),
      color: accent,
      lineHeight: 11,
      kern: 1.8
    )
    drawContactStrip(
      x: textX, y: 108, color: UIColor.white.withAlphaComponent(0.85), iconColor: accent)
  }

  // MARK: - The art-led letterheads
  //
  // The five that reach for a picture rather than a rule: a disc off the corner,
  // a name half in outline, a title set up the spine, headings out in the margin,
  // and a masthead that carries the summary itself.
  //
  // Each grows with what it is given — a name that wraps, a summary that runs long
  // — so each measures where it finished and leaves the answer in
  // `measuredHeaderBottom` for `firstPageTop` to read.

  /// The eclipse: the accent as a disc bleeding off the corner, with the portrait
  /// inscribed in it like a moon. The name keeps the left of the sheet, and a
  /// faint halo carries the colour further down the page than the disc does.
  private func drawEclipsePrimaryHeader() {
    let centre = CGPoint(x: pageBounds.width - 34, y: 26)
    drawDisc(centre: centre, radius: 172, color: accent.withAlphaComponent(0.10))
    drawDisc(centre: centre, radius: 122, color: accent)

    // Tangent to the rim, so the portrait reads as sitting inside the colour
    // rather than clipped by it — and the initials, when there is no photo, are
    // set on the accent where white type carries.
    drawPortrait(
      in: CGRect(x: 462, y: 21, width: 104, height: 104),
      ring: .white,
      ringWidth: 3.5,
      emptyFill: UIColor.white.withAlphaComponent(0.20),
      emptyText: .white
    )

    let nameWidth: CGFloat = 320
    let nameHeight = measuredHeight(
      displayName, width: nameWidth, font: boldFont(30), lineHeight: 34)
    drawText(
      displayName,
      rect: CGRect(x: margin, y: 48, width: nameWidth, height: nameHeight),
      font: boldFont(30),
      color: charcoal,
      lineHeight: 34
    )

    let headlineY = 48 + nameHeight + 8
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: headlineY, width: nameWidth, height: 15),
      font: mediumFont(8.8),
      color: accent,
      lineHeight: 11,
      kern: 1.6
    )
    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: headlineY + 26, width: 44, height: 3))
    drawContactStrip(x: margin, y: headlineY + 46, color: charcoal, iconColor: accent)

    // The floor keeps the body clear of the halo, which reaches further down the
    // page than the disc it surrounds.
    measuredHeaderBottom = max(headlineY + 92, 214)
  }

  /// The outline: the forename set solid and the surname left hollow — stroked
  /// glyphs, no fill — with the rest of the page given over to air.
  private func drawContourPrimaryHeader() {
    let words = displayName.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    let forename = words.first.map(String.init) ?? displayName
    let surname = words.count > 1 ? String(words[1]) : ""

    let font = boldFont(33)
    let forenameWidth: CGFloat = 330
    let forenameHeight = measuredHeight(
      forename, width: forenameWidth, font: font, lineHeight: 37)
    drawText(
      forename,
      rect: CGRect(x: margin, y: 36, width: forenameWidth, height: forenameHeight),
      font: font,
      color: charcoal,
      lineHeight: 37
    )

    var nameBottom = 36 + forenameHeight
    if !surname.isEmpty {
      let surnameHeight = measuredHeight(
        surname, width: contentWidth, font: font, lineHeight: 37)
      drawOutlinedText(
        surname,
        rect: CGRect(x: margin, y: nameBottom + 2, width: contentWidth, height: surnameHeight),
        font: font,
        color: accent,
        lineHeight: 37
      )
      nameBottom += surnameHeight + 2
    }

    drawText(
      contactLine,
      rect: CGRect(x: pageBounds.width - margin - 210, y: 44, width: 210, height: 12),
      font: regularFont(8.4),
      color: gray,
      lineHeight: 10,
      alignment: .right
    )

    let headlineY = nameBottom + 14
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: headlineY, width: contentWidth, height: 15),
      font: mediumFont(8.6),
      color: gray,
      lineHeight: 11,
      kern: 2.4
    )

    // The hairline runs the measure; the accent takes only its first inch.
    ruleGray.setFill()
    rendererContext.cgContext.fill(
      CGRect(x: margin, y: headlineY + 25, width: contentWidth, height: 0.6))
    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: headlineY + 24, width: 46, height: 2.4))

    measuredHeaderBottom = headlineY + 50
  }

  /// The spine: the job title runs up a full-height band of colour — drawn as page
  /// furniture, so it is on every sheet — and the page beside it is left plain.
  private func drawAxisPrimaryHeader() {
    let nameWidth = bodyWidth - portraitGutter(112)
    let nameHeight = measuredHeight(
      displayName, width: nameWidth, font: boldFont(31), lineHeight: 35)
    drawText(
      displayName,
      rect: CGRect(x: bodyX, y: 46, width: nameWidth, height: nameHeight),
      font: boldFont(31),
      color: charcoal,
      lineHeight: 35
    )

    let barY = 46 + nameHeight + 14
    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: bodyX, y: barY, width: 64, height: 5))
    drawContactStrip(x: bodyX, y: barY + 20, color: charcoal, iconColor: accent)

    if showsPortrait {
      drawPortrait(
        in: CGRect(x: pageBounds.width - margin - 92, y: 42, width: 92, height: 92),
        ring: accent,
        ringWidth: 2.5,
        emptyFill: accent.withAlphaComponent(0.14),
        emptyText: accent,
        shape: .rounded(6)
      )
    }

    measuredHeaderBottom = max(barY + 60, 158)
  }

  /// The margins: the contact — or the portrait — sits in the gutter the section
  /// titles will hang in, and the name keeps to the measure of text beneath it.
  private func drawTerracePrimaryHeader() {
    var gutterY: CGFloat = 62
    if showsPortrait {
      drawPortrait(
        in: CGRect(x: margin, y: 38, width: 54, height: 54),
        ring: accent,
        ringWidth: 2,
        emptyFill: accent.withAlphaComponent(0.14),
        emptyText: accent
      )
      gutterY = 106
    } else {
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: margin, y: 44, width: 11, height: 11))
    }

    for detail in [document.personal.phone, document.personal.email] where !detail.isBlank {
      let height = measuredHeight(
        detail, width: headingGutter - 10, font: regularFont(7.8), lineHeight: 10.5)
      drawText(
        detail,
        rect: CGRect(x: margin, y: gutterY, width: headingGutter - 10, height: height),
        font: regularFont(7.8),
        color: gray,
        lineHeight: 10.5
      )
      gutterY += height + 5
    }

    let nameHeight = measuredHeight(
      displayName, width: bodyWidth, font: boldFont(27), lineHeight: 31)
    drawText(
      displayName,
      rect: CGRect(x: bodyX, y: 38, width: bodyWidth, height: nameHeight),
      font: boldFont(27),
      color: charcoal,
      lineHeight: 31
    )

    let headlineY = 38 + nameHeight + 8
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: bodyX, y: headlineY, width: bodyWidth, height: 15),
      font: mediumFont(8.4),
      color: accent,
      lineHeight: 11,
      kern: 2
    )
    charcoal.setFill()
    rendererContext.cgContext.fill(CGRect(x: bodyX, y: headlineY + 25, width: bodyWidth, height: 1))

    // Clear of both columns: the rule under the name, and whatever the gutter ran to.
    measuredHeaderBottom = max(headlineY + 47, gutterY + 16)
  }

  /// Vantage's summary, measured once. The panel's height, the body's first line
  /// and the decision below all have to agree on it.
  private lazy var heroProfileHeight: CGFloat = measuredHeight(
    document.professionalProfile.trimmingCharacters(in: .whitespacesAndNewlines),
    width: heroProfileWidth,
    font: regularFont(9.4),
    lineHeight: 13.6
  )

  private var heroProfileWidth: CGFloat { contentWidth - 66 }

  /// Whether the panel prints the summary at all. An essay would swallow the page,
  /// so past a sane depth it flows in the body as it does under every other
  /// template, and the panel shrinks back to being a letterhead.
  private var heroCarriesProfile: Bool {
    !document.professionalProfile.isBlank && heroProfileHeight <= 300
  }

  /// The hero: a full-bleed panel that carries the summary itself, the way a
  /// masthead carries a standfirst. The panel is only as deep as the words in it.
  private func drawVantagePrimaryHeader() {
    let nameWidth = contentWidth - portraitGutter(126)
    let nameHeight = measuredHeight(
      displayName, width: nameWidth, font: boldFont(31), lineHeight: 35)
    let headlineY = 44 + nameHeight + 6
    let ruleY = headlineY + 25
    let profileY = ruleY + 18
    let contactY = profileY + (heroCarriesProfile ? heroProfileHeight + 20 : 0)
    let panelHeight = contactY + 34

    charcoal.setFill()
    rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: panelHeight))
    accent.setFill()
    rendererContext.cgContext.fill(
      CGRect(x: 0, y: panelHeight, width: pageBounds.width, height: 4))

    drawText(
      displayName,
      rect: CGRect(x: margin, y: 44, width: nameWidth, height: nameHeight),
      font: boldFont(31),
      color: .white,
      lineHeight: 35
    )
    drawText(
      document.personal.headline.uppercased(),
      rect: CGRect(x: margin, y: headlineY, width: nameWidth, height: 15),
      font: mediumFont(9),
      color: accent,
      lineHeight: 11,
      kern: 1.8
    )
    accent.setFill()
    rendererContext.cgContext.fill(CGRect(x: margin, y: ruleY, width: 50, height: 3))

    if heroCarriesProfile {
      drawText(
        document.professionalProfile.trimmingCharacters(in: .whitespacesAndNewlines),
        rect: CGRect(x: margin, y: profileY, width: heroProfileWidth, height: heroProfileHeight),
        font: regularFont(9.4),
        color: UIColor(white: 1, alpha: 0.84),
        lineHeight: 13.6
      )
    }
    drawContactStrip(
      x: margin, y: contactY, color: UIColor.white.withAlphaComponent(0.88), iconColor: accent)

    if showsPortrait {
      drawPortrait(
        in: CGRect(x: pageBounds.width - margin - 96, y: 44, width: 96, height: 96),
        ring: accent,
        ringWidth: 2.5,
        emptyFill: accent,
        emptyText: .white,
        shape: .rounded(8)
      )
    }

    measuredHeaderBottom = panelHeight + 26
  }

  /// A disc, for the letterhead whose art is a circle rather than a band.
  private func drawDisc(centre: CGPoint, radius: CGFloat, color: UIColor) {
    color.setFill()
    rendererContext.cgContext.fillEllipse(
      in: CGRect(
        x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
  }

  /// A soft circle of light that fades to nothing at its rim: the glow the radial
  /// mastheads set behind the name. Its falloff is transparent, so it lifts colour
  /// off the paper without drawing a hard edge.
  private func drawRadialGlow(centre: CGPoint, radius: CGFloat, color: UIColor) {
    let context = rendererContext.cgContext
    guard
      let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray,
        locations: [0, 1]
      )
    else { return }
    context.saveGState()
    context.drawRadialGradient(
      gradient,
      startCenter: centre, startRadius: 0,
      endCenter: centre, endRadius: radius,
      options: []
    )
    context.restoreGState()
  }

  /// A hexagon on its point, for the monogram letterhead's mark.
  private func hexagonPath(centre: CGPoint, radius: CGFloat) -> UIBezierPath {
    let path = UIBezierPath()
    for corner in 0..<6 {
      let angle = CGFloat.pi / 3 * CGFloat(corner) - CGFloat.pi / 2
      let point = CGPoint(
        x: centre.x + radius * cos(angle), y: centre.y + radius * sin(angle))
      if corner == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.close()
    return path
  }

  /// Hollow type: the glyphs stroked and left unfilled. A *positive* stroke width
  /// is what tells TextKit to draw the outline alone — and the glyphs are still
  /// real text, so an outlined name is as searchable as a solid one.
  private func drawOutlinedText(
    _ text: String,
    rect: CGRect,
    font: UIFont,
    color: UIColor,
    lineHeight: CGFloat,
    strokeWidth: CGFloat = 2.2
  ) {
    let style = NSMutableParagraphStyle()
    style.minimumLineHeight = lineHeight
    style.maximumLineHeight = lineHeight
    style.lineBreakMode = .byWordWrapping
    NSAttributedString(
      string: text,
      attributes: [
        .font: font,
        .foregroundColor: UIColor.clear,
        .strokeColor: color,
        .strokeWidth: strokeWidth,
        .paragraphStyle: style,
      ]
    ).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
  }

  /// Type set up the page — the spine of the sheet, read from the foot to the head.
  /// `x` is the left edge of the band it runs in, `bottom` the baseline it starts
  /// from, and `length` how far up the page it may run.
  private func drawVerticalText(
    _ text: String,
    x: CGFloat,
    bottom: CGFloat,
    length: CGFloat,
    font: UIFont,
    color: UIColor,
    lineHeight: CGFloat,
    kern: CGFloat
  ) {
    let context = rendererContext.cgContext
    context.saveGState()
    // After the quarter turn the text's own x runs up the page and its y runs
    // across the band, so it can be drawn as though it were horizontal.
    context.translateBy(x: x, y: bottom)
    context.rotate(by: -.pi / 2)
    drawText(
      text,
      rect: CGRect(x: 0, y: 0, width: length, height: lineHeight + 2),
      font: font,
      color: color,
      lineHeight: lineHeight,
      alignment: .center,
      kern: kern
    )
    context.restoreGState()
  }

  private func drawDiamond(centeredAt centre: CGPoint, size: CGFloat, color: UIColor) {
    let path = UIBezierPath()
    path.move(to: CGPoint(x: centre.x, y: centre.y - size / 2))
    path.addLine(to: CGPoint(x: centre.x + size / 2, y: centre.y))
    path.addLine(to: CGPoint(x: centre.x, y: centre.y + size / 2))
    path.addLine(to: CGPoint(x: centre.x - size / 2, y: centre.y))
    path.close()
    color.setFill()
    path.fill()
  }

  /// The L-shaped crop marks the grid templates set at their corners.
  private func drawCornerTicks(around rect: CGRect, arm: CGFloat, thickness: CGFloat) {
    accent.setFill()
    let context = rendererContext.cgContext
    let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
      (rect.minX, rect.minY, 1, 1),
      (rect.maxX, rect.minY, -1, 1),
      (rect.minX, rect.maxY, 1, -1),
      (rect.maxX, rect.maxY, -1, -1),
    ]
    for (x, y, dx, dy) in corners {
      let originX = dx > 0 ? x : x - arm
      let originY = dy > 0 ? y : y - thickness
      context.fill(CGRect(x: originX, y: originY, width: arm, height: thickness))
      let verticalX = dx > 0 ? x : x - thickness
      let verticalY = dy > 0 ? y : y - arm
      context.fill(CGRect(x: verticalX, y: verticalY, width: thickness, height: arm))
    }
  }

  private func drawContinuationHeader() {
    if let style = template.advancedStyle {
      drawAdvancedContinuationHeader(style)
      return
    }
    switch template {
    case .portrait, .modern, .horizon:
      drawModernContinuationHeader()
    case .classic:
      drawClassicContinuationHeader()
    case .minimal:
      drawMinimalContinuationHeader()
    case .spotlight, .atelier, .canvas, .contemporary, .corporate, .elegant, .nordic, .creative,
      .technical, .compact, .academic, .timeline, .monochrome, .editorial, .beacon, .harbor,
      .bloom, .aurora, .slate, .onyx, .lumen, .cascade, .vector, .mosaic, .vertex, .meridian,
      .linen, .ledger, .quill, .atlas, .verso, .oxford, .chronicle, .gazette, .strata, .duo,
      .signal, .concise, .pivot, .noir, .gauge, .folio, .insignia, .marquee, .metro, .ivy,
      .crest, .geneva, .plinth, .stockholm, .tandem, .varsity, .laureate, .modena, .nova,
      .prism, .aurelia, .nocturne, .monarch, .eclipse, .contour, .axis, .terrace, .vantage:
      drawStyledContinuationHeader()
    default:
      break
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
    case .elegant, .academic, .editorial, .aurelia:
      ruleGray.setFill()
      rendererContext.cgContext.fill(CGRect(x: margin, y: 57, width: contentWidth, height: 0.7))
      accent.setFill()
      rendererContext.cgContext.fillEllipse(
        in: CGRect(x: pageBounds.midX - 2.5, y: 55, width: 5, height: 5))
      nameColor = charcoal
      pageColor = gray
    case .noir:
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: margin, y: 56, width: 44, height: 2))
      nameColor = .white
      pageColor = UIColor(white: 0.72, alpha: 1)
    case .nocturne:
      UIColor(white: 1, alpha: 0.35).setFill()
      rendererContext.cgContext.fill(CGRect(x: margin, y: 57, width: contentWidth, height: 0.6))
      drawDiamond(centeredAt: CGPoint(x: pageBounds.midX, y: 57.3), size: 5, color: accent)
      nameColor = .white
      pageColor = UIColor(white: 0.72, alpha: 1)
    case .nova:
      accent.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: 0, y: 0, width: pageBounds.width, height: headerHeight))
      navy.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: 0, y: headerHeight - 4, width: pageBounds.width, height: 4))
      nameColor = .white
      pageColor = .white
    case .gauge:
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: bodyX, y: 52, width: 40, height: 2))
      nameColor = navy
      pageColor = gray
    case .folio, .ivy, .laureate:
      charcoal.setFill()
      rendererContext.cgContext.fill(CGRect(x: margin, y: 56, width: contentWidth, height: 1))
      nameColor = charcoal
      pageColor = gray
    case .insignia:
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: margin, y: 18, width: 26, height: 26))
      drawText(
        document.initials,
        rect: CGRect(x: margin, y: 24, width: 26, height: 14),
        font: boldFont(10),
        color: .white,
        lineHeight: 12,
        alignment: .center
      )
      nameColor = navy
      pageColor = gray
    case .marquee:
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: margin, y: 52, width: 120, height: 4))
      nameColor = navy
      pageColor = gray
    case .metro, .crest, .monarch:
      navy.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: 0, y: 0, width: pageBounds.width, height: headerHeight))
      accent.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: 0, y: headerHeight - 4, width: pageBounds.width, height: 4))
      nameColor = .white
      pageColor = .white
    case .geneva, .varsity:
      ruleGray.setFill()
      rendererContext.cgContext.fill(CGRect(x: margin, y: 57, width: contentWidth, height: 0.7))
      nameColor = charcoal
      pageColor = gray
    case .plinth:
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: margin, y: 54, width: contentWidth, height: 2))
      nameColor = navy
      pageColor = gray
    case .nordic, .modena:
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: margin, y: 56, width: 70, height: 2))
      nameColor = navy
      pageColor = gray
    case .compact:
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: margin, y: 52, width: contentWidth, height: 3))
      nameColor = navy
      pageColor = gray
    case .aurora:
      drawGradientBand(
        CGRect(x: 0, y: 0, width: pageBounds.width, height: headerHeight),
        from: accent,
        to: navy
      )
      nameColor = .white
      pageColor = .white
    case .slate, .onyx:
      (template == .onyx ? UIColor(white: 0.07, alpha: 1) : charcoal).setFill()
      rendererContext.cgContext.fill(
        CGRect(x: 0, y: 0, width: pageBounds.width, height: headerHeight))
      accent.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: 0, y: headerHeight - 4, width: pageBounds.width, height: 4))
      nameColor = .white
      pageColor = .white
    case .beacon:
      accent.setFill()
      rendererContext.cgContext.fillEllipse(in: CGRect(x: margin, y: 22, width: 18, height: 18))
      nameColor = navy
      pageColor = gray
    case .harbor:
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: 6))
      nameColor = navy
      pageColor = gray
    case .bloom:
      let pill = UIBezierPath(
        roundedRect: CGRect(x: margin - 10, y: 14, width: 300, height: 36), cornerRadius: 18)
      accent.withAlphaComponent(0.1).setFill()
      pill.fill()
      nameColor = navy
      pageColor = accent
    case .vertex:
      let wedge = UIBezierPath()
      wedge.move(to: CGPoint(x: 0, y: 0))
      wedge.addLine(to: CGPoint(x: 34, y: 0))
      wedge.addLine(to: CGPoint(x: 0, y: 34))
      wedge.close()
      accent.setFill()
      wedge.fill()
      nameColor = navy
      pageColor = gray
    case .mosaic:
      accent.setFill()
      for index in 0..<3 {
        accent.withAlphaComponent(1 - CGFloat(index) * 0.3).setFill()
        rendererContext.cgContext.fill(
          CGRect(x: margin + CGFloat(index) * 14, y: 52, width: 10, height: 10))
      }
      nameColor = navy
      pageColor = gray
    case .cascade:
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: margin, y: 52, width: 120, height: 3))
      accent.withAlphaComponent(0.4).setFill()
      rendererContext.cgContext.fill(CGRect(x: margin, y: 58, width: 76, height: 3))
      nameColor = navy
      pageColor = gray
    case .vector:
      ruleGray.withAlphaComponent(0.5).setFill()
      for x in stride(from: margin, through: pageBounds.width - margin, by: 14) {
        rendererContext.cgContext.fillEllipse(in: CGRect(x: x, y: 54, width: 1.4, height: 1.4))
      }
      nameColor = navy
      pageColor = accent
    case .lumen:
      ruleGray.setFill()
      rendererContext.cgContext.fill(CGRect(x: margin, y: 57, width: contentWidth, height: 0.6))
      nameColor = charcoal
      pageColor = gray
    case .meridian:
      ruleGray.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: 48, y: 57, width: pageBounds.width - margin - 48, height: 0.7))
      nameColor = charcoal
      pageColor = gray
    case .linen:
      accent.withAlphaComponent(0.07).setFill()
      rendererContext.cgContext.fill(
        CGRect(x: 0, y: 0, width: pageBounds.width, height: headerHeight))
      nameColor = charcoal
      pageColor = gray
    case .ledger:
      charcoal.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: margin + 8, y: 56, width: contentWidth - 16, height: 1))
      nameColor = charcoal
      pageColor = gray
    case .quill:
      charcoal.setFill()
      rendererContext.cgContext.fill(CGRect(x: margin, y: 56, width: contentWidth, height: 1.2))
      charcoal.withAlphaComponent(0.5).setFill()
      rendererContext.cgContext.fill(CGRect(x: margin, y: 60, width: contentWidth, height: 0.5))
      nameColor = charcoal
      pageColor = gray
    case .atlas, .oxford, .verso, .prism:
      // The band is page furniture and already runs the height of the page, so
      // the continuation header only has to name the column beside it.
      (sideColumn?.fill == .accent ? accent : navy).setFill()
      rendererContext.cgContext.fill(CGRect(x: bodyX, y: 52, width: 40, height: 2))
      nameColor = template == .oxford ? charcoal : navy
      pageColor = gray
    case .chronicle, .duo, .tandem:
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: margin, y: 54, width: contentWidth, height: 2))
      nameColor = navy
      pageColor = gray
    case .gazette:
      charcoal.setFill()
      rendererContext.cgContext.fill(CGRect(x: margin, y: 54, width: contentWidth, height: 1))
      nameColor = charcoal
      pageColor = gray
    case .strata, .signal, .stockholm:
      (template == .signal ? lightGray : accent.withAlphaComponent(0.07)).setFill()
      rendererContext.cgContext.fill(
        CGRect(x: 0, y: 0, width: pageBounds.width, height: headerHeight))
      accent.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: 0, y: headerHeight - 3, width: pageBounds.width, height: 3))
      nameColor = template == .stockholm ? charcoal : navy
      pageColor = gray
    case .concise:
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: margin, y: 46, width: contentWidth, height: 2.5))
      nameColor = navy
      pageColor = gray
    case .pivot:
      navy.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: 0, y: 0, width: pageBounds.width, height: headerHeight))
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: pageBounds.width, height: 5))
      nameColor = .white
      pageColor = .white
    case .vantage:
      // The hero panel, restated as a band: the page keeps its dark head.
      charcoal.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: 0, y: 0, width: pageBounds.width, height: headerHeight))
      accent.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: 0, y: headerHeight - 4, width: pageBounds.width, height: 4))
      nameColor = .white
      pageColor = UIColor(white: 1, alpha: 0.7)
    case .eclipse:
      // The disc, come round again — a quarter of it, off the corner.
      drawDisc(centre: CGPoint(x: pageBounds.width, y: 0), radius: 76, color: accent)
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: margin, y: 54, width: 44, height: 2.5))
      nameColor = charcoal
      pageColor = gray
    case .contour:
      ruleGray.setFill()
      rendererContext.cgContext.fill(CGRect(x: margin, y: 56, width: contentWidth, height: 0.6))
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: margin, y: 55, width: 46, height: 2.4))
      nameColor = charcoal
      pageColor = gray
    case .axis:
      // The spine is already page furniture; the header only has to name the page
      // beside it.
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: bodyX, y: 54, width: 44, height: 4))
      nameColor = charcoal
      pageColor = gray
    case .terrace:
      charcoal.setFill()
      rendererContext.cgContext.fill(CGRect(x: bodyX, y: 56, width: bodyWidth, height: 1))
      nameColor = charcoal
      pageColor = gray
    case .portrait, .spotlight, .atelier, .canvas, .modern, .classic, .minimal, .horizon:
      nameColor = navy
      pageColor = gray
    default:
      nameColor = headingInk
      pageColor = mutedInk
    }

    let isCentered = [.elegant, .academic, .linen, .ledger, .harbor, .ivy, .laureate, .aurelia,
      .nocturne].contains(template)
    let nameX: CGFloat =
      switch template {
      case .timeline: 53
      case .meridian: 48
      case .beacon: margin + 26
      case .vertex: margin + 12
      case .insignia: margin + 36
      // Clear of the band running down the page.
      case .atlas, .oxford, .axis: bodyX
      default: margin
      }
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
    // The plinth: the contact strip lives in a colour band along the foot of
    // every page, which is the whole idea of the template.
    if template == .plinth {
      accent.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: 0, y: 810, width: pageBounds.width, height: pageBounds.height - 810))
      drawText(
        displayName.uppercased(),
        rect: CGRect(x: margin, y: 820, width: 142, height: 11),
        font: mediumFont(7.5),
        color: .white,
        lineHeight: 9
      )
      drawContactStrip(x: 208, y: 821, color: .white, iconColor: .white)
      drawText(
        "\(pageNumber)",
        rect: CGRect(x: 535, y: 820, width: 26, height: 10),
        font: mediumFont(7.5),
        color: .white,
        lineHeight: 9,
        alignment: .right
      )
      return
    }

    // A full-height spine would swallow the footer, so the templates that draw
    // one start their footer clear of it.
    let footerX = plan.bodyInset > 0 ? bodyX : margin
    let name = document.personal.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
    drawText(
      name.isEmpty ? "RESUME STUDIO" : "\(name.uppercased())  |  RESUME",
      rect: CGRect(x: footerX, y: 819, width: 390, height: 10),
      font: mediumFont(7),
      color: mutedInk,
      lineHeight: 9
    )
    drawText(
      "\(pageNumber)",
      rect: CGRect(x: 535, y: 819, width: 26, height: 10),
      font: mediumFont(7),
      color: mutedInk,
      lineHeight: 9,
      alignment: .right
    )
  }

  private func drawProfessionalProfile() {
    let profile = document.professionalProfile.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !profile.isEmpty else { return }

    drawSectionTitle(heading(.profile))
    let height = measuredHeight(
      profile,
      width: bodyWidth,
      font: regularFont(9.3),
      lineHeight: 12.5
    )
    ensureSpace(height + 13)
    drawText(
      profile,
      rect: CGRect(x: bodyX, y: cursorY, width: bodyWidth, height: height),
      font: regularFont(9.3),
      color: ink,
      lineHeight: 12.5
    )
    cursorY += height + 13
  }

  private func drawCompetencies() {
    let items = document.competencies
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard !items.isEmpty else { return }

    switch plan.competencies {
    case .chips:
      drawSectionTitle(heading(.competencies))
      let height = chipsHeight(items, width: bodyWidth)
      ensureSpace(height + 12, continuationTitle: continuedHeading(.competencies))
      drawChips(items, x: bodyX, y: cursorY, width: bodyWidth)
      cursorY += height + 12
      return
    case .iconGrid:
      drawSectionTitle(heading(.competencies))
      drawCompetencyGrid(items)
      return
    case .meters:
      drawSectionTitle(heading(.competencies))
      drawCompetencyMeters(items)
      return
    case .dots:
      drawSectionTitle(heading(.competencies))
      drawCompetencyDots(items)
      return
    case .columns:
      drawSectionTitle(heading(.competencies))
      drawCompetencyColumns(items)
      return
    case .bullets:
      break
    }

    drawSectionTitle(heading(.competencies))
    let gap: CGFloat = 18
    let columnWidth = (bodyWidth - gap) / 2

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
      ensureSpace(rowHeight, continuationTitle: continuedHeading(.competencies))

      drawCompactBullet(left, x: bodyX, y: cursorY, width: columnWidth, height: leftHeight)
      if let right {
        drawCompactBullet(
          right,
          x: bodyX + columnWidth + gap,
          y: cursorY,
          width: columnWidth,
          height: rightHeight
        )
      }
      cursorY += rowHeight
    }
    cursorY += 8
  }

  /// The skills matrix: ticked, two across.
  private func drawCompetencyGrid(_ items: [String]) {
    let gap: CGFloat = 16
    let columnWidth = (bodyWidth - gap) / 2

    for index in stride(from: 0, to: items.count, by: 2) {
      let pair = [items[index], index + 1 < items.count ? items[index + 1] : nil]
      let heights = pair.map { item in
        item.map {
          measuredHeight($0, width: columnWidth - 16, font: regularFont(8.8), lineHeight: 11)
        } ?? 0
      }
      let rowHeight = max(heights[0], heights[1]) + 8
      ensureSpace(rowHeight, continuationTitle: continuedHeading(.competencies))

      for (column, item) in pair.enumerated() {
        guard let item else { continue }
        let x = bodyX + CGFloat(column) * (columnWidth + gap)
        drawIcon(
          "checkmark.seal.fill",
          in: CGRect(x: x, y: cursorY + 0.5, width: 9.5, height: 9.5),
          color: accent
        )
        drawText(
          item,
          rect: CGRect(x: x + 16, y: cursorY, width: columnWidth - 16, height: heights[column]),
          font: regularFont(8.8),
          color: ink,
          lineHeight: 11
        )
      }
      cursorY += rowHeight
    }
    cursorY += 8
  }

  /// The ranked bars, two across.
  private func drawCompetencyMeters(_ items: [String]) {
    let gap: CGFloat = 18
    let columnWidth = (bodyWidth - gap) / 2

    for rowStart in stride(from: 0, to: items.count, by: 2) {
      let rowItems = (rowStart..<min(rowStart + 2, items.count)).map { ($0, items[$0]) }
      let rowHeight = rowItems.map { meterHeight($0.1, width: columnWidth) }.max() ?? 0
      ensureSpace(rowHeight + 8, continuationTitle: continuedHeading(.competencies))
      for (column, entry) in rowItems.enumerated() {
        drawMeter(
          entry.1,
          index: entry.0,
          x: bodyX + CGFloat(column) * (columnWidth + gap),
          y: cursorY,
          width: columnWidth,
          ink: ink,
          track: accent.withAlphaComponent(0.16),
          fill: accent
        )
      }
      cursorY += rowHeight + 8
    }
    cursorY += 6
  }

  /// Three across, plain type: the compact list the ATS guides recommend.
  private func drawCompetencyColumns(_ items: [String]) {
    let gap: CGFloat = 14
    let columnWidth = (bodyWidth - gap * 2) / 3

    for rowStart in stride(from: 0, to: items.count, by: 3) {
      let rowItems = Array(items[rowStart..<min(rowStart + 3, items.count)])
      let heights = rowItems.map {
        measuredHeight($0, width: columnWidth, font: regularFont(8.8), lineHeight: 11)
      }
      let rowHeight = (heights.max() ?? 0) + 5
      ensureSpace(rowHeight, continuationTitle: continuedHeading(.competencies))
      for (column, item) in rowItems.enumerated() {
        drawText(
          item,
          rect: CGRect(
            x: bodyX + CGFloat(column) * (columnWidth + gap),
            y: cursorY,
            width: columnWidth,
            height: heights[column]
          ),
          font: regularFont(8.8),
          color: ink,
          lineHeight: 11
        )
      }
      cursorY += rowHeight
    }
    cursorY += 8
  }

  /// Dot ratings, two across. The rank is the position in the list, exactly as
  /// the meters read it, drawn as five beads filled to that level.
  private func drawCompetencyDots(_ items: [String]) {
    let gap: CGFloat = 18
    let columnWidth = (bodyWidth - gap) / 2
    for rowStart in stride(from: 0, to: items.count, by: 2) {
      let rowItems = (rowStart..<min(rowStart + 2, items.count)).map { ($0, items[$0]) }
      let rowHeight: CGFloat = 20
      ensureSpace(rowHeight, continuationTitle: continuedHeading(.competencies))
      for (column, entry) in rowItems.enumerated() {
        drawDotRating(
          entry.1, index: entry.0,
          x: bodyX + CGFloat(column) * (columnWidth + gap), y: cursorY, width: columnWidth,
          textInk: ink, fill: accent, empty: accent.withAlphaComponent(0.18))
      }
      cursorY += rowHeight
    }
    cursorY += 6
  }

  @discardableResult
  private func drawDotRating(
    _ item: String, index: Int, x: CGFloat, y: CGFloat, width: CGFloat,
    textInk: UIColor, fill: UIColor, empty: UIColor
  ) -> CGFloat {
    let dots = 5
    let dotDiameter: CGFloat = 6
    let dotGap: CGFloat = 4
    let dotsWidth = CGFloat(dots) * dotDiameter + CGFloat(dots - 1) * dotGap
    let labelWidth = width - dotsWidth - 8
    let labelHeight = max(
      measuredHeight(item, width: labelWidth, font: regularFont(8.4), lineHeight: 10.6), 11)
    drawText(
      item, rect: CGRect(x: x, y: y, width: labelWidth, height: labelHeight),
      font: regularFont(8.4), color: textInk, lineHeight: 10.6)
    let filled = max(1, min(dots, Int((meterLevel(index) * CGFloat(dots)).rounded())))
    let context = rendererContext.cgContext
    let dotsX = x + width - dotsWidth
    for dot in 0..<dots {
      (dot < filled ? fill : empty).setFill()
      context.fillEllipse(
        in: CGRect(
          x: dotsX + CGFloat(dot) * (dotDiameter + dotGap), y: y + 1.5,
          width: dotDiameter, height: dotDiameter))
    }
    return labelHeight
  }

  private func drawExperience() {
    let entries = document.experience.filter {
      !$0.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !$0.company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    guard !entries.isEmpty else { return }

    // The heading travels with the first role.
    let first = entries[0]
    let firstHeight =
      measuredHeight(first.role, width: bodyWidth - entryInset, font: boldFont(11.2), lineHeight: 14)
      + (first.highlights.first.map {
        measuredHeight(
          $0, width: bodyWidth - entryInset - 18, font: regularFont(8.8), lineHeight: 11.2)
      } ?? 0) + 30
    ensureSpace(sectionTitleAllowance + firstHeight, continuationTitle: nil)

    drawSectionTitle(heading(.experience))

    if plan.experience == .timeline {
      railY = cursorY
    }
    for entry in entries {
      drawExperienceEntry(entry)
    }
    if plan.experience == .timeline {
      extendRail(to: cursorY - 6)
      railY = nil
    }
  }

  /// The rail is drawn behind the roles as the cursor passes them, so a page
  /// break simply starts a new segment rather than leaving a line to nowhere.
  private func extendRail(to y: CGFloat) {
    guard let start = railY, y > start else { return }
    accent.withAlphaComponent(0.3).setFill()
    rendererContext.cgContext.fill(
      CGRect(x: bodyX + 4.5, y: start, width: 1.5, height: y - start))
    railY = y
  }

  private func drawExperienceEntry(_ entry: ExperienceEntry) {
    let highlights = entry.highlights
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    let role = entry.role.trimmingCharacters(in: .whitespacesAndNewlines)
    let period = entry.period.trimmingCharacters(in: .whitespacesAndNewlines)
    let company = entry.company.trimmingCharacters(in: .whitespacesAndNewlines)

    // With the dates hanging in the margin, repeating them on the metadata line
    // would just be saying it twice.
    let usesGutter = plan.experience == .dateGutter
    let metadata =
      usesGutter
      ? company
      : [company, period].filter { !$0.isEmpty }.joined(separator: "  |  ")

    let inset = entryInset
    let entryX = bodyX + inset
    let entryWidth = bodyWidth - inset - (plan.sectionChrome == .card ? 13 : 0)

    let roleHeight = measuredHeight(role, width: entryWidth, font: boldFont(11.2), lineHeight: 14)
    let metaHeight = measuredHeight(
      metadata, width: entryWidth, font: mediumFont(8.6), lineHeight: 11)
    let bulletHeights = highlights.map {
      measuredHeight($0, width: entryWidth - 18, font: regularFont(8.8), lineHeight: 11.2)
    }

    // A card has to be sure of its whole height before it can draw its border, so
    // it claims the room for the entire entry up front. Anything too tall to fit
    // on a page of its own falls back to flowing, rather than being cut in half.
    let bodyHeight =
      roleHeight + 2 + (metadata.isEmpty ? 0 : metaHeight + 6)
      + bulletHeights.reduce(0) { $0 + $1 + 4 }
    let cardHeight = bodyHeight + 20
    let drawsCard = plan.sectionChrome == .card && cardHeight < footerTop - continuationTop

    if drawsCard {
      ensureSpace(cardHeight + 8, continuationTitle: continuedHeading(.experience))
      let card = CGRect(x: bodyX, y: cursorY, width: bodyWidth, height: cardHeight)
      let path = UIBezierPath(roundedRect: card, cornerRadius: 8)
      accent.withAlphaComponent(0.045).setFill()
      path.fill()
      accent.withAlphaComponent(0.3).setStroke()
      path.lineWidth = 0.7
      path.stroke()
      cursorY += 10
    } else {
      let brokeBeforeEntry = ensureSpace(
        roleHeight + metaHeight + (bulletHeights.first ?? 0) + 24,
        continuationTitle: continuedHeading(.experience)
      )
      if brokeBeforeEntry {
        cursorY += 1
      }
    }

    if plan.experience == .timeline {
      // The stop on the rail. Drawn over a paper-coloured disc so the rail does
      // not show through the middle of it.
      paper.setFill()
      rendererContext.cgContext.fillEllipse(
        in: CGRect(x: bodyX - 0.75, y: cursorY + 1.5, width: 12, height: 12))
      accent.setFill()
      rendererContext.cgContext.fillEllipse(
        in: CGRect(x: bodyX + 0.75, y: cursorY + 3.5, width: 9, height: 9))
    }

    if usesGutter, !period.isEmpty {
      drawText(
        period,
        rect: CGRect(x: bodyX, y: cursorY + 2, width: 84, height: 26),
        font: mediumFont(8.4),
        color: accent,
        lineHeight: 11,
        alignment: .right
      )
    }

    drawText(
      role,
      rect: CGRect(x: entryX, y: cursorY, width: entryWidth, height: roleHeight),
      font: boldFont(11.2),
      color: headingInk,
      lineHeight: 14
    )
    cursorY += roleHeight + 2

    if !metadata.isEmpty {
      drawText(
        metadata,
        rect: CGRect(x: entryX, y: cursorY, width: entryWidth, height: metaHeight),
        font: mediumFont(8.6),
        color: mutedInk,
        lineHeight: 11
      )
      cursorY += metaHeight + 6
    }

    for (highlight, height) in zip(highlights, bulletHeights) {
      let brokeInsideEntry =
        drawsCard
        ? false
        : ensureSpace(height + 5, continuationTitle: continuedHeading(.experience))
      if brokeInsideEntry {
        if plan.experience == .timeline {
          railY = cursorY
        }
        let continued = role.isEmpty ? "Experience Continued" : "\(role) - Continued"
        let continuedHeight = measuredHeight(
          continued,
          width: entryWidth,
          font: boldFont(10.5),
          lineHeight: 13
        )
        drawText(
          continued,
          rect: CGRect(x: entryX, y: cursorY, width: entryWidth, height: continuedHeight),
          font: boldFont(10.5),
          color: headingInk,
          lineHeight: 13
        )
        cursorY += continuedHeight + 7
      }
      drawBullet(highlight, height: height, x: entryX, width: entryWidth)
    }

    cursorY += drawsCard ? 18 : 11
    if plan.experience == .timeline {
      extendRail(to: cursorY - 6)
    }
  }

  /// How far the roles are set in from the edge of the column: room for the rail,
  /// the margin dates, or the card's padding.
  private var entryInset: CGFloat {
    switch plan.experience {
    case .timeline: 22
    case .dateGutter: 100
    case .stacked: plan.sectionChrome == .card ? 13 : 0
    }
  }

  private func drawEducation() {
    let entries = document.education.filter {
      !$0.qualification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !$0.institution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    guard !entries.isEmpty else { return }

    // The heading travels with the first qualification, for the same reason the
    // references' heading travels with the first card.
    let firstEntry = entries[0]
    let firstHeight =
      measuredHeight(
        firstEntry.qualification, width: bodyWidth - 26, font: boldFont(10), lineHeight: 12.5)
      + measuredHeight(
        firstEntry.institution, width: bodyWidth - 26, font: mediumFont(8.5), lineHeight: 10.5)
      + 16
    ensureSpace(sectionTitleAllowance + firstHeight, continuationTitle: nil)
    drawSectionTitle(heading(.education))

    // The margin dates and the cards apply here too, so a template holds its
    // shape all the way down the page rather than only through the roles.
    let usesGutter = plan.experience == .dateGutter
    let cardPadding: CGFloat = plan.sectionChrome == .card ? 13 : 0
    let inset: CGFloat = usesGutter ? 100 : cardPadding
    let entryX = bodyX + inset
    let entryWidth = bodyWidth - inset - cardPadding

    for entry in entries {
      let qualification = entry.qualification.trimmingCharacters(in: .whitespacesAndNewlines)
      let period = entry.period.trimmingCharacters(in: .whitespacesAndNewlines)
      let institutionLine =
        usesGutter
        ? entry.institution.trimmingCharacters(in: .whitespacesAndNewlines)
        : [entry.institution, entry.period]
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }
          .joined(separator: "  |  ")
      let details = entry.details.trimmingCharacters(in: .whitespacesAndNewlines)

      let qualificationHeight = measuredHeight(
        qualification,
        width: entryWidth,
        font: boldFont(10),
        lineHeight: 12.5
      )
      let institutionHeight = measuredHeight(
        institutionLine,
        width: entryWidth,
        font: mediumFont(8.5),
        lineHeight: 10.5
      )
      let detailsHeight =
        details.isEmpty
        ? 0
        : measuredHeight(
          details,
          width: entryWidth,
          font: regularFont(8.5),
          lineHeight: 11
        )
      let entryHeight = qualificationHeight + institutionHeight + detailsHeight + 16
      ensureSpace(entryHeight, continuationTitle: continuedHeading(.education))

      if plan.sectionChrome == .card {
        let card = CGRect(x: bodyX, y: cursorY - 8, width: bodyWidth, height: entryHeight + 4)
        let path = UIBezierPath(roundedRect: card, cornerRadius: 8)
        accent.withAlphaComponent(0.045).setFill()
        path.fill()
        accent.withAlphaComponent(0.3).setStroke()
        path.lineWidth = 0.7
        path.stroke()
      }

      if usesGutter, !period.isEmpty {
        drawText(
          period,
          rect: CGRect(x: bodyX, y: cursorY + 1, width: 84, height: 24),
          font: mediumFont(8.4),
          color: accent,
          lineHeight: 11,
          alignment: .right
        )
      }

      drawText(
        qualification,
        rect: CGRect(x: entryX, y: cursorY, width: entryWidth, height: qualificationHeight),
        font: boldFont(10),
        color: headingInk,
        lineHeight: 12.5
      )
      cursorY += qualificationHeight + 2
      drawText(
        institutionLine,
        rect: CGRect(x: entryX, y: cursorY, width: entryWidth, height: institutionHeight),
        font: mediumFont(8.5),
        color: mutedInk,
        lineHeight: 10.5
      )
      cursorY += institutionHeight + 3

      if !details.isEmpty {
        drawText(
          details,
          rect: CGRect(x: entryX, y: cursorY, width: entryWidth, height: detailsHeight),
          font: regularFont(8.5),
          color: ink,
          lineHeight: 11
        )
        cursorY += detailsHeight + 3
      }
      cursorY += plan.sectionChrome == .card ? 16 : 8
    }
  }

  private func drawReferences() {
    let references = document.references.filter {
      !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    guard !references.isEmpty else { return }

    let gap: CGFloat = 14
    let cardWidth = (bodyWidth - gap) / 2
    let cardHeight: CGFloat = 112

    // Room for the heading *and* the first row of cards. Asking only for the
    // heading leaves it stranded at the foot of the page with its content
    // starting, "continued", on the next one.
    ensureSpace(sectionTitleAllowance + cardHeight + 10, continuationTitle: nil)
    drawSectionTitle(heading(.references))

    for index in stride(from: 0, to: references.count, by: 2) {
      ensureSpace(cardHeight + 10, continuationTitle: continuedHeading(.references))
      drawReferenceCard(
        references[index], x: bodyX, y: cursorY, width: cardWidth, height: cardHeight)
      if index + 1 < references.count {
        drawReferenceCard(
          references[index + 1],
          x: bodyX + cardWidth + gap,
          y: cursorY,
          width: cardWidth,
          height: cardHeight
        )
      }
      cursorY += cardHeight + 10
    }
  }

  /// The room a section heading needs. Every style of heading is within a few
  /// points of this, and it is only ever used to decide whether one still fits.
  private var sectionTitleAllowance: CGFloat { 34 }

  private func heading(_ block: ResumeContentBlock) -> String {
    document.layout.heading(for: block)
  }

  private func continuedHeading(_ block: ResumeContentBlock) -> String {
    "\(heading(block)) - Continued"
  }

  private func drawAdditionalSections() {
    for section in document.additionalSections {
      let title = section.title.trimmingCharacters(in: .whitespacesAndNewlines)
      let items = section.items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
      guard !title.isEmpty, !items.isEmpty else { continue }

      let firstItemHeight = measuredHeight(
        items[0], width: bodyWidth - 18, font: regularFont(8.8), lineHeight: 11.2)
      ensureSpace(sectionTitleAllowance + firstItemHeight + 5, continuationTitle: nil)
      drawSectionTitle(title)
      for item in items {
        let height = measuredHeight(
          item, width: bodyWidth - 18, font: regularFont(8.8), lineHeight: 11.2)
        ensureSpace(height + 5, continuationTitle: "\(title) - Continued")
        drawBullet(item, height: height)
      }
      cursorY += 8
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
    case .noir, .nocturne:
      // A lighter panel on the dark paper, edged in the accent.
      faintFill.setFill()
      rendererContext.cgContext.fill(cardRect)
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: x, y: y, width: width, height: 2.5))
    case .atelier, .portrait, .modern, .horizon, .aurora, .beacon, .cascade, .marquee:
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
    case .minimal, .lumen, .atlas, .verso, .oxford, .duo, .concise, .gauge, .geneva, .insignia,
      .stockholm, .tandem, .varsity, .modena, .contour, .terrace:
      UIColor.white.setFill()
      rendererContext.cgContext.fill(cardRect)
      accent.withAlphaComponent(0.1).setFill()
      rendererContext.cgContext.fill(CGRect(x: x, y: y, width: width, height: 28))
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: x, y: y, width: 3, height: height))
    case .contemporary, .crest, .prism:
      accent.withAlphaComponent(0.09).setFill()
      rendererContext.cgContext.fill(cardRect)
      navy.setFill()
      rendererContext.cgContext.fill(CGRect(x: x, y: y, width: 8, height: height))
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: x + 8, y: y, width: width - 8, height: 3))
    case .corporate, .slate, .onyx, .metro, .nova, .axis, .vantage:
      lightGray.setFill()
      rendererContext.cgContext.fill(cardRect)
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: x, y: y, width: width, height: 5))
      navy.setFill()
      rendererContext.cgContext.fill(CGRect(x: x, y: y + height - 2, width: width, height: 2))
    case .elegant, .academic, .editorial, .ledger, .linen, .quill, .gazette, .folio, .ivy,
      .laureate, .aurelia, .monarch:
      UIColor.white.setFill()
      rendererContext.cgContext.fill(cardRect)
      rendererContext.cgContext.setStrokeColor(charcoal.withAlphaComponent(0.55).cgColor)
      rendererContext.cgContext.setLineWidth(0.7)
      rendererContext.cgContext.stroke(cardRect.insetBy(dx: 0.5, dy: 0.5))
      rendererContext.cgContext.stroke(cardRect.insetBy(dx: 4, dy: 4))
      accent.setFill()
      rendererContext.cgContext.fillEllipse(
        in: CGRect(x: x + width / 2 - 3, y: y + 5, width: 6, height: 6))
    case .canvas, .spotlight, .nordic, .harbor, .bloom, .meridian, .chronicle, .eclipse:
      UIColor.white.setFill()
      rendererContext.cgContext.fill(cardRect)
      accent.withAlphaComponent(0.16).setFill()
      rendererContext.cgContext.fillEllipse(in: CGRect(x: x + 9, y: y + 11, width: 14, height: 14))
      ruleGray.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: x, y: y + height - 0.7, width: width, height: 0.7))
    case .creative, .vertex, .mosaic:
      accent.withAlphaComponent(0.12).setFill()
      rendererContext.cgContext.fill(cardRect)
      navy.setFill()
      rendererContext.cgContext.fill(CGRect(x: x + width - 26, y: y, width: 26, height: 26))
      accent.setFill()
      rendererContext.cgContext.fillEllipse(
        in: CGRect(x: x + width - 35, y: y + height - 24, width: 38, height: 38))
    case .technical, .vector, .signal:
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
    case .compact, .strata, .pivot, .plinth:
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
    case .apex, .aperture, .arclight, .blueprint, .catalyst, .circuit, .continuum, .district,
      .ember, .facet, .gallery, .halo, .helix, .kinetic, .lattice, .nexus, .orbit, .panorama,
      .quantum, .ribbon, .runway, .sentinel, .spectrum, .summit, .tessera, .vault, .wave,
      .zenith, .alcove, .sovereign, .palisade, .volta, .obsidian, .radiant, .verge, .datum,
      .pinnacle, .cobalt, .equinox, .mirage, .parallax, .emblem, .cadence, .citadel, .atrium,
      .zephyr, .cinder, .keystone, .loom, .graphite, .stratus, .vellum,
      .salute, .couture, .medallion, .sable, .terracotta, .lozenge, .circlet, .vogue, .signet,
      .almanac:
      if let style = template.advancedStyle {
        drawAdvancedReferenceCard(style, rect: cardRect)
      }
    }

    let isCentered = [
      .classic, .elegant, .academic, .editorial, .ledger, .linen, .quill, .harbor, .ivy,
      .laureate, .aurelia, .monarch,
    ]
    .contains(template)
    let insetX = isCentered ? x + 10 : x + 16
    let textWidth = isCentered ? width - 20 : width - 27
    let alignment: NSTextAlignment = isCentered ? .center : .left
    drawText(
      reference.name,
      rect: CGRect(x: insetX, y: y + 13, width: textWidth, height: 16),
      font: boldFont(10.2),
      color: headingInk,
      lineHeight: 13,
      alignment: alignment
    )
    drawText(
      reference.company,
      rect: CGRect(x: insetX, y: y + 31, width: textWidth, height: 14),
      font: mediumFont(8.3),
      color: mutedInk,
      lineHeight: 11,
      alignment: alignment
    )
    let labelColor = [.monochrome, .ivy].contains(template) ? ink : accent
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
      color: ink,
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
      color: ink,
      lineHeight: 9.5,
      alignment: alignment
    )
  }

  private func drawSectionTitle(_ title: String) {
    if cursorY + 30 > footerTop {
      beginPage(isFirst: false)
    }

    if let style = template.advancedStyle {
      drawAdvancedSectionTitle(title, style: style)
      return
    }

    switch template {
    case .portrait, .modern, .horizon:
      drawText(
        title.uppercased(),
        rect: CGRect(x: bodyX, y: cursorY, width: bodyWidth, height: 16),
        font: boldFont(11.2),
        color: accent,
        lineHeight: 14
      )
      navy.setStroke()
      let path = UIBezierPath()
      path.lineWidth = 0.7
      path.move(to: CGPoint(x: bodyX, y: cursorY + 21))
      path.addLine(to: CGPoint(x: bodyX + bodyWidth, y: cursorY + 21))
      path.stroke()
      cursorY += 29
    case .classic:
      drawText(
        title.uppercased(),
        rect: CGRect(x: bodyX, y: cursorY, width: bodyWidth, height: 17),
        font: boldFont(11),
        color: navy,
        lineHeight: 14,
        alignment: .center
      )
      accent.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: bodyX + (bodyWidth - 48) / 2, y: cursorY + 22, width: 48, height: 1.5)
      )
      cursorY += 31
    case .canvas, .spotlight, .minimal, .harbor, .atlas, .verso, .duo, .gauge, .insignia:
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: bodyX, y: cursorY + 1, width: 4, height: 15))
      drawText(
        title.uppercased(),
        rect: CGRect(x: bodyX + 12, y: cursorY, width: bodyWidth - 12, height: 17),
        font: boldFont(10.8),
        color: navy,
        lineHeight: 14
      )
      ruleGray.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: bodyX + 12, y: cursorY + 21, width: bodyWidth - 12, height: 0.6)
      )
      cursorY += 28
    case .terrace:
      // The heading steps out into the margin and the body starts level with it,
      // so the rule — which belongs to the text, not the heading — marks the
      // column the section actually occupies.
      ruleGray.setFill()
      rendererContext.cgContext.fill(CGRect(x: bodyX, y: cursorY, width: bodyWidth, height: 0.6))
      drawText(
        title.uppercased(),
        rect: CGRect(x: margin, y: cursorY + 8, width: headingGutter - 10, height: 30),
        font: boldFont(8.4),
        color: navy,
        lineHeight: 11,
        kern: 1.4
      )
      cursorY += 14
    case .atelier, .contemporary, .corporate, .elegant, .nordic, .creative, .technical,
      .compact, .academic, .timeline, .monochrome, .editorial, .beacon, .bloom, .aurora, .slate,
      .onyx, .lumen, .cascade, .vector, .mosaic, .vertex, .meridian, .linen, .ledger, .quill,
      .oxford, .chronicle, .gazette, .strata, .signal, .concise, .pivot, .noir, .folio,
      .marquee, .metro, .ivy, .crest, .geneva, .plinth, .stockholm, .tandem, .varsity,
      .laureate, .modena, .nova, .prism, .aurelia, .nocturne, .monarch, .eclipse, .contour,
      .axis, .vantage:
      drawStyledSectionTitle(title)
    default:
      break
    }
  }

  private func drawAdvancedSectionTitle(_ title: String, style: AdvancedResumeStyle) {
    if plan.hangingHeadings {
      hairlineInk.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: bodyX, y: cursorY, width: bodyWidth, height: 0.7))
      drawText(
        title.uppercased(),
        rect: CGRect(x: margin, y: cursorY + 6, width: headingGutter - 10, height: 30),
        font: boldFont(8.2),
        color: plan.darkPaper ? .white : headingInk,
        lineHeight: 10.5,
        kern: 1.2
      )
      cursorY += 14
      return
    }

    let shouldNumber = plan.numberedSections && !title.hasSuffix("Continued")
    if shouldNumber { sectionNumber += 1 }
    let number = String(format: "%02d", max(sectionNumber, 1))
    let titleColor = plan.darkPaper ? UIColor.white : headingInk

    switch style.variant {
    case 0:
      if plan.numberedSections {
        drawText(
          number,
          rect: CGRect(x: bodyX, y: cursorY - 1, width: 30, height: 22),
          font: boldFont(15),
          color: accent,
          lineHeight: 18
        )
      }
      let titleX = bodyX + (plan.numberedSections ? 36 : 0)
      drawText(
        title.uppercased(),
        rect: CGRect(x: titleX, y: cursorY + 2, width: bodyX + bodyWidth - titleX, height: 16),
        font: boldFont(10.5),
        color: titleColor,
        lineHeight: 13,
        kern: 0.9
      )
      accent.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: titleX, y: cursorY + 22, width: min(bodyX + bodyWidth - titleX, 88 + CGFloat(style.motif * 9)), height: 2.5))
      cursorY += 31
    case 1:
      let tabWidth: CGFloat = plan.numberedSections ? 44 : 16
      accent.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: bodyX, y: cursorY, width: tabWidth, height: 23))
      if plan.numberedSections {
        drawText(
          number,
          rect: CGRect(x: bodyX, y: cursorY + 4, width: tabWidth, height: 14),
          font: boldFont(9),
          color: .white,
          lineHeight: 11,
          alignment: .center
        )
      }
      accent.withAlphaComponent(0.10).setFill()
      rendererContext.cgContext.fill(
        CGRect(x: bodyX + tabWidth, y: cursorY, width: bodyWidth - tabWidth, height: 23))
      drawText(
        title.uppercased(),
        rect: CGRect(x: bodyX + tabWidth + 12, y: cursorY + 4, width: bodyWidth - tabWidth - 16, height: 15),
        font: boldFont(10),
        color: titleColor,
        lineHeight: 12
      )
      cursorY += 31
    case 2:
      let centreX = bodyMidX
      drawText(
        plan.numberedSections ? "\(number)  /  \(title.uppercased())" : title.uppercased(),
        rect: CGRect(x: bodyX, y: cursorY, width: bodyWidth, height: 16),
        font: mediumFont(9.4),
        color: titleColor,
        lineHeight: 12,
        alignment: .center,
        kern: 1.8
      )
      hairlineInk.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: bodyX, y: cursorY + 21, width: bodyWidth / 2 - 12, height: 0.7))
      rendererContext.cgContext.fill(
        CGRect(x: centreX + 12, y: cursorY + 21, width: bodyWidth / 2 - 12, height: 0.7))
      drawDiamond(centeredAt: CGPoint(x: centreX, y: cursorY + 21.3), size: 6, color: accent)
      cursorY += 30
    default:
      let titleText = plan.numberedSections ? "\(number)  \(title.uppercased())" : title.uppercased()
      drawText(
        titleText,
        rect: CGRect(x: bodyX + 18, y: cursorY, width: bodyWidth - 18, height: 17),
        font: boldFont(10.6),
        color: titleColor,
        lineHeight: 13
      )
      let marker = UIBezierPath()
      marker.move(to: CGPoint(x: bodyX, y: cursorY + 2))
      marker.addLine(to: CGPoint(x: bodyX + 11, y: cursorY + 8))
      marker.addLine(to: CGPoint(x: bodyX, y: cursorY + 14))
      marker.close()
      accent.setFill()
      marker.fill()
      hairlineInk.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: bodyX + 18, y: cursorY + 21, width: bodyWidth - 18, height: 0.7))
      cursorY += 30
    }
  }

  private func drawAdvancedReferenceCard(_ style: AdvancedResumeStyle, rect: CGRect) {
    let context = rendererContext.cgContext
    (plan.darkPaper ? faintFill : UIColor.white).setFill()
    context.fill(rect)
    switch style.variant {
    case 0:
      accent.setFill()
      context.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 4))
      accent.withAlphaComponent(0.08).setFill()
      context.fill(CGRect(x: rect.minX, y: rect.minY + 4, width: rect.width, height: 25))
    case 1:
      context.setStrokeColor(accent.withAlphaComponent(0.55).cgColor)
      context.setLineWidth(0.8)
      context.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
      drawCornerTicks(around: rect.insetBy(dx: 5, dy: 5), arm: 9, thickness: 1.2)
    case 2:
      context.setStrokeColor(hairlineInk.cgColor)
      context.setLineWidth(0.7)
      context.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
      accent.withAlphaComponent(0.16).setFill()
      context.fillEllipse(
        in: CGRect(x: rect.maxX - 32, y: rect.minY + 8, width: 19, height: 19))
    default:
      context.setStrokeColor((plan.darkPaper ? UIColor.white : headingInk).withAlphaComponent(0.48).cgColor)
      context.setLineWidth(0.7)
      context.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
      context.stroke(rect.insetBy(dx: 4.5, dy: 4.5))
      drawDiamond(
        centeredAt: CGPoint(x: rect.midX, y: rect.minY + 8),
        size: 6,
        color: accent
      )
    }
  }

  private func drawStyledSectionTitle(_ title: String) {
    switch template {
    case .contemporary, .pivot, .crest, .prism:
      accent.withAlphaComponent(0.12).setFill()
      rendererContext.cgContext.fill(CGRect(x: bodyX, y: cursorY, width: 192, height: 21))
      navy.setFill()
      rendererContext.cgContext.fill(CGRect(x: bodyX, y: cursorY, width: 5, height: 21))
      drawText(
        title.uppercased(),
        rect: CGRect(x: bodyX + 14, y: cursorY + 3, width: 174, height: 15),
        font: boldFont(10.2),
        color: navy,
        lineHeight: 12
      )
      cursorY += 29
    case .corporate:
      navy.setFill()
      rendererContext.cgContext.fill(CGRect(x: bodyX, y: cursorY, width: bodyWidth, height: 22))
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: bodyX, y: cursorY, width: 7, height: 22))
      drawText(
        title.uppercased(),
        rect: CGRect(x: bodyX + 16, y: cursorY + 4, width: bodyWidth - 20, height: 15),
        font: boldFont(10),
        color: .white,
        lineHeight: 12
      )
      cursorY += 31
    case .elegant, .editorial, .linen:
      drawText(
        title,
        rect: CGRect(x: bodyX, y: cursorY, width: bodyWidth, height: 18),
        font: boldFont(11.3),
        color: charcoal,
        lineHeight: 15,
        alignment: .center
      )
      ruleGray.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: bodyX, y: cursorY + 22, width: bodyWidth, height: 0.6))
      accent.setFill()
      rendererContext.cgContext.fillEllipse(
        in: CGRect(x: bodyMidX - 3, y: cursorY + 19, width: 6, height: 6))
      cursorY += 31
    case .nordic, .chronicle, .plinth, .stockholm, .vantage:
      drawText(
        title.uppercased(),
        rect: CGRect(x: bodyX, y: cursorY, width: bodyWidth, height: 16),
        font: boldFont(10.5),
        color: navy,
        lineHeight: 13
      )
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: bodyX, y: cursorY + 21, width: 68, height: 2))
      cursorY += 31
    case .eclipse:
      // The disc, in miniature, at the head of every section.
      accent.setFill()
      rendererContext.cgContext.fillEllipse(
        in: CGRect(x: bodyX, y: cursorY + 3, width: 9, height: 9))
      drawText(
        title.uppercased(),
        rect: CGRect(x: bodyX + 18, y: cursorY, width: bodyWidth - 18, height: 16),
        font: boldFont(10.6),
        color: navy,
        lineHeight: 13,
        kern: 0.8
      )
      ruleGray.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: bodyX + 18, y: cursorY + 21, width: bodyWidth - 18, height: 0.6))
      cursorY += 30
    case .noir:
      drawText(
        title.uppercased(),
        rect: CGRect(x: bodyX, y: cursorY, width: bodyWidth, height: 16),
        font: boldFont(10.6),
        color: .white,
        lineHeight: 13
      )
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: bodyX, y: cursorY + 21, width: 56, height: 2))
      cursorY += 31
    case .folio:
      // The counter. A continued section keeps its number rather than taking
      // the next one.
      if !title.hasSuffix("Continued") {
        sectionNumber += 1
      }
      drawText(
        String(format: "%02d", max(sectionNumber, 1)),
        rect: CGRect(x: bodyX, y: cursorY, width: 32, height: 20),
        font: boldFont(15),
        color: accent,
        lineHeight: 18
      )
      drawText(
        title.uppercased(),
        rect: CGRect(x: bodyX + 34, y: cursorY + 4, width: bodyWidth - 34, height: 16),
        font: boldFont(10.8),
        color: charcoal,
        lineHeight: 13,
        kern: 1.2
      )
      ruleGray.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: bodyX + 34, y: cursorY + 22, width: bodyWidth - 34, height: 0.6))
      cursorY += 31
    case .marquee, .nova, .axis:
      drawText(
        title.uppercased(),
        rect: CGRect(x: bodyX, y: cursorY, width: bodyWidth, height: 17),
        font: boldFont(12),
        color: navy,
        lineHeight: 15,
        kern: 0.6
      )
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: bodyX, y: cursorY + 21, width: 34, height: 4))
      cursorY += 32
    case .metro:
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: bodyX, y: cursorY, width: bodyWidth, height: 22))
      navy.setFill()
      rendererContext.cgContext.fill(CGRect(x: bodyX, y: cursorY, width: 6, height: 22))
      drawText(
        title.uppercased(),
        rect: CGRect(x: bodyX + 15, y: cursorY + 4, width: bodyWidth - 20, height: 15),
        font: boldFont(10),
        color: .white,
        lineHeight: 12
      )
      cursorY += 31
    case .ivy:
      drawText(
        title.uppercased(),
        rect: CGRect(x: bodyX, y: cursorY, width: bodyWidth, height: 16),
        font: boldFont(10.5),
        color: charcoal,
        lineHeight: 13,
        kern: 0.8
      )
      charcoal.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: bodyX, y: cursorY + 20, width: bodyWidth, height: 0.8))
      cursorY += 30
    case .atelier, .creative:
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: bodyX, y: cursorY, width: 29, height: 24))
      accent.withAlphaComponent(0.15).setFill()
      rendererContext.cgContext.fill(
        CGRect(x: bodyX + 29, y: cursorY, width: bodyWidth - 29, height: 24))
      drawText(
        title.uppercased(),
        rect: CGRect(x: bodyX + 41, y: cursorY + 4, width: bodyWidth - 48, height: 16),
        font: boldFont(10.5),
        color: navy,
        lineHeight: 13
      )
      cursorY += 32
    case .technical:
      drawText(
        "[ \(title.uppercased()) ]",
        rect: CGRect(x: bodyX, y: cursorY, width: bodyWidth, height: 16),
        font: boldFont(9.5),
        color: accent,
        lineHeight: 13
      )
      ruleGray.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: bodyX, y: cursorY + 21, width: bodyWidth, height: 0.6))
      cursorY += 28
    case .compact, .signal, .concise:
      drawText(
        title.uppercased(),
        rect: CGRect(x: bodyX, y: cursorY, width: 178, height: 15),
        font: boldFont(9.8),
        color: navy,
        lineHeight: 12
      )
      accent.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: bodyX + 184, y: cursorY + 7, width: bodyWidth - 184, height: 2))
      cursorY += 23
    case .academic, .ledger, .oxford, .gazette, .monarch:
      drawText(
        title.uppercased(),
        rect: CGRect(x: bodyX, y: cursorY, width: bodyWidth, height: 17),
        font: boldFont(10.8),
        color: charcoal,
        lineHeight: 14
      )
      charcoal.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: bodyX, y: cursorY + 21, width: bodyWidth, height: 1.3))
      ruleGray.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: bodyX, y: cursorY + 25, width: bodyWidth, height: 0.5))
      cursorY += 32
    case .beacon:
      let pill = UIBezierPath(
        roundedRect: CGRect(x: bodyX, y: cursorY, width: 208, height: 22), cornerRadius: 11)
      accent.setFill()
      pill.fill()
      drawText(
        title.uppercased(),
        rect: CGRect(x: bodyX + 16, y: cursorY + 4, width: 186, height: 15),
        font: boldFont(9.8),
        color: .white,
        lineHeight: 12
      )
      cursorY += 31
    case .bloom, .strata:
      let pill = UIBezierPath(
        roundedRect: CGRect(x: bodyX, y: cursorY, width: bodyWidth, height: 24),
        cornerRadius: 12)
      accent.withAlphaComponent(0.1).setFill()
      pill.fill()
      drawText(
        title.uppercased(),
        rect: CGRect(x: bodyX + 16, y: cursorY + 5, width: bodyWidth - 24, height: 15),
        font: boldFont(9.8),
        color: accent,
        lineHeight: 12
      )
      cursorY += 33
    case .aurora:
      drawText(
        title.uppercased(),
        rect: CGRect(x: bodyX, y: cursorY, width: bodyWidth, height: 16),
        font: boldFont(10.6),
        color: navy,
        lineHeight: 13
      )
      drawGradientBand(
        CGRect(x: bodyX, y: cursorY + 21, width: bodyWidth, height: 2),
        from: accent,
        to: navy.withAlphaComponent(0.15)
      )
      cursorY += 31
    case .slate:
      drawText(
        title.uppercased(),
        rect: CGRect(x: bodyX, y: cursorY, width: bodyWidth, height: 16),
        font: boldFont(10.2),
        color: accent,
        lineHeight: 13
      )
      charcoal.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: bodyX, y: cursorY + 21, width: bodyWidth, height: 1.2))
      cursorY += 30
    case .onyx:
      UIColor(white: 0.07, alpha: 1).setFill()
      rendererContext.cgContext.fill(CGRect(x: bodyX, y: cursorY + 2, width: 12, height: 12))
      drawText(
        title.uppercased(),
        rect: CGRect(x: bodyX + 20, y: cursorY, width: bodyWidth - 20, height: 16),
        font: boldFont(11),
        color: charcoal,
        lineHeight: 13
      )
      accent.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: bodyX, y: cursorY + 21, width: bodyWidth, height: 1.5))
      cursorY += 30
    case .lumen, .geneva, .contour:
      drawText(
        title.uppercased(),
        rect: CGRect(x: bodyX, y: cursorY, width: bodyWidth, height: 15),
        font: mediumFont(8.6),
        color: gray,
        lineHeight: 12,
        kern: 2.2
      )
      ruleGray.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: bodyX, y: cursorY + 19, width: bodyWidth, height: 0.5))
      cursorY += 28
    case .cascade:
      drawText(
        title.uppercased(),
        rect: CGRect(x: bodyX, y: cursorY, width: bodyWidth, height: 16),
        font: boldFont(10.5),
        color: navy,
        lineHeight: 13
      )
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: bodyX, y: cursorY + 21, width: 86, height: 2.5))
      accent.withAlphaComponent(0.35).setFill()
      rendererContext.cgContext.fill(CGRect(x: bodyX + 90, y: cursorY + 21, width: 48, height: 2.5))
      cursorY += 31
    case .vector:
      drawText(
        title.uppercased(),
        rect: CGRect(x: bodyX + 16, y: cursorY, width: bodyWidth - 16, height: 16),
        font: boldFont(10),
        color: navy,
        lineHeight: 13
      )
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: bodyX, y: cursorY + 3, width: 8, height: 8))
      ruleGray.withAlphaComponent(0.6).setFill()
      for x in stride(from: bodyX, through: bodyX + bodyWidth, by: 8) {
        rendererContext.cgContext.fill(CGRect(x: x, y: cursorY + 21, width: 3, height: 1))
      }
      cursorY += 29
    case .mosaic:
      for index in 0..<3 {
        accent.withAlphaComponent(1 - CGFloat(index) * 0.3).setFill()
        rendererContext.cgContext.fill(
          CGRect(x: bodyX + CGFloat(index) * 11, y: cursorY + 3, width: 8, height: 8))
      }
      drawText(
        title.uppercased(),
        rect: CGRect(x: bodyX + 42, y: cursorY, width: bodyWidth - 42, height: 16),
        font: boldFont(10.5),
        color: navy,
        lineHeight: 13
      )
      navy.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: bodyX, y: cursorY + 21, width: bodyWidth, height: 1.5))
      cursorY += 31
    case .vertex:
      let arrow = UIBezierPath()
      arrow.move(to: CGPoint(x: bodyX, y: cursorY + 2))
      arrow.addLine(to: CGPoint(x: bodyX + 11, y: cursorY + 8))
      arrow.addLine(to: CGPoint(x: bodyX, y: cursorY + 14))
      arrow.close()
      accent.setFill()
      arrow.fill()
      drawText(
        title.uppercased(),
        rect: CGRect(x: bodyX + 20, y: cursorY, width: bodyWidth - 20, height: 16),
        font: boldFont(10.5),
        color: navy,
        lineHeight: 13
      )
      navy.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: bodyX + 20, y: cursorY + 21, width: bodyWidth - 20, height: 1.5))
      cursorY += 31
    case .meridian:
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: bodyX, y: cursorY + 3, width: 9, height: 9))
      drawText(
        title,
        rect: CGRect(x: bodyX + 18, y: cursorY, width: bodyWidth - 18, height: 17),
        font: boldFont(11.2),
        color: charcoal,
        lineHeight: 14
      )
      ruleGray.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: bodyX + 18, y: cursorY + 22, width: bodyWidth - 18, height: 0.7))
      cursorY += 31
    case .quill:
      drawText(
        title,
        rect: CGRect(x: bodyX + 16, y: cursorY, width: bodyWidth - 16, height: 18),
        font: boldFont(11.4),
        color: charcoal,
        lineHeight: 15
      )
      drawDiamond(centeredAt: CGPoint(x: bodyX + 4, y: cursorY + 9), size: 7, color: accent)
      charcoal.withAlphaComponent(0.75).setFill()
      rendererContext.cgContext.fill(
        CGRect(x: bodyX, y: cursorY + 23, width: bodyWidth, height: 0.8))
      cursorY += 32
    case .timeline, .tandem:
      accent.withAlphaComponent(0.35).setFill()
      rendererContext.cgContext.fill(CGRect(x: bodyX + 6, y: cursorY, width: 2, height: 25))
      accent.setFill()
      rendererContext.cgContext.fillEllipse(
        in: CGRect(x: bodyX + 1, y: cursorY + 3, width: 12, height: 12))
      drawText(
        title.uppercased(),
        rect: CGRect(x: bodyX + 24, y: cursorY + 1, width: bodyWidth - 24, height: 16),
        font: boldFont(10.5),
        color: navy,
        lineHeight: 13
      )
      cursorY += 29
    case .varsity:
      drawText(
        title.uppercased(),
        rect: CGRect(x: bodyX, y: cursorY, width: bodyWidth, height: 15),
        font: boldFont(9.6),
        color: accent,
        lineHeight: 12,
        kern: 1.8
      )
      ruleGray.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: bodyX, y: cursorY + 19, width: bodyWidth, height: 0.6))
      cursorY += 27
    case .laureate:
      // The two-tone heading: the first word in the accent, the rest in ink.
      let words = title.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
      let lead = words.first.map { String($0).uppercased() } ?? title.uppercased()
      let rest = words.count > 1 ? "  " + String(words[1]).uppercased() : ""
      let leadAttributes = textAttributes(font: boldFont(11.2), color: accent, lineHeight: 14)
      NSAttributedString(string: lead, attributes: leadAttributes)
        .draw(at: CGPoint(x: bodyX, y: cursorY))
      if !rest.isEmpty {
        let leadWidth = singleLineWidth(lead, attributes: leadAttributes)
        drawText(
          rest,
          rect: CGRect(
            x: bodyX + leadWidth, y: cursorY, width: bodyWidth - leadWidth, height: 16),
          font: boldFont(11.2),
          color: charcoal,
          lineHeight: 14
        )
      }
      ruleGray.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: bodyX, y: cursorY + 21, width: bodyWidth, height: 0.8))
      cursorY += 30
    case .modena:
      // The margin box: a solid accent tab hanging at the head of the section.
      accent.setFill()
      rendererContext.cgContext.fill(CGRect(x: bodyX, y: cursorY + 2, width: 30, height: 14))
      drawText(
        title.uppercased(),
        rect: CGRect(x: bodyX + 40, y: cursorY + 2, width: bodyWidth - 40, height: 15),
        font: boldFont(10.2),
        color: navy,
        lineHeight: 13
      )
      ruleGray.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: bodyX + 40, y: cursorY + 21, width: bodyWidth - 40, height: 0.6))
      cursorY += 29
    case .aurelia:
      let attributes = textAttributes(
        font: mediumFont(9.2), color: charcoal, lineHeight: 12, kern: 3)
      drawText(
        title.uppercased(),
        rect: CGRect(x: bodyX, y: cursorY, width: bodyWidth, height: 15),
        font: mediumFont(9.2),
        color: charcoal,
        lineHeight: 12,
        alignment: .center,
        kern: 3
      )
      // Hairlines flank the words, the stationer's way.
      let titleWidth = singleLineWidth(title.uppercased(), attributes: attributes)
      let armWidth = max((bodyWidth - titleWidth - 36) / 2, 0)
      ruleGray.setFill()
      rendererContext.cgContext.fill(CGRect(x: bodyX, y: cursorY + 6, width: armWidth, height: 0.6))
      rendererContext.cgContext.fill(
        CGRect(x: bodyX + bodyWidth - armWidth, y: cursorY + 6, width: armWidth, height: 0.6))
      cursorY += 27
    case .nocturne:
      drawText(
        title.uppercased(),
        rect: CGRect(x: bodyX, y: cursorY, width: bodyWidth, height: 15),
        font: mediumFont(9.4),
        color: .white,
        lineHeight: 12,
        alignment: .center,
        kern: 2.6
      )
      UIColor(white: 1, alpha: 0.3).setFill()
      rendererContext.cgContext.fill(
        CGRect(x: bodyX, y: cursorY + 21, width: bodyWidth / 2 - 12, height: 0.5))
      rendererContext.cgContext.fill(
        CGRect(
          x: bodyX + bodyWidth / 2 + 12, y: cursorY + 21, width: bodyWidth / 2 - 12, height: 0.5))
      drawDiamond(
        centeredAt: CGPoint(x: bodyX + bodyWidth / 2, y: cursorY + 21.3), size: 5, color: accent)
      cursorY += 31
    case .monochrome:
      charcoal.setFill()
      rendererContext.cgContext.fill(CGRect(x: bodyX, y: cursorY, width: 182, height: 21))
      drawText(
        title.uppercased(),
        rect: CGRect(x: bodyX + 10, y: cursorY + 3, width: 168, height: 15),
        font: boldFont(9.8),
        color: .white,
        lineHeight: 12
      )
      charcoal.setFill()
      rendererContext.cgContext.fill(
        CGRect(x: bodyX + 190, y: cursorY + 10, width: bodyWidth - 190, height: 1))
      cursorY += 29
    // Drawn by `drawSectionTitle` itself, so they never arrive here.
    case .canvas, .portrait, .spotlight, .modern, .classic, .minimal, .horizon, .harbor,
      .atlas, .verso, .duo, .gauge, .insignia, .terrace:
      break
    default:
      break
    }
  }

  @discardableResult
  private func ensureSpace(_ requiredHeight: CGFloat, continuationTitle: String? = nil) -> Bool {
    guard cursorY + requiredHeight > footerTop else { return false }
    // Run the rail down to the foot of the page before leaving it, or it stops
    // dead in the middle of the column.
    extendRail(to: footerTop - 4)
    beginPage(isFirst: false)
    if let continuationTitle {
      drawSectionTitle(continuationTitle)
      if plan.experience == .timeline {
        railY = cursorY
      }
    }
    return true
  }

  private func drawBullet(_ text: String, height: CGFloat, x: CGFloat? = nil, width: CGFloat? = nil)
  {
    let bulletX = x ?? bodyX
    let bulletWidth = width ?? bodyWidth
    drawBulletMarker(x: bulletX, y: cursorY, compact: false)
    drawText(
      text,
      rect: CGRect(x: bulletX + 16, y: cursorY, width: bulletWidth - 16, height: height),
      font: regularFont(8.8),
      color: ink,
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
      color: ink,
      lineHeight: 11
    )
  }

  private func drawBulletMarker(x: CGFloat, y: CGFloat, compact: Bool) {
    let markerX = x + (compact ? 2 : 3)
    let markerY = y + (compact ? 3.5 : 4)
    ([.monochrome, .ivy].contains(template) ? ink : accent).setFill()

    if let style = template.advancedStyle {
      drawAdvancedBullet(style, x: markerX, y: markerY)
      return
    }

    switch template {
    case .portrait, .spotlight, .atelier, .canvas, .modern, .nordic, .horizon, .aurora, .harbor,
      .bloom, .cascade, .lumen, .beacon, .atlas, .verso, .chronicle, .duo, .signal, .pivot,
      .noir, .gauge, .insignia, .crest, .plinth, .stockholm, .tandem, .nova, .eclipse, .vantage:
      rendererContext.cgContext.fillEllipse(
        in: CGRect(x: markerX, y: markerY, width: 3.2, height: 3.2))
    case .contour:
      // Hollow, like the name.
      rendererContext.cgContext.setStrokeColor(accent.cgColor)
      rendererContext.cgContext.setLineWidth(1)
      rendererContext.cgContext.stroke(
        CGRect(x: markerX + 0.5, y: markerY + 0.5, width: 3.4, height: 3.4))
    case .classic, .elegant, .academic, .monochrome, .editorial, .linen, .ledger, .quill,
      .meridian, .oxford, .gazette, .folio, .ivy, .aurelia, .nocturne, .monarch:
      rendererContext.cgContext.fill(
        CGRect(x: markerX - 1, y: markerY + 1, width: 6, height: 1.4))
    case .minimal, .corporate, .technical, .compact, .slate, .onyx, .vector, .mosaic, .strata,
      .concise, .metro, .geneva, .varsity, .laureate, .modena, .axis, .terrace:
      rendererContext.cgContext.fill(
        CGRect(x: markerX, y: markerY, width: 3.5, height: 3.5))
    case .contemporary, .timeline:
      rendererContext.cgContext.fill(
        CGRect(x: markerX + 1, y: markerY - 1, width: 2, height: 6))
    case .creative, .vertex, .marquee, .prism:
      let path = UIBezierPath()
      path.move(to: CGPoint(x: markerX + 2, y: markerY - 1))
      path.addLine(to: CGPoint(x: markerX + 5, y: markerY + 2))
      path.addLine(to: CGPoint(x: markerX + 2, y: markerY + 5))
      path.addLine(to: CGPoint(x: markerX - 1, y: markerY + 2))
      path.close()
      path.fill()
    default:
      rendererContext.cgContext.fill(
        CGRect(x: markerX, y: markerY, width: 3.5, height: 3.5))
    }
  }

  private func drawAdvancedBullet(_ style: AdvancedResumeStyle, x: CGFloat, y: CGFloat) {
    let context = rendererContext.cgContext
    accent.setFill()
    switch style.motif % 4 {
    case 0:
      context.fillEllipse(in: CGRect(x: x, y: y, width: 4, height: 4))
      context.setStrokeColor(accent.withAlphaComponent(0.35).cgColor)
      context.setLineWidth(0.7)
      context.strokeEllipse(in: CGRect(x: x - 2, y: y - 2, width: 8, height: 8))
    case 1:
      context.fill(CGRect(x: x, y: y, width: 4, height: 4))
    case 2:
      let diamond = UIBezierPath()
      diamond.move(to: CGPoint(x: x + 2, y: y - 1))
      diamond.addLine(to: CGPoint(x: x + 5, y: y + 2))
      diamond.addLine(to: CGPoint(x: x + 2, y: y + 5))
      diamond.addLine(to: CGPoint(x: x - 1, y: y + 2))
      diamond.close()
      diamond.fill()
    default:
      context.fill(CGRect(x: x + 1, y: y - 1, width: 2, height: 6))
      context.fill(CGRect(x: x - 1, y: y + 1, width: 6, height: 2))
    }
  }

  private func drawText(
    _ text: String,
    rect: CGRect,
    font: UIFont,
    color: UIColor,
    lineHeight: CGFloat,
    alignment: NSTextAlignment = .left,
    kern: CGFloat = 0
  ) {
    let attributes = textAttributes(
      font: font,
      color: color,
      lineHeight: lineHeight,
      alignment: alignment,
      kern: kern
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
    alignment: NSTextAlignment = .left,
    kern: CGFloat = 0
  ) -> [NSAttributedString.Key: Any] {
    let style = NSMutableParagraphStyle()
    let effectiveLineHeight = lineHeight * CGFloat(document.layout.fontScale * document.layout.lineSpacing)
    style.minimumLineHeight = effectiveLineHeight
    style.maximumLineHeight = effectiveLineHeight
    style.lineBreakMode = .byWordWrapping
    style.alignment = alignment
    var attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: color,
      .paragraphStyle: style,
    ]
    if kern != 0 {
      attributes[.kern] = kern
    }
    return attributes
  }

  /// The typeface a template is set in. Kept apart from the template list because
  /// several looks share a voice — what separates them is the letterhead, not the
  /// alphabet.
  private enum FontFamily {
    case helvetica
    case georgia
    case avenir
    case futura
    case menlo
    case condensed
    case palatino
    case baskerville
    case iowan
    case rounded
  }

  private var fontFamily: FontFamily {
    switch document.layout.fontChoice {
    case .cleanSans: return .helvetica
    case .editorialSerif: return .baskerville
    case .modernRounded: return .rounded
    case .technicalMono: return .menlo
    case .template: break
    }
    if let style = template.advancedStyle {
      return switch style.motif {
      case 0: .helvetica
      case 1: .avenir
      case 2: .baskerville
      case 3: .menlo
      case 4: .futura
      case 5: .condensed
      case 6: .iowan
      case 7: .rounded
      // The Signature Collection.
      case 8: .helvetica
      case 9: .avenir
      case 10: .helvetica
      case 11: .futura
      case 12: .condensed
      case 13: .avenir
      case 14: .georgia
      // The Showcase Collection.
      case 16: .avenir  // Salute — friendly
      case 17: .condensed  // Couture — tall editorial
      case 18: .futura  // Medallion — geometric
      case 19: .helvetica  // Sable — neutral
      case 20: .iowan  // Terracotta — warm serif
      case 21: .rounded  // Lozenge — soft
      case 22: .avenir  // Circlet
      case 23: .baskerville  // Vogue — serif editorial
      case 24: .georgia  // Signet — classic serif
      case 25: .helvetica  // Almanac — data
      default: .avenir
      }
    }
    return switch template {
    case .portrait, .modern, .contemporary, .corporate, .compact, .horizon, .beacon, .slate,
      .atlas, .duo, .concise, .pivot, .gauge, .metro, .geneva, .laureate, .modena, .axis,
      .vantage:
      .helvetica
    case .classic, .elegant, .academic, .editorial, .meridian, .oxford, .gazette, .folio, .ivy,
      .nocturne, .monarch:
      .georgia
    case .canvas, .spotlight, .minimal, .nordic, .timeline, .aurora, .harbor, .lumen, .cascade,
      .vector, .verso, .chronicle, .strata, .signal, .insignia, .crest, .plinth, .stockholm,
      .tandem, .varsity, .nova, .eclipse, .terrace:
      .avenir
    case .atelier, .creative, .mosaic, .vertex, .marquee, .prism, .contour:
      .futura
    case .technical:
      .menlo
    case .monochrome, .onyx, .noir:
      .condensed
    case .ledger:
      .palatino
    case .linen, .aurelia:
      .baskerville
    case .quill:
      .iowan
    case .bloom:
      .rounded
    default:
      .helvetica
    }
  }

  private func regularFont(_ rawSize: CGFloat) -> UIFont {
    let size = rawSize * plan.density * CGFloat(document.layout.fontScale)
    return switch fontFamily {
    case .helvetica:
      UIFont(name: "HelveticaNeue", size: size) ?? .systemFont(ofSize: size)
    case .georgia:
      UIFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size)
    case .avenir:
      UIFont(name: "AvenirNext-Regular", size: size) ?? .systemFont(ofSize: size)
    case .futura:
      UIFont(name: "Futura-Medium", size: size) ?? .systemFont(ofSize: size)
    case .menlo:
      UIFont(name: "Menlo-Regular", size: size)
        ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    case .condensed:
      UIFont(name: "HelveticaNeue-Condensed", size: size) ?? .systemFont(ofSize: size)
    case .palatino:
      UIFont(name: "Palatino-Roman", size: size) ?? .systemFont(ofSize: size)
    case .baskerville:
      UIFont(name: "Baskerville", size: size) ?? .systemFont(ofSize: size)
    case .iowan:
      UIFont(name: "IowanOldStyle-Roman", size: size) ?? .systemFont(ofSize: size)
    case .rounded:
      roundedFont(size, weight: .regular)
    }
  }

  private func mediumFont(_ rawSize: CGFloat) -> UIFont {
    let size = rawSize * plan.density * CGFloat(document.layout.fontScale)
    return switch fontFamily {
    case .helvetica:
      UIFont(name: "HelveticaNeue-Medium", size: size) ?? .systemFont(ofSize: size, weight: .medium)
    case .georgia:
      UIFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size, weight: .medium)
    case .avenir:
      UIFont(name: "AvenirNext-Medium", size: size) ?? .systemFont(ofSize: size, weight: .medium)
    case .futura:
      UIFont(name: "Futura-Medium", size: size) ?? .systemFont(ofSize: size, weight: .medium)
    case .menlo:
      UIFont(name: "Menlo-Bold", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .medium)
    case .condensed:
      UIFont(name: "HelveticaNeue-CondensedBold", size: size)
        ?? .systemFont(ofSize: size, weight: .medium)
    case .palatino:
      UIFont(name: "Palatino-Roman", size: size) ?? .systemFont(ofSize: size, weight: .medium)
    case .baskerville:
      UIFont(name: "Baskerville-SemiBold", size: size)
        ?? .systemFont(ofSize: size, weight: .medium)
    case .iowan:
      UIFont(name: "IowanOldStyle-Roman", size: size) ?? .systemFont(ofSize: size, weight: .medium)
    case .rounded:
      roundedFont(size, weight: .medium)
    }
  }

  private func boldFont(_ rawSize: CGFloat) -> UIFont {
    let size = rawSize * plan.density * CGFloat(document.layout.fontScale)
    return switch fontFamily {
    case .helvetica:
      UIFont(name: "HelveticaNeue-Bold", size: size) ?? .systemFont(ofSize: size, weight: .bold)
    case .georgia:
      UIFont(name: "Georgia-Bold", size: size) ?? .systemFont(ofSize: size, weight: .bold)
    case .avenir:
      UIFont(name: "AvenirNext-DemiBold", size: size)
        ?? .systemFont(ofSize: size, weight: .semibold)
    case .futura:
      UIFont(name: "Futura-Bold", size: size) ?? .systemFont(ofSize: size, weight: .bold)
    case .menlo:
      UIFont(name: "Menlo-Bold", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .bold)
    case .condensed:
      UIFont(name: "HelveticaNeue-CondensedBold", size: size)
        ?? .systemFont(ofSize: size, weight: .bold)
    case .palatino:
      UIFont(name: "Palatino-Bold", size: size) ?? .systemFont(ofSize: size, weight: .bold)
    case .baskerville:
      UIFont(name: "Baskerville-Bold", size: size) ?? .systemFont(ofSize: size, weight: .bold)
    case .iowan:
      UIFont(name: "IowanOldStyle-Bold", size: size) ?? .systemFont(ofSize: size, weight: .bold)
    case .rounded:
      roundedFont(size, weight: .bold)
    }
  }

  /// SF Rounded has no PostScript name to ask for, so it comes from a descriptor.
  private func roundedFont(_ size: CGFloat, weight: UIFont.Weight) -> UIFont {
    let system = UIFont.systemFont(ofSize: size, weight: weight)
    guard let descriptor = system.fontDescriptor.withDesign(.rounded) else { return system }
    return UIFont(descriptor: descriptor, size: size)
  }
}
