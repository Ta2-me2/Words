import Foundation

/// Where the sound of an imported deck comes from.
///
/// All or nothing, on purpose. A deck's recordings are one voice — often a
/// robotic one — and Words' own voice is another; a card that reads the word in
/// one and the example in the other sounds like two apps.
nonisolated enum AnkiAudioChoice: String, CaseIterable, Identifiable, Hashable, Sendable {
    /// The recordings the deck came with, where it has them.
    case deck
    /// None of the deck's recordings: Words reads the word and the example.
    case ourVoice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deck: "Deck’s Recordings"
        case .ourVoice: "Words’ Voice"
        }
    }
}

/// One Anki note turned into what would become a Words word.
nonisolated struct AnkiWord: Identifiable, Hashable, Sendable {
    var id: Int64
    var term: String
    var meaning: String
    var gender: Gender?
    var example: String
    var exampleTranslation: String
    var note: String

    /// File names inside the package.
    var wordAudio: String?
    var exampleAudio: String?
    var picture: String?

    var isDuplicate = false

    var isUsable: Bool { !term.isEmpty && !meaning.isEmpty }

    /// Stand-in for the word the preview shows, built from exactly what would
    /// be written — with its media left pointing into the package.
    func previewEntry(profileID: UUID) -> Entry {
        Entry(
            profileID: profileID,
            term: term,
            meaning: meaning,
            gender: gender,
            example: example,
            exampleTranslation: exampleTranslation,
            note: note
        )
    }
}

/// What importing a deck would do, worked out in full before anything is done.
nonisolated struct AnkiImportPlan: Hashable, Sendable {
    var words: [AnkiWord] = []

    var usable: [AnkiWord] { words.filter { $0.isUsable && !$0.isDuplicate } }
    var duplicates: Int { words.count { $0.isUsable && $0.isDuplicate } }
    var incomplete: Int { words.count { !$0.isUsable } }

    var recordings: Int { usable.count { $0.wordAudio != nil } + usable.count { $0.exampleAudio != nil } }
    var pictures: Int { usable.count { $0.picture != nil } }

    /// Notes worth looking at before importing: ones that came out with a hole
    /// in them.
    var needingAttention: [AnkiWord] {
        words.filter { !$0.isUsable || $0.example.isEmpty && $0.exampleAudio != nil }
    }
}

nonisolated enum AnkiImport {

    /// Pours one note through a mapping.
    static func word(
        from note: ParsedAnkiNote,
        mapping: AnkiMapping,
        fieldNames: [String],
        profile: LanguageProfile,
        audio: AnkiAudioChoice,
        package: AnkiPackage
    ) -> AnkiWord {
        func text(_ slot: WordsSlot) -> String {
            let indices = mapping.fields(for: slot)
            let parts: [(String, String)] = indices.compactMap { index in
                guard let value = note.values[safe: index] else { return nil }
                let text = value.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty, !AnkiText.isPlaceholder(text) else { return nil }
                return (fieldNames[safe: index] ?? "", text)
            }
            // Several fields in one place are labelled with their own names, or
            // "nearly, about" and "completely, fully" would sit in one note with
            // nothing to say which is the synonym. A note is labelled even when
            // it is one field — "-e" on its own says nothing, "Plural: -e" does —
            // unless the field is only called a note.
            let labels = parts.count > 1 || slot == .note && !Self.plainNoteNames.contains(parts.first?.0.lowercased() ?? "")
            guard labels else { return parts.first?.1 ?? "" }
            return parts.map { $0.0.isEmpty ? $0.1 : "\($0.0): \($0.1)" }.joined(separator: "\n")
        }

        func media(_ slot: WordsSlot, kind: KeyPath<AnkiValue, [String]>) -> String? {
            mapping.fields(for: slot)
                .compactMap { note.values[safe: $0]?[keyPath: kind].first }
                .first { package.hasMedia(named: $0) }
        }

        var term = text(.word)
        var gender: Gender?
        var remarks = text(.note)

        if LanguageGenders.marksGender(profile.learningCode) {
            let form = LanguageGenders.dictionaryForm(term, language: profile.learningCode)
            term = form.term
            gender = form.gender
            if let plural = form.plural {
                remarks = ["Plural: \(plural)", remarks].filter { !$0.isEmpty }.joined(separator: "\n")
            }
        }

        // An article in a field of its own says the gender outright, and says
        // it louder than an article typed in front of the word.
        if let stated = mapping.fields(for: .gender)
            .lazy
            .compactMap({ note.values[safe: $0].flatMap { Gender.parse($0.text) } })
            .first {
            gender = stated
        }

        return AnkiWord(
            id: 0,
            term: term,
            meaning: text(.meaning),
            gender: gender,
            example: text(.example),
            exampleTranslation: text(.exampleTranslation),
            note: remarks,
            wordAudio: audio == .deck ? media(.wordAudio, kind: \.sounds) : nil,
            exampleAudio: audio == .deck ? media(.exampleAudio, kind: \.sounds) : nil,
            picture: media(.picture, kind: \.images)
        )
    }

    /// Field names that say no more than that the field is a note.
    private static let plainNoteNames: Set<String> = ["note", "notes", "extra", "remark", "remarks", "comment", "comments", "info", "notiz", "anmerkung", "hinweis"]

    static func plan(
        notes: [ParsedAnkiNote],
        mapping: AnkiMapping,
        fieldNames: [String],
        profile: LanguageProfile,
        audio: AnkiAudioChoice,
        package: AnkiPackage,
        existing: [Entry]
    ) -> AnkiImportPlan {
        // A word is the same word only if it means the same thing: a deck with
        // "der Anschluss" twice has two words, a connection and a train to
        // catch, and throwing the second away would lose one of them.
        var seen = Set(existing.filter { $0.profileID == profile.id }.map { key($0.term, $0.meaning) })

        var words: [AnkiWord] = []
        words.reserveCapacity(notes.count)
        for note in notes {
            var word = word(from: note, mapping: mapping, fieldNames: fieldNames, profile: profile, audio: audio, package: package)
            word.id = note.id
            if word.isUsable {
                let identity = key(word.term, word.meaning)
                word.isDuplicate = !seen.insert(identity).inserted
            }
            words.append(word)
        }
        return AnkiImportPlan(words: words)
    }

    static func key(_ term: String, _ meaning: String) -> String {
        "\(term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())\u{1F}\(meaning.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }
}
