import SwiftUI
import UniformTypeIdentifiers

/// Adding a list of words at once: pasted, dropped, or chosen from disk.
///
/// The screen reads the list as it is typed and says what it found before
/// anything is added — how many words, which lines it could not read, and which
/// ones the language already has. An import that surprises the owner
/// afterwards is an import that should have shown its work first.
struct ImportWordsView: View {
    let profile: LanguageProfile

    @Binding var deckID: UUID?

    @Environment(LibraryStore.self) private var store
    @Environment(Router.self) private var router

    @State private var text = ""
    @State private var plan = ImportPlan()
    @State private var isChoosingFile = false
    @State private var isTargeted = false
    @State private var added: Int?
    @State private var failure: String?

    /// The companion writing examples for rows that have none, and what it
    /// wrote. Kept beside the plan rather than in it: the list is read again
    /// from the text on every keystroke, and a sentence that took the model
    /// five seconds must not vanish because a letter was typed three lines
    /// below it. Filed under the word, which is what survives a reread.
    @State private var writer = SentenceWriter()
    @State private var written: [String: Written] = [:]

    /// An example written for a word that is not in the library yet.
    private struct Written {
        var sentence: String
        var translation: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
            editor
            summary

            if !plan.words.isEmpty {
                preview
            }

            footer
        }
        .frame(maxWidth: Metrics.pageWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
        .pageInsets()
        .onChange(of: text) { reread() }
        .onChange(of: store.library.entries.count) { reread() }
        .fileImporter(
            isPresented: $isChoosingFile,
            allowedContentTypes: Self.readableTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { load(url) }
            case .failure(let error):
                failure = error.localizedDescription
            }
        }
        .alert("The file could not be read", isPresented: .init(
            get: { failure != nil },
            set: { if !$0 { failure = nil } }
        )) {
            Button("OK", role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }

    // MARK: - The text

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.body.monospaced())
                .scrollContentBackground(.hidden)
                .padding(6)

            if text.isEmpty {
                Text(Self.placeholder)
                    .font(.body.monospaced())
                    .foregroundStyle(Palette.tertiaryText)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 150)
        .background(Palette.card, in: .rect(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(
                    isTargeted ? Palette.selection : Palette.separator,
                    lineWidth: isTargeted ? 1.5 : 1
                )
        }
        .animation(.easeOut(duration: 0.12), value: isTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            load(url)
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private static let placeholder = """
        Haus;house
        Mutter;мама;f;[ˈmʊtɐ];Meine Mutter kocht.;Моя мама готовит.
        gehen;to go;;Ich gehe nach Hause.;;irregular: ging, gegangen

        word;meaning;gender (f, m, n);[transcription];example;translation;note
        Everything after the meaning is optional. A transcription is found by its brackets, so it never needs an empty column.
        """

    // MARK: - What was found

    private var summary: some View {
        HStack(spacing: 14) {
            if let added {
                Label("Added \(added) \(added == 1 ? "word" : "words")", systemImage: "checkmark.circle")
                    .foregroundStyle(Palette.secondaryText)

                Button("Show in Library") {
                    if let deckID { router.show(deck: deckID) } else { router.show(.library) }
                }
                .buttonStyle(.link)
            } else if plan.isEmpty {
                Text("Paste a list, drop a text file here, or choose one.")
                    .foregroundStyle(Palette.secondaryText)
            } else {
                Text(countLine)
                    .foregroundStyle(Palette.secondaryText)
                    .monospacedDigit()
            }

            Spacer(minLength: 0)

            if let refusal = writer.lastRefusal {
                Label(refusal, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Palette.warning)
                    .lineLimit(2)
            }

            ListPromptButton(profile: profile)

            Button("Choose File…") { isChoosingFile = true }
        }
        .font(.callout)
    }

    private var countLine: String {
        var parts: [String] = []
        let ready = plan.importable.count
        parts.append("\(ready) \(ready == 1 ? "word" : "words") ready")

        let duplicates = plan.duplicates.count
        if duplicates > 0 { parts.append("\(duplicates) already here") }

        let problems = plan.problems.count
        if problems > 0 { parts.append("\(problems) \(problems == 1 ? "line" : "lines") skipped") }

        return parts.joined(separator: " · ")
    }

    // MARK: - The preview

    private var preview: some View {
        Table(plan.words) {
            TableColumn("Word") { word in
                HStack(spacing: 4) {
                    if let mark = word.gender.flatMap({
                        LanguageGenders.mark($0, before: word.term, language: profile.learningCode)
                    }) {
                        Text(mark.text).foregroundStyle(Palette.secondaryText)
                    }
                    Text(word.term)
                        .font(.body.weight(.medium))
                    if !word.transcription.isEmpty {
                        Text(word.transcription)
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
                .reads(profile.learningCode)
                .opacity(word.isImportable ? 1 : 0.45)
            }
            .width(min: 100, ideal: 150)

            TableColumn("Meaning") { word in
                Text(word.meaning)
                    .opacity(word.isImportable ? 1 : 0.45)
            }
            .width(min: 90, ideal: 130)

            TableColumn("Example") { word in
                example(for: word)
                    .opacity(word.isImportable ? 1 : 0.45)
            }
            // Wide, because what goes in it is a whole sentence and, once the
            // companion has written one, its translation underneath.
            .width(min: 140, ideal: 320)

            TableColumn("") { word in
                if word.duplicate != nil {
                    Text("Already here")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            .width(min: 70, ideal: 90)
        }
        .alternatingRowBackgrounds(.disabled)
        .frame(height: 210)
    }

    /// What the Example column shows: the example the list carried, the one
    /// the companion wrote — which can be corrected here, where it is read —
    /// or the button that asks for one.
    @ViewBuilder
    private func example(for word: ImportedWord) -> some View {
        let key = WordImport.key(word.term)

        if written[key] != nil {
            VStack(alignment: .leading, spacing: 1) {
                TextField("Example", text: sentence(of: key))
                    .textFieldStyle(.plain)
                TextField("Translation", text: translation(of: key))
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            }
        } else if !word.example.isEmpty {
            Text(word.example)
                .foregroundStyle(Palette.secondaryText)
        } else if word.isImportable {
            HStack(spacing: 6) {
                SentenceButton(
                    profile: profile,
                    key: key,
                    word: word.term,
                    meaning: word.meaning,
                    showsTitle: false,
                    writer: writer,
                    filled: { sentence, translation in
                        written[key] = Written(sentence: sentence, translation: translation)
                    }
                )
                if let refusal = writer.refusal(for: key) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Palette.warning)
                        .help(refusal)
                }
            }
        }
    }

    private func sentence(of key: String) -> Binding<String> {
        Binding(
            get: { written[key]?.sentence ?? "" },
            set: { written[key]?.sentence = $0 }
        )
    }

    private func translation(of key: String) -> Binding<String> {
        Binding(
            get: { written[key]?.translation ?? "" },
            set: { written[key]?.translation = $0 }
        )
    }

    // MARK: - Doing it

    private var footer: some View {
        HStack(spacing: 12) {
            if !decks.isEmpty {
                Picker("Deck", selection: $deckID) {
                    Text("None").tag(UUID?.none)
                    Divider()
                    ForEach(decks) { deck in
                        Text(store.library.path(of: deck)).tag(Optional(deck.id))
                    }
                }
                .frame(maxWidth: 260)
            }

            Spacer(minLength: 0)

            if !text.isEmpty {
                Button("Clear") {
                    text = ""
                    added = nil
                    writer.cancel()
                    written = [:]
                }
            }

            Button(importTitle) { performImport() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(plan.importable.isEmpty)
        }
    }

    private var importTitle: String {
        let count = plan.importable.count
        guard count > 0 else { return "Import" }
        return "Import \(count) \(count == 1 ? "Word" : "Words")"
    }

    private var decks: [Deck] {
        store.library.decks(in: profile.id)
    }

    private func reread() {
        // Clearing the box is what an import does last; the line saying what it
        // added has to survive that, and go only when a new list is typed.
        if !text.isEmpty { added = nil }
        plan = WordImport.plan(
            text: text,
            language: profile.learningCode,
            existing: store.library.entries(in: profile.id)
        )
    }

    private func performImport() {
        let count = store.addEntries(importing, profileID: profile.id, deckID: deckID)
        text = ""
        plan = ImportPlan()
        writer.cancel()
        written = [:]
        added = count
    }

    /// The words to add, with whatever the companion wrote for them. The plan
    /// stays what the text says; this is where the two are put together, once,
    /// at the moment it matters.
    private var importing: [ImportedWord] {
        plan.importable.map { word in
            guard word.example.isEmpty, let written = written[WordImport.key(word.term)] else { return word }
            var word = word
            word.example = written.sentence
            word.exampleTranslation = written.translation
            return word
        }
    }

    // MARK: - Files

    private static let readableTypes: [UTType] = {
        var types: [UTType] = [.plainText, .utf8PlainText, .text, .delimitedText, .commaSeparatedText, .tabSeparatedText]
        if let markdown = UTType(filenameExtension: "md") { types.append(markdown) }
        return types
    }()

    private func load(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            // A word list can come from anywhere, and not everything on a Mac
            // is UTF-8. Reading it wrong is worse than reading it slowly.
            guard let contents = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16)
                ?? String(data: data, encoding: .isoLatin1)
            else {
                failure = "Its text is in an encoding this app does not recognise."
                return
            }
            text = contents
        } catch {
            failure = error.localizedDescription
        }
    }
}
