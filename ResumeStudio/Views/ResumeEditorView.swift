import SwiftUI

struct ResumeEditorView: View {
    @EnvironmentObject private var store: ResumeStore
    @State private var showPreview = false
    @State private var pendingReset: ResetChoice?

    var body: some View {
        NavigationStack {
            Form {
                personalSection
                profileSection
                competenciesSection
                experienceSection
                educationSection
                referencesSection
                appearanceSection

                Section {
                    Label("Your draft is saved automatically on this device.", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let error = store.lastSaveError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Resume Studio")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Load Mandisa Sample", systemImage: "doc.text") {
                            pendingReset = .sample
                        }
                        Button("Start Blank Resume", systemImage: "doc.badge.plus") {
                            pendingReset = .blank
                        }
                    } label: {
                        Label("Draft", systemImage: "ellipsis.circle")
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    EditButton()
                    Button {
                        showPreview = true
                    } label: {
                        Label("Preview", systemImage: "doc.richtext")
                    }
                }
            }
            .navigationDestination(isPresented: $showPreview) {
                ResumePreviewView(document: store.document)
            }
            .alert(item: $pendingReset) { choice in
                Alert(
                    title: Text("Replace current draft?"),
                    message: Text("This replaces the resume currently saved on this device."),
                    primaryButton: .destructive(Text("Replace")) {
                        switch choice {
                        case .sample:
                            store.loadSample()
                        case .blank:
                            store.startBlankResume()
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    private var personalSection: some View {
        Section("Personal Details") {
            TextField("Full name", text: $store.document.personal.fullName)
                .textContentType(.name)
            TextField("Professional headline", text: $store.document.personal.headline)
            TextField("Phone", text: $store.document.personal.phone)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
            TextField("Email", text: $store.document.personal.email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    private var profileSection: some View {
        Section("Professional Profile") {
            TextEditor(text: $store.document.professionalProfile)
                .frame(minHeight: 130)
                .accessibilityLabel("Professional profile")
        }
    }

    private var competenciesSection: some View {
        Section("Core Competencies") {
            ForEach(store.document.competencies.indices, id: \.self) { index in
                TextField("Competency", text: $store.document.competencies[index])
            }
            .onDelete { store.document.competencies.remove(atOffsets: $0) }
            .onMove { store.document.competencies.move(fromOffsets: $0, toOffset: $1) }

            Button("Add Competency", systemImage: "plus") {
                store.document.competencies.append("")
            }
        }
    }

    private var experienceSection: some View {
        Section("Professional Experience") {
            ForEach($store.document.experience) { $entry in
                NavigationLink {
                    ExperienceEditorView(entry: $entry)
                } label: {
                    EditorRow(
                        title: entry.role.isEmpty ? "New Role" : entry.role,
                        subtitle: entry.company,
                        systemImage: "briefcase.fill"
                    )
                }
            }
            .onDelete { store.document.experience.remove(atOffsets: $0) }
            .onMove { store.document.experience.move(fromOffsets: $0, toOffset: $1) }

            Button("Add Experience", systemImage: "plus") {
                store.document.experience.append(
                    ExperienceEntry(role: "", company: "", period: "", highlights: [""])
                )
            }
        }
    }

    private var educationSection: some View {
        Section("Education") {
            ForEach($store.document.education) { $entry in
                NavigationLink {
                    EducationEditorView(entry: $entry)
                } label: {
                    EditorRow(
                        title: entry.qualification.isEmpty ? "New Qualification" : entry.qualification,
                        subtitle: entry.institution,
                        systemImage: "graduationcap.fill"
                    )
                }
            }
            .onDelete { store.document.education.remove(atOffsets: $0) }
            .onMove { store.document.education.move(fromOffsets: $0, toOffset: $1) }

            Button("Add Education", systemImage: "plus") {
                store.document.education.append(
                    EducationEntry(qualification: "", institution: "", period: "", details: "")
                )
            }
        }
    }

    private var referencesSection: some View {
        Section("References") {
            ForEach($store.document.references) { $reference in
                NavigationLink {
                    ReferenceEditorView(reference: $reference)
                } label: {
                    EditorRow(
                        title: reference.name.isEmpty ? "New Reference" : reference.name,
                        subtitle: reference.company,
                        systemImage: "person.crop.circle.fill"
                    )
                }
            }
            .onDelete { store.document.references.remove(atOffsets: $0) }
            .onMove { store.document.references.move(fromOffsets: $0, toOffset: $1) }

            Button("Add Reference", systemImage: "plus") {
                store.document.references.append(
                    ReferenceEntry(name: "", company: "", phone: "", email: "")
                )
            }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Accent Colour", selection: $store.document.accent) {
                ForEach(ResumeAccent.allCases) { accent in
                    Label {
                        Text(accent.title)
                    } icon: {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(accent.color)
                    }
                    .tag(accent)
                }
            }
        }
    }
}

private struct EditorRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } icon: {
            Image(systemName: systemImage)
        }
    }
}

private enum ResetChoice: String, Identifiable {
    case sample
    case blank

    var id: String { rawValue }
}

#Preview {
    ResumeEditorView()
        .environmentObject(ResumeStore(initialDocument: .mandisaSample))
}
