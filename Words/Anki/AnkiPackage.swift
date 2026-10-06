import Foundation
import SQLite3

/// An Anki package, read and not interpreted.
///
/// This is the raw material and nothing more: the note types with their fields
/// and templates, the notes with their values, the decks, and the media the
/// package carries. What any of it *means* for a word in Words is decided later,
/// by `AnkiMapping`, and confirmed by the learner — an Anki field called "Back"
/// is a name somebody typed, not a promise about what is in it.
nonisolated struct AnkiPackage: Sendable {

    nonisolated struct NoteType: Identifiable, Hashable, Sendable {
        var id: Int64
        var name: String
        var fields: [String]
        var templates: [Template]
        /// The field Anki sorts by, which its author usually meant as "the word".
        var sortField: Int
        var isCloze: Bool
    }

    nonisolated struct Template: Hashable, Sendable {
        var name: String
        var front: String
        var back: String
    }

    nonisolated struct Note: Identifiable, Hashable, Sendable {
        var id: Int64
        var guid: String
        var noteTypeID: Int64
        var fields: [String]
        var tags: [String]

        func value(at index: Int) -> String {
            index < fields.count ? fields[index] : ""
        }
    }

    nonisolated enum Failure: LocalizedError {
        case newerFormat
        case olderFormat
        case empty
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .newerFormat:
                "This deck was exported by a recent version of Anki in a compressed format Words cannot read yet."
            case .olderFormat:
                "This package was made by a version of Anki Words does not know."
            case .empty:
                "The package has no notes in it."
            case .unreadable(let detail):
                "The package could not be read. \(detail)"
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .newerFormat:
                "In Anki, export the deck again with “Support older Anki versions” ticked, and import that file."
            default:
                nil
            }
        }
    }

    /// What the file was called, which is usually the most honest name the
    /// deck has.
    let fileName: String

    let noteTypes: [NoteType]
    let notes: [Note]

    /// Every deck the package defines, by id. Anki nests them with `::`.
    let decks: [Int64: String]

    /// The deck each note's first card sits in.
    let deckOfNote: [Int64: Int64]

    /// How many cards each note type makes per note — two for a type with a
    /// forward and a reverse template, and also two for a type with two
    /// variants of one exercise, which is why this is information and not a
    /// plan.
    let cardsPerNote: [Int64: Int]

    /// Original file name → the entry inside the archive that holds it.
    let media: [String: String]

    private let archive: ZipArchive

    // MARK: - Opening

    static func open(_ url: URL) throws -> AnkiPackage {
        let archive: ZipArchive
        do {
            archive = try ZipArchive(url: url)
        } catch {
            throw Failure.unreadable(error.localizedDescription)
        }
        return try AnkiPackage(archive: archive, fileName: url.deletingPathExtension().lastPathComponent)
    }

    init(archive: ZipArchive, fileName: String) throws {
        self.archive = archive
        self.fileName = fileName

        // The newest format compresses the database and the media with zstd,
        // which macOS does not ship a decoder for. A package made to be read by
        // older versions carries a readable copy as well; one that does not
        // cannot be opened, and saying why is better than failing strangely.
        if Self.metaVersion(archive) >= 3 { throw Failure.newerFormat }

        let databaseName: String
        if archive.contains("collection.anki21") {
            // Preferred over `collection.anki2` when both are present: in that
            // case the older file is a stub holding a single note that says
            // "please update Anki", and importing it would import that note.
            databaseName = "collection.anki21"
        } else if archive.contains("collection.anki2") {
            databaseName = "collection.anki2"
        } else if archive.contains("collection.anki21b") {
            throw Failure.newerFormat
        } else {
            throw Failure.unreadable("There is no collection inside it.")
        }

        let database = try Database(data: archive.read(databaseName))
        guard try database.scalarInt("select ver from col") == 11 else { throw Failure.olderFormat }

        noteTypes = try Self.readNoteTypes(database)
        decks = try Self.readDecks(database)

        notes = try database.rows("select id, guid, mid, tags, flds from notes order by id") { row in
            Note(
                id: row.int64(0),
                guid: row.string(1),
                noteTypeID: row.int64(2),
                fields: row.string(4).split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init),
                tags: row.string(3).split(separator: " ").map(String.init)
            )
        }
        guard !notes.isEmpty else { throw Failure.empty }

        var deckOfNote: [Int64: Int64] = [:]
        var cardsPerNoteByType: [Int64: Set<Int64>] = [:]
        try database.each("select c.nid, c.did, c.ord, n.mid from cards c join notes n on n.id = c.nid order by c.nid, c.ord") { row in
            let note = row.int64(0)
            if deckOfNote[note] == nil { deckOfNote[note] = row.int64(1) }
            cardsPerNoteByType[row.int64(3), default: []].insert(row.int64(2))
        }
        self.deckOfNote = deckOfNote
        cardsPerNote = cardsPerNoteByType.mapValues(\.count)

        media = Self.readMedia(archive)
    }

    // MARK: - Reading

    /// Note types that actually have notes. Packages routinely carry an unused
    /// "Basic" along with the type the deck is really made of.
    var usedNoteTypes: [NoteType] {
        let counts = Dictionary(grouping: notes, by: \.noteTypeID).mapValues(\.count)
        return noteTypes
            .filter { (counts[$0.id] ?? 0) > 0 }
            .sorted { (counts[$0.id] ?? 0) > (counts[$1.id] ?? 0) }
    }

    func notes(of type: NoteType.ID) -> [Note] {
        notes.filter { $0.noteTypeID == type }
    }

    /// The deck the package is mostly about, without its subdecks — the name a
    /// learner would recognise it by.
    var mainDeckName: String {
        let counts = Dictionary(grouping: deckOfNote.values, by: { $0 }).mapValues(\.count)
        let names = counts
            .sorted { $0.value > $1.value }
            .compactMap { decks[$0.key] }
            .map { $0.components(separatedBy: "::").first ?? $0 }
            .filter { $0 != "Default" }
        return names.first ?? fileName.replacingOccurrences(of: "_", with: " ")
    }

    /// The Anki deck a note sits in, in Anki's own `A::B::C` form.
    func deckName(ofNote id: Int64) -> String? {
        deckOfNote[id].flatMap { decks[$0] }
    }

    /// The package's file name made readable: underscores gone, spaces
    /// single. What a deck is called when its notes share no deck of their own.
    var readableName: String {
        fileName
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
    }

    /// Where every note of one note type sits in the package's decks.
    func deckLayout(forNotes ids: [Int64]) -> AnkiDeckLayout {
        var names: [Int64: String] = [:]
        for id in ids { names[id] = deckName(ofNote: id) ?? "" }
        return AnkiDeckLayout(deckNames: names, fallbackName: readableName)
    }

    /// The bytes of a file a note refers to, by the name the note uses.
    func mediaData(named name: String) -> Data? {
        guard let entry = media[name] else { return nil }
        return try? archive.read(entry)
    }

    func hasMedia(named name: String) -> Bool {
        media[name] != nil
    }

    /// How big a file is, without reading it. A sound that keeps pace with a
    /// sentence grows with it, and that is enough to tell whose voice it is.
    func mediaSize(named name: String) -> Int? {
        media[name].flatMap { archive.entries[$0]?.size }
    }

    // MARK: - The pieces

    private static func metaVersion(_ archive: ZipArchive) -> Int {
        // A protobuf with a single varint in field 1. Two bytes are enough for
        // the versions that exist; anything unreadable counts as old.
        guard archive.contains("meta"), let bytes = try? archive.read("meta"), bytes.count >= 2,
              bytes[bytes.startIndex] == 0x08
        else { return 0 }
        return Int(bytes[bytes.startIndex + 1])
    }

    private static func readNoteTypes(_ database: Database) throws -> [NoteType] {
        guard let json = try database.scalarString("select models from col"),
              let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: [String: Any]]
        else { throw Failure.unreadable("Its note types are missing.") }

        return object.values.compactMap { model in
            guard let idValue = model["id"], let name = model["name"] as? String else { return nil }
            let id = (idValue as? NSNumber)?.int64Value ?? Int64("\(idValue)") ?? 0

            let fields = (model["flds"] as? [[String: Any]] ?? [])
                .sorted { ($0["ord"] as? Int ?? 0) < ($1["ord"] as? Int ?? 0) }
                .compactMap { $0["name"] as? String }

            let templates = (model["tmpls"] as? [[String: Any]] ?? [])
                .sorted { ($0["ord"] as? Int ?? 0) < ($1["ord"] as? Int ?? 0) }
                .map { Template(name: $0["name"] as? String ?? "", front: $0["qfmt"] as? String ?? "", back: $0["afmt"] as? String ?? "") }

            return NoteType(
                id: id,
                name: name,
                fields: fields,
                templates: templates,
                sortField: model["sortf"] as? Int ?? 0,
                isCloze: (model["type"] as? Int) == 1
            )
        }
    }

    private static func readDecks(_ database: Database) throws -> [Int64: String] {
        guard let json = try database.scalarString("select decks from col"),
              let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: [String: Any]]
        else { return [:] }

        var decks: [Int64: String] = [:]
        for (key, deck) in object {
            guard let name = deck["name"] as? String, let id = Int64(key) else { continue }
            decks[id] = name
        }
        return decks
    }

    private static func readMedia(_ archive: ZipArchive) -> [String: String] {
        guard archive.contains("media"),
              let data = try? archive.read("media"),
              let map = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return [:] }

        // The file inside the archive is the key; the name the notes use is the
        // value. Turned round, because notes are what ask.
        var byName: [String: String] = [:]
        for (entry, name) in map where archive.contains(entry) {
            byName[name] = entry
        }
        return byName
    }
}

// MARK: - SQLite

/// A read-only look at an SQLite file held in memory.
///
/// SQLite opens files, not bytes, so the database is written to a temporary
/// file first and removed again when this goes away.
private nonisolated final class Database {
    private var handle: OpaquePointer?
    private let url: URL

    init(data: Data) throws {
        url = FileManager.default.temporaryDirectory.appending(path: "words-anki-\(UUID().uuidString).sqlite")
        try data.write(to: url)
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw AnkiPackage.Failure.unreadable("Its database would not open.")
        }
    }

    deinit {
        sqlite3_close(handle)
        try? FileManager.default.removeItem(at: url)
    }

    struct Row {
        let statement: OpaquePointer

        func int64(_ column: Int32) -> Int64 { sqlite3_column_int64(statement, column) }

        func string(_ column: Int32) -> String {
            guard let text = sqlite3_column_text(statement, column) else { return "" }
            return String(cString: text)
        }
    }

    func each(_ sql: String, _ body: (Row) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw AnkiPackage.Failure.unreadable(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            try body(Row(statement: statement))
        }
    }

    func rows<T>(_ sql: String, _ make: (Row) throws -> T) throws -> [T] {
        var result: [T] = []
        try each(sql) { result.append(try make($0)) }
        return result
    }

    func scalarInt(_ sql: String) throws -> Int64? {
        try rows(sql) { $0.int64(0) }.first
    }

    func scalarString(_ sql: String) throws -> String? {
        try rows(sql) { $0.string(0) }.first
    }
}
