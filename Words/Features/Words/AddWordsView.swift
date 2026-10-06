import SwiftUI

/// Where words are added: one at a time, or a list at once.
///
/// Its own screen rather than a sheet, because adding vocabulary is the thing a
/// learner does most often and it is where the app will grow first. The single
/// form keeps the cursor and clears itself, so twenty words are twenty typings
/// and nothing else.
struct AddWordsView: View {
    let profile: LanguageProfile

    @Environment(LibraryStore.self) private var store
    @Environment(Router.self) private var router

    @State private var term = ""
    @State private var meaning = ""
    @State private var gender: Gender?
    @State private var transcription = ""
    @State private var example = ""
    @State private var exampleTranslation = ""
    @State private var note = ""
    @State private var deckID: UUID?

    /// What this sitting has put in, newest first. Kept as identifiers so the
    /// rows follow any later edit.
    @State private var added: [UUID] = []

    /// A drawing or a photo chosen before the word it belongs to exists. It is
    /// held here until the word is added, then written to the library with it.
    @State private var drawing: DrawingContent = .none


    @FocusState private var focus: Field?

    private enum Field { case term, meaning, transcription, example, exampleTranslation, note }

    var body: some View {
        // The mode is read inside the switch and the picker, never here. The
        // toolbar is made from this body, and a body that changed with the
        // mode handed AppKit a new toolbar on every click — which laid out
        // again the very control that had been clicked, halfway through its
        // animation.
        AddModeSwitch(
            oneWord: single,
            list: ImportWordsView(profile: profile, deckID: $deckID),
            anki: AnkiImportView(profile: profile)
        )
        .navigationTitle(AppSection.add.title)
        .navigationSubtitle(profile.languagePair)
        .toolbar {
            ToolbarItem(id: "add.mode", placement: .principal) {
                AddModePicker()
            }
        }
        .task {
            focus = .term
            deckID = router.lastDeckID
        }
        .onChange(of: router.addWordsFocus) { focus = .term }
        .onChange(of: router.lastDeckID) {
            // Arriving from a deck files into that deck: filling a shelf should
            // not mean choosing it again for every word.
            deckID = router.lastDeckID
        }
    }

    // MARK: - One word

    private var single: some View {
        Form {
            Section {
                TextField(LanguageCatalog.name(for: profile.learningCode), text: $term, prompt: Text("Word"))
                    .focused($focus, equals: .term)
                    .onSubmit { focus = .meaning }

                TextField(LanguageCatalog.name(for: profile.nativeCode), text: $meaning, prompt: Text("Meaning"))
                    .focused($focus, equals: .meaning)
                    .onSubmit { add() }

                TextField("Said", text: $transcription, prompt: Text("Optional"))
                    .focused($focus, equals: .transcription)
                    .onSubmit { add() }

                if marksGender {
                    Picker("Gender", selection: $gender) {
                        Text("—").tag(Gender?.none)
                        ForEach(Gender.allCases) { gender in
                            Text(articleLabel(for: gender)).tag(Optional(gender))
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
            } header: {
                Text("New Word")
            } footer: {
                Text(marksGender
                     ? "Type the article with the word — “die Mutter” — and the gender is filed for you."
                     : "The word as you want to be asked it, and what it means in \(LanguageCatalog.name(for: profile.nativeCode)).")
            }

            Section {
                TextField("Example", text: $example, prompt: Text("Optional"), axis: .vertical)
                    .lineLimit(1...3)
                    .focused($focus, equals: .example)

                TextField("Translation", text: $exampleTranslation, prompt: Text("Optional"), axis: .vertical)
                    .lineLimit(1...3)
                    .focused($focus, equals: .exampleTranslation)

                TextField("Note", text: $note, prompt: Text("Optional"), axis: .vertical)
                    .lineLimit(1...3)
                    .focused($focus, equals: .note)
            }

            Section("Drawing") {
                AssociationEditor(
                    term: term,
                    meaning: meaning,
                    load: { drawing },
                    save: { drawing = $0 }
                )
                // A fresh row for each word added, so the drawing that has just
                // gone into the library does not linger on the next word.
                .id(added.count)
                .padding(.vertical, 2)
            }

            Section {
                Button("Add Word") { add() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isComplete)
            }

            if !recent.isEmpty {
                Section("Added Just Now") {
                    ForEach(recent) { entry in
                        row(for: entry)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: Metrics.readableWidth + 120)
        .frame(maxWidth: .infinity)
    }

    private var marksGender: Bool {
        LanguageGenders.marksGender(profile.learningCode)
    }

    /// "die" reads better than "Feminine" on a button a German learner presses
    /// twenty times a day.
    private func articleLabel(for gender: Gender) -> String {
        LanguageGenders.article(gender, language: profile.learningCode) ?? gender.short
    }

    private var decks: [Deck] {
        store.library.decks(in: profile.id)
    }

    private var recent: [Entry] {
        added.compactMap { store.library.entry(id: $0) }
    }

    private var isComplete: Bool {
        !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func row(for entry: Entry) -> some View {
        HStack(spacing: 12) {
            Text(entry.displayTerm(in: profile))
                .font(.body.weight(.medium))
                .lineLimit(1)

            Text(entry.meaning)
                .foregroundStyle(Palette.secondaryText)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button("Edit", systemImage: "pencil") { router.editWord(entry.id) }
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .foregroundStyle(Palette.secondaryText)
                .help("Edit this word")

            Button("Delete", systemImage: "trash") {
                store.deleteEntries(ids: [entry.id])
                added.removeAll { $0 == entry.id }
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            .foregroundStyle(Palette.secondaryText)
            .help("Delete this word")
        }
    }

    private func add() {
        guard isComplete else { return }

        // "die Mutter" is how a German learner writes a noun; the gender is in
        // what they typed, and asking for it again would be asking twice.
        let (bare, typed) = LanguageGenders.split(term: term, language: profile.learningCode)

        guard let entry = store.addEntry(
            profileID: profile.id,
            deckID: deckID,
            term: bare,
            meaning: meaning,
            gender: gender ?? typed,
            transcription: transcription,
            example: example,
            exampleTranslation: exampleTranslation,
            note: note
        ) else { return }

        switch drawing {
        case .none:
            break
        case .drawing(let data, let strokes):
            Task { await store.attachAssociation(data, strokeCount: strokes, to: entry.id) }
        case .photo(let data, let fileExtension):
            Task { await store.attachPicture(data, fileExtension: fileExtension, to: entry.id) }
        }

        added.insert(entry.id, at: 0)
        term = ""
        meaning = ""
        gender = nil
        transcription = ""
        example = ""
        exampleTranslation = ""
        note = ""
        drawing = .none
        focus = .term
    }
}

/// The three sides of the screen, with the one the mode asks for in front.
///
/// The sides are kept, not rebuilt, once they have been made. Making one is a
/// whole form or a list editor laid out from nothing, a few frames of work on
/// the main thread; switching between kept ones is only a change of which is
/// visible. Those frames are the ones the mode control needs for its glass to
/// settle, and taking them showed as a lens that froze and then jumped. A kept
/// side also keeps what was typed in it, which is what someone who looks at the
/// other side for a moment expects to find when they come back.
private struct AddModeSwitch<OneWord: View, WordList: View, Anki: View>: View {
    let oneWord: OneWord
    let list: WordList
    let anki: Anki

    @Environment(Router.self) private var router

    /// The sides that exist. The one on show is made at once; the others a
    /// moment after the screen has arrived, when nothing is animating.
    @State private var made: Set<AddMode> = []

    var body: some View {
        ZStack {
            side(.single) { oneWord }
            side(.list) { list }
            side(.anki) { anki }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(500))
            made.formUnion(AddMode.allCases)
        }
        .onChange(of: router.addMode, initial: true) { made.insert(router.addMode) }
    }

    @ViewBuilder
    private func side(_ mode: AddMode, @ViewBuilder content: () -> some View) -> some View {
        let isShown = router.addMode == mode
        if isShown || made.contains(mode) {
            content()
                .opacity(isShown ? 1 : 0)
                // A hidden side must not take a drop, a click, the focus or
                // Return: each side has a default button of its own.
                .allowsHitTesting(isShown)
                .disabled(!isShown)
                .accessibilityHidden(!isShown)
        }
    }
}

/// The control that chooses between adding one word, a list, or a deck.
///
/// It shows the segment that was clicked at once and hands the choice on a
/// moment later, because of where a click on a segmented control is handled:
/// inside the control's own event loop, which is also where its glass
/// animation plays. Building a whole screen — a form, a list editor, an
/// import — inside that loop took the animation's frames for itself, which is
/// why a click looked flat and a drag, which only commits on release, did not.
private struct AddModePicker: View {
    @Environment(Router.self) private var router

    /// The segment clicked, until the screen has caught up with it.
    @State private var chosen: AddMode?

    var body: some View {
        Picker("Add", selection: Binding(
            get: { chosen ?? router.addMode },
            set: { choose($0) }
        )) {
            ForEach(AddMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 300)
        // The menu bar can change the mode too; the control follows it.
        .onChange(of: router.addMode) { chosen = nil }
    }

    private func choose(_ mode: AddMode) {
        guard mode != (chosen ?? router.addMode) else { return }
        chosen = mode
        // The default mode is the one the run loop returns to once the
        // control's tracking is over; nothing queued for it runs while the
        // click is still being handled.
        nonisolated(unsafe) let router = router
        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeIsolated { router.addMode = mode }
        }
    }
}
