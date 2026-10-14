import AppKit
import SwiftUI

/// Add Words ▸ One Word — an empty card, filled in.
///
/// The screen is the thing it makes. Every field stands where the finished card
/// puts what goes in it: the word large and in the middle with its article
/// beside it, the way it is said underneath, the picture under that, then the
/// line the card draws when the answer comes out, and below it the meaning, the
/// example and its translation, and the note last of all. Somebody who has
/// studied one card knows what this screen is before reading a word of it, and
/// knows what they are making while they make it.
///
/// A form would have been less work and is what this was. But a form teaches
/// the shape of a form, and the shape worth teaching here is the card.
struct WordCardEditor: View {
    let profile: LanguageProfile

    /// Shared with the list side, and with the deck a learner arrived from.
    @Binding var deckID: UUID?

    @Environment(LibraryStore.self) private var store
    @Environment(Router.self) private var router
    private let speaker = Speaker.shared

    @State private var term = ""
    @State private var meaning = ""
    @State private var gender: Gender?
    @State private var transcription = ""
    @State private var example = ""
    @State private var exampleTranslation = ""
    @State private var note = ""

    /// A drawing or a photo chosen before the word it belongs to exists. It is
    /// held here until the word is added, then written to the library with it.
    @State private var drawing: DrawingContent = .none
    @State private var thumbnail: NSImage?
    @State private var isDrawing = false
    @State private var isChoosingPhoto = false
    @State private var isTargeted = false

    /// What this sitting has put in, newest first. Kept as identifiers so the
    /// rows follow any later edit.
    @State private var added: [UUID] = []

    /// The companion writing an example for the word in the card. Its own
    /// object, so a request in flight survives the card being retyped around
    /// it — and is let go of the moment the word it was for changes.
    @State private var writer = SentenceWriter()

    /// The word being written has no identifier yet, and the speaker wants one
    /// to say which word it is reading. This stands in for it until there is a
    /// real one, and is never written anywhere.
    @State private var draftID = UUID()

    @FocusState private var focus: Field?

    /// The order the card is filled in, which is also the order Tab walks.
    private enum Field: Int, CaseIterable {
        case term, transcription, meaning, example, exampleTranslation, note

        var after: Field {
            Self.allCases[(Self.allCases.firstIndex(of: self)! + 1) % Self.allCases.count]
        }

        var before: Field {
            Self.allCases[(Self.allCases.firstIndex(of: self)! + Self.allCases.count - 1) % Self.allCases.count]
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                card
                beneath
                if !recent.isEmpty { addedJustNow }
            }
            .frame(maxWidth: Metrics.pageWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .pageInsets()
        }
        .task { focus = .term }
        .onChange(of: router.addWordsFocus) { focus = .term }
        .onChange(of: bareTerm) {
            // A sentence that arrives for a word no longer in the card would
            // be an example of something else entirely.
            if writer.isWriting { writer.cancel() }
            writer.forget()
        }
        .onDisappear { speaker.stop() }
        .onChange(of: router.addMode) { speaker.stop() }
        .sheet(isPresented: $isDrawing) {
            AssociationSheet(term: bareTerm, meaning: meaning, existing: existingDrawing) { drawn, strokes in
                take(strokes == 0 ? .none : .drawing(drawn, strokes: strokes))
            }
        }
        .fileImporter(isPresented: $isChoosingPhoto, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result { takePhoto(from: url) }
        }
    }

    // MARK: - The card

    private var card: some View {
        VStack(spacing: 16) {
            word
            said
            picture

            // The line the card draws between what is asked and what answers
            // it. Here it says the same thing: above it is the word, below it
            // is everything the learner is trying to remember about the word.
            Divider().frame(width: 96)

            means
            sentence
            sentenceMeaning
            remark
        }
        .frame(maxWidth: Metrics.readableWidth)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, Metrics.cardPadding)
        .background(Palette.card, in: .rect(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Palette.separator, lineWidth: 1)
        }
        // Tab is written down here rather than left to the window's own idea of
        // what comes next: the order a card is filled in is the order it reads
        // in, and it should not change when the layout does.
        .onKeyPress(.tab, phases: .down) { press in
            guard let focus else { return .ignored }
            self.focus = press.modifiers.contains(.shift) ? focus.before : focus.after
            return .handled
        }
    }

    private var word: some View {
        slot(LanguageCatalog.name(for: profile.learningCode), field: .term, trailing: {
            if canHearWord {
                speakButton(systemImage: "speaker.wave.2", scale: .large, help: "Hear how the Mac says it") {
                    speaker.speak(spokenTerm, in: profile, entryID: draftID)
                }
                .disabled(bareTerm.isEmpty)
            }
        }, content: {
            HStack(spacing: 10) {
                if marksGender { articles }

                TextField("", text: $term, prompt: Text("Word"))
                    .textFieldStyle(.plain)
                    .font(.largeTitle.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .focused($focus, equals: .term)
                    .onSubmit { focus = .meaning }
            }
            // So the gender control sits on the side of the word the card
            // will put the mark on, and an Arabic word is typed from the
            // right-hand edge of its field.
            .reads(profile.learningCode)
        }, footnote: genderFootnote)
    }

    /// Where the card shows "der", "die" or "das", so does this — and where
    /// it shows "жен.", so does this.
    ///
    /// Over the genders the *language* has, never over every gender there is:
    /// Spanish has two and Dutch's two are not the same two, and a control
    /// offering a third would be asking about something the language does not
    /// do.
    private var articles: some View {
        Picker("Gender", selection: $gender) {
            ForEach(genderChoices, id: \.self) { choice in
                Text(choice.map(markLabel) ?? "—").tag(choice)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    private var said: some View {
        slot("Said", field: .transcription) {
            TextField("", text: $transcription, prompt: Text("Optional"))
                .textFieldStyle(.plain)
                .font(.title3)
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)
                .focused($focus, equals: .transcription)
                .reads(profile.learningCode)
        }
    }

    private var means: some View {
        slot(LanguageCatalog.name(for: profile.nativeCode), field: .meaning) {
            TextField("", text: $meaning, prompt: Text("Meaning"), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.title)
                .lineLimit(1 ... 3)
                .multilineTextAlignment(.center)
                .focused($focus, equals: .meaning)
        }
    }

    private var sentence: some View {
        slot("Example", field: .example, trailing: {
            SentenceButton(
                profile: profile,
                key: bareTerm,
                word: bareTerm,
                meaning: meaning,
                showsTitle: false,
                writer: writer,
                filled: { sentence, translation in
                    example = sentence
                    exampleTranslation = translation
                }
            )

            if canHearWord {
                speakButton(systemImage: "speaker.wave.2", scale: .medium, help: "Hear the example") {
                    speaker.speak(example, in: profile, entryID: draftID)
                }
                .disabled(example.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }, content: {
            TextField("", text: $example, prompt: Text("Optional"), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.callout.italic())
                .lineLimit(1 ... 3)
                .multilineTextAlignment(.center)
                .focused($focus, equals: .example)
                .reads(profile.learningCode)
        }, footnote: writer.refusal(for: bareTerm))
    }

    private var sentenceMeaning: some View {
        slot("Translation", field: .exampleTranslation) {
            TextField("", text: $exampleTranslation, prompt: Text("Optional"), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundStyle(Palette.secondaryText)
                .lineLimit(1 ... 3)
                .multilineTextAlignment(.center)
                .focused($focus, equals: .exampleTranslation)
        }
    }

    private var remark: some View {
        slot("Note", field: .note) {
            TextField("", text: $note, prompt: Text("Optional"), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundStyle(Palette.tertiaryText)
                .lineLimit(1 ... 4)
                .multilineTextAlignment(.center)
                .focused($focus, equals: .note)
        }
    }

    // MARK: - One field of the card

    /// A field where the card puts the thing it holds: what it is called above
    /// it, the field itself in a well that lights up when it is being typed
    /// into, and — where there is something worth saying — a line under it.
    private func slot<Content: View, Trailing: View>(
        _ label: String,
        field: Field,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder content: () -> Content,
        footnote: String? = nil
    ) -> some View {
        let isFocused = focus == field

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Palette.tertiaryText)
                Spacer(minLength: 8)
                trailing()
            }

            content()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    Palette.subtleFill.opacity(isFocused ? 0.5 : 0.3),
                    in: .rect(cornerRadius: Metrics.smallRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                        .strokeBorder(
                            isFocused ? Palette.selection : Palette.separator,
                            lineWidth: isFocused ? 2 : 1
                        )
                }
                .contentShape(.rect)
                .onTapGesture { focus = field }

            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(footnote == writer.refusal(for: bareTerm) ? Palette.warning : Palette.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(.easeOut(duration: 0.12), value: isFocused)
    }

    private func speakButton(
        systemImage: String,
        scale: Image.Scale,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: speaker.speakingEntryID == draftID ? "speaker.wave.2.fill" : systemImage)
                .imageScale(scale)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Palette.secondaryText)
        .help(help)
    }

    // MARK: - The picture

    /// A word has one place for a picture and two ways of filling it, so the
    /// row is one slot with two doors: a photograph on the left, a drawing of
    /// your own on the right. Once either is through, the row shows what came
    /// in — and the other door is not offered, because the library would
    /// refuse it.
    private var picture: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Picture")
                .font(.caption)
                .foregroundStyle(Palette.tertiaryText)

            if drawing == .none {
                HStack(spacing: 10) {
                    door(
                        title: "Photo",
                        subtitle: "Drop one here, paste, or choose",
                        systemImage: "photo",
                        action: { isChoosingPhoto = true }
                    )
                    .overlay(alignment: .bottom) {
                        if canPaste {
                            Button("Paste") { paste() }
                                .buttonStyle(.link)
                                .font(.caption)
                                .padding(.bottom, 8)
                        }
                    }

                    door(
                        title: "Association",
                        subtitle: bareTerm.isEmpty ? "Type the word first" : "Draw what it reminds you of",
                        systemImage: "lightbulb",
                        action: { isDrawing = true }
                    )
                    .disabled(bareTerm.isEmpty)
                }
                .frame(height: 132)
                .dropDestination(for: URL.self) { urls, _ in
                    guard let url = urls.first else { return false }
                    takePhoto(from: url)
                    return true
                } isTargeted: { isTargeted = $0 }
            } else {
                taken
            }
        }
    }

    private func door(title: String, subtitle: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 22))
                    .foregroundStyle(Palette.tertiaryText)
                Text(title)
                    .font(.callout.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(Palette.subtleFill.opacity(0.3), in: .rect(cornerRadius: Metrics.smallRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                .strokeBorder(
                    isTargeted ? Palette.selection : Palette.separator,
                    style: StrokeStyle(lineWidth: isTargeted ? 1.5 : 1, dash: [6, 4])
                )
        }
        .animation(.easeOut(duration: 0.12), value: isTargeted)
    }

    private var taken: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Color.clear
                }
            }
            .frame(width: 160, height: 104)
            .background(isDrawn ? AssociationCanvas.paper : Palette.subtleFill)
            .clipShape(.rect(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Palette.separator)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(isDrawn ? "An association of your own" : "A photograph")
                    .font(.callout)
                Button(isDrawn ? "Edit…" : "Replace…") {
                    if isDrawn { isDrawing = true } else { isChoosingPhoto = true }
                }
                .buttonStyle(.link)
                Button("Remove", role: .destructive) { take(.none) }
                    .buttonStyle(.link)
            }
            .font(.callout)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Under the card

    private var beneath: some View {
        VStack(spacing: 10) {
            // A deck is not part of the card — it is where the card is filed —
            // so it sits under it rather than on it.
            if !decks.isEmpty {
                HStack(spacing: 12) {
                    Text("Deck")
                        .foregroundStyle(Palette.secondaryText)
                    Spacer(minLength: 8)
                    Picker("Deck", selection: $deckID) {
                        Text("None").tag(UUID?.none)
                        Divider()
                        ForEach(decks) { deck in
                            Text(store.library.path(of: deck)).tag(Optional(deck.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 280)
                }
            }

            Button("Add Word") { add() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .keyboardShortcut(.defaultAction)
                .disabled(!isComplete)
        }
        .frame(maxWidth: Metrics.readableWidth)
        .frame(maxWidth: .infinity)
    }

    private var addedJustNow: some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            SectionHeader("Added Just Now")

            GroupedRows {
                ForEach(Array(recent.enumerated()), id: \.element.id) { index, entry in
                    GroupedRow(showsDivider: index < recent.count - 1) {
                        row(for: entry)
                    }
                }
            }
        }
        .frame(maxWidth: Metrics.readableWidth)
        .frame(maxWidth: .infinity)
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

    // MARK: - What it knows

    private var marksGender: Bool {
        LanguageGenders.marksGender(profile.learningCode)
    }

    /// What to say under the word about its gender, which is a different
    /// sentence depending on what the language does with it. A language that
    /// has an article has something to type; a language that only shows the
    /// gender has something to choose, and the learner should know up front
    /// that it will not be read out.
    private var genderFootnote: String? {
        guard let first = LanguageGenders.genders(for: profile.learningCode).first,
              let mark = LanguageGenders.mark(first, language: profile.learningCode)
        else { return nil }

        return mark.isSpoken
            ? "Type the article with the word and the gender is filed for you."
            : "Shown beside the word on the card, and never read aloud."
    }

    /// "die" reads better than "Feminine" on a button a German learner presses
    /// twenty times a day, and "жен." reads better than either for a Russian
    /// one. Both come from the same place, which is how the button and the
    /// card are guaranteed to agree.
    /// The choices in the order they should be read: nothing chosen, then the
    /// genders the language has.
    ///
    /// Reversed for a language read right to left, because the segmented
    /// control underneath is an AppKit one and lays its segments out left to
    /// right whatever the environment around it says. An Arabic learner
    /// therefore meets the empty choice first — from the right — exactly as a
    /// German one does from the left.
    private var genderChoices: [Gender?] {
        let choices: [Gender?] = [nil] + LanguageGenders.genders(for: profile.learningCode).map { $0 }
        return LanguageCatalog.isRightToLeft(profile.learningCode) ? choices.reversed() : choices
    }

    private func markLabel(for gender: Gender) -> String {
        LanguageGenders.mark(gender, language: profile.learningCode)?.text ?? gender.short
    }

    /// The word without the article typed in front of it. "die Mutter" is how
    /// a German learner writes a noun, and "die Mutter" is not a word the
    /// companion can be asked to use in a sentence.
    private var bareTerm: String {
        LanguageGenders.split(term: term, language: profile.learningCode).0
    }

    /// What the speaker is given: the article with the word, the way the card
    /// says it.
    private var spokenTerm: String {
        let (bare, typed) = LanguageGenders.split(term: term, language: profile.learningCode)
        guard let which = gender ?? typed,
              let article = LanguageGenders.article(which, language: profile.learningCode)
        else { return bare }
        return "\(article) \(bare)"
    }

    /// The app only ever offers to say a word out loud where there is a voice
    /// to say it with. A word that does not exist yet can have no recording of
    /// its own, so the language's voice is the whole of the question.
    private var canHearWord: Bool {
        Speaker.voice(for: profile) != nil
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

    private var isDrawn: Bool {
        if case .drawing = drawing { return true }
        return false
    }

    private var existingDrawing: Data? {
        if case .drawing(let data, _) = drawing { return data }
        return nil
    }

    private var canPaste: Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil)
    }

    // MARK: - Doing

    private func take(_ content: DrawingContent) {
        drawing = content
        switch content {
        case .none: thumbnail = nil
        case .drawing(let data, _): thumbnail = AssociationRenderer.image(from: data)
        case .photo(let data, _): thumbnail = NSImage(data: data)
        }
    }

    private func takePhoto(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let prepared = PhotoPreparation.prepare(data) else { return }
        take(.photo(prepared.data, fileExtension: prepared.fileExtension))
    }

    private func paste() {
        guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage,
              let tiff = image.tiffRepresentation,
              let prepared = PhotoPreparation.prepare(tiff)
        else { return }
        take(.photo(prepared.data, fileExtension: prepared.fileExtension))
    }

    private func add() {
        guard isComplete else { return }
        // The card is about to be emptied; anything still being written for it
        // is for a word that will no longer be in it.
        writer.cancel()
        speaker.stop()

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
        take(.none)
        draftID = UUID()
        focus = .term
    }
}
