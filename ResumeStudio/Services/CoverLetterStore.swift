import Combine
import Foundation

@MainActor
final class CoverLetterStore: ObservableObject {
  @Published var document: CoverLetterDocument {
    didSet { save() }
  }
  @Published private(set) var lastSaveError: String?

  private let fileURL: URL

  init(fileURL: URL? = nil, initialDocument: CoverLetterDocument? = nil) {
    let url = fileURL ?? Self.defaultDraftURL
    self.fileURL = url
    if let initialDocument {
      document = initialDocument
    } else {
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .secondsSince1970
      if let data = try? Data(contentsOf: url),
        let stored = try? decoder.decode(CoverLetterDocument.self, from: data)
      {
        document = stored
      } else {
        document = .blank
      }
    }
  }

  func startBlank(using resume: ResumeDocument) {
    document = .blank
    syncContact(from: resume)
  }

  func loadExample() {
    document = .example
  }

  func syncContact(from resume: ResumeDocument) {
    document.senderName = resume.personal.fullName
    document.senderHeadline = resume.personal.headline
    document.senderPhone = resume.personal.phone
    document.senderEmail = resume.personal.email
    document.accent = resume.accent
  }

  func save() {
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .secondsSince1970
      try encoder.encode(document).write(to: fileURL, options: .atomic)
      lastSaveError = nil
      NotificationCenter.default.post(name: .coverLetterDidSave, object: nil)
    } catch {
      lastSaveError = error.localizedDescription
    }
  }

  func exportData() throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    return try encoder.encode(document)
  }

  func importData(_ data: Data) throws {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    document = try decoder.decode(CoverLetterDocument.self, from: data)
  }

  static var defaultDraftURL: URL {
    let root =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    return root
      .appendingPathComponent("ResumeStudio", isDirectory: true)
      .appendingPathComponent("cover-letter.json")
  }
}

extension Notification.Name {
  static let coverLetterDidSave = Notification.Name("ResumeStudio.coverLetterDidSave")
}
