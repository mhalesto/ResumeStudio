import Foundation

private struct CloudWorkspaceArchive: Codable {
  var schemaVersion: Int?
  var revision: String?
  var parentRevision: String?
  var deviceID: String?
  var deviceName: String?
  var savedAt: Date
  var resumeLibrary: Data
  var applications: Data
  var coverLetter: Data
  var careerIntelligence: Data?
  var aiArtifacts: Data?

  var resolvedRevision: String {
    revision ?? "legacy-\(Int(savedAt.timeIntervalSince1970))"
  }
}

@MainActor
final class ICloudSyncService: ObservableObject {
  struct Conflict: Equatable, Identifiable {
    let id = UUID()
    let deviceSavedAt: Date
    let cloudSavedAt: Date
    let cloudDeviceName: String

    static func == (lhs: Conflict, rhs: Conflict) -> Bool {
      lhs.id == rhs.id
    }
  }

  enum ConflictResolution {
    case keepThisDevice
    case useICloud
    case merge
  }

  enum Status: Equatable {
    case notConfigured
    case unavailable
    case syncing
    case conflict
    case synced(Date)
    case failed(String)
  }

  @Published private(set) var status: Status = .notConfigured
  @Published private(set) var conflict: Conflict?
  @Published var isEnabled: Bool {
    didSet {
      UserDefaults.standard.set(isEnabled, forKey: "iCloudSyncEnabled")
      if isEnabled { Task { await synchronize() } }
      else {
        conflict = nil
        status = .notConfigured
      }
    }
  }

  private weak var resumeStore: ResumeStore?
  private weak var applicationStore: ApplicationStore?
  private weak var coverLetterStore: CoverLetterStore?
  private weak var careerIntelligenceStore: CareerIntelligenceStore?
  private weak var aiArtifactStore: AIArtifactStore?
  private var observers: [NSObjectProtocol] = []
  private var isConfigured = false
  private var isApplyingRemote = false
  private var hasLocalChanges = false
  private var pendingRemote: CloudWorkspaceArchive?
  private let cloudFileURLOverride: URL?

  init(isEnabled: Bool? = nil, cloudFileURLOverride: URL? = nil) {
    self.cloudFileURLOverride = cloudFileURLOverride
    self.isEnabled = isEnabled
      ?? (UserDefaults.standard.object(forKey: "iCloudSyncEnabled") as? Bool ?? true)
  }

  deinit {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
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
    hasLocalChanges = (UserDefaults.standard.object(forKey: localChangeKey) as? Date ?? .distantPast)
      > (UserDefaults.standard.object(forKey: lastSyncDateKey) as? Date ?? .distantPast)

    for name in [Notification.Name.resumeLibraryDidSave, .applicationStoreDidSave, .coverLetterDidSave, .careerIntelligenceDidSave, .aiArtifactStoreDidSave] {
      observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor [weak self] in
          guard let self, !self.isApplyingRemote else { return }
          self.hasLocalChanges = true
          UserDefaults.standard.set(Date(), forKey: self.localChangeKey)
          await self.upload()
        }
      })
    }
    Task { await synchronize() }
  }

  func synchronize() async {
    guard isEnabled else { status = .notConfigured; return }
    guard let url = cloudFileURL else { status = .unavailable; return }
    guard storesAreConfigured else { status = .notConfigured; return }
    guard status != .syncing, conflict == nil else { return }
    status = .syncing

    do {
      guard let remote = try readArchive(at: url) else {
        let archive = try writeCurrentWorkspace(to: url, parentRevision: nil)
        markSynced(archive)
        return
      }

      let lastRevision = UserDefaults.standard.string(forKey: lastRevisionKey)
      if lastRevision == nil,
         let legacySyncDate = UserDefaults.standard.object(forKey: lastSyncDateKey) as? Date,
         !hasLocalChanges
      {
        if remote.savedAt > legacySyncDate {
          try apply(remote)
          markSynced(remote)
        } else {
          let archive = try writeCurrentWorkspace(to: url, parentRevision: remote.resolvedRevision)
          markSynced(archive)
        }
        return
      }
      if let lastRevision, remote.resolvedRevision == lastRevision {
        if hasLocalChanges {
          let archive = try writeCurrentWorkspace(to: url, parentRevision: remote.resolvedRevision)
          markSynced(archive)
        } else {
          status = .synced(remote.savedAt)
        }
      } else if hasLocalChanges {
        try presentConflict(remote)
      } else {
        try apply(remote)
        markSynced(remote)
      }
    } catch {
      status = .failed(error.localizedDescription)
    }
  }

  func upload() async {
    guard isEnabled else { status = .notConfigured; return }
    guard status != .syncing, conflict == nil else { return }
    guard let url = cloudFileURL else { status = .unavailable; return }
    guard storesAreConfigured else { status = .notConfigured; return }
    status = .syncing

    do {
      let remote = try readArchive(at: url)
      let lastRevision = UserDefaults.standard.string(forKey: lastRevisionKey)
      if let remote,
         remote.resolvedRevision != lastRevision,
         lastRevision != nil || hasLocalChanges
      {
        try presentConflict(remote)
        return
      }
      let archive = try writeCurrentWorkspace(to: url, parentRevision: remote?.resolvedRevision)
      markSynced(archive)
    } catch {
      status = .failed(error.localizedDescription)
    }
  }

  func resolveConflict(_ resolution: ConflictResolution) async {
    guard let remote = pendingRemote, let url = cloudFileURL else { return }
    status = .syncing
    do {
      switch resolution {
      case .keepThisDevice:
        try createSnapshot(remote, label: "iCloud-before-keep-device")
        let archive = try writeCurrentWorkspace(to: url, parentRevision: remote.resolvedRevision)
        markSynced(archive)
      case .useICloud:
        try createSnapshot(try currentArchive(parentRevision: nil), label: "device-before-use-iCloud")
        try apply(remote)
        markSynced(remote)
      case .merge:
        try createSnapshot(try currentArchive(parentRevision: nil), label: "device-before-merge")
        try createSnapshot(remote, label: "iCloud-before-merge")
        try merge(remote)
        let archive = try writeCurrentWorkspace(to: url, parentRevision: remote.resolvedRevision)
        markSynced(archive)
      }
    } catch {
      status = .failed(error.localizedDescription)
    }
  }

  func eraseCloudWorkspace() async throws {
    guard let url = cloudFileURL else { throw CocoaError(.fileNoSuchFile) }
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
    UserDefaults.standard.removeObject(forKey: lastSyncDateKey)
    UserDefaults.standard.removeObject(forKey: lastRevisionKey)
    UserDefaults.standard.removeObject(forKey: localChangeKey)
    hasLocalChanges = false
    conflict = nil
    pendingRemote = nil
    status = isEnabled ? .synced(Date()) : .notConfigured
  }

  private var storesAreConfigured: Bool {
    resumeStore != nil && applicationStore != nil && coverLetterStore != nil && careerIntelligenceStore != nil
  }

  private func presentConflict(_ remote: CloudWorkspaceArchive) throws {
    try createSnapshot(remote, label: "detected-iCloud")
    try createSnapshot(try currentArchive(parentRevision: nil), label: "detected-device")
    pendingRemote = remote
    conflict = Conflict(
      deviceSavedAt: UserDefaults.standard.object(forKey: localChangeKey) as? Date ?? Date(),
      cloudSavedAt: remote.savedAt,
      cloudDeviceName: remote.deviceName ?? "another device"
    )
    status = .conflict
  }

  private func apply(_ archive: CloudWorkspaceArchive) throws {
    guard let resumeStore, let applicationStore, let coverLetterStore, let careerIntelligenceStore else { return }
    isApplyingRemote = true
    defer { isApplyingRemote = false }
    try resumeStore.importLibraryData(archive.resumeLibrary)
    try applicationStore.importData(archive.applications)
    try coverLetterStore.importData(archive.coverLetter)
    if let data = archive.careerIntelligence { try careerIntelligenceStore.importData(data) }
    if let data = archive.aiArtifacts { try aiArtifactStore?.importData(data) }
  }

  private func merge(_ archive: CloudWorkspaceArchive) throws {
    guard let resumeStore, let applicationStore, let careerIntelligenceStore else { return }
    isApplyingRemote = true
    defer { isApplyingRemote = false }
    try resumeStore.mergeLibraryData(archive.resumeLibrary)
    try applicationStore.mergeData(archive.applications)
    if let data = archive.careerIntelligence { try careerIntelligenceStore.mergeData(data) }
    if let data = archive.aiArtifacts { try aiArtifactStore?.importData(data) }
  }

  private func writeCurrentWorkspace(to url: URL, parentRevision: String?) throws -> CloudWorkspaceArchive {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let archive = try currentArchive(parentRevision: parentRevision)
    try Self.encoder.encode(archive).write(to: url, options: .atomic)
    return archive
  }

  private func currentArchive(parentRevision: String?) throws -> CloudWorkspaceArchive {
    guard let resumeStore, let applicationStore, let coverLetterStore, let careerIntelligenceStore else {
      throw CocoaError(.fileNoSuchFile)
    }
    return CloudWorkspaceArchive(
      schemaVersion: 2,
      revision: UUID().uuidString,
      parentRevision: parentRevision,
      deviceID: deviceID,
      deviceName: ProcessInfo.processInfo.hostName,
      savedAt: Date(),
      resumeLibrary: try resumeStore.exportLibraryData(),
      applications: try applicationStore.exportData(),
      coverLetter: try coverLetterStore.exportData(),
      careerIntelligence: try careerIntelligenceStore.exportData(),
      aiArtifacts: try aiArtifactStore?.exportData()
    )
  }

  private func readArchive(at url: URL) throws -> CloudWorkspaceArchive? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try Self.decoder.decode(CloudWorkspaceArchive.self, from: Data(contentsOf: url))
  }

  private func markSynced(_ archive: CloudWorkspaceArchive) {
    UserDefaults.standard.set(archive.savedAt, forKey: lastSyncDateKey)
    UserDefaults.standard.set(archive.resolvedRevision, forKey: lastRevisionKey)
    UserDefaults.standard.removeObject(forKey: localChangeKey)
    hasLocalChanges = false
    pendingRemote = nil
    conflict = nil
    status = .synced(archive.savedAt)
  }

  private func createSnapshot(_ archive: CloudWorkspaceArchive, label: String) throws {
    let directory = try snapshotDirectory()
    let formatter = ISO8601DateFormatter()
    let name = "\(formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-"))-\(label).json"
    try Self.encoder.encode(archive).write(to: directory.appendingPathComponent(name), options: .atomic)
    let snapshots = try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.contentModificationDateKey],
      options: [.skipsHiddenFiles]
    ).sorted { lhs, rhs in
      let left = try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
      let right = try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
      return (left ?? .distantPast) > (right ?? .distantPast)
    }
    for oldSnapshot in snapshots.dropFirst(12) { try? FileManager.default.removeItem(at: oldSnapshot) }
  }

  private func snapshotDirectory() throws -> URL {
    let base = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let directory = base.appendingPathComponent("ResumeStudio/SyncSnapshots", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private var cloudFileURL: URL? {
    if let cloudFileURLOverride { return cloudFileURLOverride }
    return FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.halalisanimbanjwa.ResumeStudio")?
      .appendingPathComponent("Documents", isDirectory: true)
      .appendingPathComponent("workspace.json")
  }

  private var keySuffix: String {
    if let cloudFileURLOverride { return ".test.\(abs(cloudFileURLOverride.path.hashValue))" }
    return ""
  }

  private var lastSyncDateKey: String { "lastICloudSync\(keySuffix)" }
  private var lastRevisionKey: String { "lastICloudSyncRevision\(keySuffix)" }
  private var localChangeKey: String { "lastICloudLocalChange\(keySuffix)" }
  private var deviceID: String {
    let key = "iCloudSyncDeviceID"
    if let value = UserDefaults.standard.string(forKey: key) { return value }
    let value = UUID().uuidString
    UserDefaults.standard.set(value, forKey: key)
    return value
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
