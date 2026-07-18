import SwiftUI
import UserNotifications
import UIKit

struct LinkedInStudioView: View {
  @EnvironmentObject private var resumeStore: ResumeStore
  @EnvironmentObject private var applicationStore: ApplicationStore
  @EnvironmentObject private var careerStore: CareerIntelligenceStore
  @EnvironmentObject private var aiArtifacts: AIArtifactStore
  @State private var applicationID: UUID?
  @State private var request = "Position me for the roles I am targeting while keeping the tone natural."
  @State private var draft: AICareerToolkitDraft?
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var copied = false

  private var application: JobApplication? {
    applicationID.flatMap { id in applicationStore.applications.first { $0.id == id } }
  }

  var body: some View {
    ToolkitScroll(title: "LinkedIn Studio") {
      PremiumFeatureHero(
        eyebrow: "RECRUITER-READY PROFILE",
        title: "One career story, built to be found.",
        subtitle: "Create a headline, About section and keyword plan from the same verified evidence behind your résumé.",
        icon: "person.crop.rectangle.stack.fill",
        accent: resumeStore.document.accent.color
      )

      VStack(alignment: .leading, spacing: 12) {
        Label("Target", systemImage: "scope").font(.headline)
        Picker("Application", selection: $applicationID) {
          Text("My general career direction").tag(Optional<UUID>.none)
          ForEach(applicationStore.applications) { value in
            Text([value.role, value.company].filter { !$0.isBlank }.joined(separator: " — ")).tag(Optional(value.id))
          }
        }
        TextField("What should the profile emphasise?", text: $request, axis: .vertical).lineLimit(2...5)
      }.padding(18).cardSurface()

      toolkitButton(isLoading ? "Building your profile…" : "Create LinkedIn profile", isLoading: isLoading) {
        Task { await generate() }
      }

      if let draft {
        VStack(alignment: .leading, spacing: 16) {
          Text("Headline").eyebrow().foregroundStyle(resumeStore.document.accent.color)
          Text(draft.title).font(.title3.bold()).foregroundStyle(Theme.ink)
          Divider()
          Text("About").eyebrow().foregroundStyle(resumeStore.document.accent.color)
          Text(draft.body).font(.subheadline).foregroundStyle(Theme.inkSoft)
          if !draft.highlights.isEmpty {
            Text("Profile upgrades").font(.headline)
            ForEach(draft.highlights, id: \.self) { Label($0, systemImage: "arrow.up.right.circle.fill").font(.subheadline) }
          }
          EvidenceSourceStrip(sources: draft.evidenceSources, claims: draft.claimsRequiringConfirmation)
          Button(copied ? "Copied" : "Copy LinkedIn content", systemImage: copied ? "checkmark" : "doc.on.doc") {
            UIPasteboard.general.string = "\(draft.title)\n\n\(draft.body)\n\n\(draft.highlights.joined(separator: "\n"))"
            copied = true
          }.buttonStyle(.borderedProminent).tint(.blue)
        }.padding(19).cardSurface()
      }
      errorLabel(errorMessage)
    }
    .task {
      guard draft == nil else { return }
      draft = aiArtifacts.latest(
        AICareerToolkitDraft.self, action: .careerToolkit, context: "linkedinProfile")
    }
  }

  @MainActor private func generate() async {
    isLoading = true; errorMessage = nil; copied = false
    do {
      draft = try await ResumeAIService.shared.createCareerToolkitDraft(
        kind: "linkedinProfile", document: resumeStore.document,
        evidence: careerStore.verifiedEvidence, application: application, request: request
      )
    } catch { errorMessage = error.localizedDescription }
    isLoading = false
  }
}

struct NetworkingStudioView: View {
  @EnvironmentObject private var resumeStore: ResumeStore
  @EnvironmentObject private var applicationStore: ApplicationStore
  @EnvironmentObject private var careerStore: CareerIntelligenceStore
  @State private var contactID: UUID?
  @State private var applicationID: UUID?
  @State private var kind = NetworkingMessageKind.introduction
  @State private var context = ""
  @State private var generated: AICareerToolkitDraft?
  @State private var editingContact: CareerContact?
  @State private var isLoading = false
  @State private var errorMessage: String?

  private var contact: CareerContact? { contactID.flatMap { id in careerStore.contacts.first { $0.id == id } } }
  private var application: JobApplication? { applicationID.flatMap { id in applicationStore.applications.first { $0.id == id } } }

  var body: some View {
    ToolkitScroll(title: "Networking") {
      PremiumFeatureHero(
        eyebrow: "RELATIONSHIPS, NOT SPAM",
        title: "Write like a person who did the homework.",
        subtitle: "Keep recruiters, referrals and mentors connected to the opportunities where they matter.",
        icon: "person.2.wave.2.fill",
        accent: resumeStore.document.accent.color
      )

      VStack(alignment: .leading, spacing: 13) {
        HStack { Label("People", systemImage: "person.2.fill").font(.headline); Spacer(); Button("Add", systemImage: "plus") { editingContact = emptyContact } }
        if careerStore.contacts.isEmpty {
          Text("Add a recruiter, referral, hiring manager or mentor to personalise your outreach.").font(.subheadline).foregroundStyle(Theme.mutedInk)
        }
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 10) {
            ForEach(careerStore.contacts.sorted(by: contactPriority)) { value in
              Button { contactID = value.id } label: {
                ContactChip(contact: value, selected: contactID == value.id, accent: resumeStore.document.accent.color)
              }.buttonStyle(.plain).contextMenu {
                Button("Edit", systemImage: "pencil") { editingContact = value }
                Button("Delete", systemImage: "trash", role: .destructive) { careerStore.deleteContact(value.id) }
              }
            }
          }.padding(.vertical, 2)
        }
      }.padding(18).cardSurface()

      VStack(alignment: .leading, spacing: 12) {
        Picker("Message", selection: $kind) { ForEach(NetworkingMessageKind.allCases) { Text($0.title).tag($0) } }
        Picker("Application", selection: $applicationID) {
          Text("No specific application").tag(Optional<UUID>.none)
          ForEach(applicationStore.applications) { Text([ $0.role, $0.company ].filter { !$0.isBlank }.joined(separator: " — ")).tag(Optional($0.id)) }
        }
        TextField("Context — how you met, what you need, timing…", text: $context, axis: .vertical).lineLimit(3...6)
      }.padding(18).cardSurface()

      toolkitButton(isLoading ? "Writing…" : "Draft personalised message", isLoading: isLoading) { Task { await generate() } }
      if let generated {
        ToolkitDraftCard(draft: generated, accent: resumeStore.document.accent.color, copyLabel: "Copy message")
        HStack {
          Button("Save draft", systemImage: "tray.and.arrow.down.fill") { saveDraft(generated) }
            .buttonStyle(.borderedProminent).tint(.green)
          if let mailURL = mailURL(generated) {
            Link(destination: mailURL) { Label("Open Mail", systemImage: "envelope.fill") }
              .buttonStyle(.bordered)
          }
          Button("Mark sent", systemImage: "checkmark.circle.fill") { markSent(generated) }
            .buttonStyle(.bordered)
        }
      }
      if let contact, !(contact.interactions ?? []).isEmpty {
        VStack(alignment: .leading, spacing: 12) {
          Text("Relationship timeline").font(.title3.bold())
          ForEach((contact.interactions ?? []).sorted { $0.occurredAt > $1.occurredAt }) { interaction in
            Label {
              VStack(alignment: .leading) {
                Text(interaction.summary).font(.subheadline)
                Text(interaction.occurredAt, style: .relative).font(.caption).foregroundStyle(Theme.mutedInk)
              }
            } icon: { Image(systemName: interaction.kind.systemImage).foregroundStyle(resumeStore.document.accent.color) }
          }
        }.padding(18).cardSurface()
      }
      errorLabel(errorMessage)
    }
    .sheet(item: $editingContact) { contact in
      ContactEditorView(contact: contact) { careerStore.upsert($0) }
    }
  }

  private var emptyContact: CareerContact {
    CareerContact(name: "", role: "", company: "", email: "", linkedInURL: "", kind: .recruiter, notes: "")
  }

  private func contactPriority(_ left: CareerContact, _ right: CareerContact) -> Bool {
    let leftDate = left.followUpAt ?? .distantFuture
    let rightDate = right.followUpAt ?? .distantFuture
    if leftDate != rightDate { return leftDate < rightDate }
    return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
  }

  @MainActor private func generate() async {
    isLoading = true; errorMessage = nil
    do {
      generated = try await ResumeAIService.shared.createCareerToolkitDraft(
        kind: "networkingMessage", document: resumeStore.document,
        evidence: careerStore.verifiedEvidence, application: application,
        recipient: [contact?.name, contact?.role, contact?.company].compactMap { $0 }.filter { !$0.isBlank }.joined(separator: " · "),
        request: "\(kind.title). \(context)"
      )
    } catch { errorMessage = error.localizedDescription }
    isLoading = false
  }

  private func saveDraft(_ value: AICareerToolkitDraft) {
    careerStore.add(NetworkingDraft(
      kind: kind, contactID: contactID, applicationID: applicationID,
      subject: value.title, body: value.body,
      claimsRequiringConfirmation: value.claimsRequiringConfirmation
    ))
  }

  private func mailURL(_ value: AICareerToolkitDraft) -> URL? {
    guard let email = contact?.email.nilIfBlank else { return nil }
    var components = URLComponents()
    components.scheme = "mailto"; components.path = email
    components.queryItems = [URLQueryItem(name: "subject", value: value.title), URLQueryItem(name: "body", value: value.body)]
    return components.url
  }

  private func markSent(_ value: AICareerToolkitDraft) {
    saveDraft(value)
    guard var contact else { return }
    var interactions = contact.interactions ?? []
    interactions.append(ContactInteraction(kind: .email, summary: value.title))
    contact.interactions = interactions
    contact.lastContactedAt = Date()
    contact.followUpAt = nil
    contact.relationshipStrength = min(5, max(1, (contact.relationshipStrength ?? 1) + 1))
    careerStore.upsert(contact)
  }
}

private struct ContactChip: View {
  let contact: CareerContact
  let selected: Bool
  let accent: Color
  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      ZStack {
        Circle().fill(selected ? accent : accent.opacity(0.13)).frame(width: 44, height: 44)
        Text(String(contact.name.nilIfBlank?.prefix(1) ?? "?")).font(.headline).foregroundStyle(selected ? .white : accent)
      }
      Text(contact.name.nilIfBlank ?? "Unnamed").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
      Text(contact.kind.title).font(.caption).foregroundStyle(Theme.mutedInk)
      if let followUp = contact.followUpAt {
        Text(followUp <= Date() ? "Follow-up due" : followUp.formatted(date: .abbreviated, time: .omitted))
          .font(.caption2.bold())
          .foregroundStyle(followUp <= Date() ? .orange : Theme.mutedInk)
      }
    }.padding(12).frame(width: 128, alignment: .leading)
      .background(Theme.muted.opacity(selected ? 1 : 0.55), in: RoundedRectangle(cornerRadius: 16))
      .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? accent : Color.clear, lineWidth: 2) }
  }
}

private struct ContactEditorView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var applicationStore: ApplicationStore
  @State var contact: CareerContact
  @State private var followUpEnabled: Bool
  let onSave: (CareerContact) -> Void

  init(contact: CareerContact, onSave: @escaping (CareerContact) -> Void) {
    _contact = State(initialValue: contact)
    _followUpEnabled = State(initialValue: contact.followUpAt != nil)
    self.onSave = onSave
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Person") {
          TextField("Name", text: $contact.name)
          TextField("Role", text: $contact.role)
          TextField("Company", text: $contact.company)
          Picker("Relationship", selection: $contact.kind) { ForEach(CareerContactKind.allCases) { Text($0.title).tag($0) } }
        }
        Section("Contact") {
          TextField("Email", text: $contact.email).textInputAutocapitalization(.never).keyboardType(.emailAddress)
          TextField("LinkedIn URL", text: $contact.linkedInURL).textInputAutocapitalization(.never).keyboardType(.URL)
          TextField("Notes", text: $contact.notes, axis: .vertical).lineLimit(3...7)
          Toggle("Schedule a follow-up", isOn: $followUpEnabled)
            .onChange(of: followUpEnabled) { _, enabled in
              contact.followUpAt = enabled
                ? (contact.followUpAt ?? Calendar.current.date(byAdding: .day, value: 3, to: Date()))
                : nil
            }
          if followUpEnabled {
            DatePicker("Follow up", selection: Binding(
              get: { contact.followUpAt ?? Calendar.current.date(byAdding: .day, value: 3, to: Date())! },
              set: { contact.followUpAt = $0 }
            ), displayedComponents: .date)
          }
          Stepper("Relationship strength: \(contact.relationshipStrength ?? 1)/5", value: Binding(
            get: { contact.relationshipStrength ?? 1 }, set: { contact.relationshipStrength = $0 }
          ), in: 1...5)
        }
        Section("Opportunity") {
          Picker("Related application", selection: $contact.applicationID) {
            Text("No specific application").tag(Optional<UUID>.none)
            ForEach(applicationStore.applications) { application in
              Text([application.role, application.company].filter { !$0.isBlank }.joined(separator: " — "))
                .tag(Optional(application.id))
            }
          }
          Text("Linking a person to an opportunity keeps relationship context with the application.")
            .font(.caption).foregroundStyle(Theme.mutedInk)
        }
      }
      .navigationTitle("Career contact").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(contact); dismiss() }.disabled(contact.name.isBlank) }
      }
    }
  }
}

struct OfferComparisonView: View {
  @EnvironmentObject private var resumeStore: ResumeStore
  @EnvironmentObject private var applicationStore: ApplicationStore
  @EnvironmentObject private var careerStore: CareerIntelligenceStore
  @State private var editingOffer: JobOffer?
  @State private var selectedOfferID: UUID?
  @State private var negotiation: AICareerToolkitDraft?
  @State private var isLoading = false
  @State private var errorMessage: String?

  private var selectedOffer: JobOffer? { selectedOfferID.flatMap { id in careerStore.offers.first { $0.id == id } } }

  var body: some View {
    ToolkitScroll(title: "Offers") {
      PremiumFeatureHero(
        eyebrow: "DECIDE WITH THE WHOLE PICTURE",
        title: "An offer is more than one number.",
        subtitle: "Compare cash, flexibility, commute, growth and culture—then prepare a respectful evidence-based negotiation.",
        icon: "scale.3d",
        accent: resumeStore.document.accent.color
      )

      HStack { Text("Offer comparison").font(.title2.bold()); Spacer(); Button("Add offer", systemImage: "plus") { editingOffer = emptyOffer } }

      if careerStore.offers.isEmpty {
        ContentUnavailableView("No offers yet", systemImage: "star.circle", description: Text("Add an offer when an application reaches the exciting part."))
          .padding(.vertical, 25).frame(maxWidth: .infinity).cardSurface()
      } else {
        ForEach(careerStore.offers) { offer in
          Button { selectedOfferID = offer.id } label: {
            OfferCard(offer: offer, selected: selectedOfferID == offer.id, maximumCash: careerStore.offers.map(\.estimatedAnnualValue).max() ?? 1, accent: resumeStore.document.accent.color)
          }.buttonStyle(.plain).contextMenu {
            Button("Edit", systemImage: "pencil") { editingOffer = offer }
            Button("Delete", systemImage: "trash", role: .destructive) { careerStore.deleteOffer(offer.id) }
          }
        }
      }

      if let selectedOffer {
        toolkitButton(isLoading ? "Preparing…" : "Prepare negotiation for \(selectedOffer.company)", isLoading: isLoading) {
          Task { await negotiate(selectedOffer) }
        }
      }
      if let negotiation { ToolkitDraftCard(draft: negotiation, accent: resumeStore.document.accent.color, copyLabel: "Copy negotiation script") }
      errorLabel(errorMessage)
    }
    .sheet(item: $editingOffer) { offer in OfferEditorView(offer: offer) { careerStore.upsert($0) } }
  }

  private var emptyOffer: JobOffer {
    JobOffer(company: "", role: "", currencyCode: Locale.current.currency?.identifier ?? "ZAR", baseSalary: 0, bonus: 0, equitySummary: "", benefits: "", workStyle: "Hybrid", commuteMinutes: 0, growthRating: 3, cultureRating: 3, notes: "", negotiationDraft: "")
  }

  @MainActor private func negotiate(_ offer: JobOffer) async {
    isLoading = true; errorMessage = nil
    let application = offer.applicationID.flatMap { id in applicationStore.applications.first { $0.id == id } }
    let context = "Offer: \(offer.currencyCode) \(offer.baseSalary) base, \(offer.bonus) bonus, \(offer.signingBonus ?? 0) signing, \(offer.employerRetirementAnnual ?? 0) retirement, \(offer.medicalAnnual ?? 0) medical, \(offer.equityAnnualValue ?? 0) annual equity, \(offer.commuteAnnualCost ?? 0) commute cost, \(offer.remoteSavingsAnnual ?? 0) remote savings, \(offer.leaveDays ?? 0) leave days. Benefits: \(offer.benefits). Work style: \(offer.workStyle). Notes: \(offer.notes). Do not invent market salary data."
    do {
      negotiation = try await ResumeAIService.shared.createCareerToolkitDraft(
        kind: "offerNegotiation", document: resumeStore.document,
        evidence: careerStore.verifiedEvidence, application: application, request: context
      )
    } catch { errorMessage = error.localizedDescription }
    isLoading = false
  }
}

private struct OfferCard: View {
  let offer: JobOffer
  let selected: Bool
  let maximumCash: Double
  let accent: Color
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading) {
          Text(offer.role.nilIfBlank ?? "Offer").font(.headline).foregroundStyle(Theme.ink)
          Text(offer.company.nilIfBlank ?? "Company").font(.subheadline).foregroundStyle(Theme.mutedInk)
        }
        Spacer()
        VStack(alignment: .trailing) {
          Text(offer.estimatedAnnualValue, format: .currency(code: offer.currencyCode)).font(.headline).foregroundStyle(accent)
          Text("estimated annual value").font(.caption2).foregroundStyle(Theme.mutedInk)
        }
        Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? accent : Theme.mutedInk)
      }
      GeometryReader { geometry in
        Capsule().fill(Theme.muted).overlay(alignment: .leading) {
          Capsule().fill(LinearGradient(colors: [accent, accent.opacity(0.55)], startPoint: .leading, endPoint: .trailing))
            .frame(width: geometry.size.width * max(0.02, offer.estimatedAnnualValue / max(maximumCash, 1)))
        }
      }.frame(height: 8)
      HStack { Label(offer.workStyle, systemImage: "house.fill"); Spacer(); Label("Growth \(offer.growthRating)/5", systemImage: "arrow.up.right"); Spacer(); Label("Culture \(offer.cultureRating)/5", systemImage: "person.2.fill") }
        .font(.caption).foregroundStyle(Theme.mutedInk)
    }.padding(17).background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
      .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(selected ? accent : Theme.hairline, lineWidth: selected ? 2 : 1) }
  }
}

private struct OfferEditorView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var applicationStore: ApplicationStore
  @State var offer: JobOffer
  let onSave: (JobOffer) -> Void
  var body: some View {
    NavigationStack {
      Form {
        Section("Offer") {
          Picker("Application", selection: $offer.applicationID) {
            Text("None").tag(Optional<UUID>.none)
            ForEach(applicationStore.applications) { Text([ $0.role, $0.company ].filter { !$0.isBlank }.joined(separator: " — ")).tag(Optional($0.id)) }
          }
          TextField("Company", text: $offer.company)
          TextField("Role", text: $offer.role)
          TextField("Currency", text: $offer.currencyCode).textInputAutocapitalization(.characters)
          TextField("Base salary", value: $offer.baseSalary, format: .number).keyboardType(.decimalPad)
          TextField("Bonus", value: $offer.bonus, format: .number).keyboardType(.decimalPad)
          TextField("Signing bonus", value: $offer.signingBonus, format: .number).keyboardType(.decimalPad)
        }
        Section("Annual value") {
          TextField("Employer retirement contribution", value: $offer.employerRetirementAnnual, format: .number).keyboardType(.decimalPad)
          TextField("Medical aid contribution", value: $offer.medicalAnnual, format: .number).keyboardType(.decimalPad)
          TextField("Estimated annual equity value", value: $offer.equityAnnualValue, format: .number).keyboardType(.decimalPad)
          TextField("Other annual value", value: $offer.otherAnnualValue, format: .number).keyboardType(.decimalPad)
          TextField("Annual commute cost", value: $offer.commuteAnnualCost, format: .number).keyboardType(.decimalPad)
          TextField("Annual remote-work savings", value: $offer.remoteSavingsAnnual, format: .number).keyboardType(.decimalPad)
          Stepper("Paid leave: \(offer.leaveDays ?? 0) days", value: Binding(
            get: { offer.leaveDays ?? 0 }, set: { offer.leaveDays = $0 }
          ), in: 0...60)
          LabeledContent("Estimated annual value", value: offer.estimatedAnnualValue, format: .currency(code: offer.currencyCode))
        }
        Section("Whole offer") {
          TextField("Benefits", text: $offer.benefits, axis: .vertical)
          TextField("Equity or long-term incentives", text: $offer.equitySummary, axis: .vertical)
          TextField("On-site, hybrid or remote", text: $offer.workStyle)
          Stepper("Commute: \(offer.commuteMinutes) min", value: $offer.commuteMinutes, in: 0...240, step: 5)
          Stepper("Growth: \(offer.growthRating)/5", value: $offer.growthRating, in: 1...5)
          Stepper("Culture: \(offer.cultureRating)/5", value: $offer.cultureRating, in: 1...5)
          TextField("Notes", text: $offer.notes, axis: .vertical).lineLimit(3...8)
        }
      }
      .navigationTitle("Job offer").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(offer); dismiss() }.disabled(offer.company.isBlank && offer.role.isBlank) }
      }
      .onChange(of: offer.applicationID) { _, id in
        guard let id, let application = applicationStore.applications.first(where: { $0.id == id }) else { return }
        offer.company = application.company; offer.role = application.role
      }
    }
  }
}

struct ReviewRoomView: View {
  @EnvironmentObject private var resumeStore: ResumeStore
  @EnvironmentObject private var careerStore: CareerIntelligenceStore
  @EnvironmentObject private var purchases: PurchaseManager
  @EnvironmentObject private var network: NetworkMonitor
  @State private var isCreating = false
  @State private var shareBundle: ReviewShareBundle?
  @State private var errorMessage: String?
  @State private var workingRequestID: UUID?
  @State private var requestPendingDeletion: ResumeReviewRequest?

  var body: some View {
    ToolkitScroll(title: "Review Room") {
      PremiumFeatureHero(
        eyebrow: "TRUSTED HUMAN FEEDBACK",
        title: "Invite another pair of eyes.",
        subtitle: "Create an expiring review request, share the exact résumé PDF and keep section-level feedback organised.",
        icon: "person.2.badge.gearshape.fill",
        accent: resumeStore.document.accent.color
      )
      Button("Create review request", systemImage: "person.badge.plus") {
        if canCreateHostedRoom { isCreating = true }
        else { purchases.requestPlans() }
      }
        .buttonStyle(.borderedProminent).tint(resumeStore.document.accent.color)
      if !network.isOnline {
        Label("Review Room publishing and refresh require a connection. Saved requests remain available.", systemImage: "wifi.slash")
          .font(.caption).foregroundStyle(Theme.mutedInk)
      }

      if careerStore.reviewRequests.isEmpty {
        PremiumEmptyState(
          image: .reviewRoomEmptyState,
          title: "Thoughtful feedback, without sending an editable file",
          detail: "Publish an expiring private review room for a mentor, recruiter or trusted colleague."
        )
      }
      ForEach(careerStore.reviewRequests) { request in
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            VStack(alignment: .leading) {
              Text(request.reviewerName.nilIfBlank ?? "Reviewer").font(.headline)
              Text("Code \(request.accessCode) · expires \(request.expiresAt.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(Theme.mutedInk)
            }
            Spacer()
            Text(request.isExpired ? "Expired" : request.status.title).font(.caption.bold())
              .foregroundStyle(request.isExpired || request.status == .revoked ? .red : .green)
          }
          if !request.message.isBlank { Text(request.message).font(.subheadline).foregroundStyle(Theme.inkSoft) }
          HStack {
            if request.status == .revoked {
              Label("Link disabled", systemImage: "link.badge.minus").foregroundStyle(.red)
            } else if request.hostedURL == nil {
              Button(workingRequestID == request.id ? "Publishing…" : "Publish private link", systemImage: "link.badge.plus") {
                Task { await publish(request) }
              }.disabled(workingRequestID != nil || !network.isOnline)
            } else {
              Button("Share review link", systemImage: "square.and.arrow.up") { prepareShare(request) }
              Button("Refresh", systemImage: "arrow.clockwise") { Task { await refresh(request) } }
                .disabled(!network.isOnline)
              Menu {
                Button("Disable link now", systemImage: "link.badge.minus", role: .destructive) {
                  Task { await revoke(request) }
                }
                Button("Delete room and comments", systemImage: "trash", role: .destructive) {
                  requestPendingDeletion = request
                }
              } label: {
                Image(systemName: "ellipsis.circle")
              }
            }
            Spacer()
            Label("\(request.comments.count) comments", systemImage: "bubble.left.fill").font(.caption).foregroundStyle(Theme.mutedInk)
          }
          if !request.comments.isEmpty {
            Divider()
            ForEach(request.comments) { comment in
              HStack(alignment: .top, spacing: 10) {
                Image(systemName: comment.isResolved ? "checkmark.circle.fill" : "bubble.left.fill")
                  .foregroundStyle(comment.isResolved ? .green : resumeStore.document.accent.color)
                VStack(alignment: .leading, spacing: 3) {
                  Text(comment.section).font(.caption.bold()).foregroundStyle(Theme.mutedInk)
                  Text(comment.comment).font(.subheadline).foregroundStyle(Theme.ink)
                  Text("\(comment.author) · \(comment.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2).foregroundStyle(Theme.mutedInk)
                }
                Spacer(minLength: 4)
                Button(comment.isResolved ? "Reopen" : "Resolve") { toggleResolved(comment.id, in: request) }
                  .font(.caption.bold()).buttonStyle(.borderless)
              }
            }
          }
        }.padding(17).cardSurface()
      }
      errorLabel(errorMessage)
    }
    .sheet(isPresented: $isCreating) {
      ReviewRequestEditorView(resumeID: resumeStore.activeResumeID) { careerStore.upsert($0) }
    }
    .sheet(item: $shareBundle) { ShareSheet(activityItems: $0.items) }
    .sheet(item: $requestPendingDeletion) { request in
      PremiumConfirmationSheet(
        title: "Delete this Review Room?",
        message: "The hosted room and every remote review asset will be removed.",
        systemImage: "person.2.slash.fill",
        accent: resumeStore.document.accent.color,
        rows: [
          PremiumConfirmationRow(
            eyebrow: "REVIEW ROOM",
            title: request.reviewerName.nilIfBlank ?? "Unnamed reviewer",
            detail: "\(request.comments.count) comment\(request.comments.count == 1 ? "" : "s") · expires \(request.expiresAt.formatted(date: .abbreviated, time: .omitted))",
            systemImage: "person.2.fill",
            tone: .destructive
          ),
          PremiumConfirmationRow(
            eyebrow: "WILL BE REMOVED",
            title: "Link, PDF and comments",
            detail: "The disabled link cannot be restored",
            systemImage: "link",
            tone: .destructive
          ),
        ],
        safetyNote: "Deleting is immediate and cannot be undone.",
        confirmTitle: "Delete room and hosted PDF",
        onConfirm: { Task { await delete(request) } },
        onCancel: { requestPendingDeletion = nil }
      )
      .premiumConfirmationPresentation()
    }
  }

  @MainActor private func prepareShare(_ request: ResumeReviewRequest) {
    do {
      guard let rawURL = request.hostedURL, let url = URL(string: rawURL) else {
        throw ResumeAIError.server(message: "Publish the private review link first.")
      }
      let invitation = "\(request.message)\n\nOpen the private review room: \(url.absoluteString)\nAccess code: \(request.accessCode)\nExpires: \(request.expiresAt.formatted(date: .long, time: .omitted))"
      shareBundle = ReviewShareBundle(items: [invitation, url])
      var sent = request; sent.status = .sent; careerStore.upsert(sent)
    } catch { errorMessage = error.localizedDescription }
  }

  @MainActor private func publish(_ request: ResumeReviewRequest) async {
    guard canCreateHostedRoom else {
      purchases.requestPlans()
      return
    }
    workingRequestID = request.id; errorMessage = nil
    do {
      var published = request
      let token = request.hostedToken ?? UUID().uuidString.replacingOccurrences(of: "-", with: "")
      published.hostedToken = token
      let url = try await ReviewRoomService.shared.publish(request: published, document: resumeStore.document)
      published.hostedURL = url.absoluteString
      published.status = .sent
      published.lastSyncedAt = Date()
      careerStore.upsert(published)
      _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    } catch { errorMessage = error.localizedDescription }
    workingRequestID = nil
  }

  @MainActor private func refresh(_ request: ResumeReviewRequest) async {
    guard let token = request.hostedToken else { return }
    workingRequestID = request.id; errorMessage = nil
    do {
      let remote = try await ReviewRoomService.shared.comments(token: token)
      let existingRemoteIDs = Set(request.comments.compactMap(\.remoteID))
      let newCommentCount = remote.count { !existingRemoteIDs.contains($0.id) }
      var updated = request
      updated.comments = remote.map { value in
        let existing = request.comments.first { $0.remoteID == value.id }
        return ResumeReviewComment(
          id: existing?.id ?? UUID(), remoteID: value.id, section: value.section,
          author: value.author, comment: value.comment, isResolved: existing?.isResolved ?? false,
          createdAt: value.createdAt
        )
      }
      updated.lastSyncedAt = Date()
      if !updated.comments.isEmpty { updated.status = .feedbackReceived }
      careerStore.upsert(updated)
      if newCommentCount > 0 { notifyAboutComments(newCommentCount, reviewer: request.reviewerName) }
    } catch { errorMessage = error.localizedDescription }
    workingRequestID = nil
  }

  @MainActor private func revoke(_ request: ResumeReviewRequest) async {
    guard let token = request.hostedToken else { return }
    workingRequestID = request.id; errorMessage = nil
    do {
      try await ReviewRoomService.shared.revoke(token: token)
      var updated = request
      updated.status = .revoked
      updated.lastSyncedAt = Date()
      careerStore.upsert(updated)
    } catch { errorMessage = error.localizedDescription }
    workingRequestID = nil
  }

  @MainActor private func delete(_ request: ResumeReviewRequest) async {
    requestPendingDeletion = nil
    workingRequestID = request.id; errorMessage = nil
    do {
      if let token = request.hostedToken { try await ReviewRoomService.shared.delete(token: token) }
      careerStore.deleteReviewRequest(request.id)
    } catch { errorMessage = error.localizedDescription }
    workingRequestID = nil
  }

  private func notifyAboutComments(_ count: Int, reviewer: String) {
    let content = UNMutableNotificationContent()
    content.title = "New résumé feedback"
    content.body = "\(reviewer.nilIfBlank ?? "Your reviewer") left \(count) new comment\(count == 1 ? "" : "s")."
    content.sound = .default
    UNUserNotificationCenter.current().add(
      UNNotificationRequest(identifier: "review-comments-\(UUID().uuidString)", content: content, trigger: nil))
  }

  @MainActor private func toggleResolved(_ commentID: UUID, in request: ResumeReviewRequest) {
    var updated = request
    guard let index = updated.comments.firstIndex(where: { $0.id == commentID }) else { return }
    updated.comments[index].isResolved.toggle()
    if updated.comments.allSatisfy(\.isResolved), !updated.comments.isEmpty { updated.status = .closed }
    else if !updated.comments.isEmpty { updated.status = .feedbackReceived }
    careerStore.upsert(updated)
  }

  private var canCreateHostedRoom: Bool {
    let activeCount = careerStore.reviewRequests.filter {
      !$0.isExpired && $0.status != .closed && $0.status != .revoked && $0.hostedURL != nil
    }.count
    return purchases.hostedReviewRoomLimit > activeCount
  }
}

private struct ReviewShareBundle: Identifiable {
  let id = UUID()
  let items: [Any]
}

private struct ReviewRequestEditorView: View {
  @Environment(\.dismiss) private var dismiss
  let resumeID: UUID
  let onSave: (ResumeReviewRequest) -> Void
  @State private var name = ""
  @State private var email = ""
  @State private var message = "I would value your honest feedback on the clarity, evidence and relevance of this résumé."
  @State private var expiresAt = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
  var body: some View {
    NavigationStack {
      Form {
        Section("Reviewer") { TextField("Name", text: $name); TextField("Email", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never) }
        Section("Request") { TextField("Message", text: $message, axis: .vertical).lineLimit(4...8); DatePicker("Expires", selection: $expiresAt, in: Date()..., displayedComponents: .date) }
        Section { Label("The shared package contains the exported PDF and an expiring access code. Personal feedback remains in your local workspace unless you share it.", systemImage: "lock.shield.fill").font(.caption).foregroundStyle(.green) }
      }
      .navigationTitle("Request a review").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Create") {
            let code = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).uppercased()
            onSave(ResumeReviewRequest(resumeID: resumeID, reviewerName: name, reviewerEmail: email, message: message, accessCode: code, expiresAt: expiresAt, status: .draft, comments: []))
            dismiss()
          }.disabled(name.isBlank)
        }
      }
    }
  }
}

struct MarketGuidanceView: View {
  @EnvironmentObject private var resumeStore: ResumeStore
  @EnvironmentObject private var careerStore: CareerIntelligenceStore
  @State private var language = "English"
  @State private var guidance: AICareerToolkitDraft?
  @State private var isLoading = false
  @State private var errorMessage: String?

  var body: some View {
    ToolkitScroll(title: "Market Guide") {
      PremiumFeatureHero(
        eyebrow: "LOCAL CONTEXT, GLOBAL AMBITION",
        title: "Make the document feel native to the market.",
        subtitle: "Adjust conventions, spelling and emphasis without changing the facts of your career.",
        icon: "globe.africa.fill",
        accent: resumeStore.document.accent.color
      )
      VStack(alignment: .leading, spacing: 14) {
        Picker("Target market", selection: $careerStore.preferredMarket) {
          ForEach(ResumeMarket.allCases) { Text("\($0.flag) \($0.title)").tag($0) }
        }
        TextField("Document language", text: $language)
        Divider()
        Text("Quick conventions").font(.headline)
        ForEach(localTips, id: \.self) { Label($0, systemImage: "checkmark.circle.fill").font(.subheadline).foregroundStyle(Theme.inkSoft) }
      }.padding(18).cardSurface()

      NavigationLink(value: HomeRoute.marketLocalization) {
        Label("Apply formatting or translate this résumé", systemImage: "character.book.closed.fill")
          .font(.headline).frame(maxWidth: .infinity).padding(15)
      }
      .buttonStyle(.borderedProminent)
      .tint(resumeStore.document.accent.color)

      VStack(alignment: .leading, spacing: 12) {
        Label("Sources and freshness", systemImage: "checkmark.seal.text.page.fill").font(.headline)
        Text("Resume conventions are clearly separated from law. Salary guidance is never invented and is omitted unless a dated source is available.")
          .font(.caption).foregroundStyle(Theme.mutedInk)
        ForEach(relevantSources) { source in
          if let url = URL(string: source.url) {
            Link(destination: url) {
              VStack(alignment: .leading, spacing: 3) {
                Text(source.title).font(.subheadline.bold()).foregroundStyle(Theme.ink)
                Text("\(source.publisher) · checked \(source.checkedAt.formatted(date: .abbreviated, time: .omitted))")
                  .font(.caption).foregroundStyle(Theme.mutedInk)
                Text(source.note).font(.caption2).foregroundStyle(Theme.inkSoft)
              }
            }
          }
        }
      }.padding(18).cardSurface()

      toolkitButton(isLoading ? "Checking conventions…" : "Create my localised guidance", isLoading: isLoading) { Task { await generate() } }
      if let guidance { ToolkitDraftCard(draft: guidance, accent: resumeStore.document.accent.color, copyLabel: "Copy guidance") }
      errorLabel(errorMessage)
    }
    .onAppear {
      if careerStore.marketSources.isEmpty { careerStore.replaceMarketSources(MarketSourceCatalog.all) }
    }
  }

  private var relevantSources: [MarketGuidanceSource] {
    let exact = careerStore.marketSources.filter { $0.market == careerStore.preferredMarket }
    return exact.isEmpty ? Array(careerStore.marketSources.prefix(3)) : exact
  }

  private var localTips: [String] {
    switch careerStore.preferredMarket {
    case .southAfrica: ["Use South African or UK spelling consistently.", "A concise personal profile is common.", "Keep identity and demographic details optional and intentional."]
    case .unitedKingdom: ["Use CV terminology and UK spelling.", "Two pages is a common experienced-candidate target.", "Do not include a photograph unless the field specifically expects it."]
    case .unitedStates: ["Use résumé terminology and US spelling.", "Exclude photograph, date of birth and marital status.", "Lead bullets with outcomes and measurable evidence where verified."]
    case .europeanUnion: ["Requirements vary substantially by country.", "Use the local language when the vacancy requests it.", "Treat photographs and personal details as market-specific, never automatic."]
    case .australia: ["Use Australian spelling and clear accomplishment evidence.", "Three to four pages can be acceptable for experienced candidates.", "Include work-rights information only when useful."]
    case .canada: ["Use Canadian spelling consistently.", "Avoid photographs and protected personal information.", "Match the document language to the vacancy and region."]
    case .international: ["Follow the vacancy's language and terminology.", "Keep personal data minimal by default.", "Prefer portable evidence over local jargon."]
    }
  }

  @MainActor private func generate() async {
    isLoading = true; errorMessage = nil
    do {
      guidance = try await ResumeAIService.shared.createCareerToolkitDraft(
        kind: "marketGuidance", document: resumeStore.document,
        evidence: careerStore.verifiedEvidence, market: careerStore.preferredMarket,
        request: "Review this resume for \(careerStore.preferredMarket.title) conventions. The intended document language is \(language). Clearly distinguish convention from law."
      )
    } catch { errorMessage = error.localizedDescription }
    isLoading = false
  }
}

private struct ToolkitScroll<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content
  init(title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) { content }
        .padding(20).padding(.bottom, 40).frame(maxWidth: 720).frame(maxWidth: .infinity)
    }.background(Theme.paper).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
  }
}

@ViewBuilder private func toolkitButton(_ title: String, isLoading: Bool, action: @escaping () -> Void) -> some View {
  Button(action: action) {
    HStack { if isLoading { ProgressView().tint(.white) } else { Image(systemName: "sparkles") }; Text(title) }
      .font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 15)
      .background(Color.orange, in: Capsule())
  }.buttonStyle(.plain).disabled(isLoading)
}

private struct ToolkitDraftCard: View {
  let draft: AICareerToolkitDraft
  let accent: Color
  let copyLabel: String
  @State private var copied = false
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(draft.title).font(.title3.bold()).foregroundStyle(Theme.ink)
      Text(draft.body).font(.subheadline).foregroundStyle(Theme.inkSoft)
      ForEach(draft.highlights, id: \.self) { Label($0, systemImage: "arrow.right.circle.fill").font(.subheadline) }
      EvidenceSourceStrip(sources: draft.evidenceSources, claims: draft.claimsRequiringConfirmation)
      Button(copied ? "Copied" : copyLabel, systemImage: copied ? "checkmark" : "doc.on.doc") {
        UIPasteboard.general.string = "\(draft.title)\n\n\(draft.body)\n\n\(draft.highlights.joined(separator: "\n"))"; copied = true
      }.buttonStyle(.borderedProminent).tint(accent)
    }.padding(19).cardSurface()
  }
}

private struct EvidenceSourceStrip: View {
  let sources: [String]
  let claims: [String]
  var body: some View {
    if !sources.isEmpty {
      VStack(alignment: .leading, spacing: 5) {
        Label("Evidence used", systemImage: "checkmark.seal.fill").font(.caption.bold()).foregroundStyle(.green)
        Text(sources.joined(separator: " · ")).font(.caption).foregroundStyle(Theme.mutedInk)
      }
    }
    ForEach(claims, id: \.self) { Label($0, systemImage: "exclamationmark.shield.fill").font(.caption).foregroundStyle(.orange) }
  }
}

@ViewBuilder private func errorLabel(_ message: String?) -> some View {
  if let message { Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
}
