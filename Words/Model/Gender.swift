import Foundation

/// The grammatical gender of a word.
///
/// Stored on the word as a fact about it, never as an article: which article a
/// gender takes is a property of the language, and the same word imported into
/// two languages would take two different ones.
nonisolated enum Gender: String, Codable, CaseIterable, Identifiable, Sendable {
    case feminine = "f"
    case masculine = "m"
    case neuter = "n"

    var id: String { rawValue }

    /// The single letter used in import files and in tight spaces.
    var short: String { rawValue }

    var title: String {
        switch self {
        case .feminine: "Feminine"
        case .masculine: "Masculine"
        case .neuter: "Neuter"
        }
    }

    /// Reads the third field of an import line.
    ///
    /// Deliberately narrow: one token, and one of the ones a word list actually
    /// uses. Anything else is not a gender, which is how the parser knows the
    /// field was an example instead.
    static func parse(_ text: String) -> Gender? {
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !token.isEmpty, !token.contains(" ") else { return nil }

        switch token {
        case "f", "f.", "fem", "fem.", "feminine", "die", "la", "w":
            return .feminine
        case "m", "m.", "masc", "masc.", "masculine", "der", "el", "le":
            return .masculine
        case "n", "n.", "neut", "neut.", "neuter", "das", "het", "s":
            return .neuter
        default:
            return nil
        }
    }
}

/// What a language does with gender.
///
/// German is filled in; everything else says "this language does not mark it
/// here", which is the honest answer until its rules are written. Adding a
/// language is adding one case.
nonisolated enum LanguageGenders {

    /// The definite article a language puts in front of a noun of this gender.
    static func article(_ gender: Gender, language code: String) -> String? {
        switch code {
        case "de":
            switch gender {
            case .feminine: "die"
            case .masculine: "der"
            case .neuter: "das"
            }
        default:
            nil
        }
    }

    /// Whether a language is worth asking about gender at all.
    static func marksGender(_ code: String) -> Bool {
        Gender.allCases.contains { article($0, language: code) != nil }
    }

    /// The articles a learner might type in front of a word, and the gender
    /// each one means.
    private static func typedArticles(for code: String) -> [String: Gender] {
        switch code {
        case "de": ["die": .feminine, "der": .masculine, "das": .neuter,
                    "eine": .feminine, "ein": .masculine]
        default: [:]
        }
    }

    /// Takes an article off the front of a typed word and reports what it said.
    ///
    /// This is the whole of the "choosing a gender" interface for a single
    /// word: a German learner types "die Mutter" without being asked to, and
    /// the app files it as Mutter, feminine.
    /// A noun the way a dictionary writes it — "die Ansage, -n", "der Arzt, -ä, e"
    /// — taken apart into the word, its gender and its plural.
    ///
    /// Only when the part before the comma really is an article and a noun;
    /// "gern(e)" and "der/die Bekannte" are left exactly as they were written,
    /// because a wrong guess about a word is worse than no guess.
    static func dictionaryForm(_ text: String, language code: String) -> (term: String, gender: Gender?, plural: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comma = trimmed.firstIndex(of: ",") else {
            let (term, gender) = split(term: trimmed, language: code)
            return (term, gender, nil)
        }

        let head = String(trimmed[..<comma])
        let tail = trimmed[trimmed.index(after: comma)...].trimmingCharacters(in: .whitespaces)
        let (term, gender) = split(term: head, language: code)
        guard gender != nil else { return (trimmed, nil, nil) }
        return (term, gender, tail.isEmpty ? nil : tail)
    }

    static func split(term: String, language code: String) -> (term: String, gender: Gender?) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let articles = typedArticles(for: code)
        guard !articles.isEmpty else { return (trimmed, nil) }

        // Exactly two words, or it is a phrase rather than an article and a
        // noun: "das ist gut" is a sentence, and taking "das" off it would
        // leave the learner with a word they never wrote.
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 2, let gender = articles[parts[0].lowercased()] else {
            return (trimmed, nil)
        }

        return (String(parts[1]), gender)
    }
}
