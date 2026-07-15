// Renders the Resume Studio app icon (light / dark / tinted) at 1024x1024.
//
// The PNGs in the asset catalogue are generated artefacts — edit this file, not
// them, and re-run:
//
//   swift Tools/GenerateAppIcon.swift ResumeStudio/Assets.xcassets/AppIcon.appiconset
//
// The colours here are mirrored by `BrandPalette`, which SplashView draws from,
// so the icon and the launch animation stay in step.

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

enum Variant: String, CaseIterable {
  case light = "AppIcon-Light"
  case dark = "AppIcon-Dark"
  case tinted = "AppIcon-Tinted"

  var hasBackground: Bool { self != .tinted }
}

// MARK: - Palette

struct Palette {
  var backgroundTop: CGColor
  var backgroundBottom: CGColor
  var spotlight: CGColor
  var vignette: CGColor
  var sheet: CGColor
  var sheetBack: CGColor
  var bandTop: CGColor
  var bandBottom: CGColor
  var bandTextStrong: CGColor
  var bandTextSoft: CGColor
  var inkBar: CGColor
  var accentBar: CGColor
  var line: CGColor
  var lineSoft: CGColor

  static func make(for variant: Variant) -> Palette {
    switch variant {
    case .light:
      return Palette(
        backgroundTop: rgb(0.16, 0.20, 0.34),
        backgroundBottom: rgb(0.04, 0.05, 0.11),
        spotlight: rgb(0.55, 0.68, 1.00, 0.24),
        vignette: gray(0, 0.30),
        sheet: gray(1.0),
        sheetBack: gray(1.0, 0.30),
        bandTop: rgb(0.90, 0.33, 0.05),
        bandBottom: rgb(0.99, 0.57, 0.16),
        bandTextStrong: gray(1.0, 0.96),
        bandTextSoft: gray(1.0, 0.58),
        inkBar: rgb(0.16, 0.19, 0.29, 0.92),
        accentBar: rgb(0.91, 0.35, 0.05),
        line: rgb(0.16, 0.19, 0.29, 0.22),
        lineSoft: rgb(0.16, 0.19, 0.29, 0.14)
      )
    case .dark:
      return Palette(
        backgroundTop: rgb(0.07, 0.09, 0.16),
        backgroundBottom: rgb(0.01, 0.02, 0.04),
        spotlight: rgb(0.42, 0.55, 0.95, 0.20),
        vignette: gray(0, 0.34),
        sheet: rgb(0.91, 0.92, 0.95),
        sheetBack: gray(1.0, 0.20),
        bandTop: rgb(0.82, 0.29, 0.04),
        bandBottom: rgb(0.95, 0.51, 0.12),
        bandTextStrong: gray(1.0, 0.93),
        bandTextSoft: gray(1.0, 0.52),
        inkBar: rgb(0.16, 0.19, 0.29, 0.88),
        accentBar: rgb(0.86, 0.32, 0.05),
        line: rgb(0.16, 0.19, 0.29, 0.24),
        lineSoft: rgb(0.16, 0.19, 0.29, 0.15)
      )
    case .tinted:
      // Grayscale over a transparent background: iOS maps luminance onto the
      // user's chosen tint, so the sheet stays bright and content reads dark.
      return Palette(
        backgroundTop: gray(0, 0),
        backgroundBottom: gray(0, 0),
        spotlight: gray(0, 0),
        vignette: gray(0, 0),
        sheet: gray(1.0),
        sheetBack: gray(1.0, 0.24),
        bandTop: gray(0.46),
        bandBottom: gray(0.60),
        bandTextStrong: gray(1.0, 0.95),
        bandTextSoft: gray(1.0, 0.55),
        inkBar: gray(0.24),
        accentBar: gray(0.44),
        line: gray(0.20, 0.26),
        lineSoft: gray(0.20, 0.16)
      )
    }
  }
}

// MARK: - Drawing helpers

func roundedPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
  CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func fill(_ ctx: CGContext, _ rect: CGRect, radius: CGFloat, color: CGColor) {
  ctx.setFillColor(color)
  ctx.addPath(roundedPath(rect, radius))
  ctx.fillPath()
}

func capsule(_ ctx: CGContext, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, color: CGColor) {
  fill(ctx, CGRect(x: x, y: y, width: w, height: h), radius: h / 2, color: color)
}

func linearGradient(
  _ ctx: CGContext, from: CGPoint, to: CGPoint, colors: [CGColor], locations: [CGFloat]
) {
  guard
    let gradient = CGGradient(
      colorsSpace: srgb, colors: colors as CFArray, locations: locations)
  else { return }
  ctx.drawLinearGradient(gradient, start: from, end: to, options: [])
}

/// Source-over rather than plus-lighter: additive light over navy washes out to
/// a muddy brown, while normal blending keeps the hue saturated.
func radialGlow(
  _ ctx: CGContext, center: CGPoint, radius: CGFloat, color: CGColor,
  blend: CGBlendMode = .normal
) {
  let clear = color.copy(alpha: 0)!
  guard
    let gradient = CGGradient(
      colorsSpace: srgb, colors: [color, clear] as CFArray, locations: [0, 1])
  else { return }
  ctx.saveGState()
  ctx.setBlendMode(blend)
  ctx.drawRadialGradient(
    gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius,
    options: [])
  ctx.restoreGState()
}

// MARK: - Icon

/// Front sheet, optically centred a touch above the middle.
let sheet = CGRect(x: 292, y: 230, width: 440, height: 540)
let sheetRadius: CGFloat = 40
let bandHeight: CGFloat = 164
let margin: CGFloat = 40

func drawSheetContents(_ ctx: CGContext, _ p: Palette) {
  let path = roundedPath(sheet, sheetRadius)

  // Paper.
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -26), blur: 54, color: gray(0, 0.42))
  ctx.setFillColor(p.sheet)
  ctx.addPath(path)
  ctx.fillPath()
  ctx.restoreGState()

  // Everything below is clipped to the paper so the band inherits its corners.
  ctx.saveGState()
  ctx.addPath(path)
  ctx.clip()

  // Header band.
  let band = CGRect(x: sheet.minX, y: sheet.minY, width: sheet.width, height: bandHeight)
  ctx.saveGState()
  ctx.clip(to: band)
  linearGradient(
    ctx,
    from: CGPoint(x: band.minX, y: band.minY),
    to: CGPoint(x: band.maxX, y: band.maxY),
    colors: [p.bandTop, p.bandBottom],
    locations: [0, 1])
  ctx.restoreGState()

  // Name + headline inside the band.
  let x = sheet.minX + margin
  capsule(ctx, x: x, y: sheet.minY + 56, w: 224, h: 28, color: p.bandTextStrong)
  capsule(ctx, x: x, y: sheet.minY + 100, w: 140, h: 16, color: p.bandTextSoft)

  // Body: two sections, the second headed by the brand accent. Deliberately few
  // and chunky so the mark still reads as a résumé at 60pt.
  let full: CGFloat = sheet.width - margin * 2
  capsule(ctx, x: x, y: sheet.minY + 208, w: 150, h: 24, color: p.inkBar)
  capsule(ctx, x: x, y: sheet.minY + 254, w: full, h: 20, color: p.line)
  capsule(ctx, x: x, y: sheet.minY + 290, w: 300, h: 20, color: p.lineSoft)

  capsule(ctx, x: x, y: sheet.minY + 348, w: 126, h: 24, color: p.accentBar)
  capsule(ctx, x: x, y: sheet.minY + 394, w: full, h: 20, color: p.line)
  capsule(ctx, x: x, y: sheet.minY + 430, w: 330, h: 20, color: p.lineSoft)
  capsule(ctx, x: x, y: sheet.minY + 466, w: 240, h: 20, color: p.lineSoft)

  ctx.restoreGState()
}

func drawIcon(_ ctx: CGContext, variant: Variant) {
  let p = Palette.make(for: variant)
  let canvas = CGRect(x: 0, y: 0, width: S, height: S)

  if variant.hasBackground {
    ctx.saveGState()
    ctx.clip(to: canvas)

    // Deep navy field, lit from the top-left.
    linearGradient(
      ctx,
      from: CGPoint(x: 0, y: 0),
      to: CGPoint(x: S, y: S),
      colors: [p.backgroundTop, p.backgroundBottom],
      locations: [0, 1])

    // A single cool spotlight behind the page. Keeping the field cool leaves the
    // orange band as the only warm note in the icon, so it carries all the pop.
    radialGlow(
      ctx, center: CGPoint(x: sheet.midX, y: sheet.midY - 30), radius: S * 0.52,
      color: p.spotlight, blend: .plusLighter)

    ctx.restoreGState()
  }

  // A second page fanned out behind the first. No shadow of its own — the front
  // sheet casts onto it, which is what sells the depth.
  ctx.saveGState()
  ctx.translateBy(x: sheet.midX, y: sheet.midY)
  ctx.rotate(by: -8.0 * .pi / 180)
  ctx.translateBy(x: -sheet.midX, y: -sheet.midY)
  ctx.setFillColor(p.sheetBack)
  ctx.addPath(roundedPath(sheet.insetBy(dx: 8, dy: 8), sheetRadius))
  ctx.fillPath()
  ctx.restoreGState()

  drawSheetContents(ctx, p)

  if variant.hasBackground {
    // Vignette to seat the mark in the field.
    ctx.saveGState()
    ctx.clip(to: canvas)
    if let vignette = CGGradient(
      colorsSpace: srgb, colors: [gray(0, 0), p.vignette] as CFArray, locations: [0.55, 1])
    {
      ctx.drawRadialGradient(
        vignette,
        startCenter: CGPoint(x: S / 2, y: S / 2), startRadius: 0,
        endCenter: CGPoint(x: S / 2, y: S / 2), endRadius: S * 0.82,
        options: [])
    }
    ctx.restoreGState()
  }
}

// MARK: - Export

func render(_ variant: Variant, to directory: URL) throws {
  let opaque = variant.hasBackground
  let bitmapInfo =
    opaque
    ? CGImageAlphaInfo.noneSkipLast.rawValue  // App Store icons must not carry alpha.
    : CGImageAlphaInfo.premultipliedLast.rawValue

  guard
    let ctx = CGContext(
      data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
      space: srgb, bitmapInfo: bitmapInfo)
  else { throw NSError(domain: "icon", code: 1) }

  // Draw in top-left origin coordinates.
  ctx.translateBy(x: 0, y: S)
  ctx.scaleBy(x: 1, y: -1)
  ctx.interpolationQuality = .high
  ctx.setAllowsAntialiasing(true)

  drawIcon(ctx, variant: variant)

  guard let image = ctx.makeImage() else { throw NSError(domain: "icon", code: 2) }
  let url = directory.appendingPathComponent("\(variant.rawValue).png")
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
  print("usage: swift GenerateIcon.swift <output-directory>")
  exit(1)
}
let outputDirectory = URL(fileURLWithPath: arguments[1])
for variant in Variant.allCases {
  try render(variant, to: outputDirectory)
}
