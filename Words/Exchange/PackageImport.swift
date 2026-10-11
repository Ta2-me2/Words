import Foundation

/// Reading a package into a library.
///
/// Everything arrives under new identifiers. A package is somebody else's
/// library, and giving its words the identifiers they had there would mean an
/// import could overwrite a word already here — including its schedule, which
/// is the one thing in the app that cannot be got back. New identifiers make
/// an import a thing that only ever adds, and make importing the same file
/// twice a thing that adds nothing the second time, because the words are
/// matched by how they are spelled rather than by a number nobody can see.
nonisolated enum PackageImport {

    /// Where one language inside a package should land.
    nonisolated enum Destination: Hashable, Sendable {
        /// Make a language for it.
        case newLanguage
        /// Put its words into a language already here.
        case existing(UUID)
        /// Leave it out.
        case skip
    }

    /// What opening a package would do, worked out before anything is written.
    nonisolated struct Plan: Sendable {
        /// Languages to create.
        var profiles: [LanguageProfile] = []
        /// Decks to create. Decks already here under the same name are reused
        /// rather than repeated, so a second import does not make "A1 2".
        var decks: [Deck] = []
        var entries: [Entry] = []
        var reviews: [ReviewRecord] = []

        /// Where each file in the package should be written: its path inside
        /// the package, against the name it takes in this library.
        var media: [String: String] = [:]

        /// Words left out because the language already has them.
        var duplicates: Int = 0

        var wordCount: Int { entries.count }
        var isEmpty: Bool { entries.isEmpty && decks.isEmpty && profiles.isEmpty }
    }

    /// The language in this library a package's language belongs in, if there
    /// is an obvious one: the same pair of languages, which is what makes two
    /// profiles the same profile.
    static func suggestedDestination(
        for profile: LanguageProfile,
        in library: Library
    ) -> Destination {
        let match = library.profiles.first {
            $0.learningCode == profile.learningCode && $0.nativeCode == profile.nativeCode
        }
        return match.map { .existing($0.id) } ?? .newLanguage
    }

    /// Works out everything an import would add.
    ///
    /// - Parameters:
    ///   - destinations: what to do with each language in the package, by its
    ///     identifier there. A language not named is left out.
    ///   - mediaInPackage: the files the package actually holds, so that a word
    ///     pointing at a photograph that was not packed arrives without one
    ///     rather than with a broken link.
    static func plan(
        _ manifest: PackageManifest,
        into library: Library,
        destinations: [UUID: Destination],
        mediaInPackage: Set<String>,
        newID: () -> UUID = UUID.init
    ) -> Plan {
        var plan = Plan()

        /// Which profile each package language ends up in.
        var profileFor: [UUID: UUID] = [:]
        for packaged in manifest.profiles {
            switch destinations[packaged.id] ?? .skip {
            case .skip:
                continue
            case .existing(let id):
                guard library.profile(id: id) != nil else { continue }
                profileFor[packaged.id] = id
            case .newLanguage:
                var made = packaged
                made.id = newID()
                made.voiceIdentifier = nil
                plan.profiles.append(made)
                profileFor[packaged.id] = made.id
            }
        }
        guard !profileFor.isEmpty else { return plan }

        // The words each destination already has, so that a package handed to
        // somebody who has half of it already adds the other half.
        var taken: [UUID: Set<String>] = [:]
        for destination in Set(profileFor.values) {
            taken[destination] = Set(library.entries(in: destination).map { key($0.term) })
        }

        // Decks, parents first, so a subdeck can find the deck it sits in.
        var deckFor: [UUID: UUID] = [:]
        for packaged in ordered(manifest.decks) {
            guard let destination = profileFor[packaged.profileID] else { continue }
            let parent = packaged.parentID.flatMap { deckFor[$0] }

            // A deck of that name already in that place is that deck.
            let existing = library.decks(in: destination).first {
                $0.parentID == parent && $0.name.caseInsensitiveCompare(packaged.name) == .orderedSame
            } ?? plan.decks.first {
                $0.profileID == destination && $0.parentID == parent
                    && $0.name.caseInsensitiveCompare(packaged.name) == .orderedSame
            }

            if let existing {
                deckFor[packaged.id] = existing.id
                continue
            }

            var made = packaged
            made.id = newID()
            made.profileID = destination
            made.parentID = parent
            plan.decks.append(made)
            deckFor[packaged.id] = made.id
        }

        // Words, and the files they own.
        var mediaFor: [String: String] = [:]
        var cardFor: [UUID: UUID] = [:]
        var entryFor: [UUID: UUID] = [:]

        for packaged in manifest.entries {
            guard let destination = profileFor[packaged.profileID] else { continue }
            let identity = key(packaged.term)
            guard !identity.isEmpty else { continue }
            if taken[destination, default: []].contains(identity) {
                plan.duplicates += 1
                continue
            }
            taken[destination, default: []].insert(identity)

            var made = packaged
            made.id = newID()
            made.profileID = destination
            made.deckID = packaged.deckID.flatMap { deckFor[$0] }
            made.cards = packaged.cards.map { card in
                var copy = card
                copy.id = newID()
                cardFor[card.id] = copy.id
                return copy
            }

            // A file keeps one new name however many words point at it.
            made.audio = rename(packaged.audio, in: mediaInPackage, using: &mediaFor, newID: newID)
            made.exampleAudio = rename(packaged.exampleAudio, in: mediaInPackage, using: &mediaFor, newID: newID)
            made.picture = rename(packaged.picture, in: mediaInPackage, using: &mediaFor, newID: newID)
            made.association = rename(packaged.association, in: mediaInPackage, using: &mediaFor, newID: newID)

            entryFor[packaged.id] = made.id
            plan.entries.append(made)
        }

        plan.media = mediaFor

        for review in manifest.reviews {
            guard let entryID = entryFor[review.entryID],
                  let cardID = cardFor[review.cardID],
                  let profileID = profileFor[review.profileID]
            else { continue }
            var made = review
            made.id = newID()
            made.profileID = profileID
            made.entryID = entryID
            made.cardID = cardID
            plan.reviews.append(made)
        }

        return plan
    }

    // MARK: - Working out

    /// Decks with the ones they sit inside before them, so that a parent is
    /// always resolved by the time its child is read. A deck whose parent is
    /// missing from the package becomes a deck at the top.
    private static func ordered(_ decks: [Deck]) -> [Deck] {
        let here = Set(decks.map(\.id))
        let tops = decks.filter { $0.parentID == nil || !here.contains($0.parentID!) }
        let rest = decks.filter { deck in !tops.contains { $0.id == deck.id } }
        return tops + rest
    }

    private static func rename(
        _ clip: AudioClip?,
        in packaged: Set<String>,
        using map: inout [String: String],
        newID: () -> UUID
    ) -> AudioClip? {
        guard var clip, let file = renamed(clip.file, in: packaged, using: &map, newID: newID) else { return nil }
        clip.file = file
        return clip
    }

    private static func rename(
        _ picture: Picture?,
        in packaged: Set<String>,
        using map: inout [String: String],
        newID: () -> UUID
    ) -> Picture? {
        guard var picture, let file = renamed(picture.file, in: packaged, using: &map, newID: newID) else { return nil }
        picture.file = file
        return picture
    }

    private static func rename(
        _ association: Association?,
        in packaged: Set<String>,
        using map: inout [String: String],
        newID: () -> UUID
    ) -> Association? {
        guard var association, let file = renamed(association.file, in: packaged, using: &map, newID: newID) else { return nil }
        association.file = file
        return association
    }

    /// The name a packed file takes here, or `nil` if it was not packed.
    private static func renamed(
        _ path: String,
        in packaged: Set<String>,
        using map: inout [String: String],
        newID: () -> UUID
    ) -> String? {
        guard packaged.contains(path) else { return nil }
        if let already = map[path] { return already }
        let suffix = (path as NSString).pathExtension
        let name = suffix.isEmpty ? newID().uuidString : "\(newID().uuidString).\(suffix)"
        let made = "\(LibraryLocation.mediaFolder)/\(name)"
        map[path] = made
        return made
    }

    /// Words are the same word whatever the case and whatever the accents did
    /// on the way through somebody else's keyboard.
    private static func key(_ term: String) -> String {
        term.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
