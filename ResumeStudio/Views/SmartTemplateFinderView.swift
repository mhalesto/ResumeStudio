import SwiftUI

struct SmartTemplateFinderView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: ResumeStore
  @EnvironmentObject private var purchases: PurchaseManager
  @State private var preferences = TemplateFinderPreferences()
  @State private var compared: Set<ResumeTemplate> = []
  @State private var showsComparison = false

  private var recommendations: [TemplateRecommendation] {
    TemplateRecommendationEngine.recommendations(
      preferences: preferences,
      unlocked: purchases.canUse
    )
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          finderForm
          recommendationSummary
          LazyVStack(spacing: 14) {
            ForEach(recommendations.prefix(12)) { recommendation in
              recommendationCard(recommendation)
            }
          }
        }
        .padding(20)
        .padding(.bottom, 36)
      }
      .background(Theme.paper)
      .navigationTitle("Template Finder")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
        if compared.count > 1 {
          ToolbarItem(placement: .confirmationAction) {
            Button("Compare \(compared.count)") { showsComparison = true }
          }
        }
      }
      .sheet(isPresented: $showsComparison) {
        TemplateComparisonView(templates: Array(compared))
      }
    }
  }

  private var finderForm: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Tell us what the document needs to do").font(.title2.bold())
      TextField("Target role or field", text: $preferences.role)
        .textFieldStyle(.roundedBorder)
      Picker("Career level", selection: $preferences.seniority) {
        ForEach(TemplateSeniority.allCases) { Text($0.title).tag($0) }
      }
      Picker("Target market", selection: $preferences.market) {
        ForEach(ResumeMarket.allCases) { Text("\($0.flag) \($0.title)").tag($0) }
      }
      Picker("Page target", selection: $preferences.targetPages) {
        ForEach(ResumePageTarget.allCases) { Text($0.title).tag($0) }
      }
      Toggle("Strict ATS preference", isOn: $preferences.strictATS)
      Toggle("I want a portrait-led design", isOn: $preferences.wantsPhoto)
      Toggle("Show only templates available now", isOn: $preferences.freeOnly)
    }
    .padding(18)
    .cardSurface(radius: 22)
  }

  private var recommendationSummary: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text("Your strongest matches").font(.title2.bold())
      Text("Ranked from structure, market conventions, role, seniority and page preference.")
        .font(.caption).foregroundStyle(Theme.mutedInk)
    }
  }

  private func recommendationCard(_ recommendation: TemplateRecommendation) -> some View {
    HStack(alignment: .top, spacing: 15) {
      TemplatePreviewCard(
        template: recommendation.template,
        accent: store.document.accent,
        isSelected: store.document.template == recommendation.template,
        photo: store.document.photo,
        photoCrop: store.document.photoCrop,
        isPhotoVisible: store.document.isPhotoVisible,
        width: 112
      )
      VStack(alignment: .leading, spacing: 7) {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text(recommendation.template.title).font(.headline)
            Text("\(recommendation.score)% fit").font(.caption.bold()).foregroundStyle(store.document.accent.color)
          }
          Spacer()
          Button {
            if compared.contains(recommendation.template) { compared.remove(recommendation.template) }
            else if compared.count < 3 { compared.insert(recommendation.template) }
          } label: {
            Image(systemName: compared.contains(recommendation.template) ? "square.stack.3d.up.fill" : "square.stack.3d.up")
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Compare \(recommendation.template.title)")
        }
        ForEach(recommendation.reasons, id: \.self) { reason in
          Label(reason, systemImage: "checkmark.circle.fill")
            .font(.caption).foregroundStyle(Theme.inkSoft)
        }
        Button {
          guard purchases.canUse(recommendation.template) else {
            purchases.requestPlans(); return
          }
          store.document.template = recommendation.template
          TemplatePreferenceStore.recordRecent(recommendation.template)
          dismiss()
        } label: {
          Text(purchases.canUse(recommendation.template) ? "Use this template" : "Unlock template")
            .font(.subheadline.bold()).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(store.document.accent.color)
      }
    }
    .padding(14)
    .cardSurface(radius: 20)
  }
}

struct TemplateComparisonView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: ResumeStore
  @EnvironmentObject private var purchases: PurchaseManager
  let templates: [ResumeTemplate]

  var body: some View {
    NavigationStack {
      ScrollView(.horizontal) {
        HStack(alignment: .top, spacing: 18) {
          ForEach(templates) { template in
            VStack(spacing: 12) {
              TemplatePreviewCard(
                template: template, accent: store.document.accent,
                isSelected: store.document.template == template,
                photo: store.document.photo, photoCrop: store.document.photoCrop,
                isPhotoVisible: store.document.isPhotoVisible, width: 210)
                .overlay(alignment: .topTrailing) {
                  if !purchases.canUse(template) { PlanLockBadge().padding(8) }
                }
              Text(template.title).font(.headline)
              Text(template.subtitle).font(.caption).foregroundStyle(Theme.mutedInk)
                .multilineTextAlignment(.center).frame(width: 210)
              Label(template.plan.hasSideColumn ? "Two-column" : "Single-column", systemImage: "rectangle.split.2x1")
              Label(template.isPhotoLed ? "Portrait-led" : "Photo optional", systemImage: "person.crop.circle")
              Label(template.styleTags.contains(.ats) ? "ATS tagged" : "Design-led", systemImage: "checkmark.shield")
              Button(purchases.canUse(template) ? "Use \(template.title)" : "Unlock \(template.title)") {
                guard purchases.canUse(template) else { purchases.requestPlans(); return }
                store.document.template = template
                TemplatePreferenceStore.recordRecent(template)
                dismiss()
              }
              .buttonStyle(.borderedProminent)
              .tint(store.document.accent.color)
            }
            .padding(16)
            .frame(width: 250)
            .cardSurface(radius: 22)
          }
        }
        .padding(20)
      }
      .background(Theme.paper)
      .navigationTitle("Compare templates")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { Button("Done") { dismiss() } }
    }
  }
}

enum TemplatePreferenceStore {
  private static let favoritesKey = "favoriteResumeTemplates"
  private static let recentKey = "recentResumeTemplates"

  static var favorites: Set<ResumeTemplate> {
    get { decode(UserDefaults.standard.string(forKey: favoritesKey)) }
    set { UserDefaults.standard.set(newValue.map(\.rawValue).sorted().joined(separator: ","), forKey: favoritesKey) }
  }

  static var recent: [ResumeTemplate] {
    decodeArray(UserDefaults.standard.string(forKey: recentKey))
  }

  static func toggleFavorite(_ template: ResumeTemplate) {
    var value = favorites
    if value.contains(template) { value.remove(template) } else { value.insert(template) }
    favorites = value
  }

  static func recordRecent(_ template: ResumeTemplate) {
    var values = recent.filter { $0 != template }
    values.insert(template, at: 0)
    UserDefaults.standard.set(values.prefix(12).map(\.rawValue).joined(separator: ","), forKey: recentKey)
  }

  private static func decode(_ raw: String?) -> Set<ResumeTemplate> { Set(decodeArray(raw)) }
  private static func decodeArray(_ raw: String?) -> [ResumeTemplate] {
    (raw ?? "").split(separator: ",").compactMap { ResumeTemplate(rawValue: String($0)) }
  }
}
