import SwiftUI

/// The full template catalogue, reached from "See all" on the home screen.
///
/// Choosing a look applies it immediately. A persistent action beneath the grid
/// then makes the next step explicit instead of leaving a selected card as a
/// visual dead end.
struct TemplateGalleryView: View {
  @EnvironmentObject private var store: ResumeStore
  @EnvironmentObject private var coverLetterStore: CoverLetterStore
  @EnvironmentObject private var purchases: PurchaseManager
  @State private var documentKind = TemplateDocumentKind.resume
  @State private var searchText = ""
  @State private var selectedTags: Set<TemplateStyleTag> = []
  @State private var activatedResumeTemplate: ResumeTemplate?
  @State private var activatedCoverLetterTemplate: CoverLetterTemplate?
  @State private var isEditingResume = false
  @State private var isEditingCoverLetter = false
  @State private var showsFinder = false
  @State private var favoritesOnly = false
  @State private var availableOnly = false
  @State private var atsSafeOnly = false
  @AppStorage("favoriteResumeTemplates") private var favoriteRaw = ""
  @AppStorage("recentResumeTemplates") private var recentRaw = ""

  private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 18)]
  private let previewWidth: CGFloat = 160
  private var previewHeight: CGFloat { previewWidth * 842 / 595 }

  var body: some View {
    ScrollView {
      VStack(spacing: 18) {
        Picker("Document type", selection: $documentKind) {
          ForEach(TemplateDocumentKind.allCases) { kind in
            Text(kind.title).tag(kind)
          }
        }
        .pickerStyle(.segmented)

        searchField
        if documentKind == .resume { discoveryTools }
        tagFilters
        AccentQuickPickRow(
          selection: $store.document.accent,
          canUse: { purchases.canUse($0) },
          onLocked: { purchases.requestPlans() }
        )

        if documentKind == .resume {
          resumeGrid
        } else {
          coverLetterGrid
        }
      }
      .padding(20)
    }
    .background(Theme.paper)
    .navigationTitle("Choose your look")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(Theme.paper, for: .navigationBar)
    .onChange(of: documentKind) { _, _ in
      selectedTags.removeAll()
    }
    .navigationDestination(isPresented: $isEditingResume) {
      ResumeEditorView(focus: nil)
    }
    .navigationDestination(isPresented: $isEditingCoverLetter) {
      CoverLetterEditorView()
    }
    .sheet(isPresented: $showsFinder) {
      SmartTemplateFinderView()
    }
  }

  private var discoveryTools: some View {
    VStack(spacing: 11) {
      Button {
        showsFinder = true
      } label: {
        Label("Find the best template for me", systemImage: "sparkles.rectangle.stack.fill")
          .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 12)
      }
      .buttonStyle(.borderedProminent)
      .tint(store.document.accent.color)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          discoveryChip("Favorites", icon: "star.fill", isOn: $favoritesOnly)
          discoveryChip("Available", icon: "lock.open.fill", isOn: $availableOnly)
          discoveryChip("Strict ATS", icon: "checkmark.shield.fill", isOn: $atsSafeOnly)
          if !recentTemplates.isEmpty {
            Text("Recent: \(recentTemplates.prefix(3).map(\.title).joined(separator: " · "))")
              .font(.caption).foregroundStyle(Theme.mutedInk).padding(.leading, 4)
          }
        }
      }
    }
  }

  private func discoveryChip(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
    Button { isOn.wrappedValue.toggle() } label: {
      Label(title, systemImage: icon)
        .font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 8)
    }
    .foregroundStyle(isOn.wrappedValue ? Color.white : Theme.ink)
    .background(isOn.wrappedValue ? store.document.accent.color : Theme.card, in: Capsule())
    .overlay { Capsule().strokeBorder(isOn.wrappedValue ? Color.clear : Theme.hairline) }
    .buttonStyle(.plain)
  }

  private var searchField: some View {
    HStack(spacing: 10) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(Theme.mutedInk)
      TextField("Search \(String(localized: documentKind.searchTitle))", text: $searchText)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      if !searchText.isEmpty {
        Button {
          searchText = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(Theme.mutedInk)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear search")
      }
    }
    .font(.subheadline)
    .padding(.horizontal, 14)
    .frame(height: 44)
    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(Theme.hairline, lineWidth: 1)
    }
  }

  private var tagFilters: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(availableTags) { tag in
          Button {
            withAnimation(.easeInOut(duration: 0.18)) {
              if selectedTags.contains(tag) {
                selectedTags.remove(tag)
              } else {
                selectedTags.insert(tag)
              }
            }
          } label: {
            Text(tag.title)
              .font(.caption.weight(.semibold))
              .foregroundStyle(selectedTags.contains(tag) ? Color.white : Theme.inkSoft)
              .padding(.horizontal, 14)
              .padding(.vertical, 8)
              .background(
                selectedTags.contains(tag) ? store.document.accent.color : Theme.card,
                in: Capsule()
              )
              .overlay {
                Capsule().strokeBorder(
                  selectedTags.contains(tag) ? Color.clear : Theme.hairline,
                  lineWidth: 1
                )
              }
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(selectedTags.contains(tag) ? .isSelected : [])
        }
      }
      .padding(.vertical, 1)
    }
    .contentMargins(.horizontal, 1, for: .scrollContent)
  }

  @ViewBuilder private var resumeGrid: some View {
    if filteredResumeTemplates.isEmpty {
      noResults
    } else {
      LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
        ForEach(filteredResumeTemplates) { template in
          VStack(spacing: 11) {
            ZStack(alignment: .topLeading) {
              Button {
                guard purchases.canUse(template) else {
                  purchases.requestPlans()
                  return
                }
                withAnimation(.spring(response: 0.34, dampingFraction: 0.76)) {
                  store.document.template = template
                  activatedResumeTemplate = template
                  TemplatePreferenceStore.recordRecent(template)
                  recentRaw = UserDefaults.standard.string(forKey: "recentResumeTemplates") ?? ""
                }
              } label: {
                ZStack(alignment: .topTrailing) {
                  TemplatePreviewCard(
                    template: template,
                    accent: store.document.accent,
                    isSelected: store.document.template == template,
                    photo: store.document.photo,
                    photoCrop: store.document.photoCrop,
                    isPhotoVisible: store.document.isPhotoVisible,
                    width: previewWidth
                  )
                  if !purchases.canUse(template) { PlanLockBadge().padding(8) }
                }
              }
              .buttonStyle(.plain)
              .templatePreviewShareMenu(
                template: template,
                accent: store.document.accent,
                photo: store.document.photo,
                crop: store.document.photoCrop,
                isPhotoVisible: store.document.isPhotoVisible
              )

              if store.document.template == template {
                Button {
                  TemplatePreferenceStore.toggleFavorite(template)
                  favoriteRaw = UserDefaults.standard.string(forKey: "favoriteResumeTemplates") ?? ""
                } label: {
                  Image(systemName: favoriteTemplates.contains(template) ? "star.fill" : "star")
                    .font(.caption.bold())
                    .foregroundStyle(store.document.accent.color)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(7)
                // TemplatePreviewCard also contains its title and subtitle. Anchor
                // the control to the A4 thumbnail's footer, not the full card.
                .offset(y: previewHeight - 42)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel(favoriteTemplates.contains(template) ? "Remove favorite" : "Add favorite")
              }
            }
            .scaleEffect(store.document.template == template ? 1.05 : 1, anchor: .center)
            .zIndex(store.document.template == template ? 1 : 0)

            if activatedResumeTemplate == template {
              useLookButton(title: "USE", trigger: template.id) {
                isEditingResume = true
              }
              .transition(
                .asymmetric(
                  insertion: .opacity.combined(with: .scale(scale: 0.88, anchor: .top)),
                  removal: .opacity.combined(with: .scale(scale: 0.94, anchor: .top))
                )
              )
            }
          }
        }
      }
      .sensoryFeedback(.selection, trigger: activatedResumeTemplate)
    }
  }

  @ViewBuilder private var coverLetterGrid: some View {
    if filteredCoverLetterTemplates.isEmpty {
      noResults
    } else {
      LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
        ForEach(filteredCoverLetterTemplates) { template in
          VStack(spacing: 11) {
            Button {
              guard purchases.canUse(template) else {
                purchases.requestPlans()
                return
              }
              withAnimation(.spring(response: 0.34, dampingFraction: 0.76)) {
                coverLetterStore.document.template = template
                coverLetterStore.document.accent = store.document.accent
                activatedCoverLetterTemplate = template
              }
            } label: {
              ZStack(alignment: .topTrailing) {
                CoverLetterTemplateCard(
                  template: template,
                  accent: store.document.accent,
                  isSelected: coverLetterStore.document.template == template,
                  width: 160
                )
                if !purchases.canUse(template) { PlanLockBadge().padding(8) }
              }
            }
            .buttonStyle(.plain)

            if activatedCoverLetterTemplate == template {
              useLookButton(title: "USE", trigger: template.id) {
                if coverLetterStore.document.senderName.isBlank {
                  coverLetterStore.syncContact(from: store.document)
                }
                isEditingCoverLetter = true
              }
              .transition(
                .asymmetric(
                  insertion: .opacity.combined(with: .scale(scale: 0.88, anchor: .top)),
                  removal: .opacity.combined(with: .scale(scale: 0.94, anchor: .top))
                )
              )
            }
          }
        }
      }
      .sensoryFeedback(.selection, trigger: activatedCoverLetterTemplate)
    }
  }

  private var noResults: some View {
    ContentUnavailableView(
      "No matching templates",
      systemImage: "doc.text.magnifyingglass",
      description: Text("Try another search or remove a filter.")
    )
    .frame(maxWidth: .infinity)
    .padding(.top, 48)
  }

  private func useLookButton(
    title: String,
    trigger: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Text(title)
        .font(.subheadline.weight(.bold))
        .foregroundStyle(store.document.accent.color)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(store.document.accent.color.opacity(0.06), in: Capsule())
        .overlay {
          CenterOutCapsuleOutline(color: store.document.accent.color, trigger: trigger)
        }
    }
    .buttonStyle(.plain)
    .accessibilityHint("Opens the editor with the selected template")
  }

  private var availableTags: [TemplateStyleTag] {
    TemplateStyleTag.allCases.filter { tag in
      switch documentKind {
      case .resume: ResumeTemplate.allCases.contains { $0.styleTags.contains(tag) }
      case .coverLetter: CoverLetterTemplate.allCases.contains { $0.styleTags.contains(tag) }
      }
    }
  }

  private var filteredResumeTemplates: [ResumeTemplate] {
    ResumeTemplate.allCases.filter { template in
      matchesSearch(template.title, template.subtitle, tags: template.styleTags)
        && matchesTags(template.styleTags)
        && (!favoritesOnly || favoriteTemplates.contains(template))
        && (!availableOnly || purchases.canUse(template))
        && (!atsSafeOnly || (!template.plan.hasSideColumn && !template.isPhotoLed))
    }
  }

  private var favoriteTemplates: Set<ResumeTemplate> {
    Set(favoriteRaw.split(separator: ",").compactMap { ResumeTemplate(rawValue: String($0)) })
  }

  private var recentTemplates: [ResumeTemplate] {
    recentRaw.split(separator: ",").compactMap { ResumeTemplate(rawValue: String($0)) }
  }

  private var filteredCoverLetterTemplates: [CoverLetterTemplate] {
    CoverLetterTemplate.allCases.filter { template in
      matchesSearch(template.title, String(localized: template.subtitle), tags: template.styleTags)
        && matchesTags(template.styleTags)
    }
  }

  private func matchesSearch(_ title: String, _ subtitle: String, tags: Set<TemplateStyleTag>) -> Bool {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return true }
    // Tags are localized, so search matches the words on screen.
    let searchable = ([title, subtitle] + tags.map { String(localized: $0.title) })
      .joined(separator: " ")
    return searchable.localizedCaseInsensitiveContains(query)
  }

  private func matchesTags(_ tags: Set<TemplateStyleTag>) -> Bool {
    selectedTags.isEmpty || !selectedTags.isDisjoint(with: tags)
  }
}

/// One mirrored half of a capsule outline. Both halves start at the top centre,
/// travel around their respective cap, and finish together at the bottom centre.
struct CenterOutCapsuleOutline: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let color: Color
  let trigger: String

  @State private var progress: CGFloat = 0

  var body: some View {
    let stroke = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)

    ZStack {
      CenterOutCapsuleHalf(edge: .leading)
        .trim(from: 0, to: progress)
        .stroke(color, style: stroke)
      CenterOutCapsuleHalf(edge: .trailing)
        .trim(from: 0, to: progress)
        .stroke(color, style: stroke)
    }
    .onAppear(perform: animate)
    .onChange(of: trigger) { _, _ in animate() }
    .accessibilityHidden(true)
  }

  private func animate() {
    if reduceMotion {
      progress = 1
      return
    }

    var reset = Transaction()
    reset.disablesAnimations = true
    withTransaction(reset) { progress = 0 }
    DispatchQueue.main.async {
      withAnimation(.easeInOut(duration: 0.82)) {
        progress = 1
      }
    }
  }
}

private struct CenterOutCapsuleHalf: Shape {
  let edge: HorizontalEdge

  func path(in rect: CGRect) -> Path {
    let rect = rect.insetBy(dx: 1, dy: 1)
    let radius = rect.height / 2
    let controlOffset = radius * 4 / 3
    let topCenter = CGPoint(x: rect.midX, y: rect.minY)
    let bottomCenter = CGPoint(x: rect.midX, y: rect.maxY)
    var path = Path()
    path.move(to: topCenter)

    switch edge {
    case .leading:
      let topTangent = CGPoint(x: rect.minX + radius, y: rect.minY)
      let bottomTangent = CGPoint(x: rect.minX + radius, y: rect.maxY)
      path.addLine(to: topTangent)
      path.addCurve(
        to: bottomTangent,
        control1: CGPoint(x: topTangent.x - controlOffset, y: topTangent.y),
        control2: CGPoint(x: bottomTangent.x - controlOffset, y: bottomTangent.y)
      )
    case .trailing:
      let topTangent = CGPoint(x: rect.maxX - radius, y: rect.minY)
      let bottomTangent = CGPoint(x: rect.maxX - radius, y: rect.maxY)
      path.addLine(to: topTangent)
      path.addCurve(
        to: bottomTangent,
        control1: CGPoint(x: topTangent.x + controlOffset, y: topTangent.y),
        control2: CGPoint(x: bottomTangent.x + controlOffset, y: bottomTangent.y)
      )
    }

    path.addLine(to: bottomCenter)
    return path
  }
}

private enum TemplateDocumentKind: String, CaseIterable, Identifiable {
  case resume
  case coverLetter

  var id: String { rawValue }
  var title: LocalizedStringResource { self == .resume ? "Résumés" : "Cover letters" }
  var searchTitle: LocalizedStringResource {
    self == .resume ? "résumé templates" : "cover-letter templates"
  }
}

#Preview {
  NavigationStack {
    TemplateGalleryView()
      .environmentObject(ResumeStore(initialDocument: .example))
      .environmentObject(CoverLetterStore(initialDocument: .example))
  }
}
