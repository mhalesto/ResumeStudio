import Combine
import Foundation

private struct ResumeLibraryArchive: Codable, Equatable {
  var activeResumeID: UUID
  var resumes: [ResumeDraft]
}

@MainActor
final class ResumeStore: ObservableObject {
  @Published var document: ResumeDocument {
    didSet {
      guard !isSwitchingDocument else { return }
      synchronizeActiveDraft()
      save()
    }
  }

  @Published private(set) var resumes: [ResumeDraft]
  @Published private(set) var activeResumeID: UUID
  @Published private(set) var lastSaveError: String?
  @Published private(set) var lastEditedAt: Date

  private let fileURL: URL
  private var isSwitchingDocument = false

  init(fileURL: URL? = nil, initialDocument: ResumeDocument? = nil) {
    let url = fileURL ?? Self.defaultDraftURL
    self.fileURL = url
    lastEditedAt =
      (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
      ?? Date()

    if let initialDocument {
      let draft = ResumeDraft(title: Self.defaultTitle(for: initialDocument), document: initialDocument)
      resumes = [draft]
      activeResumeID = draft.id
      document = initialDocument
      return
    }

    let data = try? Data(contentsOf: url)
    if let data,
      let archive = try? Self.decoder.decode(ResumeLibraryArchive.self, from: data),
      !archive.resumes.isEmpty
    {
      let selectedID = archive.resumes.contains { $0.id == archive.activeResumeID }
        ? archive.activeResumeID : archive.resumes[0].id
      resumes = archive.resumes
      activeResumeID = selectedID
      document = archive.resumes.first { $0.id == selectedID }?.document
        ?? archive.resumes[0].document
      return
    }

    let stored = data.flatMap { try? Self.decoder.decode(ResumeDocument.self, from: $0) }
    let migratedDocument: ResumeDocument
    if let stored, stored.schemaVersion >= ResumeDocument.currentSchemaVersion {
      migratedDocument = stored
    } else {
      migratedDocument = .example
    }
    let draft = ResumeDraft(title: Self.defaultTitle(for: migratedDocument), document: migratedDocument)
    resumes = [draft]
    activeResumeID = draft.id
    document = migratedDocument
    save()
  }

  var activeDraft: ResumeDraft? {
    resumes.first { $0.id == activeResumeID }
  }

  func loadSample() {
    document = .example
  }

  func startBlankResume() {
    document = .blank
  }

  @discardableResult
  func createResume(title: String? = nil, from source: ResumeDocument = .blank) -> UUID {
    synchronizeActiveDraft()
    let draft = ResumeDraft(
      title: normalizedTitle(title, fallback: Self.defaultTitle(for: source)),
      document: source
    )
    resumes.append(draft)
    selectResume(draft.id)
    return draft.id
  }

  @discardableResult
  func duplicateActiveResume(title: String? = nil) -> UUID {
    let baseTitle = activeDraft?.title ?? Self.defaultTitle(for: document)
    return createResume(title: normalizedTitle(title, fallback: "\(baseTitle) Copy"), from: document)
  }

  func selectResume(_ id: UUID) {
    guard id != activeResumeID, let selected = resumes.first(where: { $0.id == id }) else { return }
    synchronizeActiveDraft()
    isSwitchingDocument = true
    activeResumeID = id
    document = selected.document
    isSwitchingDocument = false
    lastEditedAt = selected.updatedAt
    save()
  }

  func renameResume(_ id: UUID, to title: String) {
    guard let index = resumes.firstIndex(where: { $0.id == id }) else { return }
    resumes[index].title = normalizedTitle(title, fallback: "Untitled Résumé")
    resumes[index].updatedAt = Date()
    save()
  }

  func deleteResume(_ id: UUID) {
    guard resumes.count > 1, let index = resumes.firstIndex(where: { $0.id == id }) else { return }
    resumes.remove(at: index)
    if activeResumeID == id {
      let replacement = resumes[min(index, resumes.count - 1)]
      isSwitchingDocument = true
      activeResumeID = replacement.id
      document = replacement.document
      isSwitchingDocument = false
    }
    save()
  }

  func replaceActiveDocument(with replacement: ResumeDocument, suggestedTitle: String? = nil) {
    isSwitchingDocument = true
    document = replacement
    isSwitchingDocument = false
    if let index = resumes.firstIndex(where: { $0.id == activeResumeID }) {
      resumes[index].document = replacement
      if let suggestedTitle {
        resumes[index].title = normalizedTitle(suggestedTitle, fallback: resumes[index].title)
      }
      resumes[index].updatedAt = Date()
    }
    save()
  }

  func save() {
    synchronizeActiveDraft()
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let archive = ResumeLibraryArchive(activeResumeID: activeResumeID, resumes: resumes)
      try Self.encoder.encode(archive).write(to: fileURL, options: .atomic)
      lastEditedAt = Date()
      lastSaveError = nil
      NotificationCenter.default.post(name: .resumeLibraryDidSave, object: nil)
    } catch {
      lastSaveError = error.localizedDescription
    }
  }

  func exportLibraryData() throws -> Data {
    synchronizeActiveDraft()
    return try Self.encoder.encode(ResumeLibraryArchive(activeResumeID: activeResumeID, resumes: resumes))
  }

  func importLibraryData(_ data: Data) throws {
    let archive = try Self.decoder.decode(ResumeLibraryArchive.self, from: data)
    guard !archive.resumes.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
    resumes = archive.resumes
    let active = archive.resumes.first { $0.id == archive.activeResumeID } ?? archive.resumes[0]
    activeResumeID = active.id
    isSwitchingDocument = true
    document = active.document
    isSwitchingDocument = false
    save()
  }

  private func synchronizeActiveDraft() {
    guard let index = resumes.firstIndex(where: { $0.id == activeResumeID }) else { return }
    guard resumes[index].document != document else { return }
    resumes[index].document = document
    resumes[index].updatedAt = Date()
  }

  private func normalizedTitle(_ title: String?, fallback: String) -> String {
    let value = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return value.isEmpty ? fallback : value
  }

  private static func defaultTitle(for document: ResumeDocument) -> String {
    let headline = document.personal.headline.trimmingCharacters(in: .whitespacesAndNewlines)
    return headline.isEmpty ? "My Résumé" : headline
  }

  static var defaultDraftURL: URL {
    let root =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    return root
      .appendingPathComponent("ResumeStudio", isDirectory: true)
      .appendingPathComponent("draft.json")
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
  static let resumeLibraryDidSave = Notification.Name("ResumeStudio.resumeLibraryDidSave")
}
