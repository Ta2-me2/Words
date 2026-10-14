import Foundation

/// Where a thing to hear came from.
nonisolated enum DictationSource: String, Codable, CaseIterable, Sendable {
    /// A word of the library, said on its own.
    case word
    /// The example sentence kept with a word of the library — which is also
    /// where the companion writes the sentences it makes.
    case example
    /// A sentence the learner wrote into the game itself.
    case written
}

/// One thing to hear and type back.
///
/// Built fresh from the library every time the game opens rather than stored:
/// a word renamed, re-translated or deleted must not leave the game playing
/// something that is no longer true. What *is* stored is the progress against
/// it, under `key`, which survives all of that.
nonisolated struct DictationItem: Identifiable, Hashable, Sendable {

    var id: String { key }

    /// What identifies this exercise for as long as it exists: the word it
    /// came from and which side of it, or the sentence's own identifier.
    let key: String

    /// What is said aloud and has to be typed.
    let text: String

    /// What it means, shown once the answer is in.
    let meaning: String

    let source: DictationSource

    /// The library word behind it, where there is one — for playing its own
    /// recording instead of the voice, and for opening it afterwards.
    let entryID: UUID?

    static func key(_ source: DictationSource, _ id: UUID) -> String {
        "\(source.rawValue):\(id.uuidString)"
    }
}

/// The words of a phrase, as the game treats them.
///
/// Splitting is the whole game's foundation: what counts as a word decides what
/// is typed, what is hinted and what is marked wrong. Anything that is not a
/// letter, a digit or a mark inside a word — an apostrophe, a hyphen — ends it.
nonisolated enum DictationText {

    /// Marks that belong inside a word rather than between words. "don't" and
    /// "well-known" are one word each; "don" and "t" would be two mistakes.
    private static let joiners: Set<Character> = ["'", "’", "-", "‑", "."]

    static func words(of text: String) -> [String] {
        var words: [String] = []
        var current = ""
        for character in text {
            if character.isLetter || character.isNumber {
                current.append(character)
            } else if joiners.contains(character), !current.isEmpty {
                current.append(character)
            } else if !current.isEmpty {
                words.append(trimmed(current))
                current = ""
            }
        }
        if !current.isEmpty { words.append(trimmed(current)) }
        return words.filter { !$0.isEmpty }
    }

    /// A joiner at the very end was punctuation after all: "day." is "day".
    private static func trimmed(_ word: String) -> String {
        var word = word
        while let last = word.last, joiners.contains(last) { word.removeLast() }
        return word
    }

    /// How a word is compared: case and punctuation are not what is being
    /// practised here, so they are not what is marked wrong.
    static func compared(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// The ways a word may be written by somebody whose keyboard will not make
    /// its letters.
    ///
    /// Two of them, because there are two habits and both are honest: dropping
    /// the mark (`groß` → `gros`), and writing the letter out the way the
    /// language itself does when it has to (`groß` → `gross`, `Bär` → `Baer`).
    /// A word matching either is told what it should have been rather than
    /// marked wrong — the point of the game is hearing, not typography.
    static func looseForms(of word: String) -> Set<String> {
        let plain = compared(word)
        var spelled = ""
        for character in plain {
            switch character {
            case "ß": spelled += "ss"
            case "ä": spelled += "ae"
            case "ö": spelled += "oe"
            case "ü": spelled += "ue"
            case "æ": spelled += "ae"
            case "ø": spelled += "oe"
            case "å": spelled += "aa"
            default: spelled.append(character)
            }
        }
        return [
            plain.folding(options: [.diacriticInsensitive], locale: nil),
            spelled.folding(options: [.diacriticInsensitive], locale: nil)
        ]
    }
}

/// How much of a word is given away before it is typed.
nonisolated enum DictationHint: String, Codable, CaseIterable, Identifiable, Sendable {
    /// `d···` — the first letter and how many follow.
    case firstLetter
    /// `····` — how long the word is, and nothing else.
    case length
    /// Nothing at all: how many words there are, and that is all.
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firstLetter: "First letters"
        case .length: "Word lengths"
        case .none: "Nothing"
        }
    }

    var detail: String {
        switch self {
        case .firstLetter: "The first letter of each word, and a dot for every letter after it."
        case .length: "A dot for every letter. Which word it is, is yours to hear."
        case .none: "How many words there are, and nothing else."
        }
    }

    /// The hint for one word: "d···", "····" or "—".
    func drawn(for word: String) -> String {
        let letters = Array(word)
        guard !letters.isEmpty else { return "" }
        switch self {
        case .firstLetter:
            return String(letters[0]) + String(repeating: "·", count: letters.count - 1)
        case .length:
            return String(repeating: "·", count: letters.count)
        case .none:
            return "—"
        }
    }
}

/// What one typed word turned out to be.
nonisolated enum DictationMark: Hashable, Sendable {
    case right
    /// Right but for the accents — told, not failed.
    case almost
    case wrong
    /// Nothing was typed where a word was wanted.
    case missing
}

/// One word of an answer, lined up against what was wanted.
nonisolated struct DictationWord: Identifiable, Hashable, Sendable {
    var id: Int
    /// What should have been typed.
    var expected: String
    /// What was typed, if anything.
    var typed: String
    var mark: DictationMark

    var isFaulty: Bool { mark == .wrong || mark == .missing }
}

/// An answer, marked.
nonisolated struct DictationResult: Hashable, Sendable {
    var words: [DictationWord]
    /// Words typed where the phrase had none.
    var extra: [String]

    var mistakes: Int { words.count { $0.isFaulty } + extra.count }
    var isPerfect: Bool { mistakes == 0 && !words.contains { $0.mark == .almost } }
    var isRight: Bool { mistakes == 0 }

    /// Of the words wanted, how many arrived — the figure the statistics are
    /// built on, because a learner who gets seven words of eight has not
    /// simply failed.
    var accuracy: Double {
        guard !words.isEmpty else { return 0 }
        return Double(words.count { !$0.isFaulty }) / Double(words.count)
    }
}

/// Marking an answer, and turning it into something the scheduler understands.
nonisolated enum DictationCheck {

    static func mark(_ typed: String, against phrase: String) -> DictationResult {
        mark(words: DictationText.words(of: typed), against: phrase)
    }

    /// The same, for an answer typed a box per word.
    ///
    /// A box left empty holds its place rather than closing the gap, so a
    /// learner who could not catch the third word of five is told that the
    /// third word is the one they missed, instead of having the fourth marked
    /// wrong for standing where the third should have been. A box with two
    /// words in it — which happens, because a box can be typed into freely —
    /// gives up both, in order.
    static func mark(boxes: [String], against phrase: String) -> DictationResult {
        let given = boxes.flatMap { box -> [String] in
            let words = DictationText.words(of: box)
            return words.isEmpty ? [""] : words
        }
        return mark(words: given, against: phrase)
    }

    private static func mark(words given: [String], against phrase: String) -> DictationResult {
        let wanted = DictationText.words(of: phrase)

        var words: [DictationWord] = []
        for (index, expected) in wanted.enumerated() {
            guard index < given.count, !given[index].isEmpty else {
                words.append(DictationWord(id: index, expected: expected, typed: "", mark: .missing))
                continue
            }
            let actual = given[index]
            let mark: DictationMark
            if DictationText.compared(actual) == DictationText.compared(expected) {
                mark = .right
            } else if !DictationText.looseForms(of: actual).isDisjoint(with: DictationText.looseForms(of: expected)) {
                mark = .almost
            } else {
                mark = .wrong
            }
            words.append(DictationWord(id: index, expected: expected, typed: actual, mark: mark))
        }

        // Boxes nobody typed in are not words typed where the phrase had none.
        let extra = given.count > wanted.count
            ? given[wanted.count...].filter { !$0.isEmpty }
            : []
        return DictationResult(words: words, extra: Array(extra))
    }

    /// What an answer is worth.
    ///
    /// The learner never presses a grade button here — the typing is the
    /// answer, and a phrase either came back or it did not. Heard again or
    /// looked up, it counts for less: a word recalled after being shown is not
    /// a word recalled.
    static func grade(_ result: DictationResult, replays: Int, revealed: Bool) -> ReviewGrade {
        if revealed || result.mistakes > 1 { return .again }
        if result.mistakes == 1 { return .hard }
        if replays > 1 || !result.isPerfect { return .good }
        return replays == 0 ? .easy : .good
    }
}
