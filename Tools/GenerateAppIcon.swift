// Renders the Resume Studio app icon (light / dark / tinted) at 1024x1024,
// plus the LaunchMark tile the static launch screen shows.
//
// The PNGs in the asset catalogue are generated artefacts — edit this file, not
// them, and re-run:
//
//   swift Tools/GenerateAppIcon.swift \
//     ResumeStudio/Assets.xcassets/AppIcon.appiconset \
//     ResumeStudio/Assets.xcassets/LaunchMark.imageset
//
// The design is the "Match" mark: a white résumé sheet with an orange dog-ear
// on the deep-navy field, and a magnifying glass whose lens enlarges the résumé
// lines and highlights one in orange — the app in one glance, a résumé you
// search. Navy field + white paper + orange accent keep it clear of the
// category's wall of blue document icons. The colours are mirrored by
// `BrandPalette`, which the launch screen and `SplashView` draw from, so the
// icon and the launch hand-off stay in step.

import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let iconSize: CGFloat = 1024
let launchPointSize: CGFloat = 132
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
  CGColor(colorSpace: srgb, components: [r, g, b, a])!
}

func gray(_ v: CGFloat, _ a: CGFloat = 1) -> CGColor { rgb(v, v, v, a) }

enum Variant: String, CaseIterable {
  case light = "AppIcon-Light"
  case dark = "AppIcon-Dark"
  case tinted = "AppIcon-Tinted"

  var hasBackground: Bool { self != .tinted }
}

// MARK: - Palette

struct Palette {
  var fieldTop: CGColor
  var fieldBottom: CGColor
  var glow: CGColor
  var vignette: CGColor
  var sheet: CGColor
  var sheetBack: CGColor
  var foldTop: CGColor
  var foldBottom: CGColor
  var nameStrong: CGColor
  var nameSoft: CGColor
  var accent: CGColor
  var lineStrong: CGColor
  var lineSoft: CGColor
  var magFrame: CGColor
  var magGlass: CGColor
  var magGlassEdge: CGColor
  var magHighlight: CGColor
  var magText: CGColor

  static func make(for variant: Variant) -> Palette {
    switch variant {
    case .light:
      return Palette(
        fieldTop: rgb(0.16, 0.20, 0.34),
        fieldBottom: rgb(0.04, 0.05, 0.11),
        glow: rgb(0.55, 0.68, 1.00, 0.24),
        vignette: gray(0, 0.30),
        sheet: gray(1.0),
        sheetBack: gray(1.0, 0.28),
        foldTop: rgb(0.99, 0.55, 0.14),
        foldBottom: rgb(0.91, 0.35, 0.05),
        nameStrong: rgb(0.16, 0.19, 0.29, 0.92),
        nameSoft: rgb(0.16, 0.19, 0.29, 0.45),
        accent: rgb(0.91, 0.35, 0.05),
        lineStrong: rgb(0.16, 0.19, 0.29, 0.22),
        lineSoft: rgb(0.16, 0.19, 0.29, 0.13),
        magFrame: rgb(0.94, 0.42, 0.06),
        magGlass: gray(1.0),
        magGlassEdge: gray(0.87),
        magHighlight: gray(1.0, 0.55),
        magText: rgb(0.16, 0.19, 0.29))
    case .dark:
      return Palette(
        fieldTop: rgb(0.07, 0.09, 0.16),
        fieldBottom: rgb(0.01, 0.02, 0.04),
        glow: rgb(0.42, 0.55, 0.95, 0.20),
        vignette: gray(0, 0.34),
        sheet: rgb(0.92, 0.93, 0.96),
        sheetBack: gray(1.0, 0.18),
        foldTop: rgb(0.95, 0.51, 0.12),
        foldBottom: rgb(0.82, 0.29, 0.04),
        nameStrong: rgb(0.14, 0.17, 0.26, 0.95),
        nameSoft: rgb(0.14, 0.17, 0.26, 0.48),
        accent: rgb(0.88, 0.33, 0.05),
        lineStrong: rgb(0.16, 0.19, 0.29, 0.26),
        lineSoft: rgb(0.16, 0.19, 0.29, 0.16),
        magFrame: rgb(0.90, 0.38, 0.05),
        magGlass: rgb(0.95, 0.96, 0.98),
        magGlassEdge: rgb(0.82, 0.84, 0.89),
        magHighlight: gray(1.0, 0.50),
        magText: rgb(0.16, 0.19, 0.29))
    case .tinted:
      // Grayscale over a transparent background: iOS maps luminance onto the
      // user's chosen tint, so the paper stays bright and the ink reads dark.
      return Palette(
        fieldTop: gray(0, 0),
        fieldBottom: gray(0, 0),
        glow: gray(0, 0),
        vignette: gray(0, 0),
        sheet: gray(1.0),
        sheetBack: gray(1.0, 0.24),
        foldTop: gray(0.60),
        foldBottom: gray(0.46),
        nameStrong: gray(0.26),
        nameSoft: gray(0.52),
        accent: gray(0.46),
        lineStrong: gray(0.58),
        lineSoft: gray(0.74),
        // Tinted is monochrome, so the frame can't be orange; a brighter grey
        // keeps the handle legible against the dark tinted field.
        magFrame: gray(0.46),
        magGlass: gray(1.0),
        magGlassEdge: gray(0.86),
        magHighlight: gray(1.0, 0.40),
        magText: gray(0.26))
    }
  }
}

// MARK: - Drawing helpers

func roundedPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
  CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func capsule(_ ctx: CGContext, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, color: CGColor) {
  ctx.setFillColor(color)
  ctx.addPath(roundedPath(CGRect(x: x, y: y, width: w, height: h), h / 2))
  ctx.fillPath()
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

// MARK: - The Match mark (all geometry in the 1024pt design space)

let sheet = CGRect(x: 236, y: 180, width: 470, height: 566)
let sheetRadius: CGFloat = 44
let fold: CGFloat = 158

/// The sheet outline with the top-right corner cut away for the dog-ear.
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

func drawSheet(_ ctx: CGContext, _ p: Palette, shadows: Bool) -> CGPath {
  // Back page fanned behind.
  ctx.saveGState()
  ctx.translateBy(x: sheet.midX, y: sheet.midY)
  ctx.rotate(by: -8.0 * .pi / 180)
  ctx.translateBy(x: -sheet.midX, y: -sheet.midY)
  ctx.setFillColor(p.sheetBack)
  ctx.addPath(roundedPath(sheet.insetBy(dx: 8, dy: 8), sheetRadius))
  ctx.fillPath()
  ctx.restoreGState()

  let page = foldedPagePath(sheet, radius: sheetRadius, fold: fold)
  ctx.saveGState()
  if shadows {
    ctx.setShadow(offset: CGSize(width: 0, height: -26), blur: 54, color: gray(0, 0.42))
  }
  ctx.setFillColor(p.sheet)
  ctx.addPath(page)
  ctx.fillPath()
  ctx.restoreGState()

  // The turned-down flap.
  let flap = CGMutablePath()
  flap.move(to: CGPoint(x: sheet.maxX - fold, y: sheet.minY))
  flap.addLine(to: CGPoint(x: sheet.maxX, y: sheet.minY + fold))
  flap.addArc(
    tangent1End: CGPoint(x: sheet.maxX - fold, y: sheet.minY + fold),
    tangent2End: CGPoint(x: sheet.maxX - fold, y: sheet.minY), radius: 20)
  flap.closeSubpath()
  ctx.saveGState()
  if shadows {
    ctx.setShadow(offset: CGSize(width: -4, height: -10), blur: 22, color: gray(0, 0.30))
  }
  ctx.addPath(flap)
  ctx.clip()
  linearGradient(
    ctx, from: CGPoint(x: sheet.maxX - fold, y: sheet.minY),
    to: CGPoint(x: sheet.maxX, y: sheet.minY + fold),
    colors: [p.foldTop, p.foldBottom], locations: [0, 1])
  ctx.restoreGState()

  return page
}

func drawResumeContent(_ ctx: CGContext, _ p: Palette, page: CGPath) {
  ctx.saveGState()
  ctx.addPath(page)
  ctx.clip()
  let x = sheet.minX + 48
  let full = sheet.width - 96
  capsule(ctx, x: x, y: sheet.minY + 64, w: 226, h: 32, color: p.nameStrong)
  capsule(ctx, x: x, y: sheet.minY + 118, w: 148, h: 17, color: p.nameSoft)

  capsule(ctx, x: x, y: sheet.minY + 214, w: 138, h: 25, color: p.accent)
  capsule(ctx, x: x, y: sheet.minY + 260, w: full, h: 19, color: p.lineStrong)
  capsule(ctx, x: x, y: sheet.minY + 294, w: full * 0.78, h: 19, color: p.lineSoft)

  capsule(ctx, x: x, y: sheet.minY + 366, w: 168, h: 25, color: p.nameStrong)
  capsule(ctx, x: x, y: sheet.minY + 412, w: full, h: 19, color: p.lineStrong)
  capsule(ctx, x: x, y: sheet.minY + 446, w: full * 0.62, h: 19, color: p.lineSoft)
  ctx.restoreGState()
}

/// Draws `text` optically centred on `center` (in the 1024pt design space, top-
/// left origin). The local flip renders the glyphs upright under the mark's
/// y-down transform.
func drawGlyphCentered(_ ctx: CGContext, _ text: String, font: NSFont, center c: CGPoint, color: CGColor) {
  let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
  ]
  let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
  ctx.saveGState()
  ctx.translateBy(x: 0, y: iconSize)
  ctx.scaleBy(x: 1, y: -1)
  let cc = CGPoint(x: c.x, y: iconSize - c.y)
  ctx.textPosition = .zero
  let bounds = CTLineGetImageBounds(line, ctx)
  ctx.setFillColor(color)
  ctx.textPosition = CGPoint(
    x: cc.x - bounds.width / 2 - bounds.minX,
    y: cc.y - bounds.height / 2 - bounds.minY)
  CTLineDraw(line, ctx)
  ctx.restoreGState()
}

/// The magnifying glass over the résumé, its handle at 45°. The lens is large
/// and carries a bold "CV" so the mark reads at a glance as a CV app.
func drawMagnifier(_ ctx: CGContext, _ p: Palette, shadows: Bool) {
  let c = CGPoint(x: 662, y: 682)
  let R: CGFloat = 170
  let thickness: CGFloat = 36
  let handleLength: CGFloat = 132
  let handleWidth: CGFloat = 52
  let angle: CGFloat = 45 * .pi / 180
  let d = CGPoint(x: cos(angle), y: sin(angle))

  var handleTransform = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle)
  let handlePath = CGPath(
    roundedRect: CGRect(x: R - 6, y: -handleWidth / 2, width: handleLength, height: handleWidth),
    cornerWidth: handleWidth / 2, cornerHeight: handleWidth / 2, transform: &handleTransform)

  // One clean drop shadow: paint the whole silhouette (lens disc + handle) in
  // the frame colour, then repaint the glass over it.
  let silhouette = CGMutablePath()
  silhouette.addEllipse(in: CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2))
  silhouette.addPath(handlePath)
  ctx.saveGState()
  if shadows {
    ctx.setShadow(offset: CGSize(width: 6, height: -16), blur: 38, color: gray(0, 0.40))
  }
  ctx.setFillColor(p.magFrame)
  ctx.addPath(silhouette)
  ctx.fillPath()
  ctx.restoreGState()

  // A darker seam down the handle for a little dimension.
  ctx.saveGState()
  ctx.setStrokeColor(gray(0, 0.12))
  ctx.setLineWidth(handleWidth * 0.16)
  ctx.setLineCap(.round)
  ctx.move(to: CGPoint(x: c.x + d.x * (R + 4), y: c.y + d.y * (R + 4)))
  ctx.addLine(
    to: CGPoint(
      x: c.x + d.x * (R + handleLength - handleWidth * 0.7),
      y: c.y + d.y * (R + handleLength - handleWidth * 0.7)))
  ctx.strokePath()
  ctx.restoreGState()

  // Glass with a bold "CV" at the centre.
  let r = R - thickness
  ctx.saveGState()
  ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
  ctx.clip()
  // A subtle gradient gives the glass dimension rather than a flat disc.
  linearGradient(
    ctx, from: CGPoint(x: c.x - r, y: c.y - r), to: CGPoint(x: c.x + r, y: c.y + r),
    colors: [p.magGlass, p.magGlassEdge], locations: [0, 1])
  drawGlyphCentered(
    ctx, "CV", font: NSFont.systemFont(ofSize: 158, weight: .heavy), center: c, color: p.magText)
  // A soft top-left reflection over the glass.
  radialGlow(
    ctx, center: CGPoint(x: c.x - r * 0.36, y: c.y - r * 0.40), radius: r * 1.05,
    color: p.magHighlight, blend: .plusLighter)
  ctx.restoreGState()
}

func drawMark(_ ctx: CGContext, palette p: Palette, hasBackground: Bool) {
  if hasBackground {
    linearGradient(
      ctx, from: CGPoint(x: 0, y: 0), to: CGPoint(x: iconSize, y: iconSize),
      colors: [p.fieldTop, p.fieldBottom], locations: [0, 1])
    radialGlow(
      ctx, center: CGPoint(x: 512, y: 452), radius: iconSize * 0.52, color: p.glow,
      blend: .plusLighter)
  }

  let page = drawSheet(ctx, p, shadows: hasBackground)
  drawResumeContent(ctx, p, page: page)
  drawMagnifier(ctx, p, shadows: hasBackground)

  if hasBackground {
    if let vignette = CGGradient(
      colorsSpace: srgb, colors: [gray(0, 0), p.vignette] as CFArray, locations: [0.55, 1])
    {
      ctx.drawRadialGradient(
        vignette,
        startCenter: CGPoint(x: iconSize / 2, y: iconSize / 2), startRadius: 0,
        endCenter: CGPoint(x: iconSize / 2, y: iconSize / 2), endRadius: iconSize * 0.82,
        options: [])
    }
  }
}

// MARK: - Export

func makeContext(_ pixels: Int, opaque: Bool) throws -> CGContext {
  let bitmapInfo =
    opaque
    ? CGImageAlphaInfo.noneSkipLast.rawValue  // App Store icons must not carry alpha.
    : CGImageAlphaInfo.premultipliedLast.rawValue
  guard
    let ctx = CGContext(
      data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
      space: srgb, bitmapInfo: bitmapInfo)
  else { throw NSError(domain: "icon", code: 1) }
  // Draw in top-left origin coordinates, with the 1024pt design space scaled to
  // fit whatever pixel size was requested.
  ctx.translateBy(x: 0, y: CGFloat(pixels))
  ctx.scaleBy(x: 1, y: -1)
  ctx.scaleBy(x: CGFloat(pixels) / iconSize, y: CGFloat(pixels) / iconSize)
  ctx.interpolationQuality = .high
  ctx.setAllowsAntialiasing(true)
  return ctx
}

func writePNG(_ ctx: CGContext, to url: URL) throws {
  guard let image = ctx.makeImage() else { throw NSError(domain: "icon", code: 2) }
  guard
    let destination = CGImageDestinationCreateWithURL(
      url as CFURL, UTType.png.identifier as CFString, 1, nil)
  else { throw NSError(domain: "icon", code: 3) }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "icon", code: 4) }
  print("wrote \(url.path)")
}

func renderIcon(_ variant: Variant, to directory: URL) throws {
  let ctx = try makeContext(Int(iconSize), opaque: variant.hasBackground)
  drawMark(ctx, palette: .make(for: variant), hasBackground: variant.hasBackground)
  try writePNG(ctx, to: directory.appendingPathComponent("\(variant.rawValue).png"))
}

/// The launch tile: the icon clipped to the home-screen corner radius so the
/// static launch screen reads as the tapped icon.
func renderLaunchMark(scale: Int, to directory: URL) throws {
  let pixels = Int(launchPointSize) * scale
  let ctx = try makeContext(pixels, opaque: false)
  ctx.addPath(roundedPath(CGRect(x: 0, y: 0, width: iconSize, height: iconSize), iconSize * 0.2237))
  ctx.clip()
  drawMark(ctx, palette: .make(for: .light), hasBackground: true)
  try writePNG(ctx, to: directory.appendingPathComponent("LaunchMark@\(scale)x.png"))
}

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
  print(
    "usage: swift GenerateAppIcon.swift <appiconset-directory> [launchmark-imageset-directory]")
  exit(1)
}
let iconDirectory = URL(fileURLWithPath: arguments[1])
for variant in Variant.allCases {
  try renderIcon(variant, to: iconDirectory)
}
if arguments.count > 2 {
  let launchDirectory = URL(fileURLWithPath: arguments[2])
  for scale in 1...3 {
    try renderLaunchMark(scale: scale, to: launchDirectory)
  }
}
