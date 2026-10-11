import Foundation

/// The games the Games section offers.
///
/// One today. The section is laid out as a shelf rather than as one big button
/// because there will be more, and a shelf with one thing on it still reads as
/// a shelf.
enum GameKind: String, CaseIterable, Identifiable {
    case wordFall
    /// Hear a phrase, type it back. The app's own.
    case dictation

    var id: String { rawValue }

    /// The game's own name, as it appears on its title screen.
    var title: String {
        switch self {
        case .wordFall: "WordFall"
        case .dictation: "Dictation"
        }
    }

    var summary: String {
        switch self {
        case .wordFall: "A downhill race. Steer through the gate that holds the right answer."
        case .dictation: "Hear a phrase and type it back. Only its first letters are given."
        }
    }

    /// How the game is recognised on the shelf.
    ///
    /// A game that arrives as a package brings its own artwork; one written
    /// here is drawn here, out of a symbol and the app's own tint, so that
    /// adding a game is not also commissioning a picture.
    var icon: GameIcon {
        switch self {
        case .wordFall: .artwork("WordFallIcon")
        case .dictation: .symbol("waveform.badge.magnifyingglass")
        }
    }

    /// The fewest words the language needs before the game can be played.
    ///
    /// WordFall asks a question with three answers, so it needs three words.
    /// Dictation reads out whatever there is.
    var minimumWords: Int {
        switch self {
        case .wordFall: GameVocabulary.minimumWords
        case .dictation: 1
        }
    }

    /// Whether the shelf itself can tell the game cannot be played.
    ///
    /// WordFall cannot start without words. Dictation can: a learner may have
    /// written sentences of their own, and its own screen is the honest place
    /// to say what is missing.
    var needsWordsToOpen: Bool {
        switch self {
        case .wordFall: true
        case .dictation: false
        }
    }

    /// Whether the game divides its words by deck on the shelf. Dictation
    /// chooses its own deck on its own screen, where the rest of its settings
    /// are.
    var picksDecksOnTheShelf: Bool {
        switch self {
        case .wordFall: true
        case .dictation: false
        }
    }
}

/// A game's picture: its own, or one drawn from a symbol.
enum GameIcon {
    case artwork(String)
    case symbol(String)
}
