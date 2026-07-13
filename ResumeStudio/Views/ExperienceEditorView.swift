import SwiftUI

struct ExperienceEditorView: View {
    @Binding var entry: ExperienceEntry

    var body: some View {
        Form {
            Section("Role") {
                TextField("Job title", text: $entry.role)
                TextField("Company", text: $entry.company)
                TextField("Period, for example Jan 2024 - Present", text: $entry.period)
            }

            Section("Highlights") {
                ForEach(entry.highlights.indices, id: \.self) { index in
                    TextField("Achievement or responsibility", text: $entry.highlights[index], axis: .vertical)
                        .lineLimit(2...5)
                }
                .onDelete { entry.highlights.remove(atOffsets: $0) }
                .onMove { entry.highlights.move(fromOffsets: $0, toOffset: $1) }

                Button("Add Highlight", systemImage: "plus") {
                    entry.highlights.append("")
                }
            }
        }
        .navigationTitle(entry.role.isEmpty ? "Experience" : entry.role)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
    }
}
