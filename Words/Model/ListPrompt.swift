import Foundation

/// The instructions a learner hands to an AI so that the list it writes can be
/// pasted straight into A List.
///
/// Only the rules of the format, never the request itself. What the learner
/// wants — a hundred A1 words, the vocabulary of a cooking show — is theirs to
/// write underneath. What is here is what the parser in `WordImport` will
/// accept, said in words a model follows well, and it is written from the
/// parser's own rules rather than from memory of them: the checks read lines
/// built the way this text says, and fail if the two ever disagree.
nonisolated enum ListPrompt {

    /// The prompt for a language, with its names written in English whatever
    /// language the Mac is set to: the instructions are in English, and "Deutsch"
    /// in the middle of an English sentence is a small thing a model can
    /// misread.
    static func standard(for profile: LanguageProfile) -> String {
        standard(learning: profile.learningCode, native: profile.nativeCode)
    }

    static func standard(learning: String, native: String) -> String {
        let word = LanguageCatalog.englishName(for: learning)
        let meaning = LanguageCatalog.englishName(for: native)
        let gendered = LanguageGenders.marksGender(learning)

        var lines: [String] = []
        lines.append("Whenever I ask you for vocabulary, write it in the format below and nothing else. A flashcard app reads it line by line, so the format has to be followed exactly.")
        lines.append("")
        lines.append("FORMAT")
        lines.append("One word per line, with the fields separated by semicolons:")
        lines.append("")
        lines.append(gendered
            ? "word;meaning;gender;[transcription];example;example translation;note"
            : "word;meaning;[transcription];example;example translation;note")
        lines.append("")
        lines.append("FIELDS")
        lines.append(gendered
            ? "- word: the \(word) word, written the way a dictionary lists it. Write nouns without their article."
            : "- word: the \(word) word or phrase, written the way a dictionary lists it.")
        lines.append("- meaning: what it means in \(meaning). If it has several meanings, put them all in this one field, separated by commas.")
        if gendered {
            let articles = Gender.allCases.compactMap { gender -> String? in
                guard let article = LanguageGenders.article(gender, language: learning) else { return nil }
                return "\(gender.short) for \(gender.title.lowercased()) (\(article))"
            }
            lines.append("- gender: for nouns only — \(articles.joined(separator: ", ")). Leave it empty for every other kind of word.")
        }
        lines.append("- transcription: how the word is said, written inside square brackets — IPA, or the sounds spelled out in the \(meaning) alphabet. The brackets are what marks the field, so it can never be mistaken for an example. Optional.")
        lines.append("- example: a short, natural \(word) sentence that uses the word. Optional.")
        lines.append("- example translation: that sentence in \(meaning). Optional.")
        lines.append("- note: anything worth remembering with the word — a plural, an irregular form, a warning. One short line. Optional.")
        lines.append("")
        lines.append("RULES")
        lines.append("- Only the word and its meaning are required.")
        lines.append("- Leave out a transcription you do not have: it is found by its brackets, not by its place, so it never needs an empty column.")
        if gendered {
            lines.append("- When any other field is empty but a later one is not, keep its semicolons: a verb with an example is word;meaning;;example;example translation.")
        } else {
            lines.append("- When any other field is empty but a later one is not, keep its semicolons: a word with only a note is word;meaning;;;note.")
        }
        lines.append("- Never use a semicolon inside a field.")
        lines.append("- No numbering, bullets, headings, blank lines or comments between the lines.")
        lines.append("- Give the whole list in a single code block, so it can be copied in one go.")
        return lines.joined(separator: "\n")
    }

    /// What a learner's saved version is, or the standard one if they never
    /// changed it.
    static func current(for profile: LanguageProfile) -> String {
        profile.listPrompt ?? standard(for: profile)
    }

    /// What to store for a draft: nothing at all when it is the standard text,
    /// so a learner who never changed anything keeps getting the standard one
    /// as it improves.
    static func stored(_ draft: String, for profile: LanguageProfile) -> String? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != standard(for: profile) else { return nil }
        return draft
    }
}
