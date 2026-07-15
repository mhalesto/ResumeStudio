import Foundation

private struct CloudWorkspaceArchive: Codable {
  var savedAt: Date
  var resumeLibrary: Data
  var applications: Data
  var coverLetter: Data
  var careerIntelligence: Data?
  var aiArtifacts: Data?
}

@MainActor
final class ICloudSyncService: ObservableObject {
  enum Status: Equatable {
    case notConfigured
    case unavailable
    case syncing
    case synced(Date)
    case failed(String)
  }

  @Published private(set) var status: Status = .notConfigured
  @Published var isEnabled: Bool {
    didSet {
      UserDefaults.standard.set(isEnabled, forKey: "iCloudSyncEnabled")
      if isEnabled { Task { await synchronize() } }
      else { status = .notConfigured }
    }
  }

  private weak var resumeStore: ResumeStore?
  private weak var applicationStore: ApplicationStore?
  private weak var coverLetterStore: CoverLetterStore?
  private weak var careerIntelligenceStore: CareerIntelligenceStore?
  private weak var aiArtifactStore: AIArtifactStore?
  private var observers: [NSObjectProtocol] = []
  private var isConfigured = false
  private let cloudFileURLOverride: URL?

  init(isEnabled: Bool? = nil, cloudFileURLOverride: URL? = nil) {
    self.cloudFileURLOverride = cloudFileURLOverride
    self.isEnabled = isEnabled
      ?? (UserDefaults.standard.object(forKey: "iCloudSyncEnabled") as? Bool ?? true)
  }

  func configure(
    resumeStore: ResumeStore,
    applicationStore: ApplicationStore,
    coverLetterStore: CoverLetterStore,
    careerIntelligenceStore: CareerIntelligenceStore,
    aiArtifactStore: AIArtifactStore? = nil
  ) {
    guard !isConfigured else { return }
    isConfigured = true
    self.resumeStore = resumeStore
    self.applicationStore = applicationStore
    self.coverLetterStore = coverLetterStore
    self.careerIntelligenceStore = careerIntelligenceStore
    self.aiArtifactStore = aiArtifactStore

    for name in [Notification.Name.resumeLibraryDidSave, .applicationStoreDidSave, .coverLetterDidSave, .careerIntelligenceDidSave, .aiArtifactStoreDidSave] {
      observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor in await self?.upload() }
      })
    }
    Task { await synchronize() }
  }

  func synchronize() async {
    guard isEnabled else { status = .notConfigured; return }
    guard let url = cloudFileURL else { status = .unavailable; return }
    guard let resumeStore, let applicationStore, let coverLetterStore, let careerIntelligenceStore else {
      status = .notConfigured
      return
    }
    guard status != .syncing else { return }
    status = .syncing
    do {
      if FileManager.default.fileExists(atPath: url.path),
        let remoteData = try? Data(contentsOf: url),
        let remote = try? Self.decoder.decode(CloudWorkspaceArchive.self, from: remoteData),
        remote.savedAt > (UserDefaults.standard.object(forKey: "lastICloudSync") as? Date ?? .distantPast)
      {
        try resumeStore.importLibraryData(remote.resumeLibrary)
        try applicationStore.importData(remote.applications)
        try coverLetterStore.importData(remote.coverLetter)
        if let data = remote.careerIntelligence { try careerIntelligenceStore.importData(data) }
        if let data = remote.aiArtifacts { try aiArtifactStore?.importData(data) }
        UserDefaults.standard.set(remote.savedAt, forKey: "lastICloudSync")
        status = .synced(remote.savedAt)
      } else {
        let savedAt = try writeWorkspace(
          to: url,
          resumeStore: resumeStore,
          applicationStore: applicationStore,
          coverLetterStore: coverLetterStore,
          careerIntelligenceStore: careerIntelligenceStore
        )
        status = .synced(savedAt)
      }
    } catch {
      status = .failed(error.localizedDescription)
    }
  }

  func upload() async {
    guard isEnabled else { status = .notConfigured; return }
    guard status != .syncing else { return }
    guard let url = cloudFileURL else { status = .unavailable; return }
    guard let resumeStore, let applicationStore, let coverLetterStore, let careerIntelligenceStore else {
      status = .notConfigured
      return
    }
    status = .syncing
    do {
      let savedAt = try writeWorkspace(
        to: url,
        resumeStore: resumeStore,
        applicationStore: applicationStore,
        coverLetterStore: coverLetterStore,
        careerIntelligenceStore: careerIntelligenceStore
      )
      status = .synced(savedAt)
    } catch {
      status = .failed(error.localizedDescription)
    }
  }

  private func writeWorkspace(
    to url: URL,
    resumeStore: ResumeStore,
    applicationStore: ApplicationStore,
    coverLetterStore: CoverLetterStore,
    careerIntelligenceStore: CareerIntelligenceStore
  ) throws -> Date {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let archive = CloudWorkspaceArchive(
      savedAt: Date(),
      resumeLibrary: try resumeStore.exportLibraryData(),
      applications: try applicationStore.exportData(),
      coverLetter: try coverLetterStore.exportData(),
      careerIntelligence: try careerIntelligenceStore.exportData(),
      aiArtifacts: try aiArtifactStore?.exportData()
    )
    let data = try Self.encoder.encode(archive)
    try data.write(to: url, options: .atomic)
    UserDefaults.standard.set(archive.savedAt, forKey: "lastICloudSync")
    return archive.savedAt
  }

  private var cloudFileURL: URL? {
    if let cloudFileURLOverride { return cloudFileURLOverride }
    return FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.halalisanimbanjwa.ResumeStudio")?
      .appendingPathComponent("Documents", isDirectory: true)
      .appendingPathComponent("workspace.json")
  }

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    return encoder
  }()

  private static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    return decoder
  }()
}
