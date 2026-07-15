import Foundation
import SwiftUI

struct CoverLetterDocument: Codable, Equatable, Hashable {
  var senderName: String
  var senderHeadline: String
  var senderPhone: String
  var senderEmail: String
  var date: Date
  var recipientName: String
  var recipientTitle: String
  var companyName: String
  var companyAddress: String
  var jobTitle: String
  var subject: String
  var greeting: String
  var bodyParagraphs: [String]
  var closing: String
  var template: CoverLetterTemplate
  var accent: ResumeAccent
  /// Kept locally to power AI generation; never printed in the letter.
  var jobDescription: String

  var suggestedFilename: String {
    let role = jobTitle.nilIfBlank ?? "Cover Letter"
    let company = companyName.nilIfBlank.map { " - \($0)" } ?? ""
    let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
    return "\(role)\(company)".components(separatedBy: invalid).joined(separator: "-")
  }

  var isReadyToPreview: Bool {
    !senderName.isBlank && !companyName.isBlank && bodyParagraphs.contains { !$0.isBlank }
  }

  /// The monogram letterhead sets these in its mark. Falls back the same way the
  /// résumé's portrait does, so an unnamed draft still prints something sane.
  var initials: String {
    let letters = senderName
      .split(separator: " ")
      .prefix(2)
      .compactMap(\.first)
    return letters.isEmpty ? "?" : String(letters).uppercased()
  }

  static let blank = CoverLetterDocument(
    senderName: "",
    senderHeadline: "",
    senderPhone: "",
    senderEmail: "",
    date: Date(),
    recipientName: "",
    recipientTitle: "",
    companyName: "",
    companyAddress: "",
    jobTitle: "",
    subject: "",
    greeting: "Dear Hiring Manager,",
    bodyParagraphs: [""],
    closing: "Kind regards,",
    template: .modern,
    accent: .orange,
    jobDescription: ""
  )

  static let example = CoverLetterDocument(
    senderName: "Avery Sample",
    senderHeadline: "People Operations Manager",
    senderPhone: "+1 202 555 0147",
    senderEmail: "avery.sample@example.com",
    date: Date(),
    recipientName: "Jordan Lee",
    recipientTitle: "Director of People",
    companyName: "Evergreen Labs",
    companyAddress: "100 Market Street\nSan Francisco, CA",
    jobTitle: "Senior People Operations Manager",
    subject: "Application for Senior People Operations Manager",
    greeting: "Dear Jordan Lee,",
    bodyParagraphs: [
      "I am writing to apply for the Senior People Operations Manager role at Evergreen Labs. My background in employee experience, manager enablement, and scalable people programmes aligns closely with the priorities described for this position.",
      "At Northstar Works, I built a quarterly people-planning rhythm connecting hiring, development, and retention priorities. I also introduced practical manager coaching resources and simplified onboarding workflows across the employee lifecycle.",
      "I would welcome the opportunity to bring this combination of thoughtful programme design and hands-on operational delivery to Evergreen Labs. Thank you for considering my application.",
    ],
    closing: "Kind regards,",
    template: .modern,
    accent: .orange,
    jobDescription: ""
  )
}

/// The letter styles.
///
/// The matched letters are deliberate counterparts to particular résumé
/// templates: a letter that arrives with a matching letterhead — same colour,
/// same rail, same contact icons — reads as one application rather than two
/// documents that happened to be attached to the same email.
enum CoverLetterTemplate: String, CaseIterable, Codable, Identifiable {
  case modern
  case gradient
  case executive
  case monogram
  case sidebar
  case minimal
  case memo
  case iconic
  case creative
  case rail
  case portfolio
  case cardstock
  case classic
  case letterpress
  case broadsheet
  case signature
  case noir
  case marquee
  case crest
  case ivy
  case plinth
  case stockholm
  case laureate
  case nova
  case aurelia
  case nocturne
  case eclipse
  case vantage
  case zenith
  case aperture
  case sovereign
  case blueprint
  case spectrum
  case halo
  case volta
  // The Signature Collection letters — matched to the résumés of the same name.
  case obsidian
  case radiant
  case verge
  case datum
  case pinnacle
  case emblem
  case cadence
  case citadel
  case stratus
  case mirage
  // The Showcase Collection: letterheads that echo the ten Showcase résumés.
  case salute
  case couture
  case medallion
  case sable
  case terracotta
  case lozenge
  case circlet
  case vogue
  case signet
  case almanac

  var id: String { rawValue }

  /// The résumé this letter was drawn to sit beside.
  var pairsWith: ResumeTemplate? {
    switch self {
    case .sidebar: .atlas
    case .iconic: .signal
    case .rail: .chronicle
    case .cardstock: .strata
    case .broadsheet: .gazette
    case .noir: .noir
    case .marquee: .marquee
    case .crest: .crest
    case .ivy: .ivy
    case .plinth: .plinth
    case .stockholm: .stockholm
    case .laureate: .laureate
    case .nova: .nova
    case .aurelia: .aurelia
    case .nocturne: .nocturne
    case .eclipse: .eclipse
    case .vantage: .vantage
    case .zenith: .zenith
    case .aperture: .aperture
    case .sovereign: .sovereign
    case .blueprint: .blueprint
    case .spectrum: .spectrum
    case .halo: .halo
    case .volta: .volta
    case .obsidian: .obsidian
    case .radiant: .radiant
    case .verge: .verge
    case .datum: .datum
    case .pinnacle: .pinnacle
    case .emblem: .emblem
    case .cadence: .cadence
    case .citadel: .citadel
    case .stratus: .stratus
    case .mirage: .mirage
    case .salute: .salute
    case .couture: .couture
    case .medallion: .medallion
    case .sable: .sable
    case .terracotta: .terracotta
    case .lozenge: .lozenge
    case .circlet: .circlet
    case .vogue: .vogue
    case .signet: .signet
    case .almanac: .almanac
    default: nil
    }
  }

  var title: String {
    switch self {
    case .sidebar: "Sidebar Letterhead"
    case .iconic: "Icon Contact"
    case .rail: "Rail Note"
    case .cardstock: "Cardstock"
    case .broadsheet: "Broadsheet"
    case .modern: "Modern Professional"
    case .gradient: "Gradient Banner"
    case .executive: "Executive Header"
    case .monogram: "Monogram Mark"
    case .minimal: "Clean Minimal"
    case .memo: "Memo Brief"
    case .creative: "Creative Accent"
    case .portfolio: "Portfolio Card"
    case .classic: "Classic Formal"
    case .letterpress: "Letterpress Serif"
    case .signature: "Signature Note"
    case .noir: "Noir Ink"
    case .marquee: "Marquee Type"
    case .crest: "Crest Banner"
    case .ivy: "Ivy Formal"
    case .plinth: "Plinth Footer"
    case .stockholm: "Stockholm Note"
    case .laureate: "Laureate Standard"
    case .nova: "Nova Banner"
    case .aurelia: "Aurelia Ornament"
    case .nocturne: "Nocturne Serif"
    case .eclipse: "Eclipse Letter"
    case .vantage: "Vantage Statement"
    case .salute: "Salute Greeting Letter"
    case .couture: "Couture Vertical Letter"
    case .medallion: "Medallion Seal Letter"
    case .sable: "Sable Sidebar Letter"
    case .terracotta: "Terracotta Circle Letter"
    case .lozenge: "Lozenge Pill Letter"
    case .circlet: "Circlet Orbit Letter"
    case .vogue: "Vogue Editorial Letter"
    case .signet: "Signet Seal Letter"
    case .almanac: "Almanac Brief Letter"
    case .zenith: "Zenith Dispatch"
    case .aperture: "Aperture Letter"
    case .sovereign: "Sovereign Letterhead"
    case .blueprint: "Blueprint Brief"
    case .spectrum: "Spectrum Statement"
    case .halo: "Halo Correspondence"
    case .volta: "Volta Manifesto"
    case .obsidian: "Obsidian Letter"
    case .radiant: "Radiant Halo Letter"
    case .verge: "Verge Duotone Letter"
    case .datum: "Datum Brief"
    case .pinnacle: "Pinnacle Letterhead"
    case .emblem: "Emblem Monogram Letter"
    case .cadence: "Cadence Note"
    case .citadel: "Citadel Dispatch"
    case .stratus: "Stratus Statement"
    case .mirage: "Mirage Letter"
    }
  }

  var subtitle: String {
    switch self {
    case .sidebar: "Contact column in colour, to match Atlas"
    case .iconic: "Icon contact strip, to match Signal"
    case .rail: "Accent rail and a dated mark, to match Chronicle"
    case .cardstock: "The letter set on a soft card, to match Strata"
    case .broadsheet: "Serif rules and a dated margin, to match Gazette"
    case .modern: "Bold name and crisp accent rule"
    case .gradient: "Colour banner fading into ink"
    case .executive: "Confident leadership presentation"
    case .monogram: "Initials set in a solid accent mark"
    case .minimal: "Quiet typography and open space"
    case .memo: "Ruled brief with a labelled sender block"
    case .creative: "Distinctive blocks with personality"
    case .portfolio: "Soft card with an accent rail"
    case .classic: "Traditional serif correspondence"
    case .letterpress: "Centred serif between printed rules"
    case .signature: "Editorial letterhead with a personal side mark"
    case .noir: "Light ink on a dark page, to match Noir"
    case .marquee: "Your name at poster size, to match Marquee"
    case .crest: "Navy banner letterhead, to match Crest"
    case .ivy: "Plain centred serif, to match Ivy League"
    case .plinth: "Contact in a colour footer, to match Plinth"
    case .stockholm: "Tinted letterhead, quiet type, to match Stockholm"
    case .laureate: "Two-tone name over a fine rule, to match Laureate"
    case .nova: "Colour banner letterhead, to match Nova"
    case .aurelia: "Fine serif and an ornament rule, to match Aurelia"
    case .nocturne: "A serif letter on the dark page, to match Nocturne"
    case .eclipse: "Orbiting colour and a monogram halo, to match Eclipse"
    case .vantage: "Editorial hero masthead with commanding contrast"
    case .salute: "A warm hello and a round monogram, to match Salute"
    case .couture: "The name set up the page, to match Couture"
    case .medallion: "A circular monogram seal, to match Medallion"
    case .sable: "A dark banner header, to match Sable"
    case .terracotta: "An earthen band and profile circle, to match Terracotta"
    case .lozenge: "Capsule contact labels, to match Lozenge"
    case .circlet: "A ringed monogram with orbiting dots, to match Circlet"
    case .vogue: "An oversized serif masthead, to match Vogue"
    case .signet: "A pressed wax-seal monogram, to match Signet"
    case .almanac: "An icon-led fact strip, to match Almanac"
    case .zenith: "Crowned portrait hero and executive hierarchy, to match Zenith"
    case .aperture: "Cinematic portrait window and focused details, to match Aperture"
    case .sovereign: "Regal editorial rules and date-led authority, to match Sovereign"
    case .blueprint: "Measured drafting grid and technical labels, to match Blueprint"
    case .spectrum: "Layered colour bands frame a bold application statement"
    case .halo: "Orbiting monogram and sculpted contact arc, to match Halo"
    case .volta: "Electric spine and high-energy typography, to match Volta"
    case .obsidian: "Stacked glass panels on midnight, to match Obsidian"
    case .radiant: "A radial halo behind a warm hello, to match Radiant"
    case .verge: "A two-tone diagonal masthead, to match Verge"
    case .datum: "Tiled metrics over a crisp brief, to match Datum"
    case .pinnacle: "An architected frame and keystone, to match Pinnacle"
    case .emblem: "A hexagon monogram letterhead, to match Emblem"
    case .cadence: "An equaliser of accent bars, to match Cadence"
    case .citadel: "Fortress framing and firm type, to match Citadel"
    case .stratus: "Soft gradient bands drift up top, to match Stratus"
    case .mirage: "A shimmering gradient masthead, to match Mirage"
    }
  }

  var systemImage: String {
    switch self {
    case .sidebar: "sidebar.left"
    case .iconic: "checkmark.seal.fill"
    case .rail: "point.topleft.down.to.point.bottomright.curvepath"
    case .cardstock: "square.stack.3d.up.fill"
    case .broadsheet: "newspaper.fill"
    case .modern: "rectangle.topthird.inset.filled"
    case .gradient: "sun.horizon.fill"
    case .executive: "building.columns.fill"
    case .monogram: "a.square.fill"
    case .minimal: "doc.plaintext"
    case .memo: "list.clipboard.fill"
    case .creative: "square.grid.2x2.fill"
    case .portfolio: "rectangle.portrait.on.rectangle.portrait.fill"
    case .classic: "text.book.closed.fill"
    case .letterpress: "textformat.alt"
    case .signature: "signature"
    case .noir: "moon.fill"
    case .marquee: "textformat.size"
    case .crest: "flag.fill"
    case .ivy: "building.columns.fill"
    case .plinth: "dock.rectangle"
    case .stockholm: "rectangle.righthalf.inset.filled"
    case .laureate: "laurel.leading"
    case .nova: "rectangle.topthird.inset.filled"
    case .aurelia: "diamond"
    case .nocturne: "moon.stars.fill"
    case .eclipse: "circle.circle.fill"
    case .vantage: "rectangle.tophalf.inset.filled"
    case .salute: "hand.wave.fill"
    case .couture: "textformat.abc.dottedunderline"
    case .medallion: "seal.fill"
    case .sable: "sidebar.left"
    case .terracotta: "circle.circle.fill"
    case .lozenge: "capsule.portrait.fill"
    case .circlet: "circle.dashed.inset.filled"
    case .vogue: "textformat.size.larger"
    case .signet: "checkmark.seal.fill"
    case .almanac: "chart.bar.xaxis"
    case .zenith: "crown.fill"
    case .aperture: "camera.aperture"
    case .sovereign: "seal.fill"
    case .blueprint: "ruler.fill"
    case .spectrum: "rainbow"
    case .halo: "circle.dotted.circle.fill"
    case .volta: "bolt.ring.closed"
    case .obsidian: "square.stack.3d.down.right.fill"
    case .radiant: "sun.max.fill"
    case .verge: "triangle.righthalf.filled"
    case .datum: "chart.bar.doc.horizontal.fill"
    case .pinnacle: "building.columns.fill"
    case .emblem: "hexagon.fill"
    case .cadence: "waveform"
    case .citadel: "building.2.fill"
    case .stratus: "cloud.fill"
    case .mirage: "aqi.medium"
    }
  }

  var styleTags: Set<TemplateStyleTag> {
    switch self {
    case .sidebar: [.structured, .bold, .modern]
    case .iconic: [.structured, .modern, .creative]
    case .rail: [.structured, .modern, .clean]
    case .cardstock: [.structured, .creative, .clean]
    case .broadsheet: [.structured, .classic, .clean]
    case .modern: [.modern, .clean]
    case .gradient: [.bold, .creative, .modern]
    case .executive: [.classic, .bold]
    case .monogram: [.bold, .modern, .creative]
    case .minimal: [.modern, .clean]
    case .memo: [.clean, .ats, .modern]
    case .creative: [.bold, .creative]
    case .portfolio: [.clean, .creative]
    case .classic: [.classic, .clean]
    case .letterpress: [.classic, .clean, .ats]
    case .signature: [.classic, .creative]
    case .noir: [.bold, .creative, .modern]
    case .marquee: [.bold, .creative]
    case .crest: [.bold, .modern]
    case .ivy: [.classic, .clean, .ats]
    case .plinth: [.modern, .clean]
    case .stockholm: [.modern, .clean, .structured]
    case .laureate: [.classic, .modern, .ats]
    case .nova: [.bold, .modern, .creative]
    case .aurelia: [.classic, .clean, .creative]
    case .nocturne: [.bold, .classic, .creative]
    case .eclipse: [.bold, .creative, .modern]
    case .vantage: [.bold, .modern, .creative]
    case .salute: [.showcase, .modern, .clean]
    case .couture: [.showcase, .creative, .bold]
    case .medallion: [.showcase, .creative, .modern]
    case .sable: [.showcase, .bold, .modern]
    case .terracotta: [.showcase, .creative, .classic]
    case .lozenge: [.showcase, .clean, .modern]
    case .circlet: [.showcase, .creative, .modern]
    case .vogue: [.showcase, .creative, .classic, .bold]
    case .signet: [.showcase, .classic, .clean]
    case .almanac: [.showcase, .modern, .creative, .bold]
    case .zenith: [.bold, .modern, .creative]
    case .aperture: [.structured, .modern, .creative]
    case .sovereign: [.classic, .bold, .clean]
    case .blueprint: [.structured, .modern, .ats]
    case .spectrum: [.bold, .creative, .modern]
    case .halo: [.creative, .modern, .clean]
    case .volta: [.bold, .creative, .modern]
    case .obsidian: [.bold, .modern, .creative]
    case .radiant: [.modern, .creative, .clean]
    case .verge: [.bold, .modern]
    case .datum: [.structured, .modern, .clean]
    case .pinnacle: [.classic, .bold]
    case .emblem: [.bold, .modern, .clean]
    case .cadence: [.modern, .creative, .bold]
    case .citadel: [.classic, .bold, .structured]
    case .stratus: [.clean, .modern, .creative]
    case .mirage: [.modern, .creative]
    }
  }

  /// The coordinated letterheads introduced with the Advanced and Signature
  /// collections. Their index selects a bespoke construction in both the PDF and
  /// gallery art.
  var advancedOrdinal: Int? {
    switch self {
    case .zenith: 0
    case .aperture: 1
    case .sovereign: 2
    case .blueprint: 3
    case .spectrum: 4
    case .halo: 5
    case .volta: 6
    case .obsidian: 7
    case .radiant: 8
    case .verge: 9
    case .datum: 10
    case .pinnacle: 11
    case .emblem: 12
    case .cadence: 13
    case .citadel: 14
    case .stratus: 15
    case .mirage: 16
    case .salute: 17
    case .couture: 18
    case .medallion: 19
    case .sable: 20
    case .terracotta: 21
    case .lozenge: 22
    case .circlet: 23
    case .vogue: 24
    case .signet: 25
    case .almanac: 26
    default: nil
    }
  }
}
