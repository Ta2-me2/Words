import Foundation

/// What a language puts beside a word to say what gender it is.
///
/// Two kinds, because languages do two different things, and the difference is
/// not cosmetic — it decides what the voice reads. German puts a word in front
/// of the noun and you say it: *die Mutter*, both words. Russian puts nothing
/// in front of anything; the gender is a fact a dictionary prints beside the
/// entry — *жен.* — and reading that out loud would be reading out a footnote.
///
/// So nothing downstream guesses from the language code. Speech asks whether
/// the mark is spoken and takes only the ones that are; the card shows both,
/// and shows them in the same place.
nonisolated enum GenderMark: Hashable, Sendable {

    /// A word said with the noun, written as it appears in front of *this*
    /// word — French and Italian change it to `l'` before a vowel.
    case article(String)

    /// A short note shown beside the word and never spoken, written in the
    /// language being learned, the way that language's own dictionaries write
    /// it.
    case label(String)

    var text: String {
        switch self {
        case .article(let text), .label(let text): text
        }
    }

    /// Whether it belongs in what the voice reads.
    var isSpoken: Bool {
        switch self {
        case .article: true
        case .label: false
        }
    }

    /// What goes between the mark and the word: nothing after an elided
    /// article, a space after everything else.
    ///
    /// An apostrophe is the rule rather than a list of languages because that
    /// is what elision *is* in every language that does it — `l'eau`,
    /// `l'amico`, `un'amica` — and a language that elides without one would be
    /// a surprise worth writing a case for.
    var spacer: String {
        guard case .article(let text) = self else { return " " }
        return text.hasSuffix("'") || text.hasSuffix("’") ? "" : " "
    }

    /// The mark and the word as one piece of text.
    ///
    /// One function rather than a string and a space at each call site,
    /// because `l'eau` is wrong with a space in it and there are nine places
    /// that would each have had to remember.
    func phrase(with term: String) -> String {
        "\(text)\(spacer)\(term)"
    }
}
