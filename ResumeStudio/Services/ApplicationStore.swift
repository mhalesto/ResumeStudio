import Foundation

private struct CareerWorkspaceArchive: Codable {
  var applications: [JobApplication]
  var interviews: [InterviewEvent]
}

@MainActor
final class ApplicationStore: ObservableObject {
  @Published private(set) var applications: [JobApplication] = []
  @Published private(set) var interviews: [InterviewEvent] = []
  @Published private(set) var lastSaveError: String?

  private let fileURL: URL

  init(fileURL: URL? = nil) {
    self.fileURL = fileURL ?? Self.defaultURL
    if let data = try? Data(contentsOf: self.fileURL) {
      if let archive = try? Self.decoder.decode(CareerWorkspaceArchive.self, from: data) {
        applications = archive.applications
        interviews = archive.interviews
      } else if let legacy = try? Self.decoder.decode([JobApplication].self, from: data) {
        applications = legacy
      }
    }
  }

  func add(_ application: JobApplication) {
    applications.insert(application, at: 0)
    save()
    Task { try? await CareerReminderService.schedule(application: application) }
  }

  func update(_ application: JobApplication) {
    guard let index = applications.firstIndex(where: { $0.id == application.id }) else { return }
    var updated = application
    updated.updatedAt = Date()
    applications[index] = updated
    save()
    Task { try? await CareerReminderService.schedule(application: updated) }
  }

  func move(_ id: UUID, to status: JobApplicationStatus) {
    guard let index = applications.firstIndex(where: { $0.id == id }), applications[index].status != status else { return }
    let previous = applications[index].status
    applications[index].status = status
    applications[index].updatedAt = Date()
    var activities = applications[index].activities ?? []
    activities.append(ApplicationActivity(
      kind: status == .applied ? .applied : status == .offer ? .offer : .statusChanged,
      title: "Moved to \(status.title)", detail: "Previously \(previous.title)"
    ))
    applications[index].activities = activities
    save()
  }

  func saveOutcomeReview(_ review: ApplicationOutcomeReview, for applicationID: UUID) {
    guard let index = applications.firstIndex(where: { $0.id == applicationID }) else { return }
    var reviews = applications[index].outcomeReviews ?? []
    var updatedReview = review
    updatedReview.updatedAt = Date()
    if let existing = reviews.firstIndex(where: { $0.stage == review.stage }) {
      updatedReview.id = reviews[existing].id
      updatedReview.createdAt = reviews[existing].createdAt
      reviews[existing] = updatedReview
    } else {
      reviews.insert(updatedReview, at: 0)
      var activities = applications[index].activities ?? []
      activities.append(ApplicationActivity(
        kind: .note,
        title: "Outcome reviewed",
        detail: updatedReview.reason.title
      ))
      applications[index].activities = activities
    }
    applications[index].outcomeReviews = reviews
    applications[index].updatedAt = Date()
    save()
  }

  @discardableResult
  func ensurePacket(
    for applicationID: UUID,
    resumeID: UUID,
    resume: ResumeDocument
  ) -> ApplicationPacket? {
    guard let index = applications.firstIndex(where: { $0.id == applicationID }) else { return nil }
    if let packet = applications[index].packet { return packet }
    let packet = ApplicationPacket.make(
      application: applications[index], resumeID: resumeID, resume: resume)
    applications[index].packet = packet
    applications[index].updatedAt = Date()
    save()
    return packet
  }

  func updatePacket(_ packet: ApplicationPacket) {
    guard let index = applications.firstIndex(where: { $0.id == packet.applicationID }) else { return }
    var updated = packet
    updated.updatedAt = Date()
    applications[index].packet = updated
    applications[index].updatedAt = Date()
    save()
  }

  func delete(at offsets: IndexSet) {
    applications.remove(atOffsets: offsets)
    save()
  }

  func applications(with status: JobApplicationStatus) -> [JobApplication] {
    applications.filter { $0.status == status }.sorted { $0.updatedAt > $1.updatedAt }
  }

  var upcomingInterviews: [InterviewEvent] {
    interviews.filter { !$0.isPast }.sorted { $0.scheduledAt < $1.scheduledAt }
  }

  var pastInterviews: [InterviewEvent] {
    interviews.filter(\.isPast).sorted { $0.scheduledAt > $1.scheduledAt }
  }

  func addInterview(_ interview: InterviewEvent) {
    interviews.append(interview)
    save()
  }

  func updateInterview(_ interview: InterviewEvent) {
    guard let index = interviews.firstIndex(where: { $0.id == interview.id }) else { return }
    var updated = interview
    updated.updatedAt = Date()
    interviews[index] = updated
    save()
  }

  func deleteInterview(_ id: UUID) {
    interviews.removeAll { $0.id == id }
    InterviewReminderService.cancel(interviewID: id)
    save()
  }

  func resetWorkspace() {
    interviews.forEach { InterviewReminderService.cancel(interviewID: $0.id) }
    applications = []
    interviews = []
    save()
  }

  func exportData() throws -> Data {
    try Self.encoder.encode(CareerWorkspaceArchive(applications: applications, interviews: interviews))
  }

  func importData(_ data: Data) throws {
    if let archive = try? Self.decoder.decode(CareerWorkspaceArchive.self, from: data) {
      applications = archive.applications
      interviews = archive.interviews
    } else {
      applications = try Self.decoder.decode([JobApplication].self, from: data)
      interviews = []
    }
    save()
  }

  func mergeData(_ data: Data) throws {
    let incoming: CareerWorkspaceArchive
    if let decoded = try? Self.decoder.decode(CareerWorkspaceArchive.self, from: data) {
      incoming = decoded
    } else {
      incoming = CareerWorkspaceArchive(
        applications: try Self.decoder.decode([JobApplication].self, from: data), interviews: [])
    }
    applications = Self.merged(applications, incoming.applications, date: \.updatedAt)
      .sorted { $0.updatedAt > $1.updatedAt }
    interviews = Self.merged(interviews, incoming.interviews, date: \.updatedAt)
      .sorted { $0.scheduledAt < $1.scheduledAt }
    save()
  }

  private static func merged<Value: Identifiable>(
    _ local: [Value], _ remote: [Value], date: KeyPath<Value, Date>
  ) -> [Value] where Value.ID: Hashable {
    var values = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
    for value in remote {
      if let existing = values[value.id], existing[keyPath: date] >= value[keyPath: date] { continue }
      values[value.id] = value
    }
    return Array(values.values)
  }

  private func save() {
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      let archive = CareerWorkspaceArchive(applications: applications, interviews: interviews)
      try Self.encoder.encode(archive).write(to: fileURL, options: .atomic)
      lastSaveError = nil
      NotificationCenter.default.post(name: .applicationStoreDidSave, object: nil)
    } catch {
      lastSaveError = error.localizedDescription
    }
  }

  private static var defaultURL: URL {
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return root.appendingPathComponent("ResumeStudio", isDirectory: true)
      .appendingPathComponent("applications.json")
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
  static let applicationStoreDidSave = Notification.Name("ResumeStudio.applicationStoreDidSave")
}
