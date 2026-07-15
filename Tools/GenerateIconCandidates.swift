// Renders app-icon redesign candidates at 1024x1024 so a winner can be picked
// before the full light/dark/tinted set is produced by GenerateAppIcon.swift.
//
//   swift Tools/GenerateIconCandidates.swift Design/AppIconCandidates
//
// Concept (per direction): the résumé sheet with the orange dog-ear, plus a
// magnifying glass that reads as job-hunting / searching the résumé. All three
// keep the navy field + white sheet + orange accent so the mark still says
// "résumé" and stays clear of the category's wall of blue document icons.
//
//   A "Folio Search" — faithful to the reference: orange dog-ear, a navy
//                      magnifier resting on the lower-right corner.
//   B "Job Hunt"     — no dog-ear; a bold orange magnifier is the hero and
//                      carries the accent. Cleanest at small sizes.
//   C "Match"        — the magnifier's lens actually enlarges the résumé lines
//                      and highlights one in orange: a found match.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let S: CGFloat = 1024
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
  CGColor(colorSpace: srgb, components: [r, g, b, a])!
}

func gray(_ v: CGFloat, _ a: CGFloat = 1) -> CGColor { rgb(v, v, v, a) }

// MARK: - Shared palette

let fieldTop = rgb(0.16, 0.20, 0.34)
let fieldBottom = rgb(0.04, 0.05, 0.11)
let fieldGlow = rgb(0.55, 0.68, 1.00, 0.24)
let navy = rgb(0.16, 0.19, 0.29)
let accent = rgb(0.91, 0.35, 0.05)
let accentBright = rgb(0.99, 0.55, 0.14)
let inkStrong = rgb(0.16, 0.19, 0.29, 0.92)
let lineStrong = rgb(0.16, 0.19, 0.29, 0.22)
let lineSoft = rgb(0.16, 0.19, 0.29, 0.13)

// MARK: - Drawing helpers

func roundedPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
  CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func fillRounded(_ ctx: CGContext, _ rect: CGRect, radius: CGFloat, color: CGColor) {
  ctx.setFillColor(color)
  ctx.addPath(roundedPath(rect, radius))
  ctx.fillPath()
}

func capsule(_ ctx: CGContext, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, color: CGColor) {
  fillRounded(ctx, CGRect(x: x, y: y, width: w, height: h), radius: h / 2, color: color)
}

func linearGradient(
  _ ctx: CGContext, from: CGPoint, to: CGPoint, colors: [CGColor], locations: [CGFloat]
) {
  guard
    let gradient = CGGradient(colorsSpace: srgb, colors: colors as CFArray, locations: locations)
  else { return }
  ctx.drawLinearGradient(gradient, start: from, end: to, options: [])
}

func radialGlow(
  _ ctx: CGContext, center: CGPoint, radius: CGFloat, color: CGColor,
  blend: CGBlendMode = .normal
) {
  let clear = color.copy(alpha: 0)!
  guard
    let gradient = CGGradient(colorsSpace: srgb, colors: [color, clear] as CFArray, locations: [0, 1])
  else { return }
  ctx.saveGState()
  ctx.setBlendMode(blend)
  ctx.drawRadialGradient(
    gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
  ctx.restoreGState()
}

func field(_ ctx: CGContext) {
  linearGradient(
    ctx, from: CGPoint(x: 0, y: 0), to: CGPoint(x: S, y: S),
    colors: [fieldTop, fieldBottom], locations: [0, 1])
  radialGlow(
    ctx, center: CGPoint(x: 512, y: 452), radius: S * 0.52, color: fieldGlow, blend: .plusLighter)
}

func vignette(_ ctx: CGContext, _ strength: CGColor) {
  if let g = CGGradient(
    colorsSpace: srgb, colors: [gray(0, 0), strength] as CFArray, locations: [0.55, 1])
  {
    ctx.drawRadialGradient(
      g, startCenter: CGPoint(x: S / 2, y: S / 2), startRadius: 0,
      endCenter: CGPoint(x: S / 2, y: S / 2), endRadius: S * 0.82, options: [])
  }
}

// MARK: - Résumé sheet

let sheet = CGRect(x: 236, y: 180, width: 470, height: 566)
let sheetRadius: CGFloat = 44
let fold: CGFloat = 158

/// The sheet outline with the top-right corner cut away for the fold.
func foldedPagePath(_ rect: CGRect, radius r: CGFloat, fold f: CGFloat) -> CGPath {
  let p = CGMutablePath()
  p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
  p.addLine(to: CGPoint(x: rect.maxX - f, y: rect.minY))
  p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + f))
  p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
  p.addArc(
    tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
    tangent2End: CGPoint(x: rect.maxX - r, y: rect.maxY), radius: r)
  p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
  p.addArc(
    tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
    tangent2End: CGPoint(x: rect.minX, y: rect.maxY - r), radius: r)
  p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
  p.addArc(
    tangent1End: CGPoint(x: rect.minX, y: rect.minY),
    tangent2End: CGPoint(x: rect.minX + r, y: rect.minY), radius: r)
  p.closeSubpath()
  return p
}

/// Draws the sheet (with or without the dog-ear) and its back page, then returns
/// the page path so the caller can clip content to it.
@discardableResult
func drawSheet(_ ctx: CGContext, dogEar: Bool) -> CGPath {
  // Back page fanned behind.
  ctx.saveGState()
  ctx.translateBy(x: sheet.midX, y: sheet.midY)
  ctx.rotate(by: -8.0 * .pi / 180)
  ctx.translateBy(x: -sheet.midX, y: -sheet.midY)
  ctx.setFillColor(gray(1.0, 0.28))
  ctx.addPath(roundedPath(sheet.insetBy(dx: 8, dy: 8), sheetRadius))
  ctx.fillPath()
  ctx.restoreGState()

  let page = dogEar ? foldedPagePath(sheet, radius: sheetRadius, fold: fold) : roundedPath(sheet, sheetRadius)
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -26), blur: 54, color: gray(0, 0.42))
  ctx.setFillColor(gray(1.0))
  ctx.addPath(page)
  ctx.fillPath()
  ctx.restoreGState()

  if dogEar {
    let flap = CGMutablePath()
    flap.move(to: CGPoint(x: sheet.maxX - fold, y: sheet.minY))
    flap.addLine(to: CGPoint(x: sheet.maxX, y: sheet.minY + fold))
    flap.addArc(
      tangent1End: CGPoint(x: sheet.maxX - fold, y: sheet.minY + fold),
      tangent2End: CGPoint(x: sheet.maxX - fold, y: sheet.minY), radius: 20)
    flap.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: -4, height: -10), blur: 22, color: gray(0, 0.30))
    ctx.addPath(flap)
    ctx.clip()
    linearGradient(
      ctx, from: CGPoint(x: sheet.maxX - fold, y: sheet.minY),
      to: CGPoint(x: sheet.maxX, y: sheet.minY + fold),
      colors: [accentBright, accent], locations: [0, 1])
    ctx.restoreGState()
  }
  return page
}

/// The résumé anatomy: name, headline, and two sections, one accent-headed.
func drawResumeContent(_ ctx: CGContext, page: CGPath) {
  ctx.saveGState()
  ctx.addPath(page)
  ctx.clip()
  let x = sheet.minX + 48
  let full = sheet.width - 96
  capsule(ctx, x: x, y: sheet.minY + 64, w: 226, h: 32, color: inkStrong)
  capsule(ctx, x: x, y: sheet.minY + 118, w: 148, h: 17, color: rgb(0.16, 0.19, 0.29, 0.45))

  capsule(ctx, x: x, y: sheet.minY + 214, w: 138, h: 25, color: accent)
  capsule(ctx, x: x, y: sheet.minY + 260, w: full, h: 19, color: lineStrong)
  capsule(ctx, x: x, y: sheet.minY + 294, w: full * 0.78, h: 19, color: lineSoft)

  capsule(ctx, x: x, y: sheet.minY + 366, w: 168, h: 25, color: inkStrong)
  capsule(ctx, x: x, y: sheet.minY + 412, w: full, h: 19, color: lineStrong)
  capsule(ctx, x: x, y: sheet.minY + 446, w: full * 0.62, h: 19, color: lineSoft)
  ctx.restoreGState()
}

// MARK: - Magnifier

/// A magnifying glass: a ring lens with a handle at `angle` (radians, screen
/// space — positive y points down). `magnify` draws inside the lens, clipped.
func drawMagnifier(
  _ ctx: CGContext, center c: CGPoint, radius R: CGFloat, thickness t: CGFloat,
  frame: CGColor, handleLength L: CGFloat, handleWidth W: CGFloat, angle: CGFloat,
  magnify: ((CGContext, CGPoint, CGFloat) -> Void)? = nil
) {
  let d = CGPoint(x: cos(angle), y: sin(angle))

  // One clean drop shadow: paint the whole silhouette (lens disc + handle) in
  // the frame colour first, then repaint the glass over it.
  var handleTransform = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle)
  let handlePath = CGPath(
    roundedRect: CGRect(x: R - 6, y: -W / 2, width: L, height: W),
    cornerWidth: W / 2, cornerHeight: W / 2, transform: &handleTransform)

  let silhouette = CGMutablePath()
  silhouette.addEllipse(in: CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2))
  silhouette.addPath(handlePath)

  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 6, height: -16), blur: 34, color: gray(0, 0.40))
  ctx.setFillColor(frame)
  ctx.addPath(silhouette)
  ctx.fillPath()
  ctx.restoreGState()

  // A darker line down the handle's centre for a little dimension.
  ctx.saveGState()
  ctx.setStrokeColor(gray(0, 0.12))
  ctx.setLineWidth(W * 0.16)
  ctx.setLineCap(.round)
  ctx.move(to: CGPoint(x: c.x + d.x * (R + 4), y: c.y + d.y * (R + 4)))
  ctx.addLine(to: CGPoint(x: c.x + d.x * (R + L - W * 0.7), y: c.y + d.y * (R + L - W * 0.7)))
  ctx.strokePath()
  ctx.restoreGState()

  // Glass.
  let glassR = R - t
  ctx.saveGState()
  ctx.addEllipse(in: CGRect(x: c.x - glassR, y: c.y - glassR, width: glassR * 2, height: glassR * 2))
  ctx.clip()
  if let magnify {
    ctx.setFillColor(gray(1.0))
    ctx.fill(CGRect(x: c.x - glassR, y: c.y - glassR, width: glassR * 2, height: glassR * 2))
    magnify(ctx, c, glassR)
  } else {
    linearGradient(
      ctx, from: CGPoint(x: c.x - glassR, y: c.y - glassR),
      to: CGPoint(x: c.x + glassR, y: c.y + glassR),
      colors: [gray(1.0, 0.96), gray(0.84, 0.96)], locations: [0, 1])
  }
  // A soft top-left highlight so the lens reads as glass.
  radialGlow(
    ctx, center: CGPoint(x: c.x - glassR * 0.34, y: c.y - glassR * 0.36), radius: glassR * 1.1,
    color: gray(1.0, 0.55), blend: .plusLighter)
  ctx.restoreGState()
}

// MARK: - Candidates

func drawFolioSearch(_ ctx: CGContext) {
  field(ctx)
  let page = drawSheet(ctx, dogEar: true)
  drawResumeContent(ctx, page: page)
  drawMagnifier(
    ctx, center: CGPoint(x: 690, y: 706), radius: 132, thickness: 34, frame: navy,
    handleLength: 150, handleWidth: 46, angle: 46 * .pi / 180)
  vignette(ctx, gray(0, 0.30))
}

func drawJobHunt(_ ctx: CGContext) {
  field(ctx)
  let page = drawSheet(ctx, dogEar: false)
  drawResumeContent(ctx, page: page)
  drawMagnifier(
    ctx, center: CGPoint(x: 694, y: 700), radius: 140, thickness: 40, frame: accent,
    handleLength: 158, handleWidth: 50, angle: 46 * .pi / 180)
  vignette(ctx, gray(0, 0.30))
}

func drawMatch(_ ctx: CGContext) {
  field(ctx)
  let page = drawSheet(ctx, dogEar: true)
  drawResumeContent(ctx, page: page)
  drawMagnifier(
    ctx, center: CGPoint(x: 686, y: 704), radius: 138, thickness: 34, frame: navy,
    handleLength: 152, handleWidth: 46, angle: 46 * .pi / 180
  ) { ctx, c, r in
    // Enlarged résumé lines, one highlighted orange — a found match.
    let x = c.x - r * 0.62
    let w = r * 1.24
    capsule(ctx, x: x, y: c.y - r * 0.5, w: w * 0.7, h: 20, color: lineStrong)
    capsule(ctx, x: x, y: c.y - r * 0.16, w: w, h: 26, color: accent)
    capsule(ctx, x: x, y: c.y + r * 0.24, w: w * 0.86, h: 20, color: lineStrong)
    capsule(ctx, x: x, y: c.y + r * 0.54, w: w * 0.5, h: 20, color: lineSoft)
  }
  vignette(ctx, gray(0, 0.30))
}

// MARK: - Export

let candidates: [(name: String, draw: (CGContext) -> Void)] = [
  ("Candidate-A-FolioSearch", drawFolioSearch),
  ("Candidate-B-JobHunt", drawJobHunt),
  ("Candidate-C-Match", drawMatch),
]

func render(_ name: String, _ draw: (CGContext) -> Void, to directory: URL) throws {
  guard
    let ctx = CGContext(
      data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
      space: srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
  else { throw NSError(domain: "icon", code: 1) }

  // Draw in top-left origin coordinates.
  ctx.translateBy(x: 0, y: S)
  ctx.scaleBy(x: 1, y: -1)
  ctx.interpolationQuality = .high
  ctx.setAllowsAntialiasing(true)

  draw(ctx)

  guard let image = ctx.makeImage() else { throw NSError(domain: "icon", code: 2) }
  let url = directory.appendingPathComponent("\(name).png")
  guard
    let destination = CGImageDestinationCreateWithURL(
      url as CFURL, UTType.png.identifier as CFString, 1, nil)
  else { throw NSError(domain: "icon", code: 3) }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "icon", code: 4) }
  print("wrote \(url.path)")
}

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
  print("usage: swift GenerateIconCandidates.swift <output-directory>")
  exit(1)
}
let outputDirectory = URL(fileURLWithPath: arguments[1])
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
for candidate in candidates {
  try render(candidate.name, candidate.draw, to: outputDirectory)
}
