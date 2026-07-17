import SwiftUI

struct ProfessionalDocumentsWorkspaceView: View {
  @EnvironmentObject private var store: ResumeStore
  @Environment(\.openWindow) private var openWindow
  @State private var selectedResumeID: UUID?
  @State private var importError: String?

  var body: some View {
    NavigationSplitView {
      List(selection: $selectedResumeID) {
        Section("Résumé versions") {
          ForEach(store.resumes) { draft in
            Button {
              selectedResumeID = draft.id
              store.selectResume(draft.id)
            } label: {
              VStack(alignment: .leading, spacing: 3) {
                Text(draft.title).font(.headline)
                Text(draft.updatedAt, style: .relative).font(.caption).foregroundStyle(Theme.mutedInk)
              }
            }
            .tag(draft.id)
            .contextMenu {
              Button("Open in New Window", systemImage: "rectangle.on.rectangle") {
                openWindow(value: draft.id)
              }
            }
          }
        }
        Section("Library") {
          NavigationLink { TemplateGalleryView() } label: {
            Label("Templates", systemImage: "rectangle.split.2x1")
          }
          NavigationLink { ResumeImportView() } label: {
            Label("Import documents", systemImage: "square.and.arrow.down")
          }
        }
      }
      .navigationTitle("Documents")
      .toolbar {
        Button("New résumé", systemImage: "plus") {
          selectedResumeID = store.createResume()
        }
      }
    } detail: {
      HStack(spacing: 0) {
        NavigationStack { ResumeEditorView(focus: nil) }
          .frame(minWidth: 390, idealWidth: 500)
        Divider()
        NavigationStack { ResumePreviewView(document: store.document) }
          .frame(minWidth: 420)
      }
      .dropDestination(for: URL.self) { urls, _ in
        importDroppedFiles(urls)
      } isTargeted: { _ in }
      .overlay(alignment: .bottom) {
        Label("Drop PDF, DOCX, text, CSV or LinkedIn ZIP files to import", systemImage: "arrow.down.doc.fill")
          .font(.caption.weight(.semibold))
          .padding(.horizontal, 14).padding(.vertical, 9)
          .background(.ultraThinMaterial, in: Capsule())
          .padding(.bottom, 12)
      }
    }
    .onAppear {
      selectedResumeID = store.activeResumeID
    }
    .alert("Import failed", isPresented: Binding(
      get: { importError != nil }, set: { if !$0 { importError = nil } }
    )) { Button("OK") {} } message: { Text(importError ?? "") }
  }

  private func importDroppedFiles(_ urls: [URL]) -> Bool {
    guard !urls.isEmpty else { return false }
    do {
      let document = try ResumeImportService.importDocuments(from: urls)
      selectedResumeID = store.createResume(
        title: document.personal.fullName.nilIfBlank.map { "\($0) Résumé" } ?? "Imported Résumé",
        from: document
      )
      return true
    } catch {
      importError = error.localizedDescription
      return false
    }
  }
}

struct ProfessionalApplicationsWorkspaceView: View {
  @EnvironmentObject private var applicationStore: ApplicationStore
  @State private var selectedApplicationID: UUID?

  var body: some View {
    NavigationSplitView {
      List(selection: $selectedApplicationID) {
        ForEach(applicationStore.applications.sorted { $0.updatedAt > $1.updatedAt }) { application in
          Button { selectedApplicationID = application.id } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(application.role.nilIfBlank ?? "Untitled role").font(.headline)
              Text(application.company.nilIfBlank ?? application.status.title)
                .font(.caption).foregroundStyle(Theme.mutedInk)
            }
          }
          .tag(application.id)
        }
      }
      .navigationTitle("Applications")
    } detail: {
      if let selectedApplicationID {
        HomeView(initialRoute: .applicationDetail(selectedApplicationID), allowsWelcome: false, acceptsExternalRoutes: false)
          .id(selectedApplicationID)
      } else {
        HomeView(initialRoute: .applications, allowsWelcome: false, acceptsExternalRoutes: false)
      }
    }
  }
}

struct ResumeVersionWindow: View {
  let resumeID: UUID
  @EnvironmentObject private var parentStore: ResumeStore
  @StateObject private var windowStore: ResumeStore
  @State private var didLoad = false

  init(resumeID: UUID) {
    self.resumeID = resumeID
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("ResumeStudio-Window-\(resumeID.uuidString).json")
    _windowStore = StateObject(wrappedValue: ResumeStore(fileURL: url, initialDocument: .blank))
  }

  var body: some View {
    HStack(spacing: 0) {
      NavigationStack { ResumeEditorView(focus: nil) }
        .environmentObject(windowStore)
        .frame(minWidth: 390)
      Divider()
      NavigationStack { ResumePreviewView(document: windowStore.document) }
        .frame(minWidth: 420)
    }
    .onAppear {
      guard !didLoad, let draft = parentStore.resumes.first(where: { $0.id == resumeID }) else { return }
      didLoad = true
      windowStore.replaceActiveDocument(with: draft.document, suggestedTitle: draft.title)
    }
    .onReceive(NotificationCenter.default.publisher(for: .resumeLibraryDidSave, object: windowStore)) { _ in
      guard didLoad else { return }
      parentStore.updateResume(resumeID, document: windowStore.document)
    }
  }
}

struct ResumeStudioCommands: Commands {
  let resumeStore: ResumeStore

  var body: some Commands {
    CommandMenu("ResumeStudio") {
      Button("New Résumé") { _ = resumeStore.createResume() }
        .keyboardShortcut("n", modifiers: [.command])
      Button("Preview Résumé") {
        NotificationCenter.default.post(name: .selectAppTab, object: "home")
        NotificationCenter.default.post(name: .openHomeRoute, object: HomeRoute.preview)
      }
      .keyboardShortcut("p", modifiers: [.command])
      Button("Open Applications") {
        NotificationCenter.default.post(name: .selectAppTab, object: "applications")
      }
      .keyboardShortcut("a", modifiers: [.command, .shift])
      Button("Browse Templates") {
        NotificationCenter.default.post(name: .selectAppTab, object: "home")
        NotificationCenter.default.post(name: .openHomeRoute, object: HomeRoute.gallery)
      }
      .keyboardShortcut("t", modifiers: [.command, .shift])
    }
  }
}
