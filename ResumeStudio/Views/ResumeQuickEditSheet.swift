import PhotosUI
import SwiftUI

/// The editor a double tap on the preview opens: whatever was tapped, and only
/// that, with the input it actually needs — a photo picker for the portrait, a
/// paragraph for the profile, a set of fields for a role.
struct ResumeQuickEditSheet: View {
  let target: ResumeQuickEditTarget
  let accent: Color
  let onSave: (ResumeDocument) -> Void

  @State private var draft: ResumeDocument
  @State private var pickedPhoto: PhotosPickerItem?
  @State private var photoError: String?
  @FocusState private var focusedField: String?
  @Environment(\.dismiss) private var dismiss

  init(
    document: ResumeDocument,
    target: ResumeQuickEditTarget,
    accent: Color,
    onSave: @escaping (ResumeDocument) -> Void
  ) {
    self.target = target
    self.accent = accent
    self.onSave = onSave
    _draft = State(initialValue: document)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          editor
          if let photoError {
            Label(photoError, systemImage: "exclamationmark.triangle.fill")
              .font(.caption).foregroundStyle(.red)
          }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 20)
      }
      .scrollDismissesKeyboard(.interactively)
      footer
    }
    .background(Theme.paper)
    .task { focusFirstField() }
    .onChange(of: pickedPhoto) { _, item in
      Task { await loadPhoto(item) }
    }
  }

  // MARK: - Chrome

  private var header: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: target.systemImage)
        .font(.system(size: 21, weight: .semibold))
        .foregroundStyle(accent)
        .frame(width: 50, height: 50)
        .background(accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 15, style: .continuous)
            .strokeBorder(accent.opacity(0.22))
        }
      VStack(alignment: .leading, spacing: 3) {
        Text(target.title).font(.title2.bold()).foregroundStyle(Theme.ink)
        Text(target.prompt).font(.subheadline).foregroundStyle(Theme.mutedInk)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 22)
    // Clear of the drag indicator, which the title otherwise sits right under.
    .padding(.top, 26)
    .padding(.bottom, 20)
  }

  private var footer: some View {
    VStack(spacing: 12) {
      Button {
        onSave(draft)
        dismiss()
      } label: {
        Text("Save")
          .font(.headline)
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
          .background(accent, in: Capsule())
      }
      .buttonStyle(.plain)

      Button("Cancel") { dismiss() }
        .font(.subheadline.bold())
        .foregroundStyle(Theme.mutedInk)
    }
    .padding(.horizontal, 22)
    .padding(.top, 14)
    .padding(.bottom, 16)
    .background(.ultraThinMaterial)
  }

  // MARK: - Editors

  @ViewBuilder
  private var editor: some View {
    switch target {
    case .photo:
      photoEditor
    case .name:
      card {
        field("Full name", text: $draft.personal.fullName, key: "name")
      }
    case .headline:
      card {
        field("Job title", text: $draft.personal.headline, key: "headline")
      }
    case .contact:
      card {
        field("Phone", text: $draft.personal.phone, key: "phone", keyboard: .phonePad)
        Divider()
        field("Email", text: $draft.personal.email, key: "email", keyboard: .emailAddress)
      }
    case .profile:
      card {
        paragraph("Summary", text: $draft.professionalProfile, key: "profile", minHeight: 150)
      }
    case .competencies:
      listEditor(
        title: "Skills", addTitle: "Add a skill", placeholder: "Skill",
        items: $draft.competencies)
    case .experience(let id):
      if let index = draft.experience.firstIndex(where: { $0.id == id }) {
        card {
          field("Job title", text: $draft.experience[index].role, key: "role")
          Divider()
          field("Company", text: $draft.experience[index].company, key: "company")
          Divider()
          field("Dates", text: $draft.experience[index].period, key: "period")
        }
        listEditor(
          title: "What you did", addTitle: "Add a bullet", placeholder: "Achievement",
          items: $draft.experience[index].highlights)
      }
    case .education(let id):
      if let index = draft.education.firstIndex(where: { $0.id == id }) {
        card {
          field("Qualification", text: $draft.education[index].qualification, key: "qualification")
          Divider()
          field("Institution", text: $draft.education[index].institution, key: "institution")
          Divider()
          field("Dates", text: $draft.education[index].period, key: "eduPeriod")
        }
        card {
          paragraph("Details", text: $draft.education[index].details, key: "details", minHeight: 84)
        }
      }
    case .reference(let id):
      if let index = draft.references.firstIndex(where: { $0.id == id }) {
        card {
          field("Name", text: $draft.references[index].name, key: "refName")
          Divider()
          field("Company", text: $draft.references[index].company, key: "refCompany")
          Divider()
          field("Phone", text: $draft.references[index].phone, key: "refPhone", keyboard: .phonePad)
          Divider()
          field(
            "Email", text: $draft.references[index].email, key: "refEmail",
            keyboard: .emailAddress)
        }
      }
    case .additional(let id):
      if let index = draft.additionalSections.firstIndex(where: { $0.id == id }) {
        card {
          field("Section heading", text: $draft.additionalSections[index].title, key: "sectionTitle")
        }
        listEditor(
          title: "Items", addTitle: "Add an item", placeholder: "Item",
          items: $draft.additionalSections[index].items)
      }
    }
  }

  private var photoEditor: some View {
    VStack(spacing: 16) {
      Group {
        if let image = draft.croppedPhotoImage {
          Image(uiImage: image).resizable().scaledToFill()
        } else {
          ZStack {
            accent.opacity(0.12)
            Text(draft.initials)
              .font(.system(size: 46, weight: .semibold, design: .rounded))
              .foregroundStyle(accent)
          }
        }
      }
      .frame(width: 148, height: 148)
      .clipShape(Circle())
      .overlay { Circle().strokeBorder(accent.opacity(0.30), lineWidth: 3) }
      .frame(maxWidth: .infinity)

      PhotosPicker(selection: $pickedPhoto, matching: .images, photoLibrary: .shared()) {
        Label(
          draft.photo == nil ? "Choose a photo" : "Replace photo",
          systemImage: "photo.on.rectangle.angled"
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(accent)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(accent.opacity(0.10), in: Capsule())
      }

      if draft.photo != nil {
        Button {
          draft.photo = nil
          draft.photoCrop = nil
        } label: {
          Label("Remove photo", systemImage: "trash")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.red)
        }
        .buttonStyle(.plain)

        Text("Reframing lives in the editor, where you can drag and zoom the portrait.")
          .font(.caption)
          .foregroundStyle(Theme.mutedInk)
          .multilineTextAlignment(.center)
      }
    }
  }

  // MARK: - Building blocks

  private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 0) { content() }
      .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
          .strokeBorder(accent.opacity(0.18))
      }
  }

  private func field(
    _ label: LocalizedStringKey,
    text: Binding<String>,
    key: String,
    keyboard: UIKeyboardType = .default
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(.caption2.weight(.semibold))
        .tracking(0.6)
        .foregroundStyle(accent)
      TextField("", text: text)
        .font(.body)
        .foregroundStyle(Theme.ink)
        .keyboardType(keyboard)
        .textInputAutocapitalization(keyboard == .emailAddress ? .never : .sentences)
        .autocorrectionDisabled(keyboard == .emailAddress)
        .focused($focusedField, equals: key)
    }
    .padding(.horizontal, 15)
    .padding(.vertical, 12)
  }

  private func paragraph(
    _ label: LocalizedStringKey,
    text: Binding<String>,
    key: String,
    minHeight: CGFloat
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(.caption2.weight(.semibold))
        .tracking(0.6)
        .foregroundStyle(accent)
      TextEditor(text: text)
        .font(.body)
        .foregroundStyle(Theme.ink)
        .scrollContentBackground(.hidden)
        .frame(minHeight: minHeight)
        .focused($focusedField, equals: key)
    }
    .padding(.horizontal, 15)
    .padding(.vertical, 12)
  }

  private func listEditor(
    title: LocalizedStringKey,
    addTitle: LocalizedStringKey,
    placeholder: LocalizedStringKey,
    items: Binding<[String]>
  ) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(Theme.mutedInk)
      card {
        ForEach(Array(items.wrappedValue.indices), id: \.self) { index in
          if index > 0 { Divider().padding(.leading, 15) }
          HStack(spacing: 10) {
            Circle().fill(accent.opacity(0.55)).frame(width: 6, height: 6)
            TextField(placeholder, text: items[index], axis: .vertical)
              .font(.subheadline)
              .foregroundStyle(Theme.ink)
              .focused($focusedField, equals: "item-\(index)")
            Button {
              items.wrappedValue.remove(at: index)
              focusedField = nil
            } label: {
              Image(systemName: "minus.circle.fill")
                .font(.system(size: 17))
                .foregroundStyle(Theme.mutedInk.opacity(0.6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove")
          }
          .padding(.horizontal, 15)
          .padding(.vertical, 11)
        }
        if items.wrappedValue.isEmpty {
          Text("Nothing here yet.")
            .font(.subheadline)
            .foregroundStyle(Theme.mutedInk)
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
        }
      }
      Button {
        items.wrappedValue.append("")
        focusedField = "item-\(items.wrappedValue.count - 1)"
      } label: {
        Label(addTitle, systemImage: "plus.circle.fill")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(accent)
      }
      .buttonStyle(.plain)
    }
  }

  // MARK: - Behaviour

  /// Opens straight into the field that was tapped. A quick edit that still needs
  /// a tap to start typing is not quick.
  private func focusFirstField() {
    switch target {
    case .photo: focusedField = nil
    case .name: focusedField = "name"
    case .headline: focusedField = "headline"
    case .contact: focusedField = "phone"
    case .profile: focusedField = "profile"
    case .competencies: focusedField = nil
    case .experience: focusedField = "role"
    case .education: focusedField = "qualification"
    case .reference: focusedField = "refName"
    case .additional: focusedField = "sectionTitle"
    }
  }

  private func loadPhoto(_ item: PhotosPickerItem?) async {
    guard let item else { return }
    defer { pickedPhoto = nil }
    photoError = nil
    do {
      guard let raw = try await item.loadTransferable(type: Data.self) else {
        photoError = String(
          localized: "The selected photo could not be read. Please choose a local JPG, PNG, or HEIC image.")
        return
      }
      // Downscaled and squared before it goes anywhere near the draft file.
      guard let prepared = ProfilePhoto.prepare(raw) else {
        photoError = String(
          localized: "That image format could not be prepared for your résumé. Please choose a JPG, PNG, or HEIC image.")
        return
      }
      let wasEmpty = draft.photo == nil
      draft.photo = prepared
      draft.photoCrop = nil
      if wasEmpty { draft.isPhotoVisible = true }
    } catch {
      photoError = error.localizedDescription
    }
  }
}
