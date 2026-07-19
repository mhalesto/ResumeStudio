import SwiftUI

struct ApplicationAnswerVaultView: View {
  @EnvironmentObject private var resumeStore: ResumeStore
  @ObservedObject var store: ApplicationAnswerVaultStore
  @State private var editingAnswer: ApplicationAnswer?
  @State private var publishMessage: String?

  var body: some View {
    List {
      Section {
        Label("Private, review-first autofill", systemImage: "hand.raised.fill")
          .foregroundStyle(.orange)
        Text("Save answers you repeatedly type into job applications. Safari suggests a matching answer only after you tap the Resume Studio extension, and it never submits a form.")
          .font(.footnote)
          .foregroundStyle(Theme.mutedInk)
      }

      Section {
        ForEach(store.answers) { answer in
          answerRow(answer)
        }
        .onDelete(perform: store.delete)
      } header: {
        Text("Saved answers")
      } footer: {
        Text("Only enabled answers with completed text are included when you publish your Safari autofill data.")
      }

      Section("Safari application autofill") {
        Button("Publish private autofill data", systemImage: "safari.fill") {
          do {
            try PlatformIntegrationService.publishAutofillProfile(
              resumeStore.document,
              answers: store.publishableAnswers
            )
            let count = store.publishableAnswers.count
            publishMessage = "Safari autofill now uses the active résumé profile and \(count) saved answer\(count == 1 ? "" : "s")."
          } catch {
            publishMessage = error.localizedDescription
          }
        }
        if let publishMessage {
          Label(publishMessage, systemImage: "checkmark.circle.fill")
            .font(.caption)
            .foregroundStyle(.green)
        }
      }

      Section {
        Button("Add custom answer", systemImage: "plus.circle.fill") {
          editingAnswer = ApplicationAnswer(
            category: .custom,
            title: "",
            isEnabled: true
          )
        }
        Button("Restore common questions", systemImage: "arrow.clockwise") {
          store.restoreStarterQuestions()
        }
      }

      if let error = store.lastSaveError {
        Section {
          Label(error, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
        }
      }
    }
    .navigationTitle("Answer Vault")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $editingAnswer) { answer in
      ApplicationAnswerEditorView(answer: answer) { updated in
        store.upsert(updated)
      }
    }
  }

  private func answerRow(_ answer: ApplicationAnswer) -> some View {
    HStack(spacing: 12) {
      Button {
        editingAnswer = answer
      } label: {
        HStack(spacing: 12) {
          Image(systemName: answer.category.systemImage)
            .frame(width: 24)
            .foregroundStyle(.orange)
          VStack(alignment: .leading, spacing: 4) {
            if let title = answer.title.nilIfBlank {
              Text(verbatim: title)
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
            } else {
              Text(answer.category.title)
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
            }
            if let savedAnswer = answer.answer.nilIfBlank {
              Text(verbatim: savedAnswer)
                .font(.caption)
                .foregroundStyle(Theme.mutedInk)
                .lineLimit(2)
            } else {
              Text("Add your answer")
                .font(.caption)
                .foregroundStyle(Theme.mutedInk)
            }
          }
          Spacer(minLength: 4)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      Toggle(
        "Use answer",
        isOn: Binding(
          get: { answer.isEnabled },
          set: { isEnabled in
            if isEnabled && answer.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
              var draft = answer
              draft.isEnabled = true
              editingAnswer = draft
            } else {
              store.setEnabled(isEnabled, id: answer.id)
            }
          }
        )
      )
      .labelsHidden()
      .accessibilityHint(
        answer.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? "Add your answer"
          : "Include in Safari suggestions"
      )
    }
  }
}

private struct ApplicationAnswerEditorView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var answer: ApplicationAnswer
  @State private var keywordsText: String
  let onSave: (ApplicationAnswer) -> Void

  init(answer: ApplicationAnswer, onSave: @escaping (ApplicationAnswer) -> Void) {
    var initialAnswer = answer
    if answer.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      initialAnswer.isEnabled = true
    }
    _answer = State(initialValue: initialAnswer)
    _keywordsText = State(initialValue: answer.keywords.joined(separator: ", "))
    self.onSave = onSave
  }

  private var isValid: Bool {
    !answer.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !answer.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && (!parsedKeywords.isEmpty || answer.category != .custom)
  }

  private var parsedKeywords: [String] {
    keywordsText
      .components(separatedBy: CharacterSet(charactersIn: ",\n"))
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private var editorTitle: LocalizedStringResource {
    answer.answer.isEmpty ? "Add answer" : "Edit answer"
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Question") {
          Picker("Type", selection: $answer.category) {
            ForEach(ApplicationAnswerCategory.allCases) { category in
              Label(category.title, systemImage: category.systemImage).tag(category)
            }
          }
          TextField("Question shown on applications", text: $answer.title, axis: .vertical)
            .lineLimit(2...4)
        }

        Section("Your reusable answer") {
          TextEditor(text: $answer.answer)
            .frame(minHeight: 130)
          Toggle("Include in Safari suggestions", isOn: $answer.isEnabled)
        }

        Section {
          TextField("e.g. notice period, when can you start", text: $keywordsText, axis: .vertical)
            .textInputAutocapitalization(.never)
        } header: {
          Text("Matching phrases")
        } footer: {
          if answer.category == .custom {
            Text("Add at least one phrase Safari can use to recognize this question. Separate phrases with commas.")
          } else {
            Text("Optional phrases supplement the safe built-in matching terms. Separate phrases with commas.")
          }
        }

        Section {
          Label("Answers remain in the app sandbox and the private Resume Studio app group. They are not sent to Resume Studio servers or submitted automatically.", systemImage: "lock.shield.fill")
            .font(.footnote)
            .foregroundStyle(Theme.mutedInk)
        }
      }
      .navigationTitle(Text(editorTitle))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            answer.keywords = parsedKeywords
            onSave(answer)
            dismiss()
          }
          .disabled(!isValid)
        }
      }
    }
  }
}
