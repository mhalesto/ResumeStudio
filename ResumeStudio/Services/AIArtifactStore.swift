import FirebaseAuth
import FirebaseFirestore
import Foundation

@MainActor
final class AIArtifactStore: ObservableObject {
  static let shared = AIArtifactStore()

  enum CloudStatus: Equatable {
    case localOnly
    case connecting
    case synced(Date)
    case failed(String)
  }

  @Published private(set) var artifacts: [SavedAIArtifact] = []
  @Published private(set) var cloudStatus: CloudStatus = .localOnly
  @Published private(set) var lastSaveError: String?

  private let fileURL: URL
  private var authHandle: AuthStateDidChangeListenerHandle?
  private var snapshotListener: ListenerRegistration?
  private var configuredForFirebase = false

  init(fileURL: URL? = nil) {
    self.fileURL = fileURL ?? Self.defaultURL
    guard let data = try? Data(contentsOf: self.fileURL) else { return }
    artifacts = (try? Self.decoder.decode([SavedAIArtifact].self, from: data)) ?? []
    sortAndLimit()
  }

  func configureFirebase() {
    guard !configuredForFirebase else { return }
    configuredForFirebase = true
    cloudStatus = .connecting
    authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
      Task { @MainActor [weak self] in self?.userDidChange(user) }
    }
  }

  @discardableResult
  func record<Result: Encodable>(
    _ result: Result, action: ResumeAIAction, context: String? = nil,
    provider: ProductInsightSource? = nil
  ) -> SavedAIArtifact? {
    do {
      let data = try Self.outputEncoder.encode(result)
      let json = String(decoding: data, as: UTF8.self)
      let artifact = SavedAIArtifact(
        action: action,
        context: context,
        provider: provider,
        outputJSON: json,
        previewLines: Self.previewLines(from: data)
      )
      artifacts.insert(artifact, at: 0)
      sortAndLimit()
      try saveLocal()
      upload(artifact)
      NotificationCenter.default.post(name: .aiArtifactDidSave, object: artifact)
      return artifact
    } catch {
      lastSaveError = error.localizedDescription
      return nil
    }
  }

  func latest<Result: Decodable>(
    _ type: Result.Type, action: ResumeAIAction, context: String? = nil
  ) -> Result? {
    guard let artifact = artifacts.first(where: {
      $0.action == action && (context == nil || $0.context == context)
    }), let data = artifact.outputJSON.data(using: .utf8) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(type, from: data)
  }

  func delete(_ artifact: SavedAIArtifact) {
    artifacts.removeAll { $0.id == artifact.id }
    try? saveLocal()
    guard configuredForFirebase, let uid = Auth.auth().currentUser?.uid else { return }
    Firestore.firestore().collection("users").document(uid)
      .collection("aiArtifacts").document(artifact.id.uuidString).delete()
  }

  func deleteAll() {
    artifacts.removeAll()
    try? saveLocal()
    guard configuredForFirebase, let uid = Auth.auth().currentUser?.uid else { return }
    Firestore.firestore().collection("users").document(uid).collection("aiArtifacts")
      .getDocuments { snapshot, _ in
        snapshot?.documents.forEach { $0.reference.delete() }
      }
  }

  func exportData() throws -> Data { try Self.encoder.encode(artifacts) }

  func importData(_ data: Data) throws {
    let incoming = try Self.decoder.decode([SavedAIArtifact].self, from: data)
    merge(incoming)
    try saveLocal()
    uploadAll()
  }

  private func userDidChange(_ user: User?) {
    snapshotListener?.remove()
    snapshotListener = nil
    guard let user else { cloudStatus = .localOnly; return }
    cloudStatus = .connecting
    uploadAll()
    snapshotListener = Firestore.firestore().collection("users").document(user.uid)
      .collection("aiArtifacts")
      .order(by: "createdAt", descending: true)
      .limit(to: 250)
      .addSnapshotListener { [weak self] snapshot, error in
        Task { @MainActor [weak self] in
          guard let self else { return }
          if let error {
            self.cloudStatus = .failed(error.localizedDescription)
            return
          }
          let remote = snapshot?.documents.compactMap(Self.artifact(from:)) ?? []
          self.merge(remote)
          try? self.saveLocal()
          self.cloudStatus = .synced(Date())
        }
      }
  }

  private func uploadAll() {
    artifacts.forEach(upload)
  }

  private func upload(_ artifact: SavedAIArtifact) {
    guard configuredForFirebase, let uid = Auth.auth().currentUser?.uid else { return }
    Firestore.firestore().collection("users").document(uid)
      .collection("aiArtifacts").document(artifact.id.uuidString)
      .setData(Self.firestoreData(for: artifact), merge: true) { [weak self] error in
        Task { @MainActor [weak self] in
          if let error { self?.cloudStatus = .failed(error.localizedDescription) }
          else { self?.cloudStatus = .synced(Date()) }
        }
      }
  }

  private func merge(_ incoming: [SavedAIArtifact]) {
    var byID = Dictionary(uniqueKeysWithValues: artifacts.map { ($0.id, $0) })
    incoming.forEach { byID[$0.id] = $0 }
    artifacts = Array(byID.values)
    sortAndLimit()
  }

  private func sortAndLimit() {
    artifacts.sort { $0.createdAt > $1.createdAt }
    artifacts = Array(artifacts.prefix(250))
  }

  private func saveLocal() throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Self.encoder.encode(artifacts).write(to: fileURL, options: .atomic)
    lastSaveError = nil
    NotificationCenter.default.post(name: .aiArtifactStoreDidSave, object: nil)
  }

  private static func firestoreData(for artifact: SavedAIArtifact) -> [String: Any] {
    var value: [String: Any] = [
      "action": artifact.action.rawValue,
      "createdAt": Timestamp(date: artifact.createdAt),
      "outputJSON": artifact.outputJSON,
      "previewLines": artifact.previewLines,
      "schemaVersion": 1,
    ]
    if let context = artifact.context { value["context"] = context }
    if let provider = artifact.provider { value["provider"] = provider.rawValue }
    return value
  }

  private static func artifact(from document: QueryDocumentSnapshot) -> SavedAIArtifact? {
    let value = document.data()
    guard let id = UUID(uuidString: document.documentID),
      let actionRaw = value["action"] as? String,
      let action = ResumeAIAction(rawValue: actionRaw),
      let outputJSON = value["outputJSON"] as? String
    else { return nil }
    return SavedAIArtifact(
      id: id,
      action: action,
      createdAt: (value["createdAt"] as? Timestamp)?.dateValue() ?? .distantPast,
      context: value["context"] as? String,
      provider: (value["provider"] as? String).flatMap(ProductInsightSource.init(rawValue:)),
      outputJSON: outputJSON,
      previewLines: value["previewLines"] as? [String] ?? []
    )
  }

  private static func previewLines(from data: Data) -> [String] {
    guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
    var values: [String] = []
    collectStrings(from: json, into: &values)
    return Array(values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .map { $0.count > 220 ? String($0.prefix(220)) + "…" : $0 }
      .prefix(8))
  }

  private static func collectStrings(from value: Any, into output: inout [String]) {
    guard output.count < 8 else { return }
    if let string = value as? String { output.append(string); return }
    if let array = value as? [Any] {
      array.forEach { collectStrings(from: $0, into: &output) }
      return
    }
    if let dictionary = value as? [String: Any] {
      dictionary.keys.sorted().forEach { key in
        guard !key.localizedCaseInsensitiveContains("source") else { return }
        collectStrings(from: dictionary[key] as Any, into: &output)
      }
    }
  }

  private static var defaultURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
      .appendingPathComponent("ResumeStudio", isDirectory: true)
      .appendingPathComponent("ai-artifacts.json")
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

  private static let outputEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()
}

extension Notification.Name {
  static let aiArtifactDidSave = Notification.Name("ResumeStudio.aiArtifactDidSave")
  static let aiArtifactStoreDidSave = Notification.Name("ResumeStudio.aiArtifactStoreDidSave")
}
