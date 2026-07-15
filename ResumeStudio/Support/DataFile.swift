import SwiftUI
import UniformTypeIdentifiers

struct DataFile: FileDocument {
  static var readableContentTypes: [UTType] { [.data] }
  var data: Data

  init(data: Data) { self.data = data }
  init(configuration: ReadConfiguration) throws {
    data = configuration.file.regularFileContents ?? Data()
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}

extension UTType {
  static let wordProcessingDocument =
    UTType(filenameExtension: "docx")
    ?? UTType(importedAs: "org.openxmlformats.wordprocessingml.document")
}
