import AppKit
import CoreText

// Premium App Store screenshot compositor for Resume Studio.
// Canvas: 1284 x 2778 (accepted for the 6.5"/6.7" iPhone slot).
// Raw captures: 1320 x 2868 (iPhone 17 Pro Max @3x).

let canvasW: CGFloat = 1284
let canvasH: CGFloat = 2778
let rawW: CGFloat = 1320
let rawH: CGFloat = 2868

let scratch = "/private/tmp/claude-502/-Users-halalisanimbanjwa-Documents-GitHub-ios-ResumeStudio/a4440b03-e742-4d16-b43d-5802e540baf4/scratchpad"
let rawDir = "\(scratch)/raw"
let outDir = CommandLine.arguments.count > 1
  ? CommandLine.arguments[1]
  : "/Users/halalisanimbanjwa/Documents/GitHub/ios/ResumeStudio/AppStoreAssets/screenshots"
let iconPath = "/Users/halalisanimbanjwa/Documents/GitHub/ios/ResumeStudio/ResumeStudio/Assets.xcassets/AppIcon.appiconset/AppIcon-Light.png"

// MARK: - Brand palette (exact app Theme values)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
  CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

enum Brand {
  static let paperTop = rgb(0.992, 0.981, 0.962)
  static let paperBottom = rgb(0.965, 0.941, 0.902)
  static let ink = rgb(0.038, 0.069, 0.121)
  static let mutedInk = rgb(0.363, 0.391, 0.435)
  static let heroTop = rgb(0.105, 0.128, 0.165)
  static let heroBottom = rgb(0.026, 0.037, 0.058)
  static let heroInk = rgb(0.956, 0.946, 0.931)
  static let heroMutedInk = rgb(0.648, 0.628, 0.594)
  static let accent = rgb(0.82, 0.28, 0.04)
  static let accentBright = rgb(0.914, 0.42, 0.153)
  static let indigo = rgb(0.29, 0.32, 0.72)
  static let bezel = rgb(0.082, 0.086, 0.101)
}

// MARK: - Shot specs

struct Spec {
  let raw: String
  let out: String
  let eyebrow: String
  let headline: [String]
  let sub: [String]
  let dark: Bool
  var showIcon = false
}

let specs: [Spec] = [
  Spec(
    raw: "01-home", out: "01-one-studio",
    eyebrow: "RESUME STUDIO",
    headline: ["Your whole job search,", "in one studio."],
    sub: ["Résumés, cover letters, interviews and", "applications — connected and private."],
    dark: true, showIcon: true
  ),
  Spec(
    raw: "02-preview", out: "02-the-resume",
    eyebrow: "THE RÉSUMÉ",
    headline: ["A résumé that", "looks the part."],
    sub: ["Polished PDF, DOCX and text exports —", "never watermarked, even on free."],
    dark: false
  ),
  Spec(
    raw: "03-templates", out: "03-templates",
    eyebrow: "TEMPLATES",
    headline: ["Change the look.", "Keep the story."],
    sub: ["Professional résumé templates with accent", "colours that carry into your PDF."],
    dark: false
  ),
  Spec(
    raw: "04-editor", out: "04-editor",
    eyebrow: "THE EDITOR",
    headline: ["Tell your story,", "section by section."],
    sub: ["Guided sections keep progress moving —", "and visible."],
    dark: false
  ),
  Spec(
    raw: "05-ats", out: "05-ats-check",
    eyebrow: "ATS CHECK",
    headline: ["Ready for the", "robots, too."],
    sub: ["An evidence-based readiness checklist —", "no invented match scores."],
    dark: false
  ),
  Spec(
    raw: "06-pipeline", out: "06-applications",
    eyebrow: "APPLICATIONS",
    headline: ["Know what's moving.", "And what needs you."],
    sub: ["Saved to offer — every application,", "interview and note in one pipeline."],
    dark: true
  ),
  Spec(
    raw: "07-voice", out: "07-interview-practice",
    eyebrow: "INTERVIEW PRACTICE",
    headline: ["Practise out loud.", "Improve with proof."],
    sub: ["Record answers, track pacing and filler", "words, then get coached."],
    dark: false
  ),
  Spec(
    raw: "08-intel", out: "08-career-tools",
    eyebrow: "CAREER INTELLIGENCE",
    headline: ["Every career tool.", "One studio."],
    sub: ["Evidence vault, job capture, offers,", "networking, LinkedIn and more."],
    dark: false
  ),
  Spec(
    raw: "09-cover", out: "09-cover-letters",
    eyebrow: "COVER LETTERS",
    headline: ["Cover letters", "that match."],
    sub: ["Styled like your résumé and", "exported in a tap."],
    dark: false
  ),
  Spec(
    raw: "10-coach", out: "10-career-coach",
    eyebrow: "CAREER COACH",
    headline: ["A coach in", "your corner."],
    sub: ["Answers grounded in your real résumé,", "applications and interviews."],
    dark: true
  ),
]

// MARK: - Font + text helpers

func serifFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
  let base = NSFont.systemFont(ofSize: size, weight: weight)
  if let descriptor = base.fontDescriptor.withDesign(.serif),
    let font = NSFont(descriptor: descriptor, size: size)
  {
    return font
  }
  return base
}

func sansFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
  NSFont.systemFont(ofSize: size, weight: weight)
}

@discardableResult
func drawLine(
  _ cg: CGContext, _ text: String, font: NSFont, color: CGColor,
  x: CGFloat, baselineY: CGFloat, kern: CGFloat = 0, centered: Bool = false
) -> CGFloat {
  let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor(cgColor: color) ?? .black,
    .kern: kern,
  ]
  let attributed = NSAttributedString(string: text, attributes: attributes)
  let line = CTLineCreateWithAttributedString(attributed)
  let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
  let drawX = centered ? x - width / 2 : x
  cg.textMatrix = .identity
  cg.textPosition = CGPoint(x: drawX, y: baselineY)
  CTLineDraw(line, cg)
  return width
}

// MARK: - Drawing helpers (bottom-left origin; "top" measured from canvas top)

func topY(_ fromTop: CGFloat, height: CGFloat = 0) -> CGFloat {
  canvasH - fromTop - height
}

func radialGlow(_ cg: CGContext, center: CGPoint, radius: CGFloat, color: CGColor, alpha: CGFloat) {
  guard let base = color.copy(alpha: alpha) else { return }
  let colors = [base, color.copy(alpha: 0)!] as CFArray
  guard
    let gradient = CGGradient(
      colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])
  else { return }
  cg.saveGState()
  cg.drawRadialGradient(
    gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius,
    options: [.drawsAfterEndLocation])
  cg.restoreGState()
}

func verticalGradient(_ cg: CGContext, rect: CGRect, top: CGColor, bottom: CGColor) {
  guard
    let gradient = CGGradient(
      colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
      colors: [top, bottom] as CFArray, locations: [0, 1])
  else { return }
  cg.saveGState()
  cg.clip(to: rect)
  cg.drawLinearGradient(
    gradient,
    start: CGPoint(x: rect.midX, y: rect.maxY),
    end: CGPoint(x: rect.midX, y: rect.minY),
    options: [])
  cg.restoreGState()
}

func loadCGImage(_ path: String) -> CGImage? {
  guard let image = NSImage(contentsOfFile: path) else { return nil }
  var rect = CGRect(origin: .zero, size: image.size)
  return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
}

func drawSymbol(
  _ cg: CGContext, name: String, tint: CGColor, pointSize: CGFloat,
  weight: NSFont.Weight, centerX: CGFloat, centerY: CGFloat
) -> CGFloat {
  guard
    let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: pointSize, weight: weight))
  else { return 0 }
  var proposed = CGRect(origin: .zero, size: symbol.size)
  guard let cgImage = symbol.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
    return 0
  }
  let width = CGFloat(cgImage.width)
  let height = CGFloat(cgImage.height)
  let rect = CGRect(x: centerX - width / 2, y: centerY - height / 2, width: width, height: height)
  cg.saveGState()
  cg.clip(to: rect, mask: cgImage)
  cg.setFillColor(tint)
  cg.fill(rect)
  cg.restoreGState()
  return width
}

// MARK: - Device frame

/// Draws the framed device with the screenshot, status bar and Dynamic Island.
func drawDevice(_ cg: CGContext, screenshot: CGImage, spec: Spec) {
  let screenW: CGFloat = 950
  let scale = screenW / rawW
  let screenH = rawH * scale
  let bezel: CGFloat = 42
  let screenRadius: CGFloat = 186 * scale  // ~62pt on device
  let deviceTop: CGFloat = 706

  let screenX = (canvasW - screenW) / 2
  let screenTop = deviceTop + bezel
  let screenRect = CGRect(
    x: screenX, y: topY(screenTop, height: screenH), width: screenW, height: screenH)
  let frameRect = screenRect.insetBy(dx: -bezel, dy: -bezel)
  let framePath = CGPath(
    roundedRect: frameRect, cornerWidth: screenRadius + bezel, cornerHeight: screenRadius + bezel,
    transform: nil)

  // Side buttons peeking out from behind the frame.
  cg.saveGState()
  cg.setFillColor(rgb(0.13, 0.135, 0.155))
  let buttonWidth: CGFloat = 9
  let buttons: [(CGFloat, CGFloat, Bool)] = [
    (430, 118, false),  // volume up (top offset, height, right side)
    (572, 118, false),  // volume down
    (300, 84, false),   // action
    (470, 176, true),   // power
  ]
  for (offset, height, right) in buttons {
    let x = right ? frameRect.maxX - 2 : frameRect.minX - buttonWidth + 2
    let rect = CGRect(
      x: x, y: topY(deviceTop + offset, height: height), width: buttonWidth, height: height)
    cg.addPath(CGPath(roundedRect: rect, cornerWidth: 4, cornerHeight: 4, transform: nil))
  }
  cg.fillPath()
  cg.restoreGState()

  // Frame with a deep soft shadow.
  cg.saveGState()
  cg.setShadow(
    offset: CGSize(width: 0, height: -34), blur: 96,
    color: rgb(0.02, 0.03, 0.05, spec.dark ? 0.62 : 0.30))
  cg.addPath(framePath)
  cg.setFillColor(Brand.bezel)
  cg.fillPath()
  cg.restoreGState()

  // Bezel edge highlights.
  cg.saveGState()
  cg.addPath(framePath)
  cg.setStrokeColor(rgb(1, 1, 1, spec.dark ? 0.16 : 0.32))
  cg.setLineWidth(2.5)
  cg.strokePath()
  let innerFrame = CGPath(
    roundedRect: frameRect.insetBy(dx: 3.5, dy: 3.5),
    cornerWidth: screenRadius + bezel - 3.5, cornerHeight: screenRadius + bezel - 3.5,
    transform: nil)
  cg.addPath(innerFrame)
  cg.setStrokeColor(rgb(0.30, 0.31, 0.35, 0.9))
  cg.setLineWidth(1.6)
  cg.strokePath()
  cg.restoreGState()

  // Screenshot, clipped to the display's corner radius.
  cg.saveGState()
  cg.addPath(
    CGPath(
      roundedRect: screenRect, cornerWidth: screenRadius, cornerHeight: screenRadius,
      transform: nil))
  cg.clip()
  cg.draw(screenshot, in: screenRect)
  cg.restoreGState()

  // Dynamic Island (raw metrics: 378 x 112, top inset 33).
  let islandW = 378 * scale
  let islandH = 112 * scale
  let islandTop = screenTop + 33 * scale
  let islandRect = CGRect(
    x: screenX + (screenW - islandW) / 2, y: topY(islandTop, height: islandH),
    width: islandW, height: islandH)
  cg.setFillColor(rgb(0, 0, 0))
  cg.addPath(
    CGPath(
      roundedRect: islandRect, cornerWidth: islandH / 2, cornerHeight: islandH / 2, transform: nil))
  cg.fillPath()

  // Status bar content — dark ink; every captured screen is light.
  let statusColor = rgb(0.09, 0.11, 0.15, 0.94)
  let statusCenterY = islandRect.midY
  let sideSegment = (screenW / 2 - islandW / 2)
  let timeCenterX = screenX + sideSegment / 2 + 12
  let timeFont = sansFont(38, .semibold)
  let timeWidth = CGFloat(
    CTLineGetTypographicBounds(
      CTLineCreateWithAttributedString(
        NSAttributedString(string: "9:41", attributes: [.font: timeFont])), nil, nil, nil))
  drawLine(
    cg, "9:41", font: timeFont, color: statusColor,
    x: timeCenterX - timeWidth / 2, baselineY: statusCenterY - 13)

  let iconsCenterX = screenX + screenW - sideSegment / 2 - 12
  _ = drawSymbol(
    cg, name: "cellularbars", tint: statusColor, pointSize: 21, weight: .bold,
    centerX: iconsCenterX - 74, centerY: statusCenterY)
  _ = drawSymbol(
    cg, name: "wifi", tint: statusColor, pointSize: 21, weight: .bold,
    centerX: iconsCenterX - 16, centerY: statusCenterY)

  // Battery drawn by hand: SF's battery symbols collide unpredictably at
  // marketing sizes, and a full charge reads better anyway.
  let batteryBody = CGRect(
    x: iconsCenterX + 26, y: statusCenterY - 13, width: 52, height: 26)
  cg.saveGState()
  cg.setStrokeColor(statusColor.copy(alpha: 0.42)!)
  cg.setLineWidth(2.6)
  cg.addPath(
    CGPath(roundedRect: batteryBody, cornerWidth: 8, cornerHeight: 8, transform: nil))
  cg.strokePath()
  cg.setFillColor(statusColor)
  cg.addPath(
    CGPath(
      roundedRect: batteryBody.insetBy(dx: 4.6, dy: 4.6), cornerWidth: 4.6, cornerHeight: 4.6,
      transform: nil))
  cg.fillPath()
  cg.setFillColor(statusColor.copy(alpha: 0.42)!)
  let capRect = CGRect(
    x: batteryBody.maxX + 3.4, y: statusCenterY - 5, width: 4.6, height: 10)
  cg.addPath(CGPath(roundedRect: capRect, cornerWidth: 2.3, cornerHeight: 2.3, transform: nil))
  cg.fillPath()
  cg.restoreGState()
}

// MARK: - Compose one screenshot

func compose(_ spec: Spec) -> Bool {
  guard let screenshot = loadCGImage("\(rawDir)/\(spec.raw).png") else {
    FileHandle.standardError.write("MISSING RAW: \(spec.raw)\n".data(using: .utf8)!)
    return false
  }

  guard
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: Int(canvasW), pixelsHigh: Int(canvasH),
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0),
    let nsContext = NSGraphicsContext(bitmapImageRep: rep)
  else { return false }

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = nsContext
  let cg = nsContext.cgContext
  cg.setAllowsAntialiasing(true)
  cg.interpolationQuality = .high

  let full = CGRect(x: 0, y: 0, width: canvasW, height: canvasH)

  // Background.
  if spec.dark {
    verticalGradient(cg, rect: full, top: Brand.heroTop, bottom: Brand.heroBottom)
    radialGlow(
      cg, center: CGPoint(x: canvasW + 40, y: topY(150)), radius: 860,
      color: Brand.accent, alpha: 0.24)
    radialGlow(
      cg, center: CGPoint(x: -60, y: topY(1500)), radius: 820,
      color: Brand.indigo, alpha: 0.22)
    radialGlow(
      cg, center: CGPoint(x: canvasW / 2, y: -140), radius: 900,
      color: Brand.accent, alpha: 0.12)
  } else {
    verticalGradient(cg, rect: full, top: Brand.paperTop, bottom: Brand.paperBottom)
    radialGlow(
      cg, center: CGPoint(x: canvasW - 150, y: topY(430)), radius: 860,
      color: Brand.accentBright, alpha: 0.15)
    radialGlow(
      cg, center: CGPoint(x: 40, y: topY(1900)), radius: 900,
      color: rgb(0.88, 0.78, 0.62), alpha: 0.34)
  }

  // Text block.
  let margin: CGFloat = 96
  var textX = margin
  let inkColor = spec.dark ? Brand.heroInk : Brand.ink
  let subColor = spec.dark ? Brand.heroMutedInk : Brand.mutedInk
  let eyebrowColor = spec.dark ? Brand.accentBright : Brand.accent

  // Optional app icon beside the eyebrow (flagship shot).
  if spec.showIcon, let icon = loadCGImage(iconPath) {
    let iconSize: CGFloat = 78
    let iconRect = CGRect(
      x: margin, y: topY(158, height: iconSize), width: iconSize, height: iconSize)
    let iconPathShape = CGPath(
      roundedRect: iconRect, cornerWidth: iconSize * 0.23, cornerHeight: iconSize * 0.23,
      transform: nil)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -8), blur: 26, color: rgb(0, 0, 0, 0.45))
    cg.addPath(iconPathShape)
    cg.setFillColor(rgb(1, 1, 1))
    cg.fillPath()
    cg.restoreGState()
    cg.saveGState()
    cg.addPath(iconPathShape)
    cg.clip()
    cg.draw(icon, in: iconRect)
    cg.restoreGState()
    cg.saveGState()
    cg.addPath(iconPathShape)
    cg.setStrokeColor(rgb(1, 1, 1, 0.22))
    cg.setLineWidth(1.5)
    cg.strokePath()
    cg.restoreGState()
    textX = margin + iconSize + 30
    drawLine(
      cg, spec.eyebrow, font: sansFont(34, .semibold), color: eyebrowColor,
      x: textX, baselineY: topY(158, height: iconSize) + iconSize / 2 - 12, kern: 5.5)
    textX = margin
  } else {
    drawLine(
      cg, spec.eyebrow, font: sansFont(34, .semibold), color: eyebrowColor,
      x: margin, baselineY: topY(206), kern: 5.5)
  }

  // Headline: New York serif, like the app's display face.
  let headlineFont = serifFont(104, .semibold)
  var baseline = topY(348)
  for line in spec.headline {
    drawLine(cg, line, font: headlineFont, color: inkColor, x: textX, baselineY: baseline)
    baseline -= 122
  }

  // Subheadline.
  var subBaseline = topY(spec.headline.count > 1 ? 566 : 444)
  for line in spec.sub {
    drawLine(cg, line, font: sansFont(44, .regular), color: subColor, x: textX, baselineY: subBaseline)
    subBaseline -= 60
  }

  drawDevice(cg, screenshot: screenshot, spec: spec)

  NSGraphicsContext.restoreGraphicsState()

  // Flatten to RGB (no alpha channel) — App Store screenshot validation
  // rejects transparency, and an opaque RGBA PNG still carries the channel.
  guard let rendered = rep.cgImage,
    let flattener = CGContext(
      data: nil, width: Int(canvasW), height: Int(canvasH), bitsPerComponent: 8,
      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
  else { return false }
  flattener.draw(rendered, in: full)
  guard let flat = flattener.makeImage() else { return false }

  let outURL = URL(fileURLWithPath: outDir).appendingPathComponent("\(spec.out).png")
  guard
    let destination = CGImageDestinationCreateWithURL(
      outURL as CFURL, "public.png" as CFString, 1, nil)
  else { return false }
  CGImageDestinationAddImage(destination, flat, nil)
  guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write("WRITE FAILED \(spec.out)\n".data(using: .utf8)!)
    return false
  }
  print("WROTE \(outURL.lastPathComponent)")
  return true
}

try? FileManager.default.createDirectory(
  at: URL(fileURLWithPath: outDir), withIntermediateDirectories: true)

var allOK = true
for spec in specs {
  if !compose(spec) { allOK = false }
}
exit(allOK ? 0 : 1)
