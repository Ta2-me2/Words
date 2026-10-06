import Foundation

/// A card waiting in a session, named by the two identifiers needed to find it
/// again. The word itself is looked up when it is shown, so editing a word
/// mid-session shows the edit.
nonisolated struct QueuedCard: Identifiable, Hashable, Codable, Sendable {
    var entryID: UUID
    var cardID: UUID

    var id: UUID { cardID }
}

/// What a profile — or one deck in it — has waiting today.
nonisolated struct StudyCounts: Hashable, Sendable {

    /// Cards that were learned before and are ready to be asked again.
    var due: Int = 0

    /// Words never seen, as many as today's allowance still permits.
    var new: Int = 0

    /// Every word in scope, studied or not.
    var words: Int = 0

    var total: Int { due + new }
    var isEmpty: Bool { total == 0 }
}

/// Which cards to ask for, and in what order.
///
/// Kept apart from both the scheduler and the interface: the scheduler decides
/// when a card is ready, this decides what a sitting is made of, and the
/// session view only walks the list it is handed.
///
/// Every entry point takes an optional scope. `nil` means the whole language,
/// which is what the Library shows by default; a scope narrows the sitting to
/// one deck and the decks inside it.
///
/// The daily allowance of new words applies to whatever is being studied: a
/// deck spends its own, counted against its own limit. That is the point of
/// studying a deck at all — a learner working through "Serials" should get
/// their twenty words from it whether or not another deck was studied this
/// morning — and it is why the language-wide figure can be nought while a deck
/// still has words to start.
nonisolated enum StudyQueue {

    /// Everything ready now, hardest-pressed first: cards part-way through
    /// learning, then reviews that have come round, then new words.
    static func build(
        profile: LanguageProfile,
        entries: [Entry],
        scope: DeckScope? = nil,
        extra: DailyExtra? = nil,
        asOf date: Date,
        calendar: Calendar = .current
    ) -> [QueuedCard] {
        let extra = todays(extra, for: profile, asOf: date, calendar: calendar)

        var fresh: [(card: QueuedCard, added: Date, draw: UInt64)] = []
        let day = dayNumber(of: date, calendar: calendar)
        for entry in entries where belongs(entry, to: profile, scope: scope) {
            for card in entry.cards where card.scheduling.stage == .new {
                fresh.append((
                    QueuedCard(entryID: entry.id, cardID: card.id),
                    entry.createdAt,
                    shuffled(card.scheduling.spread, day: day)
                ))
            }
        }

        let allowance = newAllowance(profile: profile, entries: entries, scope: scope, extra: extra, asOf: date, calendar: calendar)

        let ordered: [QueuedCard]
        switch profile.newWordOrder {
        case .added:
            ordered = fresh.sorted { $0.added < $1.added }.map(\.card)
        case .random:
            ordered = fresh.sorted { $0.draw < $1.draw }.map(\.card)
        }

        return reviews(profile: profile, entries: entries, scope: scope, extra: extra, asOf: date, calendar: calendar)
            + ordered.prefix(allowance)
    }

    /// A card's place in a random order of new words, for one day.
    ///
    /// Drawn from the number every card already carries rather than from a
    /// generator, so that the order holds for the whole day — a sitting stopped
    /// and begun again goes on with the same words rather than pulling a new
    /// handful out of the hat — and changes with the next one.
    private static func shuffled(_ spread: UInt64, day: Int) -> UInt64 {
        var value = spread ^ (UInt64(bitPattern: Int64(day)) &* 0x9E37_79B9_7F4A_7C15)
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    private static func dayNumber(of date: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: date)
        return Int((start.timeIntervalSinceReferenceDate / 86_400).rounded())
    }

    static func counts(
        profile: LanguageProfile,
        entries: [Entry],
        scope: DeckScope? = nil,
        extra: DailyExtra? = nil,
        asOf date: Date,
        calendar: Calendar = .current
    ) -> StudyCounts {
        let extra = todays(extra, for: profile, asOf: date, calendar: calendar)
        var counts = StudyCounts()
        var newCards = 0

        for entry in entries where belongs(entry, to: profile, scope: scope) {
            counts.words += 1
            newCards += entry.cards.count { $0.scheduling.stage == .new }
        }

        // The same function that builds the sitting, so that the number on the
        // button is always the number of cards behind it. Once limits and extras
        // are involved, which cards make the cut depends on their order, and a
        // count worked out separately would sooner or later disagree.
        counts.due = reviews(profile: profile, entries: entries, scope: scope, extra: extra, asOf: date, calendar: calendar).count
        counts.new = min(newCards, newAllowance(profile: profile, entries: entries, scope: scope, extra: extra, asOf: date, calendar: calendar))
        return counts
    }

    /// The cards already learned that today asks for, in the order it asks.
    ///
    /// A card part-way through learning *today* — met this morning, or
    /// forgotten an hour ago — always continues: it is work already begun, and
    /// a limit that stopped it half-way would leave a word half-learned. Only
    /// cards coming in from earlier days spend the review limit, earliest
    /// first, so that what is held back is what can best afford to wait.
    private static func reviews(
        profile: LanguageProfile,
        entries: [Entry],
        scope: DeckScope?,
        extra: DailyExtra?,
        asOf date: Date,
        calendar: Calendar
    ) -> [QueuedCard] {
        var learning: [(card: QueuedCard, due: Date, begun: Bool)] = []
        var review: [(card: QueuedCard, due: Date)] = []

        for entry in entries where belongs(entry, to: profile, scope: scope) {
            for card in entry.cards {
                let state = card.scheduling
                guard state.stage != .new, state.isDue(onDayOf: date, calendar: calendar) else { continue }
                let queued = QueuedCard(entryID: entry.id, cardID: card.id)

                switch state.stage {
                case .learning, .relearning:
                    learning.append((queued, state.dueDate ?? date, state.wasAnswered(on: date, calendar: calendar)))
                case .review:
                    review.append((queued, state.dueDate ?? date))
                case .new:
                    continue
                }
            }
        }

        var budget = reviewAllowance(profile: profile, entries: entries, asOf: date, calendar: calendar)
        var planned: [QueuedCard] = []

        for item in learning.sorted(by: { $0.due < $1.due }) {
            if !item.begun, let left = budget {
                guard left > 0 else { continue }
                budget = left - 1
            }
            planned.append(item.card)
        }

        for item in review.sorted(by: { $0.due < $1.due }) {
            if let left = budget {
                guard left > 0 else { break }
                budget = left - 1
            }
            planned.append(item.card)
        }

        // What "I want more" brought in, for as long as it is still waiting.
        if let extra, !extra.reviews.isEmpty {
            var included = Set(planned.map(\.cardID))
            let byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            for queued in extra.reviews where !included.contains(queued.cardID) {
                guard let entry = byID[queued.entryID],
                      belongs(entry, to: profile, scope: scope),
                      let card = entry.card(id: queued.cardID),
                      card.scheduling.stage != .new,
                      !card.scheduling.wasAnswered(on: date, calendar: calendar)
                else { continue }
                planned.append(queued)
                included.insert(queued.cardID)
            }
        }

        return planned
    }

    /// When the next card comes round, for the days there is nothing to do.
    ///
    /// Answering "nothing due — next on Thursday" is the difference between an
    /// empty screen and a finished one.
    static func nextDueDate(
        profile: LanguageProfile,
        entries: [Entry],
        scope: DeckScope? = nil,
        after date: Date
    ) -> Date? {
        entries
            .filter { belongs($0, to: profile, scope: scope) }
            .flatMap(\.cards)
            .compactMap { card -> Date? in
                guard card.scheduling.stage != .new, let due = card.scheduling.dueDate, due > date else { return nil }
                return due
            }
            .min()
    }

    /// How many new words may still start today in what is being studied.
    ///
    /// Counted from the cards themselves — a card knows the day it was first
    /// answered — rather than from a tally that a crash could leave wrong.
    /// Today's extra, if the learner asked for one, is added to whatever
    /// allowance is being worked out: ten more is ten more wherever the day is
    /// spent.
    static func newAllowance(
        profile: LanguageProfile,
        entries: [Entry],
        scope: DeckScope? = nil,
        extra: DailyExtra? = nil,
        asOf date: Date,
        calendar: Calendar = .current
    ) -> Int {
        let extra = todays(extra, for: profile, asOf: date, calendar: calendar)
        let limit = (scope?.dailyNewLimit ?? profile.dailyNewLimit) + (extra?.newWords ?? 0)
        guard limit > 0 else { return 0 }

        let introduced = entries
            .filter { belongs($0, to: profile, scope: scope) }
            .flatMap(\.cards)
            .count { $0.scheduling.wasIntroduced(on: date, calendar: calendar) }

        return max(0, limit - introduced)
    }

    /// How many cards from earlier days may still be taken on today, or `nil`
    /// when the language sets no limit.
    ///
    /// Counted across the whole language rather than per deck. New words are a
    /// shelf's business — twenty from "Serials" — but reviews are the cost of
    /// everything already learned, and a limit on them is a limit on the
    /// learner's day, whichever deck the day is spent in.
    static func reviewAllowance(
        profile: LanguageProfile,
        entries: [Entry],
        asOf date: Date,
        calendar: Calendar = .current
    ) -> Int? {
        guard let limit = profile.dailyReviewLimit else { return nil }
        let reviewed = entries
            .filter { $0.profileID == profile.id }
            .flatMap(\.cards)
            .count { $0.scheduling.wasReviewed(on: date, calendar: calendar) }
        return max(0, limit - reviewed)
    }

    // MARK: - More than today asked for

    /// The cards "I want more" can bring into today, in the order it brings
    /// them: first whatever the daily limit was holding back, then the words
    /// that would have come round soonest.
    ///
    /// Bringing a word forward is honest here in a way it would not be for
    /// practice: it is a real review, asked for out loud, and FSRS measures
    /// the gap that actually passed — a word answered three days early gains
    /// less from it than one answered on time, which is exactly right.
    static func moreReviews(
        profile: LanguageProfile,
        entries: [Entry],
        scope: DeckScope? = nil,
        extra: DailyExtra? = nil,
        asOf date: Date,
        calendar: Calendar = .current
    ) -> [QueuedCard] {
        let extra = todays(extra, for: profile, asOf: date, calendar: calendar)
        let planned = Set(reviews(profile: profile, entries: entries, scope: scope, extra: extra, asOf: date, calendar: calendar).map(\.cardID))

        var heldBack: [(QueuedCard, Date)] = []
        var ahead: [(QueuedCard, Date)] = []

        for entry in entries where belongs(entry, to: profile, scope: scope) {
            for card in entry.cards {
                let state = card.scheduling
                // A word already answered today is not asked twice in one day:
                // it would teach nothing, and FSRS would learn nothing from it.
                guard state.stage != .new,
                      !planned.contains(card.id),
                      !state.wasAnswered(on: date, calendar: calendar),
                      let due = state.dueDate
                else { continue }

                let queued = QueuedCard(entryID: entry.id, cardID: card.id)
                if state.isDue(onDayOf: date, calendar: calendar) {
                    heldBack.append((queued, due))
                } else {
                    ahead.append((queued, due))
                }
            }
        }

        return heldBack.sorted { $0.1 < $1.1 }.map(\.0) + ahead.sorted { $0.1 < $1.1 }.map(\.0)
    }

    /// An extra only counts on its own day and for its own language; anything
    /// else handed in is ignored rather than trusted.
    private static func todays(
        _ extra: DailyExtra?,
        for profile: LanguageProfile,
        asOf date: Date,
        calendar: Calendar
    ) -> DailyExtra? {
        guard let extra, extra.profileID == profile.id, extra.belongs(toDayOf: date, calendar: calendar) else { return nil }
        return extra
    }

    // MARK: - Practice

    /// The cards answered today, for going over again.
    ///
    /// Practice changes nothing, so this is drawn from the history rather than
    /// from the schedule: it is the work of the day, repeated, not a second
    /// helping of it.
    static func practiceToday(
        profile: LanguageProfile,
        entries: [Entry],
        reviews: [ReviewRecord],
        scope: DeckScope? = nil,
        asOf date: Date,
        calendar: Calendar = .current
    ) -> [QueuedCard] {
        let studied = reviews.filter {
            $0.profileID == profile.id
                && !$0.isPractice
                && calendar.isDate($0.reviewedAt, inSameDayAs: date)
        }

        var seen: Set<UUID> = []
        var queue: [QueuedCard] = []

        for record in studied where !seen.contains(record.cardID) {
            guard let entry = entries.first(where: { $0.id == record.entryID }),
                  belongs(entry, to: profile, scope: scope),
                  entry.card(id: record.cardID) != nil
            else { continue }
            seen.insert(record.cardID)
            queue.append(QueuedCard(entryID: entry.id, cardID: record.cardID))
        }

        return queue.shuffled()
    }

    /// Which words an endless sitting draws on.
    nonisolated enum PracticePool: String, CaseIterable, Identifiable, Codable, Sendable {
        /// Everything, including words never studied.
        case everything
        /// Only words that have been answered at least once.
        case seen

        var id: String { rawValue }

        var title: String {
            switch self {
            case .everything: "All Words"
            case .seen: "Words I've Seen"
            }
        }

        var symbol: String {
            switch self {
            case .everything: "books.vertical"
            case .seen: "eye"
            }
        }
    }

    /// A sitting with no end: whatever is in scope, shuffled.
    static func endless(
        profile: LanguageProfile,
        entries: [Entry],
        scope: DeckScope? = nil,
        pool: PracticePool
    ) -> [QueuedCard] {
        entries
            .filter { belongs($0, to: profile, scope: scope) }
            .flatMap { entry in
                entry.cards.compactMap { card -> QueuedCard? in
                    if pool == .seen, card.scheduling.firstReviewedAt == nil { return nil }
                    return QueuedCard(entryID: entry.id, cardID: card.id)
                }
            }
            .shuffled()
    }

    /// Whether a word is part of what is being studied: the whole language when
    /// there is no scope, and otherwise the deck together with the decks inside
    /// it.
    static func belongs(_ entry: Entry, to profile: LanguageProfile, scope: DeckScope?) -> Bool {
        guard entry.profileID == profile.id else { return false }
        guard let scope else { return true }
        return scope.contains(entry)
    }
}
