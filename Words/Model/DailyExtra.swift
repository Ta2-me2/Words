import Foundation

/// More than the day was going to ask for, because the learner asked for it.
///
/// "I want more" is for the afternoon when today's cards are done and there is
/// still appetite. It changes today and nothing else — the settings stay where
/// they were, and tomorrow is an ordinary day — which is why it is kept here,
/// stamped with its day, rather than written into the language's limits.
///
/// New words are a number: today's allowance grows by it, wherever the day is
/// spent. Reviews are a list of cards, chosen at the moment of asking — first
/// whatever the daily review limit was holding back, then the words that would
/// have come round soonest. A list rather than a number, so that the plan holds
/// still while it is worked through: each card leaves it by being answered.
nonisolated struct DailyExtra: Codable, Hashable, Sendable {

    var profileID: UUID

    /// The start of the day it belongs to.
    var day: Date

    var newWords: Int

    /// Cards brought into today, in the order they are asked.
    var reviews: [QueuedCard]

    init(profileID: UUID, day: Date, newWords: Int = 0, reviews: [QueuedCard] = []) {
        self.profileID = profileID
        self.day = day
        self.newWords = max(0, newWords)
        self.reviews = reviews
    }

    func belongs(toDayOf date: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(day, inSameDayAs: date)
    }
}
