import SwiftUI

struct CoverLetterEditorView: View {
  @EnvironmentObject private var resumeStore: ResumeStore
  @EnvironmentObject private var store: CoverLetterStore
  @EnvironmentObject private var purchases: PurchaseManager

  @State private var isGenerating = false
  @State private var generated: AIGeneratedCoverLetter?
  @State private var errorMessage: String?

  var body: some View {
    Form {
      Section {
        Button("Use résumé contact details", systemImage: "arrow.triangle.2.circlepath") {
          store.syncContact(from: resumeStore.document)
        }
        TextField("Full name", text: $store.document.senderName)
        TextField("Professional headline", text: $store.document.senderHeadline)
        TextField("Phone", text: $store.document.senderPhone)
          .keyboardType(.phonePad)
        TextField("Email", text: $store.document.senderEmail)
          .keyboardType(.emailAddress)
          .textInputAutocapitalization(.never)
      } header: {
        Text("Your details")
      }

      Section("Application") {
        DatePicker("Date", selection: $store.document.date, displayedComponents: .date)
        TextField("Job title", text: $store.document.jobTitle)
        TextField("Company", text: $store.document.companyName)
        TextField("Subject", text: $store.document.subject)
      }

      Section("Recipient") {
        TextField("Hiring manager name", text: $store.document.recipientName)
        TextField("Hiring manager title", text: $store.document.recipientTitle)
        TextField("Company address", text: $store.document.companyAddress, axis: .vertical)
          .lineLimit(2...4)
      }

      Section {
        TextEditor(text: $store.document.jobDescription)
          .frame(minHeight: 180)
          .accessibilityLabel("Job description for cover letter")

        Button {
          AppKeyboard.dismiss()
          Task { await generateCoverLetter() }
        } label: {
          Label("Generate from résumé", systemImage: "wand.and.stars")
        }
        .disabled(store.document.jobDescription.isBlank || isGenerating)

        if isGenerating {
          ProgressView("Writing from your résumé evidence…")
        }
        if let errorMessage {
          Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.red)
        }
      } header: {
        Text("AI cover letter")
      } footer: {
        Text("AI is instructed not to invent achievements. You review the complete letter before applying it.")
      }

      Section("Letter") {
        TextField("Greeting", text: $store.document.greeting)

        ForEach(store.document.bodyParagraphs.indices, id: \.self) { index in
          TextField(
            "Paragraph \(index + 1)",
            text: $store.document.bodyParagraphs[index],
            axis: .vertical
          )
          .lineLimit(4...10)
        }
        .onDelete { store.document.bodyParagraphs.remove(atOffsets: $0) }
        .onMove { store.document.bodyParagraphs.move(fromOffsets: $0, toOffset: $1) }

        Button("Add Paragraph", systemImage: "plus") {
          store.document.bodyParagraphs.append("")
        }
        TextField("Closing", text: $store.document.closing)
      }

      Section("Template") {
        Picker("Style", selection: gatedTemplate) {
          ForEach(CoverLetterTemplate.allCases) { template in
            Label {
              HStack {
                Text(template.title)
                if !purchases.canUse(template) { Image(systemName: "lock.fill") }
              }
            } icon: {
              Image(systemName: template.systemImage)
            }
            .tag(template)
          }
        }
        Picker("Accent", selection: gatedAccent) {
          ForEach(ResumeAccent.allCases) { accent in
            Text(String(localized: accent.title) + (purchases.canUse(accent) ? "" : "  🔒"))
              .tag(accent)
          }
        }
      }

      if let saveError = store.lastSaveError {
        Section {
          Label(saveError, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
        }
      }
    }
    .supportsKeyboardDismissal()
    .scrollContentBackground(.hidden)
    .background(Theme.paper)
    .navigationTitle("Cover letter")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        EditButton()
        NavigationLink {
          CoverLetterPreviewView(document: store.document)
        } label: {
          Text("Preview").font(.subheadline.weight(.semibold))
        }
      }
    }
    .sheet(item: $generated) { suggestion in
      CoverLetterAIReviewView(suggestion: suggestion) {
        store.document.subject = suggestion.subject
        store.document.greeting = suggestion.greeting
        store.document.bodyParagraphs = suggestion.bodyParagraphs
        store.document.closing = suggestion.closing
        generated = nil
      }
    }
  }

  private var gatedTemplate: Binding<CoverLetterTemplate> {
    Binding(
      get: { store.document.template },
      set: { value in
        guard purchases.canUse(value) else {
          purchases.requestPlans()
          return
        }
        store.document.template = value
      }
    )
  }

  private var gatedAccent: Binding<ResumeAccent> {
    Binding(
      get: { store.document.accent },
      set: { value in
        guard purchases.canUse(value) else {
          purchases.requestPlans()
          return
        }
        store.document.accent = value
      }
    )
  }

  @MainActor
  private func generateCoverLetter() async {
    isGenerating = true
    errorMessage = nil
    do {
      generated = try await ResumeAIService.shared.writeCoverLetter(
        document: resumeStore.document,
        jobDescription: store.document.jobDescription,
        jobTitle: store.document.jobTitle,
        company: store.document.companyName,
        recipientName: store.document.recipientName
      )
    } catch {
      errorMessage = error.localizedDescription
    }
    isGenerating = false
  }
}

private struct CoverLetterAIReviewView: View {
  let suggestion: AIGeneratedCoverLetter
  let onApply: () -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section("Subject") { Text(suggestion.subject) }
        Section("Greeting") { Text(suggestion.greeting) }
        Section("Body") {
          ForEach(Array(suggestion.bodyParagraphs.enumerated()), id: \.offset) { _, paragraph in
            Text(paragraph).padding(.vertical, 4)
          }
        }
        Section("Closing") { Text(suggestion.closing) }
        if !suggestion.claimsRequiringConfirmation.isEmpty {
          Section("Please verify") {
            ForEach(suggestion.claimsRequiringConfirmation, id: \.self) { claim in
              Label(claim, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            }
          }
        }
      }
      .navigationTitle("Review AI Draft")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Apply") {
            onApply()
            dismiss()
          }
          .fontWeight(.semibold)
        }
      }
    }
  }
}

extension AIGeneratedCoverLetter: Identifiable {
  var id: String { subject + greeting + bodyParagraphs.joined() }
}
