import Foundation

/// Bringing a library written by an older algorithm up to date.
///
/// It lives here rather than in the model because it is knowledge about one
/// particular scheduler, and the model is not supposed to have any. All it does
/// is fill in what a card knows about itself; no due date, stage or interval is
/// touched, so a learner who opens the app on the morning of the change finds
/// exactly the work they were expecting.
nonisolated enum ScheduleMigration {

    /// Replays each card's own history through the new arithmetic.
    ///
    /// The conversion from the old ease factor, which happens as each card is
    /// read, is a reasonable guess made from one number. This is better: it is
    /// what actually happened, answer by answer. Cards with no history keep the
    /// guess.
    static func replayHistory(
        into entries: inout [Entry],
        reviews: [ReviewRecord],
        scheduler: FSRSScheduler = FSRSScheduler()
    ) {
        var byCard: [UUID: [FSRSScheduler.ReplayedAnswer]] = [:]
        for record in reviews where !record.isPractice {
            byCard[record.cardID, default: []].append(
                FSRSScheduler.ReplayedAnswer(grade: record.grade, at: record.reviewedAt, stage: record.stageBefore)
            )
        }
        guard !byCard.isEmpty else { return }

        for entry in entries.indices {
            for card in entries[entry].cards.indices {
                guard let answers = byCard[entries[entry].cards[card].id],
                      let memory = scheduler.memory(replaying: answers)
                else { continue }
                entries[entry].cards[card].scheduling.stability = memory.stability
                entries[entry].cards[card].scheduling.difficulty = memory.difficulty
            }
        }
    }
}
