import SwiftUI

struct ReferenceEditorView: View {
    @Binding var reference: ReferenceEntry

    var body: some View {
        Form {
            Section("Reference") {
                TextField("Full name", text: $reference.name)
                    .textContentType(.name)
                TextField("Company", text: $reference.company)
                TextField("Phone", text: $reference.phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                TextField("Email", text: $reference.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .navigationTitle(reference.name.isEmpty ? "Reference" : reference.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
