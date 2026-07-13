import Combine
import Foundation

@MainActor
final class ResumeStore: ObservableObject {
    @Published var document: ResumeDocument {
        didSet { save() }
    }

    @Published private(set) var lastSaveError: String?

    private let fileURL: URL

    init(fileURL: URL? = nil, initialDocument: ResumeDocument? = nil) {
        self.fileURL = fileURL ?? Self.defaultDraftURL

        if let initialDocument {
            document = initialDocument
        } else if
            let data = try? Data(contentsOf: self.fileURL),
            let stored = try? JSONDecoder().decode(ResumeDocument.self, from: data)
        {
            document = stored
        } else {
            document = .mandisaSample
        }
    }

    func loadSample() {
        document = .mandisaSample
    }

    func startBlankResume() {
        document = .blank
    }

    func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.pretty.encode(document)
            try data.write(to: fileURL, options: .atomic)
            lastSaveError = nil
        } catch {
            lastSaveError = error.localizedDescription
        }
    }

    static var defaultDraftURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return root
            .appendingPathComponent("ResumeStudio", isDirectory: true)
            .appendingPathComponent("draft.json")
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
