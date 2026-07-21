import PDFKit
import PencilKit
import SwiftUI
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
    XCTAssertEqual(ResumeStudioPlan.free.dailyAIImportLimit, 1)
    XCTAssertEqual(ResumeStudioPlan.go.dailyAIImportLimit, 1)
    XCTAssertEqual(ResumeStudioPlan.pro.dailyAIImportLimit, 2)

    XCTAssertEqual(MonetizationCatalog.freeResumeTemplates.count, 34)
    XCTAssertEqual(MonetizationCatalog.freeCoverLetterTemplates.count, 16)
    XCTAssertTrue(MonetizationCatalog.freeResumeTemplates.isSubset(of: Set(ResumeTemplate.allCases)))
    XCTAssertTrue(MonetizationCatalog.freeCoverLetterTemplates.isSubset(of: Set(CoverLetterTemplate.allCases)))

    // The four original accents are free; the sixteen Signature, Atelier, and
    // Luxe tones are subscription only, gated like the premium templates.
    XCTAssertEqual(MonetizationCatalog.freeAccents.count, 4)
    XCTAssertEqual(MonetizationCatalog.freeAccents, [.orange, .blue, .teal, .burgundy])
    XCTAssertEqual(ResumeAccent.allCases.count, 20)
    XCTAssertEqual(ResumeAccent.allCases.filter(\.isPremium).count, 16)
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
    XCTAssertEqual(ResumeAIAction.negotiationPractice.creditCost, 1)
    XCTAssertEqual(ResumeAIAction.writeCoverLetter.creditCost, 3)
    XCTAssertEqual(ResumeAIAction.evaluateInterviewAnswer.creditCost, 3)
    XCTAssertEqual(ResumeAIAction.tailorResume.creditCost, 5)
    XCTAssertEqual(ResumeAIAction.interviewPrep.creditCost, 5)
    XCTAssertEqual(ResumeAIAction.translateResume.creditCost, 5)
  }

  func testHybridAIRoutingPolicyKeepsComplexQualityChoicePredictable() {
    XCTAssertEqual(HybridAIRoutingPolicy.initialRoute(plan: .free, onDeviceEnabled: true), .onDevice)
    XCTAssertEqual(HybridAIRoutingPolicy.initialRoute(plan: .free, onDeviceEnabled: false), .connected)
    XCTAssertEqual(HybridAIRoutingPolicy.initialRoute(plan: .go, onDeviceEnabled: true), .connected)
    XCTAssertEqual(HybridAIRoutingPolicy.initialRoute(plan: .pro, onDeviceEnabled: true), .connected)
  }

  func testOnDeviceQualityGateRejectsWeakOrDuplicateOutput() throws {
    XCTAssertThrowsError(try OnDeviceAIQualityGate.textAlternatives(["Short", "Short", "Short"]))
    let alternatives = try OnDeviceAIQualityGate.textAlternatives([
      "Led cross-functional planning for the supported programme.",
      "Coordinated cross-functional planning for the supported programme.",
      "Directed cross-functional planning for the supported programme.",
    ])
    XCTAssertEqual(alternatives.count, 3)
    XCTAssertThrowsError(try OnDeviceAIQualityGate.competencies(
      ["Leadership", "Leadership", "Planning"], excluding: []))
    XCTAssertFalse(OnDeviceAIQualityGate.isReviewableJob(role: "", company: "", description: "Too short"))
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

  func testOfflineEntitlementCacheRetainsServerVerifiableProofAndDecodesLegacyData() throws {
    let expiry = Date(timeIntervalSince1970: 2_000_086_400)
    let cached = OfflineEntitlements(
      plan: .pro,
      subscriptionExpiry: expiry,
      hasDesignPack: false,
      verifiedAt: Date(timeIntervalSince1970: 2_000_000_000),
      signedTransactions: [ResumeStudioProduct.proMonthly: "signed-pro-jws"],
      signedAppTransaction: "signed-app-jws"
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(OfflineEntitlements.self, from: encoder.encode(cached))
    XCTAssertEqual(decoded.signedTransactions?[ResumeStudioProduct.proMonthly], "signed-pro-jws")
    XCTAssertEqual(decoded.signedAppTransaction, "signed-app-jws")

    let legacy = Data("""
      {"plan":"pro","subscriptionExpiry":"2033-05-19T03:33:20Z","hasDesignPack":false,"verifiedAt":"2033-05-18T03:33:20Z"}
      """.utf8)
    let legacyDecoded = try decoder.decode(OfflineEntitlements.self, from: legacy)
    XCTAssertNil(legacyDecoded.signedTransactions)
    XCTAssertNil(legacyDecoded.signedAppTransaction)
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
    XCTAssertEqual(ResumeTemplate.allCases.count, 140)

    // Every template is its own look: no shared names, no shared descriptions.
    XCTAssertEqual(Set(ResumeTemplate.allCases.map(\.title)).count, 140)
    XCTAssertEqual(Set(ResumeTemplate.allCases.map(\.subtitle)).count, 140)
    XCTAssertEqual(Set(ResumeTemplate.allCases.map(\.rawValue)).count, 140)

    // The photo-led ones build their header around the portrait. Everything else
    // takes a photo too — it just closes the space up without one.
    XCTAssertEqual(
      ResumeTemplate.allCases.filter(\.isPhotoLed),
      [
        .atlas, .portrait, .spotlight, .beacon, .harbor, .bloom, .atelier, .canvas, .insignia,
        .nova, .monarch, .eclipse, .aperture, .gallery, .halo, .orbit, .panorama, .spectrum,
        .zenith, .alcove, .radiant, .zephyr, .vellum,
        .salute, .couture, .medallion, .sable, .terracotta, .circlet, .vogue,
        .passport, .cutline, .constellation,
      ]
    )
  }

  func testAdvancedCollectionAndFreeShowcaseStayIntentional() throws {
    let advanced = ResumeTemplate.allCases.filter { $0.advancedStyle != nil }
    XCTAssertEqual(advanced.count, 71)
    XCTAssertEqual(Set(advanced.compactMap { $0.advancedStyle?.ordinal }), Set(0..<71))

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
    XCTAssertEqual(Set(advanced).subtracting(freeAdvanced).count, 49)

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
    let showcase = advanced.filter {
      let ordinal = $0.advancedStyle?.ordinal ?? 0
      return ordinal >= 52 && ordinal < 62
    }
    XCTAssertEqual(showcase.count, 10)
    for template in showcase {
      let style = try XCTUnwrap(template.advancedStyle)
      XCTAssertGreaterThanOrEqual(style.motif, 16, template.title)
      XCTAssertLessThanOrEqual(style.motif, 25, template.title)
      XCTAssertTrue(style.styleTags.contains(.showcase), template.title)
    }
    XCTAssertEqual(
      ResumeTemplate.allCases.filter { $0.styleTags.contains(.showcase) }.count, 10)

    // Studio is the bespoke collection: one dedicated construction per template,
    // after the Showcase range, and a gallery filter of its own.
    let studio = advanced.filter { ($0.advancedStyle?.ordinal ?? 0) >= 62 }
    XCTAssertEqual(studio.count, 9)
    XCTAssertEqual(studio.compactMap { $0.advancedStyle?.motif }, Array(26...34))
    XCTAssertTrue(studio.allSatisfy { $0.styleTags.contains(.studio) })
    XCTAssertEqual(ResumeTemplate.allCases.filter { $0.styleTags.contains(.studio) }.count, 9)
  }

  /// The point of the structural templates: they rearrange the page, not the
  /// letterhead. Sixty of them do, and each does it differently — otherwise they
  /// are just more headers on the same one-column résumé.
  func testStructuralTemplatesActuallyRestructureThePage() {
    let structural = ResumeTemplate.allCases.filter { $0.styleTags.contains(.structured) }
    XCTAssertEqual(structural.count, 60)

    // Every structural template departs from the plain single-column flow...
    for template in structural {
      XCTAssertNotEqual(template.plan, TemplatePlan(), template.title)
    }

    // No two of them are built the same way.
    XCTAssertEqual(Set(structural.map(\.plan)).count, structural.count)

    // Twenty-seven run a column of their own; the ATS check has to warn about exactly
    // those, since a parser can read two columns out of order.
    XCTAssertEqual(
      structural.filter { $0.plan.hasSideColumn },
      [
        .atlas, .verso, .oxford, .duo, .concise, .gauge, .crest, .geneva,
        .stockholm, .tandem, .varsity, .prism,
        .aperture, .blueprint, .circuit, .district, .facet, .helix, .lattice, .panorama,
        .quantum, .sentinel, .tessera, .alcove, .palisade,
        .bauhaus, .passport,
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
      return (String(localized: accent.title), page.thumbnail(of: CGSize(width: 357, height: 505), for: .mediaBox))
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

  /// One glance over the whole advanced catalogue, including Studio résumés and
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

  func testJobSpecImportReadsPDFDOCXAndText() async throws {
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
    let pdf = try await JobSpecImportService.importDocument(from: pdfURL)
    XCTAssertTrue(pdf.text.contains("workforce planning"))
    XCTAssertEqual(pdf.fileName, "People Lead Spec.pdf")

    let docxURL = directory.appendingPathComponent("Role.docx")
    try ResumeDOCXRenderer.render(document: .example).write(to: docxURL)
    let docx = try await JobSpecImportService.importDocument(from: docxURL)
    XCTAssertTrue(docx.text.contains("People Operations Manager"))

    let textURL = directory.appendingPathComponent("Role.txt")
    try "Own hiring operations and coach senior managers".write(
      to: textURL, atomically: true, encoding: .utf8)
    let text = try await JobSpecImportService.importDocument(from: textURL)
    XCTAssertEqual(text.text, "Own hiring operations and coach senior managers")
  }

  func testJobSpecImportUsesOnDeviceOCRForAnImage() async throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
    defer { try? FileManager.default.removeItem(at: url) }
    let image = UIGraphicsImageRenderer(size: CGSize(width: 1_400, height: 420)).image { context in
      UIColor.white.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 1_400, height: 420))
      NSAttributedString(
        string: "Senior Product Designer",
        attributes: [.font: UIFont.systemFont(ofSize: 86, weight: .semibold), .foregroundColor: UIColor.black]
      ).draw(at: CGPoint(x: 55, y: 145))
    }
    try XCTUnwrap(image.pngData()).write(to: url)

    let imported = try await JobSpecImportService.importDocument(from: url)
    XCTAssertTrue(imported.text.localizedCaseInsensitiveContains("Product Designer"))
    XCTAssertEqual(imported.ocrPageCount, 0)
  }

  func testResumePhotoImportUsesOnDeviceOCR() async throws {
    let image = UIGraphicsImageRenderer(size: CGSize(width: 1_400, height: 700)).image { context in
      UIColor.white.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 1_400, height: 700))
      NSAttributedString(
        string: "SAMPLE CANDIDATE\nEXPERIENCE\nProject Coordinator",
        attributes: [
          .font: UIFont.systemFont(ofSize: 64, weight: .semibold),
          .foregroundColor: UIColor.black,
        ]
      ).draw(in: CGRect(x: 55, y: 130, width: 1_290, height: 450))
    }

    let text = try await ResumeImportService.extractText(
      fromImageData: XCTUnwrap(image.pngData())
    )
    XCTAssertTrue(text.localizedCaseInsensitiveContains("SAMPLE CANDIDATE"), text)
    XCTAssertTrue(text.localizedCaseInsensitiveContains("Project Coordinator"), text)
  }

  func testJobSpecImportCombinesSelectableAndScannedPDFPages() async throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).appendingPathExtension("pdf")
    defer { try? FileManager.default.removeItem(at: url) }
    let scannedPage = UIGraphicsImageRenderer(size: CGSize(width: 1_200, height: 500)).image { context in
      UIColor.white.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 1_200, height: 500))
      NSAttributedString(
        string: "Lead customer research programmes",
        attributes: [.font: UIFont.systemFont(ofSize: 66, weight: .bold), .foregroundColor: UIColor.black]
      ).draw(at: CGPoint(x: 45, y: 190))
    }
    let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842)).pdfData { context in
      context.beginPage()
      NSAttributedString(string: "Senior Product Designer role and team context")
        .draw(at: CGPoint(x: 40, y: 40))
      context.beginPage()
      scannedPage.draw(in: CGRect(x: 30, y: 160, width: 535, height: 223))
    }
    try data.write(to: url)

    let imported = try await JobSpecImportService.importDocument(from: url)
    XCTAssertTrue(imported.text.localizedCaseInsensitiveContains("Senior Product Designer"))
    XCTAssertTrue(imported.text.localizedCaseInsensitiveContains("customer research"), imported.text)
    XCTAssertEqual(imported.ocrPageCount, 1)
    XCTAssertFalse(imported.wasPageLimited)
  }

  func testJobSpecImportReportsItsTwentyPageSafetyLimit() async throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).appendingPathExtension("pdf")
    defer { try? FileManager.default.removeItem(at: url) }
    let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842)).pdfData { context in
      for page in 1...21 {
        context.beginPage()
        NSAttributedString(string: "Job pack page \(page) with responsibilities and requirements")
          .draw(at: CGPoint(x: 40, y: 40))
      }
    }
    try data.write(to: url)

    let imported = try await JobSpecImportService.importDocument(from: url)
    XCTAssertTrue(imported.wasPageLimited)
    XCTAssertTrue(imported.wasTruncated)
    XCTAssertTrue(imported.text.contains("page 20"))
    XCTAssertFalse(imported.text.contains("page 21"))
  }

  func testTodayPriorityAndWeeklyCampaignProgressPreferRealActivity() {
    XCTAssertGreaterThan(TodayActionPriority.imminentInterview, .campaign)
    XCTAssertGreaterThan(TodayActionPriority.dueFollowUp, .resumeReadiness)
    let start = Date().addingTimeInterval(-3_600)
    let resumeID = UUID()
    var application = JobApplication(
      company: "Example", role: "Designer", jobDescription: "Role", sourceURL: "",
      status: .applied, notes: "", baseResumeID: resumeID,
      tailoredResumeID: nil, matchAnalysis: nil, interviewPlan: nil)
    application.createdAt = start.addingTimeInterval(-86_400)
    application.activities = [ApplicationActivity(
      kind: .followUp, title: "Followed up", detail: "Email", occurredAt: Date())]
    let contact = CareerContact(
      name: "Sam", role: "Recruiter", company: "Example", email: "", linkedInURL: "",
      kind: .recruiter, applicationID: nil, notes: "", lastContactedAt: Date(), followUpAt: nil,
      interactions: [ContactInteraction(kind: .email, summary: "Introduced", occurredAt: Date())])
    let attempt = VoicePracticeAttempt(
      applicationID: nil, question: "Tell me about yourself", transcript: "Answer",
      durationSeconds: 30, wordsPerMinute: 120, fillerWords: [], starCoverage: [], strengths: [],
      improvements: [], suggestedAnswerShape: "", claimsRequiringConfirmation: [], createdAt: Date())

    XCTAssertEqual(
      WeeklyCampaignService.progress(
        applications: [application], contacts: [contact], voiceAttempts: [attempt], since: start),
      WeeklyCampaignProgress(applications: 1, networking: 1, practice: 1))

    // A negotiation rehearsal counts as practice too; one from last week does not.
    let rehearsal = NegotiationPracticeSession(
      company: "Example", role: "Designer", persona: .formalRecruiter, difficulty: .realistic,
      goal: "Raise base", offerSummary: "Offer: ZAR 100 base", messages: [])
    var oldRehearsal = rehearsal
    oldRehearsal.id = UUID()
    oldRehearsal.createdAt = start.addingTimeInterval(-86_400)
    XCTAssertEqual(
      WeeklyCampaignService.progress(
        applications: [application], contacts: [contact], voiceAttempts: [attempt],
        negotiationSessions: [rehearsal, oldRehearsal], since: start),
      WeeklyCampaignProgress(applications: 1, networking: 1, practice: 2))
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
    XCTAssertEqual(CoverLetterTemplate.allCases.count, 65)

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
        .kintsugi, .bauhaus, .terminal, .topograph, .passport, .transit, .cutline, .receipt,
        .constellation,
      ]
    )
    XCTAssertEqual(CoverLetterTemplate.allCases.compactMap(\.advancedOrdinal), Array(0..<37))
    let studioLetters = CoverLetterTemplate.allCases.filter { $0.styleTags.contains(.studio) }
    let studioResumes = Set(
      ResumeTemplate.allCases.filter { $0.styleTags.contains(.studio) }
    )
    XCTAssertEqual(studioLetters.count, 10)
    XCTAssertEqual(Set(studioLetters.compactMap(\.pairsWith)), studioResumes)
    XCTAssertEqual(studioLetters.filter { $0.pairsWith == nil }, [.studioFolio])
    XCTAssertEqual(
      Set(CoverLetterTemplate.allCases.map(\.title)).count,
      CoverLetterTemplate.allCases.count
    )
    XCTAssertEqual(
      Set(CoverLetterTemplate.allCases.map { String(localized: $0.subtitle) }).count,
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
    XCTAssertEqual(
      Set(ResumeAccent.allCases.map { String(localized: $0.title) }).count,
      ResumeAccent.allCases.count)
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

  // MARK: - Section styles

  /// The whole promise of section styles: a résumé that has not asked for one is
  /// drawn exactly as it was before they existed.
  ///
  /// Two guarantees together give that. No template may ship a value for the
  /// three sections whose look used to be inferred — while those stay `nil`, the
  /// renderer takes the branch that reproduces the old derivation verbatim. And
  /// laying an empty override set over a plan must be the identity, so a résumé
  /// that customises nothing customises nothing.
  ///
  /// (Rendering twice and comparing bytes cannot stand in for this: a PDF
  /// carries its creation date, so two renders of one document never match.)
  func testUncustomisedTemplatesKeepTheirOriginalSectionLooks() {
    for template in ResumeTemplate.allCases {
      let plan = template.plan
      XCTAssertNil(plan.education, "\(template.rawValue) pins an education style")
      XCTAssertNil(plan.references, "\(template.rawValue) pins a reference style")
      XCTAssertNil(plan.additional, "\(template.rawValue) pins an extra-section style")
      XCTAssertEqual(plan.applying(.none), plan, "\(template.rawValue) drifted under no overrides")
    }
  }

  func testSectionStylesOverrideTheTemplateAndSurviveARoundTrip() throws {
    // Chronicle draws a timeline; asking for margin dates has to beat it.
    var document = ResumeDocument.example
    document.template = .chronicle
    XCTAssertEqual(document.template.plan.experience, .timeline)

    document.layout.sectionStyles.experience = .dateGutter
    document.layout.sectionStyles.competencies = .chips
    document.layout.sectionStyles.references = .compact
    document.layout.sectionStyles.additional = .chips

    let plan = document.template.plan.applying(document.layout.sectionStyles)
    XCTAssertEqual(plan.experience, .dateGutter)
    XCTAssertEqual(plan.competencies, .chips)
    XCTAssertEqual(plan.references, .compact)

    // The overridden document is a different document, and still a valid PDF.
    XCTAssertNotEqual(
      try ResumePDFRenderer.render(document: document),
      try ResumePDFRenderer.render(document: .example))
    let pdf = try XCTUnwrap(PDFDocument(data: ResumePDFRenderer.render(document: document)))
    let text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
    XCTAssertTrue(text.contains("Riley Example"), text)
    XCTAssertTrue(text.contains("People Operations Strategy"), text)

    let decoded = try JSONDecoder().decode(
      ResumeDocument.self, from: JSONEncoder().encode(document))
    XCTAssertEqual(decoded.layout.sectionStyles, document.layout.sectionStyles)
    XCTAssertEqual(decoded.layout.sectionStyles.count, 4)
  }

  /// Moving the column keeps whatever the template painted there; a template
  /// that never had one gets a plain column rather than an invented colour band.
  func testColumnOverrideMovesAndFlattensTheLayout() {
    let atlas = ResumeTemplate.atlas.plan
    guard case .side(let native) = atlas.body else { return XCTFail("Atlas lost its column") }
    XCTAssertEqual(native.edge, .leading)

    guard case .side(let moved) = atlas.applying(.init(body: .rightColumn)).body else {
      return XCTFail("column was dropped")
    }
    XCTAssertEqual(moved.edge, .trailing)
    XCTAssertEqual(moved.fill, native.fill, "the template's own band should survive the move")
    XCTAssertEqual(moved.width, native.width)

    XCTAssertFalse(atlas.applying(.init(body: .single)).hasSideColumn)

    let classic = ResumeTemplate.classic.plan
    XCTAssertFalse(classic.hasSideColumn)
    guard case .side(let added) = classic.applying(.init(body: .leftColumn)).body else {
      return XCTFail("no column was added")
    }
    XCTAssertEqual(added.fill, SideColumn.Fill.none)
    XCTAssertTrue(added.divider)
  }

  /// Every section style has to survive a full render on a template that did not
  /// ship with it — that is the entire point of the feature.
  func testEverySectionStyleRendersOnATemplateThatDidNotShipWithIt() throws {
    var overrides: [ResumeSectionStyleOverrides] = []
    for style in ExperienceStyle.allCases { overrides.append(.init(experience: style)) }
    for style in CompetencyStyle.allCases { overrides.append(.init(competencies: style)) }
    for style in EducationStyle.allCases { overrides.append(.init(education: style)) }
    for style in ReferenceStyle.allCases { overrides.append(.init(references: style)) }
    for style in AdditionalSectionStyle.allCases { overrides.append(.init(additional: style)) }
    for style in ContactStyle.allCases { overrides.append(.init(contact: style)) }
    for style in SectionChrome.allCases { overrides.append(.init(sectionChrome: style)) }
    for choice in BodyLayoutChoice.allCases { overrides.append(.init(body: choice)) }
    overrides.append(.init(numberedSections: true))
    overrides.append(.init(hangingHeadings: true))

    // One single-column template and one two-column one, so both page shapes see
    // every style.
    for template in [ResumeTemplate.modern, .atlas] {
      for override in overrides {
        var document = ResumeDocument.example
        document.template = template
        document.layout.sectionStyles = override
        let pdf = try XCTUnwrap(
          PDFDocument(data: ResumePDFRenderer.render(document: document)),
          "\(template.rawValue) failed to render \(override)")
        XCTAssertGreaterThan(pdf.pageCount, 0)
        let text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }
          .joined(separator: "\n")
        // Nothing may be dropped on the floor by a restyle.
        XCTAssertTrue(text.contains("Avery Sample"), "\(template.rawValue) \(override)")
        XCTAssertTrue(
          text.localizedCaseInsensitiveContains("Northstar Works"),
          "\(template.rawValue) lost an employer under \(override)")
      }
    }
  }

  /// Visual-review artifact: one template wearing other templates' section
  /// styles. Text tests prove nothing was dropped; only this shows whether the
  /// borrowed style sits properly on a page it was not designed for.
  func testSectionStyleContactSheet() throws {
    let cases: [(String, ResumeSectionStyleOverrides)] = [
      ("Modern, untouched", .none),
      ("+ timeline roles", .init(experience: .timeline)),
      ("+ margin dates", .init(experience: .dateGutter)),
      ("+ skill pills", .init(competencies: .chips)),
      ("+ dot ratings", .init(competencies: .dots)),
      ("+ education cards", .init(education: .card)),
      ("+ plain referees", .init(references: .plain)),
      ("+ one-line referees", .init(references: .compact)),
      ("+ extras as pills", .init(additional: .chips)),
      ("+ numbered headings", .init(numberedSections: true)),
      ("+ margin headings", .init(hangingHeadings: true)),
      ("+ left column", .init(body: .leftColumn)),
    ]

    // Page 2 carries education, extras and references, so both pages are shown.
    var items: [(String, UIImage)] = []
    for (label, override) in cases {
      var document = ResumeDocument.example
      document.template = .modern
      document.layout.sectionStyles = override
      let pdf = try XCTUnwrap(PDFDocument(data: ResumePDFRenderer.render(document: document)))
      let page = try XCTUnwrap(pdf.page(at: min(1, pdf.pageCount - 1)))
      items.append((label, page.thumbnail(of: CGSize(width: 238, height: 337), for: .mediaBox)))
    }

    let data = try XCTUnwrap(contactSheet(items: items, columns: 4).pngData())
    let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
    attachment.name = "section-styles.png"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// A résumé saved before section styles existed — or before any other layout
  /// setting did — must still decode. Synthesised decoding throws on a missing
  /// key, and `layout` lives inside the document, so a throw here would take the
  /// whole résumé with it.
  func testLayoutSettingsDecodeFromEveryOlderShape() throws {
    let legacy = """
      {"fontScale": 0.9, "marginPoints": 40}
      """
    let decoded = try JSONDecoder().decode(
      ResumeLayoutSettings.self, from: Data(legacy.utf8))
    XCTAssertEqual(decoded.fontScale, 0.9)
    XCTAssertEqual(decoded.marginPoints, 40)
    XCTAssertEqual(decoded.fontChoice, .template)
    XCTAssertEqual(decoded.paperSize, .a4)
    XCTAssertEqual(decoded.sectionOrder, ResumeContentBlock.allCases)
    XCTAssertEqual(decoded.customHeadings, [:])
    XCTAssertTrue(decoded.sectionStyles.isEmpty)

    XCTAssertTrue(
      try JSONDecoder().decode(ResumeLayoutSettings.self, from: Data("{}".utf8)).sectionStyles
        .isEmpty)

    // The same, one level up: a whole résumé whose layout predates the feature.
    let document = """
      {
        "schemaVersion": 2, "personal": {"fullName": "Avery Sample", "headline": "",
        "phone": "", "email": ""}, "professionalProfile": "", "competencies": [],
        "experience": [], "education": [], "references": [],
        "accent": "orange", "template": "modern",
        "layout": {"fontScale": 1, "marginPoints": 34, "paperSize": "letter"}
      }
      """
    let resume = try JSONDecoder().decode(ResumeDocument.self, from: Data(document.utf8))
    XCTAssertEqual(resume.layout.paperSize, .letter)
    XCTAssertTrue(resume.layout.sectionStyles.isEmpty)
    XCTAssertEqual(resume.personal.fullName, "Avery Sample")
  }

  // MARK: - Attachments

  /// A PDF of `pages` sheets, each carrying findable text.
  private func sampleAttachmentPDF(pages: Int, marker: String) -> Data {
    let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
    return UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
      for page in 1...pages {
        context.beginPage()
        ("\(marker) \(page)" as NSString).draw(
          at: CGPoint(x: 80, y: 300),
          withAttributes: [.font: UIFont.systemFont(ofSize: 28)]
        )
      }
    }
  }

  private func sampleAttachmentImage(side: CGFloat = 900) -> Data {
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
      .image { context in
        UIColor.systemTeal.setFill()
        context.cgContext.fill(CGRect(x: 0, y: 0, width: side, height: side))
      }
    return image.jpegData(compressionQuality: 0.9) ?? Data()
  }

  func testAttachmentsAddTheirOwnPagesToTheExport() throws {
    let base = try XCTUnwrap(PDFDocument(data: ResumePDFRenderer.render(document: .example)))
      .pageCount

    var document = ResumeDocument.example
    document.attachments = [
      try ResumeAttachmentImporter.make(
        title: "Certificate", from: sampleAttachmentPDF(pages: 2, marker: "CERTIFICATE PAGE")),
      try ResumeAttachmentImporter.make(title: "Award photo", from: sampleAttachmentImage()),
    ]

    XCTAssertEqual(document.attachmentPageCount, 3)

    let pdf = try XCTUnwrap(PDFDocument(data: ResumePDFRenderer.render(document: document)))
    XCTAssertEqual(pdf.pageCount, base + 3)

    // The attached PDF is drawn, not rasterised, so its text stays selectable —
    // and the caption is printed above it.
    let appended = (base..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }
      .joined(separator: "\n")
    XCTAssertTrue(appended.contains("CERTIFICATE PAGE 1"), appended)
    XCTAssertTrue(appended.contains("CERTIFICATE PAGE 2"), appended)
    XCTAssertTrue(appended.localizedCaseInsensitiveContains("CERTIFICATE"), appended)
    XCTAssertTrue(appended.localizedCaseInsensitiveContains("AWARD PHOTO"), appended)

    // Multi-page attachments say which sheet you're looking at.
    XCTAssertTrue(appended.contains("1 / 2"), appended)
  }

  func testExcludedAndMeasurementRendersLeaveTheResumeAlone() throws {
    let base = try XCTUnwrap(PDFDocument(data: ResumePDFRenderer.render(document: .example)))
      .pageCount

    var document = ResumeDocument.example
    document.attachments = [
      try ResumeAttachmentImporter.make(
        title: "Certificate", from: sampleAttachmentPDF(pages: 2, marker: "CERT"))
    ]

    // Unchecking an attachment keeps the file but drops it from the export.
    document.attachments[0].isIncluded = false
    XCTAssertEqual(document.attachmentPageCount, 0)
    XCTAssertFalse(document.attachments[0].data.isEmpty)
    XCTAssertEqual(
      try XCTUnwrap(PDFDocument(data: ResumePDFRenderer.render(document: document))).pageCount,
      base)

    // Auto-fit measures the résumé alone: attachments are pages the user chose to
    // add, not overflow to be squeezed out by shrinking the text.
    document.attachments[0].isIncluded = true
    XCTAssertEqual(
      try XCTUnwrap(
        PDFDocument(data: ResumePDFRenderer.render(document: document, includeAttachments: false))
      ).pageCount,
      base)

    // Shrinking can only reduce the résumé's own length, so a reported count
    // above `base` would mean the attachment pages had been counted against it.
    var onePage = document
    onePage.layout.pageTarget = .one
    let fitted = try ResumeAutoFitService.fit(onePage, target: .one)
    XCTAssertLessThanOrEqual(fitted.pageCount, base)
  }

  func testAttachmentsSurviveARoundTripAndOlderDraftsStillLoad() throws {
    var document = ResumeDocument.example
    document.attachments = [
      try ResumeAttachmentImporter.make(title: "Licence", from: sampleAttachmentImage(side: 400))
    ]

    let decoded = try JSONDecoder().decode(
      ResumeDocument.self, from: JSONEncoder().encode(document))
    XCTAssertEqual(decoded.attachments, document.attachments)
    XCTAssertTrue(decoded.attachments[0].isIncluded)
    XCTAssertTrue(decoded.attachments[0].showsTitleOnPage)

    // A draft written before attachments existed has no key, and must still
    // decode rather than being replaced by the example.
    let legacy = """
      {
        "schemaVersion": 2, "personal": {"fullName": "Avery Sample", "headline": "",
        "phone": "", "email": ""}, "professionalProfile": "", "competencies": [],
        "experience": [], "education": [], "references": [],
        "accent": "orange", "template": "modern"
      }
      """
    let migrated = try JSONDecoder().decode(ResumeDocument.self, from: Data(legacy.utf8))
    XCTAssertEqual(migrated.attachments, [])
    XCTAssertEqual(migrated.attachmentPageCount, 0)
    XCTAssertNil(migrated.signature)
  }

  func testSignatureSurvivesARoundTripAndPrintsWithoutAddingAPage() throws {
    let points = [
      PKStrokePoint(
        location: CGPoint(x: 12, y: 54), timeOffset: 0, size: CGSize(width: 3, height: 3),
        opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
      PKStrokePoint(
        location: CGPoint(x: 55, y: 14), timeOffset: 0.1, size: CGSize(width: 3, height: 3),
        opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
      PKStrokePoint(
        location: CGPoint(x: 104, y: 45), timeOffset: 0.2, size: CGSize(width: 3, height: 3),
        opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
    ]
    let drawing = PKDrawing(strokes: [
      PKStroke(
        ink: PKInk(.pen, color: .systemBlue),
        path: PKStrokePath(controlPoints: points, creationDate: Date())
      )
    ])

    let unsignedData = try ResumePDFRenderer.render(document: .example)
    var signed = ResumeDocument.example
    signed.signature = ResumeSignature(
      drawingData: drawing.dataRepresentation(),
      pageIndex: 99, // A stale choice is clamped to the final résumé page.
      placement: .lowerCenter,
      widthPoints: 144
    )

    let decoded = try JSONDecoder().decode(
      ResumeDocument.self, from: JSONEncoder().encode(signed))
    XCTAssertEqual(decoded.signature, signed.signature)

    let unsignedPDF = try XCTUnwrap(PDFDocument(data: unsignedData))
    let signedPDF = try XCTUnwrap(PDFDocument(data: ResumePDFRenderer.render(document: signed)))
    XCTAssertEqual(signedPDF.pageCount, unsignedPDF.pageCount)
    XCTAssertEqual(
      (0..<signedPDF.pageCount).compactMap { signedPDF.page(at: $0)?.string }.joined(),
      (0..<unsignedPDF.pageCount).compactMap { unsignedPDF.page(at: $0)?.string }.joined()
    )

    let last = signedPDF.pageCount - 1
    let size = CGSize(width: 238, height: 337)
    XCTAssertNotEqual(
      signedPDF.page(at: last)?.thumbnail(of: size, for: .mediaBox).pngData(),
      unsignedPDF.page(at: last)?.thumbnail(of: size, for: .mediaBox).pngData()
    )
  }

  func testAttachmentImportCompressesImagesAndRejectsJunk() throws {
    // A camera-roll-sized photo comes down to something a draft can carry.
    let large = sampleAttachmentImage(side: 4000)
    let attachment = try ResumeAttachmentImporter.make(title: "Scan", from: large)
    XCTAssertEqual(attachment.kind, .image)
    XCTAssertEqual(attachment.pageCount, 1)
    XCTAssertLessThanOrEqual(attachment.data.count, ResumeAttachmentLimits.maxPreparedBytes)
    let prepared = try XCTUnwrap(UIImage(data: attachment.data))
    XCTAssertLessThanOrEqual(
      max(prepared.size.width, prepared.size.height), ResumeAttachmentLimits.imageMaxDimension)

    XCTAssertThrowsError(try ResumeAttachmentImporter.make(title: "Junk", from: Data([0x01, 0x02])))
    XCTAssertThrowsError(try ResumeAttachmentImporter.make(title: "Empty", from: Data()))

    // A PDF small enough to keep is kept exactly as it arrived, so its text stays
    // selectable and its vectors stay sharp.
    let pdf = sampleAttachmentPDF(pages: 1, marker: "KEEP")
    let kept = try ResumeAttachmentImporter.make(title: "Doc", from: pdf)
    XCTAssertEqual(kept.kind, .pdf)
    XCTAssertEqual(kept.data, pdf)

    XCTAssertEqual(
      ResumeAttachmentImporter.suggestedTitle(fromFilename: "AWS_solutions-architect.pdf"),
      "AWS solutions architect")
  }

  /// Visual-review artifact: the last page of the résumé followed by the sheets
  /// its attachments produce. Text tests can prove the pages exist and carry the
  /// right words; only this shows whether the artwork is placed well.
  func testAttachmentPageContactSheet() throws {
    let certificate = certificateStylePDF(pages: 2)
    let photo = sampleAttachmentImage(side: 900)

    var document = ResumeDocument.example
    document.attachments = [
      try ResumeAttachmentImporter.make(
        title: "Certified People Analytics Practitioner", from: certificate),
      try ResumeAttachmentImporter.make(title: "Team award, 2024", from: photo),
    ]
    document.attachments[1].showsTitleOnPage = false

    // The same run under a dark-paper template: the attachment sheet must stay
    // white and its footer must stay legible on it.
    var dark = document
    dark.template = .noir
    dark.attachments[1].showsTitleOnPage = true

    func pages(_ source: ResumeDocument, label: String) throws -> [(String, UIImage)] {
      let pdf = try XCTUnwrap(PDFDocument(data: ResumePDFRenderer.render(document: source)))
      let first = max(0, pdf.pageCount - (source.attachmentPageCount + 1))
      return try (first..<pdf.pageCount).map { index in
        let page = try XCTUnwrap(pdf.page(at: index))
        return (
          "\(label) p\(index + 1)",
          page.thumbnail(of: CGSize(width: 238, height: 337), for: .mediaBox)
        )
      }
    }

    let items = try pages(document, label: "Modern") + pages(dark, label: "Noir")
    let sheet = contactSheet(items: items, columns: 4)
    let data = try XCTUnwrap(sheet.pngData())
    let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
    attachment.name = "resume-attachment-pages.png"
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// Something that looks like a real certificate rather than a text marker, so
  /// the contact sheet shows how a landscape document sits on the page.
  private func certificateStylePDF(pages: Int) -> Data {
    let bounds = CGRect(x: 0, y: 0, width: 842, height: 595)
    return UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
      for page in 1...pages {
        context.beginPage()
        UIColor(red: 0.99, green: 0.98, blue: 0.95, alpha: 1).setFill()
        context.cgContext.fill(bounds)
        UIColor(red: 0.55, green: 0.42, blue: 0.16, alpha: 1).setStroke()
        context.cgContext.setLineWidth(6)
        context.cgContext.stroke(bounds.insetBy(dx: 30, dy: 30))

        let title = NSMutableParagraphStyle()
        title.alignment = .center
        ("CERTIFICATE OF COMPLETION" as NSString).draw(
          with: CGRect(x: 60, y: 150, width: 722, height: 60),
          options: [.usesLineFragmentOrigin],
          attributes: [
            .font: UIFont.systemFont(ofSize: 34, weight: .bold),
            .paragraphStyle: title,
          ],
          context: nil
        )
        ("Avery Sample — page \(page) of \(pages)" as NSString).draw(
          with: CGRect(x: 60, y: 260, width: 722, height: 40),
          options: [.usesLineFragmentOrigin],
          attributes: [.font: UIFont.systemFont(ofSize: 22), .paragraphStyle: title],
          context: nil
        )
      }
    }
  }

  func testAttachmentLimitsGuardTheDraftFileSize() throws {
    var document = ResumeDocument.blank
    document.attachments = (0..<ResumeAttachmentLimits.maxAttachments).map { index in
      ResumeAttachment(title: "File \(index)", kind: .image, data: Data([0xFF]), pageCount: 1)
    }
    XCTAssertFalse(document.canAcceptAttachment(ofSize: 1))

    document.attachments = [
      ResumeAttachment(
        title: "Huge", kind: .pdf,
        data: Data(count: ResumeAttachmentLimits.maxTotalBytes), pageCount: 1)
    ]
    XCTAssertFalse(document.canAcceptAttachment(ofSize: 1))
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

  func testPhotoImportLimitsMatchSubscriptionTiers() {
    XCTAssertEqual(ResumeStudioPlan.free.photoImportImageLimit, 2)
    XCTAssertEqual(ResumeStudioPlan.go.photoImportImageLimit, 5)
    XCTAssertEqual(ResumeStudioPlan.pro.photoImportImageLimit, 5)
    XCTAssertEqual(ResumeStudioPlan.free.dailyAIImportLimit, 1)
    XCTAssertEqual(ResumeStudioPlan.go.dailyAIImportLimit, 1)
    XCTAssertEqual(ResumeStudioPlan.pro.dailyAIImportLimit, 2)
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

  // MARK: - Interview Live Activity eligibility

  /// The count-down Live Activity surfaces exactly one interview: the soonest
  /// whose window is open — starting 24h before, lingering 30m past its end.
  func testInterviewLiveActivitySurfacesTheSoonestOpenInterview() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    func interview(inHours hours: Double, durationMinutes: Int = 60, role: String) -> InterviewEvent {
      InterviewEvent(
        applicationID: nil, role: role, company: "Acme",
        scheduledAt: now.addingTimeInterval(hours * 3600), durationMinutes: durationMinutes,
        format: .video, locationOrLink: "", interviewerNames: "", reminderEnabled: true,
        preparationNotes: "", outcome: .pending, selfRating: 0,
        whatWentWell: "", needsImprovement: "", followUpNotes: "")
    }

    // Nothing to show when there are no interviews.
    XCTAssertNil(InterviewLiveActivityController.eligibleInterview(from: [], now: now))

    // Beyond the 24h lead window it is not surfaced yet.
    XCTAssertNil(InterviewLiveActivityController.eligibleInterview(
      from: [interview(inHours: 30, role: "Too far")], now: now))

    // Among open interviews, the soonest wins regardless of array order.
    XCTAssertEqual(
      InterviewLiveActivityController.eligibleInterview(
        from: [interview(inHours: 10, role: "Later"), interview(inHours: 2, role: "Soon")],
        now: now)?.role,
      "Soon")

    // An interview currently underway is still surfaced.
    XCTAssertEqual(
      InterviewLiveActivityController.eligibleInterview(
        from: [interview(inHours: -0.25, role: "Underway")], now: now)?.role,
      "Underway")

    // Ended 15m ago (inside the 30m grace) → still surfaced.
    XCTAssertEqual(
      InterviewLiveActivityController.eligibleInterview(
        from: [interview(inHours: -1.25, role: "Just ended")], now: now)?.role,
      "Just ended")

    // Ended 60m ago (past the 30m grace) → gone.
    XCTAssertNil(InterviewLiveActivityController.eligibleInterview(
      from: [interview(inHours: -2, role: "Long gone")], now: now))
  }

  // MARK: - Personal CV page handles

  /// The client-side handle rules must mirror the backend's `validHandle`, so
  /// the editor never fires a request the server will only reject.
  func testProfileHandleValidationMatchesBackendRules() {
    XCTAssertTrue(PersonalProfile.isValidHandle("halalisani"))
    XCTAssertTrue(PersonalProfile.isValidHandle("jane-doe"))
    XCTAssertTrue(PersonalProfile.isValidHandle("a1b"))
    XCTAssertFalse(PersonalProfile.isValidHandle("ab")) // too short
    XCTAssertFalse(PersonalProfile.isValidHandle(String(repeating: "a", count: 31))) // too long
    XCTAssertFalse(PersonalProfile.isValidHandle("-jane")) // leading hyphen
    XCTAssertFalse(PersonalProfile.isValidHandle("jane-")) // trailing hyphen
    XCTAssertFalse(PersonalProfile.isValidHandle("ja--ne")) // doubled hyphen
    XCTAssertFalse(PersonalProfile.isValidHandle("Jane")) // uppercase not folded
    XCTAssertFalse(PersonalProfile.isValidHandle("jane.doe")) // illegal character
  }

  /// Suggested and typed handles are always backend-legal: separators collapse
  /// to single hyphens, illegal characters drop, and trailing hyphens are trimmed.
  func testProfileHandleSuggestionAndNormalization() {
    XCTAssertEqual(PersonalProfile.suggestedHandle(from: "Jane Doe"), "jane-doe")
    XCTAssertEqual(PersonalProfile.suggestedHandle(from: "  Thabo   M. Nkosi "), "thabo-m-nkosi")
    XCTAssertEqual(PersonalProfile.suggestedHandle(from: "Jane_Doe 99!"), "jane-doe-99")
    XCTAssertTrue(PersonalProfile.isValidHandle(PersonalProfile.suggestedHandle(from: "Jane Doe")))

    XCTAssertEqual(PersonalProfileView.normalizeHandle("Jane   Doe"), "jane-doe")
    XCTAssertEqual(PersonalProfileView.normalizeHandle("a_b.c"), "a-b-c")
    XCTAssertEqual(PersonalProfileView.normalizeHandle("HELLO"), "hello")
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

  func testNegotiationRehearsalSurvivesReloadAndLegacyArchivesStillDecode() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("negotiation-practice-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }

    var session = NegotiationPracticeSession(
      company: "Example Labs", role: "Director", persona: .directHiringManager,
      difficulty: .firm, goal: "Add a signing bonus", offerSummary: "Offer: ZAR 1000000 base",
      messages: [
        NegotiationSessionMessage(kind: .counterpart, content: "Where did you land on the offer?"),
        NegotiationSessionMessage(kind: .user, content: "I would like to discuss the base."),
        NegotiationSessionMessage(kind: .nudge, content: "Anchor with a number, not a feeling."),
      ])
    let store = CareerIntelligenceStore(fileURL: url)
    store.upsert(session)
    XCTAssertFalse(store.negotiationSessions.first?.isCompleted ?? true)

    session.debrief = NegotiationDebrief(
      outcomeSummary: "Secured a conversation about base.",
      strengths: ["Stayed calm"], improvements: ["State a number"],
      strongerLines: ["Based on my verified delivery record, I am looking for 1.1M."],
      tacticsObserved: ["Calibrated question"], missedOpportunities: ["Comfortable silence"])
    store.upsert(session)

    let reloaded = CareerIntelligenceStore(fileURL: url)
    XCTAssertEqual(reloaded.negotiationSessions.count, 1)
    XCTAssertEqual(reloaded.negotiationSessions.first?.messages.count, 3)
    XCTAssertEqual(reloaded.negotiationSessions.first?.messages.map(\.kind), [.counterpart, .user, .nudge])
    XCTAssertEqual(reloaded.negotiationSessions.first?.persona, .directHiringManager)
    XCTAssertEqual(reloaded.negotiationSessions.first?.debrief?.tacticsObserved, ["Calibrated question"])
    XCTAssertTrue(reloaded.negotiationSessions.first?.isCompleted ?? false)

    reloaded.deleteNegotiationSession(session.id)
    XCTAssertTrue(reloaded.negotiationSessions.isEmpty)
    XCTAssertTrue(CareerIntelligenceStore(fileURL: url).negotiationSessions.isEmpty)

    // An archive written before rehearsals existed must still load cleanly.
    let legacy = """
      {"evidence":[],"contacts":[],"networkingDrafts":[],"offers":[],
       "reviewRequests":[],"voiceAttempts":[],"preferredMarket":"southAfrica"}
      """
    try Data(legacy.utf8).write(to: url)
    XCTAssertTrue(CareerIntelligenceStore(fileURL: url).negotiationSessions.isEmpty)
  }

  /// Renders the rehearsal screen's setup phase — seeded offer preselected,
  /// history showing both a reviewed and a resumable session — and attaches the
  /// PNG for visual review, the same way the template render tests do.
  @MainActor func testNegotiationRehearsalScreenRendersItsSetupAndHistory() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let careerStore = CareerIntelligenceStore(fileURL: root.appendingPathComponent("career.json"))
    let offer = JobOffer(
      company: "Aurora Analytics", role: "Senior Data Engineer", currencyCode: "ZAR",
      baseSalary: 980_000, bonus: 98_000, equitySummary: "", benefits: "Medical aid, 25 leave days",
      workStyle: "Hybrid", commuteMinutes: 40, growthRating: 4, cultureRating: 4,
      notes: "Verbal offer, written version promised Friday", deadline: nil,
      negotiationDraft: "", signingBonus: 40_000, leaveDays: 25)
    careerStore.upsert(offer)
    careerStore.upsert(NegotiationPracticeSession(
      offerID: offer.id, company: "Aurora Analytics", role: "Senior Data Engineer",
      persona: .directHiringManager, difficulty: .firm, goal: "Add a signing bonus",
      offerSummary: offer.negotiationSummary,
      messages: [NegotiationSessionMessage(kind: .counterpart, content: "Where did you land?")],
      debrief: NegotiationDebrief(
        outcomeSummary: "Secured a written follow-up on the signing bonus.",
        strengths: ["Anchored early"], improvements: ["Hold the silence"],
        strongerLines: [], tacticsObserved: ["Anchoring"], missedOpportunities: [])))
    careerStore.upsert(NegotiationPracticeSession(
      company: "Northwind Retail", role: "Platform Lead", persona: .warmHRPartner,
      difficulty: .realistic, goal: "Move the start date out by a month",
      offerSummary: "Offer: ZAR 700000 base",
      messages: [NegotiationSessionMessage(kind: .counterpart, content: "Thanks for making time today.")]))

    let screen = NavigationStack {
      NegotiationPracticeView(offerID: offer.id)
    }
    .environmentObject(ResumeStore(
      fileURL: root.appendingPathComponent("resume.json"), initialDocument: .example))
    .environmentObject(careerStore)
    .environmentObject(ApplicationStore(fileURL: root.appendingPathComponent("apps.json")))

    // ImageRenderer cannot draw NavigationStack or ScrollView content, and a
    // detached UIWindow never commits — the view must live in a window attached
    // to the host app's real scene before drawHierarchy sees anything.
    let scene = try XCTUnwrap(
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
    window.rootViewController = UIHostingController(rootView: screen)
    window.isHidden = false
    window.rootViewController?.view.layoutIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.7))

    func snapshot(_ name: String) {
      let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
      }
      let attachment = XCTAttachment(image: image)
      attachment.name = name
      attachment.lifetime = .keepAlways
      add(attachment)
    }
    snapshot("negotiation-rehearsal-setup")

    func scrollView(in view: UIView) -> UIScrollView? {
      if let scroll = view as? UIScrollView { return scroll }
      for child in view.subviews { if let found = scrollView(in: child) { return found } }
      return nil
    }
    if let scroll = scrollView(in: window) {
      scroll.setContentOffset(
        CGPoint(x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height)), animated: false)
      RunLoop.main.run(until: Date().addingTimeInterval(0.4))
      snapshot("negotiation-rehearsal-history")
    }
    window.isHidden = true
  }

  func testNegotiationTurnDecodesBothExchangeAndDebriefShapes() throws {
    let exchange = """
      {"reply":"Our band tops out below that, but tell me more.","coachingNudge":"Ask what the band is.",
       "conversationComplete":false,"outcomeSummary":"","strengths":[],"improvements":[],
       "strongerLines":[],"tacticsObserved":[],"missedOpportunities":[]}
      """
    let exchangeTurn = try JSONDecoder().decode(AINegotiationTurn.self, from: Data(exchange.utf8))
    XCTAssertEqual(exchangeTurn.coachingNudge, "Ask what the band is.")
    XCTAssertFalse(exchangeTurn.conversationComplete)

    let debrief = """
      {"reply":"","coachingNudge":"","conversationComplete":true,
       "outcomeSummary":"You secured a review of the base.",
       "strengths":["Used evidence"],"improvements":["Slow down"],
       "strongerLines":["I need 1.1M to say yes today."],
       "tacticsObserved":["Anchoring"],"missedOpportunities":["Trading not conceding"]}
      """
    let debriefTurn = try JSONDecoder().decode(AINegotiationTurn.self, from: Data(debrief.utf8))
    XCTAssertTrue(debriefTurn.conversationComplete)
    XCTAssertEqual(debriefTurn.tacticsObserved, ["Anchoring"])
    XCTAssertEqual(debriefTurn.strongerLines.count, 1)
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

  func testOutcomeReviewPersistsExactResumeAndReplacesTheSameStageReview() throws {
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("outcome-store-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: fileURL) }
    let resumeID = UUID()
    let application = JobApplication(
      company: "Evergreen Labs", role: "People Lead", jobDescription: "",
      sourceURL: "https://jobs.example/outcome", status: .rejected, notes: "",
      baseResumeID: resumeID, tailoredResumeID: nil, matchAnalysis: nil,
      interviewPlan: nil
    )
    let store = ApplicationStore(fileURL: fileURL)
    store.add(application)
    store.saveOutcomeReview(ApplicationOutcomeReview(
      stage: .rejected,
      reason: .evidenceTooWeak,
      feedbackSource: .recruiter,
      feedback: "Show clearer results.",
      whatWorked: "Role alignment",
      nextChange: "Strengthen one achievement",
      followUpAt: nil,
      resumeID: resumeID,
      packetID: nil
    ), for: application.id)

    let first = try XCTUnwrap(ApplicationStore(fileURL: fileURL).applications.first)
    XCTAssertEqual(first.outcomeReviewList.count, 1)
    XCTAssertEqual(first.currentOutcomeReview?.resumeID, resumeID)
    XCTAssertEqual(first.currentOutcomeReview?.feedback, "Show clearer results.")
    XCTAssertFalse(first.needsCurrentOutcomeReview)

    store.saveOutcomeReview(ApplicationOutcomeReview(
      stage: .rejected,
      reason: .skillsGap,
      feedbackSource: .interviewer,
      feedback: "A specific skill was missing.",
      whatWorked: "",
      nextChange: "Surface supported skills",
      followUpAt: nil,
      resumeID: resumeID,
      packetID: nil
    ), for: application.id)
    let replaced = try XCTUnwrap(ApplicationStore(fileURL: fileURL).applications.first)
    XCTAssertEqual(replaced.outcomeReviewList.count, 1)
    XCTAssertEqual(replaced.currentOutcomeReview?.reason, .skillsGap)
  }

  func testOutcomeLearningPrioritizesMissingDebriefThenRecordedEvidenceSignal() throws {
    let resumeID = UUID()
    var application = JobApplication(
      company: "Example", role: "Operations Lead", jobDescription: "", sourceURL: "",
      status: .rejected, notes: "", baseResumeID: resumeID, tailoredResumeID: nil,
      matchAnalysis: nil, interviewPlan: nil
    )
    var summary = OutcomeLearningService.summarize(
      applications: [application],
      resumes: [ResumeDraft(id: resumeID, title: "Operations", document: .example)]
    )
    XCTAssertEqual(summary.recommendation.focus, .collectOutcome)
    XCTAssertEqual(summary.pendingApplicationIDs, [application.id])

    application.outcomeReviews = [ApplicationOutcomeReview(
      stage: .rejected,
      reason: .evidenceTooWeak,
      feedbackSource: .recruiter,
      feedback: "",
      whatWorked: "",
      nextChange: "",
      followUpAt: nil,
      resumeID: resumeID,
      packetID: nil
    )]
    summary = OutcomeLearningService.summarize(
      applications: [application],
      resumes: [ResumeDraft(id: resumeID, title: "Operations", document: .example)]
    )
    XCTAssertEqual(summary.recommendation.focus, .experienceEvidence)
    XCTAssertEqual(summary.recommendation.resumeID, resumeID)
    XCTAssertEqual(summary.reviewedCount, 1)
    XCTAssertTrue(summary.recommendation.detail.localizedCaseInsensitiveContains("evidence"))
  }

  func testOutcomeLearningQualityGateRejectsInventedNumbers() throws {
    let document = ResumeDocument.example
    let entry = try XCTUnwrap(document.experience.first)
    let original = try XCTUnwrap(entry.highlights.first)
    let result = try OnDeviceAIQualityGate.outcomeLearningDraft(
      AIOutcomeLearningDraft(
        title: "Strengthen evidence",
        rationale: "Make an existing result easier to scan.",
        proposedProfile: "",
        proposedCompetencies: [],
        experienceEntryID: entry.id.uuidString,
        originalBullet: original,
        proposedBullet: "Improved this result by 99% while preserving every responsibility.",
        coachingSteps: ["Add a metric only when it can be verified."],
        claimsRequiringConfirmation: []
      ),
      for: document
    )
    XCTAssertFalse(result.hasExperienceChange)
    XCTAssertEqual(result.coachingSteps, ["Add a metric only when it can be verified."])
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

  func testRecruiterRepairPreparesOnlySupportedChangesAndDropsBlankSlots() {
    var buried = ResumeDocument.example
    buried.experience[0].highlights[2] = "Lifted engagement scores by 12 points."
    let buriedReport = RecruiterScanService.analyze(document: buried)
    let reordered = RecruiterScanService.makeRepairDraft(
      document: buried, report: buriedReport)

    XCTAssertEqual(
      reordered.experience[0].highlights.first,
      "Lifted engagement scores by 12 points.")
    XCTAssertEqual(reordered.experience[0].highlights.count, buried.experience[0].highlights.count)
    XCTAssertEqual(
      RecruiterScanService.finalizeRepairDraft(reordered).experience[0].highlights.first,
      "Lifted engagement scores by 12 points.")

    let blankReport = RecruiterScanService.analyze(document: .blank)
    var repair = RecruiterScanService.makeRepairDraft(document: .blank, report: blankReport)
    XCTAssertEqual(repair.experience.count, 2)
    XCTAssertEqual(repair.education.count, 1)
    XCTAssertEqual(RecruiterScanService.finalizeRepairDraft(repair), .blank)

    repair.experience[0].role = "Operations Analyst"
    repair.education[0].qualification = "Bachelor of Commerce"
    let finalized = RecruiterScanService.finalizeRepairDraft(repair)
    XCTAssertEqual(finalized.experience.count, 1)
    XCTAssertEqual(finalized.experience[0].role, "Operations Analyst")
    XCTAssertEqual(finalized.education.count, 1)
    XCTAssertEqual(finalized.education[0].qualification, "Bachelor of Commerce")
  }

  func testRecruiterRepairImprovesMissingHeadlineAndProfileWithoutNetworkAI() {
    var document = ResumeDocument.example
    document.personal.headline = ""
    document.professionalProfile = ""
    let originalBullet = document.experience[0].highlights[0]
    let before = RecruiterScanService.analyze(document: document)

    let repair = RecruiterScanService.makeRepairDraft(document: document, report: before)
    let after = RecruiterScanService.analyze(document: repair)

    XCTAssertTrue(repair.personal.headline.contains(document.experience[0].role))
    XCTAssertTrue(repair.professionalProfile.contains(document.experience[0].role))
    XCTAssertTrue(repair.professionalProfile.contains(document.experience[0].company))
    XCTAssertLessThanOrEqual(
      repair.professionalProfile.split(whereSeparator: \.isWhitespace).count, 52)
    XCTAssertFalse(repair.professionalProfile.contains(document.personal.email))
    XCTAssertFalse(repair.professionalProfile.contains(document.personal.phone))
    XCTAssertEqual(repair.experience[0].highlights[0], originalBullet)
    XCTAssertEqual(before.score, 82)
    XCTAssertEqual(after.score, 92)
    XCTAssertEqual(after.findings.first { $0.id == "identity" }?.severity, .pass)
    XCTAssertEqual(after.findings.first { $0.id == "profile-skim" }?.severity, .pass)
  }

  func testRecruiterRepairBuildsOnlyUserSuppliedMetricIntoBullet() {
    let original = "Built mobile monitoring features."
    XCTAssertNil(RecruiterScanService.addingVerifiedMetric(
      "", outcome: "fewer false alarms", to: original))
    XCTAssertNil(RecruiterScanService.addingVerifiedMetric(
      "30%", outcome: "", to: original))

    let improved = RecruiterScanService.addingVerifiedMetric(
      "30%",
      outcome: "fewer false alarms",
      context: "across 3 releases",
      to: original)
    XCTAssertEqual(
      improved,
      "Built mobile monitoring features, delivering 30% fewer false alarms across 3 releases.")
    XCTAssertTrue(RecruiterScanService.isQuantified(improved ?? ""))
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
      remoteID: String(repeating: "a", count: 64),
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
    XCTAssertEqual(link.totalDownloads, 1)
    XCTAssertEqual(link.unseenOpens, 3)

    link.activityByDay = [
      SmartLinkDailyActivity(day: "2026-07-17", opens: 3, seconds: 120, downloads: 1)
    ]
    XCTAssertEqual(link.dailyActivity.first?.opens, 3)
    XCTAssertNotNil(link.dailyActivity.first?.date)

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
      remoteID: String(repeating: "a", count: 64),
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
    link.activityByDay = [
      SmartLinkDailyActivity(day: "2026-07-17", opens: 1, seconds: 45, downloads: 0)
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
    XCTAssertEqual(reloaded.links.first?.remoteID, String(repeating: "a", count: 64))
    XCTAssertEqual(reloaded.links.first?.acknowledgedOpens, 1)
    XCTAssertEqual(reloaded.links.first?.dailyActivity.first?.seconds, 45)
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

  // MARK: - Application calibration

  private func makeCalibrationApplication(
    status: JobApplicationStatus,
    matched: Int = 0,
    missing: Int = 0,
    sourceURL: String = "",
    updatedDaysAgo: Int = 0,
    reviewStages: [JobApplicationStatus] = [],
    now: Date = Date()
  ) -> JobApplication {
    let resumeID = UUID()
    let analysis: AIJobMatchAnalysis? = (matched + missing) > 0
      ? AIJobMatchAnalysis(
        summary: "",
        matchedKeywords: (0..<matched).map { "matched-\($0)" },
        missingKeywords: (0..<missing).map { "missing-\($0)" },
        recommendations: [],
        claimsRequiringConfirmation: [])
      : nil
    var application = JobApplication(
      company: "Example", role: "Designer", jobDescription: "Role", sourceURL: sourceURL,
      status: status, notes: "", baseResumeID: resumeID,
      tailoredResumeID: nil, matchAnalysis: analysis, interviewPlan: nil)
    application.updatedAt = now.addingTimeInterval(-Double(updatedDaysAgo) * 86_400)
    application.outcomeReviews = reviewStages.map { stage in
      ApplicationOutcomeReview(
        stage: stage, reason: .strongRoleFit, feedbackSource: .recruiter,
        feedback: "", whatWorked: "", nextChange: "", followUpAt: nil,
        resumeID: resumeID, packetID: nil)
    }
    return application
  }

  func testCalibrationNamesTheReachGapWhenStretchesDominateAndDoNotLand() {
    let now = Date()
    // Six stretch applications that went nowhere, three well-matched ones where
    // a single interview happened: the comparison the whole feature rests on.
    var applications = (0..<6).map { _ in
      makeCalibrationApplication(status: .rejected, matched: 1, missing: 3, now: now)
    }
    applications.append(makeCalibrationApplication(
      status: .interview, matched: 3, missing: 1, now: now))
    applications += (0..<2).map { _ in
      makeCalibrationApplication(status: .rejected, matched: 3, missing: 1, now: now)
    }

    let report = ApplicationCalibrationService.calibrate(applications: applications, now: now)
    XCTAssertEqual(report.primary?.kind, .reachGap)
    XCTAssertEqual(report.settledCount, 9)
    XCTAssertEqual(report.progressedCount, 1)
    XCTAssertEqual(report.analyzedCount, 9)
    // Nine analysed applications sits in the middle confidence band.
    XCTAssertEqual(report.primary?.confidence, .emerging)
    XCTAssertEqual(report.progressionRateText, "11%")
  }

  func testCalibrationCallsOutADroughtRatherThanEncouragingMoreVolume() {
    let now = Date()
    let applications = (0..<ApplicationCalibrationService.droughtMinimumSettled).map { _ in
      makeCalibrationApplication(status: .applied, updatedDaysAgo: 30, now: now)
    }
    let report = ApplicationCalibrationService.calibrate(applications: applications, now: now)
    XCTAssertEqual(report.primary?.kind, .responseDrought)
    XCTAssertEqual(report.progressedCount, 0)

    // One short of the floor, silence is still ordinary noise.
    let quieter = Array(applications.dropLast())
    let quieterReport = ApplicationCalibrationService.calibrate(applications: quieter, now: now)
    XCTAssertNotEqual(quieterReport.primary?.kind, .responseDrought)
  }

  func testCalibrationCountsAnInterviewThatLaterBecameARejection() {
    let application = makeCalibrationApplication(
      status: .rejected, reviewStages: [.interview])
    XCTAssertTrue(ApplicationCalibrationService.progressed(application))

    let neverProgressed = makeCalibrationApplication(status: .rejected)
    XCTAssertFalse(ApplicationCalibrationService.progressed(neverProgressed))
  }

  func testCalibrationOnlyCountsApplicationsThatHaveSettled() {
    let now = Date()
    XCTAssertFalse(ApplicationCalibrationService.isSettled(
      makeCalibrationApplication(status: .saved, updatedDaysAgo: 400, now: now), now: now))
    XCTAssertFalse(ApplicationCalibrationService.isSettled(
      makeCalibrationApplication(status: .applied, updatedDaysAgo: 5, now: now), now: now))
    XCTAssertTrue(ApplicationCalibrationService.isSettled(
      makeCalibrationApplication(
        status: .applied,
        updatedDaysAgo: ApplicationCalibrationService.settlingDays,
        now: now),
      now: now))
    XCTAssertTrue(ApplicationCalibrationService.isSettled(
      makeCalibrationApplication(status: .rejected, now: now), now: now))
  }

  func testCalibrationConfidenceAndCoverageThresholdsStayPinned() {
    XCTAssertEqual(ApplicationCalibrationService.confidence(for: 5), .provisional)
    XCTAssertEqual(ApplicationCalibrationService.confidence(for: 6), .emerging)
    XCTAssertEqual(ApplicationCalibrationService.confidence(for: 12), .consistent)

    // A match analysis with too few keywords cannot produce an honest ratio.
    XCTAssertNil(ApplicationCalibrationService.matchCoverage(
      makeCalibrationApplication(status: .rejected, matched: 1, missing: 2)))
    XCTAssertEqual(
      ApplicationCalibrationService.matchCoverage(
        makeCalibrationApplication(status: .rejected, matched: 3, missing: 1)) ?? 0,
      0.75, accuracy: 0.0001)
  }

  func testCalibrationSaysSoWhenThereIsNothingToCompare() {
    let report = ApplicationCalibrationService.calibrate(applications: [])
    XCTAssertEqual(report.primary?.kind, .notEnoughData)
    XCTAssertEqual(report.settledCount, 0)
    XCTAssertNil(report.progressionRate)
  }

  func testCalibrationFlagsASingleUnproductiveSource() {
    let now = Date()
    let applications = (0..<6).map { _ in
      makeCalibrationApplication(
        status: .rejected, sourceURL: "https://www.example-board.com/jobs/1", now: now)
    }
    let report = ApplicationCalibrationService.calibrate(applications: applications, now: now)
    let concentration = report.signals.first { $0.kind == .sourceConcentration }
    XCTAssertNotNil(concentration)
    // The host is stated plainly, without the www prefix.
    XCTAssertTrue(concentration?.evidence.contains("example-board.com") ?? false)
  }

  // MARK: - Opportunity ranking

  /// Written in the example résumé's own vocabulary, so a high overlap is
  /// expected rather than coincidental.
  private var wellMatchedAdvert: String {
    """
    People Operations Manager responsible for employee experience, manager coaching, \
    workforce planning, people analytics, talent acquisition, policy and process design, \
    change communication. You will build inclusive employee programmes, improve manager \
    support, and turn workforce insights into practical action, creating scalable \
    processes that strengthen culture while supporting business growth across the \
    operations function.
    """
  }

  /// Deliberately from another profession entirely.
  private var unrelatedAdvert: String {
    """
    Senior Kubernetes platform engineer maintaining distributed microservice clusters, \
    writing Golang controllers, tuning Postgres replication, managing Terraform modules, \
    debugging kernel networking stacks, operating service mesh ingress gateways, \
    optimising container scheduling latency across regional availability zones, and \
    automating continuous delivery pipelines for infrastructure teams every single day.
    """
  }

  private func makeOpportunity(
    advert: String, status: JobApplicationStatus = .saved, role: String = "Designer"
  ) -> JobApplication {
    JobApplication(
      company: "Example", role: role, jobDescription: advert, sourceURL: "",
      status: status, notes: "", baseResumeID: UUID(),
      tailoredResumeID: nil, matchAnalysis: nil, interviewPlan: nil)
  }

  func testOpportunityBandsStayAnchoredToTheATSPassLine() {
    let pass = ATSReadinessService.jobLanguagePassThreshold
    // A résumé that passes the ATS keyword check for an advert can never be
    // ranked a long shot for that same advert.
    XCTAssertNotEqual(OpportunityRankingService.band(for: pass), .longShot)
    XCTAssertLessThanOrEqual(OpportunityRankingService.possibleCoverage, pass)
    XCTAssertGreaterThanOrEqual(OpportunityRankingService.strongCoverage, pass)
    XCTAssertEqual(OpportunityRankingService.band(for: 0), .longShot)
    XCTAssertEqual(
      OpportunityRankingService.band(for: OpportunityRankingService.strongCoverage), .strong)
  }

  func testOpportunityRankingScoresOnlySavedOpportunities() {
    let applications = [
      makeOpportunity(advert: wellMatchedAdvert, status: .saved),
      makeOpportunity(advert: wellMatchedAdvert, status: .applied),
      makeOpportunity(advert: wellMatchedAdvert, status: .rejected),
    ]
    let ranking = OpportunityRankingService.rank(
      applications: applications, document: .example)
    XCTAssertEqual(ranking.scores.count, 1)
  }

  func testOpportunityRankingRefusesToScoreAThinAdvert() {
    let ranking = OpportunityRankingService.rank(
      applications: [makeOpportunity(advert: "People Operations Manager. Apply within.")],
      document: .example)
    XCTAssertEqual(ranking.scores.first?.band, .unscored)
    XCTAssertNil(ranking.scores.first?.coverage)
    XCTAssertEqual(ranking.unscoredCount, 1)
  }

  func testOpportunityRankingPutsTheWorkThatCanLandFirst() {
    let applications = [
      makeOpportunity(advert: unrelatedAdvert, role: "Platform Engineer"),
      makeOpportunity(advert: wellMatchedAdvert, role: "People Operations Manager"),
    ]
    let ranking = OpportunityRankingService.rank(
      applications: applications, document: .example)

    XCTAssertEqual(ranking.scores.first?.band, .strong)
    XCTAssertEqual(ranking.scores.first?.role, "People Operations Manager")
    XCTAssertEqual(ranking.scores.last?.band, .longShot)
    XCTAssertEqual(ranking.strongCount, 1)
    XCTAssertEqual(ranking.longShotCount, 1)
    XCTAssertTrue(ranking.summary.contains("1 ready to send"))
    // The unrelated advert should surface its own language as missing.
    XCTAssertFalse(ranking.scores.last?.topMissing.isEmpty ?? true)
  }

  func testOpportunityRankingSaysSoWhenNothingMatches() {
    let applications = (0..<3).map { _ in makeOpportunity(advert: unrelatedAdvert) }
    let ranking = OpportunityRankingService.rank(
      applications: applications, document: .example)
    XCTAssertEqual(ranking.strongCount, 0)
    XCTAssertTrue(ranking.summary.contains("Nothing here matches"))
    XCTAssertTrue(ranking.summary.contains("3 cover letters"))
  }

  // MARK: - Benchmarks

  func testBenchmarkRoleFamilyPrefersTheMoreSpecificTitle() {
    // "Product manager" and "project manager" both contain "manager" and must
    // not collapse into the same family.
    XCTAssertEqual(BenchmarkAnalysis.roleFamily(for: "Product Manager"), .product)
    XCTAssertEqual(BenchmarkAnalysis.roleFamily(for: "Project Manager"), .operationsLogistics)
    XCTAssertEqual(BenchmarkAnalysis.roleFamily(for: "Senior Data Analyst"), .dataAnalytics)
    XCTAssertEqual(BenchmarkAnalysis.roleFamily(for: "iOS Engineer"), .engineering)
    XCTAssertEqual(BenchmarkAnalysis.roleFamily(for: "People Operations Manager"), .peopleOperations)
    XCTAssertEqual(BenchmarkAnalysis.roleFamily(for: "Underwater Basket Weaver"), .other)
  }

  func testBenchmarkSeniorityReadsTheTitle() {
    XCTAssertEqual(BenchmarkAnalysis.seniority(for: "Head of Design"), .lead)
    XCTAssertEqual(BenchmarkAnalysis.seniority(for: "Senior Accountant"), .senior)
    XCTAssertEqual(BenchmarkAnalysis.seniority(for: "Graduate Engineer"), .entry)
    XCTAssertEqual(BenchmarkAnalysis.seniority(for: "Bookkeeper"), .mid)
  }

  func testBenchmarkCohortComesFromTheResumeTheUserAlreadyWrote() {
    let cohort = BenchmarkAnalysis.cohort(document: .example, market: .southAfrica)
    // The example résumé's headline is a People Operations Manager.
    XCTAssertEqual(cohort.roleFamily, .peopleOperations)
    XCTAssertEqual(cohort.market, .southAfrica)
    // The cohort is three enum cases, so no free text can reach the wire.
    let encoded = try? JSONEncoder().encode(cohort)
    let json = encoded.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    XCTAssertFalse(json.contains("Avery"))
    XCTAssertFalse(json.contains("Northstar"))
  }

  func testBenchmarkContributionCarriesCountsAndNothingElse() {
    let now = Date()
    var applications = (0..<4).map { _ in
      makeCalibrationApplication(status: .rejected, now: now)
    }
    applications.append(makeCalibrationApplication(status: .interview, now: now))

    let cohort = BenchmarkAnalysis.cohort(document: .example, market: .unitedKingdom)
    let contribution = BenchmarkAnalysis.contribution(
      cohort: cohort, applications: applications, now: now)
    XCTAssertEqual(contribution?.settled, 5)
    XCTAssertEqual(contribution?.progressed, 1)

    // A history with nothing settled has nothing to contribute.
    XCTAssertNil(BenchmarkAnalysis.contribution(
      cohort: cohort,
      applications: [makeCalibrationApplication(status: .saved, now: now)],
      now: now))
  }

  func testBenchmarkComparisonStaysSilentUntilBothSidesAreBigEnough() {
    let now = Date()
    let cohort = BenchmarkAnalysis.cohort(document: .example, market: .southAfrica)
    let released = BenchmarkSnapshot(
      released: true, contributors: 14, settled: 210,
      progressionPercent: 20, medianDaysToProgress: 11)

    // An unreleased cohort never produces a verdict, however much local history.
    let manyLocal = (0..<20).map { _ in makeCalibrationApplication(status: .rejected, now: now) }
    let unreleased = BenchmarkAnalysis.compare(
      cohort: cohort, snapshot: .unreleased, applications: manyLocal, now: now)
    XCTAssertEqual(unreleased.verdict, .unknown)

    // A released cohort with too little local history is reported, not compared.
    let thinLocal = (0..<2).map { _ in makeCalibrationApplication(status: .rejected, now: now) }
    let notComparable = BenchmarkAnalysis.compare(
      cohort: cohort, snapshot: released, applications: thinLocal, now: now)
    XCTAssertEqual(notComparable.verdict, .unknown)
    XCTAssertTrue(notComparable.headline.contains("20%"))
  }

  func testBenchmarkComparisonNamesTheGapInBothDirections() {
    let now = Date()
    let cohort = BenchmarkAnalysis.cohort(document: .example, market: .southAfrica)
    let released = BenchmarkSnapshot(
      released: true, contributors: 14, settled: 210,
      progressionPercent: 20, medianDaysToProgress: 11)

    // Ten settled, none progressed: 0% against a cohort's 20%.
    let behind = (0..<10).map { _ in makeCalibrationApplication(status: .rejected, now: now) }
    let behindResult = BenchmarkAnalysis.compare(
      cohort: cohort, snapshot: released, applications: behind, now: now)
    XCTAssertEqual(behindResult.verdict, .behind)
    XCTAssertEqual(behindResult.localProgressionPercent, 0)

    // Six of ten progressed: 60% against 20%.
    var ahead = (0..<4).map { _ in makeCalibrationApplication(status: .rejected, now: now) }
    ahead += (0..<6).map { _ in makeCalibrationApplication(status: .interview, now: now) }
    let aheadResult = BenchmarkAnalysis.compare(
      cohort: cohort, snapshot: released, applications: ahead, now: now)
    XCTAssertEqual(aheadResult.verdict, .ahead)
    XCTAssertEqual(aheadResult.localProgressionPercent, 60)

    // Two of ten progressed: 20%, exactly the cohort rate.
    var inLine = (0..<8).map { _ in makeCalibrationApplication(status: .rejected, now: now) }
    inLine += (0..<2).map { _ in makeCalibrationApplication(status: .interview, now: now) }
    let inLineResult = BenchmarkAnalysis.compare(
      cohort: cohort, snapshot: released, applications: inLine, now: now)
    XCTAssertEqual(inLineResult.verdict, .inLine)
    XCTAssertTrue(inLineResult.detail.contains("not a signal"))
  }

  // MARK: - Evidence attestations

  private func makeAttestation(
    evidenceID: UUID, status: AttestationStatus, name: String = "Sam Patel", role: String = ""
  ) -> EvidenceAttestation {
    EvidenceAttestation(
      evidenceID: evidenceID, token: "token-\(UUID().uuidString)", claim: "Led the migration",
      context: "", status: status, verifierName: name, verifierRole: role, comment: "",
      respondedAt: nil, expiresAt: Date().addingTimeInterval(86_400))
  }

  func testAttestationResolutionPrefersAConfirmationOverAnOpenRequest() {
    let evidenceID = UUID()
    let attestations = [
      makeAttestation(evidenceID: evidenceID, status: .pending),
      makeAttestation(evidenceID: evidenceID, status: .confirmed, name: "Dana Reed"),
      makeAttestation(evidenceID: UUID(), status: .confirmed, name: "Someone Else"),
    ]
    XCTAssertEqual(attestations.attestation(for: evidenceID)?.verifierName, "Dana Reed")

    // With only a declined answer, that is what shows — not nothing.
    let declined = [makeAttestation(evidenceID: evidenceID, status: .declined)]
    XCTAssertEqual(declined.attestation(for: evidenceID)?.status, .declined)
    XCTAssertNil(declined.attestation(for: UUID()))
  }

  func testAttestationAttributionNamesThePersonNotTheApp() {
    let withRole = makeAttestation(
      evidenceID: UUID(), status: .confirmed, name: "Sam Patel", role: "Former manager")
    XCTAssertEqual(withRole.attributionText, "Confirmed by Sam Patel, Former manager")

    let withoutRole = makeAttestation(evidenceID: UUID(), status: .confirmed, name: "Sam Patel")
    XCTAssertEqual(withoutRole.attributionText, "Confirmed by Sam Patel")

    // The feature must never describe a response as identity-verified.
    XCTAssertTrue(EvidenceAttestation.assuranceNote.contains("does not check who they are"))
  }

  func testAttestationsPersistAndLegacyArchivesStillDecode() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("career-intelligence.json")

    // An archive written before attestations existed must still load.
    let legacy = """
      {"evidence":[],"contacts":[],"networkingDrafts":[],"offers":[],\
      "reviewRequests":[],"voiceAttempts":[],"preferredMarket":"southAfrica"}
      """
    try Data(legacy.utf8).write(to: url)
    let migrated = CareerIntelligenceStore(fileURL: url)
    XCTAssertTrue(migrated.attestations.isEmpty)

    let evidenceID = UUID()
    migrated.upsert(makeAttestation(evidenceID: evidenceID, status: .confirmed, name: "Dana Reed"))

    let reloaded = CareerIntelligenceStore(fileURL: url)
    XCTAssertEqual(reloaded.attestations.count, 1)
    XCTAssertEqual(reloaded.attestation(for: evidenceID)?.verifierName, "Dana Reed")
    XCTAssertEqual(reloaded.confirmedAttestations.count, 1)
  }

  func testSelfDeclaredEvidenceIsNotTreatedAsAConfirmation() {
    // isVerified means "I have a source"; an attestation means somebody else
    // said so. A self-ticked item with no referee must resolve to nothing.
    let selfTicked = CareerEvidence(
      kind: .achievement, title: "Led the migration", detail: "Detail", source: "",
      tags: [], isVerified: true)
    let store = CareerIntelligenceStore(
      fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("\(UUID().uuidString).json"))
    store.upsert(selfTicked)
    XCTAssertEqual(store.verifiedEvidence.count, 1)
    XCTAssertNil(store.attestation(for: selfTicked.id))
    XCTAssertTrue(store.confirmedAttestations.isEmpty)
  }
}

extension CGSize {
  fileprivate func contains(rect: CGRect) -> Bool {
    rect.minX >= 0 && rect.minY >= 0 && rect.maxX <= width && rect.maxY <= height
  }
}

@MainActor
/// The share extension reads a shared page in Safari and sends back whatever the
/// board publishes for search engines. These cover the turning of that into the
/// plain wording the capture step reads.
final class SharedJobCaptureTests: XCTestCase {
  private let posting = """
    {"@context":"https://schema.org","@type":"JobPosting",
     "title":"Senior React Native Engineer",
     "hiringOrganization":{"@type":"Organization","name":"Methys Digital"},
     "jobLocation":{"@type":"Place","address":{"@type":"PostalAddress",
       "addressLocality":"Durban","addressRegion":"KwaZulu-Natal"}},
     "employmentType":"FULL_TIME",
     "description":"<p>Build alarm monitoring apps.</p><ul><li>React Native</li></ul>"}
    """

  func testAStructuredPostingIsPreferredOverTheSweptUpPageText() {
    let capture = SharedJobCapture(
      url: "https://example.com/jobs/1",
      text: "Cookie preferences Similar jobs Sign in Senior React Native Engineer",
      title: "Senior React Native Engineer | Methys Digital",
      posting: posting)

    let read = capture.bestAvailableText
    XCTAssertTrue(read.contains("Senior React Native Engineer"))
    XCTAssertTrue(read.contains("Methys Digital"))
    XCTAssertTrue(read.contains("Durban, KwaZulu-Natal"))
    XCTAssertTrue(read.contains("Build alarm monitoring apps."))
    // The page furniture the structured posting lets us skip.
    XCTAssertFalse(read.contains("Cookie preferences"))
    XCTAssertFalse(read.contains("Sign in"))
  }

  func testMarkupInAPostingBecomesReadableLines() {
    let capture = SharedJobCapture(url: "", text: "", title: nil, posting: posting)
    let read = capture.bestAvailableText
    XCTAssertFalse(read.contains("<p>"))
    XCTAssertFalse(read.contains("</li>"))
    // Block tags become breaks, so the paragraphing survives the stripping.
    XCTAssertTrue(read.contains("Build alarm monitoring apps.\nReact Native"))
  }

  func testPageTextIsUsedWhenABoardPublishesNoStructuredPosting() {
    // Boards title the page "Role at Company", which is worth keeping in front
    // of body text that opens with navigation.
    let titled = SharedJobCapture(
      url: "https://example.com/jobs/3", text: "Apply now Share Save",
      title: "Web Developer at Atom Foundation", posting: nil)
    XCTAssertEqual(
      titled.bestAvailableText, "Web Developer at Atom Foundation\n\nApply now Share Save")

    // Not repeated when the text already begins with it.
    let capture = SharedJobCapture(
      url: "https://example.com/jobs/2", text: "Web Developer at Atom Foundation",
      title: "Web Developer", posting: nil)
    XCTAssertEqual(capture.bestAvailableText, "Web Developer at Atom Foundation")

    // Malformed JSON on the page is not a reason to lose the text beside it.
    let broken = SharedJobCapture(
      url: "", text: "Fallback wording", title: nil, posting: "{not json")
    XCTAssertEqual(broken.bestAvailableText, "Fallback wording")
  }

  /// A capture queued by a build that predates these fields still has to decode.
  func testAnOlderQueuedCaptureStillDecodes() throws {
    let legacy = #"{"url":"https://example.com","text":"Role","receivedAt":760000000}"#
    let capture = try JSONDecoder().decode(
      SharedJobCapture.self, from: Data(legacy.utf8))
    XCTAssertEqual(capture.url, "https://example.com")
    XCTAssertNil(capture.posting)
    XCTAssertEqual(capture.bestAvailableText, "Role")
  }

  /// Pay is usually the most buried thing in a posting and the most useful to
  /// have kept, so a structured salary is carried across whichever way it is set.
  func testSalaryIsReadAsARangeOrASingleFigure() {
    func read(_ salary: String) -> String {
      SharedJobCapture(
        url: "", text: "", title: nil,
        posting: #"{"@type":"JobPosting","title":"Engineer","baseSalary":\#(salary)}"#
      ).bestAvailableText
    }

    let range = read(
      #"{"currency":"ZAR","value":{"minValue":600000,"maxValue":840000,"unitText":"YEAR"}}"#)
    XCTAssertTrue(range.contains("ZAR"), range)
    XCTAssertTrue(range.contains("per year"), range)
    XCTAssertTrue(range.contains("–"), range)

    let single = read(#"{"currency":"GBP","value":{"value":450,"unitText":"DAY"}}"#)
    XCTAssertTrue(single.contains("GBP 450 per day"), single)

    // No salary published is simply no salary line, not a broken one.
    let none = SharedJobCapture(
      url: "", text: "", title: nil, posting: #"{"@type":"JobPosting","title":"Engineer"}"#)
    XCTAssertFalse(none.bestAvailableText.contains("Salary:"))
  }

  func testARemotePostingSaysSoEvenWhenItListsAnAddress() {
    let capture = SharedJobCapture(
      url: "", text: "", title: nil,
      posting: """
        {"@type":"JobPosting","title":"Engineer","jobLocationType":"TELECOMMUTE",
         "jobLocation":{"address":{"addressLocality":"Cape Town",
         "addressCountry":"South Africa"}},"validThrough":"2026-09-30"}
        """)
    let read = capture.bestAvailableText
    XCTAssertTrue(read.contains("Cape Town, South Africa"), read)
    XCTAssertTrue(read.contains("Remote"), read)
    XCTAssertTrue(read.contains("Closing date: 2026-09-30"), read)
  }

  func testOnlyWebAddressesAreAcceptedAsSavedSearches() {
    XCTAssertEqual(
      SavedJobSearchStore.normalised("pnet.co.za/jobs")?.absoluteString,
      "https://pnet.co.za/jobs")
    XCTAssertEqual(
      SavedJobSearchStore.normalised(" https://otta.com/jobs ")?.absoluteString,
      "https://otta.com/jobs")
    // A custom scheme must never become a way to reach another app.
    XCTAssertNil(SavedJobSearchStore.normalised("resumestudio://capture-job"))
    XCTAssertNil(SavedJobSearchStore.normalised("javascript:alert(1)"))
    XCTAssertNil(SavedJobSearchStore.normalised("   "))
  }
}

/// Sharing several roles in a row is how someone works through a board, and the
/// app is rarely open while they do it. These cover the queue that holds them.
final class SharedJobInboxTests: XCTestCase {
  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    defaults = UserDefaults(suiteName: SharedJobInbox.appGroupID)
    SharedJobInbox.discardAll()
  }

  override func tearDown() {
    SharedJobInbox.discardAll()
    super.tearDown()
  }

  private func queue(_ captures: [SharedJobCapture]) {
    captures.forEach(SharedJobInbox.enqueue)
  }

  private func capture(_ url: String, at offset: TimeInterval) -> SharedJobCapture {
    SharedJobCapture(
      url: url, text: "Role at \(url)", title: nil, posting: nil,
      receivedAt: Date(timeIntervalSince1970: 760_000_000 + offset))
  }

  func testSharesAreKeptInOrderRatherThanReplacingEachOther() {
    queue([capture("first", at: 0), capture("second", at: 10), capture("third", at: 20)])

    XCTAssertEqual(SharedJobInbox.pendingCount, 3)
    XCTAssertEqual(SharedJobInbox.consume()?.url, "first")
    XCTAssertEqual(SharedJobInbox.consume()?.url, "second")
    XCTAssertEqual(SharedJobInbox.pendingCount, 1)
    XCTAssertEqual(SharedJobInbox.consume()?.url, "third")
    XCTAssertNil(SharedJobInbox.consume())
  }

  /// Shares can be written out of order; the queue answers by when they arrived.
  func testTheOldestShareIsAlwaysTakenFirst() {
    queue([capture("late", at: 90), capture("early", at: 5)])
    XCTAssertEqual(SharedJobInbox.consume()?.url, "early")
    XCTAssertEqual(SharedJobInbox.consume()?.url, "late")
  }

  /// A job shared just before this update installed sat in a single default.
  func testACaptureLeftInTheOldSingleSlotIsNotStranded() throws {
    let legacy = SharedJobCapture(
      url: "https://example.com/legacy", text: "Waiting since the last build",
      title: nil, posting: nil, receivedAt: Date(timeIntervalSince1970: 760_000_000))
    defaults.set(try JSONEncoder().encode(legacy), forKey: SharedJobInbox.legacyKey)
    queue([capture("newer", at: 500)])
    // The automatic pass runs once per process, so drive it directly here.
    SharedJobInbox.migrateLegacyStorage()

    XCTAssertEqual(SharedJobInbox.pendingCount, 2)
    XCTAssertEqual(SharedJobInbox.consume()?.url, "https://example.com/legacy")
    // Carried into the file, so it is not handed out a second time.
    XCTAssertNil(defaults.data(forKey: SharedJobInbox.legacyKey))
    XCTAssertEqual(SharedJobInbox.pendingCount, 1)
  }

  /// The queue itself lived in defaults for one build before moving to a file.
  func testAQueueLeftInDefaultsIsCarriedIntoTheFile() throws {
    let stranded = [capture("one", at: 0), capture("two", at: 10)]
    defaults.set(try JSONEncoder().encode(stranded), forKey: SharedJobInbox.legacyQueueKey)
    SharedJobInbox.migrateLegacyStorage()

    XCTAssertEqual(SharedJobInbox.pending().map(\.url), ["one", "two"])
    XCTAssertNil(defaults.data(forKey: SharedJobInbox.legacyQueueKey))
    // And still there on the next read, from the file this time.
    XCTAssertEqual(SharedJobInbox.pending().map(\.url), ["one", "two"])
  }

  /// The whole point of coordinating: the app draining and the extension
  /// filling must not lose each other's work.
  func testConcurrentDrainingAndFillingLosesNothing() {
    queue((0..<10).map { capture("seeded-\($0)", at: TimeInterval($0)) })

    let drained = NSLock()
    var taken: [String] = []
    let group = DispatchGroup()

    for index in 0..<10 {
      DispatchQueue.global().async(group: group) {
        if let capture = SharedJobInbox.consume() {
          drained.lock()
          taken.append(capture.url)
          drained.unlock()
        }
      }
      DispatchQueue.global().async(group: group) {
        SharedJobInbox.enqueue(self.capture("shared-\(index)", at: TimeInterval(100 + index)))
      }
    }
    XCTAssertEqual(group.wait(timeout: .now() + 20), .success)

    // Ten went in and ten came out, so nothing was silently dropped: whatever
    // was taken plus whatever is left must account for every capture.
    let remaining = SharedJobInbox.pending().map(\.url)
    XCTAssertEqual(taken.count + remaining.count, 20)
    XCTAssertEqual(Set(taken).count, taken.count, "a capture was handed out twice")
    XCTAssertEqual(Set(remaining).count, remaining.count, "a capture was stored twice")
    XCTAssertTrue(Set(taken).isDisjoint(with: Set(remaining)))
  }

  /// The cap holds as shares arrive, and drops the oldest — someone who has
  /// shared forty roles without opening the app wants the twenty most recent.
  func testTheQueueStopsGrowingAndKeepsTheMostRecent() {
    queue((0..<40).map { capture("job-\($0)", at: TimeInterval($0)) })

    let waiting = SharedJobInbox.pending().map(\.url)
    XCTAssertEqual(waiting.count, SharedJobInbox.limit)
    XCTAssertEqual(waiting.first, "job-20")
    XCTAssertEqual(waiting.last, "job-39")

    // The oldest of what was kept is still what comes out next.
    XCTAssertEqual(SharedJobInbox.consume()?.url, "job-20")
    XCTAssertEqual(SharedJobInbox.pendingCount, SharedJobInbox.limit - 1)
  }

  func testDiscardingLeavesTheRestOfTheQueueAlone() {
    let unwanted = capture("unwanted", at: 10)
    queue([capture("keep", at: 0), unwanted, capture("also-keep", at: 20)])

    SharedJobInbox.discard(unwanted)
    XCTAssertEqual(SharedJobInbox.pending().map(\.url), ["keep", "also-keep"])
  }
}

final class ResumeQuickEditLocatorTests: XCTestCase {
  /// The double-tap editor identifies what was tapped by matching the rendered
  /// line against the résumé's own text, so it has to survive the ways templates
  /// reprint that text: upper case headings, bullets, pipes, wrapped paragraphs
  /// and several values sharing one line.
  private func target(
    _ line: String, relativeY: CGFloat = 0.5, page: Int = 0
  ) -> ResumeQuickEditTarget? {
    ResumeQuickEditLocator.target(
      forLine: line, relativeY: relativeY, pageIndex: page, in: .example)
  }

  func testHeadingsAndBulletsResolveToTheFieldTheyCameFrom() {
    let document = ResumeDocument.example
    XCTAssertEqual(target(document.personal.fullName.uppercased(), relativeY: 0.05), .name)
    XCTAssertEqual(target("•  \(document.competencies[0])"), .competencies)

    let role = document.experience[0]
    XCTAssertEqual(target(role.company), .experience(role.id))
    XCTAssertEqual(target("•  \(role.highlights[0])"), .experience(role.id))

    let study = document.education[0]
    XCTAssertEqual(target(study.qualification), .education(study.id))
  }

  func testWrappedParagraphAndSharedLinesStillResolve() {
    let document = ResumeDocument.example
    // A profile is printed wrapped, so a tapped line is only a fragment of it.
    let fragment = String(document.professionalProfile.prefix(40))
    XCTAssertEqual(target(fragment), .profile)

    // Two-column competencies put several stored values on one printed line.
    let shared = "\(document.competencies[0])    \(document.competencies[1])"
    XCTAssertEqual(target(shared), .competencies)
  }

  func testTheLetterheadDecidesBetweenAJobTitleAndTheSameWordsAsARole() {
    var document = ResumeDocument.example
    document.personal.headline = "Software Engineer"
    document.experience[0].role = "Software Engineer"

    let atTop = ResumeQuickEditLocator.target(
      forLine: "Software Engineer", relativeY: 0.06, pageIndex: 0, in: document)
    let inBody = ResumeQuickEditLocator.target(
      forLine: "Software Engineer", relativeY: 0.55, pageIndex: 0, in: document)

    XCTAssertEqual(atTop, .headline)
    XCTAssertEqual(inBody, .experience(document.experience[0].id))
  }

  func testSectionHeadingsOpenTheSectionTheyLabel() {
    let document = ResumeDocument.example
    XCTAssertEqual(target("PROFESSIONAL EXPERIENCE"), .experience(document.experience[0].id))
    XCTAssertEqual(target("Education"), .education(document.education[0].id))
    XCTAssertEqual(target("CORE COMPETENCIES"), .competencies)
    XCTAssertEqual(target("Professional Profile"), .profile)
    if let reference = document.references.first {
      XCTAssertEqual(target("REFERENCES"), .reference(reference.id))
    }
  }

  func testHeadingWordsInsideBodyTextDoNotHijackTheirSection() {
    var document = ResumeDocument.example
    document.experience[0].highlights[0] = "Improved the employee experience across three regions"
    // The word alone is a heading; a sentence carrying it is still its own bullet.
    let sentence = ResumeQuickEditLocator.target(
      forLine: "Improved the employee experience across three regions",
      relativeY: 0.5, pageIndex: 0, in: document)
    XCTAssertEqual(sentence, .experience(document.experience[0].id))

    // A user's own section named like a heading wins over the heading list.
    var custom = ResumeDocument.example
    custom.additionalSections = [ResumeAdditionalSection(title: "Skills", items: ["Welding"])]
    XCTAssertEqual(
      ResumeQuickEditLocator.target(
        forLine: "Skills", relativeY: 0.5, pageIndex: 0, in: custom),
      .additional(custom.additionalSections[0].id))
  }

  func testAContinuedHeadingOpensTheEntryPrintedUnderItNotThePageOneEntry() {
    var document = ResumeDocument.example
    document.education = [
      EducationEntry(
        qualification: "Bachelor of Business Administration",
        institution: "Example State University", period: "2014 - 2018", details: ""),
      EducationEntry(
        qualification: "Certificate in People Analytics",
        institution: "Sample Learning Institute", period: "2021", details: ""),
    ]

    // Page two reprints the heading over the entry that spilled onto it.
    let spilled = ResumeQuickEditLocator.target(
      forLine: "EDUCATION - CONTINUED",
      following: "Certificate in People Analytics  Sample Learning Institute  2021",
      relativeY: 0.2, pageIndex: 1, in: document)
    XCTAssertEqual(spilled, .education(document.education[1].id))

    // The same heading on page one still opens page one's entry.
    let original = ResumeQuickEditLocator.target(
      forLine: "EDUCATION",
      following: "Bachelor of Business Administration  Example State University",
      relativeY: 0.8, pageIndex: 0, in: document)
    XCTAssertEqual(original, .education(document.education[0].id))
  }

  /// A referee is usually a former manager, so their employer is also a company
  /// listed under professional experience and matches both fields equally well.
  /// The heading above the tap is the only thing that says which one is meant.
  func testTheHeadingAboveATapSeparatesARefereeFromTheRoleAtTheSameCompany() {
    var document = ResumeDocument.example
    document.experience = [
      ExperienceEntry(
        role: "Software Engineer", company: "Methys Digital",
        period: "Feb 2023 - Present", highlights: ["Built the alarm monitoring app."])
    ]
    document.references = [
      ReferenceEntry(
        name: "Riley Example", company: "Methys Digital",
        phone: "+27 11 555 0100", email: "riley@example.com")
    ]

    // The company name printed under the references heading is the referee's.
    let referee = ResumeQuickEditLocator.target(
      forLine: "Methys Digital",
      preceding: "REFERENCES Riley Example",
      relativeY: 0.72, pageIndex: 1, in: document)
    XCTAssertEqual(referee, .reference(document.references[0].id))

    // The same words under the experience heading are still the role.
    let employer = ResumeQuickEditLocator.target(
      forLine: "Methys Digital",
      preceding: "PROFESSIONAL EXPERIENCE Software Engineer",
      relativeY: 0.4, pageIndex: 0, in: document)
    XCTAssertEqual(employer, .experience(document.experience[0].id))

    // With no heading above it, the tie falls back to the old ordering rather
    // than guessing — nothing regresses for templates that print no headings.
    XCTAssertNotNil(
      ResumeQuickEditLocator.target(
        forLine: "Methys Digital", relativeY: 0.5, pageIndex: 0, in: document))
  }

  /// The nearest heading wins: page two reprints "experience continued" above a
  /// references block that comes later on the same page.
  func testTheNearestHeadingAboveTheTapWinsWhenAPageHoldsSeveralSections() {
    var document = ResumeDocument.example
    document.experience = [
      ExperienceEntry(
        role: "Teaching Assistant", company: "Northstar Works",
        period: "2017 - 2018", highlights: ["Taught classes of 30 to 50 students."])
    ]
    document.references = [
      ReferenceEntry(
        name: "Morgan Sample", company: "Northstar Works",
        phone: "+27 11 555 0164", email: "morgan@example.com")
    ]

    let target = ResumeQuickEditLocator.target(
      forLine: "Northstar Works",
      preceding: """
        PROFESSIONAL EXPERIENCE - CONTINUED Teaching Assistant \
        Taught classes of 30 to 50 students. REFERENCES Morgan Sample
        """,
      relativeY: 0.8, pageIndex: 1, in: document)
    XCTAssertEqual(target, .reference(document.references[0].id))
  }

  func testEmptyLetterheadOffersThePortraitAndBlankMarginsStayInert() {
    XCTAssertEqual(target("", relativeY: 0.04), .photo)
    XCTAssertNil(target("", relativeY: 0.7))
    XCTAssertNil(target("Nothing in this résumé says this", relativeY: 0.7))
    // A portrait only ever sits on the first page's letterhead.
    XCTAssertNil(target("", relativeY: 0.04, page: 1))
  }
}
