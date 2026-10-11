import Foundation

/// What the companion is told when it is asked for an example sentence, and
/// what counts as an answer.
///
/// Written here, away from the model, for the same reason the card assistant's
/// text is: a model is only as right as what it was given, and what it was
/// given should be readable and checkable without running it. The reading half
/// matters as much as the asking — a sentence that does not contain the word
/// it was asked for is no use to anybody, and is refused rather than saved.
nonisolated enum SentencePrompt {

    /// How short a sentence may be, and how long. Below three words it is not
    /// a sentence; above sixteen it is not an example.
    static let wordRange = 3 ... 16

    static func instructions(for profile: LanguageProfile) -> String {
        let learning = LanguageCatalog.englishName(for: profile.learningCode)
        let native = LanguageCatalog.englishName(for: profile.nativeCode)

        var lines: [String] = []
        lines.append("You write example sentences for somebody learning \(learning). You are given one word; you write one sentence that uses it, and the translation of that sentence.")
        lines.append("")
        lines.append("THE SENTENCE")
        lines.append("- In \(learning), and it must use the given word. A different form of the word — a plural, a conjugation, a case — is right and welcome.")
        lines.append("- Between \(wordRange.lowerBound) and \(wordRange.upperBound) words. One sentence, ending in a full stop.")
        lines.append("- Everyday language a beginner would actually meet. Simple present unless the word asks for something else.")
        lines.append("- Grammatically perfect: articles, agreement, case and word order all correct. This is the whole point — a learner cannot tell a wrong sentence from a right one, and will learn whatever you write. If you are not certain a sentence is correct, write a simpler one you are certain of.")
        lines.append("- Nothing that needs explaining: no names, no idioms, no wordplay.")
        lines.append("")
        lines.append("THE TRANSLATION")
        lines.append("- The same sentence in \(native), written naturally rather than word for word.")
        lines.append("")
        lines.append("HOW TO ANSWER")
        lines.append("Two lines, and nothing else at all — no labels, no quotation marks, no explanation:")
        lines.append("<the \(learning) sentence>")
        lines.append("<the \(native) translation>")
        return lines.joined(separator: "\n")
    }

    static func ask(word: String, meaning: String) -> String {
        let meaning = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        return meaning.isEmpty ? "Word: \(word)" : "Word: \(word) (\(meaning))"
    }

    /// Reads what came back, or `nil` if it cannot be used.
    ///
    /// Models answer tidily most of the time and then, every so often, with a
    /// label, a bullet, a pair of quotation marks or an apology. Those are
    /// taken off; anything that is still not a sentence using the word is
    /// refused, because a wrong example is worse than none.
    static func read(_ text: String, word: String) -> (sentence: String, translation: String)? {
        let lines = text
            .components(separatedBy: .newlines)
            .map { tidied($0) }
            .filter { !$0.isEmpty }

        guard let sentence = lines.first else { return nil }
        let translation = lines.count > 1 ? lines[1] : ""

        let count = DictationText.words(of: sentence).count
        guard wordRange.contains(count) else { return nil }
        guard uses(word, in: sentence) else { return nil }
        return (sentence, translation)
    }

    /// One line, with whatever the model put around it taken off.
    private static func tidied(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)

        for bullet in ["- ", "* ", "• ", "1. ", "2. "] where text.hasPrefix(bullet) {
            text = String(text.dropFirst(bullet.count))
        }
        for label in ["sentence:", "translation:", "example:", "answer:"] where text.lowercased().hasPrefix(label) {
            text = String(text.dropFirst(label.count)).trimmingCharacters(in: .whitespaces)
        }
        text = text.replacingOccurrences(of: "**", with: "")
        while let first = text.first, "\"'“”«".contains(first) { text = String(text.dropFirst()) }
        while let last = text.last, "\"'“”»".contains(last) { text = String(text.dropLast()) }

        return text.trimmingCharacters(in: .whitespaces)
    }

    /// Whether a sentence really uses the word it was asked for.
    ///
    /// By the stem rather than the whole word, because the useful answer often
    /// inflects it: asked for "gehen", "Ich gehe nach Hause" is exactly right.
    /// A short word has no stem to speak of and has to appear as itself.
    static func uses(_ word: String, in sentence: String) -> Bool {
        let wanted = DictationText.compared(word)
        guard !wanted.isEmpty else { return false }
        let words = DictationText.words(of: sentence).map { DictationText.compared($0) }

        if wanted.count <= 3 { return words.contains(wanted) }
        let stem = String(wanted.prefix(max(4, wanted.count - 2)))
        return words.contains { $0.hasPrefix(stem) || wanted.hasPrefix($0) && $0.count >= stem.count }
    }
}
