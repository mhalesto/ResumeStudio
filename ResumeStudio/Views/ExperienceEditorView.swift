import SwiftUI

struct ExperienceEditorView: View {
    @Binding var entry: ExperienceEntry
    @State private var aiContext: BulletAIContext?

    var body: some View {
        Form {
            Section("Role") {
                TextField("Job title", text: $entry.role)
                TextField("Company", text: $entry.company)
                TextField("Period, for example Jan 2024 - Present", text: $entry.period)
            }

            Section("Highlights") {
                ForEach(entry.highlights.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Achievement or responsibility", text: $entry.highlights[index], axis: .vertical)
                            .lineLimit(2...5)

                        Button("Improve with AI", systemImage: "wand.and.stars") {
                            AppKeyboard.dismiss()
                            aiContext = BulletAIContext(index: index)
                        }
                        .font(.caption.weight(.semibold))
                        .disabled(entry.highlights[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .onDelete { entry.highlights.remove(atOffsets: $0) }
                .onMove { entry.highlights.move(fromOffsets: $0, toOffset: $1) }

                Button("Add Highlight", systemImage: "plus") {
                    entry.highlights.append("")
                }
            }
        }
        .supportsKeyboardDismissal()
        .navigationTitle(entry.role.isEmpty ? "Experience" : entry.role)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .sheet(item: $aiContext) { context in
            AITextSuggestionsView(
                title: "Improve Highlight",
                guidance: "Choose a rewrite. AI is instructed not to invent numbers, outcomes or responsibilities.",
                load: {
                    guard entry.highlights.indices.contains(context.index) else {
                        throw ResumeAIError.invalidResponse
                    }
                    return try await ResumeAIService.shared.improveBullet(
                        entry.highlights[context.index],
                        role: entry.role,
                        company: entry.company
                    )
                },
                onApply: { suggestion in
                    guard entry.highlights.indices.contains(context.index) else { return }
                    entry.highlights[context.index] = suggestion
                }
            )
        }
    }
}

private struct BulletAIContext: Identifiable {
    let index: Int
    var id: Int { index }
}
