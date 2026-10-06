import Foundation

/// A set of words a game can be played with: the whole language, or one of its
/// decks.
nonisolated struct GameCollection: Identifiable, Hashable, Sendable {

    /// Stable across launches, because a game keeps its levels by it.
    var id: String
    var name: String

    /// The deck it came from, or `nil` for the whole language.
    var deckID: UUID?

    var words: [GameWord]
}

nonisolated struct GameWord: Identifiable, Hashable, Sendable {

    /// The word's own identifier, so that what a game learns about a word
    /// survives the word being edited, moved to another deck, or appearing in
    /// two collections at once.
    var id: String

    /// As it is read — with its article, where the language has one.
    var word: String

    var translation: String
}

/// Which of a language's words a game may use.
///
/// Nothing a game does touches the schedule: a game is practice, and practice
/// changes nothing. What is decided here is only which words go in.
///
/// A choice of three needs one right answer and two wrong ones, so a collection
/// of fewer than three words cannot be played at all. It is left out rather
/// than offered and then refused.
nonisolated enum GameVocabulary {

    static let minimumWords = 3

    /// The whole language. The app never names it — it is simply what the
    /// Library shows before a deck is chosen — but a game's picker has to call
    /// it something.
    static let allWordsID = "all"
    static let allWordsName = "All Words"

    /// Every collection that can actually be played, the whole language first
    /// and then the decks, each followed by the decks inside it. A deck plays
    /// with its subdecks' words as well as its own.
    static func collections(for profile: LanguageProfile, in library: Library) -> [GameCollection] {
        var result: [GameCollection] = []

        let everything = words(library.entries(in: profile.id), profile: profile)
        if everything.count >= minimumWords {
            result.append(GameCollection(id: allWordsID, name: allWordsName, deckID: nil, words: everything))
        }

        for deck in library.decks(in: profile.id) {
            let inDeck = words(library.entries(in: profile.id, deckID: deck.id), profile: profile)
            guard inDeck.count >= minimumWords else { continue }
            // A subdeck is named by where it sits: two decks called "A1" in two
            // different decks are two different things to play.
            result.append(GameCollection(id: deck.id.uuidString, name: library.path(of: deck), deckID: deck.id, words: inDeck))
        }

        return result
    }

    /// The decks left out, so the screen can say why they are missing.
    static func tooSmall(for profile: LanguageProfile, in library: Library) -> [Deck] {
        library.decks(in: profile.id).filter { deck in
            words(library.entries(in: profile.id, deckID: deck.id), profile: profile).count < minimumWords
        }
    }

    private static func words(_ entries: [Entry], profile: LanguageProfile) -> [GameWord] {
        entries.compactMap { entry in
            let word = entry.displayTerm(in: profile).trimmingCharacters(in: .whitespacesAndNewlines)
            let translation = entry.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
            // A blank on either side would make the game refuse the whole
            // collection, so one bad word is dropped instead.
            guard !word.isEmpty, !translation.isEmpty else { return nil }
            return GameWord(id: entry.id.uuidString, word: word, translation: translation)
        }
    }
}
