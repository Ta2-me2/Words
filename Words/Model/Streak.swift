import Foundation

/// One day of the week shown beside the streak.
nonisolated struct StreakDay: Identifiable, Hashable, Sendable {

    nonisolated enum State: Hashable, Sendable {
        /// Something was studied or practised.
        case studied
        /// Nothing was, and a freeze kept the streak.
        case frozen
        /// Nothing was, and nothing kept it.
        case missed
        /// Today, with nothing done yet.
        case today
        /// Still to come.
        case ahead
    }

    var date: Date
    var state: State

    var id: Date { date }
}

/// Where the streak stands today.
nonisolated struct StreakStatus: Hashable, Sendable {

    /// Days studied in a row, the frozen ones between them kept but not
    /// counted.
    var length: Int

    var studiedToday: Bool
    var frozenToday: Bool

    /// Freezes the current week still has.
    var freezesLeft: Int

    /// The calendar week today is in, first day first.
    var week: [StreakDay]

    /// A freeze keeps a streak; with no streak, or a day that already counts,
    /// there is nothing for one to do.
    var canFreezeToday: Bool {
        length > 0 && !studiedToday && !frozenToday && freezesLeft > 0
    }
}

/// Days in a row, worked out from the history of answers.
///
/// Any answer counts — a review, today's cards again, a single card of endless
/// practice — in any language. A streak is about coming back to the app, and
/// the learner who opened it for one word on a hard day came back.
///
/// Nothing about a streak is stored except the freezes, which are the one part
/// of it that is a decision rather than something that happened. The rest is
/// read from the reviews every time, so it can never disagree with them.
nonisolated enum Streak {

    /// How many days a week may be frozen.
    static let freezesPerWeek = 2

    static func status(
        reviews: [ReviewRecord],
        freezes: [Date],
        asOf date: Date,
        calendar: Calendar = .current
    ) -> StreakStatus {
        let today = calendar.startOfDay(for: date)
        let studied = Set(reviews.map { calendar.startOfDay(for: $0.reviewedAt) })
        let frozen = Set(freezes.map { calendar.startOfDay(for: $0) })

        let studiedToday = studied.contains(today)
        var length = studiedToday ? 1 : 0

        // Back from yesterday until a day that neither counted nor was kept.
        // Today does not end a streak yet: the day is not over.
        if let earliest = (studied.union(frozen)).min() {
            var day = calendar.date(byAdding: .day, value: -1, to: today)
            while let current = day, current >= earliest {
                if studied.contains(current) {
                    length += 1
                } else if !frozen.contains(current) {
                    break
                }
                day = calendar.date(byAdding: .day, value: -1, to: current)
            }
        }

        let week = days(ofWeekContaining: today, calendar: calendar).map { day -> StreakDay in
            let state: StreakDay.State
            if studied.contains(day) {
                state = .studied
            } else if frozen.contains(day) {
                state = .frozen
            } else if day == today {
                state = .today
            } else if day > today {
                state = .ahead
            } else {
                state = .missed
            }
            return StreakDay(date: day, state: state)
        }

        return StreakStatus(
            length: length,
            studiedToday: studiedToday,
            frozenToday: frozen.contains(today) && !studiedToday,
            freezesLeft: freezesLeft(studied: studied, frozen: frozen, weekOf: today, calendar: calendar),
            week: week
        )
    }

    /// A freeze on a day that was studied after all was never needed, and is
    /// given back.
    private static func freezesLeft(
        studied: Set<Date>,
        frozen: Set<Date>,
        weekOf day: Date,
        calendar: Calendar
    ) -> Int {
        let week = Set(days(ofWeekContaining: day, calendar: calendar))
        let used = frozen.count { week.contains($0) && !studied.contains($0) }
        return max(0, freezesPerWeek - used)
    }

    /// The seven days of the calendar week a day is in, as the learner's own
    /// calendar counts weeks — from Monday in most of the world.
    static func days(ofWeekContaining day: Date, calendar: Calendar) -> [Date] {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: day)?.start else { return [day] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
}
