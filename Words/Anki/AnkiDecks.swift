import Foundation

/// How deeply an Anki deck's own structure is kept.
///
/// Anki nests decks as deep as an author likes — "Course::Chapter 2::Faire" —
/// and Words goes two levels and stops. The top of an Anki deck is always the
/// Words deck; what differs is which of the levels under it become subdecks.
nonisolated enum AnkiSubdeckStyle: String, CaseIterable, Identifiable, Hashable, Sendable {
    /// Everything in one deck.
    case none
    /// The level just under the top: "Chapter 2". Anything deeper is poured
    /// into the subdeck above it.
    case firstLevel
    /// Every level under the top, run together into one name:
    /// "Chapter 2 · Faire". The finest the deck was divided, at the price of
    /// long names.
    case allLevels

    var id: String { rawValue }

    /// How levels run together when they are kept in one name. Not " › ":
    /// that is how Words writes a deck inside a deck, and a subdeck called
    /// "Chapter 2 › Faire" would look like a third level that is not there.
    static let joiner = " · "
}

/// Where each note of an Anki deck sits, measured from the deck's own top.
nonisolated struct AnkiDeckLayout: Hashable, Sendable {

    /// The name of the deck everything is imported under: the top level every
    /// note shares, or — when the notes have no top in common — the package's
    /// own name.
    let baseName: String

    /// Each note's path below `baseName`. Empty for a note that sits in the top
    /// deck itself.
    let paths: [Int64: [String]]

    /// How many levels there are below the top, at the deepest.
    let depth: Int

    /// - Parameters:
    ///   - deckNames: each note's Anki deck, in Anki's own `A::B::C` form.
    ///   - fallbackName: what to call the deck when the notes share no top.
    init(deckNames: [Int64: String], fallbackName: String) {
        // Anki's "Default" is where a note lands when nobody chose a deck for
        // it. It is not part of any structure the author made.
        let raw = deckNames.mapValues { name -> [String] in
            let parts = name.components(separatedBy: "::")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return parts == ["Default"] ? [] : parts
        }

        let tops = Set(raw.values.compactMap(\.first))
        if tops.count == 1, let top = tops.first {
            baseName = top
            paths = raw.mapValues { Array($0.dropFirst()) }
        } else {
            // Several decks at the top of one package, or none at all: the
            // package is the thing that holds them, so it lends its name and
            // each of those decks is one level down.
            baseName = fallbackName
            paths = raw
        }
        depth = paths.values.map(\.count).max() ?? 0
    }

    /// Whether the deck has any structure worth offering to keep.
    var hasSubdecks: Bool { depth >= 1 }

    /// Whether there is more than one level under the top, so that the
    /// learner has a real choice between the two styles.
    var hasDeeperLevels: Bool { depth >= 2 }

    /// The styles worth showing for this deck.
    var styles: [AnkiSubdeckStyle] {
        switch depth {
        case 0: [.none]
        case 1: [.none, .firstLevel]
        default: [.none, .firstLevel, .allLevels]
        }
    }

    /// The subdeck a note would go in, or `nil` for the top deck.
    func subdeckName(forNote id: Int64, style: AnkiSubdeckStyle) -> String? {
        guard let path = paths[id], !path.isEmpty else { return nil }
        switch style {
        case .none: return nil
        case .firstLevel: return path[0]
        case .allLevels: return path.joined(separator: AnkiSubdeckStyle.joiner)
        }
    }

    /// The subdecks a style makes of some notes, by name, with how many of
    /// those notes each would hold — in the order Words lists decks.
    func subdecks(for noteIDs: [Int64], style: AnkiSubdeckStyle) -> [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for id in noteIDs {
            guard let name = subdeckName(forNote: id, style: style) else { continue }
            counts[name, default: 0] += 1
        }
        return counts
            .map { (name: $0.key, count: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// Where the words of an import go.
nonisolated enum AnkiDeckTarget: Hashable, Sendable {
    /// A deck at the top of the language, by name — made if the language does
    /// not have one called that already.
    case newDeck(String)
    /// A deck the language already has.
    case existing(UUID)
    /// No deck at all.
    case none
}

/// The decks an import would make or reuse, and which deck each word lands in.
///
/// Worked out against the library as it stands, before anything is written, so
/// the same result can be shown to the learner and then carried out. A deck
/// that is already there under the same name is used rather than made again:
/// importing a deck a second time, or into a deck that already has its
/// chapters, must not leave two "Chapter 2"s side by side.
nonisolated struct AnkiDeckPlacement: Hashable, Sendable {

    nonisolated struct Planned: Identifiable, Hashable, Sendable {
        var deck: Deck
        var isNew: Bool
        var wordCount: Int

        var id: UUID { deck.id }
    }

    /// The deck the import is under, or `nil` when it goes into no deck.
    var top: Planned?

    /// The subdecks it fills, in the order Words lists them.
    var subdecks: [Planned] = []

    /// Each word's deck, by the Anki note it came from.
    var deckOfNote: [Int64: UUID] = [:]

    /// The decks that have to be made, parents first.
    var newDecks: [Deck] {
        ([top].compactMap { $0 } + subdecks).filter(\.isNew).map(\.deck)
    }

    /// Whether the chosen deck can hold subdecks at all. A subdeck cannot, and
    /// "no deck" has nothing to hold them in.
    var canHoldSubdecks = true

    static func resolve(
        target: AnkiDeckTarget,
        style: AnkiSubdeckStyle,
        layout: AnkiDeckLayout,
        noteIDs: [Int64],
        profileID: UUID,
        library: Library
    ) -> AnkiDeckPlacement {
        var placement = AnkiDeckPlacement()

        let parent: Deck
        let parentIsNew: Bool
        switch target {
        case .none:
            placement.canHoldSubdecks = false
            return placement

        case .existing(let id):
            guard let deck = library.deck(id: id), deck.profileID == profileID else {
                placement.canHoldSubdecks = false
                return placement
            }
            parent = deck
            parentIsNew = false

        case .newDeck(let name):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let same = library.topLevelDecks(in: profileID).first(where: { Self.sameName($0.displayName, trimmed) }) {
                parent = same
                parentIsNew = false
            } else {
                parent = Deck(profileID: profileID, name: trimmed.isEmpty ? layout.baseName : trimmed)
                parentIsNew = true
            }
        }

        // A deck inside a deck cannot take decks of its own: everything goes
        // straight into it, whatever the style says.
        placement.canHoldSubdecks = !parent.isSubdeck
        let effective = placement.canHoldSubdecks ? style : .none

        var children: [String: Planned] = [:]
        var topCount = 0
        let existingChildren = parentIsNew ? [] : library.subdecks(of: parent.id)

        for id in noteIDs {
            guard let name = layout.subdeckName(forNote: id, style: effective) else {
                placement.deckOfNote[id] = parent.id
                topCount += 1
                continue
            }

            let key = name.lowercased()
            if children[key] == nil {
                if let existing = existingChildren.first(where: { Self.sameName($0.displayName, name) }) {
                    children[key] = Planned(deck: existing, isNew: false, wordCount: 0)
                } else {
                    children[key] = Planned(
                        deck: Deck(profileID: profileID, name: name, parentID: parent.id),
                        isNew: true,
                        wordCount: 0
                    )
                }
            }
            children[key]?.wordCount += 1
            placement.deckOfNote[id] = children[key]?.deck.id
        }

        placement.top = Planned(deck: parent, isNew: parentIsNew, wordCount: topCount)
        placement.subdecks = children.values.sorted {
            $0.deck.displayName.localizedStandardCompare($1.deck.displayName) == .orderedAscending
        }
        return placement
    }

    private static func sameName(_ first: String, _ second: String) -> Bool {
        first.compare(second, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}
