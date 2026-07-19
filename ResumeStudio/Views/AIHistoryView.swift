import SwiftUI
import UIKit

struct AIHistoryView: View {
  @EnvironmentObject private var store: AIArtifactStore
  @State private var artifactToDelete: SavedAIArtifact?

  var body: some View {
    Group {
      if store.artifacts.isEmpty {
        ContentUnavailableView(
          "No saved AI work yet",
          systemImage: "sparkles.rectangle.stack",
          description: Text("Every successful AI result will appear here automatically.")
        )
      } else {
        List {
          Section {
            cloudStatus
          } footer: {
            Text("Results are saved on this iPhone first, synchronized to your private Firebase account, and included in iCloud workspace sync when enabled.")
          }

          ForEach(store.artifacts) { artifact in
            NavigationLink {
              AIArtifactDetailView(artifact: artifact)
            } label: {
              VStack(alignment: .leading, spacing: 7) {
                Label(artifact.action.title, systemImage: artifact.action.systemImage)
                  .font(.headline)
                if let provider = artifact.provider { AIRouteBadge(provider: provider) }
                if let preview = artifact.previewLines.first {
                  Text(preview).font(.subheadline).foregroundStyle(Theme.mutedInk)
                    .lineLimit(2)
                }
                Text(artifact.createdAt, format: .relative(presentation: .named))
                  .font(.caption).foregroundStyle(Theme.mutedInk)
              }
              .padding(.vertical, 4)
            }
            .swipeActions {
              Button("Delete", systemImage: "trash", role: .destructive) {
                artifactToDelete = artifact
              }
            }
          }
        }
      }
    }
    .scrollContentBackground(.hidden)
    .background(Theme.paper)
    .navigationTitle("Saved AI work")
    .sheet(item: $artifactToDelete) { artifact in
      PremiumConfirmationSheet(
        title: "Delete saved AI result?",
        message: "This result will be removed from your processing history and private backup.",
        systemImage: "sparkles.rectangle.stack.fill",
        accent: .purple,
        rows: [
          PremiumConfirmationRow(
            eyebrow: "SAVED RESULT",
            title: String(localized: artifact.action.title),
            detail: artifact.previewLines.first ?? artifact.createdAt.formatted(date: .abbreviated, time: .shortened),
            systemImage: artifact.action.systemImage,
            tone: .destructive
          )
        ],
        safetyNote: "Your résumé and any changes you already applied stay untouched.",
        confirmTitle: "Delete saved result",
        onConfirm: {
          store.delete(artifact)
          artifactToDelete = nil
        },
        onCancel: { artifactToDelete = nil }
      )
      .premiumConfirmationPresentation(initialFraction: 0.48)
    }
  }

  @ViewBuilder private var cloudStatus: some View {
    switch store.cloudStatus {
    case .localOnly:
      Label("Saved on this iPhone", systemImage: "iphone")
    case .connecting:
      ProgressView("Connecting to private backup…")
    case .synced(let date):
      Label("Firebase backup synced \(date.formatted(.relative(presentation: .named)))", systemImage: "checkmark.icloud")
    case .failed(let message):
      Label(message, systemImage: "exclamationmark.icloud").foregroundStyle(.orange)
    }
  }
}

private struct AIArtifactDetailView: View {
  let artifact: SavedAIArtifact
  @State private var copied = false

  var body: some View {
    List {
      Section {
        LabeledContent("Generated", value: artifact.createdAt.formatted(date: .abbreviated, time: .shortened))
        if let provider = artifact.provider {
          LabeledContent("AI route") { AIRouteBadge(provider: provider) }
        }
      }
      if !artifact.previewLines.isEmpty {
        Section("Result") {
          ForEach(Array(artifact.previewLines.enumerated()), id: \.offset) { _, line in
            Text(line).textSelection(.enabled)
          }
        }
      }
      Section {
        Button(copied ? "Copied" : "Copy complete result", systemImage: copied ? "checkmark" : "doc.on.doc") {
          UIPasteboard.general.string = artifact.outputJSON
          copied = true
        }
      }
    }
    .scrollContentBackground(.hidden)
    .background(Theme.paper)
    .navigationTitle(artifact.action.title)
    .navigationBarTitleDisplayMode(.inline)
  }
}

struct AIRouteBadge: View {
  let provider: ProductInsightSource

  var body: some View {
    Label(provider.title, systemImage: provider.systemImage)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(provider == .onDeviceAI ? Color.green : Color.blue)
      .accessibilityIdentifier("ai.route.\(provider.rawValue)")
  }
}
