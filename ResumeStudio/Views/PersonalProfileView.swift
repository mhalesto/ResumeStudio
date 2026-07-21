import SwiftUI

/// The hosted personal CV page: claim a permanent vanity handle, publish the
/// current résumé behind it, and manage or withdraw the live page. Free pages
/// carry a "Made with ResumeStudio" footer; Go and Pro remove it.
struct PersonalProfileView: View {
  @EnvironmentObject private var store: ResumeStore
  @EnvironmentObject private var purchases: PurchaseManager
  @EnvironmentObject private var profileStore: PersonalProfileStore
  @Environment(\.openURL) private var openURL

  @State private var handle = ""
  @State private var displayName = ""
  @State private var headline = ""
  @State private var location = ""
  @State private var links: [ProfileLink] = []
  @State private var searchable = true

  @State private var handleState: HandleState = .idle
  @State private var handleCheckTask: Task<Void, Never>?

  @State private var isPublishing = false
  @State private var isEditing = false
  @State private var errorMessage: String?
  @State private var shareItem: ShareItem?
  @State private var didPrime = false

  enum HandleState: Equatable { case idle, checking, available, taken, invalid }
  private struct ShareItem: Identifiable { let id = UUID(); let url: URL }

  private var accent: Color { store.document.accent.color }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        if profileStore.isLoading && profileStore.profile == nil {
          loadingCard
        } else if let profile = profileStore.profile, !isEditing {
          publishedState(profile)
        } else {
          editor
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(Theme.paper.ignoresSafeArea())
    .navigationTitle("CV page")
    .navigationBarTitleDisplayMode(.inline)
    .task {
      if profileStore.profile == nil { await profileStore.load() }
      prime()
    }
    .sheet(item: $shareItem) { item in ShareSheet(activityItems: [item.url]) }
  }

  // MARK: - Loading

  private var loadingCard: some View {
    HStack(spacing: 12) {
      ProgressView()
      Text("Checking your page…").foregroundStyle(Theme.mutedInk)
    }
    .frame(maxWidth: .infinity).padding(.vertical, 40).cardSurface()
  }

  // MARK: - Published

  @ViewBuilder private func publishedState(_ profile: PersonalProfile) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 12) {
        ZStack {
          Circle().fill(accent.opacity(0.16))
          Image(systemName: "globe").font(.title3.weight(.semibold)).foregroundStyle(accent)
        }.frame(width: 46, height: 46)
        VStack(alignment: .leading, spacing: 2) {
          Text("Your page is live").font(.headline).foregroundStyle(Theme.ink)
          Text(profile.searchable ? "Public · findable on search" : "Public · hidden from search")
            .font(.caption).foregroundStyle(Theme.mutedInk)
        }
        Spacer()
      }

      if let url = profile.url {
        VStack(alignment: .leading, spacing: 10) {
          Text(prettyURL(url)).font(.callout.weight(.semibold)).foregroundStyle(accent)
            .lineLimit(1).truncationMode(.middle)
          HStack(spacing: 10) {
            actionChip("Open", "safari") { openURL(url) }
            actionChip("Copy", "doc.on.doc") { UIPasteboard.general.url = url }
            actionChip("Share", "square.and.arrow.up") { shareItem = ShareItem(url: url) }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14).cardSurface()
      }
    }
    .padding(16).cardSurface()

    if profile.branded {
      brandingUpsell
    }

    VStack(spacing: 10) {
      primaryButton(isPublishing ? "Updating…" : "Update page with current résumé", isLoading: isPublishing) {
        publish()
      }
      Button {
        isEditing = true
      } label: {
        Text("Edit details & handle").frame(maxWidth: .infinity)
      }
      .buttonStyle(.bordered).tint(accent).controlSize(.large)

      Button(role: .destructive) {
        withdraw()
      } label: {
        Text("Withdraw page").frame(maxWidth: .infinity)
      }
      .buttonStyle(.bordered).controlSize(.large)
    }

    errorLabel
  }

  // MARK: - Editor

  private var editor: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 6) {
        Text("A permanent home for your résumé")
          .displayFont(26).foregroundStyle(Theme.ink)
        Text("Claim a short link you can put on LinkedIn, in an email signature, or on a business card. It always shows your latest résumé — and, unlike a trackable link, it never expires.")
          .font(.subheadline).foregroundStyle(Theme.mutedInk)
      }

      handleField

      labelledField("Your name", text: $displayName, placeholder: "Jane Doe")
      labelledField("Headline", text: $headline, placeholder: "Product Designer · Fintech")
      labelledField("Location", text: $location, placeholder: "Cape Town, South Africa")

      linksEditor

      Toggle(isOn: $searchable) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Show up in search results").foregroundStyle(Theme.ink)
          Text("Let recruiters find this page when they search your name. Turn off to keep it link-only.")
            .font(.caption).foregroundStyle(Theme.mutedInk)
        }
      }
      .tint(accent).padding(14).cardSurface()

      brandingNote

      primaryButton(isPublishing ? "Publishing…" : (profileStore.profile == nil ? "Publish page" : "Save changes"),
                    isLoading: isPublishing, disabled: !canPublish) {
        publish()
      }

      if profileStore.profile != nil {
        Button("Cancel") { isEditing = false; prime(force: true) }
          .frame(maxWidth: .infinity)
      }

      errorLabel
    }
  }

  private var handleField: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Your link").font(.footnote.weight(.semibold)).foregroundStyle(Theme.mutedInk)
      HStack(spacing: 4) {
        Text("…/p/").font(.callout.monospaced()).foregroundStyle(Theme.mutedInk)
        TextField("your-name", text: $handle)
          .font(.callout.monospaced())
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .onChange(of: handle) { _, newValue in
            let normalized = Self.normalizeHandle(newValue)
            if normalized != newValue { handle = normalized }
            scheduleHandleCheck()
          }
        handleStatusIcon
      }
      .padding(12).cardSurface()
      if let hint = handleHint {
        Text(hint).font(.caption).foregroundStyle(handleState == .available ? .green : Theme.mutedInk)
      }
    }
  }

  /// Hidden from VoiceOver on purpose: `handleHint` states the same result in
  /// words directly beneath the field, so naming the icon too would announce the
  /// availability twice on the way to the next control.
  @ViewBuilder private var handleStatusIcon: some View {
    switch handleState {
    case .checking: ProgressView().controlSize(.small)
    case .available:
      Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        .accessibilityHidden(true)
    case .taken, .invalid:
      Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        .accessibilityHidden(true)
    case .idle: EmptyView()
    }
  }

  private var handleHint: String? {
    switch handleState {
    case .available: "Available"
    case .taken: "That handle is taken — try another."
    case .invalid: "3–30 letters, numbers and single hyphens."
    case .checking, .idle: handle.isEmpty ? "3–30 letters, numbers and single hyphens." : nil
    }
  }

  private var linksEditor: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Links").font(.footnote.weight(.semibold)).foregroundStyle(Theme.mutedInk)
        Spacer()
        if links.count < 6 {
          Button("Add", systemImage: "plus") { links.append(ProfileLink()) }
            .font(.caption.weight(.semibold)).tint(accent)
        }
      }
      if links.isEmpty {
        Text("Add up to six — LinkedIn, a portfolio, GitHub.")
          .font(.caption).foregroundStyle(Theme.mutedInk)
      }
      ForEach($links) { $link in
        VStack(spacing: 8) {
          HStack {
            TextField("Label (e.g. LinkedIn)", text: $link.label)
            Button {
              links.removeAll { $0.id == link.id }
            } label: {
              Image(systemName: "minus.circle.fill").foregroundStyle(Theme.mutedInk)
                .accessibilityLabel(link.label.isBlank ? "Remove link" : "Remove \(link.label) link")
            }
          }
          TextField("https://…", text: $link.url)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .keyboardType(.URL)
        }
        .padding(12).cardSurface()
      }
    }
  }

  private var brandingNote: some View {
    Group {
      if purchases.plan == .free {
        Label("Free pages include a small \u{201C}Made with ResumeStudio\u{201D} footer. Go or Pro removes it.",
              systemImage: "sparkles")
          .font(.caption).foregroundStyle(Theme.mutedInk)
      }
    }
  }

  private var brandingUpsell: some View {
    Button {
      purchases.requestPlans()
    } label: {
      HStack(spacing: 12) {
        Image(systemName: "sparkles").foregroundStyle(accent)
        VStack(alignment: .leading, spacing: 2) {
          Text("Remove the ResumeStudio footer").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
          Text("Go or Pro publishes a clean, unbranded page.").font(.caption).foregroundStyle(Theme.mutedInk)
        }
        Spacer()
        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.mutedInk)
      }
      .padding(14).cardSurface()
    }
    .buttonStyle(.plain)
  }

  // MARK: - Shared bits

  private func labelledField(_ title: String, text: Binding<String>, placeholder: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Theme.mutedInk)
      TextField(placeholder, text: text).padding(12).cardSurface()
    }
  }

  private func actionChip(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Label(title, systemImage: icon).font(.caption.weight(.semibold))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(accent.opacity(0.12), in: Capsule()).foregroundStyle(accent)
    }
    .buttonStyle(.plain)
  }

  private func primaryButton(_ title: String, isLoading: Bool, disabled: Bool = false,
                             action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack {
        if isLoading { ProgressView().tint(.white) }
        Text(title).fontWeight(.semibold)
      }
      .frame(maxWidth: .infinity).padding(.vertical, 14)
      .background(disabled ? AnyShapeStyle(Theme.muted) : AnyShapeStyle(accent), in: Capsule())
      .foregroundStyle(.white)
    }
    .disabled(disabled || isLoading)
  }

  @ViewBuilder private var errorLabel: some View {
    if let errorMessage {
      Text(errorMessage).font(.caption).foregroundStyle(.red)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  // MARK: - Logic

  private var cleanedLinks: [ProfileLink] {
    links.compactMap { link in
      let label = link.label.trimmingCharacters(in: .whitespacesAndNewlines)
      var url = link.url.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !label.isEmpty, !url.isEmpty else { return nil }
      if !url.lowercased().hasPrefix("http") { url = "https://" + url }
      return ProfileLink(label: label, url: url)
    }
  }

  private var canPublish: Bool {
    PersonalProfile.isValidHandle(handle) && handleState != .taken && handleState != .invalid
      && !displayName.trimmingCharacters(in: .whitespaces).isEmpty
  }

  private func prime(force: Bool = false) {
    guard !didPrime || force else { return }
    didPrime = true
    if let profile = profileStore.profile {
      handle = profile.handle
      displayName = profile.displayName
      headline = profile.headline
      location = profile.location
      links = profile.links
      searchable = profile.searchable
      handleState = .available
    } else {
      if displayName.isEmpty { displayName = store.document.personal.fullName }
      if headline.isEmpty { headline = store.document.personal.headline }
      if handle.isEmpty {
        handle = PersonalProfile.suggestedHandle(from: store.document.personal.fullName)
        scheduleHandleCheck()
      }
    }
  }

  private func scheduleHandleCheck() {
    handleCheckTask?.cancel()
    let value = handle
    if value.isEmpty { handleState = .idle; return }
    guard PersonalProfile.isValidHandle(value) else { handleState = .invalid; return }
    // A handle the user already owns is theirs to keep.
    if value == profileStore.profile?.handle { handleState = .available; return }
    handleState = .checking
    handleCheckTask = Task {
      try? await Task.sleep(nanoseconds: 450_000_000)
      if Task.isCancelled { return }
      do {
        let available = try await PersonalProfileService().checkHandle(value)
        if Task.isCancelled || handle != value { return }
        handleState = available ? .available : .taken
      } catch {
        if !Task.isCancelled { handleState = .idle }
      }
    }
  }

  private func publish() {
    guard PersonalProfile.isValidHandle(handle) else { return }
    isPublishing = true
    errorMessage = nil
    let document = store.document
    let publishHandle = handle
    let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    let head = headline.trimmingCharacters(in: .whitespacesAndNewlines)
    let place = location.trimmingCharacters(in: .whitespacesAndNewlines)
    let payloadLinks = cleanedLinks
    let wantsSearch = searchable
    Task {
      defer { isPublishing = false }
      do {
        await purchases.refreshEntitlements()
        let pdf = try ResumePDFRenderer.render(document: document)
        let pageImages = ResumePageRasterizer.images(fromPDF: pdf)
        let result = try await PersonalProfileService().publish(
          PersonalProfileService.PublishRequest(
            handle: publishHandle, displayName: name, headline: head, location: place,
            links: payloadLinks, searchable: wantsSearch, pdfData: pdf, pageImages: pageImages))
        profileStore.apply(PersonalProfile(
          handle: result.handle, displayName: name, headline: head, location: place,
          links: payloadLinks, searchable: result.searchable, branded: result.branded,
          pageCount: pageImages.count, hostedURL: result.hostedURL.absoluteString, updatedAt: Date()))
        isEditing = false
      } catch let error as PersonalProfileError {
        errorMessage = error.errorDescription
        if error.isHandleTaken { handleState = .taken }
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  private func withdraw() {
    isPublishing = true
    errorMessage = nil
    Task {
      defer { isPublishing = false }
      do {
        try await PersonalProfileService().unpublish()
        profileStore.apply(nil)
        isEditing = false
        didPrime = false
        prime()
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  private func prettyURL(_ url: URL) -> String {
    var text = url.absoluteString
    for prefix in ["https://", "http://"] where text.hasPrefix(prefix) {
      text.removeFirst(prefix.count)
    }
    return text
  }

  /// Keeps only handle-legal characters as the user types: lowercase, digits,
  /// and single hyphens (spaces and separators collapse to a hyphen).
  static func normalizeHandle(_ raw: String) -> String {
    var out = ""
    var lastHyphen = false
    for scalar in raw.lowercased().unicodeScalars {
      if scalar == " " || scalar == "_" || scalar == "." || scalar == "-" {
        if !out.isEmpty && !lastHyphen { out.append("-"); lastHyphen = true }
      } else if (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9") {
        out.unicodeScalars.append(scalar)
        lastHyphen = false
      }
    }
    return String(out.prefix(30))
  }
}
