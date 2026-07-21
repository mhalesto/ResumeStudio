import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Manages the supporting documents printed after the last page of the résumé.
struct ResumeAttachmentsView: View {
  @Binding var document: ResumeDocument

  @State private var pickedPhotos: [PhotosPickerItem] = []
  @State private var isImportingFile = false
  @State private var errorMessage: String?
  @State private var isPreparing = false

  /// Thumbnails are decoded once per attachment and kept here. Rebuilding them
  /// inside `body` would re-decode every payload on every keystroke in a title.
  @State private var thumbnails: [UUID: UIImage] = [:]

  private var accent: Color { document.accent.color }
  private var attachments: [ResumeAttachment] { document.attachments }

  var body: some View {
    Form {
      if attachments.isEmpty {
        emptyState
      } else {
        attachmentRows
        summarySection
      }
      addSection
    }
    .supportsKeyboardDismissal()
    .scrollContentBackground(.hidden)
    .background(Theme.paper)
    .navigationTitle("Attachments")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if !attachments.isEmpty {
        ToolbarItemGroup(placement: .topBarTrailing) {
          EditButton()
          NavigationLink {
            ResumePreviewView(document: document)
          } label: {
            Text("Preview").font(.subheadline.weight(.semibold))
          }
        }
      }
    }
    .onChange(of: pickedPhotos) { _, items in
      guard !items.isEmpty else { return }
      Task { await importPhotos(items) }
    }
    .fileImporter(
      isPresented: $isImportingFile,
      allowedContentTypes: [.pdf, .image],
      allowsMultipleSelection: true
    ) { result in
      switch result {
      case .success(let urls): Task { await importFiles(urls) }
      case .failure(let error): errorMessage = error.localizedDescription
      }
    }
    .alert(
      "Unable to Attach File",
      isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage ?? "")
    }
    .task(id: attachmentIdentity) { await refreshThumbnails() }
  }

  // MARK: - Sections

  private var emptyState: some View {
    Section {
      VStack(alignment: .leading, spacing: 10) {
        Image(systemName: "paperclip")
          .scaledFont(26, relativeTo: .title2)
          .foregroundStyle(accent)
        Text("Add certificates and supporting pages")
          .font(.headline)
          .foregroundStyle(Theme.ink)
        Text(
          "Attach a certificate, licence, transcript, portfolio page or reference letter. Each one is printed after the last page of your résumé, so the export is a single file you can send anywhere."
        )
        .font(.subheadline)
        .foregroundStyle(Theme.mutedInk)
      }
      .padding(.vertical, 8)
    }
  }

  private var attachmentRows: some View {
    Section {
      ForEach($document.attachments) { $attachment in
        NavigationLink {
          AttachmentDetailView(attachment: $attachment, accent: accent)
        } label: {
          row(for: attachment)
        }
      }
      .onDelete { offsets in
        for index in offsets {
          thumbnails[document.attachments[index].id] = nil
        }
        document.attachments.remove(atOffsets: offsets)
      }
      .onMove { document.attachments.move(fromOffsets: $0, toOffset: $1) }
    } header: {
      Text("Attached files")
    } footer: {
      Text(
        "Drag to reorder. Attachments print in this order, after your last résumé page."
      )
    }
  }

  private func row(for attachment: ResumeAttachment) -> some View {
    HStack(spacing: 12) {
      thumbnailView(for: attachment)

      VStack(alignment: .leading, spacing: 3) {
        Text(attachment.displayTitle)
          .foregroundStyle(.primary)
          .lineLimit(2)
        Text(attachment.summary)
          .font(.caption)
          .foregroundStyle(.secondary)
        if !attachment.isIncluded {
          Label("Not in this export", systemImage: "eye.slash.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.mutedInk)
        }
      }
      Spacer(minLength: 0)
    }
    .opacity(attachment.isIncluded ? 1 : 0.55)
    .padding(.vertical, 2)
  }

  private func thumbnailView(for attachment: ResumeAttachment) -> some View {
    ZStack {
      if let image = thumbnails[attachment.id] {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        Theme.muted
        Image(systemName: attachment.kind == .pdf ? "doc.richtext" : "photo")
          .foregroundStyle(Theme.mutedInk)
      }
    }
    .frame(width: 42, height: 56)
    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 5, style: .continuous)
        .strokeBorder(Theme.muted, lineWidth: 1)
    }
  }

  private var summarySection: some View {
    Section {
      LabeledContent("Pages added", value: "\(document.attachmentPageCount)")
      LabeledContent(
        "Total size",
        value: Int64(document.attachmentByteCount).formatted(.byteCount(style: .file))
      )
    } footer: {
      Text(
        "Applicant tracking systems read the résumé text, not attached artwork — keep anything essential in the résumé itself and use attachments as supporting evidence. The ATS-safe layout and the editable DOCX export leave attachments out."
      )
    }
  }

  private var addSection: some View {
    Section {
      PhotosPicker(selection: $pickedPhotos, matching: .images, photoLibrary: .shared()) {
        HStack(spacing: 10) {
          Image(systemName: "photo.on.rectangle.angled")
            .foregroundStyle(accent)
            .frame(width: 24)
          Text("Add from Photos")
        }
      }
      .disabled(isFull || isPreparing)

      Button {
        isImportingFile = true
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "folder")
            .foregroundStyle(accent)
            .frame(width: 24)
          Text("Add a PDF or image file")
        }
      }
      .disabled(isFull || isPreparing)

      if isPreparing {
        HStack(spacing: 10) {
          ProgressView()
          Text("Preparing…").foregroundStyle(Theme.mutedInk)
        }
      }
    } footer: {
      if isFull {
        Text(
          "You've reached the limit of \(ResumeAttachmentLimits.maxAttachments) attachments for one résumé. Remove one to add another."
        )
      } else {
        Text(
          "Images are resized to print resolution and PDFs keep their original pages, so your résumé file stays a sensible size to email."
        )
      }
    }
  }

  // MARK: - Machinery

  private var isFull: Bool {
    attachments.count >= ResumeAttachmentLimits.maxAttachments
      || document.attachmentByteCount >= ResumeAttachmentLimits.maxTotalBytes
  }

  /// Changes whenever a payload is added, removed or replaced — but not when a
  /// title is edited, which would otherwise redecode every thumbnail per letter.
  private var attachmentIdentity: [UUID] {
    attachments.map(\.id)
  }

  @MainActor
  private func refreshThumbnails() async {
    for attachment in attachments where thumbnails[attachment.id] == nil {
      thumbnails[attachment.id] = attachment.thumbnail()
      await Task.yield()
    }
    let live = Set(attachmentIdentity)
    thumbnails = thumbnails.filter { live.contains($0.key) }
  }

  @MainActor
  private func importPhotos(_ items: [PhotosPickerItem]) async {
    defer { pickedPhotos = [] }
    isPreparing = true
    defer { isPreparing = false }

    for item in items {
      do {
        guard let data = try await item.loadTransferable(type: Data.self) else {
          errorMessage = ResumeAttachmentError.unreadable.errorDescription
          return
        }
        // A picked photo has no filename to name it after, so number them rather
        // than leaving a list of identical rows.
        try append(data, title: String(localized: "Attachment \(attachments.count + 1)"))
      } catch let error as ResumeAttachmentError {
        errorMessage = error.errorDescription
        return
      } catch {
        errorMessage = error.localizedDescription
        return
      }
    }
  }

  @MainActor
  private func importFiles(_ urls: [URL]) async {
    isPreparing = true
    defer { isPreparing = false }

    for url in urls {
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      do {
        let data = try Data(contentsOf: url)
        try append(
          data,
          title: ResumeAttachmentImporter.suggestedTitle(fromFilename: url.lastPathComponent)
        )
      } catch let error as ResumeAttachmentError {
        errorMessage = error.errorDescription
        return
      } catch {
        errorMessage = error.localizedDescription
        return
      }
    }
  }

  @MainActor
  private func append(_ data: Data, title: String) throws {
    guard attachments.count < ResumeAttachmentLimits.maxAttachments else {
      throw ResumeAttachmentError.libraryFull
    }
    let attachment = try ResumeAttachmentImporter.make(title: title, from: data)
    guard document.canAcceptAttachment(ofSize: attachment.data.count) else {
      throw ResumeAttachmentError.noRoomLeft
    }
    document.attachments.append(attachment)
    thumbnails[attachment.id] = attachment.thumbnail()
  }
}

// MARK: - Detail

private struct AttachmentDetailView: View {
  @Binding var attachment: ResumeAttachment
  let accent: Color

  @State private var preview: UIImage?

  var body: some View {
    Form {
      Section {
        if let preview {
          Image(uiImage: preview)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .frame(maxHeight: 280)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.muted, lineWidth: 1)
            }
            .padding(.vertical, 6)
        } else {
          ProgressView().frame(maxWidth: .infinity)
        }
      }

      Section {
        TextField("Title", text: $attachment.title)
      } header: {
        Text("Title")
      } footer: {
        Text("Printed above the attachment, in small caps.")
      }

      Section {
        Toggle("Include in this résumé", isOn: $attachment.isIncluded)
          .tint(accent)
        Toggle("Print the title on the page", isOn: $attachment.showsTitleOnPage)
          .tint(accent)
      } footer: {
        Text(
          "Turn the title off for artwork that already carries its own heading. Turning the attachment off keeps the file here but leaves it out of the export — useful when you keep several versions of one résumé."
        )
      }

      Section {
        LabeledContent("Type", value: attachment.kind == .pdf ? "PDF" : "Image")
        LabeledContent(
          "Pages",
          value: "\(attachment.pageCount)")
        LabeledContent("Size", value: attachment.formattedSize)
      }
    }
    .supportsKeyboardDismissal()
    .scrollContentBackground(.hidden)
    .background(Theme.paper)
    .navigationTitle(attachment.displayTitle)
    .navigationBarTitleDisplayMode(.inline)
    .task { preview = attachment.thumbnail(maxDimension: 900) }
  }
}

#Preview {
  NavigationStack {
    ResumeAttachmentsView(document: .constant(.example))
  }
}
