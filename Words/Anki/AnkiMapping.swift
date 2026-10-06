import Foundation

/// The places a piece of an Anki note can go in a Words word.
nonisolated enum WordsSlot: String, CaseIterable, Identifiable, Hashable, Sendable {
    case word
    /// The article, or a gender however it is written — "die", "f".
    case gender
    case meaning
    case example
    case exampleTranslation
    case note
    case wordAudio
    case exampleAudio
    case picture
    case skip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .word: "Word"
        case .gender: "Article"
        case .meaning: "Meaning"
        case .example: "Example"
        case .exampleTranslation: "Example Translation"
        case .note: "Note"
        case .wordAudio: "Word Audio"
        case .exampleAudio: "Example Audio"
        case .picture: "Picture"
        case .skip: "Don’t Import"
        }
    }

    var isAudio: Bool { self == .wordAudio || self == .exampleAudio }

    /// Text that several Anki fields may be poured into at once. A deck that
    /// keeps synonyms and antonyms in fields of their own still has only one
    /// note to put them in.
    var gathersSeveral: Bool { self == .meaning || self == .note }
}

/// What one Anki field turns out to hold across every note of its type.
///
/// The name of a field is what somebody typed; this is what is actually in it,
/// and it is the better evidence of the two.
nonisolated struct AnkiFieldProfile: Hashable, Sendable {
    var index: Int
    var name: String

    /// Share of notes with anything in the field once placeholders are ignored.
    var filled: Double
    var withSound: Double
    var withPicture: Double

    /// Average length of the text in the notes where there is some.
    var characters: Double
    var words: Double

    /// Share of the notes with text in the field whose text is an article or a
    /// gender and nothing else — "der", "die", "das", "m", "f".
    var genders: Double

    /// The same value in every note — an author's name, a source, a licence.
    var isConstant: Bool

    /// Nothing but digits — an identifier someone kept for their own
    /// bookkeeping.
    var isNumber: Bool

    var isOnFront: Bool
    var isOnBack: Bool
}

/// Which Anki field goes where, for one note type.
///
/// One mapping serves every note of the type, because a note type is exactly
/// the thing that gives its notes one shape: if the first note comes out right,
/// the nine hundred after it do too. What it cannot promise is that every note
/// is *filled in* the same way, which is why the preview can walk to the notes
/// that came out with something missing.
nonisolated struct AnkiMapping: Hashable, Sendable {

    /// One slot per field, in the note type's field order.
    var slots: [WordsSlot]

    func fields(for slot: WordsSlot) -> [Int] {
        slots.indices.filter { slots[$0] == slot }
    }

    /// What stops an import from being a sensible one, said the way the learner
    /// would fix it.
    var problem: String? {
        switch fields(for: .word).count {
        case 0: return "Choose which field holds the word."
        case 1: break
        default: return "Only one field can be the word."
        }
        if fields(for: .meaning).isEmpty { return "Choose which field holds the meaning." }
        for slot in [WordsSlot.gender, .example, .exampleTranslation, .wordAudio, .exampleAudio, .picture]
        where fields(for: slot).count > 1 {
            return "Only one field can be the \(slot.title.lowercased())."
        }
        return nil
    }

    /// Changes one field's slot. A slot that only one field may fill is taken
    /// from whichever field had it, so choosing "Word" for the right field is
    /// one click rather than two.
    mutating func assign(_ slot: WordsSlot, toField index: Int) {
        guard slots.indices.contains(index) else { return }
        if slot != .skip, !slot.gathersSeveral {
            for other in fields(for: slot) where other != index { slots[other] = .skip }
        }
        slots[index] = slot
    }

    // MARK: - Guessing

    /// A first guess, made from the names of the fields, where they sit on the
    /// card, and what is actually in them. It is a guess and is shown as one:
    /// the learner is the judge, and one deck in ten will need a correction.
    static func suggest(
        for type: AnkiPackage.NoteType,
        notes: [ParsedAnkiNote],
        package: AnkiPackage,
        profile: LanguageProfile
    ) -> AnkiMapping {
        let profiles = AnkiFieldProfile.measure(type: type, notes: notes)
        var slots = Array(repeating: WordsSlot.skip, count: type.fields.count)
        var free = Set(profiles.filter { $0.filled > 0 && !$0.isConstant && !$0.isNumber }.map(\.index))

        // Pictures and sounds are recognised by what they are, not by name.
        if let picture = profiles.filter({ free.contains($0.index) && $0.withPicture >= 0.5 }).max(by: { $0.withPicture < $1.withPicture }) {
            slots[picture.index] = .picture
        }
        let sounding = profiles.filter { free.contains($0.index) && $0.withSound >= 0.5 }
        for field in profiles where field.withSound >= 0.5 || field.withPicture >= 0.5 { free.remove(field.index) }

        // An article kept in a field of its own is recognised by what is in
        // it: nothing but "der", "die" and "das", in the notes that are nouns.
        // It is empty in every other note, so how full it is says nothing.
        if let gender = profiles
            .filter({ free.contains($0.index) && $0.genders >= 0.9 && $0.characters <= 6 })
            .max(by: { $0.genders < $1.genders }) {
            slots[gender.index] = .gender
            free.remove(gender.index)
        }

        let text = profiles.filter { free.contains($0.index) }
        func score(_ field: AnkiFieldProfile, for slot: WordsSlot) -> Double {
            Self.score(field, for: slot, type: type, profile: profile)
        }
        func take(_ slot: WordsSlot, where allowed: (AnkiFieldProfile) -> Bool = { _ in true }) -> AnkiFieldProfile? {
            var best: AnkiFieldProfile?
            var bestScore = 0.0
            for field in text where free.contains(field.index) && allowed(field) {
                let value = score(field, for: slot)
                // Ties go to the earlier field: authors put the main thing first.
                if value > bestScore { best = field; bestScore = value }
            }
            if let best {
                slots[best.index] = slot
                free.remove(best.index)
            }
            return best
        }

        let word = take(.word) ?? {
            // Nothing looked like a word by name: the field Anki sorts by, or the
            // first thing on the front of the card.
            let fallback = text.first { $0.index == type.sortField } ?? text.first { $0.isOnFront } ?? text.first
            if let fallback { slots[fallback.index] = .word; free.remove(fallback.index) }
            return fallback
        }()

        if take(.meaning) == nil, let next = text.first(where: { free.contains($0.index) && $0.words <= 8 }) {
            slots[next.index] = .meaning
            free.remove(next.index)
        }

        let example = take(.example) { $0.words >= 3 }
        if example != nil { _ = take(.exampleTranslation) { $0.words >= 3 } }

        for field in text where free.contains(field.index) && score(field, for: .note) > 0 {
            slots[field.index] = .note
            free.remove(field.index)
        }

        // A single sound belongs to whichever text it keeps pace with. A word
        // takes half a second to say whatever it is; a sentence takes longer the
        // longer it is — which is how a deck whose "audio" reads the example is
        // told apart from one that reads the word.
        if sounding.count == 1, let sound = sounding.first {
            if let word, let example {
                let followsWord = Self.correlation(sound: sound.index, text: word.index, notes: notes, package: package)
                let followsExample = Self.correlation(sound: sound.index, text: example.index, notes: notes, package: package)
                slots[sound.index] = followsExample > followsWord ? .exampleAudio : .wordAudio
            } else {
                slots[sound.index] = .wordAudio
            }
        } else if sounding.count > 1 {
            assignSounds(sounding, word: word, example: example, slots: &slots, notes: notes, package: package)
        }

        return AnkiMapping(slots: slots)
    }

    /// Several recordings: which reads the word and which the example.
    ///
    /// A name says it first — "Audio_Wort" is the word however big its files
    /// are, and one deck's word recordings from a dictionary can easily
    /// outweigh its sentences from a speech engine. Then what the recording
    /// keeps pace with: the one that grows with the example sentence reads it.
    /// Only when neither says anything is the smaller recording taken for the
    /// word.
    private static func assignSounds(
        _ sounding: [AnkiFieldProfile],
        word: AnkiFieldProfile?,
        example: AnkiFieldProfile?,
        slots: inout [WordsSlot],
        notes: [ParsedAnkiNote],
        package: AnkiPackage
    ) {
        func tokens(_ field: AnkiFieldProfile) -> Set<String> {
            Set(field.name.lowercased().split { !$0.isLetter }.map(String.init))
        }
        let sentenceNames: Set<String> = ["example", "examples", "sentence", "sentences", "satz", "phrase", "beispiel"]
        var left = sounding

        var wordSound = left.first { !tokens($0).isDisjoint(with: hints[.word] ?? []) && tokens($0).isDisjoint(with: sentenceNames) }
        left.removeAll { $0.index == wordSound?.index }

        var exampleSound = left.first { !tokens($0).isDisjoint(with: sentenceNames) }
        if exampleSound == nil, let example {
            let paced = left
                .map { ($0, correlation(sound: $0.index, text: example.index, notes: notes, package: package)) }
                .max { $0.1 < $1.1 }
            if let paced, paced.1 >= 0.3 { exampleSound = paced.0 }
        }
        left.removeAll { $0.index == exampleSound?.index }

        let bySize = left.sorted {
            medianSize(of: $0.index, notes: notes, package: package) < medianSize(of: $1.index, notes: notes, package: package)
        }
        if wordSound == nil { wordSound = bySize.first }
        if exampleSound == nil { exampleSound = bySize.first { $0.index != wordSound?.index } }

        if let wordSound { slots[wordSound.index] = .wordAudio }
        if let exampleSound { slots[exampleSound.index] = .exampleAudio }
    }

    // MARK: - Evidence

    private static let hints: [WordsSlot: Set<String>] = [
        .word: ["word", "front", "term", "vocab", "vocabulary", "expression", "headword", "lemma", "target", "question", "wort"],
        .meaning: ["meaning", "meanings", "translation", "translations", "definition", "definitions", "back", "gloss", "answer", "native", "bedeutung", "übersetzung"],
        .example: ["example", "examples", "sentence", "sentences", "satz", "phrase", "usage", "context", "beispiel"],
        .exampleTranslation: ["example", "sentence", "translation"],
        .note: ["note", "notes", "hint", "hints", "explanation", "comment", "comments", "extra", "info", "synonym", "synonyms", "antonym", "antonyms", "grammar", "plural", "remark",
                "forms", "conjugation", "hinweis", "anmerkung", "notiz", "verbformen", "formen", "konjugation", "grammatik"],
    ]

    private static func score(_ field: AnkiFieldProfile, for slot: WordsSlot, type: AnkiPackage.NoteType, profile: LanguageProfile) -> Double {
        let tokens = Set(field.name.lowercased().split { !$0.isLetter }.map(String.init))
        let learning = tokens.contains(profile.learningCode) || tokens.contains(LanguageCatalog.name(for: profile.learningCode).lowercased())
        let native = tokens.contains(profile.nativeCode) || tokens.contains(LanguageCatalog.name(for: profile.nativeCode).lowercased())
            || tokens.contains("en") && profile.learningCode != "en"
        let named = Double(tokens.intersection(hints[slot] ?? []).count)
        let sentence = !tokens.isDisjoint(with: ["example", "sentence", "satz", "phrase", "examples", "sentences"])

        // The word and its meaning are in every note of a vocabulary deck. A
        // field that is empty in half of them is a hint, not the thing itself.
        if (slot == .word || slot == .meaning) && field.filled < 0.8 { return 0 }

        switch slot {
        case .word:
            var value = named * 2
            if sentence { value -= 3 }
            if learning { value += 2 }
            if native { value -= 2 }
            if field.index == type.sortField { value += 1 }
            if field.isOnFront { value += 0.5 }
            if field.words > 4 { value -= 2 }
            return value
        case .meaning:
            var value = named * 2
            if sentence { value -= 2 }
            if native { value += 2 + (tokens.contains("word") ? 1 : 0) }
            if learning { value -= 2 }
            if field.isOnBack && !field.isOnFront { value += 0.5 }
            return value
        case .example:
            var value: Double = sentence ? 3 : 0
            if learning { value += 2 }
            if native || tokens.contains("translation") { value -= 3 }
            if tokens.contains("synonym") || tokens.contains("antonym") || tokens.contains("synonyms") || tokens.contains("antonyms") { value -= 2 }
            return value
        case .exampleTranslation:
            var value: Double = sentence ? 2 : 0
            if native || tokens.contains("translation") { value += 2 }
            if learning { value -= 3 }
            return value > 2 ? value : 0
        case .note:
            return named
        default:
            return 0
        }
    }

    private static func correlation(sound: Int, text: Int, notes: [ParsedAnkiNote], package: AnkiPackage) -> Double {
        var pairs: [(Double, Double)] = []
        for note in notes {
            guard let name = note.values[safe: sound]?.sounds.first,
                  let size = package.mediaSize(named: name),
                  let length = note.values[safe: text]?.text.count, length > 0
            else { continue }
            pairs.append((Double(length), Double(size)))
            if pairs.count == 120 { break }
        }
        guard pairs.count >= 5 else { return 0 }

        let meanX = pairs.map(\.0).reduce(0, +) / Double(pairs.count)
        let meanY = pairs.map(\.1).reduce(0, +) / Double(pairs.count)
        let covariance = pairs.map { ($0.0 - meanX) * ($0.1 - meanY) }.reduce(0, +)
        let spreadX = pairs.map { pow($0.0 - meanX, 2) }.reduce(0, +)
        let spreadY = pairs.map { pow($0.1 - meanY, 2) }.reduce(0, +)
        guard spreadX > 0, spreadY > 0 else { return 0 }
        return covariance / (spreadX * spreadY).squareRoot()
    }

    private static func medianSize(of field: Int, notes: [ParsedAnkiNote], package: AnkiPackage) -> Int {
        let sizes = notes.prefix(200).compactMap { note in
            note.values[safe: field]?.sounds.first.flatMap { package.mediaSize(named: $0) }
        }.sorted()
        return sizes.isEmpty ? 0 : sizes[sizes.count / 2]
    }
}

/// A note with every field already cleaned, so that changing a mapping is a
/// matter of rearranging and not of reading nine hundred notes again.
nonisolated struct ParsedAnkiNote: Identifiable, Hashable, Sendable {
    var id: Int64
    var values: [AnkiValue]

    init(_ note: AnkiPackage.Note) {
        id = note.id
        values = note.fields.map(AnkiText.parse)
    }
}

extension AnkiFieldProfile {

    nonisolated static func measure(type: AnkiPackage.NoteType, notes: [ParsedAnkiNote]) -> [AnkiFieldProfile] {
        let front = type.templates.first?.front ?? ""
        let back = type.templates.first?.back ?? ""
        let count = Double(max(1, notes.count))

        return type.fields.enumerated().map { index, name in
            var filled = 0, sound = 0, picture = 0
            var characters = 0, words = 0, texts = 0, genders = 0
            var distinct = Set<String>()
            var numeric = true

            for note in notes {
                guard let value = note.values[safe: index] else { continue }
                let text = AnkiText.isPlaceholder(value.text) ? "" : value.text
                if !text.isEmpty || !value.sounds.isEmpty || !value.images.isEmpty { filled += 1 }
                if !value.sounds.isEmpty { sound += 1 }
                if !value.images.isEmpty { picture += 1 }
                if !text.isEmpty {
                    texts += 1
                    characters += text.count
                    words += text.split(whereSeparator: \.isWhitespace).count
                    if Gender.parse(text) != nil { genders += 1 }
                    if distinct.count < 3 { distinct.insert(text) }
                    if numeric, !text.allSatisfy(\.isNumber) { numeric = false }
                }
            }

            let mentioned = { (template: String) in
                template.contains("{{\(name)}}") || template.contains(":\(name)}}") || template.contains("{{#\(name)}}")
            }

            return AnkiFieldProfile(
                index: index,
                name: name,
                filled: Double(filled) / count,
                withSound: Double(sound) / count,
                withPicture: Double(picture) / count,
                characters: texts == 0 ? 0 : Double(characters) / Double(texts),
                words: texts == 0 ? 0 : Double(words) / Double(texts),
                genders: texts == 0 ? 0 : Double(genders) / Double(texts),
                isConstant: texts >= 3 && distinct.count == 1 && sound == 0 && picture == 0,
                isNumber: texts > 0 && numeric,
                isOnFront: mentioned(front),
                isOnBack: mentioned(back) && !mentioned(front)
            )
        }
    }
}

extension Array {
    nonisolated subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
