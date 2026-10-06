import Foundation

/// The rule that decides when a card is seen again.
///
/// The whole of the app's spaced repetition sits behind this one method. The
/// interface never computes a date, and never asks how an interval was reached;
/// swapping in a better algorithm later means writing one more conformance.
nonisolated protocol ReviewScheduler: Sendable {

    /// The state a card should have after being answered.
    ///
    /// - Parameter retention: the share of words the learner means to still
    ///   know when they come round. It is a goal rather than an implementation
    ///   detail — how much forgetting is acceptable is the learner's to decide,
    ///   and any scheduler is free to honour it in its own way.
    func nextState(
        for state: SchedulingState,
        grade: ReviewGrade,
        at date: Date,
        retention: Double
    ) -> SchedulingState
}

/// What "remembering well enough" means, when nobody has said otherwise.
nonisolated enum Retention {

    /// Nine words in ten. Higher costs far more reviews for very little more
    /// memory; Anki's own guidance is never to go above 0.97.
    static let standard = 0.90

    static let range: ClosedRange<Double> = 0.80...0.97

    /// A goal outside what the algorithm can honour is brought back inside it
    /// rather than refused: a file is not a form to be validated.
    static func clamped(_ value: Double) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

extension ReviewScheduler {

    /// What each button would do, worked out before the answer is given.
    ///
    /// The session shows these on the buttons — "Good · 3 d" — because a
    /// scheduler the user cannot see is a scheduler the user cannot trust.
    func preview(
        for state: SchedulingState,
        at date: Date,
        retention: Double = Retention.standard
    ) -> [ReviewGrade: TimeInterval] {
        var result: [ReviewGrade: TimeInterval] = [:]
        for grade in ReviewGrade.allCases {
            let next = nextState(for: state, grade: grade, at: date, retention: retention)
            result[grade] = (next.dueDate ?? date).timeIntervalSince(date)
        }
        return result
    }

    /// The everyday call, for the places that have no learner to ask.
    func nextState(for state: SchedulingState, grade: ReviewGrade, at date: Date) -> SchedulingState {
        nextState(for: state, grade: grade, at: date, retention: Retention.standard)
    }
}
