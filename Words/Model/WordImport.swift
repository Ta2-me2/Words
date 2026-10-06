import Foundation

/// One line of an import, read.
nonisolated struct ImportedWord: Identifiable, Hashable, Sendable {
    var id = UUID()
    var line: Int
    var term: String
    var meaning: String
    var gender: Gender?
    /// How it is said, as the list wrote it, without the brackets it was
    /// recognised by.
    var transcription: String = ""
    var example: String = ""
    var exampleTranslation: String = ""
    var note: String = ""

    /// Why this word will not be added, if it will not be.
    var duplicate: Duplicate?

    nonisolated enum Duplicate: String, Hashable, Sendable {
        /// The language already has this word.
        case inLibrary
        /// The same word appears earlier in the same paste.
        case inFile
    }

    var isImportable: Bool { duplicate == nil }
}

/// A line that could not be read.
nonisolated struct ImportProblem: Identifiable, Hashable, Sendable {
    var id = UUID()
    var line: Int
    var text: String
    var reason: Reason

    nonisolated enum Reason: String, Hashable, Sendable {
        case noMeaning

        var message: String {
            switch self {
            case .noMeaning: "No meaning"
            }
        }
    }
}

/// What an import would do, worked out before anything is added.
nonisolated struct ImportPlan: Hashable, Sendable {
    var words: [ImportedWord] = []
    var problems: [ImportProblem] = []

    var importable: [ImportedWord] { words.filter(\.isImportable) }
    var duplicates: [ImportedWord] { words.filter { !$0.isImportable } }
    var isEmpty: Bool { words.isEmpty && problems.isEmpty }
}

/// Reading a list of words that somebody else wrote.
///
/// The format is `word;meaning;gender;[transcription];example;translation;note`,
/// and everything after the meaning is optional. Neither the gender nor the
/// transcription is positioned: the gender is recognised by being `f`, `m` or
/// `n`, and the transcription by the brackets around it — `[ˈvasɐ]`, `/ˈvasɐ/`.
/// That is what lets a list carry examples without carrying either, and what
/// keeps every list written before these fields existed reading exactly as it
/// did.
///
/// A parser for pasted text has to be forgiving about everything that is not
/// the format itself — blank lines, Markdown bullets and headings, a stray
/// dash instead of a semicolon — because the text was written by a person, for
/// a person, and only afterwards given to a program.
nonisolated enum WordImport {

    /// Reads text, and marks the words a language already has.
    static func plan(
        text: String,
        language: String,
        existing: [Entry] = []
    ) -> ImportPlan {
        var plan = ImportPlan()
        var seen = Set(existing.map { key($0.term) })
        var seenInFile: Set<String> = []

        for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let number = index + 1
            guard let line = cleaned(rawLine) else { continue }

            let fields = split(line)
            guard let first = fields.first, !first.isEmpty else { continue }

            guard fields.count > 1, !fields[1].isEmpty else {
                plan.problems.append(ImportProblem(line: number, text: line, reason: .noMeaning))
                continue
            }

            // An article typed in front of the word says the gender without
            // anybody having to write it in a column.
            let (term, impliedGender) = LanguageGenders.split(term: first, language: language)
            var word = ImportedWord(line: number, term: term, meaning: fields[1], gender: impliedGender)

            var rest = Array(fields.dropFirst(2))

            // The gender column, if that is what it is. An empty one counts
            // only where the language has genders to write: in a language that
            // has none the format has no gender column at all, and an empty
            // third field is an example nobody wrote, with the translation and
            // the note after it.
            if let candidate = rest.first {
                if candidate.isEmpty {
                    if LanguageGenders.marksGender(language) { rest.removeFirst() }
                } else if let gender = Gender.parse(candidate) {
                    word.gender = gender
                    rest.removeFirst()
                }
            }

            // The transcription, wherever it sits: an example sentence is not
            // written in brackets, so a list from before this field existed
            // still reads its third column as an example.
            if let spoken = rest.firstIndex(where: { unbracketed($0) != nil }) {
                word.transcription = unbracketed(rest[spoken]) ?? ""
                rest.remove(at: spoken)
            }

            // Three fields are left to fill. More than three means somebody
            // kept a semicolon for a column this language does not have — a
            // gender in a language with none, a transcription that needed no
            // column — and the empties are at the front. Dropping them is what
            // keeps a note at the end of the line a note.
            while rest.count > 3, rest.first?.isEmpty == true {
                rest.removeFirst()
            }

            word.example = rest.first ?? ""
            word.exampleTranslation = rest.dropFirst().first ?? ""
            word.note = rest.dropFirst(2).first ?? ""

            let identity = key(word.term)
            if seen.contains(identity) {
                word.duplicate = seenInFile.contains(identity) ? .inFile : .inLibrary
            }
            seen.insert(identity)
            seenInFile.insert(identity)

            plan.words.append(word)
        }

        return plan
    }

    // MARK: - Reading a line

    /// Strips what a text file puts around a list and nothing else.
    ///
    /// Returns `nil` for a line that is not a word: blank, a Markdown heading,
    /// or the `---` under one.
    private static func cleaned(_ raw: String) -> String? {
        var line = raw.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return nil }
        guard !line.hasPrefix("#") else { return nil }
        // The fences around a code block, which is how an AI hands a list back
        // and how the prompt in A List asks for it: ``` or ```text.
        guard !line.hasPrefix("```") else { return nil }
        guard line.first(where: { $0 != "-" && $0 != "=" && $0 != "*" && $0 != "_" }) != nil else { return nil }

        // A Markdown bullet is punctuation, not a word.
        for bullet in ["- ", "* ", "+ "] where line.hasPrefix(bullet) {
            line = String(line.dropFirst(bullet.count))
            break
        }

        return line.trimmingCharacters(in: .whitespaces)
    }

    /// The inside of a field written as a transcription, or `nil` if it is not
    /// one.
    ///
    /// The brackets are how a transcription says what it is without needing a
    /// column of its own, and all three pairs are in use: square brackets are
    /// what dictionaries print, slashes are what phonology writes, and angle
    /// brackets are what a learner reaches for when the others are taken.
    private static func unbracketed(_ field: String) -> String? {
        for (open, close) in [("[", "]"), ("/", "/"), ("⟨", "⟩")] {
            guard field.hasPrefix(open), field.hasSuffix(close), field.count > open.count + close.count else { continue }
            let inside = field.dropFirst(open.count).dropLast(close.count)
                .trimmingCharacters(in: .whitespaces)
            guard !inside.isEmpty else { continue }
            return inside
        }
        return nil
    }

    /// Splits a line into fields.
    ///
    /// A semicolon is the format. A tab is what a spreadsheet gives when the
    /// list came from one. A dash with spaces around it is what people write
    /// when nobody told them a format, and it only ever means "word, meaning".
    private static func split(_ line: String) -> [String] {
        let fields: [String]

        if line.contains(";") {
            fields = line.components(separatedBy: ";")
        } else if line.contains("\t") {
            fields = line.components(separatedBy: "\t")
        } else if let range = line.range(of: " — ") ?? line.range(of: " – ") ?? line.range(of: " - ") {
            fields = [String(line[line.startIndex..<range.lowerBound]),
                      String(line[range.upperBound...])]
        } else {
            fields = [line]
        }

        var trimmed = fields.map { $0.trimmingCharacters(in: .whitespaces) }
        // Trailing separators are typing, not empty columns.
        while let last = trimmed.last, last.isEmpty, trimmed.count > 2 {
            trimmed.removeLast()
        }
        return trimmed
    }

    /// Words are the same word whatever the case and whatever article was typed
    /// in front of them.
    private static func key(_ term: String) -> String {
        term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
