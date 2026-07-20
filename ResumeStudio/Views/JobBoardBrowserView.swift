import SafariServices
import SwiftUI

/// Browsing for work, without ResumeStudio standing between the reader and the
/// board.
///
/// Boards open in `SFSafariViewController`, which shares Safari's cookies — so a
/// posting that needs a sign-in simply works, and no password is ever typed into
/// this app. Saving is the share sheet: the reader taps Share → ResumeStudio on
/// the page they are reading, and the capture screen opens already filled in.
/// Nothing is fetched or scraped behind their back.
struct JobBoardBrowserView: View {
  @EnvironmentObject private var store: ResumeStore
  @AppStorage("resumeMarketPreference") private var marketRaw = ResumeMarket.southAfrica.rawValue
  @State private var searches: [SavedJobSearch] = SavedJobSearchStore.load()
  @State private var opening: URL?
  @State private var isAddingSearch = false
  @State private var draftName = ""
  @State private var draftURL = ""
  @State private var draftError: String?

  private var market: ResumeMarket {
    ResumeMarket(rawValue: marketRaw) ?? .southAfrica
  }

  private var accent: Color { store.document.accent.color }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        howItWorks
        if !searches.isEmpty { savedSearches }
        boards
      }
      .padding(20)
      .padding(.bottom, 40)
      .frame(maxWidth: 700)
      .frame(maxWidth: .infinity)
    }
    .background(Theme.paper)
    .navigationTitle("Find jobs")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Picker("Market", selection: $marketRaw) {
          ForEach(ResumeMarket.allCases) { option in
            Text("\(option.flag) \(String(localized: option.title))").tag(option.rawValue)
          }
        }
        .pickerStyle(.menu)
      }
    }
    .sheet(item: $opening) { destination in
      SafariView(url: destination).ignoresSafeArea()
    }
    .sheet(isPresented: $isAddingSearch) { addSearchSheet }
  }

  // MARK: - Sections

  /// Said once, plainly, because the whole design rests on the reader knowing
  /// that the share sheet is the "save" button.
  private var howItWorks: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Saving a job", systemImage: "square.and.arrow.up")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Theme.ink)
      Text(
        """
        Open a board, find a role, then tap Share and choose ResumeStudio. \
        The posting comes across with it, and tailoring starts on a copy — \
        your own résumé is never changed.
        """
      )
      .font(.footnote)
      .foregroundStyle(Theme.mutedInk)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .cardSurface(radius: 18)
  }

  private var savedSearches: some View {
    VStack(alignment: .leading, spacing: 10) {
      sectionHeader("Your searches") {
        Button {
          isAddingSearch = true
        } label: {
          Image(systemName: "plus")
        }
        .accessibilityLabel("Add a search")
      }
      ForEach(searches) { search in
        Button {
          opening = SavedJobSearchStore.normalised(search.url)
        } label: {
          row(title: search.name, detail: search.host, systemImage: "bookmark.fill")
        }
        .buttonStyle(.plain)
        .contextMenu {
          Button("Remove", systemImage: "trash", role: .destructive) {
            remove(search)
          }
        }
      }
    }
  }

  private var boards: some View {
    VStack(alignment: .leading, spacing: 10) {
      sectionHeader(searches.isEmpty ? "Boards" : "More boards") {
        if searches.isEmpty {
          Button {
            isAddingSearch = true
          } label: {
            Image(systemName: "plus")
          }
          .accessibilityLabel("Add a search")
        }
      }
      ForEach(JobBoardCatalogue.boards(for: market)) { board in
        Button {
          opening = URL(string: board.url)
        } label: {
          row(
            title: board.name, detail: String(localized: board.note),
            systemImage: "safari.fill")
        }
        .buttonStyle(.plain)
      }
    }
  }

  private func sectionHeader(
    _ title: LocalizedStringKey, @ViewBuilder trailing: () -> some View
  ) -> some View {
    HStack {
      Text(title).eyebrow().foregroundStyle(Theme.mutedInk)
      Spacer()
      trailing()
    }
  }

  private func row(title: String, detail: String, systemImage: String) -> some View {
    HStack(spacing: 13) {
      Image(systemName: systemImage)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(accent)
        .frame(width: 38, height: 38)
        .background(accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 12))
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
        Text(detail).font(.caption).foregroundStyle(Theme.mutedInk).lineLimit(1)
      }
      Spacer(minLength: 6)
      Image(systemName: "arrow.up.right")
        .font(.caption.weight(.bold))
        .foregroundStyle(Theme.mutedInk)
    }
    .padding(13)
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardSurface(radius: 16)
  }

  // MARK: - Adding a search

  private var addSearchSheet: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Name", text: $draftName)
          TextField("Address", text: $draftURL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
        } header: {
          Text("Saved search")
        } footer: {
          Text(
            """
            Filter a board down to the roles you want, then paste the address \
            here to come straight back to that list.
            """
          )
        }
        if let draftError {
          Text(draftError).font(.footnote).foregroundStyle(.red)
        }
      }
      .navigationTitle("Add a search")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismissDraft() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { commitDraft() }
            .disabled(draftName.isBlank || draftURL.isBlank)
        }
      }
    }
    .presentationDetents([.medium])
  }

  private func commitDraft() {
    guard let url = SavedJobSearchStore.normalised(draftURL) else {
      draftError = String(localized: "That does not look like a web address.")
      return
    }
    searches.append(
      SavedJobSearch(
        name: draftName.trimmingCharacters(in: .whitespacesAndNewlines),
        url: url.absoluteString))
    SavedJobSearchStore.save(searches)
    dismissDraft()
  }

  private func dismissDraft() {
    isAddingSearch = false
    draftName = ""
    draftURL = ""
    draftError = nil
  }

  private func remove(_ search: SavedJobSearch) {
    searches.removeAll { $0.id == search.id }
    SavedJobSearchStore.save(searches)
  }
}

/// Safari, in a sheet. It keeps the reader's existing sign-ins because it shares
/// Safari's cookie store, and the host app cannot read the page — which is the
/// point: browsing needs no such access, and saving goes through the share sheet
/// where the reader decides.
struct SafariView: UIViewControllerRepresentable {
  let url: URL

  func makeUIViewController(context: Context) -> SFSafariViewController {
    let configuration = SFSafariViewController.Configuration()
    configuration.entersReaderIfAvailable = false
    let controller = SFSafariViewController(url: url, configuration: configuration)
    controller.dismissButtonStyle = .close
    return controller
  }

  func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

extension URL: @retroactive Identifiable {
  public var id: String { absoluteString }
}
