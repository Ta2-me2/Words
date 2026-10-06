import Foundation

/// A sitting that was left before it ended.
///
/// Closing the window half-way through a review is stopping, not finishing, and
/// the app must not treat the two the same. The cards that were left are still
/// today's, in the order they were in, under the same count — so they are
/// written down after every answer and handed back when the sitting is opened
/// again.
///
/// A snapshot belongs to one day. Come back tomorrow and it is gone; not
/// because the work was forgiven, but because those cards are due again by
/// then, which is the schedule's job rather than this one's. That is also why
/// nothing is ever skipped: an unfinished card is either still due or still
/// new, and both come back on their own.
nonisolated struct StudySnapshot: Codable, Hashable, Sendable {

    var profileID: UUID

    /// The deck being studied, or `nil` for the whole language. A deck's
    /// sitting and the language's sitting are different sittings.
    var deckID: UUID?

    var mode: StudyMode

    /// The start of the day the sitting belongs to.
    var day: Date

    var remaining: [QueuedCard]

    /// Cards done for the day, kept as a list because a set is not a document.
    var finished: [UUID]

    var plannedCount: Int
    var answerCount: Int
    var updatedAt: Date

    /// Whether this is the sitting a given scope would come back to.
    func matches(profileID: UUID, deckID: UUID?, mode: StudyMode) -> Bool {
        self.profileID == profileID && self.deckID == deckID && self.mode == mode
    }

    func belongs(toDayOf date: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(day, inSameDayAs: date)
    }
}
