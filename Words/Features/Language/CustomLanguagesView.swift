import SwiftUI

/// The languages the learner added themselves.
///
/// There is nothing to teach about a language the app has never heard of, so
/// this asks for the two things it cannot work out — what to call it and which
/// flag to show — and nothing else. A custom language then behaves exactly
/// like the twelve the app ships with that mark no gender: it has no gender
/// control, because inventing one would be inventing grammar.
struct CustomLanguagesView: View {

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var flag = ""
    @State private var deleting: CustomLanguage?

    private var languages: [CustomLanguage] {
        store.library.customLanguages
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Your Languages",
                subtitle: "A language the app does not know. It works like any other, without the gender help."
            )

            Form {
                Section {
                    HStack(spacing: 10) {
                        FlagField(flag: $flag)

                        TextField("Name", text: $name, prompt: Text("Language name"))
                            .labelsHidden()
                            .onSubmit(add)

                        Button("Add", action: add)
                            .disabled(!canAdd)
                    }
                } header: {
                    Text("Add a Language")
                } footer: {
                    Text("Press ⌃⌘Space for the emoji picker.")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                }

                if languages.isEmpty {
                    Section {
                        Text("No languages of your own yet.")
                            .foregroundStyle(Palette.secondaryText)
                    }
                } else {
                    Section("Added") {
                        ForEach(languages) { language in
                            CustomLanguageRow(
                                language: language,
                                usedBy: store.library.profilesUsing(language.id).count,
                                rename: { store.save($0) },
                                remove: { deleting = language }
                            )
                        }
                    }
                }
            }
            .formStyle(.grouped)

            SheetActions {
                Spacer(minLength: 0)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(Metrics.cardPadding)
        }
        .frame(width: 460, height: 500)
        .alert("Delete this language?", isPresented: .init(
            get: { deleting != nil },
            set: { if !$0 { deleting = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let deleting { store.deleteCustomLanguage(id: deleting.id) }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("It is not being studied, so nothing goes with it.")
        }
    }

    private var canAdd: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func add() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.addCustomLanguage(name: trimmed, flag: flag.isEmpty ? "🏳️" : flag)
        name = ""
        flag = ""
    }
}

/// One added language: its flag, its name, and what it would take with it.
private struct CustomLanguageRow: View {

    let language: CustomLanguage
    let usedBy: Int
    let rename: (CustomLanguage) -> Void
    let remove: () -> Void

    @State private var name: String
    @State private var flag: String

    init(
        language: CustomLanguage,
        usedBy: Int,
        rename: @escaping (CustomLanguage) -> Void,
        remove: @escaping () -> Void
    ) {
        self.language = language
        self.usedBy = usedBy
        self.rename = rename
        self.remove = remove
        _name = State(initialValue: language.name)
        _flag = State(initialValue: language.flag)
    }

    var body: some View {
        HStack(spacing: 10) {
            FlagField(flag: $flag)
                .onChange(of: flag) { save() }

            VStack(alignment: .leading, spacing: 1) {
                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .labelsHidden()
                    .onSubmit(save)

                // Why the delete button is off, said before it is pressed
                // rather than after.
                if usedBy > 0 {
                    Text("Studied by \(usedBy) \(usedBy == 1 ? "language" : "languages")")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
            }

            Button(role: .destructive, action: remove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            .foregroundStyle(usedBy > 0 ? Palette.secondaryText : Palette.warning)
            .disabled(usedBy > 0)
            .help(usedBy > 0
                  ? "A language being studied cannot be deleted. Delete the language profile first."
                  : "Delete \(language.name)")
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            name = language.name
            return
        }
        var changed = language
        changed.name = trimmed
        changed.flag = flag.isEmpty ? "🏳️" : flag
        guard changed != language else { return }
        rename(changed)
    }
}

/// One emoji, and only one.
///
/// A free field rather than a row of suggestions, because the app has no idea
/// which flag a language it has never heard of should wear — and because the
/// learner may well want something that is not a flag at all.
struct FlagField: View {

    @Binding var flag: String

    var body: some View {
        TextField("", text: $flag, prompt: Text("🏳️"))
            .textFieldStyle(.plain)
            .font(.title3)
            .multilineTextAlignment(.center)
            .frame(width: 44, height: 26)
            .background {
                RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                    .fill(Palette.subtleFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                    .strokeBorder(Palette.separator)
            }
            // Whatever is pasted, one character of it is kept: a flag is one
            // thing, and a pasted sentence in this field would push the name
            // off the row.
            .onChange(of: flag) {
                if let first = flag.first, flag.count > 1 {
                    flag = String(first)
                }
            }
            .accessibilityLabel("Flag")
    }
}
