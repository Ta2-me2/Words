import Foundation

/// One day of the activity calendar.
nonisolated struct ActivityDay: Identifiable, Hashable, Sendable {
    var date: Date
    var count: Int

    /// 0 for a day with nothing on it, then 1 to 4 from a quiet day to the
    /// learner's own busiest. Relative, not absolute: twenty reviews is a big
    /// day for one person and a warm-up for another.
    var level: Int

    var id: Date { date }
}

/// What a day asks for.
nonisolated struct DailyPlan: Hashable, Sendable {
    var reviews: Int
    var newWords: Int

    var total: Int { reviews + newWords }
    var isEmpty: Bool { total == 0 }
}

/// A word that keeps being forgotten.
nonisolated struct DifficultWord: Identifiable, Hashable, Sendable {
    var entry: Entry
    var lapses: Int

    /// What the scheduler now thinks of it, from 1 to 10.
    var difficulty: Double

    /// Forgotten so often that the card itself, rather than the schedule, is
    /// the thing to change.
    var needsAttention: Bool

    var id: UUID { entry.id }
}

/// One column of the forecast.
nonisolated struct ForecastDay: Identifiable, Hashable, Sendable {
    var date: Date
    var count: Int

    var id: Date { date }
}

/// How many of each answer were given.
nonisolated struct GradeCount: Identifiable, Hashable, Sendable {
    var grade: ReviewGrade
    var count: Int

    var id: String { grade.rawValue }
}

/// Where a language stands.
nonisolated struct ProfileSummary: Hashable, Sendable {
    var words = 0
    var newWords = 0
    var learning = 0

    /// Cards out of learning and on an interval.
    var known = 0

    /// Cards whose interval has passed three weeks — the usual line between
    /// "answered correctly lately" and "remembered".
    var mature = 0

    var reviews = 0
    var reviewsToday = 0
    var lapses = 0

    /// The share of answers that were not "Again". `nil` while there is nothing
    /// to be accurate about — a percentage of no answers is not zero.
    var accuracy: Double?

    /// Reviews a day over the last month, counting the days with none.
    var averagePerDay: Double = 0
}

/// One language in the across-languages summary.
nonisolated struct LanguageTotals: Identifiable, Hashable, Sendable {
    var profile: LanguageProfile
    var words: Int
    var known: Int
    var due: Int
    var reviewsThisWeek: Int

    var id: UUID { profile.id }
}

/// Everything the home and statistics screens say about the learner, worked out
/// from the words and the review history alone.
///
/// Pure functions over the model: no view builds a statistic for itself, and
/// every number on screen can be checked without a window.
nonisolated enum Insights {

    // MARK: - Activity

    /// A day-by-day count of answers, ending today.
    static func activity(
        reviews: [ReviewRecord],
        profileID: UUID?,
        days: Int,
        asOf date: Date,
        calendar: Calendar = .current
    ) -> [ActivityDay] {
        let today = calendar.startOfDay(for: date)
        guard days > 0, let first = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }

        var counts: [Date: Int] = [:]
        for record in reviews where !record.isPractice && (profileID == nil || record.profileID == profileID) {
            let day = calendar.startOfDay(for: record.reviewedAt)
            guard day >= first, day <= today else { continue }
            counts[day, default: 0] += 1
        }

        let busiest = counts.values.max() ?? 0

        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: first) else { return nil }
            let count = counts[day] ?? 0
            return ActivityDay(date: day, count: count, level: level(count, busiest: busiest))
        }
    }

    static func level(_ count: Int, busiest: Int) -> Int {
        guard count > 0 else { return 0 }
        guard busiest > 0 else { return 1 }
        let share = Double(count) / Double(busiest)
        return min(4, max(1, Int((share * 4).rounded(.up))))
    }

    // MARK: - The plan

    /// What is waiting now.
    static func today(
        profile: LanguageProfile,
        entries: [Entry],
        asOf date: Date,
        calendar: Calendar = .current
    ) -> DailyPlan {
        let counts = StudyQueue.counts(profile: profile, entries: entries, asOf: date, calendar: calendar)
        return DailyPlan(reviews: counts.due, newWords: counts.new)
    }

    /// What tomorrow will ask for if today is finished.
    ///
    /// Only cards actually scheduled for tomorrow are counted — carrying
    /// today's leftovers into tomorrow's figure would quietly punish the
    /// learner twice for the same afternoon.
    static func tomorrow(
        profile: LanguageProfile,
        entries: [Entry],
        asOf date: Date,
        calendar: Calendar = .current
    ) -> DailyPlan {
        let start = calendar.startOfDay(for: date)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: start),
              let dayAfter = calendar.date(byAdding: .day, value: 1, to: tomorrow)
        else { return DailyPlan(reviews: 0, newWords: 0) }

        var reviews = 0
        var unseen = 0

        for entry in entries where entry.profileID == profile.id {
            for card in entry.cards {
                if card.scheduling.stage == .new {
                    unseen += 1
                } else if let due = card.scheduling.dueDate, due >= tomorrow, due < dayAfter {
                    reviews += 1
                }
            }
        }

        let startedToday = today(profile: profile, entries: entries, asOf: date, calendar: calendar).newWords
        let left = max(0, unseen - startedToday)
        // A day's review limit holds tomorrow to it too: promising three hundred
        // reviews to someone who has said fifty is enough would be untrue.
        let asked = profile.dailyReviewLimit.map { min(reviews, $0) } ?? reviews
        return DailyPlan(reviews: asked, newWords: min(left, profile.dailyNewLimit))
    }

    // MARK: - Difficult words

    /// The words that keep going. Sorted by how often they have been forgotten,
    /// then by how hard the scheduler now thinks they are.
    static func difficult(
        entries: [Entry],
        profileID: UUID,
        limit: Int = 5
    ) -> [DifficultWord] {
        entries
            .filter { $0.profileID == profileID }
            .compactMap { entry -> DifficultWord? in
                // A word speaks with its worst card.
                guard let worst = entry.cards.max(by: {
                    ($0.scheduling.lapses, $0.scheduling.difficulty) < ($1.scheduling.lapses, $1.scheduling.difficulty)
                }), worst.scheduling.lapses > 0 else { return nil }
                return DifficultWord(
                    entry: entry,
                    lapses: worst.scheduling.lapses,
                    difficulty: worst.scheduling.difficulty,
                    needsAttention: worst.scheduling.needsAttention
                )
            }
            .sorted {
                if $0.lapses != $1.lapses { return $0.lapses > $1.lapses }
                if $0.difficulty != $1.difficulty { return $0.difficulty > $1.difficulty }
                return $0.entry.term.localizedStandardCompare($1.entry.term) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Where a language stands

    static func summary(
        entries: [Entry],
        reviews: [ReviewRecord],
        profileID: UUID,
        asOf date: Date,
        calendar: Calendar = .current
    ) -> ProfileSummary {
        var summary = ProfileSummary()

        for entry in entries where entry.profileID == profileID {
            summary.words += 1
            for card in entry.cards {
                switch card.scheduling.stage {
                case .new: summary.newWords += 1
                case .learning, .relearning: summary.learning += 1
                case .review:
                    summary.known += 1
                    if card.scheduling.intervalDays >= 21 { summary.mature += 1 }
                }
            }
        }

        let mine = reviews.filter { $0.profileID == profileID && !$0.isPractice }
        summary.reviews = mine.count
        summary.reviewsToday = mine.count { calendar.isDate($0.reviewedAt, inSameDayAs: date) }
        summary.lapses = mine.count { $0.grade == .again }

        if !mine.isEmpty {
            summary.accuracy = 1 - Double(summary.lapses) / Double(mine.count)
        }

        let window = 30
        if let first = calendar.date(byAdding: .day, value: -(window - 1), to: calendar.startOfDay(for: date)) {
            let recent = mine.count { $0.reviewedAt >= first }
            summary.averagePerDay = Double(recent) / Double(window)
        }

        return summary
    }

    // MARK: - What is coming

    /// How many cards fall due on each of the next days. Anything already
    /// overdue is counted on the first day, which is where it will be met.
    static func forecast(
        entries: [Entry],
        profileID: UUID,
        days: Int,
        asOf date: Date,
        calendar: Calendar = .current
    ) -> [ForecastDay] {
        let today = calendar.startOfDay(for: date)
        guard days > 0 else { return [] }

        var counts: [Date: Int] = [:]
        guard let last = calendar.date(byAdding: .day, value: days - 1, to: today) else { return [] }

        for entry in entries where entry.profileID == profileID {
            for card in entry.cards {
                guard card.scheduling.stage != .new, let due = card.scheduling.dueDate else { continue }
                let day = max(calendar.startOfDay(for: due), today)
                guard day <= last else { continue }
                counts[day, default: 0] += 1
            }
        }

        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return ForecastDay(date: day, count: counts[day] ?? 0)
        }
    }

    static func grades(
        reviews: [ReviewRecord],
        profileID: UUID,
        since: Date? = nil
    ) -> [GradeCount] {
        let mine = reviews.filter {
            $0.profileID == profileID && !$0.isPractice && (since == nil || $0.reviewedAt >= since!)
        }
        return ReviewGrade.allCases.map { grade in
            GradeCount(grade: grade, count: mine.count { $0.grade == grade })
        }
    }

    // MARK: - Across languages

    static func totals(
        profiles: [LanguageProfile],
        entries: [Entry],
        reviews: [ReviewRecord],
        extras: [DailyExtra] = [],
        asOf date: Date,
        calendar: Calendar = .current
    ) -> [LanguageTotals] {
        let weekStart = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: date))

        return profiles.map { profile in
            // With today's extra, so that this row and the Today block above it
            // never disagree about what is waiting.
            let counts = StudyQueue.counts(
                profile: profile,
                entries: entries,
                extra: extras.first { $0.profileID == profile.id },
                asOf: date,
                calendar: calendar
            )
            let known = entries
                .filter { $0.profileID == profile.id }
                .flatMap(\.cards)
                .count { $0.scheduling.stage == .review }
            let week = reviews.count {
                $0.profileID == profile.id && !$0.isPractice
                    && (weekStart == nil || $0.reviewedAt >= weekStart!)
            }
            return LanguageTotals(
                profile: profile,
                words: counts.words,
                known: known,
                due: counts.total,
                reviewsThisWeek: week
            )
        }
    }

    /// How many languages the learner has actually studied in. The
    /// across-languages card is only worth the space it takes when there is
    /// more than one answer in it.
    static func studiedLanguageCount(profiles: [LanguageProfile], reviews: [ReviewRecord]) -> Int {
        let studied = Set(reviews.filter { !$0.isPractice }.map(\.profileID))
        return profiles.count { studied.contains($0.id) }
    }
}
