import Foundation
import Observation

/// The single in-memory copy of the library, and the only thing the interface
/// ever changes.
///
/// Every edit goes through `update`, which applies it and schedules a save.
/// Views never touch the persistence layer and never ask whether a save
/// worked — they read `saveState`.
@Observable
final class LibraryStore {

    enum LoadState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    enum SaveState: Equatable {
        case saved
        case pending
        case saving
        case failed(String)
    }

    private(set) var library = Library()
    private(set) var loadState: LoadState = .loading
    private(set) var saveState: SaveState = .saved
    private(set) var lastSavedAt: Date?

    /// The rule that decides when a card comes back. Held here so the whole app
    /// answers with one scheduler, and so a different one can be handed in.
    let scheduler: any ReviewScheduler

    private let persistence: any LibraryPersistence
    private var pendingSave: Task<Void, Never>?

    /// Long enough that typing a word does not write the file on every
    /// keystroke, short enough that closing the lid straight after an answer is
    /// safe.
    private let autosaveDelay: Duration = .milliseconds(800)

    init(
        persistence: any LibraryPersistence = FileLibraryPersistence(),
        scheduler: any ReviewScheduler = FSRSScheduler()
    ) {
        self.persistence = persistence
        self.scheduler = scheduler
    }

    // MARK: - Loading

    func load() async {
        loadState = .loading
        do {
            library = try await persistence.load()
            loadState = .ready
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Saving

    func update(_ mutate: (inout Library) -> Void) {
        mutate(&library)
        scheduleSave()
    }

    private func scheduleSave() {
        saveState = .pending
        pendingSave?.cancel()
        pendingSave = Task { [autosaveDelay] in
            try? await Task.sleep(for: autosaveDelay)
            guard !Task.isCancelled else { return }
            await self.saveNow()
        }
    }

    /// Writes immediately. Used when the app is quitting and when a study
    /// session ends, where waiting out the autosave delay would be wrong.
    func saveNow() async {
        pendingSave?.cancel()
        pendingSave = nil
        saveState = .saving
        let snapshot = library
        do {
            try await persistence.save(snapshot)
            saveState = .saved
            lastSavedAt = .now
        } catch {
            saveState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Languages

    @discardableResult
    func addProfile(
        name: String,
        learningCode: String,
        nativeCode: String,
        flag: String? = nil,
        dailyNewLimit: Int = 20,
        dailyReviewLimit: Int? = nil,
        desiredRetention: Double = Retention.standard,
        voiceIdentifier: String? = nil,
        speechRate: Double = 0.45,
        speaksOnReveal: Bool = false,
        speaksExampleOnReveal: Bool = false
    ) -> LanguageProfile {
        let profile = LanguageProfile(
            name: name,
            learningCode: learningCode,
            nativeCode: nativeCode,
            flag: flag,
            dailyNewLimit: dailyNewLimit,
            dailyReviewLimit: dailyReviewLimit,
            desiredRetention: desiredRetention,
            voiceIdentifier: voiceIdentifier,
            speechRate: speechRate,
            speaksOnReveal: speaksOnReveal,
            speaksExampleOnReveal: speaksExampleOnReveal
        )
        update { $0.upsert(profile) }
        return profile
    }

    func save(_ profile: LanguageProfile) {
        update { $0.upsert(profile) }
    }

    func deleteProfile(id: UUID) {
        let files = library.entries
            .filter { $0.profileID == id }
            .flatMap(\.mediaFiles)
        update { $0.removeProfile(id: id) }
        discard(files)
    }

    // MARK: - Decks

    /// Makes a deck, and the decks inside it, in one change.
    ///
    /// One change because the sheet that makes "Germany" can make "A1" and
    /// "A2" in the same breath, and a structure built in one sheet should
    /// arrive in one piece — one save, one undoable moment — rather than as a
    /// parent that briefly has no children.
    @discardableResult
    func addDeck(
        profileID: UUID,
        name: String,
        parentID: UUID? = nil,
        icon: DeckIcon? = nil,
        dailyNewLimit: Int? = nil,
        subdecks: [(name: String, icon: DeckIcon?)] = []
    ) -> Deck? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        guard parentID.map({ library.canNest(nil, inside: $0) }) ?? true else { return nil }

        let deck = Deck(profileID: profileID, name: name, parentID: parentID, icon: icon, dailyNewLimit: dailyNewLimit)

        // Only a deck at the top can hold others.
        let children = parentID == nil
            ? subdecks.compactMap { child -> Deck? in
                let childName = child.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !childName.isEmpty else { return nil }
                return Deck(profileID: profileID, name: childName, parentID: deck.id, icon: child.icon)
            }
            : []

        update { library in
            library.upsert(deck)
            for child in children { library.upsert(child) }
        }
        return deck
    }

    func save(_ deck: Deck) {
        update { $0.upsert(deck) }
    }

    /// Removes a deck and the decks inside it.
    ///
    /// With `includingWords` false no word goes with them: each moves one level
    /// up, which for a deck at the top is the language itself. With it true the
    /// words go too, and so do the recordings, photos and drawings they own.
    func deleteDeck(id: UUID, includingWords: Bool = false) {
        guard includingWords else {
            update { $0.removeDeck(id: id) }
            return
        }

        let doomed = library.entryIDs(inDeck: id)
        let files = library.entries.filter { doomed.contains($0.id) }.flatMap(\.mediaFiles)
        update { $0.removeDeckAndWords(id: id) }
        discard(files)
    }

    func move(entries ids: Set<UUID>, toDeck deckID: UUID?) {
        guard !ids.isEmpty else { return }
        update { $0.move(entries: ids, toDeck: deckID) }
    }

    // MARK: - Words

    /// Adds a word. Blank words are refused here rather than in the sheet, so
    /// no route into the library can create one.
    @discardableResult
    func addEntry(
        profileID: UUID,
        deckID: UUID? = nil,
        term: String,
        meaning: String,
        gender: Gender? = nil,
        transcription: String = "",
        example: String = "",
        exampleTranslation: String = "",
        note: String = ""
    ) -> Entry? {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let meaning = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !meaning.isEmpty else { return nil }

        let entry = Entry(
            profileID: profileID,
            deckID: deckID,
            term: term,
            meaning: meaning,
            gender: gender,
            transcription: transcription.trimmingCharacters(in: .whitespacesAndNewlines),
            example: example.trimmingCharacters(in: .whitespacesAndNewlines),
            exampleTranslation: exampleTranslation.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        update { $0.upsert(entry) }
        return entry
    }

    /// Adds a whole list at once.
    ///
    /// One change and one save for the lot: a two-hundred-word import must not
    /// be two hundred writes to disk.
    @discardableResult
    func addEntries(_ words: [ImportedWord], profileID: UUID, deckID: UUID?) -> Int {
        let entries = words.compactMap { word -> Entry? in
            let term = word.term.trimmingCharacters(in: .whitespacesAndNewlines)
            let meaning = word.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty, !meaning.isEmpty else { return nil }
            return Entry(
                profileID: profileID,
                deckID: deckID,
                term: term,
                meaning: meaning,
                gender: word.gender,
                transcription: word.transcription,
                example: word.example,
                exampleTranslation: word.exampleTranslation,
                note: word.note
            )
        }

        guard !entries.isEmpty else { return 0 }
        update { library in
            for entry in entries { library.upsert(entry) }
        }
        return entries.count
    }

    func editEntry(
        id: UUID,
        term: String,
        meaning: String,
        gender: Gender?,
        transcription: String,
        example: String,
        exampleTranslation: String,
        note: String
    ) {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let meaning = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !meaning.isEmpty else { return }
        update {
            $0.editEntry(
                id: id,
                term: term,
                meaning: meaning,
                gender: gender,
                transcription: transcription.trimmingCharacters(in: .whitespacesAndNewlines),
                example: example.trimmingCharacters(in: .whitespacesAndNewlines),
                exampleTranslation: exampleTranslation.trimmingCharacters(in: .whitespacesAndNewlines),
                note: note.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    /// Starts words over. Their history is kept; their schedules are not.
    func forgetSchedule(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        update { $0.forget(entries: ids) }
    }

    func deleteEntries(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        // The files a word owns go with it; nothing else points at them.
        let files = library.entries
            .filter { ids.contains($0.id) }
            .flatMap(\.mediaFiles)
        update { $0.removeEntries(ids: ids) }
        discard(files)
    }

    // MARK: - Files that belong to a word

    /// Where a word's recording is, for a player to open.
    nonisolated func mediaURL(for relativePath: String) -> URL {
        persistence.mediaURL(for: relativePath)
    }

    /// Takes a recording into the library and hangs it on a word.
    @discardableResult
    func attachAudio(from source: URL, to entryID: UUID, kind: AudioClip.Source, seconds: Double? = nil) async -> Bool {
        guard let entry = library.entry(id: entryID) else { return false }

        let name = "\(entryID.uuidString)-\(UUID().uuidString.prefix(6)).\(source.pathExtension.isEmpty ? "m4a" : source.pathExtension)"
        do {
            let path = try await persistence.importMedia(from: source, as: name)
            let previous = entry.audio?.file
            update { library in
                guard let index = library.entries.firstIndex(where: { $0.id == entryID }) else { return }
                library.entries[index].audio = AudioClip(file: path, source: kind, seconds: seconds)
            }
            // Only once the new one is safely in place.
            if let previous { discard([previous]) }
            return true
        } catch {
            saveState = .failed(error.localizedDescription)
            return false
        }
    }

    /// Takes a pile of recordings in at once.
    ///
    /// Every file is copied first and the library is changed once, so a folder
    /// of two hundred recordings is one edit and one save rather than two
    /// hundred of each.
    @discardableResult
    func attachAudio(_ items: [(url: URL, entryID: UUID)], kind: AudioClip.Source) async -> Int {
        var clips: [UUID: AudioClip] = [:]
        var replaced: [String] = []

        for item in items {
            guard let entry = library.entry(id: item.entryID) else { continue }
            let ext = item.url.pathExtension.isEmpty ? "m4a" : item.url.pathExtension
            let name = "\(item.entryID.uuidString)-\(UUID().uuidString.prefix(6)).\(ext)"

            let scoped = item.url.startAccessingSecurityScopedResource()
            defer { if scoped { item.url.stopAccessingSecurityScopedResource() } }

            guard let path = try? await persistence.importMedia(from: item.url, as: name) else { continue }
            clips[item.entryID] = AudioClip(file: path, source: kind)
            if let previous = entry.audio?.file { replaced.append(previous) }
        }

        guard !clips.isEmpty else { return 0 }

        update { library in
            for (id, clip) in clips {
                guard let index = library.entries.firstIndex(where: { $0.id == id }) else { continue }
                library.entries[index].audio = clip
            }
        }
        discard(replaced)
        return clips.count
    }

    // MARK: - Drawings

    /// Puts a drawing on a word, replacing whatever was there.
    ///
    /// The file is named after the word, so redrawing overwrites rather than
    /// leaving a trail of orphans behind, and a library folder can be read by a
    /// person: `Media/<word id>.drawing`.
    @discardableResult
    func attachAssociation(_ data: Data, strokeCount: Int, to entryID: UUID) async -> Bool {
        // A word with a photograph does not also get a drawing: see `Picture`.
        guard let entry = library.entry(id: entryID), entry.picture == nil else { return false }
        guard strokeCount > 0 else {
            removeAssociation(from: entryID)
            return true
        }

        do {
            let path = try await persistence.writeMedia(data, as: "\(entryID.uuidString).drawing")
            update { library in
                guard let index = library.entries.firstIndex(where: { $0.id == entryID }) else { return }
                library.entries[index].association = Association(file: path, strokeCount: strokeCount)
            }
            return true
        } catch {
            saveState = .failed(error.localizedDescription)
            return false
        }
    }

    /// Puts a photograph on a word. The word's drawing, if it had one, goes:
    /// a word has one picture or the other, never both.
    @discardableResult
    func attachPicture(_ data: Data, fileExtension: String, to entryID: UUID) async -> Bool {
        guard let entry = library.entry(id: entryID) else { return false }
        let name = "\(entryID.uuidString)-\(UUID().uuidString.prefix(6)).\(fileExtension)"

        do {
            let path = try await persistence.writeMedia(data, as: name)
            let replaced = [entry.picture?.file, entry.association?.file].compactMap { $0 }
            update { library in
                guard let index = library.entries.firstIndex(where: { $0.id == entryID }) else { return }
                library.entries[index].picture = Picture(file: path)
                library.entries[index].association = nil
            }
            discard(replaced)
            return true
        } catch {
            saveState = .failed(error.localizedDescription)
            return false
        }
    }

    func removePicture(from entryID: UUID) {
        guard let file = library.entry(id: entryID)?.picture?.file else { return }
        update { library in
            guard let index = library.entries.firstIndex(where: { $0.id == entryID }) else { return }
            library.entries[index].picture = nil
        }
        discard([file])
    }

    func removeAssociation(from entryID: UUID) {
        guard let file = library.entry(id: entryID)?.association?.file else { return }
        update { library in
            guard let index = library.entries.firstIndex(where: { $0.id == entryID }) else { return }
            library.entries[index].association = nil
        }
        discard([file])
    }

    /// A drawing's bytes, read where they are wanted.
    ///
    /// Not async, unlike everything else that touches a file: these are a few
    /// kilobytes each, and a view that is about to draw a picture should not
    /// have to render itself twice to get it.
    nonisolated func associationData(for association: Association) -> Data? {
        try? Data(contentsOf: persistence.mediaURL(for: association.file))
    }

    func removeAudio(from entryID: UUID) {
        guard let file = library.entry(id: entryID)?.audio?.file else { return }
        update { library in
            guard let index = library.entries.firstIndex(where: { $0.id == entryID }) else { return }
            library.entries[index].audio = nil
        }
        discard([file])
    }

    // MARK: - Anki

    /// Brings a planned deck in: every word in one change, then every file.
    ///
    /// The words go in first and at once, so the library is never left holding
    /// half a deck. The files follow — hundreds of them, copied out of the
    /// package — and are hung on their words in a second single change, so a
    /// deck of fifteen hundred recordings is two saves rather than fifteen
    /// hundred. `progress` is told how far the files have got.
    @discardableResult
    func importAnki(
        _ words: [AnkiWord],
        from package: AnkiPackage,
        profileID: UUID,
        deckID: UUID?,
        progress: @escaping @MainActor (Double) -> Void = { _ in }
    ) async -> Int {
        await importAnki(
            words,
            from: package,
            profileID: profileID,
            target: deckID.map(AnkiDeckTarget.existing) ?? .none,
            style: .none,
            layout: AnkiDeckLayout(deckNames: [:], fallbackName: package.readableName),
            progress: progress
        ).count
    }

    /// Brings a planned deck in, with the Anki deck's own structure laid out
    /// as decks and subdecks.
    ///
    /// Where the words go is worked out against the library at the moment of
    /// writing, not when the screen was opened, so a deck made meanwhile is
    /// reused rather than made twice. The decks and the words then go in as one
    /// change.
    @discardableResult
    func importAnki(
        _ words: [AnkiWord],
        from package: AnkiPackage,
        profileID: UUID,
        target: AnkiDeckTarget,
        style: AnkiSubdeckStyle,
        layout: AnkiDeckLayout,
        progress: @escaping @MainActor (Double) -> Void = { _ in }
    ) async -> (count: Int, placement: AnkiDeckPlacement) {
        let placement = AnkiDeckPlacement.resolve(
            target: target,
            style: style,
            layout: layout,
            noteIDs: words.map(\.id),
            profileID: profileID,
            library: library
        )

        let pairs = words.map { word in
            (word, Entry(
                profileID: profileID,
                deckID: placement.deckOfNote[word.id],
                term: word.term,
                meaning: word.meaning,
                gender: word.gender,
                example: word.example,
                exampleTranslation: word.exampleTranslation,
                note: word.note
            ))
        }
        guard !pairs.isEmpty else { return (0, placement) }

        update { library in
            for deck in placement.newDecks { library.upsert(deck) }
            for (_, entry) in pairs { library.upsert(entry) }
        }

        var clips: [UUID: (audio: AudioClip?, example: AudioClip?, picture: Picture?)] = [:]
        let total = Double(pairs.count)

        for (offset, (word, entry)) in pairs.enumerated() {
            var found: (audio: AudioClip?, example: AudioClip?, picture: Picture?) = (nil, nil, nil)

            if let name = word.wordAudio, let path = await copy(name, from: package, for: entry.id) {
                found.audio = AudioClip(file: path, source: .imported)
            }
            if let name = word.exampleAudio, let path = await copy(name, from: package, for: entry.id) {
                found.example = AudioClip(file: path, source: .imported)
            }
            if let name = word.picture, let path = await copy(name, from: package, for: entry.id) {
                found.picture = Picture(file: path)
            }
            if found.audio != nil || found.example != nil || found.picture != nil {
                clips[entry.id] = found
            }
            if offset % 25 == 0 { progress(Double(offset) / total) }
        }

        if !clips.isEmpty {
            update { library in
                for index in library.entries.indices {
                    guard let found = clips[library.entries[index].id] else { continue }
                    library.entries[index].audio = found.audio
                    library.entries[index].exampleAudio = found.example
                    library.entries[index].picture = found.picture
                }
            }
        }

        progress(1)
        await saveNow()
        return (pairs.count, placement)
    }

    /// One file out of the package and into the library, named after the word
    /// it belongs to. The extension is taken from what the bytes are rather
    /// than from the name: decks in the wild carry files called `photo.jpg!d`.
    private func copy(_ name: String, from package: AnkiPackage, for entryID: UUID) async -> String? {
        guard let data = package.mediaData(named: name) else { return nil }
        let kind = MediaKind.sniff(data) ?? MediaKind(fileName: name)
        let file = "\(entryID.uuidString)-\(UUID().uuidString.prefix(6)).\(kind.fileExtension)"
        return try? await persistence.writeMedia(data, as: file)
    }

    /// A place to record into before the recording is worth keeping.
    nonisolated func scratchURL(extension ext: String = "m4a") -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "words-recording-\(UUID().uuidString).\(ext)")
    }

    /// Deletes files nothing in the library points at any more.
    ///
    /// Asked of the library as it stands after the change, not taken on trust
    /// from the caller: the app names every file after the one word that owns
    /// it, but a library that has been copied, merged or edited by hand may
    /// have two words sharing one recording, and taking a word away must never
    /// take the other word's sound with it.
    private func discard(_ files: [String]) {
        let stillUsed = Set(library.entries.flatMap(\.mediaFiles))
        let orphans = Array(Set(files).subtracting(stillUsed))
        guard !orphans.isEmpty else { return }
        Task { [persistence] in
            for file in orphans { await persistence.removeMedia(at: file) }
        }
    }

    // MARK: - Studying

    /// Adds to today, and only today, for one language.
    ///
    /// The cards are chosen now, from what `moreAvailable` offers at this
    /// moment, and asking for more than there is gives what there is.
    func studyMore(
        profileID: UUID,
        deckID: UUID? = nil,
        newWords: Int,
        reviews: Int,
        at date: Date = .now
    ) {
        let available = library.moreAvailable(for: profileID, deckID: deckID, asOf: date)
        let words = min(max(0, newWords), available.newWords)
        let cards = Array(available.reviews.prefix(max(0, reviews)))
        guard words > 0 || !cards.isEmpty else { return }
        update { $0.addExtra(profileID: profileID, newWords: words, reviews: cards, asOf: date) }
    }

    // MARK: - The streak

    func freezeStreak(at date: Date = .now) {
        guard library.streak(asOf: date).canFreezeToday else { return }
        update { $0.freezeStreak(asOf: date) }
    }

    func unfreezeStreak(at date: Date = .now) {
        guard library.streak(asOf: date).frozenToday else { return }
        update { $0.unfreezeStreak(asOf: date) }
    }

    /// Writes down where a sitting has got to, so that closing the window is
    /// stopping rather than starting again.
    func keep(_ snapshot: StudySnapshot) {
        update { $0.upsert(snapshot) }
    }

    /// Forgets a sitting, because it is finished or because there is nothing
    /// left in it worth coming back to.
    func forgetSession(profileID: UUID, deckID: UUID?, mode: StudyMode) {
        guard library.sessions.contains(where: { $0.matches(profileID: profileID, deckID: deckID, mode: mode) }) else { return }
        update { $0.removeSnapshot(profileID: profileID, deckID: deckID, mode: mode) }
    }

    /// Records an answer that changes nothing but the record of it.
    func practise(
        _ card: QueuedCard,
        grade: ReviewGrade,
        at date: Date = .now,
        seconds: Double? = nil
    ) {
        update {
            $0.recordPractice(entryID: card.entryID, cardID: card.cardID, grade: grade, at: date, seconds: seconds)
        }
    }

    /// Records an answer and returns where the card landed, which is what the
    /// session needs in order to decide whether it will come round again today.
    @discardableResult
    func answer(
        _ card: QueuedCard,
        grade: ReviewGrade,
        at date: Date = .now,
        seconds: Double? = nil
    ) -> SchedulingState? {
        // The goal belongs to the language the word is in, not to the app.
        let retention = library.entry(id: card.entryID)
            .flatMap { library.profile(id: $0.profileID) }?
            .desiredRetention ?? Retention.standard

        var state: SchedulingState?
        update {
            state = $0.recordReview(
                entryID: card.entryID,
                cardID: card.cardID,
                grade: grade,
                at: date,
                using: scheduler,
                retention: retention,
                seconds: seconds
            )
        }
        return state
    }
}
