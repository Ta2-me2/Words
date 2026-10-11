import Foundation

/// One thing that can be ticked for export.
///
/// Decks are ticked one by one rather than as a tree, because a subdeck is a
/// real choice: a learner who wants to hand somebody "A1" should not have to
/// hand them the whole of "Germany" to do it.
nonisolated enum ExportNode: Hashable, Sendable {
    case deck(UUID)
    /// The words of a language that are in no deck. They are a real part of a
    /// library and would otherwise be the one thing an export could not carry.
    case unfiled(UUID)
}

/// What a learner has asked to take with them.
nonisolated struct ExportSelection: Hashable, Sendable {

    var nodes: Set<ExportNode> = []

    /// Whether to carry the files a word owns, each kind on its own: somebody
    /// sharing a deck often wants the words and the pictures but not three
    /// hundred megabytes of their own voice.
    var includesPhotos = true
    var includesRecordings = true
    var includesDrawings = true

    /// Whether to carry the schedule and the answers behind it.
    ///
    /// Off by default, because the common case is handing somebody a deck, and
    /// a deck that arrives already half-learned by somebody else is a deck with
    /// a wrong schedule. On, it is a backup of one's own work.
    var includesProgress = false

    var isEmpty: Bool { nodes.isEmpty }

    func contains(_ node: ExportNode) -> Bool { nodes.contains(node) }

    mutating func set(_ node: ExportNode, to wanted: Bool) {
        if wanted { nodes.insert(node) } else { nodes.remove(node) }
    }

    mutating func set(_ many: [ExportNode], to wanted: Bool) {
        for node in many { set(node, to: wanted) }
    }
}

/// Everything an export would do, worked out before a single byte is written.
///
/// Separate from the writing so that the screen can show what is about to
/// happen — how many words, how many files, how large — and so that the rules
/// about which deck carries which word can be checked without a disk.
nonisolated struct ExportPlan: Sendable {

    var profiles: [LanguageProfile] = []
    var decks: [Deck] = []
    var entries: [Entry] = []
    var reviews: [ReviewRecord] = []

    /// The files to pack, by their path inside the library.
    var mediaFiles: [String] = []

    /// What the files add up to, where the sizes were available.
    var mediaBytes: Int64 = 0

    /// Whether the learner asked for their schedule to come along. Carried
    /// rather than read off the cards: a deck nobody has answered yet has no
    /// schedule to show either way, and the package has to say which it is.
    var includesProgress = false

    var isEmpty: Bool { entries.isEmpty && decks.isEmpty }

    var wordCount: Int { entries.count }

    /// Works out what the selection comes to.
    ///
    /// - Parameter sizeOfMedia: how large a file is, asked of the caller so
    ///   that this stays a function of the library alone.
    static func make(
        from library: Library,
        selection: ExportSelection,
        sizeOfMedia: (String) -> Int64 = { _ in 0 }
    ) -> ExportPlan {
        var plan = ExportPlan()
        plan.includesProgress = selection.includesProgress
        guard !selection.isEmpty else { return plan }

        let chosenDecks = Set(selection.nodes.compactMap { node -> UUID? in
            if case .deck(let id) = node { return id }
            return nil
        })
        let chosenUnfiled = Set(selection.nodes.compactMap { node -> UUID? in
            if case .unfiled(let id) = node { return id }
            return nil
        })

        // A deck keeps the deck above it only when that one is coming too.
        // Exporting "A1" on its own should hand over "A1", not an empty
        // "Germany" with "A1" hidden inside it.
        plan.decks = library.decks
            .filter { chosenDecks.contains($0.id) }
            .map { deck in
                var copy = deck
                if let parent = copy.parentID, !chosenDecks.contains(parent) { copy.parentID = nil }
                return copy
            }
            .sorted { $0.createdAt < $1.createdAt }

        let wanted = library.entries.filter { entry in
            if let deckID = entry.deckID { return chosenDecks.contains(deckID) }
            return chosenUnfiled.contains(entry.profileID)
        }

        plan.entries = wanted
            .map { strip($0, with: selection) }
            .sorted { $0.createdAt < $1.createdAt }

        let profileIDs = Set(plan.decks.map(\.profileID))
            .union(plan.entries.map(\.profileID))
            .union(chosenUnfiled)
        plan.profiles = library.profiles
            .filter { profileIDs.contains($0.id) }
            .map { profile in
                var copy = profile
                // A voice is a fact about a Mac, not about a language: an
                // identifier from this one would point at nothing on another,
                // and "best available" is the right answer everywhere.
                copy.voiceIdentifier = nil
                return copy
            }

        if selection.includesProgress {
            let entryIDs = Set(plan.entries.map(\.id))
            plan.reviews = library.reviews
                .filter { entryIDs.contains($0.entryID) }
                .sorted { $0.reviewedAt < $1.reviewedAt }
        }

        // Each file once, however many words point at it: two words sharing a
        // recording must not pack it twice.
        var seen: Set<String> = []
        for file in plan.entries.flatMap(\.mediaFiles) where seen.insert(file).inserted {
            plan.mediaFiles.append(file)
            plan.mediaBytes += sizeOfMedia(file)
        }

        return plan
    }

    /// A word with whatever the learner left behind taken off it.
    ///
    /// The schedule goes with the progress: a word arriving without its history
    /// must arrive as a word nobody has answered, or its owner's dates would be
    /// somebody else's homework.
    private static func strip(_ entry: Entry, with selection: ExportSelection) -> Entry {
        var copy = entry
        if !selection.includesPhotos { copy.picture = nil }
        if !selection.includesRecordings {
            copy.audio = nil
            copy.exampleAudio = nil
        }
        if !selection.includesDrawings { copy.association = nil }
        if !selection.includesProgress {
            copy.cards = copy.cards.map { Card(id: $0.id, direction: $0.direction) }
        }
        return copy
    }
}
