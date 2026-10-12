import Foundation

/// A sentence the learner wrote into the game rather than into the library.
///
/// Sentences the companion makes are not kept here: those are written onto the
/// word they were made for, as its example, where they also do their work on
/// the card during an ordinary sitting. These are the ones that belong to
/// nobody — a line from a song, something heard at work — and the game is the
/// only place for them.
nonisolated struct DictationSentence: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var text: String
    var meaning: String
    var createdAt: Date

    init(id: UUID = UUID(), text: String, meaning: String = "", createdAt: Date = .now) {
        self.id = id
        self.text = text
        self.meaning = meaning
        self.createdAt = createdAt
    }
}

/// What the game plays, and how much of it in a day.
nonisolated struct DictationSettings: Codable, Hashable, Sendable {

    /// Which kinds of thing go in. Empty would be a game with nothing to play,
    /// so it is never allowed to be.
    var sources: Set<DictationSource>

    /// The deck the words are drawn from, or `nil` for the whole language.
    var deckID: UUID?

    /// How many phrases never heard before to start in a day.
    var dailyNew: Int

    var hint: DictationHint

    init(
        sources: Set<DictationSource> = [.word, .example, .written],
        deckID: UUID? = nil,
        dailyNew: Int = 10,
        hint: DictationHint = .firstLetter
    ) {
        self.sources = sources.isEmpty ? [.word] : sources
        self.deckID = deckID
        self.dailyNew = max(1, dailyNew)
        self.hint = hint
    }
}

/// What the game remembers about one exercise.
///
/// The schedule is the app's own `SchedulingState`, moved by the same FSRS the
/// rest of the app uses — but kept here, in the game's own file. A game is
/// practice: however well a phrase is typed, no card's due date moves.
nonisolated struct DictationRecord: Codable, Hashable, Sendable {
    var scheduling = SchedulingState()
    var attempts = 0
    /// Answers with nothing wrong in them at all.
    var perfect = 0
    var wordsWanted = 0
    var wordsRight = 0
    var lastSeenAt: Date?

    /// Of every word ever asked of this phrase, how many came back.
    var accuracy: Double {
        wordsWanted == 0 ? 0 : Double(wordsRight) / Double(wordsWanted)
    }
}

/// One day's work, for the goal and for the statistics.
nonisolated struct DictationDay: Codable, Hashable, Sendable {
    var newDone = 0
    var reviewsDone = 0
    var exercises = 0
    var wordsWanted = 0
    var wordsRight = 0
    var seconds: Double = 0

    var accuracy: Double {
        wordsWanted == 0 ? 0 : Double(wordsRight) / Double(wordsWanted)
    }
}

/// Everything the game keeps for one language.
nonisolated struct DictationProgress: Codable, Sendable {

    static let currentVersion = 1

    var formatVersion = currentVersion
    var settings = DictationSettings()
    var sentences: [DictationSentence] = []
    /// By `DictationItem.key`.
    var records: [String: DictationRecord] = [:]
    /// By day, as `yyyy-MM-dd`, so a file can be read by a person.
    var days: [String: DictationDay] = [:]

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decodeIfPresent(Int.self, forKey: .formatVersion) ?? Self.currentVersion
        settings = try container.decodeIfPresent(DictationSettings.self, forKey: .settings) ?? DictationSettings()
        sentences = try container.decodeIfPresent([DictationSentence].self, forKey: .sentences) ?? []
        records = try container.decodeIfPresent([String: DictationRecord].self, forKey: .records) ?? [:]
        days = try container.decodeIfPresent([String: DictationDay].self, forKey: .days) ?? [:]
    }

    // MARK: - Days

    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    func day(on date: Date, calendar: Calendar = .current) -> DictationDay {
        days[Self.day(date, calendar: calendar)] ?? DictationDay()
    }

    /// Days worked, most recent first — what the statistics are drawn from.
    func recentDays(before date: Date, count: Int, calendar: Calendar = .current) -> [(day: String, work: DictationDay)] {
        (0 ..< count).compactMap { back in
            guard let when = calendar.date(byAdding: .day, value: -back, to: date) else { return nil }
            let key = Self.day(when, calendar: calendar)
            guard let work = days[key] else { return nil }
            return (key, work)
        }
    }

    /// Days in a row up to today with at least one exercise in them. Today not
    /// having started yet does not break it — the day is not over.
    func streak(on date: Date, calendar: Calendar = .current) -> Int {
        var count = 0
        var back = 0
        while back < 400 {
            guard let when = calendar.date(byAdding: .day, value: -back, to: date) else { break }
            let worked = (days[Self.day(when, calendar: calendar)]?.exercises ?? 0) > 0
            if worked {
                count += 1
            } else if back > 0 {
                break
            }
            back += 1
        }
        return count
    }

    /// A year of days, in the shape the activity calendar draws.
    ///
    /// Counted in phrases rather than in answers, which is what the rest of
    /// the game counts: the busiest day sets the darkest square, so a learner
    /// is measured against themselves.
    func activity(days count: Int, asOf date: Date, calendar: Calendar = .current) -> [ActivityDay] {
        let today = calendar.startOfDay(for: date)
        guard count > 0, let first = calendar.date(byAdding: .day, value: -(count - 1), to: today) else { return [] }

        let busiest = days.values.map(\.exercises).max() ?? 0
        return (0 ..< count).compactMap { offset in
            guard let when = calendar.date(byAdding: .day, value: offset, to: first) else { return nil }
            let done = days[Self.day(when, calendar: calendar)]?.exercises ?? 0
            return ActivityDay(date: when, count: done, level: Insights.level(done, busiest: busiest))
        }
    }

    // MARK: - Totals

    /// Phrases that have been answered at least once.
    var started: Int { records.count { $0.value.attempts > 0 } }

    /// Phrases whose interval has passed three weeks — the same line the rest
    /// of the app draws between "in review" and "known well".
    var known: Int { records.count { $0.value.scheduling.intervalDays >= 21 } }

    var lifetimeAccuracy: Double {
        let wanted = records.values.reduce(0) { $0 + $1.wordsWanted }
        let right = records.values.reduce(0) { $0 + $1.wordsRight }
        return wanted == 0 ? 0 : Double(right) / Double(wanted)
    }
}
