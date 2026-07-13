import SwiftUI

struct ResumeEditorView: View {
  @EnvironmentObject private var store: ResumeStore
  @State private var showPreview = false

  var body: some View {
    Form {
      personalSection
      profileSection
      competenciesSection
      experienceSection
      educationSection
      referencesSection
      appearanceSection

      Section {
        Label(
          "Your draft is saved automatically on this device.", systemImage: "checkmark.circle.fill"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)

        if let error = store.lastSaveError {
          Label(error, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.red)
        }
      }
    }
    .navigationTitle("Edit Resume")
    .toolbar {
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
      NavigationLink {
        AppearanceEditorView(
          template: $store.document.template,
          accent: $store.document.accent
        )
      } label: {
        HStack(spacing: 12) {
          Image(systemName: store.document.template.systemImage)
            .foregroundStyle(store.document.accent.color)
            .frame(width: 28)
          VStack(alignment: .leading, spacing: 3) {
            Text(store.document.template.title)
              .foregroundStyle(.primary)
            Text(store.document.accent.title)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Circle()
            .fill(store.document.accent.color)
            .frame(width: 20, height: 20)
            .overlay {
              Circle().stroke(.white.opacity(0.8), lineWidth: 2)
            }
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

#Preview {
  NavigationStack {
    ResumeEditorView()
      .environmentObject(ResumeStore(initialDocument: .example))
  }
}
