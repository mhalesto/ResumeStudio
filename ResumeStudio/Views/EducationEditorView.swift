import SwiftUI

struct EducationEditorView: View {
    @Binding var entry: EducationEntry

    var body: some View {
        Form {
            Section("Qualification") {
                TextField("Degree or qualification", text: $entry.qualification, axis: .vertical)
                TextField("Institution", text: $entry.institution)
                TextField("Period, for example 2020 - 2023", text: $entry.period)
            }

            Section("Additional Details") {
                TextEditor(text: $entry.details)
                    .frame(minHeight: 100)
                    .accessibilityLabel("Education details")
            }
        }
        .supportsKeyboardDismissal()
        .navigationTitle(entry.qualification.isEmpty ? "Education" : entry.qualification)
        .navigationBarTitleDisplayMode(.inline)
    }
}
