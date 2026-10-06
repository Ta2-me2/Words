import Foundation

/// A named group of words inside one language.
///
/// A deck is a subdivision of a language, never a thing of its own: it belongs
/// to a profile, it can be studied on its own, and deleting it returns its
/// words to the language rather than destroying them.
///
/// Decks go two levels deep and no further. "Germany" can hold "A1" and "A2";
/// "A1" cannot hold anything. A third level is where a sidebar stops being a
/// map and becomes a filing cabinet, and every picker in the app would have to
/// learn to draw a tree to keep up.
nonisolated struct Deck: Identifiable, Codable, Hashable, Sendable {

    var id: UUID
    var profileID: UUID
    var name: String

    /// The deck this one sits inside, or `nil` for a deck at the top of its
    /// language.
    ///
    /// A deck contains its subdecks: studying "Germany" studies "A1" and "A2"
    /// with it, and its word count includes theirs. A word can still be filed
    /// in "Germany" itself — a subdeck is a way of dividing a deck, not a rule
    /// that everything in it must be divided.
    var parentID: UUID?

    /// What the deck is recognised by in the sidebar, or `nil` for the ordinary
    /// stack.
    var icon: DeckIcon?

    /// How many unseen words a day this deck will start, or `nil` to follow
    /// the deck above it, and the language above that.
    ///
    /// A deck is studied on its own, so its allowance is its own: a learner
    /// working through "Serials" should get their twenty words from it whether
    /// or not another deck was studied this morning.
    var dailyNewLimit: Int?

    var createdAt: Date

    init(
        id: UUID = UUID(),
        profileID: UUID,
        name: String,
        parentID: UUID? = nil,
        icon: DeckIcon? = nil,
        dailyNewLimit: Int? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.profileID = profileID
        self.name = name
        self.parentID = parentID
        self.icon = icon
        self.dailyNewLimit = dailyNewLimit.map { max(0, $0) }
        self.createdAt = createdAt
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Deck" : trimmed
    }

    var isSubdeck: Bool { parentID != nil }

    /// The icon to draw: the chosen one, or the ordinary stack.
    var displayIcon: DeckIcon { icon ?? .standard }
}

/// A deck's icon: one of the system's own symbols, or an emoji.
///
/// Symbols are drawn in the sidebar's own tint and change with the accent
/// colour and the selection, the way every other row does. An emoji is drawn
/// as itself — which is the point of choosing one: 🇩🇪 is recognisable in a
/// way no symbol for "German" could be.
nonisolated enum DeckIcon: Hashable, Sendable {
    case symbol(String)
    case emoji(String)

    static let standard = DeckIcon.symbol("rectangle.stack")

    /// The one emoji a person typed or pasted, or `nil` if there is none.
    ///
    /// Only the first character counts, because an icon is one picture; and
    /// only a character that is really an emoji, because "A" or "7" typed by
    /// accident would otherwise sit in the sidebar looking like a mistake.
    /// Digits and `#` are emoji to Unicode when a variation selector follows
    /// them, so a lone ASCII character is refused explicitly.
    static func emoji(in text: String) -> DeckIcon? {
        guard let character = text.first(where: { !$0.isWhitespace }) else { return nil }
        let scalars = character.unicodeScalars
        let isEmoji = scalars.contains { $0.properties.isEmojiPresentation }
            || (scalars.count > 1 && scalars.contains { $0.properties.isEmoji })
        guard isEmoji, !(scalars.count == 1 && character.isASCII) else { return nil }
        return .emoji(String(character))
    }
}

extension DeckIcon: Codable {

    private enum CodingKeys: String, CodingKey { case symbol, emoji }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let emoji = try container.decodeIfPresent(String.self, forKey: .emoji) {
            self = .emoji(emoji)
        } else {
            self = .symbol(try container.decode(String.self, forKey: .symbol))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .symbol(let name): try container.encode(name, forKey: .symbol)
        case .emoji(let emoji): try container.encode(emoji, forKey: .emoji)
        }
    }
}

/// What a sitting, a count or a list is drawn from when it is a deck rather
/// than the whole language: the deck, every deck inside it, and the allowance
/// of new words it works to.
///
/// Worked out once by the library, which is the only thing that knows which
/// decks sit inside which, and handed to the queue, which then never has to
/// ask.
nonisolated struct DeckScope: Hashable, Sendable {

    let deckID: UUID

    /// The deck and its subdecks.
    let deckIDs: Set<UUID>

    /// Its own limit, or that of the deck it sits inside, or `nil` to follow
    /// the language.
    let dailyNewLimit: Int?

    func contains(_ entry: Entry) -> Bool {
        guard let deckID = entry.deckID else { return false }
        return deckIDs.contains(deckID)
    }
}
