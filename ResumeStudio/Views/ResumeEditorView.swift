import PhotosUI
import SwiftUI

struct ResumeEditorView: View {
  /// When set, the editor opens scrolled to this section — so "Next up" on the
  /// home screen lands you on the actual field that's missing.
  var focus: ResumeSection?

  @EnvironmentObject private var store: ResumeStore
  @State private var pickedPhoto: PhotosPickerItem?
  @State private var showCropper = false
  @State private var showProfileAI = false
  @State private var showCompetencyAI = false

  var body: some View {
    ScrollViewReader { proxy in
      Form {
        progressSection
        aiToolsSection
        personalSection
        profileSection
        competenciesSection
        experienceSection
        educationSection
        additionalSections
        referencesSection
        appearanceSection

        Section {
          Label(
            "Your draft is saved automatically on this device.",
            systemImage: "checkmark.circle.fill"
          )
          .font(.footnote)
          .foregroundStyle(Theme.mutedInk)

          if let error = store.lastSaveError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
              .font(.footnote)
              .foregroundStyle(.red)
          }
        }
      }
      .supportsKeyboardDismissal()
      .scrollContentBackground(.hidden)
      .background(Theme.paper)
      .onAppear {
        guard let focus else { return }
        // A beat, so the scroll lands after the form has laid out.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
          withAnimation(.easeInOut(duration: 0.4)) {
            proxy.scrollTo(focus, anchor: .top)
          }
        }
      }
    }
    .navigationTitle("Edit résumé")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(Theme.paper, for: .navigationBar)
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        EditButton()
        NavigationLink {
          ResumePreviewView(document: store.document)
        } label: {
          Text("Preview")
            .font(.subheadline.weight(.semibold))
        }
      }
    }
    .sheet(isPresented: $showProfileAI) {
      AITextSuggestionsView(
        title: "Professional Profile",
        guidance: "Choose a version to replace the current profile. Review every factual claim before exporting.",
        load: { try await ResumeAIService.shared.writeProfile(for: store.document) },
        onApply: { store.document.professionalProfile = $0 }
      )
    }
    .sheet(isPresented: $showCompetencyAI) {
      AICompetencySuggestionsView(document: store.document) { suggestions in
        let existing = Set(store.document.competencies.map { $0.lowercased() })
        store.document.competencies.append(
          contentsOf: suggestions.filter { !existing.contains($0.lowercased()) }
        )
      }
    }
  }

  private var accent: Color { store.document.accent.color }

  // MARK: - Progress

  private var progressSection: some View {
    Section {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Text("\(store.document.completionPercentage)% complete")
            .font(.headline)
            .foregroundStyle(Theme.ink)
          Spacer()
          Text(remainingSummary)
            .font(.caption)
            .foregroundStyle(Theme.mutedInk)
        }

        GeometryReader { geometry in
          ZStack(alignment: .leading) {
            Capsule().fill(Theme.muted)
            Capsule()
              .fill(accent)
              .frame(width: geometry.size.width * store.document.completion)
          }
        }
        .frame(height: 6)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: store.document.completion)
      }
      .padding(.vertical, 4)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        "\(store.document.completionPercentage) percent complete. \(remainingSummary)")
    }
  }

  private var remainingSummary: String {
    let remaining = store.document.incompleteSections.count
    return remaining == 0
      ? "Ready to export" : "\(remaining) section\(remaining == 1 ? "" : "s") to go"
  }

  private var aiToolsSection: some View {
    Section {
      NavigationLink(value: HomeRoute.jobTargeting) {
        Label {
          VStack(alignment: .leading, spacing: 3) {
            Text("Target a job")
              .foregroundStyle(.primary)
            Text("Review the match and create a tailored draft")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        } icon: {
          Image(systemName: "wand.and.stars")
            .foregroundStyle(accent)
        }
      }
    } header: {
      Text("AI career tools")
    } footer: {
      Text("AI suggestions never replace your draft until you approve them.")
    }
  }

  // MARK: - Sections

  private var personalSection: some View {
    Section {
      photoRow

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
    } header: {
      header(for: .personal)
    } footer: {
      Text(
        "Your photo is optional, and every template has a place for it. The photo-led ones — \(photoTemplateNames) — build their header around it. It never leaves this device."
      )
    }
    .id(ResumeSection.personal)
  }

  /// The portrait: a circle ringed in the accent colour, showing the exact crop
  /// the PDF will draw. Tapping it re-frames.
  private var photoRow: some View {
    let hasPhoto = store.document.photo != nil
    return HStack(spacing: 16) {
      Button {
        if store.document.photo != nil { showCropper = true }
      } label: {
        ZStack {
          if let image = store.document.croppedPhotoImage {
            Image(uiImage: image)
              .resizable()
              .scaledToFill()
          } else {
            accent.opacity(0.14)
            Text(store.document.initials)
              .font(.system(size: 22, weight: .bold))
              .foregroundStyle(accent)
          }
        }
        .frame(width: 68, height: 68)
        .clipShape(Circle())
        .overlay {
          Circle().strokeBorder(accent, lineWidth: 3)
        }
      }
      .buttonStyle(.plain)
      .disabled(!hasPhoto)
      .accessibilityLabel(hasPhoto ? "Profile photo. Reframe" : "No photo")

      VStack(alignment: .leading, spacing: 10) {
        PhotosPicker(
          selection: $pickedPhoto,
          matching: .images,
          photoLibrary: .shared()
        ) {
          // A plain HStack, not a Label: in a Form, Label's icon gets pushed into
          // the list's alignment gutter and the row falls apart.
          HStack(spacing: 6) {
            Image(systemName: "camera.fill")
            Text(hasPhoto ? "Change photo" : "Add photo")
          }
          .font(.subheadline.weight(.semibold))
        }

        if hasPhoto {
          Button {
            showCropper = true
          } label: {
            HStack(spacing: 6) {
              Image(systemName: "crop")
              Text("Reframe")
            }
            .font(.subheadline.weight(.semibold))
          }
          .buttonStyle(.plain)
          .foregroundStyle(accent)

          Button {
            store.document.photo = nil
            store.document.photoCrop = nil
          } label: {
            HStack(spacing: 6) {
              Image(systemName: "trash")
              Text("Remove")
            }
            .font(.subheadline)
            .foregroundStyle(.red)
          }
          .buttonStyle(.plain)
        }
      }

      Spacer(minLength: 0)
    }
    .padding(.vertical, 6)
    .onChange(of: pickedPhoto) { _, item in
      Task { await load(item) }
    }
    .sheet(isPresented: $showCropper) {
      if let image = store.document.photoImage {
        PhotoCropView(image: image, crop: store.document.photoCrop, accent: accent) { crop in
          store.document.photoCrop = crop
        }
      }
    }
  }

  private func load(_ item: PhotosPickerItem?) async {
    guard let item,
      let raw = try? await item.loadTransferable(type: Data.self),
      // Downscaled and squared before it goes anywhere near the draft file.
      let prepared = ProfilePhoto.prepare(raw)
    else { return }
    store.document.photo = prepared
  }

  /// The photo-led templates, which build their whole header around the portrait.
  /// Every other template takes one too — it just closes the space up without one.
  private var photoTemplateNames: String {
    ResumeTemplate.allCases
      .filter(\.isPhotoLed)
      .map(\.title)
      .formatted(.list(type: .and))
  }

  private var profileSection: some View {
    Section {
      TextEditor(text: $store.document.professionalProfile)
        .frame(minHeight: 130)
        .accessibilityLabel("Professional profile")

      Button("Write with AI", systemImage: "wand.and.stars") {
        AppKeyboard.dismiss()
        showProfileAI = true
      }
    } header: {
      header(for: .profile)
    } footer: {
      if store.document.professionalProfile.isBlank {
        Text(ResumeSection.profile.prompt)
      }
    }
    .id(ResumeSection.profile)
  }

  private var competenciesSection: some View {
    Section {
      ForEach(store.document.competencies.indices, id: \.self) { index in
        TextField("Competency", text: $store.document.competencies[index])
      }
      .onDelete { store.document.competencies.remove(atOffsets: $0) }
      .onMove { store.document.competencies.move(fromOffsets: $0, toOffset: $1) }

      Button("Add Competency", systemImage: "plus") {
        store.document.competencies.append("")
      }

      Button("Suggest with AI", systemImage: "sparkles") {
        AppKeyboard.dismiss()
        showCompetencyAI = true
      }
    } header: {
      header(for: .competencies)
    }
    .id(ResumeSection.competencies)
  }

  private var experienceSection: some View {
    Section {
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
    } header: {
      header(for: .experience)
    }
    .id(ResumeSection.experience)
  }

  private var educationSection: some View {
    Section {
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
    } header: {
      header(for: .education)
    }
    .id(ResumeSection.education)
  }

  private var additionalSections: some View {
    Section("Additional sections") {
      ForEach($store.document.additionalSections) { $section in
        DisclosureGroup {
          TextField("Section title", text: $section.title)
          ForEach(section.items.indices, id: \.self) { index in
            TextField("Item", text: $section.items[index], axis: .vertical)
              .lineLimit(1...5)
          }
          .onDelete { section.items.remove(atOffsets: $0) }

          Button("Add item", systemImage: "plus") {
            section.items.append("")
          }
        } label: {
          Label(section.title.isBlank ? "Untitled section" : section.title, systemImage: "square.stack.3d.up.fill")
        }
      }
      .onDelete { store.document.additionalSections.remove(atOffsets: $0) }
      .onMove { store.document.additionalSections.move(fromOffsets: $0, toOffset: $1) }

      Menu("Add section", systemImage: "plus") {
        ForEach(["Projects", "Certifications", "Languages", "Awards", "Volunteering", "Publications"], id: \.self) { title in
          Button(title) {
            store.document.additionalSections.append(
              ResumeAdditionalSection(title: title, items: [""])
            )
          }
        }
        Button("Custom section") {
          store.document.additionalSections.append(
            ResumeAdditionalSection(title: "", items: [""])
          )
        }
      }
    }
  }

  private var referencesSection: some View {
    Section {
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
    } header: {
      header(for: .references)
    }
    .id(ResumeSection.references)
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
            .foregroundStyle(accent)
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
            .fill(accent)
            .frame(width: 20, height: 20)
            .overlay {
              Circle().stroke(.white.opacity(0.8), lineWidth: 2)
            }
        }
      }
    }
  }

  /// Section headers carry a tick once the section has real content, so the
  /// remaining work is visible at a glance while scrolling.
  private func header(for section: ResumeSection) -> some View {
    let done = store.document.isComplete(section)
    return HStack(spacing: 6) {
      Image(systemName: done ? "checkmark.circle.fill" : "circle")
        .foregroundStyle(done ? accent : Theme.mutedInk.opacity(0.5))
      Text(section.title)
      Spacer()
    }
    .font(.footnote.weight(.semibold))
    .accessibilityLabel("\(section.title), \(done ? "complete" : "incomplete")")
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
