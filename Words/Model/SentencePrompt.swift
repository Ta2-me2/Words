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
        lines.append("- If the word has several meanings, take the one the learner was given and ignore the rest.")
        lines.append("")
        lines.append("THE TRANSLATION")
        lines.append("- The same sentence in \(native), written naturally rather than word for word.")
        lines.append("")
        lines.append("HOW TO ANSWER")
        lines.append("Two lines, and nothing else at all — no greeting before them, no note after them, no labels, no quotation marks, no explanation:")
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
    /// label, a bullet, a pair of quotation marks, an apology, or a paragraph
    /// about what they have just written. None of that is refused outright:
    /// the answer is searched for the line that is actually a sentence using
    /// the word, and the rest is left where it was. What cannot be found that
    /// way is refused, because a wrong example is worse than none.
    static func read(_ text: String, word: String) -> (sentence: String, translation: String)? {
        let lines = text
            .components(separatedBy: .newlines)
            .map { tidied($0) }
            .filter { !$0.isEmpty }

        // The first line that is a sentence using the word. A model that
        // begins with "Sure — here you are:" has still answered, and throwing
        // the whole answer away over its manners would refuse a good sentence.
        //
        // Twice over, because a line that mentions the word is not always the
        // sentence: a model explaining itself writes "Here is an example with
        // Haus, which means house" first and the sentence after it. A line
        // that ends the way a sentence ends is preferred; only if there is no
        // such line does one that merely reads like a sentence do.
        for mustEnd in [true, false] {
            for (index, line) in lines.enumerated() {
                // Both halves on one line first, which is the other thing that
                // happens: "Das Haus ist groß. — Дом большой." Read whole, that
                // line passes for a sentence and the translation is lost
                // inside it, so the halves are tried before the line.
                if let halved = halved(line, word: word, mustEnd: mustEnd) { return halved }
                if isSentence(line, using: word, mustEnd: mustEnd) {
                    return (line, translation(after: index, in: lines))
                }
            }
        }

        return nil
    }

    /// A line carrying the sentence and its translation at once, told apart by
    /// what is between them. A separator only counts with space around it, so
    /// a hyphenated word and a decimal point are left alone.
    private static func halved(_ line: String, word: String, mustEnd: Bool) -> (sentence: String, translation: String)? {
        for separator in [" — ", " – ", " - ", " / ", " | ", " = ", " · "] {
            let halves = line.components(separatedBy: separator)
            guard halves.count == 2 else { continue }
            let sentence = tidied(halves[0])
            guard isSentence(sentence, using: word, mustEnd: mustEnd) else { continue }
            return (sentence, usable(tidied(halves[1]), sentence: sentence) ?? "")
        }
        return nil
    }

    /// Whether a line is the sentence that was asked for: the right length,
    /// really using the word, and not the introduction to one.
    private static func isSentence(_ line: String, using word: String, mustEnd: Bool) -> Bool {
        guard !line.hasSuffix(":") else { return false }
        guard wordRange.contains(DictationText.words(of: line).count) else { return false }
        guard !mustEnd || ends.contains(line.last ?? " ") else { return false }
        return uses(word, in: line)
    }

    /// How a sentence ends, in the scripts a learner might be reading.
    private static let ends: Set<Character> = [".", "!", "?", "…", "。", "！", "？", "।", "۔", "؟"]

    /// The translation: the next line that is not the sentence over again.
    private static func translation(after spoken: Int, in lines: [String]) -> String {
        let sentence = lines[spoken]
        for line in lines.dropFirst(spoken + 1) {
            guard let usable = usable(line, sentence: sentence) else { continue }
            return usable
        }
        return ""
    }

    /// Whether a line can be used as the translation of this sentence.
    ///
    /// Not the sentence repeated, and not an essay: a translation of sixteen
    /// words cannot itself be thirty, and a model that has started explaining
    /// itself is writing something that does not belong on a card. Rather
    /// than refuse the sentence over it, the sentence is kept and the
    /// translation left empty for the learner to fill in.
    private static func usable(_ line: String, sentence: String) -> String? {
        let bare = DictationText.compared(line)
        guard !bare.isEmpty, bare != DictationText.compared(sentence) else { return nil }
        guard DictationText.words(of: line).count <= wordRange.upperBound + 6 else { return nil }
        return line
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
