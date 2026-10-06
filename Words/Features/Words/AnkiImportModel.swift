import AppKit
import Observation

/// A deck being looked at before it is imported.
///
/// Holds the package, the guess about which field goes where, and the plan that
/// guess produces — recomputed on every change the learner makes, so the card
/// in the preview is always the card the import would write.
@Observable
@MainActor
final class AnkiImportModel {

    /// Everything that takes real work, done away from the window.
    nonisolated struct Prepared: Sendable {
        var package: AnkiPackage
        var type: AnkiPackage.NoteType
        var notes: [ParsedAnkiNote]
        var mapping: AnkiMapping
        var fields: [AnkiFieldProfile]
    }

    nonisolated static func prepare(_ url: URL, profile: LanguageProfile, type chosen: Int64? = nil) async throws -> Prepared {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let package = try AnkiPackage.open(url)
        return prepare(package, profile: profile, type: chosen)
    }

    nonisolated static func prepare(_ package: AnkiPackage, profile: LanguageProfile, type chosen: Int64?) -> Prepared {
        let types = package.usedNoteTypes
        let type = types.first { $0.id == chosen } ?? types[0]
        let notes = package.notes(of: type.id).map(ParsedAnkiNote.init)
        return Prepared(
            package: package,
            type: type,
            notes: notes,
            mapping: AnkiMapping.suggest(for: type, notes: notes, package: package, profile: profile),
            fields: AnkiFieldProfile.measure(type: type, notes: notes)
        )
    }

    let package: AnkiPackage
    let profile: LanguageProfile
    private(set) var type: AnkiPackage.NoteType
    private(set) var notes: [ParsedAnkiNote]
    private(set) var fields: [AnkiFieldProfile]
    private var existing: [Entry]

    var mapping: AnkiMapping { didSet { replan() } }
    var audio: AnkiAudioChoice = .deck { didSet { replan() } }

    /// Where the Anki deck's own decks sit, for the notes of this type.
    private(set) var layout: AnkiDeckLayout

    var target: AnkiDeckTarget = .none
    var subdeckStyle: AnkiSubdeckStyle = .none

    private(set) var plan = AnkiImportPlan()

    /// Only the notes the import would leave behind, for checking why.
    var showsSkippedOnly = false {
        didSet { position = 0 }
    }

    /// Moving to another note hides its meaning again, as a card would. Changing
    /// where a field goes does not: the learner is looking at the answer to see
    /// what the change did to it.
    var position = 0 {
        didSet { if position != oldValue { isRevealed = false } }
    }

    var isRevealed = false

    private let previewFolder: URL
    private var previewFiles: [String: URL] = [:]
    private var previewPictures: [String: NSImage] = [:]

    init(_ prepared: Prepared, profile: LanguageProfile, existing: [Entry]) {
        package = prepared.package
        type = prepared.type
        notes = prepared.notes
        fields = prepared.fields
        mapping = prepared.mapping
        layout = prepared.package.deckLayout(forNotes: prepared.notes.map(\.id))
        self.profile = profile
        self.existing = existing
        previewFolder = FileManager.default.temporaryDirectory.appending(path: "words-anki-preview-\(UUID().uuidString)")
        audio = hasRecordings ? .deck : .ourVoice
        subdeckStyle = layout.hasSubdecks ? .firstLevel : .none
        replan()
    }

    /// Where the words go by default: a deck of the language that already has
    /// the deck's name, or a new one called that.
    func chooseTarget(in library: Library) {
        if let same = library.topLevelDecks(in: profile.id).first(where: {
            $0.displayName.compare(layout.baseName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            target = .existing(same.id)
        } else {
            target = .newDeck(layout.baseName)
        }
    }

    /// The decks the import would make or fill, for the words that would
    /// actually be imported.
    func placement(in library: Library) -> AnkiDeckPlacement {
        AnkiDeckPlacement.resolve(
            target: target,
            style: subdeckStyle,
            layout: layout,
            noteIDs: plan.usable.map(\.id),
            profileID: profile.id,
            library: library
        )
    }

    /// How a style reads in the menu: what it makes, with the first names as
    /// an example, since "first level" means nothing until it is seen.
    func title(for style: AnkiSubdeckStyle) -> String {
        guard style != .none else { return "No Subdecks" }
        let names = layout.subdecks(for: plan.usable.map(\.id), style: style).map(\.name)
        guard !names.isEmpty else { return "No Subdecks" }
        let shown = names.prefix(2).joined(separator: ", ")
        let more = names.count > 2 ? ", …" : ""
        return "\(names.count) \(names.count == 1 ? "Subdeck" : "Subdecks"): \(shown)\(more)"
    }

    deinit {
        try? FileManager.default.removeItem(at: previewFolder)
    }

    /// Another note type from the same package: the guess starts again.
    func switchType(to id: Int64) {
        guard id != type.id else { return }
        let prepared = Self.prepare(package, profile: profile, type: id)
        type = prepared.type
        notes = prepared.notes
        fields = prepared.fields
        layout = package.deckLayout(forNotes: prepared.notes.map(\.id))
        if !layout.styles.contains(subdeckStyle) { subdeckStyle = layout.hasSubdecks ? .firstLevel : .none }
        position = 0
        mapping = prepared.mapping
    }

    func refresh(existing: [Entry]) {
        self.existing = existing
        replan()
    }

    private func replan() {
        plan = AnkiImport.plan(
            notes: notes,
            mapping: mapping,
            fieldNames: type.fields,
            profile: profile,
            audio: audio,
            package: package,
            existing: existing
        )
        position = min(position, max(0, visible.count - 1))
    }

    // MARK: - What the preview walks through

    var visible: [AnkiWord] {
        showsSkippedOnly ? plan.words.filter { !$0.isUsable || $0.isDuplicate } : plan.words
    }

    var skippedCount: Int { plan.incomplete + plan.duplicates }

    var current: AnkiWord? { visible[safe: position] }

    var currentNote: ParsedAnkiNote? {
        guard let current else { return nil }
        return notes.first { $0.id == current.id }
    }

    func step(_ offset: Int) {
        let count = visible.count
        guard count > 0 else { return }
        position = (position + offset + count) % count
    }

    /// Whether the deck brings recordings at all. A deck without any has
    /// nothing to choose between.
    var hasRecordings: Bool {
        !mapping.fields(for: .wordAudio).isEmpty || !mapping.fields(for: .exampleAudio).isEmpty
            || fields.contains { $0.withSound > 0.3 }
    }

    /// The word the preview shows: built from exactly what the import would
    /// write, with its sounds pointing into the package instead of the library.
    func previewEntry(for word: AnkiWord) -> Entry {
        var entry = word.previewEntry(profileID: profile.id)
        entry.id = Self.identifier(for: word.id)
        entry.audio = word.wordAudio.map { AudioClip(file: $0, source: .imported) }
        entry.exampleAudio = word.exampleAudio.map { AudioClip(file: $0, source: .imported) }
        return entry
    }

    func picture(for word: AnkiWord) -> NSImage? {
        guard let name = word.picture else { return nil }
        if let cached = previewPictures[name] { return cached }
        guard let data = package.mediaData(named: name), let image = NSImage(data: data) else { return nil }
        previewPictures[name] = image
        return image
    }

    /// Where a sound from the package can be played from: copied out once into
    /// a folder of its own, which goes when the preview does.
    func previewURL(_ name: String) -> URL? {
        if let url = previewFiles[name] { return url }
        guard let data = package.mediaData(named: name) else { return nil }
        let kind = MediaKind.sniff(data) ?? MediaKind(fileName: name)
        let url = previewFolder.appending(path: "\(previewFiles.count).\(kind.fileExtension)")
        do {
            try FileManager.default.createDirectory(at: previewFolder, withIntermediateDirectories: true)
            try data.write(to: url)
        } catch {
            return nil
        }
        previewFiles[name] = url
        return url
    }

    /// One sound straight from a field, for hearing what a field holds before
    /// deciding where it goes.
    func sound(inField index: Int) -> URL? {
        currentNote?.values[safe: index]?.sounds.first.flatMap(previewURL)
    }

    private static func identifier(for noteID: Int64) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        withUnsafeBytes(of: noteID.bigEndian) { raw in
            for (index, byte) in raw.enumerated() { bytes[8 + index] = byte }
        }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    // MARK: - Describing it

    /// Which slots a field can sensibly be put in, given what is in it. A field
    /// of recordings offered "Meaning" is a menu that invites a mistake.
    func choices(forField index: Int) -> [WordsSlot] {
        guard let field = fields[safe: index] else { return [.skip] }
        var slots: [WordsSlot] = []
        if field.characters > 0 { slots += [.word, .meaning, .example, .exampleTranslation, .note] }
        // Only for a field with an article or a gender in it somewhere: offered
        // for a field of sentences it would only be a way to lose them.
        if field.genders > 0 { slots.insert(.gender, at: min(1, slots.count)) }
        if field.withSound > 0 { slots += [.wordAudio, .exampleAudio] }
        if field.withPicture > 0 { slots.append(.picture) }
        return slots + [.skip]
    }

    /// Why the current note would not be imported, if it would not.
    var currentStatus: String? {
        guard let current else { return nil }
        if current.term.isEmpty { return "Skipped: the word is empty in this note." }
        if current.meaning.isEmpty { return "Skipped: the meaning is empty in this note." }
        if current.isDuplicate { return "Skipped: this word with this meaning is already in the library or earlier in the deck." }
        return nil
    }

    var recordingsDescription: String {
        let word = plan.words.contains { $0.wordAudio != nil }
        let example = plan.words.contains { $0.exampleAudio != nil }
        switch (audio, word, example) {
        case (.ourVoice, _, _):
            return "Words’ voice reads the word and the example. None of the deck’s recordings are imported."
        case (.deck, true, true):
            return "The deck’s recordings are used for the word and the example."
        case (.deck, true, false):
            return "The deck has recordings of the word only. Words’ voice reads the examples."
        case (.deck, false, true):
            return "The deck has recordings of the example only. Words’ voice reads the word."
        case (.deck, false, false):
            return "No recordings are assigned. Words’ voice reads everything."
        }
    }
}
