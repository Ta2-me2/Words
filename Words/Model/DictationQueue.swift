import Foundation

/// What today asks for, and the order it is asked in.
///
/// The same shape as the rest of the app's day: everything that has come round
/// again, plus a few never heard before, and then it says so and stops. A game
/// with no end is a game nobody finishes.
nonisolated struct DictationQueue: Sendable {

    /// Still to be answered, in order.
    private(set) var pending: [DictationItem] = []

    /// Of the queue as it was built — what is a repeat and what is new.
    private(set) var dueCount = 0
    private(set) var newCount = 0

    /// Answered in this sitting. A phrase sent round again counts once.
    private(set) var answered: Set<String> = []

    /// How far along: a phrase re-queued for being wrong is still one phrase.
    var total: Int { dueCount + newCount }
    var done: Int { answered.count }
    var current: DictationItem? { pending.first }
    var isFinished: Bool { pending.isEmpty }

    /// How many places later a phrase that fell apart comes back.
    ///
    /// Far enough that it is recalled rather than echoed, near enough that it
    /// is still the same sitting. At the end of a short queue it simply goes
    /// last.
    static let returnAfter = 4

    init() {}

    /// Builds the day.
    ///
    /// - Parameters:
    ///   - items: everything the chosen sources come to, already built from
    ///     the library.
    ///   - allowance: how many never-heard phrases are still owed today.
    init(
        items: [DictationItem],
        records: [String: DictationRecord],
        allowance: Int,
        now: Date = .now,
        shuffle: Bool = true
    ) {
        var due: [(DictationItem, Date)] = []
        var fresh: [DictationItem] = []

        for item in items {
            guard let record = records[item.key], record.attempts > 0 else {
                fresh.append(item)
                continue
            }
            // No due date on something already answered means it was sent back
            // to the beginning; it is wanted now.
            let when = record.scheduling.dueDate ?? .distantPast
            if when <= now { due.append((item, when)) }
        }

        // The longest overdue first: a phrase waiting a fortnight is the one
        // closest to being lost.
        let reviews = due.sorted { $0.1 < $1.1 }.map(\.0)
        let starters = Array((shuffle ? fresh.shuffled() : fresh).prefix(max(0, allowance)))

        dueCount = reviews.count
        newCount = starters.count
        pending = reviews + starters
    }

    /// Takes the answer to the phrase in front and moves on.
    ///
    /// Returns whether this was the first time the phrase was answered today,
    /// which is what the day's count is made of.
    @discardableResult
    mutating func finish(_ grade: ReviewGrade) -> Bool {
        guard !pending.isEmpty else { return false }
        let item = pending.removeFirst()
        let first = answered.insert(item.key).inserted

        // Wrong means wrong until it is right: it comes round again before the
        // sitting is over, and does not count as done a second time.
        if grade == .again {
            let place = min(Self.returnAfter, pending.count)
            pending.insert(item, at: place)
        }
        return first
    }

    /// Drops the phrase in front without answering it — for a sentence deleted
    /// mid-sitting, or one skipped.
    mutating func skip() {
        guard !pending.isEmpty else { return }
        pending.removeFirst()
    }
}

/// Turning a library and a set of choices into things to type.
nonisolated enum DictationMaterial {

    /// Everything the chosen sources come to.
    ///
    /// Built fresh each time rather than stored: a word edited, re-translated
    /// or deleted has to change the game at once, and progress is kept against
    /// the key rather than against a copy of the text.
    static func items(
        for profile: LanguageProfile,
        in library: Library,
        settings: DictationSettings,
        sentences: [DictationSentence]
    ) -> [DictationItem] {
        var items: [DictationItem] = []

        let scope = settings.deckID.flatMap { library.scope(forDeck: $0) }
        let entries = library.entries(in: profile.id).filter { entry in
            guard let scope else { return true }
            return scope.contains(entry)
        }

        if settings.sources.contains(.word) {
            for entry in entries {
                let said = entry.displayTerm(in: profile)
                guard !DictationText.words(of: said).isEmpty else { continue }
                items.append(DictationItem(
                    key: DictationItem.key(.word, entry.id),
                    text: said,
                    meaning: entry.meaning,
                    source: .word,
                    entryID: entry.id
                ))
            }
        }

        if settings.sources.contains(.example) {
            for entry in entries {
                let sentence = entry.example.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !sentence.isEmpty, !DictationText.words(of: sentence).isEmpty else { continue }
                items.append(DictationItem(
                    key: DictationItem.key(.example, entry.id),
                    text: sentence,
                    meaning: entry.exampleTranslation,
                    source: .example,
                    entryID: entry.id
                ))
            }
        }

        if settings.sources.contains(.written) {
            for sentence in sentences {
                let text = sentence.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty, !DictationText.words(of: text).isEmpty else { continue }
                items.append(DictationItem(
                    key: DictationItem.key(.written, sentence.id),
                    text: text,
                    meaning: sentence.meaning,
                    source: .written,
                    entryID: nil
                ))
            }
        }

        return items
    }

    /// What tomorrow will ask for, if nothing is answered before then.
    ///
    /// The same promise the Home screen makes about cards: a day's work is
    /// easier to turn up for when yesterday said how big it would be.
    static func tomorrow(
        items: [DictationItem],
        records: [String: DictationRecord],
        settings: DictationSettings,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> (reviews: Int, new: Int) {
        guard let start = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
              let end = calendar.date(byAdding: .day, value: 1, to: start)
        else { return (0, 0) }

        var reviews = 0
        var untouched = 0
        for item in items {
            guard let record = records[item.key], record.attempts > 0 else {
                untouched += 1
                continue
            }
            guard let due = record.scheduling.dueDate else { continue }
            // Everything already waiting is waiting tomorrow as well.
            if due < end { reviews += 1 }
        }
        return (reviews, min(settings.dailyNew, untouched))
    }

    /// How many of today's new phrases are still owed.
    static func allowance(_ settings: DictationSettings, done: DictationDay) -> Int {
        max(0, settings.dailyNew - done.newDone)
    }

    /// The words of a deck or language that have no example yet — what the
    /// companion is pointed at.
    static func wordsWithoutExamples(
        for profile: LanguageProfile,
        in library: Library,
        deckID: UUID?
    ) -> [Entry] {
        let scope = deckID.flatMap { library.scope(forDeck: $0) }
        return library.entries(in: profile.id)
            .filter { entry in
                guard entry.example.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
                guard let scope else { return true }
                return scope.contains(entry)
            }
            .sorted { $0.createdAt < $1.createdAt }
    }
}
