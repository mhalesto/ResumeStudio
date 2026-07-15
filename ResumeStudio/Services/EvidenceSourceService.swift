import Foundation

enum EvidenceSourceService {
  static func importFile(_ url: URL, evidenceID: UUID) throws -> URL {
    let accessed = url.startAccessingSecurityScopedResource()
    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
      .appendingPathComponent("ResumeStudio/EvidenceSources", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let safeName = url.lastPathComponent.replacingOccurrences(of: "/", with: "-")
    let destination = root.appendingPathComponent("\(evidenceID.uuidString)-\(safeName)")
    if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
    try FileManager.default.copyItem(at: url, to: destination)
    return destination
  }
}
