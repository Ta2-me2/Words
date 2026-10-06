import Foundation

/// Everything the app knows, in one value: the languages being learned, the
/// words in them, and every answer ever given.
///
/// One document rather than three, because the three are only ever read and
/// written together, and a vocabulary that can lose its history in a crash is
/// not worth the folder it sits in.
nonisolated struct Library: Codable, Sendable {

    /// Stamped into the file so a future version can recognise an old one.
    ///
    /// 2 — words whose article had been typed into the word itself ("das Brot")
    /// became a word and a gender, which is what the app can now do something
    /// with.
    ///
    /// 3 — the ease factor of the old algorithm became a stability and a
    /// difficulty. Converted card by card as the file is read, without moving a
    /// due date; see `SchedulingState.init(from:)`.
    static let currentFormatVersion = 3

    var formatVersion: Int
    var libraryID: UUID
    var createdAt: Date

    var profiles: [LanguageProfile]
    var decks: [Deck]
    var entries: [Entry]

    /// Append-only. Nothing in the app rewrites a review that happened.
    var reviews: [ReviewRecord]

    /// Sittings that were stopped rather than finished, at most one per scope,
    /// and only ever from today.
    var sessions: [StudySnapshot]

    /// Today's "I want more", at most one per language, and never older than
    /// today.
    var extras: [DailyExtra]

    /// The days the learner froze their streak, one date each. The only part
    /// of a streak that is stored: see `Streak`.
    var streakFreezes: [Date]

    init() {
        formatVersion = Self.currentFormatVersion
        libraryID = UUID()
        createdAt = .now
        profiles = []
        decks = []
        entries = []
        reviews = []
        sessions = []
        extras = []
        streakFreezes = []
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        libraryID = try container.decodeIfPresent(UUID.self, forKey: .libraryID) ?? UUID()
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        profiles = try container.decodeIfPresent([LanguageProfile].self, forKey: .profiles) ?? []
        decks = try container.decodeIfPresent([Deck].self, forKey: .decks) ?? []
        entries = try container.decodeIfPresent([Entry].self, forKey: .entries) ?? []
        reviews = try container.decodeIfPresent([ReviewRecord].self, forKey: .reviews) ?? []
        sessions = try container.decodeIfPresent([StudySnapshot].self, forKey: .sessions) ?? []
        extras = try container.decodeIfPresent([DailyExtra].self, forKey: .extras) ?? []
        streakFreezes = try container.decodeIfPresent([Date].self, forKey: .streakFreezes) ?? []

        // A word whose language is gone can never be shown or studied. Its
        // reviews stay: they are a record of study that did happen.
        let known = Set(profiles.map(\.id))
        decks.removeAll { !known.contains($0.profileID) }
        entries.removeAll { !known.contains($0.profileID) }
        sessions.removeAll { !known.contains($0.profileID) }
        extras.removeAll { !known.contains($0.profileID) }

        // Two levels, no loops, and never a deck inside another language's.
        decks = Self.normalised(decks)

        // A word filed under a deck that is no longer there is not lost, it is
        // simply unfiled.
        let shelves = Set(decks.map(\.id))
        for index in entries.indices where entries[index].deckID.map({ !shelves.contains($0) }) == true {
            entries[index].deckID = nil
        }

        if formatVersion < 2 {
            // Before genders existed, a German learner had nowhere to put one
            // but the word itself. Those words are lifted into a word and a
            // gender, which reads exactly the same on screen and can now be
            // asked about.
            let languages = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.learningCode) })
            for index in entries.indices where entries[index].gender == nil {
                guard let code = languages[entries[index].profileID] else { continue }
                let (bare, gender) = LanguageGenders.split(term: entries[index].term, language: code)
                guard let gender else { continue }
                entries[index].term = bare
                entries[index].gender = gender
            }
        }

        if formatVersion < 3 {
            // Everything this library has ever been told about a word, put
            // through the arithmetic that will schedule it from now on. Only
            // what a card knows about itself changes; what it is waiting for
            // does not.
            ScheduleMigration.replayHistory(into: &entries, reviews: reviews)
        }

        formatVersion = Self.currentFormatVersion
    }

    // MARK: - Reading

    var isEmpty: Bool { profiles.isEmpty }

    func profile(id: UUID?) -> LanguageProfile? {
        guard let id else { return nil }
        return profiles.first { $0.id == id }
    }

    func entry(id: UUID) -> Entry? {
        entries.first { $0.id == id }
    }

    /// A profile's words, newest first — the order in which they were added is
    /// the order the learner remembers adding them in. `deckID` narrows it to
    /// one deck and the decks inside it; `nil` is the whole language.
    func entries(in profileID: UUID, deckID: UUID? = nil) -> [Entry] {
        let scope = scope(forDeck: deckID)
        return entries
            .filter { $0.profileID == profileID && (scope?.contains($0) ?? true) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func deck(id: UUID?) -> Deck? {
        guard let id else { return nil }
        return decks.first { $0.id == id }
    }

    /// A language's decks in the order a sidebar shows them: each deck at the
    /// top by name, followed by the decks inside it, also by name.
    ///
    /// One order for every list of decks in the app, so a deck is always found
    /// in the same place — under the deck it belongs to, never alphabetised
    /// away from it.
    func decks(in profileID: UUID) -> [Deck] {
        topLevelDecks(in: profileID).flatMap { [$0] + subdecks(of: $0.id) }
    }

    /// The decks at the top of a language, by name.
    func topLevelDecks(in profileID: UUID) -> [Deck] {
        let present = Set(decks.map(\.id))
        return decks
            // A deck whose parent is not there is shown at the top rather than
            // nowhere; the file is repaired the next time it is read.
            .filter { $0.profileID == profileID && $0.parentID.map(present.contains) != true }
            .sorted(by: Self.byName)
    }

    /// The decks inside one deck, by name.
    func subdecks(of deckID: UUID) -> [Deck] {
        decks
            .filter { $0.parentID == deckID }
            .sorted(by: Self.byName)
    }

    /// A deck and every deck inside it.
    func deckIDs(within deckID: UUID) -> Set<UUID> {
        Set([deckID] + decks.filter { $0.parentID == deckID }.map(\.id))
    }

    /// Where a deck sits, said the way a person would read it: "Germany › A1".
    func path(of deck: Deck) -> String {
        guard let parent = self.deck(id: deck.parentID) else { return deck.displayName }
        return "\(parent.displayName) › \(deck.displayName)"
    }

    /// What studying a deck is drawn from, or `nil` for the whole language.
    func scope(forDeck deckID: UUID?) -> DeckScope? {
        guard let deck = deck(id: deckID) else { return nil }
        return DeckScope(
            deckID: deck.id,
            deckIDs: deckIDs(within: deck.id),
            // A subdeck that sets no limit of its own works to the deck it sits
            // in; only then to the language.
            dailyNewLimit: deck.dailyNewLimit ?? self.deck(id: deck.parentID)?.dailyNewLimit
        )
    }

    /// Whether a deck may be put inside another.
    ///
    /// Only inside a deck at the top, only within its own language, never
    /// inside itself — and a deck that already has decks inside it stays at
    /// the top, or they would become a third level.
    func canNest(_ deckID: UUID?, inside parentID: UUID) -> Bool {
        guard let parent = deck(id: parentID), parent.parentID == nil else { return false }
        guard let deckID else { return true }
        guard deckID != parentID, let deck = deck(id: deckID) else { return false }
        return deck.profileID == parent.profileID && subdecks(of: deckID).isEmpty
    }

    /// Every word in a deck, counting the decks inside it.
    func wordCount(inDeck deckID: UUID) -> Int {
        let ids = deckIDs(within: deckID)
        return entries.count { $0.deckID.map(ids.contains) == true }
    }

    private static func byName(_ first: Deck, _ second: Deck) -> Bool {
        first.displayName.localizedStandardCompare(second.displayName) == .orderedAscending
    }

    /// Repairs a list of decks so that it is a tree two levels deep.
    ///
    /// A link to the deck itself or to a deck in another language is dropped,
    /// and so is a link to a deck that is itself inside another. Each is judged
    /// against the links as they were found, so the repair does not depend on
    /// the order the decks were written in — and a deck that loses its place is
    /// moved to the top, never deleted.
    ///
    /// A link to a deck that is not there is dropped only when the list is
    /// complete, which is when a file is read. While decks are being written
    /// one at a time, a subdeck may simply have arrived before its parent, and
    /// treating that as damage would make the result depend on the order of
    /// two lines of code.
    static func normalised(_ decks: [Deck], keepingMissingParents: Bool = false) -> [Deck] {
        let byID = Dictionary(decks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let linked = decks.map { deck -> Deck in
            var deck = deck
            if let parentID = deck.parentID {
                if let parent = byID[parentID] {
                    if parentID == deck.id || parent.profileID != deck.profileID { deck.parentID = nil }
                } else if !keepingMissingParents {
                    deck.parentID = nil
                }
            }
            return deck
        }

        let found = Dictionary(linked.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return linked.map { deck in
            var deck = deck
            if let parentID = deck.parentID, found[parentID]?.parentID != nil {
                deck.parentID = nil
            }
            return deck
        }
    }

    /// Words in a language that have not been filed under any deck.
    func unfiledCount(in profileID: UUID) -> Int {
        entries.count { $0.profileID == profileID && $0.deckID == nil }
    }

    func counts(for profileID: UUID, deckID: UUID? = nil, asOf date: Date, calendar: Calendar = .current) -> StudyCounts {
        guard let profile = profile(id: profileID) else { return StudyCounts() }
        return StudyQueue.counts(
            profile: profile,
            entries: entries,
            scope: scope(forDeck: deckID),
            extra: extra(for: profileID, asOf: date, calendar: calendar),
            asOf: date,
            calendar: calendar
        )
    }

    func queue(for profileID: UUID, deckID: UUID? = nil, asOf date: Date, calendar: Calendar = .current) -> [QueuedCard] {
        guard let profile = profile(id: profileID) else { return [] }
        return StudyQueue.build(
            profile: profile,
            entries: entries,
            scope: scope(forDeck: deckID),
            extra: extra(for: profileID, asOf: date, calendar: calendar),
            asOf: date,
            calendar: calendar
        )
    }

    /// The cards answered today, for going over again without consequence.
    func practiceQueue(for profileID: UUID, deckID: UUID? = nil, asOf date: Date, calendar: Calendar = .current) -> [QueuedCard] {
        guard let profile = profile(id: profileID) else { return [] }
        return StudyQueue.practiceToday(
            profile: profile,
            entries: entries,
            reviews: reviews,
            scope: scope(forDeck: deckID),
            asOf: date,
            calendar: calendar
        )
    }

    func endlessQueue(for profileID: UUID, deckID: UUID? = nil, pool: StudyQueue.PracticePool) -> [QueuedCard] {
        guard let profile = profile(id: profileID) else { return [] }
        return StudyQueue.endless(profile: profile, entries: entries, scope: scope(forDeck: deckID), pool: pool)
    }

    func nextDueDate(for profileID: UUID, deckID: UUID? = nil, after date: Date) -> Date? {
        guard let profile = profile(id: profileID) else { return nil }
        return StudyQueue.nextDueDate(profile: profile, entries: entries, scope: scope(forDeck: deckID), after: date)
    }

    func reviews(for profileID: UUID) -> [ReviewRecord] {
        reviews.filter { $0.profileID == profileID }
    }

    // MARK: - The streak

    func streak(asOf date: Date, calendar: Calendar = .current) -> StreakStatus {
        Streak.status(reviews: reviews, freezes: streakFreezes, asOf: date, calendar: calendar)
    }

    /// Freezes today, if a freeze has anything to keep and the week has one
    /// left. Asking twice freezes once.
    mutating func freezeStreak(asOf date: Date, calendar: Calendar = .current) {
        guard streak(asOf: date, calendar: calendar).canFreezeToday else { return }
        streakFreezes.append(calendar.startOfDay(for: date))
    }

    /// Takes today's freeze back.
    mutating func unfreezeStreak(asOf date: Date, calendar: Calendar = .current) {
        streakFreezes.removeAll { calendar.isDate($0, inSameDayAs: date) }
    }

    // MARK: - More than today asked for

    func extra(for profileID: UUID, asOf date: Date, calendar: Calendar = .current) -> DailyExtra? {
        extras.first { $0.profileID == profileID && $0.belongs(toDayOf: date, calendar: calendar) }
    }

    /// What "I want more" could still add today in a scope: how many new words
    /// have not been offered yet, and which cards could be brought forward.
    func moreAvailable(
        for profileID: UUID,
        deckID: UUID? = nil,
        asOf date: Date,
        calendar: Calendar = .current
    ) -> (newWords: Int, reviews: [QueuedCard]) {
        guard let profile = profile(id: profileID) else { return (0, []) }
        let scope = scope(forDeck: deckID)
        let extra = extra(for: profileID, asOf: date, calendar: calendar)

        let unstarted = entries
            .filter { StudyQueue.belongs($0, to: profile, scope: scope) }
            .flatMap(\.cards)
            .count { $0.scheduling.stage == .new }
        let offered = StudyQueue.counts(profile: profile, entries: entries, scope: scope, extra: extra, asOf: date, calendar: calendar).new

        let reviews = StudyQueue.moreReviews(profile: profile, entries: entries, scope: scope, extra: extra, asOf: date, calendar: calendar)
        return (max(0, unstarted - offered), reviews)
    }

    /// Whether "I want more" has anything to offer in a scope right now: the
    /// day's cards are done, nothing is waiting half-finished, and there is
    /// something left to add. Checked in that order, so a busy day never pays
    /// for working out what "more" would be.
    func canStudyMore(for profileID: UUID, deckID: UUID? = nil, asOf date: Date, calendar: Calendar = .current) -> Bool {
        guard counts(for: profileID, deckID: deckID, asOf: date, calendar: calendar).total == 0,
              snapshot(profileID: profileID, deckID: deckID, asOf: date, calendar: calendar) == nil
        else { return false }
        let more = moreAvailable(for: profileID, deckID: deckID, asOf: date, calendar: calendar)
        return more.newWords > 0 || !more.reviews.isEmpty
    }

    /// Adds to today's extra for a language, starting one if there is none,
    /// and throws away every extra that is no longer today's.
    mutating func addExtra(
        profileID: UUID,
        newWords: Int,
        reviews: [QueuedCard],
        asOf date: Date,
        calendar: Calendar = .current
    ) {
        var extra = extra(for: profileID, asOf: date, calendar: calendar)
            ?? DailyExtra(profileID: profileID, day: calendar.startOfDay(for: date))
        extra.newWords += max(0, newWords)
        let already = Set(extra.reviews.map(\.cardID))
        extra.reviews += reviews.filter { !already.contains($0.cardID) }

        extras.removeAll { $0.profileID == profileID || !$0.belongs(toDayOf: date, calendar: calendar) }
        extras.append(extra)
    }

    // MARK: - Sittings left unfinished

    /// The sitting a scope would come back to, if it was left today.
    func snapshot(
        profileID: UUID,
        deckID: UUID? = nil,
        mode: StudyMode = .scheduled,
        asOf date: Date,
        calendar: Calendar = .current
    ) -> StudySnapshot? {
        sessions.first {
            $0.matches(profileID: profileID, deckID: deckID, mode: mode)
                && $0.belongs(toDayOf: date, calendar: calendar)
        }
    }

    /// Keeps one sitting per scope, and throws away everything that is no
    /// longer today's. Yesterday's leftovers are not lost by this: they are
    /// cards, and cards come back on their own.
    mutating func upsert(_ snapshot: StudySnapshot, calendar: Calendar = .current) {
        sessions.removeAll {
            $0.matches(profileID: snapshot.profileID, deckID: snapshot.deckID, mode: snapshot.mode)
                || !$0.belongs(toDayOf: snapshot.day, calendar: calendar)
        }
        sessions.append(snapshot)
    }

    mutating func removeSnapshot(profileID: UUID, deckID: UUID?, mode: StudyMode) {
        sessions.removeAll { $0.matches(profileID: profileID, deckID: deckID, mode: mode) }
    }

    // MARK: - Languages

    mutating func upsert(_ profile: LanguageProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
    }

    /// Removes a language, its decks and its words. The review history is kept:
    /// it is what happened, and the statistics have a right to it.
    mutating func removeProfile(id: UUID) {
        profiles.removeAll { $0.id == id }
        decks.removeAll { $0.profileID == id }
        entries.removeAll { $0.profileID == id }
        sessions.removeAll { $0.profileID == id }
        extras.removeAll { $0.profileID == id }
    }

    // MARK: - Decks

    /// Adds a deck or replaces it. The tree is repaired afterwards, so nothing
    /// written through here can leave a third level or a loop behind — the
    /// editor offers only places a deck can go, and this is the backstop.
    mutating func upsert(_ deck: Deck) {
        if let index = decks.firstIndex(where: { $0.id == deck.id }) {
            decks[index] = deck
        } else {
            decks.append(deck)
        }
        decks = Self.normalised(decks, keepingMissingParents: true)
    }

    /// Removes a deck, and the decks inside it.
    ///
    /// A shelf is not a box: taking the shelf away must not take the books with
    /// it, or renaming a mistake would cost the learner a hundred words. The
    /// words go one level up. Taking "A1" out of "Germany" leaves its words in
    /// "Germany", which is where they were all along; taking "Germany" away
    /// leaves every word that was in it — "A1" and "A2" included — in the
    /// language, unfiled.
    mutating func removeDeck(id: UUID) {
        guard let deck = deck(id: id) else { return }
        let removed = deckIDs(within: id)

        decks.removeAll { removed.contains($0.id) }
        sessions.removeAll { $0.deckID.map(removed.contains) == true }
        for index in entries.indices where entries[index].deckID.map(removed.contains) == true {
            entries[index].deckID = deck.parentID
        }
    }

    mutating func move(entries ids: Set<UUID>, toDeck deckID: UUID?) {
        for index in entries.indices where ids.contains(entries[index].id) {
            entries[index].deckID = deckID
        }
    }

    // MARK: - Words

    mutating func upsert(_ entry: Entry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
    }

    /// Applies an edit to a word without disturbing its schedule.
    mutating func editEntry(
        id: UUID,
        term: String,
        meaning: String,
        gender: Gender?,
        transcription: String = "",
        example: String,
        exampleTranslation: String,
        note: String,
        at date: Date = .now
    ) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].term = term
        entries[index].meaning = meaning
        entries[index].gender = gender
        entries[index].transcription = transcription
        entries[index].example = example
        entries[index].exampleTranslation = exampleTranslation
        entries[index].note = note
        entries[index].updatedAt = date
    }

    /// Whether a language already has a word, however it was capitalised.
    func containsTerm(_ term: String, in profileID: UUID) -> Bool {
        let key = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return entries.contains { $0.profileID == profileID && $0.term.lowercased() == key }
    }

    /// Puts words back to never having been studied.
    ///
    /// The history stays — it is a record of study that happened, and the
    /// statistics have a right to it — but the cards start again from nothing.
    /// It is the answer to a word whose record says more about an afternoon of
    /// fumbling with the app than about the word, and to a word that has been
    /// forgotten so often that the card itself needs rewriting.
    mutating func forget(entries ids: Set<UUID>) {
        for index in entries.indices where ids.contains(entries[index].id) {
            for card in entries[index].cards.indices {
                entries[index].cards[card].scheduling = SchedulingState()
            }
        }
    }

    mutating func removeEntries(ids: Set<UUID>) {
        entries.removeAll { ids.contains($0.id) }
    }

    /// The words filed in a deck or in any deck inside it.
    func entryIDs(inDeck deckID: UUID) -> Set<UUID> {
        let decks = deckIDs(within: deckID)
        return Set(entries.lazy.filter { $0.deckID.map(decks.contains) == true }.map(\.id))
    }

    /// Removes a deck, the decks inside it, and every word filed in any of them.
    ///
    /// The other half of `removeDeck`. A deck made by hand is a shelf, and its
    /// words outlive it; a deck that arrived as a package — a hundred and sixty
    /// verbs with their recordings and photos — is the words, and leaving them
    /// behind unfiled means a second clean-up the learner never asked for. The
    /// learner chooses which one they meant. The review history stays either
    /// way: it is a record of study that happened.
    mutating func removeDeckAndWords(id: UUID) {
        let words = entryIDs(inDeck: id)
        removeEntries(ids: words)
        removeDeck(id: id)
    }

    /// Records an answer that changes nothing.
    ///
    /// Practice moves no schedule and starts no new word. It is written down
    /// all the same, marked for what it is, because the time was spent.
    mutating func recordPractice(
        entryID: UUID,
        cardID: UUID,
        grade: ReviewGrade,
        at date: Date,
        seconds: Double? = nil
    ) {
        guard let entry = entry(id: entryID), let card = entry.card(id: cardID) else { return }

        reviews.append(
            ReviewRecord(
                profileID: entry.profileID,
                entryID: entryID,
                cardID: cardID,
                reviewedAt: date,
                grade: grade,
                stageBefore: card.scheduling.stage,
                stageAfter: card.scheduling.stage,
                intervalBeforeDays: card.scheduling.intervalDays,
                intervalAfterDays: card.scheduling.intervalDays,
                dueAfter: card.scheduling.dueDate,
                seconds: seconds,
                isPractice: true
            )
        )
    }

    // MARK: - Answering

    /// Applies an answer: the scheduler decides the new state, the card takes
    /// it, and the history gets a line it never loses.
    ///
    /// The whole learning loop is this one method, which is why it lives in the
    /// model where it can be tested without a window.
    @discardableResult
    mutating func recordReview(
        entryID: UUID,
        cardID: UUID,
        grade: ReviewGrade,
        at date: Date,
        using scheduler: any ReviewScheduler,
        retention: Double = Retention.standard,
        seconds: Double? = nil
    ) -> SchedulingState? {
        guard let entryIndex = entries.firstIndex(where: { $0.id == entryID }),
              let cardIndex = entries[entryIndex].cards.firstIndex(where: { $0.id == cardID })
        else { return nil }

        let before = entries[entryIndex].cards[cardIndex].scheduling
        let after = scheduler.nextState(for: before, grade: grade, at: date, retention: retention)
        entries[entryIndex].cards[cardIndex].scheduling = after

        reviews.append(
            ReviewRecord(
                profileID: entries[entryIndex].profileID,
                entryID: entryID,
                cardID: cardID,
                reviewedAt: date,
                grade: grade,
                stageBefore: before.stage,
                stageAfter: after.stage,
                intervalBeforeDays: before.intervalDays,
                intervalAfterDays: after.intervalDays,
                dueAfter: after.dueDate,
                seconds: seconds
            )
        )

        return after
    }
}
