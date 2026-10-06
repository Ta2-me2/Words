import SwiftUI

/// Changing a word that is already in the library.
///
/// Adding happens on its own screen; this is the sheet that opens on a
/// double click, from the hard-to-remember list, or from the row that was just
/// added. It edits the word and leaves its schedule alone — a spelling
/// correction is not a reason to start learning something again.
struct WordEditor: View {
    let entry: Entry
    let profile: LanguageProfile

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var term: String
    @State private var meaning: String
    @State private var gender: Gender?
    @State private var transcription: String
    @State private var example: String
    @State private var exampleTranslation: String
    @State private var note: String
    @State private var deckID: UUID?

    @FocusState private var isFocused: Bool

    init(entry: Entry, profile: LanguageProfile) {
        self.entry = entry
        self.profile = profile
        _term = State(initialValue: entry.term)
        _meaning = State(initialValue: entry.meaning)
        _gender = State(initialValue: entry.gender)
        _transcription = State(initialValue: entry.transcription)
        _example = State(initialValue: entry.example)
        _exampleTranslation = State(initialValue: entry.exampleTranslation)
        _note = State(initialValue: entry.note)
        _deckID = State(initialValue: entry.deckID)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Word", subtitle: profile.languagePair)

            Form {
                Section {
                    TextField(LanguageCatalog.name(for: profile.learningCode), text: $term, prompt: Text("Word"))
                        .focused($isFocused)

                    TextField(LanguageCatalog.name(for: profile.nativeCode), text: $meaning, prompt: Text("Meaning"))

                    TextField("Said", text: $transcription, prompt: Text("Optional"))

                    if LanguageGenders.marksGender(profile.learningCode) {
                        Picker("Gender", selection: $gender) {
                            Text("—").tag(Gender?.none)
                            ForEach(Gender.allCases) { gender in
                                Text(LanguageGenders.article(gender, language: profile.learningCode) ?? gender.short)
                                    .tag(Optional(gender))
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if !decks.isEmpty {
                        Picker("Deck", selection: $deckID) {
                            Text("None").tag(UUID?.none)
                            Divider()
                            ForEach(decks) { deck in
                                Text(store.library.path(of: deck)).tag(Optional(deck.id))
                            }
                        }
                    }
                }

                Section("Audio") {
                    AudioEditor(entry: entry, profile: profile)
                        .padding(.vertical, 2)
                }

                Section("Drawing") {
                    AssociationEditor(
                        term: term,
                        meaning: meaning,
                        load: {
                            if let picture = entry.picture,
                               let data = try? Data(contentsOf: store.mediaURL(for: picture.file)) {
                                return .photo(data, fileExtension: (picture.file as NSString).pathExtension)
                            }
                            if let association = entry.association, let data = store.associationData(for: association) {
                                return .drawing(data, strokes: association.strokeCount)
                            }
                            return .none
                        },
                        save: { content in
                            let id = entry.id
                            switch content {
                            case .none:
                                store.removePicture(from: id)
                                store.removeAssociation(from: id)
                            case .drawing(let data, let strokes):
                                store.removePicture(from: id)
                                Task { await store.attachAssociation(data, strokeCount: strokes, to: id) }
                            case .photo(let data, let fileExtension):
                                Task { await store.attachPicture(data, fileExtension: fileExtension, to: id) }
                            }
                        }
                    )
                    .padding(.vertical, 2)
                }

                Section {
                    TextField("Example", text: $example, prompt: Text("Optional"), axis: .vertical)
                        .lineLimit(1...3)

                    TextField("Translation", text: $exampleTranslation, prompt: Text("Optional"), axis: .vertical)
                        .lineLimit(1...3)

                    TextField("Note", text: $note, prompt: Text("Optional"), axis: .vertical)
                        .lineLimit(1...3)
                } footer: {
                    Text(scheduleLine)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack(spacing: 10) {
                Button("Delete", role: .destructive) {
                    store.deleteEntries(ids: [entry.id])
                    dismiss()
                }

                Spacer(minLength: 0)

                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isComplete)
            }
            .padding(Metrics.cardPadding)
        }
        .frame(width: 480, height: 560)
        .task { isFocused = true }
    }

    private var decks: [Deck] {
        store.library.decks(in: profile.id)
    }

    /// Where the word stands, said in the sheet rather than left to the table:
    /// somebody editing a word they keep forgetting deserves to see why it
    /// keeps coming back.
    private var scheduleLine: String {
        guard let state = entry.recognitionCard?.scheduling else { return "" }
        switch state.stage {
        case .new:
            return "Not started yet."
        case .learning, .relearning:
            return "Being learned · next \(DueText.describe(state.dueDate, now: .now).lowercased())"
        case .review:
            let interval = IntervalText.days(state.intervalDays)
            let forgotten = state.lapses > 0 ? " · forgotten \(state.lapses)×" : ""
            return "Interval \(interval) · next \(DueText.describe(state.dueDate, now: .now).lowercased())\(forgotten)"
        }
    }

    private var isComplete: Bool {
        !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        // The article may have been typed into the word field here too.
        let (bare, typed) = LanguageGenders.split(term: term, language: profile.learningCode)
        store.editEntry(
            id: entry.id,
            term: bare,
            meaning: meaning,
            gender: gender ?? typed,
            transcription: transcription,
            example: example,
            exampleTranslation: exampleTranslation,
            note: note
        )
        if deckID != entry.deckID {
            store.move(entries: [entry.id], toDeck: deckID)
        }
        dismiss()
    }
}
