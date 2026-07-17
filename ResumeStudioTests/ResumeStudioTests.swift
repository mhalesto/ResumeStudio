import PDFKit
import UIKit
import XCTest

@testable import ResumeStudio

@MainActor
final class ResumeStudioTests: XCTestCase {
  func testMonetizationAllowancesAndCatalogStayIntentional() {
    XCTAssertEqual(ResumeStudioPlan.free.monthlyAICredits, 5)
    XCTAssertEqual(ResumeStudioPlan.go.monthlyAICredits, 35)
    XCTAssertEqual(ResumeStudioPlan.pro.monthlyAICredits, 150)
    XCTAssertEqual(ResumeStudioPlan.free.hostedReviewRoomLimit, 0)
    XCTAssertEqual(ResumeStudioPlan.go.hostedReviewRoomLimit, 1)
    XCTAssertEqual(ResumeStudioPlan.pro.hostedReviewRoomLimit, 10)
    XCTAssertEqual(ResumeStudioPlan.free.dailyAIImportLimit, 5)
    XCTAssertEqual(ResumeStudioPlan.go.dailyAIImportLimit, 20)
    XCTAssertEqual(ResumeStudioPlan.pro.dailyAIImportLimit, 30)

    XCTAssertEqual(MonetizationCatalog.freeResumeTemplates.count, 34)
    XCTAssertEqual(MonetizationCatalog.freeCoverLetterTemplates.count, 16)
    XCTAssertTrue(MonetizationCatalog.freeResumeTemplates.isSubset(of: Set(ResumeTemplate.allCases)))
    XCTAssertTrue(MonetizationCatalog.freeCoverLetterTemplates.isSubset(of: Set(CoverLetterTemplate.allCases)))

    // The four original accents are free; the ten Signature and Atelier tones
    // are subscription only, gated the same way the premium templates are.
    XCTAssertEqual(MonetizationCatalog.freeAccents.count, 4)
    XCTAssertEqual(MonetizationCatalog.freeAccents, [.orange, .blue, .teal, .burgundy])
    XCTAssertEqual(ResumeAccent.allCases.filter(\.isPremium).count, 10)
    for accent in ResumeAccent.allCases {
      XCTAssertEqual(accent.isPremium, !MonetizationCatalog.freeAccents.contains(accent))
    }

    XCTAssertEqual(Set(ResumeStudioProduct.allIDs).count, 3)
    XCTAssertTrue(ResumeStudioProduct.subscriptionIDs.contains(ResumeStudioProduct.goMonthly))
    XCTAssertTrue(ResumeStudioProduct.subscriptionIDs.contains(ResumeStudioProduct.proMonthly))
    XCTAssertFalse(ResumeStudioProduct.subscriptionIDs.contains(ResumeStudioProduct.designForever))
  }

  func testAIWeightsMatchThePublishedCreditExamples() {
    XCTAssertEqual(ResumeAIAction.importResume.creditCost, 0)
    XCTAssertEqual(ResumeAIAction.improveBullet.creditCost, 1)
    XCTAssertEqual(ResumeAIAction.careerCoach.creditCost, 1)
    XCTAssertEqual(ResumeAIAction.writeCoverLetter.creditCost, 3)
    XCTAssertEqual(ResumeAIAction.evaluateInterviewAnswer.creditCost, 3)
    XCTAssertEqual(ResumeAIAction.tailorResume.creditCost, 5)
    XCTAssertEqual(ResumeAIAction.interviewPrep.creditCost, 5)
    XCTAssertEqual(ResumeAIAction.translateResume.creditCost, 5)
  }

  func testOfflineAccessNeverInventsOrExtendsPaidAccess() {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    XCTAssertEqual(
      OfflineAccessPolicy.resolve(nil, now: now),
      OfflineAccessDecision(plan: .free, hasDesignPack: false, subscriptionExpiry: nil))

    let expired = OfflineEntitlements(
      plan: .pro, subscriptionExpiry: now.addingTimeInterval(-1),
      hasDesignPack: false, verifiedAt: now.addingTimeInterval(-86_400))
    XCTAssertEqual(
      OfflineAccessPolicy.resolve(expired, now: now),
      OfflineAccessDecision(plan: .free, hasDesignPack: false, subscriptionExpiry: nil))

    let expiry = now.addingTimeInterval(86_400)
    let active = OfflineEntitlements(
      plan: .go, subscriptionExpiry: expiry,
      hasDesignPack: false, verifiedAt: now.addingTimeInterval(-3_600))
    XCTAssertEqual(
      OfflineAccessPolicy.resolve(active, now: now),
      OfflineAccessDecision(plan: .go, hasDesignPack: false, subscriptionExpiry: expiry))

    let designPack = OfflineEntitlements(
      plan: .free, subscriptionExpiry: nil,
      hasDesignPack: true, verifiedAt: now.addingTimeInterval(-100_000))
    XCTAssertEqual(
      OfflineAccessPolicy.resolve(designPack, now: now),
      OfflineAccessDecision(plan: .free, hasDesignPack: true, subscriptionExpiry: nil))
  }

  func testEntitlementContinuityDistinguishesMissingFromRevokedStoreData() {
    let cachedPro = OfflineAccessDecision(
      plan: .pro,
      hasDesignPack: true,
      subscriptionExpiry: Date().addingTimeInterval(86_400)
    )

    XCTAssertTrue(
      EntitlementContinuityPolicy.shouldRetainCachedSubscription(
        cachedPro, resolvedPlan: .free, authoritativeProductIDs: []))
    XCTAssertFalse(
      EntitlementContinuityPolicy.shouldRetainCachedSubscription(
        cachedPro,
        resolvedPlan: .free,
        authoritativeProductIDs: [ResumeStudioProduct.proMonthly]
      ))
    XCTAssertTrue(
      EntitlementContinuityPolicy.shouldRetainCachedDesignPack(
        cachedPro, resolvedDesignPack: false, authoritativeProductIDs: []))
    XCTAssertFalse(
      EntitlementContinuityPolicy.shouldRetainCachedDesignPack(
        cachedPro,
        resolvedDesignPack: false,
        authoritativeProductIDs: [ResumeStudioProduct.designForever]
      ))
  }

  func testTemplateCatalogueIsDistinct() {
    XCTAssertEqual(ResumeTemplate.allCases.count, 131)

    // Every template is its own look: no shared names, no shared descriptions.
    XCTAssertEqual(Set(ResumeTemplate.allCases.map(\.title)).count, 131)
    XCTAssertEqual(Set(ResumeTemplate.allCases.map(\.subtitle)).count, 131)
    XCTAssertEqual(Set(ResumeTemplate.allCases.map(\.rawValue)).count, 131)

    // The photo-led ones build their header around the portrait. Everything else
    // takes a photo too — it just closes the space up without one.
    XCTAssertEqual(
      ResumeTemplate.allCases.filter(\.isPhotoLed),
      [
        .atlas, .portrait, .spotlight, .beacon, .harbor, .bloom, .atelier, .canvas, .insignia,
        .nova, .monarch, .eclipse, .aperture, .gallery, .halo, .orbit, .panorama, .spectrum,
        .zenith, .alcove, .radiant, .zephyr, .vellum,
        .salute, .couture, .medallion, .sable, .terracotta, .circlet, .vogue,
      ]
    )
  }

  func testAdvancedCollectionAndFreeShowcaseStayIntentional() throws {
    let advanced = ResumeTemplate.allCases.filter { $0.advancedStyle != nil }
    XCTAssertEqual(advanced.count, 62)
    XCTAssertEqual(Set(advanced.compactMap { $0.advancedStyle?.ordinal }), Set(0..<62))

    let freeAdvanced = Set(advanced).intersection(MonetizationCatalog.freeResumeTemplates)
    XCTAssertEqual(freeAdvanced.count, 22)
    XCTAssertEqual(
      freeAdvanced,
      [
        .apex, .aperture, .arclight, .blueprint, .catalyst,
        .circuit, .continuum, .district, .ember, .facet,
        .gallery, .halo, .helix, .kinetic, .lattice,
        .nexus, .orbit, .panorama, .quantum, .ribbon,
        .salute, .lozenge,
      ]
    )
    XCTAssertEqual(Set(advanced).subtracting(freeAdvanced).count, 40)

    // The twenty Signature Collection mastheads reach beyond the first thirty-two
    // into constructions 8-15, each addressed explicitly rather than by modulo.
    let signature = advanced.filter {
      let ordinal = $0.advancedStyle?.ordinal ?? 0
      return ordinal >= 32 && ordinal < 52
    }
    XCTAssertEqual(signature.count, 20)
    for template in signature {
      let style = try XCTUnwrap(template.advancedStyle)
      XCTAssertGreaterThanOrEqual(style.motif, 8, template.title)
      XCTAssertLessThanOrEqual(style.motif, 15, template.title)
      XCTAssertLessThanOrEqual(style.variant, 3, template.title)
    }

    // The ten Showcase mastheads occupy their own constructions, 16-25, and all
    // carry the Showcase tag so they group together in the gallery.
    let showcase = advanced.filter { ($0.advancedStyle?.ordinal ?? 0) >= 52 }
    XCTAssertEqual(showcase.count, 10)
    for template in showcase {
      let style = try XCTUnwrap(template.advancedStyle)
      XCTAssertGreaterThanOrEqual(style.motif, 16, template.title)
      XCTAssertLessThanOrEqual(style.motif, 25, template.title)
      XCTAssertTrue(style.styleTags.contains(.showcase), template.title)
    }
    XCTAssertEqual(
      ResumeTemplate.allCases.filter { $0.styleTags.contains(.showcase) }.count, 10)
  }

  /// The point of the structural templates: they rearrange the page, not the
  /// letterhead. Fifty-one of them do, and each does it differently — otherwise they
  /// are just more headers on the same one-column résumé.
  func testStructuralTemplatesActuallyRestructureThePage() {
    let structural = ResumeTemplate.allCases.filter { $0.styleTags.contains(.structured) }
    XCTAssertEqual(structural.count, 51)

    // Every structural template departs from the plain single-column flow...
    for template in structural {
      XCTAssertNotEqual(template.plan, TemplatePlan(), template.title)
    }

    // No two of them are built the same way.
    XCTAssertEqual(Set(structural.map(\.plan)).count, structural.count)

    // Twenty-five run a column of their own; the ATS check has to warn about exactly
    // those, since a parser can read two columns out of order.
    XCTAssertEqual(
      structural.filter { $0.plan.hasSideColumn },
      [
        .atlas, .verso, .oxford, .duo, .concise, .gauge, .crest, .geneva,
        .stockholm, .tandem, .varsity, .prism,
        .aperture, .blueprint, .circuit, .district, .facet, .helix, .lattice, .panorama,
        .quantum, .sentinel, .tessera, .alcove, .palisade,
      ]
    )
  }

  func testColumnWarningTracksTheTemplateRatherThanTheWording() {
    var sidebar = ResumeDocument.example
    sidebar.template = .atlas
    let sidebarReport = ATSReadinessService.analyze(document: sidebar)
    XCTAssertTrue(sidebarReport.items.contains { $0.id == "columns" && $0.severity == .warning })

    var single = ResumeDocument.example
    single.template = .modern
    let singleReport = ATSReadinessService.analyze(document: single)
    XCTAssertTrue(singleReport.items.contains { $0.id == "columns" && $0.severity == .pass })
  }

  /// The point of the photo rework: a portrait is optional everywhere, so every
  /// template must render one, and every template must still render without one.
  func testEveryTemplateRendersWithAndWithoutAPortrait() throws {
    let photo = try XCTUnwrap(ProfilePhoto.prepare(Self.samplePhotoData()))

    for template in ResumeTemplate.allCases {
      var withPhoto = ResumeDocument.example
      withPhoto.template = template
      withPhoto.photo = photo
      XCTAssertTrue(withPhoto.showsPortrait, template.title)

      var withoutPhoto = ResumeDocument.example
      withoutPhoto.template = template
      XCTAssertEqual(withoutPhoto.showsPortrait, template.isPhotoLed, template.title)

      var hiddenPhoto = withPhoto
      hiddenPhoto.isPhotoVisible = false
      XCTAssertFalse(hiddenPhoto.showsPortrait, template.title)

      for document in [withPhoto, withoutPhoto, hiddenPhoto] {
        let pdf = try XCTUnwrap(
          PDFDocument(data: try ResumePDFRenderer.render(document: document)))
        XCTAssertGreaterThanOrEqual(pdf.pageCount, 1, template.title)

        // A portrait must never push the letterhead over the text: the name and
        // the first role still have to be on the page, and readable.
        let text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined()
        XCTAssertTrue(text.contains("Avery Sample"), template.title)
        XCTAssertTrue(text.contains("People Operations Manager"), template.title)
      }
    }
  }

  /// Privacy regression: keeping a photo in the saved résumé while hiding it
  /// must produce exactly the same visible page as a résumé with no photo data.
  /// Comparing page pixels catches template-specific drawing that text checks miss.
  func testHiddenPhotoCannotAffectAnyRenderedTemplate() throws {
    let photo = try XCTUnwrap(ProfilePhoto.prepare(Self.samplePhotoData()))
    let thumbnailSize = CGSize(width: 180, height: 254)

    for template in ResumeTemplate.allCases {
      var hiddenWithPhoto = ResumeDocument.example
      hiddenWithPhoto.template = template
      hiddenWithPhoto.photo = photo
      hiddenWithPhoto.photoCrop = PhotoCrop(centerX: 0.42, centerY: 0.58, zoom: 1.4)
      hiddenWithPhoto.isPhotoVisible = false

      var hiddenWithoutPhoto = hiddenWithPhoto
      hiddenWithoutPhoto.photo = nil
      hiddenWithoutPhoto.photoCrop = nil

      let storedPhotoPage = try XCTUnwrap(
        PDFDocument(data: ResumePDFRenderer.render(document: hiddenWithPhoto))?.page(at: 0),
        template.title
      )
      let noPhotoPage = try XCTUnwrap(
        PDFDocument(data: ResumePDFRenderer.render(document: hiddenWithoutPhoto))?.page(at: 0),
        template.title
      )
      let storedPhotoPixels = storedPhotoPage.thumbnail(
        of: thumbnailSize, for: .mediaBox
      ).pngData()
      let noPhotoPixels = noPhotoPage.thumbnail(
        of: thumbnailSize, for: .mediaBox
      ).pngData()

      XCTAssertEqual(
        storedPhotoPixels,
        noPhotoPixels,
        "\(template.title) rendered stored photo data while Show in CV was off"
      )
    }
  }

  /// Contemporary Split's name box was a hair too short for the two lines a full
  /// name wraps onto in its narrow panel, so the surname was never drawn — not
  /// clipped, not shrunk, simply absent from the page. The old test missed it
  /// because page two's header still carried the name, so assert on page one.
  ///
  /// Page one prints the name twice: the letterhead and the footer. Counting is
  /// what makes this bite — the footer alone would satisfy a plain `contains`,
  /// and matching has to ignore case because two letterheads set the name in
  /// capitals.
  func testEveryTemplatePrintsTheWholeNameOnPageOne() throws {
    for template in ResumeTemplate.allCases {
      var document = ResumeDocument.example
      document.template = template
      document.personal.fullName = "Avery Fitzwilliam"

      let pdf = try XCTUnwrap(PDFDocument(data: try ResumePDFRenderer.render(document: document)))
      let firstPage = try XCTUnwrap(pdf.page(at: 0)?.string).lowercased()
      for part in ["avery", "fitzwilliam"] {
        let occurrences = firstPage.components(separatedBy: part).count - 1
        XCTAssertGreaterThanOrEqual(occurrences, 2, "\(template.title): \(part)")
      }
    }
  }

  /// Creative Accent dropped the surname out of its narrow colour panel for the
  /// same reason. The letter prints the sender's name twice on page one — the
  /// letterhead and the sign-off — so one occurrence means the letterhead lost it.
  func testEveryCoverLetterPrintsTheSenderNameInItsLetterhead() throws {
    for template in CoverLetterTemplate.allCases {
      var document = CoverLetterDocument.example
      document.template = template

      let pdf = try XCTUnwrap(
        PDFDocument(data: try CoverLetterPDFRenderer.render(document: document)))
      let firstPage = try XCTUnwrap(pdf.page(at: 0)?.string)
      let occurrences = firstPage.components(separatedBy: "Sample").count - 1
      XCTAssertGreaterThanOrEqual(occurrences, 2, template.title)
    }
  }

  /// A visual-review artifact for the templates added in the greatest-hits
  /// pass — the ten modelled on the web's most-reviewed formats. The PNGs are
  /// also attached to the test result so they remain inspectable after CI has
  /// cleaned its temporary directory.
  func testNewTemplateContactSheets() throws {
    let resumeTemplates: [ResumeTemplate] = [
      .stockholm, .tandem, .varsity, .laureate, .modena,
      .nova, .prism, .aurelia, .nocturne, .monarch,
    ]
    let letterTemplates: [CoverLetterTemplate] = [
      .stockholm, .laureate, .nova, .aurelia, .nocturne,
    ]

    let resumeItems = try resumeTemplates.map { template in
      var document = ResumeDocument.example
      document.template = template
      let pdf = try XCTUnwrap(PDFDocument(data: ResumePDFRenderer.render(document: document)))
      let page = try XCTUnwrap(pdf.page(at: 0))
      return (template.title, page.thumbnail(of: CGSize(width: 238, height: 337), for: .mediaBox))
    }
    let letterItems = try letterTemplates.map { template in
      var document = CoverLetterDocument.example
      document.template = template
      let pdf = try XCTUnwrap(PDFDocument(data: CoverLetterPDFRenderer.render(document: document)))
      let page = try XCTUnwrap(pdf.page(at: 0))
      return (template.title, page.thumbnail(of: CGSize(width: 238, height: 337), for: .mediaBox))
    }

    let resumeSheet = contactSheet(items: resumeItems, columns: 5)
    let letterSheet = contactSheet(items: letterItems, columns: 5)
    let outputDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ResumeStudioContactSheets", isDirectory: true)
    try FileManager.default.createDirectory(
      at: outputDirectory, withIntermediateDirectories: true)

    for (name, image) in [("new-resume-templates.png", resumeSheet), ("new-cover-letter-templates.png", letterSheet)] {
      let data = try XCTUnwrap(image.pngData())
      try data.write(to: outputDirectory.appendingPathComponent(name), options: .atomic)
      let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
      attachment.name = name
      attachment.lifetime = .keepAlways
      add(attachment)
    }
  }

  /// Visual-review artifact for the Showcase Collection: the ten portfolio-grade
  /// mastheads — greeting, monogram, vertical name, dot ratings — at export size.
  func testShowcaseCollectionContactSheets() throws {
    let resumeTemplates: [ResumeTemplate] = [
      .salute, .couture, .medallion, .sable, .terracotta,
      .lozenge, .circlet, .vogue, .signet, .almanac,
    ]
    let resumeItems = try resumeTemplates.map { template in
      var document = ResumeDocument.example
      document.template = template
      let pdf = try XCTUnwrap(PDFDocument(data: ResumePDFRenderer.render(document: document)))
      let page = try XCTUnwrap(pdf.page(at: 0))
      return (template.title, page.thumbnail(of: CGSize(width: 357, height: 505), for: .mediaBox))
    }
    let letterTemplates: [CoverLetterTemplate] = [
      .salute, .couture, .medallion, .sable, .terracotta,
      .lozenge, .circlet, .vogue, .signet, .almanac,
    ]
    let letterItems = try letterTemplates.map { template in
      var document = CoverLetterDocument.example
      document.template = template
      let pdf = try XCTUnwrap(PDFDocument(data: CoverLetterPDFRenderer.render(document: document)))
      let page = try XCTUnwrap(pdf.page(at: 0))
      return (template.title, page.thumbnail(of: CGSize(width: 357, height: 505), for: .mediaBox))
    }

    let resumeSheet = contactSheet(
      items: resumeItems, columns: 5, pageSize: CGSize(width: 357, height: 505))
    let letterSheet = contactSheet(
      items: letterItems, columns: 5, pageSize: CGSize(width: 357, height: 505))
    let outputDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ResumeStudioContactSheets", isDirectory: true)
    try FileManager.default.createDirectory(
      at: outputDirectory, withIntermediateDirectories: true)
    for (name, image) in [
      ("showcase-resume-templates.png", resumeSheet),
      ("showcase-cover-letter-templates.png", letterSheet),
    ] {
      let data = try XCTUnwrap(image.pngData())
      try data.write(to: outputDirectory.appendingPathComponent(name), options: .atomic)
      let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
      attachment.name = name
      attachment.lifetime = .keepAlways
      add(attachment)
    }
  }

  /// Focused visual-review artifacts for the art-led release: five résumé
  /// compositions and the two correspondence designs drawn to accompany them.
  func testArtLedTemplateContactSheets() throws {
    let resumeTemplates: [ResumeTemplate] = [.eclipse, .contour, .axis, .terrace, .vantage]
    let letterTemplates: [CoverLetterTemplate] = [.eclipse, .vantage]

    let resumeItems = try resumeTemplates.map { template in
      var document = ResumeDocument.example
      document.template = template
      let pdf = try XCTUnwrap(PDFDocument(data: ResumePDFRenderer.render(document: document)))
      let page = try XCTUnwrap(pdf.page(at: 0))
      return (template.title, page.thumbnail(of: CGSize(width: 357, height: 505), for: .mediaBox))
    }
    let letterItems = try letterTemplates.map { template in
      var document = CoverLetterDocument.example
      document.template = template
      let pdf = try XCTUnwrap(PDFDocument(data: CoverLetterPDFRenderer.render(document: document)))
      let page = try XCTUnwrap(pdf.page(at: 0))
      return (template.title, page.thumbnail(of: CGSize(width: 357, height: 505), for: .mediaBox))
    }

    let resumeSheet = contactSheet(items: resumeItems, columns: 5, pageSize: CGSize(width: 357, height: 505))
    let letterSheet = contactSheet(items: letterItems, columns: 2, pageSize: CGSize(width: 357, height: 505))
    let outputDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ResumeStudioContactSheets", isDirectory: true)
    try FileManager.default.createDirectory(
      at: outputDirectory, withIntermediateDirectories: true)

    for (name, image) in [
      ("art-led-resume-templates.png", resumeSheet),
      ("art-led-cover-letter-templates.png", letterSheet),
    ] {
      let data = try XCTUnwrap(image.pngData())
      try data.write(to: outputDirectory.appendingPathComponent(name), options: .atomic)
      let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
      attachment.name = name
      attachment.lifetime = .keepAlways
      add(attachment)
    }
  }

  /// Visual-review artifact for the Signature Collection: the twenty new résumé
  /// mastheads, the ten matched letters, and the five premium accents shown on a
  /// single template so the jewel tones can be compared at export size.
  func testSignatureCollectionContactSheets() throws {
    let resumeTemplates: [ResumeTemplate] = [
      .obsidian, .radiant, .verge, .datum, .pinnacle,
      .cobalt, .equinox, .mirage, .parallax, .emblem,
      .cadence, .citadel, .atrium, .zephyr, .cinder,
      .keystone, .loom, .graphite, .stratus, .vellum,
    ]
    let letterTemplates: [CoverLetterTemplate] = [
      .obsidian, .radiant, .verge, .datum, .pinnacle,
      .emblem, .cadence, .citadel, .stratus, .mirage,
    ]
    let premiumAccents: [ResumeAccent] = [.emerald, .amethyst, .sapphire, .rose, .midnight]

    let resumeItems = try resumeTemplates.map { template in
      var document = ResumeDocument.example
      document.template = template
      let pdf = try XCTUnwrap(PDFDocument(data: ResumePDFRenderer.render(document: document)))
      let page = try XCTUnwrap(pdf.page(at: 0))
      return (template.title, page.thumbnail(of: CGSize(width: 357, height: 505), for: .mediaBox))
    }
    let letterItems = try letterTemplates.map { template in
      var document = CoverLetterDocument.example
      document.template = template
      let pdf = try XCTUnwrap(PDFDocument(data: CoverLetterPDFRenderer.render(document: document)))
      let page = try XCTUnwrap(pdf.page(at: 0))
      return (template.title, page.thumbnail(of: CGSize(width: 357, height: 505), for: .mediaBox))
    }
    let accentItems = try premiumAccents.map { accent -> (String, UIImage) in
      var document = ResumeDocument.example
      document.template = .emblem
      document.accent = accent
      let pdf = try XCTUnwrap(PDFDocument(data: ResumePDFRenderer.render(document: document)))
      let page = try XCTUnwrap(pdf.page(at: 0))
      return (accent.title, page.thumbnail(of: CGSize(width: 357, height: 505), for: .mediaBox))
    }

    let sheets = [
      ("signature-resume-templates.png", contactSheet(items: resumeItems, columns: 5, pageSize: CGSize(width: 357, height: 505))),
      ("signature-cover-letter-templates.png", contactSheet(items: letterItems, columns: 5, pageSize: CGSize(width: 357, height: 505))),
      ("signature-premium-accents.png", contactSheet(items: accentItems, columns: 5, pageSize: CGSize(width: 357, height: 505))),
    ]
    let outputDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ResumeStudioContactSheets", isDirectory: true)
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    for (name, image) in sheets {
      let data = try XCTUnwrap(image.pngData())
      try data.write(to: outputDirectory.appendingPathComponent(name), options: .atomic)
      let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
      attachment.name = name
      attachment.lifetime = .keepAlways
      add(attachment)
    }
  }

  /// One glance over the whole release: all 32 résumé pages and all seven
  /// coordinated letters. Kept as a test attachment so visual regressions can be
  /// reviewed alongside the searchable-PDF assertions.
  func testAdvancedCollectionContactSheets() throws {
    let resumeTemplates = ResumeTemplate.allCases.filter { $0.advancedStyle != nil }
    let letterTemplates = CoverLetterTemplate.allCases.filter { $0.advancedOrdinal != nil }

    let resumeItems = try resumeTemplates.map { template in
      var document = ResumeDocument.example
      document.template = template
      let pdf = try XCTUnwrap(PDFDocument(data: ResumePDFRenderer.render(document: document)))
      let page = try XCTUnwrap(pdf.page(at: 0))
      return (template.title, page.thumbnail(of: CGSize(width: 178, height: 252), for: .mediaBox))
    }
    let letterItems = try letterTemplates.map { template in
      var document = CoverLetterDocument.example
      document.template = template
      let pdf = try XCTUnwrap(PDFDocument(data: CoverLetterPDFRenderer.render(document: document)))
      let page = try XCTUnwrap(pdf.page(at: 0))
      return (template.title, page.thumbnail(of: CGSize(width: 238, height: 337), for: .mediaBox))
    }

    let sheets = [
      (
        "advanced-resume-templates.png",
        contactSheet(items: resumeItems, columns: 8, pageSize: CGSize(width: 178, height: 252))
      ),
      (
        "advanced-cover-letter-templates.png",
        contactSheet(items: letterItems, columns: 7)
      ),
    ]
    let outputDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ResumeStudioContactSheets", isDirectory: true)
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    for (name, image) in sheets {
      let data = try XCTUnwrap(image.pngData())
      try data.write(to: outputDirectory.appendingPathComponent(name), options: .atomic)
      let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
      attachment.name = name
      attachment.lifetime = .keepAlways
      add(attachment)
    }
  }

  private func contactSheet(
    items: [(String, UIImage)],
    columns: Int,
    pageSize: CGSize = CGSize(width: 238, height: 337)
  ) -> UIImage {
    let labelHeight: CGFloat = 34
    let gap: CGFloat = 18
    let inset: CGFloat = 22
    let rows = Int(ceil(Double(items.count) / Double(columns)))
    let size = CGSize(
      width: inset * 2 + CGFloat(columns) * pageSize.width + CGFloat(columns - 1) * gap,
      height: inset * 2 + CGFloat(rows) * (pageSize.height + labelHeight) + CGFloat(rows - 1) * gap
    )

    return UIGraphicsImageRenderer(size: size).image { context in
      UIColor(white: 0.92, alpha: 1).setFill()
      context.fill(CGRect(origin: .zero, size: size))

      for (index, item) in items.enumerated() {
        let column = index % columns
        let row = index / columns
        let origin = CGPoint(
          x: inset + CGFloat(column) * (pageSize.width + gap),
          y: inset + CGFloat(row) * (pageSize.height + labelHeight + gap)
        )
        item.1.draw(in: CGRect(origin: origin, size: pageSize))

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        NSAttributedString(
          string: item.0,
          attributes: [
            .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: UIColor.label,
            .paragraphStyle: style,
          ]
        ).draw(
          with: CGRect(x: origin.x, y: origin.y + pageSize.height + 8, width: pageSize.width, height: 22),
          options: [.usesLineFragmentOrigin],
          context: nil
        )
      }
    }
  }

  func testJobSpecImportReadsPDFDOCXAndText() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let pdfURL = directory.appendingPathComponent("People Lead Spec.pdf")
    let pdfData = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
      .pdfData { context in
        context.beginPage()
        NSAttributedString(string: "Lead manager development and workforce planning")
          .draw(at: CGPoint(x: 40, y: 40))
      }
    try pdfData.write(to: pdfURL)
    let pdf = try JobSpecImportService.importDocument(from: pdfURL)
    XCTAssertTrue(pdf.text.contains("workforce planning"))
    XCTAssertEqual(pdf.fileName, "People Lead Spec.pdf")

    let docxURL = directory.appendingPathComponent("Role.docx")
    try ResumeDOCXRenderer.render(document: .example).write(to: docxURL)
    let docx = try JobSpecImportService.importDocument(from: docxURL)
    XCTAssertTrue(docx.text.contains("People Operations Manager"))

    let textURL = directory.appendingPathComponent("Role.txt")
    try "Own hiring operations and coach senior managers".write(
      to: textURL, atomically: true, encoding: .utf8)
    let text = try JobSpecImportService.importDocument(from: textURL)
    XCTAssertEqual(text.text, "Own hiring operations and coach senior managers")
  }

  /// A red square, encoded as a JPEG — enough for the renderer to draw and crop.
  private static func samplePhotoData() -> Data {
    let size = CGSize(width: 400, height: 400)
    let image = UIGraphicsImageRenderer(size: size).image { context in
      UIColor.systemRed.setFill()
      context.fill(CGRect(origin: .zero, size: size))
    }
    return image.jpegData(compressionQuality: 0.9) ?? Data()
  }

  func testCropSelectsASquareAndCannotRunOffTheImage() {
    let landscape = CGSize(width: 1000, height: 600)

    // Zoomed out: the largest square that fits, centred.
    let centred = PhotoCrop.centred.rect(in: landscape)
    XCTAssertEqual(centred, CGRect(x: 200, y: 0, width: 600, height: 600))

    // Zoomed in halves the side.
    let zoomed = PhotoCrop(centerX: 0.5, centerY: 0.5, zoom: 2).rect(in: landscape)
    XCTAssertEqual(zoomed.width, 300)
    XCTAssertEqual(zoomed.height, 300)

    // Pushed hard into the corner, it clamps to the edge rather than hanging off
    // it — which would otherwise render blank wedges in the circle.
    let corner = PhotoCrop(centerX: 0, centerY: 0, zoom: 1).rect(in: landscape)
    XCTAssertEqual(corner, CGRect(x: 0, y: 0, width: 600, height: 600))
    XCTAssertTrue(landscape.contains(rect: corner))
  }

  func testCropSurvivesARoundTripAndDefaultsToCentred() throws {
    var framed = ResumeDocument.example
    framed.photo = Data([0xFF, 0xD8, 0xFF, 0xE0])
    framed.photoCrop = PhotoCrop(centerX: 0.31, centerY: 0.22, zoom: 2.4)

    let decoded = try JSONDecoder().decode(
      ResumeDocument.self, from: JSONEncoder().encode(framed))
    XCTAssertEqual(decoded.photoCrop, framed.photoCrop)

    // A draft saved before framing existed has no crop, and must behave exactly
    // as it did then: the centred square.
    XCTAssertNil(ResumeDocument.example.photoCrop)
  }

  func testCoverLetterCatalogueIsDistinct() {
    XCTAssertEqual(CoverLetterTemplate.allCases.count, 55)

    // The matched letters name the résumé they were drawn to sit beside.
    XCTAssertEqual(
      CoverLetterTemplate.allCases.compactMap(\.pairsWith),
      [
        .atlas, .signal, .chronicle, .strata, .gazette, .noir, .marquee, .crest, .ivy, .plinth,
        .stockholm, .laureate, .nova, .aurelia, .nocturne,
        .eclipse, .vantage, .zenith, .aperture, .sovereign, .blueprint, .spectrum, .halo,
        .volta,
        .obsidian, .radiant, .verge, .datum, .pinnacle, .emblem, .cadence, .citadel, .stratus,
        .mirage,
        .salute, .couture, .medallion, .sable, .terracotta, .lozenge, .circlet, .vogue, .signet,
        .almanac,
      ]
    )
    XCTAssertEqual(CoverLetterTemplate.allCases.compactMap(\.advancedOrdinal), Array(0..<27))
    XCTAssertEqual(
      Set(CoverLetterTemplate.allCases.map(\.title)).count,
      CoverLetterTemplate.allCases.count
    )
    XCTAssertEqual(
      Set(CoverLetterTemplate.allCases.map(\.subtitle)).count,
      CoverLetterTemplate.allCases.count
    )
  }

  func testMonogramInitialsFallBackLikeThePortraitDoes() {
    XCTAssertEqual(CoverLetterDocument.example.initials, "AS")
    XCTAssertEqual(CoverLetterDocument.blank.initials, "?")
  }

  func testPhotoSurvivesARoundTripAndOlderDraftsStillLoad() throws {
    var withPhoto = ResumeDocument.example
    withPhoto.photo = Data([0xFF, 0xD8, 0xFF, 0xE0])
    let encoded = try JSONEncoder().encode(withPhoto)
    let decoded = try JSONDecoder().decode(ResumeDocument.self, from: encoded)
    XCTAssertEqual(decoded.photo, withPhoto.photo)
    XCTAssertTrue(decoded.isPhotoVisible)

    withPhoto.isPhotoVisible = false
    let hidden = try JSONDecoder().decode(
      ResumeDocument.self, from: JSONEncoder().encode(withPhoto))
    XCTAssertFalse(hidden.isPhotoVisible)
    XCTAssertEqual(hidden.photo, withPhoto.photo)

    // A draft written before photos existed has no `photo` key. It must still
    // decode — the store replaces any draft older than the current schema with
    // the example, so a version bump here would destroy real résumés.
    let legacy = """
      {
        "schemaVersion": 2, "personal": {"fullName": "Avery Sample", "headline": "",
        "phone": "", "email": ""}, "professionalProfile": "", "competencies": [],
        "experience": [], "education": [], "references": [],
        "accent": "orange", "template": "modern"
      }
      """
    let migrated = try JSONDecoder().decode(
      ResumeDocument.self, from: Data(legacy.utf8))
    XCTAssertNil(migrated.photo)
    XCTAssertTrue(migrated.isPhotoVisible)
    XCTAssertEqual(migrated.schemaVersion, ResumeDocument.currentSchemaVersion)
    XCTAssertEqual(migrated.personal.fullName, "Avery Sample")
  }

  func testInitialsStandInForAMissingPortrait() {
    XCTAssertEqual(ResumeDocument.example.initials, "AS")
    XCTAssertEqual(ResumeDocument.blank.initials, "?")
  }

  func testCompletionScoresTheFilledInSections() {
    XCTAssertEqual(ResumeDocument.example.completionPercentage, 100)
    XCTAssertEqual(ResumeDocument.blank.completionPercentage, 0)

    // Whitespace and empty rows are not progress.
    var padded = ResumeDocument.blank
    padded.personal.fullName = "   "
    padded.competencies = ["", "  "]
    padded.experience = [ExperienceEntry(role: "", company: "", period: "", highlights: [])]
    XCTAssertEqual(padded.completionPercentage, 0)

    // Nine sections are scored, so one real field is a ninth of the way there.
    var started = ResumeDocument.blank
    started.personal.fullName = "Avery Sample"
    XCTAssertEqual(started.completion, 1.0 / 9.0, accuracy: 0.0001)
    XCTAssertEqual(started.completionPercentage, 11)
  }

  func testIncompleteSectionsDriveTheNextStep() {
    XCTAssertEqual(ResumeDocument.example.incompleteSections, [])

    // A blank draft points at the first thing to fill in.
    XCTAssertEqual(ResumeDocument.blank.incompleteSections, ResumeSection.allCases)
    XCTAssertEqual(ResumeDocument.blank.incompleteSections.first, .personal)

    // Personal only counts once every contact field is there.
    var partial = ResumeDocument.blank
    partial.personal.fullName = "Avery Sample"
    partial.personal.headline = "People Ops"
    XCTAssertFalse(partial.isComplete(.personal))
    partial.personal.email = "avery@example.com"
    partial.personal.phone = "+1 202 555 0147"
    XCTAssertTrue(partial.isComplete(.personal))
    XCTAssertEqual(partial.incompleteSections.first, .profile)
  }

  func testAccentsKeepTheirExportColoursAndHaveDistinctNames() {
    // The display names changed with the redesign; the export colours must not.
    XCTAssertEqual(Set(ResumeAccent.allCases.map(\.title)).count, ResumeAccent.allCases.count)
    XCTAssertEqual(ResumeAccent.orange.title, "Burnt Orange")

    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    ResumeAccent.orange.uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    XCTAssertEqual(red, 0.82, accuracy: 0.001)
    XCTAssertEqual(green, 0.28, accuracy: 0.001)
    XCTAssertEqual(blue, 0.04, accuracy: 0.001)
  }

  func testEveryTemplateRendersSearchablePDF() throws {
    for template in ResumeTemplate.allCases {
      var source = ResumeDocument.example
      source.template = template
      let data = try ResumePDFRenderer.render(document: source)

      XCTAssertTrue(data.starts(with: Data("%PDF".utf8)), template.title)

      let pdf = try XCTUnwrap(PDFDocument(data: data))
      XCTAssertGreaterThanOrEqual(pdf.pageCount, 1, template.title)

      let searchableText = (0..<pdf.pageCount)
        .compactMap { pdf.page(at: $0)?.string }
        .joined(separator: "\n")

      XCTAssertTrue(searchableText.contains("Avery Sample"), template.title)
      XCTAssertTrue(searchableText.contains("Riley Example"), template.title)
      XCTAssertTrue(searchableText.contains("Morgan Sample"), template.title)
    }
  }

  func testEveryCoverLetterTemplateRendersSearchablePDF() throws {
    for template in CoverLetterTemplate.allCases {
      var source = CoverLetterDocument.example
      source.template = template
      let data = try CoverLetterPDFRenderer.render(document: source)

      XCTAssertTrue(data.starts(with: Data("%PDF".utf8)), template.title)
      let pdf = try XCTUnwrap(PDFDocument(data: data))
      XCTAssertGreaterThanOrEqual(pdf.pageCount, 1, template.title)

      let searchableText = (0..<pdf.pageCount)
        .compactMap { pdf.page(at: $0)?.string }
        .joined(separator: "\n")
      XCTAssertTrue(searchableText.contains("Avery Sample"), template.title)
      XCTAssertTrue(searchableText.contains("Evergreen Labs"), template.title)
      XCTAssertTrue(searchableText.contains("Senior People Operations Manager"), template.title)
    }
  }

  func testAIResumeSnapshotRedactsPersonalAndReferenceData() throws {
    var source = ResumeDocument.example
    source.photo = Data("private-photo".utf8)
    let data = try JSONEncoder().encode(AIResumeSnapshot(document: source))
    let json = try XCTUnwrap(String(data: data, encoding: .utf8))

    XCTAssertFalse(json.contains(source.personal.fullName))
    XCTAssertFalse(json.contains(source.personal.phone))
    XCTAssertFalse(json.contains(source.personal.email))
    XCTAssertFalse(json.contains(source.references[0].name))
    XCTAssertFalse(json.contains("private-photo"))
    XCTAssertTrue(json.contains("People Operations Manager"))
  }

  func testCoverLetterStorePersistsDateAndContent() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("json")
    defer { try? FileManager.default.removeItem(at: url) }

    let writer = CoverLetterStore(fileURL: url, initialDocument: .example)
    writer.save()
    let reader = CoverLetterStore(fileURL: url)

    var expected = CoverLetterDocument.example
    expected.date = reader.document.date
    XCTAssertEqual(reader.document, expected)
  }

  func testInitialCloudSyncUploadsInsteadOfRemainingStuck() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let cloudURL = root.appendingPathComponent("iCloud/workspace.json")
    let service = ICloudSyncService(isEnabled: true, cloudFileURLOverride: cloudURL)
    let resumeStore = ResumeStore(
      fileURL: root.appendingPathComponent("resume.json"),
      initialDocument: .example
    )
    let applicationStore = ApplicationStore(
      fileURL: root.appendingPathComponent("applications.json")
    )
    let coverLetterStore = CoverLetterStore(
      fileURL: root.appendingPathComponent("cover-letter.json"),
      initialDocument: .example
    )
    let careerIntelligenceStore = CareerIntelligenceStore(
      fileURL: root.appendingPathComponent("career-intelligence.json")
    )
    service.configure(
      resumeStore: resumeStore,
      applicationStore: applicationStore,
      coverLetterStore: coverLetterStore,
      careerIntelligenceStore: careerIntelligenceStore
    )

    await service.synchronize()
    for _ in 0..<100 {
      if case .synced = service.status { break }
      try await Task.sleep(for: .milliseconds(5))
    }

    guard case .synced = service.status else {
      return XCTFail("Initial iCloud sync did not leave the syncing state")
    }
    XCTAssertTrue(FileManager.default.fileExists(atPath: cloudURL.path))

    let firstData = try Data(contentsOf: cloudURL)
    var archive = try XCTUnwrap(JSONSerialization.jsonObject(with: firstData) as? [String: Any])
    XCTAssertEqual(archive["schemaVersion"] as? Int, 2)
    XCTAssertNotNil(archive["revision"] as? String)

    // Simulate edits on this device while a second device advances iCloud.
    // Synchronization must stop for a choice instead of silently overwriting.
    service.isEnabled = false
    resumeStore.document.personal.headline = "Offline local edit"
    try await Task.sleep(for: .milliseconds(20))
    archive["revision"] = "remote-divergent-revision"
    archive["savedAt"] = Date().addingTimeInterval(60).timeIntervalSince1970
    try JSONSerialization.data(withJSONObject: archive).write(to: cloudURL, options: .atomic)
    service.isEnabled = true
    for _ in 0..<100 {
      if service.status == .conflict { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    XCTAssertEqual(service.status, .conflict)
    XCTAssertNotNil(service.conflict)
  }

  func testResumeDocumentRoundTripsThroughJSON() throws {
    let source = ResumeDocument.example
    let data = try JSONEncoder().encode(source)
    let decoded = try JSONDecoder().decode(ResumeDocument.self, from: data)
    XCTAssertEqual(decoded, source)
  }

  func testBlankResumeStillProducesAValidPage() throws {
    let data = try ResumePDFRenderer.render(document: .blank)
    let pdf = try XCTUnwrap(PDFDocument(data: data))
    XCTAssertEqual(pdf.pageCount, 1)
  }

  func testLegacyDevelopmentDraftMigratesToFictionalExample() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("json")
    defer { try? FileManager.default.removeItem(at: url) }

    let encoded = try JSONEncoder().encode(ResumeDocument.example)
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object.removeValue(forKey: "schemaVersion")
    object.removeValue(forKey: "template")
    try JSONSerialization.data(withJSONObject: object).write(to: url)

    let store = ResumeStore(fileURL: url)

    XCTAssertEqual(store.document.schemaVersion, ResumeDocument.currentSchemaVersion)
    XCTAssertEqual(store.document, .example)
  }

  func testResumeLibraryKeepsMultipleIndependentVersions() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    defer { try? FileManager.default.removeItem(at: url) }

    let writer = ResumeStore(fileURL: url, initialDocument: .example)
    writer.save()
    var tailored = ResumeDocument.example
    tailored.personal.headline = "Targeted Product Leader"
    let targetedID = writer.createResume(title: "Product Role", from: tailored)
    XCTAssertEqual(writer.resumes.count, 2)
    XCTAssertEqual(writer.activeResumeID, targetedID)

    let reader = ResumeStore(fileURL: url)
    XCTAssertEqual(reader.resumes.count, 2)
    XCTAssertEqual(reader.activeDraft?.title, "Product Role")
    XCTAssertEqual(reader.document.personal.headline, "Targeted Product Leader")
  }

  func testImportCanSafelyReplaceOrFreeASavedVersionSlot() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    defer { try? FileManager.default.removeItem(at: url) }

    let store = ResumeStore(fileURL: url, initialDocument: .example)
    let secondID = store.createResume(title: "Second", from: .blank)
    let thirdID = store.createResume(title: "Third", from: .blank)
    XCTAssertEqual(store.resumes.count, 3)

    var imported = ResumeDocument.example
    imported.personal.fullName = "Imported Person"
    imported.personal.headline = "Imported Replacement"
    XCTAssertTrue(store.replaceResume(secondID, with: imported, title: "Imported CV"))
    XCTAssertEqual(store.resumes.count, 3)
    XCTAssertEqual(store.activeResumeID, secondID)
    XCTAssertEqual(store.document.personal.fullName, "Imported Person")
    XCTAssertEqual(store.resumes.first(where: { $0.id == secondID })?.title, "Imported CV")
    XCTAssertEqual(
      store.resumes.first(where: { $0.id == secondID })?.document.personal.headline,
      "Imported Replacement")

    let importedID = try XCTUnwrap(
      store.createResume(replacing: thirdID, title: "Fresh Import", from: imported)
    )
    XCTAssertEqual(store.resumes.count, 3)
    XCTAssertEqual(store.activeResumeID, importedID)
    XCTAssertFalse(store.resumes.contains(where: { $0.id == thirdID }))

    let reader = ResumeStore(fileURL: url)
    XCTAssertEqual(reader.activeResumeID, importedID)
    XCTAssertEqual(reader.activeDraft?.title, "Fresh Import")
    XCTAssertEqual(reader.document.personal.fullName, "Imported Person")
    XCTAssertEqual(reader.document.personal.headline, "Imported Replacement")
  }

  func testAdditionalSectionsRenderAndRoundTrip() throws {
    var document = ResumeDocument.example
    document.additionalSections = [
      ResumeAdditionalSection(title: "Certifications", items: ["Apple Development Certificate"])
    ]
    let decoded = try JSONDecoder().decode(
      ResumeDocument.self, from: JSONEncoder().encode(document))
    XCTAssertEqual(decoded.additionalSections, document.additionalSections)

    let pdfData = try ResumePDFRenderer.render(document: document)
    let pdf = try XCTUnwrap(PDFDocument(data: pdfData))
    let text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
    XCTAssertTrue(text.localizedCaseInsensitiveContains("Certifications"), text)
    XCTAssertTrue(text.localizedCaseInsensitiveContains("Apple Development Certificate"), text)
  }

  func testDOCXExportProducesAnOfficePackage() throws {
    let data = try ResumeDOCXRenderer.render(document: .example)
    XCTAssertGreaterThan(data.count, 1_000)
    XCTAssertEqual(Array(data.prefix(2)), Array(Data("PK".utf8)))
  }

  func testJobDescriptionQualityAndATSChecksAreDeterministic() {
    let short = JobDescriptionAnalyzer.analyze("Software Engineer")
    XCTAssertFalse(short.isDetailedEnough)
    XCTAssertFalse(short.blockingIssues.isEmpty)

    let full = JobDescriptionAnalyzer.analyze(String(repeating: "You will build products and collaborate with teams. Required experience in delivery. ", count: 8))
    XCTAssertTrue(full.isDetailedEnough)
    XCTAssertGreaterThan(full.score, short.score)

    let blankReport = ATSReadinessService.analyze(document: .blank)
    XCTAssertGreaterThan(blankReport.actionCount, 0)
    let completeReport = ATSReadinessService.analyze(document: .example)
    XCTAssertGreaterThan(completeReport.passedCount, blankReport.passedCount)
  }

  func testApplicationTrackerPersistsAnApplication() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    defer { try? FileManager.default.removeItem(at: url) }
    let resumeID = UUID()
    let application = JobApplication(
      company: "Example Co", role: "Designer", jobDescription: "A full advert",
      sourceURL: "", status: .applied, notes: "Follow up", baseResumeID: resumeID,
      tailoredResumeID: nil, matchAnalysis: nil, interviewPlan: nil
    )
    ApplicationStore(fileURL: url).add(application)
    let reloaded = ApplicationStore(fileURL: url)
    XCTAssertEqual(reloaded.applications.first?.role, "Designer")
    XCTAssertEqual(reloaded.applications.first?.status, .applied)
  }

  func testPlainTextImportCreatesReviewableContent() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).appendingPathExtension("txt")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("Jordan Lee\nProduct Designer\njordan@example.com\nProfessional Profile\nDesigns accessible products.\nExperience\nLead Designer".utf8).write(to: url)
    let imported = try ResumeImportService.importDocuments(from: [url])
    XCTAssertEqual(imported.personal.fullName, "Jordan Lee")
    XCTAssertEqual(imported.personal.email, "jordan@example.com")
    XCTAssertEqual(imported.experience.first?.role, "Lead Designer")
    XCTAssertFalse(imported.additionalSections.contains { $0.title == "Imported content" })
  }

  func testPDFStyleImportMapsRealResumeSectionsInsteadOfDumpingImportedContent() {
    let extractedText = """
      Mandisa Nkabinde
      HR BUSINESS PARTNER | EMPLOYEE RELATIONS
      071 740 5898 / 078 509 2995 Mandisankabinde21@gmail.com
      PROFESSIONAL PROFILE
      Strategic and people-centered HR Business Partner with 5+ years of progressive
      experience across employee relations, talent acquisition, and HR compliance.
      PROFESSIONAL EXPERIENCE
      Human Resources Business Partner
      Cubix Talksure Trading (Pty) Ltd | Feb 2025 - 31 March 2026
      Partner with senior leadership to design and implement HR strategies aligned with
      business objectives, enhancing organisational performance.
      Employee Relations Consultant
      Cubix Talksure Trading (Pty) Ltd | Aug 2024 - Jan 2025
      Advised managers on employee relations matters, ensuring legally compliant and fair
      resolutions.
      MANDISA NKABINDE | RESUME CORE COMPETENCIES
      Strategic HR Partnership & Workforce
      Planning
      Diversity, Equity & Inclusion
      Performance Management & Coaching
      Change Management & Organisational
      Development
      HR Analytics & Metrics
      Talent Acquisition & Employer Branding
      HR Administration & Compliance
      Communication & Advisory Skills
      Labour Law & Industrial Relations
      Employee Engagement & Development
      EDUCATION
      Bachelor of Industrial Psychology &
      Psychology
      University of KwaZulu-Natal | 2016 - 2019
      BCom Honours in Industrial/
      Employment Relations
      University of KwaZulu-Natal | 2019 - 2020
      Master of Commerce in Industrial/
      Employment Relations
      University of KwaZulu-Natal
      Coursework completed; research component
      pending. Studies currently on hold.
      1 / 2
      Mandisa Nkabinde
      HR BUSINESS PARTNER | EMPLOYEE RELATIONS
      PAGE 2 OF 2
      PROFESSIONAL EXPERIENCE
      -
      CONTINUED
      Talent Acquisition Specialist
      Capita SA / UK / ROI | Jun 2022 - Apr 2024
      Managed end-to-end recruitment processes across South Africa, the UK, and ROI.
      Junior Human Resources Business Partner
      Talksure Trading (Pty) Ltd | Feb 2020 - Sep 2021
      Provided HR advisory services on employee relations and performance management.
      REFERENCES
      Triselle Munsamy
      Talksure Cubix
      CONTACT NUMBER
      +27 84 220 7397
      EMAIL ADDRESS
      Triselle.Munsamy@talksuresa.co.za
      Philile Mbambo
      Capita
      CONTACT NUMBER
      +27 73 095 8356
      EMAIL ADDRESS
      Tymlesc@gmail.com
      MANDISA NKABINDE | RESUME 2 / 2
      """

    let imported = ResumeImportService.parseResumeText(extractedText)

    XCTAssertEqual(imported.personal.fullName, "Mandisa Nkabinde")
    XCTAssertEqual(imported.experience.count, 4)
    XCTAssertEqual(imported.education.count, 3)
    XCTAssertEqual(imported.competencies.count, 10, "\(imported.competencies)")
    XCTAssertEqual(imported.references.count, 2)
    XCTAssertEqual(imported.experience.first?.role, "Human Resources Business Partner")
    XCTAssertEqual(imported.education.last?.institution, "University of KwaZulu-Natal")
    XCTAssertEqual(imported.references.last?.name, "Philile Mbambo")
    XCTAssertFalse(imported.additionalSections.contains { $0.title.localizedCaseInsensitiveContains("import") })
  }

  func testInterviewAIRequiresNinetyPercentResumeCompletion() async {
    do {
      _ = try await ResumeAIService.shared.createInterviewAssessment(
        document: .blank,
        jobDescription: "Example role",
        role: "Designer",
        company: "Example"
      )
      XCTFail("An incomplete résumé must not reach the AI service")
    } catch {
      XCTAssertEqual(error as? ResumeAIError, .resumeIncomplete)
    }
  }

  func testInterviewCalendarAndReflectionPersist() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    defer { try? FileManager.default.removeItem(at: url) }
    let event = InterviewEvent(
      applicationID: nil,
      role: "Product Designer",
      company: "Example Co",
      scheduledAt: Date().addingTimeInterval(-3600),
      durationMinutes: 60,
      format: .video,
      locationOrLink: "https://example.test/interview",
      interviewerNames: "Jordan",
      reminderEnabled: true,
      preparationNotes: "Prepare portfolio",
      outcome: .progressed,
      selfRating: 4,
      whatWentWell: "Clear examples",
      needsImprovement: "Shorter answers",
      followUpNotes: "Sent thank-you note"
    )
    let writer = ApplicationStore(fileURL: url)
    writer.addInterview(event)

    let reader = ApplicationStore(fileURL: url)
    XCTAssertEqual(reader.interviews.count, 1)
    XCTAssertEqual(reader.interviews.first?.role, event.role)
    XCTAssertEqual(reader.pastInterviews.first?.needsImprovement, "Shorter answers")
    XCTAssertEqual(reader.pastInterviews.first?.outcome, .progressed)
  }

  func testAssessmentEvaluationAndFocusPlanPersistWithApplication() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    defer { try? FileManager.default.removeItem(at: url) }
    let evaluation = AIAssessmentEvaluation(
      score: 6,
      total: 8,
      percentage: 75,
      strengths: ["Evidence selection"],
      knowledgeGaps: ["STAR result statements"],
      focusPlan: ["Practise two STAR stories", "Quantify only verified outcomes", "Retake the quiz"],
      overallFeedback: "Good foundation.",
      questionFeedback: [AIAssessmentQuestionFeedback(id: "a1", isCorrect: true, feedback: "Strong choice.")]
    )
    var application = JobApplication(
      company: "Example", role: "Designer", jobDescription: "", sourceURL: "",
      status: .interview, notes: "", baseResumeID: UUID(), tailoredResumeID: nil,
      matchAnalysis: nil, interviewPlan: nil
    )
    application.assessmentAttempts = [InterviewAssessmentAttempt(
      assessmentTitle: "Practice", score: 6, total: 8, evaluation: evaluation)]
    ApplicationStore(fileURL: url).add(application)

    let saved = ApplicationStore(fileURL: url).applications.first
    XCTAssertEqual(saved?.assessmentAttempts?.first?.evaluation?.percentage, 75)
    XCTAssertEqual(saved?.assessmentAttempts?.first?.evaluation?.knowledgeGaps, ["STAR result statements"])
  }

  func testCareerCoachContextUsesCareerHistoryWithoutContactOrSourceData() throws {
    var resume = ResumeDocument.example
    resume.additionalSections = [
      ResumeAdditionalSection(title: "Certifications", items: ["Inclusive Hiring Certificate"])
    ]
    let application = JobApplication(
      company: "Example Co", role: "People Lead", jobDescription: "Lead manager development",
      sourceURL: "https://private.example/jobs/secret", status: .interview,
      notes: "Practise the change-management example", baseResumeID: UUID(),
      tailoredResumeID: nil, matchAnalysis: nil, interviewPlan: nil
    )
    let interview = InterviewEvent(
      applicationID: application.id, role: application.role, company: application.company,
      scheduledAt: Date(), durationMinutes: 60, format: .panel, locationOrLink: "Private room",
      interviewerNames: "Private interviewer", reminderEnabled: true,
      preparationNotes: "Prepare manager coaching story", outcome: .pending, selfRating: 0,
      whatWentWell: "", needsImprovement: "Keep answers concise", followUpNotes: ""
    )
    let context = CareerCoachContext(
      resumeTitle: "Leadership résumé", document: resume, applications: [application],
      interviews: [interview], coverLetter: .example
    )
    let json = try XCTUnwrap(String(data: JSONEncoder().encode(context), encoding: .utf8))

    XCTAssertTrue(json.contains("People Lead"))
    XCTAssertTrue(json.contains("Inclusive Hiring Certificate"))
    XCTAssertTrue(json.contains("Keep answers concise"))
    XCTAssertFalse(json.contains(resume.personal.fullName))
    XCTAssertFalse(json.contains(resume.personal.email))
    XCTAssertFalse(json.contains(resume.personal.phone))
    XCTAssertFalse(json.contains(resume.references[0].name))
    XCTAssertFalse(json.contains(application.sourceURL))
    XCTAssertFalse(json.contains(interview.locationOrLink))
    XCTAssertFalse(json.contains(interview.interviewerNames))
  }

  // MARK: - Career coach replies

  /// A quiz exactly as the coach writes one. It used to reach the screen as a
  /// wall of prose with literal `**` in it, ending in four options the user could
  /// only answer by reading them and then retyping a letter.
  private static let quizReply = """
    I don’t have any recorded assessment weak areas yet, so I’ll start with a likely \
    development area based on your background: **people analytics and business impact**.

    **Question 1:** Leadership asks whether a manager-coaching programme is improving \
    retention. Which measurement approach would be strongest?

    A. Report how many managers attended
    B. Compare retention before and after the programme, while controlling for factors \
    such as team size, tenure, and business changes
    C. Ask managers whether they enjoyed the programme
    D. Report the number of coaching sessions delivered

    Reply with A, B, C, or D—and briefly explain your reasoning.
    """

  func testCoachQuizBecomesCardsAndOptions() {
    let blocks = CoachReplyParser.parse(Self.quizReply)
    XCTAssertEqual(blocks.count, 5)

    guard case .paragraph(let intro) = blocks[0].kind else { return XCTFail("expected an intro") }
    // The emphasis is emphasis now, not a pair of asterisks around the words.
    XCTAssertFalse(String(intro.characters).contains("*"))
    XCTAssertTrue(String(intro.characters).hasSuffix("based on your background."))

    guard case .focus(let area) = blocks[1].kind else { return XCTFail("expected a focus area") }
    XCTAssertEqual(area, "People analytics and business impact")

    guard case .question(let question) = blocks[2].kind else { return XCTFail("expected a question") }
    XCTAssertEqual(question.title, "Question 1")
    XCTAssertTrue(String(question.prompt.characters).hasPrefix("Leadership asks whether"))
    XCTAssertTrue(String(question.prompt.characters).hasSuffix("would be strongest?"))

    guard case .choices(let choices) = blocks[3].kind else { return XCTFail("expected options") }
    XCTAssertEqual(choices.map(\.letter), ["A", "B", "C", "D"])
    XCTAssertEqual(choices[0].text, "Report how many managers attended")
    XCTAssertTrue(choices[1].text.hasSuffix("team size, tenure, and business changes"))

    guard case .hint = blocks[4].kind else { return XCTFail("expected a hint") }
  }

  func testTappedOptionReadsBackAsTheAnswer() {
    let blocks = CoachReplyParser.parse(Self.quizReply)
    guard case .choices(let choices) = blocks[3].kind else { return XCTFail("expected options") }

    // Tapping sends the letter the coach asked for, plus the answer itself, so the
    // transcript still says something when it is scrolled back to later.
    let tapped = choices[1].reply
    XCTAssertTrue(tapped.hasPrefix("B — Compare retention"))

    // Which option was picked is recovered from that reply rather than stored, so
    // it survives a relaunch — and typing the letter counts the same as tapping it.
    XCTAssertEqual(CoachChoice.answered(in: tapped, among: choices), "B")
    XCTAssertEqual(CoachChoice.answered(in: "C", among: choices), "C")
    XCTAssertEqual(CoachChoice.answered(in: "d", among: choices), "D")
    XCTAssertEqual(CoachChoice.answered(in: "D. Report the number", among: choices), "D")

    // A sentence that merely opens with an option letter is not an answer to it.
    XCTAssertNil(CoachChoice.answered(in: "Can you explain the first one?", among: choices))
    XCTAssertNil(CoachChoice.answered(in: "But why does that matter?", among: choices))
    XCTAssertNil(CoachChoice.answered(in: "Ask me an easier one", among: choices))
  }

  func testLetteredProseIsNotMistakenForOptions() {
    // An option list runs A, B, C… in order. A line that happens to open with a
    // letter and a full stop is a sentence, and stays one.
    let blocks = CoachReplyParser.parse("A. Smith is the hiring manager you met in May.")

    XCTAssertEqual(blocks.count, 1)
    guard case .paragraph(let text) = blocks[0].kind else { return XCTFail("expected prose") }
    XCTAssertEqual(String(text.characters), "A. Smith is the hiring manager you met in May.")
  }

  func testCoachMarkdownRendersAsFormatting() {
    let blocks = CoachReplyParser.parse(
      """
      **Next steps**

      - Quantify your **retention** work
      - Name the tools you used

      1. Rewrite the summary
      2. Add one metric per role
      """
    )

    guard case .heading(let heading) = blocks[0].kind else { return XCTFail("expected a heading") }
    XCTAssertEqual(heading, "Next steps")

    guard case .bullets(let bullets) = blocks[1].kind else { return XCTFail("expected bullets") }
    XCTAssertEqual(bullets.count, 2)
    XCTAssertEqual(String(bullets[0].text.characters), "Quantify your retention work")

    guard case .steps(let steps) = blocks[2].kind else { return XCTFail("expected steps") }
    XCTAssertEqual(steps.map(\.marker), ["1", "2"])
    XCTAssertEqual(String(steps[1].text.characters), "Add one metric per role")
  }

  func testPlainCoachReplyStaysOneParagraph() {
    let welcome = "Hi! I’m your Career Coach. What would you like to improve first?"
    let blocks = CoachReplyParser.parse(welcome)

    XCTAssertEqual(blocks.count, 1)
    guard case .paragraph(let text) = blocks[0].kind else { return XCTFail("expected prose") }
    XCTAssertEqual(String(text.characters), welcome)
  }

  func testEvidenceVaultImportsVerifiedFactsWithoutDuplicatesAndPersists() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("career-intelligence-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }

    let store = CareerIntelligenceStore(fileURL: url)
    let firstCount = store.importEvidence(
      from: .example, resumeID: UUID(), sourceTitle: "Example Résumé")
    XCTAssertGreaterThan(firstCount, 10)
    XCTAssertEqual(store.evidence.count, firstCount)
    XCTAssertTrue(store.evidence.allSatisfy(\.isVerified))

    let secondCount = store.importEvidence(
      from: .example, resumeID: UUID(), sourceTitle: "Example Résumé")
    XCTAssertEqual(secondCount, 0)
    XCTAssertEqual(store.evidence.count, firstCount)

    let reloaded = CareerIntelligenceStore(fileURL: url)
    XCTAssertEqual(reloaded.evidence.count, firstCount)
    XCTAssertEqual(reloaded.evidence.first?.detail, store.evidence.first?.detail)
  }

  func testEveryAIResultCanBeRecoveredAfterTheGeneratingScreenCloses() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("ai-artifacts-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }

    let writer = AIArtifactStore(fileURL: url)
    let result = AICareerToolkitDraft(
      title: "People Operations Manager | Employee Experience",
      body: "I build practical people programmes grounded in verified career evidence.",
      highlights: ["Workforce planning", "Manager coaching"],
      evidenceSources: ["Current résumé"],
      claimsRequiringConfirmation: []
    )
    let saved = try XCTUnwrap(writer.record(
      result, action: .careerToolkit, context: "linkedinProfile"))
    XCTAssertTrue(saved.outputJSON.contains("People Operations Manager"))

    let reloaded = AIArtifactStore(fileURL: url)
    XCTAssertEqual(reloaded.artifacts.count, 1)
    XCTAssertEqual(reloaded.artifacts.first?.action, .careerToolkit)
    XCTAssertEqual(reloaded.artifacts.first?.context, "linkedinProfile")
    XCTAssertTrue(reloaded.artifacts.first?.previewLines.contains {
      $0.contains("People Operations Manager")
    } == true)
    XCTAssertEqual(
      reloaded.latest(
        AICareerToolkitDraft.self, action: .careerToolkit, context: "linkedinProfile"),
      result
    )
  }

  func testAtlasPreviewCannotLoopForeverOnOversizedImportedSidebarContent() throws {
    var document = ResumeDocument.example
    document.template = .atlas
    document.additionalSections = [
      ResumeAdditionalSection(
        title: "Projects",
        items: [String(repeating: "Built a verified cross-functional project outcome. ", count: 1_200)]
      )
    ]

    let startedAt = Date()
    let data = try ResumePDFRenderer.render(document: document)
    let pdf = try XCTUnwrap(PDFDocument(data: data))

    XCTAssertGreaterThan(pdf.pageCount, 0)
    XCTAssertLessThanOrEqual(pdf.pageCount, 52)
    XCTAssertLessThan(Date().timeIntervalSince(startedAt), 8)
  }

  func testLegacyApplicationsDecodeWithoutNewCaptureFields() throws {
    let application = JobApplication(
      company: "Example Labs", role: "People Lead", jobDescription: "Lead the people function",
      sourceURL: "https://example.com/job", status: .saved, notes: "",
      baseResumeID: UUID(), tailoredResumeID: nil, matchAnalysis: nil, interviewPlan: nil
    )
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(application)) as? [String: Any]
    )
    object.removeValue(forKey: "capturedOpportunity")
    object.removeValue(forKey: "deadline")
    object.removeValue(forKey: "activities")

    let decoded = try JSONDecoder().decode(
      JobApplication.self, from: JSONSerialization.data(withJSONObject: object)
    )
    XCTAssertNil(decoded.capturedOpportunity)
    XCTAssertNil(decoded.deadline)
    XCTAssertEqual(decoded.activityTimeline.first?.title, "Opportunity saved")
  }

  func testCareerIntelligencePersistsReversibleAIHistoryAndReviewState() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("career-enhancements-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let resumeID = UUID()
    let store = CareerIntelligenceStore(fileURL: url)
    store.addRevision(AIRevision(
      resumeID: resumeID, field: "Professional profile", before: "Original",
      after: "Revised", evidenceIDs: [], evidenceLabels: ["Verified role"],
      claimsRequiringConfirmation: []
    ))
    store.upsert(ResumeReviewRequest(
      resumeID: resumeID, reviewerName: "Jordan", reviewerEmail: "jordan@example.com",
      message: "Please review", accessCode: "ABCD1234",
      expiresAt: Date().addingTimeInterval(86_400), status: .feedbackReceived,
      comments: [ResumeReviewComment(
        remoteID: "remote-comment-1", section: "Experience", author: "Jordan",
        comment: "Clarify the outcome.", isResolved: true
      )]
    ))

    let reloaded = CareerIntelligenceStore(fileURL: url)
    XCTAssertEqual(reloaded.aiRevisions.first?.before, "Original")
    XCTAssertEqual(reloaded.reviewRequests.first?.comments.first?.remoteID, "remote-comment-1")
    XCTAssertTrue(reloaded.reviewRequests.first?.comments.first?.isResolved == true)
  }

  func testOfferComparisonIncludesCashBenefitsAndRealCosts() {
    let offer = JobOffer(
      applicationID: nil, company: "Example Labs", role: "Director", currencyCode: "ZAR",
      baseSalary: 1_000_000, bonus: 100_000, equitySummary: "", benefits: "",
      workStyle: "Hybrid", commuteMinutes: 30, growthRating: 4, cultureRating: 4,
      notes: "", deadline: nil, negotiationDraft: "", signingBonus: 50_000,
      employerRetirementAnnual: 80_000, medicalAnnual: 24_000, equityAnnualValue: 60_000,
      otherAnnualValue: 10_000, commuteAnnualCost: 36_000, remoteSavingsAnnual: 12_000,
      leaveDays: 25
    )
    XCTAssertEqual(offer.firstYearCash, 1_150_000)
    XCTAssertEqual(offer.estimatedAnnualValue, 1_300_000)
  }

  func testLayoutSettingsRoundTripAndDrivePaperHeadingsAndFont() throws {
    var document = ResumeDocument.example
    document.layout.fontChoice = .editorialSerif
    document.layout.fontScale = 0.91
    document.layout.lineSpacing = 0.94
    document.layout.marginPoints = 42
    document.layout.paperSize = .letter
    document.layout.pageTarget = .two
    document.layout.sectionOrder = [.experience, .profile, .competencies, .education, .additional, .references]
    document.layout.customHeadings[ResumeContentBlock.experience.rawValue] = "Career Evidence"

    let decoded = try JSONDecoder().decode(
      ResumeDocument.self, from: JSONEncoder().encode(document))
    XCTAssertEqual(decoded.layout, document.layout)

    let pdf = try XCTUnwrap(PDFDocument(data: ResumePDFRenderer.render(document: document)))
    let bounds = try XCTUnwrap(pdf.page(at: 0)).bounds(for: .mediaBox)
    XCTAssertEqual(bounds.width, 612, accuracy: 1)
    XCTAssertEqual(bounds.height, 792, accuracy: 1)
    let text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
    XCTAssertTrue(text.localizedCaseInsensitiveContains("Career Evidence"))
  }

  func testTemplateFinderRanksATSOptionsAndHonoursFreeOnly() throws {
    let strict = TemplateFinderPreferences(
      role: "Software Engineer", seniority: .experienced, market: .unitedStates,
      wantsPhoto: false, strictATS: true, targetPages: .one, freeOnly: false)
    let top = try XCTUnwrap(TemplateRecommendationEngine.recommendations(preferences: strict).first)
    XCTAssertFalse(top.template.plan.hasSideColumn)
    XCTAssertFalse(top.template.isPhotoLed)
    XCTAssertTrue(top.reasons.contains { $0.localizedCaseInsensitiveContains("ATS") })

    var free = strict
    free.freeOnly = true
    let freeResults = TemplateRecommendationEngine.recommendations(
      preferences: free,
      unlocked: { MonetizationCatalog.freeResumeTemplates.contains($0) })
    XCTAssertEqual(freeResults.count, MonetizationCatalog.freeResumeTemplates.count)
    XCTAssertTrue(freeResults.allSatisfy { MonetizationCatalog.freeResumeTemplates.contains($0.template) })

    let defaultResults = TemplateRecommendationEngine.recommendations(
      preferences: TemplateFinderPreferences())
    XCTAssertTrue(defaultResults.allSatisfy { (0...100).contains($0.score) })
    XCTAssertGreaterThan(
      Set(defaultResults.prefix(12).map(\.score)).count, 2,
      "Structurally different top matches should not all display the same fit")

    XCTAssertEqual(
      TemplateRecommendation(template: .minimal, score: 110, reasons: []).score,
      100,
      "The recommendation model must never expose an impossible percentage")
  }

  func testApplicationPacketPersistsAndExportsTheCompleteSet() throws {
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("packet-store-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: fileURL) }
    let resumeID = UUID()
    let application = JobApplication(
      company: "Evergreen Labs", role: "People Lead", jobDescription: "Lead people operations",
      sourceURL: "https://example.com/jobs/people-lead", status: .applied, notes: "",
      baseResumeID: resumeID, tailoredResumeID: nil, matchAnalysis: nil, interviewPlan: nil)
    let store = ApplicationStore(fileURL: fileURL)
    store.add(application)
    var resume = ResumeDocument.example
    resume.template = .atlas
    let packet = try XCTUnwrap(store.ensurePacket(
      for: application.id, resumeID: resumeID, resume: resume))
    XCTAssertEqual(packet.coverLetter.companyName, "Evergreen Labs")
    XCTAssertEqual(packet.coverLetter.template.pairsWith, resume.template)

    let reloaded = ApplicationStore(fileURL: fileURL)
    let persisted = try XCTUnwrap(reloaded.applications.first?.packet)
    XCTAssertEqual(persisted.id, packet.id)

    let files = try ApplicationPacketExporter.files(
      packet: persisted, application: application, resume: resume)
    defer { try? FileManager.default.removeItem(at: files[0].deletingLastPathComponent()) }
    XCTAssertEqual(files.count, 5)
    XCTAssertTrue(files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    XCTAssertEqual(Set(files.map(\.pathExtension)), ["pdf", "txt"])
  }

  func testApplicationAnalyticsCalculatesConversionAndSourcePerformance() throws {
    let resumeID = UUID()
    let started = Date(timeIntervalSince1970: 1_700_000_000)
    func application(_ status: JobApplicationStatus, source: String, responseDays: Int?) -> JobApplication {
      var value = JobApplication(
        company: UUID().uuidString, role: "Engineer", jobDescription: "", sourceURL: source,
        status: status, notes: "", baseResumeID: resumeID, tailoredResumeID: nil,
        matchAnalysis: nil, interviewPlan: nil, createdAt: started, updatedAt: started)
      if let responseDays {
        value.activities = [ApplicationActivity(
          kind: status == .offer ? .offer : .interview,
          title: "Response", detail: "",
          occurredAt: started.addingTimeInterval(Double(responseDays) * 86_400))]
      }
      return value
    }
    let applications = [
      application(.saved, source: "", responseDays: nil),
      application(.applied, source: "https://jobs.example.com/one", responseDays: nil),
      application(.interview, source: "https://jobs.example.com/two", responseDays: 4),
      application(.offer, source: "https://referrals.example.org/three", responseDays: 8),
    ]
    let summary = ApplicationAnalyticsService.summarize(applications)
    XCTAssertEqual(summary.tracked, 4)
    XCTAssertEqual(summary.applied, 3)
    XCTAssertEqual(summary.interviews, 2)
    XCTAssertEqual(summary.offers, 1)
    XCTAssertEqual(summary.applicationToInterviewRate, 67)
    XCTAssertEqual(summary.interviewToOfferRate, 50)
    XCTAssertEqual(try XCTUnwrap(summary.averageDaysToResponse), 6, accuracy: 0.01)
    XCTAssertEqual(summary.bySource.first { $0.name == "jobs.example.com" }?.count, 2)
  }

  func testLocalizationAndTranslationPreserveIdentityAndEvidenceStructure() throws {
    var localized = ResumeDocument.example
    ResumeMarketLocalizationService.apply(
      market: .unitedStates, language: "isiZulu", to: &localized)
    XCTAssertEqual(localized.layout.paperSize, .letter)
    XCTAssertEqual(
      localized.layout.heading(for: .experience),
      "Ulwazi Lomsebenzi")

    let source = ResumeDocument.example
    let translated = AITranslatedResume(
      headline: "Responsable des opérations humaines",
      professionalProfile: "Profil traduit fondé sur les mêmes preuves.",
      competencies: ["Analyse des personnes"],
      experience: source.experience.map {
        AITailoredExperience(id: $0.id.uuidString, highlights: $0.highlights.map { "FR: \($0)" })
      },
      education: source.education.indices.map {
        AITranslatedEducation(
          index: $0, qualification: "FR: \(source.education[$0].qualification)",
          institution: source.education[$0].institution,
          period: source.education[$0].period,
          details: "FR: \(source.education[$0].details)")
      },
      additionalSections: [],
      translatedHeadings: [ResumeContentBlock.experience.rawValue: "Expérience Professionnelle"],
      claimsRequiringConfirmation: [])
    let result = translated.applying(to: source)
    XCTAssertEqual(result.personal.fullName, source.personal.fullName)
    XCTAssertEqual(result.personal.email, source.personal.email)
    XCTAssertEqual(result.experience.map(\.id), source.experience.map(\.id))
    XCTAssertEqual(result.experience.map(\.role), source.experience.map(\.role))
    XCTAssertEqual(result.experience.map(\.period), source.experience.map(\.period))
    XCTAssertEqual(result.layout.heading(for: .experience), "Expérience Professionnelle")
  }

  func testATSEvidenceShowsMatchedMissingAndActionableDestinations() throws {
    let advert = "People analytics manager coaching Kubernetes Terraform observability"
    let report = ATSReadinessService.analyze(
      document: .example, jobDescription: advert)
    XCTAssertTrue(report.matchedKeywords.contains("analytics"))
    XCTAssertTrue(report.missingKeywords.contains("kubernetes"))
    XCTAssertTrue(report.missingKeywords.contains("terraform"))
    XCTAssertNotNil(report.items.first { $0.id == "keywords" }?.section)

    var portraitDocument = ResumeDocument.example
    portraitDocument.photo = try XCTUnwrap(ProfilePhoto.prepare(Self.samplePhotoData()))
    let portraitFormatItem = ATSReadinessService.analyze(document: portraitDocument)
      .items.first { $0.id == "format" }
    XCTAssertEqual(portraitFormatItem?.section, .personal)
    XCTAssertTrue(
      portraitFormatItem?.detail.contains("Show in CV") == true)

    let suggestions = ATSReadinessService.keywordSuggestions(
      document: .example, jobDescription: advert)
    XCTAssertTrue(suggestions.contains { $0.keyword == "kubernetes" })
    XCTAssertTrue(suggestions.allSatisfy { !$0.guidance.isBlank })
  }

  func testRecruiterScanReadsTheExampleHonestly() {
    let report = RecruiterScanService.analyze(document: .example)

    // The example résumé is complete except for one deliberate gap: its first
    // bullet carries no number, so the evidence fixation must be the only
    // warning. If the example content changes, the scan should notice.
    XCTAssertEqual(report.score, 92)
    XCTAssertEqual(report.verdict, "Survives the first pass")
    XCTAssertFalse(report.findings.contains { $0.severity == .action })
    XCTAssertEqual(
      report.findings.filter { $0.severity == .warning }.map(\.id), ["evidence"])
    XCTAssertTrue(report.capturedFacts.contains { $0.contains("Northstar Works") })

    // Weights stay tied to the study's gaze shares: every finding claims part
    // of the 7.4 seconds, and the maximum points total exactly 100.
    XCTAssertEqual(report.findings.reduce(0) { $0 + $1.maxPoints }, 100)
    XCTAssertEqual(
      report.findings.reduce(0.0) { $0 + $1.gazeSeconds },
      RecruiterScanStudy.scanSeconds - 0.3, accuracy: 0.001)
  }

  func testRecruiterScanFlagsAnEmptyResume() {
    let report = RecruiterScanService.analyze(document: .blank)
    XCTAssertLessThan(report.score, 10)
    XCTAssertEqual(report.verdict, "Invisible in seven seconds")
    for id in ["identity", "current-role", "current-dates", "evidence", "education"] {
      XCTAssertEqual(
        report.findings.first { $0.id == id }?.severity, .action,
        "\(id) should demand action on an empty résumé")
    }
    XCTAssertTrue(report.capturedFacts.isEmpty)
    XCTAssertFalse(report.missedFacts.isEmpty)
  }

  func testRecruiterScanRewardsAQuantifiedFirstBullet() {
    XCTAssertTrue(RecruiterScanService.isQuantified("Cut onboarding time by 38%"))
    XCTAssertTrue(RecruiterScanService.isQuantified("Managed a R2.4m budget"))
    XCTAssertFalse(RecruiterScanService.isQuantified("Led a team of engineers"))

    var quantifiedFirst = ResumeDocument.example
    quantifiedFirst.experience[0].highlights[0] = "Cut onboarding time by 38% across 4 regions."
    let strong = RecruiterScanService.analyze(document: quantifiedFirst)
    XCTAssertEqual(strong.findings.first { $0.id == "evidence" }?.severity, .pass)
    XCTAssertEqual(strong.score, 100)

    // A number buried lower in the role is credited, but told to move up.
    var buried = ResumeDocument.example
    buried.experience[0].highlights[2] = "Lifted engagement scores by 12 points."
    let moved = RecruiterScanService.analyze(document: buried)
    let evidence = moved.findings.first { $0.id == "evidence" }
    XCTAssertEqual(evidence?.severity, .warning)
    XCTAssertTrue(evidence?.detail.contains("Move it up") == true)
  }

  func testRecruiterScanStrictnessMovesTheBar() {
    // The example carries no numbers anywhere in its latest role, so the three
    // levels read the same page differently: low forgives the prose bullets,
    // medium asks for a number, high refuses to pass without one.
    let low = RecruiterScanService.analyze(document: .example, strictness: .low)
    let medium = RecruiterScanService.analyze(document: .example, strictness: .medium)
    let high = RecruiterScanService.analyze(document: .example, strictness: .high)
    XCTAssertEqual(low.score, 100)
    XCTAssertEqual(medium.score, 92)
    XCTAssertEqual(high.score, 80)
    XCTAssertEqual(low.findings.first { $0.id == "evidence" }?.severity, .pass)
    XCTAssertEqual(medium.findings.first { $0.id == "evidence" }?.severity, .warning)
    XCTAssertEqual(high.findings.first { $0.id == "evidence" }?.severity, .action)

    // A single-role résumé slides one severity per level on trajectory.
    var singleRole = ResumeDocument.example
    singleRole.experience = [singleRole.experience[0]]
    let expectations: [(RecruiterScanStrictness, ATSIssueSeverity)] = [
      (.low, .pass), (.medium, .warning), (.high, .action),
    ]
    for (level, expected) in expectations {
      let report = RecruiterScanService.analyze(document: singleRole, strictness: level)
      XCTAssertEqual(
        report.findings.first { $0.id == "trajectory" }?.severity, expected,
        "single role at \(level.rawValue) strictness")
    }

    // The default stays the study baseline.
    XCTAssertEqual(RecruiterScanService.analyze(document: .example).score, medium.score)
  }

  func testRecruiterGazePathStaysOnThePageForEveryTemplate() {
    for template in ResumeTemplate.allCases {
      var document = ResumeDocument.example
      document.template = template
      let stops = RecruiterScanService.gazePath(for: document)
      XCTAssertFalse(stops.isEmpty, "\(template) produced no gaze path")
      for stop in stops {
        XCTAssertTrue(
          (0.0...1.0).contains(stop.point.x) && (0.0...1.0).contains(stop.point.y),
          "\(template) sent the gaze off the page at \(stop.point)")
        XCTAssertGreaterThan(stop.duration, 0)
        XCTAssertFalse(stop.label.isEmpty)
      }
      XCTAssertEqual(
        stops.reduce(0.0) { $0 + $1.duration }, RecruiterScanStudy.scanSeconds,
        accuracy: 0.001,
        "\(template) does not spend exactly the study's 7.4 seconds")
    }
  }

  func testRecruiterGazePathFollowsTheTemplatePlan() {
    func stops(_ template: ResumeTemplate) -> [RecruiterGazeStop] {
      var document = ResumeDocument.example
      document.template = template
      return RecruiterScanService.gazePath(for: document)
    }
    func stop(_ label: String, in path: [RecruiterGazeStop]) -> RecruiterGazeStop? {
      path.first { $0.label == label }
    }

    // A leading facts rail pushes the main story to the right.
    let atlasRole = stop("Current title and company", in: stops(.atlas))
    let classicRole = stop("Current title and company", in: stops(.classic))
    XCTAssertGreaterThan(atlasRole?.point.x ?? 0, (classicRole?.point.x ?? 1) + 0.15)

    // A trailing rail keeps education in the right-hand column.
    XCTAssertGreaterThan(stop("Education check", in: stops(.verso))?.point.x ?? 0, 0.7)

    // Margin dates hang left of the story; stacked dates sit on the right edge.
    XCTAssertLessThan(stop("Dates check", in: stops(.gazette))?.point.x ?? 1, 0.08)
    XCTAssertGreaterThan(stop("Dates check", in: stops(.classic))?.point.x ?? 0, 0.7)

    // A visible portrait claims the first fixation without stretching the scan.
    var withPhoto = ResumeDocument.example
    withPhoto.photo = Data([0x1])
    withPhoto.isPhotoVisible = true
    let photoPath = RecruiterScanService.gazePath(for: withPhoto)
    XCTAssertEqual(photoPath.first?.label, "The portrait")
    XCTAssertEqual(
      photoPath.reduce(0.0) { $0 + $1.duration }, RecruiterScanStudy.scanSeconds,
      accuracy: 0.001)
  }

  func testSmartLinkAllowancesAndTokensMatchTheBackend() {
    // Mirrors LINK_LIMITS in functions/src/link-policy.js — both sides must
    // promise the same numbers.
    XCTAssertEqual(ResumeStudioPlan.free.smartLinkLimit, 1)
    XCTAssertEqual(ResumeStudioPlan.go.smartLinkLimit, 5)
    XCTAssertEqual(ResumeStudioPlan.pro.smartLinkLimit, 25)

    // Tokens must satisfy the backend's ^[A-Za-z0-9-]{24,80}$ gate.
    for _ in 0..<20 {
      let token = SmartLink.newToken()
      XCTAssertEqual(token.count, 40)
      XCTAssertNil(token.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted))
    }
  }

  func testSmartLinkAccountingAndUnseenOpens() {
    var link = SmartLink(
      token: SmartLink.newToken(),
      url: URL(string: "https://example.com/cv/x")!,
      title: "Avery Sample Resume",
      company: "Acme Corp",
      createdAt: Date(),
      expiresAt: Date(timeIntervalSinceNow: 86_400)
    )
    XCTAssertTrue(link.isActive)
    XCTAssertEqual(link.unseenOpens, 0)

    link.views = [
      SmartLinkView(id: "a", firstOpenedAt: Date(), lastSeenAt: Date(), opens: 2, seconds: 90, viewer: "iPhone · Safari", downloadedPDF: false),
      SmartLinkView(id: "b", firstOpenedAt: Date(), lastSeenAt: Date(timeIntervalSinceNow: -600), opens: 1, seconds: 30, viewer: "Windows · Chrome", downloadedPDF: true),
    ]
    XCTAssertEqual(link.totalOpens, 3)
    XCTAssertEqual(link.totalSeconds, 120)
    XCTAssertEqual(link.unseenOpens, 3)

    link.acknowledgedOpens = link.totalOpens
    XCTAssertEqual(link.unseenOpens, 0)

    link.status = .revoked
    XCTAssertFalse(link.isActive)
  }

  func testSmartLinkStorePersistsAcrossLaunches() throws {
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("smart-links-test-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: fileURL) }

    let store = SmartLinkStore(fileURL: fileURL)
    var link = SmartLink(
      token: SmartLink.newToken(),
      url: URL(string: "https://example.com/cv/y")!,
      title: "Avery Sample Resume",
      company: "Northstar Works",
      createdAt: Date(),
      expiresAt: Date(timeIntervalSinceNow: 86_400)
    )
    link.views = [
      SmartLinkView(id: "v", firstOpenedAt: Date(), lastSeenAt: Date(), opens: 1, seconds: 45, viewer: "Mac · Safari", downloadedPDF: false),
    ]
    store.add(link)
    XCTAssertEqual(store.activeCount, 1)
    XCTAssertEqual(store.unseenOpens, 1)
    XCTAssertEqual(store.mostRecentUnseenLink?.id, link.id)

    store.acknowledge(link.id)
    XCTAssertEqual(store.unseenOpens, 0)

    let reloaded = SmartLinkStore(fileURL: fileURL)
    XCTAssertEqual(reloaded.links.count, 1)
    XCTAssertEqual(reloaded.links.first?.company, "Northstar Works")
    XCTAssertEqual(reloaded.links.first?.acknowledgedOpens, 1)
    XCTAssertEqual(reloaded.unseenOpens, 0)
  }

  func testShortcutRoutesAreConsumedOnce() {
    _ = ShortcutRouteStore.consume()
    var receivedNotification = false
    let observer = NotificationCenter.default.addObserver(
      forName: .shortcutRouteQueued, object: nil, queue: nil
    ) { _ in
      receivedNotification = true
    }
    defer { NotificationCenter.default.removeObserver(observer) }
    ShortcutRouteStore.queue("ats")
    XCTAssertTrue(receivedNotification)
    _ = ShortcutRouteStore.consume()
  }
}

extension CGSize {
  fileprivate func contains(rect: CGRect) -> Bool {
    rect.minX >= 0 && rect.minY >= 0 && rect.maxX <= width && rect.maxY <= height
  }
}
