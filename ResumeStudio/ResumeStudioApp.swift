import SwiftUI

@main
struct ResumeStudioApp: App {
    @StateObject private var store = ResumeStore()

    var body: some Scene {
        WindowGroup {
            ResumeEditorView()
                .environmentObject(store)
                .tint(store.document.accent.color)
        }
    }
}
