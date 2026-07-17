import Foundation

private struct CareerIntelligenceArchive: Codable {
  var evidence: [CareerEvidence]
  var contacts: [CareerContact]
  var networkingDrafts: [NetworkingDraft]
  var offers: [JobOffer]
  var reviewRequests: [ResumeReviewRequest]
  var voiceAttempts: [VoicePracticeAttempt]
  var preferredMarket: ResumeMarket
  var aiRevisions: [AIRevision]?
  var processingRecords: [AIProcessingRecord]?
  var marketSources: [MarketGuidanceSource]?

  init(
    evidence: [CareerEvidence] = [],
    contacts: [CareerContact] = [],
    networkingDrafts: [NetworkingDraft] = [],
    offers: [JobOffer] = [],
    reviewRequests: [ResumeReviewRequest] = [],
    voiceAttempts: [VoicePracticeAttempt] = [],
    preferredMarket: ResumeMarket = .southAfrica,
    aiRevisions: [AIRevision] = [],
    processingRecords: [AIProcessingRecord] = [],
    marketSources: [MarketGuidanceSource] = []
  ) {
    self.evidence = evidence
    self.contacts = contacts
    self.networkingDrafts = networkingDrafts
    self.offers = offers
    self.reviewRequests = reviewRequests
    self.voiceAttempts = voiceAttempts
    self.preferredMarket = preferredMarket
    self.aiRevisions = aiRevisions
    self.processingRecords = processingRecords
    self.marketSources = marketSources
  }
}

@MainActor
final class CareerIntelligenceStore: ObservableObject {
  @Published private(set) var evidence: [CareerEvidence] = []
  @Published private(set) var contacts: [CareerContact] = []
  @Published private(set) var networkingDrafts: [NetworkingDraft] = []
  @Published private(set) var offers: [JobOffer] = []
  @Published private(set) var reviewRequests: [ResumeReviewRequest] = []
  @Published private(set) var voiceAttempts: [VoicePracticeAttempt] = []
  @Published private(set) var aiRevisions: [AIRevision] = []
  @Published private(set) var processingRecords: [AIProcessingRecord] = []
  @Published private(set) var marketSources: [MarketGuidanceSource] = []
  @Published var preferredMarket: ResumeMarket = .southAfrica { didSet { save() } }
  @Published private(set) var lastSaveError: String?

  private let fileURL: URL
  private var isLoading = true

  init(fileURL: URL? = nil) {
    self.fileURL = fileURL ?? Self.defaultURL
    if let data = try? Data(contentsOf: self.fileURL),
      let archive = try? Self.decoder.decode(CareerIntelligenceArchive.self, from: data)
    {
      evidence = archive.evidence
      contacts = archive.contacts
      networkingDrafts = archive.networkingDrafts
      offers = archive.offers
      reviewRequests = archive.reviewRequests
      voiceAttempts = archive.voiceAttempts
      preferredMarket = archive.preferredMarket
      aiRevisions = archive.aiRevisions ?? []
      processingRecords = archive.processingRecords ?? []
      marketSources = archive.marketSources ?? []
    }
    isLoading = false
    NotificationCenter.default.addObserver(
      forName: .aiRequestDidComplete, object: nil, queue: .main
    ) { [weak self] note in
      guard UserDefaults.standard.object(forKey: CareerPrivacySetting.keepHistoryKey) as? Bool ?? true,
        let action = note.userInfo?["action"] as? String
      else { return }
      Task { @MainActor [weak self] in
        self?.addProcessingRecord(action: action)
      }
    }
  }

  var verifiedEvidence: [CareerEvidence] { evidence.filter(\.isVerified) }

  func upsert(_ item: CareerEvidence) {
    var updated = item
    updated.updatedAt = Date()
    if let index = evidence.firstIndex(where: { $0.id == item.id }) { evidence[index] = updated }
    else { evidence.insert(updated, at: 0) }
    save()
  }

  func deleteEvidence(at offsets: IndexSet) { evidence.remove(atOffsets: offsets); save() }

  func deleteEvidence(ids: Set<UUID>) {
    evidence.removeAll { ids.contains($0.id) }
    save()
  }

  @discardableResult
  func importEvidence(from document: ResumeDocument, resumeID: UUID?, sourceTitle: String) -> Int {
    var candidates: [CareerEvidence] = []
    for entry in document.experience {
      for highlight in entry.highlights where !highlight.isBlank {
        candidates.append(CareerEvidence(
          kind: .achievement,
          title: entry.role.nilIfBlank ?? "Experience evidence",
          detail: highlight,
          source: [entry.company, entry.period].filter { !$0.isBlank }.joined(separator: " · "),
          sourceResumeID: resumeID,
          tags: [entry.role, entry.company].filter { !$0.isBlank },
          isVerified: true
        ))
      }
    }
    for skill in document.competencies where !skill.isBlank {
      candidates.append(CareerEvidence(
        kind: .skill, title: skill, detail: "Demonstrated in \(sourceTitle)", source: sourceTitle,
        sourceResumeID: resumeID, tags: [skill], isVerified: true
      ))
    }
    for entry in document.education where !entry.qualification.isBlank || !entry.institution.isBlank {
      candidates.append(CareerEvidence(
        kind: .qualification, title: entry.qualification.nilIfBlank ?? "Qualification",
        detail: entry.details, source: [entry.institution, entry.period].filter { !$0.isBlank }.joined(separator: " · "),
        sourceResumeID: resumeID, tags: [], isVerified: true
      ))
    }
    for section in document.additionalSections {
      let kind: CareerEvidenceKind = section.title.localizedCaseInsensitiveContains("award") ? .award : .project
      for value in section.items where !value.isBlank {
        candidates.append(CareerEvidence(
          kind: kind, title: section.title, detail: value, source: sourceTitle,
          sourceResumeID: resumeID, tags: [section.title], isVerified: true
        ))
      }
    }

    let existingKeys = Set(evidence.map { Self.evidenceKey($0.title, $0.detail, $0.source) })
    let unique = candidates.filter { !existingKeys.contains(Self.evidenceKey($0.title, $0.detail, $0.source)) }
    evidence.insert(contentsOf: unique, at: 0)
    save()
    return unique.count
  }

  func upsert(_ contact: CareerContact) {
    if let index = contacts.firstIndex(where: { $0.id == contact.id }) { contacts[index] = contact }
    else { contacts.insert(contact, at: 0) }
    save()
    Task { try? await CareerReminderService.schedule(contact: contact) }
  }

  func deleteContact(_ id: UUID) { contacts.removeAll { $0.id == id }; save() }

  func add(_ draft: NetworkingDraft) { networkingDrafts.insert(draft, at: 0); save() }

  func upsert(_ offer: JobOffer) {
    if let index = offers.firstIndex(where: { $0.id == offer.id }) { offers[index] = offer }
    else { offers.insert(offer, at: 0) }
    save()
  }

  func deleteOffer(_ id: UUID) { offers.removeAll { $0.id == id }; save() }

  func upsert(_ request: ResumeReviewRequest) {
    if let index = reviewRequests.firstIndex(where: { $0.id == request.id }) { reviewRequests[index] = request }
    else { reviewRequests.insert(request, at: 0) }
    save()
  }

  func deleteReviewRequest(_ id: UUID) {
    reviewRequests.removeAll { $0.id == id }
    save()
  }

  func add(_ attempt: VoicePracticeAttempt) { voiceAttempts.insert(attempt, at: 0); save() }

  func addRevision(_ revision: AIRevision) { aiRevisions.insert(revision, at: 0); save() }

  func markRevisionReverted(_ id: UUID) {
    guard let index = aiRevisions.firstIndex(where: { $0.id == id }) else { return }
    aiRevisions[index].status = .reverted
    aiRevisions[index].revertedAt = Date()
    save()
  }

  func deleteProcessingHistory() { processingRecords.removeAll(); save() }

  func resetCareerIntelligence() {
    evidence.removeAll(); contacts.removeAll(); networkingDrafts.removeAll(); offers.removeAll()
    reviewRequests.removeAll(); voiceAttempts.removeAll(); aiRevisions.removeAll()
    processingRecords.removeAll(); marketSources.removeAll()
    save()
  }

  func replaceMarketSources(_ sources: [MarketGuidanceSource]) {
    marketSources = sources
    save()
  }

  func exportData() throws -> Data { try Self.encoder.encode(archive) }

  func importData(_ data: Data) throws {
    let value = try Self.decoder.decode(CareerIntelligenceArchive.self, from: data)
    evidence = value.evidence
    contacts = value.contacts
    networkingDrafts = value.networkingDrafts
    offers = value.offers
    reviewRequests = value.reviewRequests
    voiceAttempts = value.voiceAttempts
    aiRevisions = value.aiRevisions ?? []
    processingRecords = value.processingRecords ?? []
    marketSources = value.marketSources ?? []
    preferredMarket = value.preferredMarket
    save()
  }

  func mergeData(_ data: Data) throws {
    let value = try Self.decoder.decode(CareerIntelligenceArchive.self, from: data)
    evidence = Self.merge(evidence, value.evidence, date: \.updatedAt)
    contacts = Self.mergeNewest(contacts, value.contacts, date: { $0.lastContactedAt ?? $0.createdAt })
    networkingDrafts = Self.mergeNewest(networkingDrafts, value.networkingDrafts, date: { $0.createdAt })
    offers = Self.mergeNewest(offers, value.offers, date: { $0.createdAt })
    reviewRequests = Self.mergeNewest(reviewRequests, value.reviewRequests, date: { $0.createdAt })
    voiceAttempts = Self.mergeNewest(voiceAttempts, value.voiceAttempts, date: { $0.createdAt })
    aiRevisions = Self.mergeNewest(aiRevisions, value.aiRevisions ?? [], date: { $0.createdAt })
    processingRecords = Self.mergeNewest(processingRecords, value.processingRecords ?? [], date: { $0.completedAt })
    marketSources = Self.mergeNewest(marketSources, value.marketSources ?? [], date: { $0.checkedAt })
    save()
  }

  private static func merge<Value: Identifiable>(
    _ local: [Value], _ remote: [Value], date: KeyPath<Value, Date>
  ) -> [Value] where Value.ID: Hashable {
    mergeNewest(local, remote, date: { $0[keyPath: date] })
  }

  private static func mergeNewest<Value: Identifiable>(
    _ local: [Value], _ remote: [Value], date: (Value) -> Date
  ) -> [Value] where Value.ID: Hashable {
    var values = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
    for value in remote {
      if let existing = values[value.id], date(existing) >= date(value) { continue }
      values[value.id] = value
    }
    return values.values.sorted { date($0) > date($1) }
  }

  private var archive: CareerIntelligenceArchive {
    CareerIntelligenceArchive(
      evidence: evidence, contacts: contacts, networkingDrafts: networkingDrafts,
      offers: offers, reviewRequests: reviewRequests, voiceAttempts: voiceAttempts,
      preferredMarket: preferredMarket,
      aiRevisions: aiRevisions,
      processingRecords: processingRecords,
      marketSources: marketSources
    )
  }

  private func addProcessingRecord(action: String) {
    let purpose = action.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).capitalized
    processingRecords.insert(AIProcessingRecord(
      action: action,
      purpose: purpose,
      includedVerifiedEvidence: UserDefaults.standard.object(forKey: CareerPrivacySetting.shareVerifiedEvidenceKey) as? Bool ?? true
    ), at: 0)
    processingRecords = Array(processingRecords.prefix(100))
    save()
  }

  private func save() {
    guard !isLoading else { return }
    do {
      try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Self.encoder.encode(archive).write(to: fileURL, options: .atomic)
      lastSaveError = nil
      NotificationCenter.default.post(name: .careerIntelligenceDidSave, object: nil)
    } catch { lastSaveError = error.localizedDescription }
  }

  private static func evidenceKey(_ title: String, _ detail: String, _ source: String) -> String {
    [title, detail, source].joined(separator: "|").lowercased()
  }

  private static var defaultURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
      .appendingPathComponent("ResumeStudio", isDirectory: true)
      .appendingPathComponent("career-intelligence.json")
  }

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .secondsSince1970
    return encoder
  }()

  private static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    return decoder
  }()
}

extension Notification.Name {
  static let careerIntelligenceDidSave = Notification.Name("ResumeStudio.careerIntelligenceDidSave")
}
