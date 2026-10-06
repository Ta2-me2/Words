import Foundation

/// The memory model the schedule is built on: the Free Spaced Repetition
/// Scheduler, as published by the open-spaced-repetition project and shipped
/// with Anki.
///
/// Two numbers describe what the learner knows about one card. **Stability** is
/// how many days may pass before the chance of recalling it falls to nine in
/// ten. **Difficulty**, between 1 and 10, is how stubbornly that stability
/// refuses to grow. Every answer moves both, and the next interval is read
/// straight off the forgetting curve — which is why two words learned on the
/// same afternoon can end up months apart, and why no ladder of fixed intervals
/// appears anywhere in this file.
///
/// The formulas are written out here rather than taken from a package. The
/// scheduling half of FSRS is this one page of arithmetic, it is stable across
/// versions, and every line of it is checked. What is *not* here is the
/// optimiser, which fits the weights to one person's history; until that exists
/// the published defaults are used, which is what FSRS itself recommends for
/// the first several hundred reviews. When it does exist, only `weights` has to
/// change.
nonisolated struct FSRS: Hashable, Sendable {

    /// FSRS-6's default weights. Twenty-one numbers fitted against a very large
    /// body of review history; they are meant to be optimised per learner, not
    /// edited by hand.
    static let defaultWeights: [Double] = [
        0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001,
        1.8722, 0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014,
        1.8729, 0.5425, 0.0912, 0.0658, 0.1542,
    ]

    var weights: [Double] = defaultWeights

    /// A memory is never worth exactly nothing, and never worth a thousand
    /// years. The floor matters more than it looks: several of the formulas
    /// raise stability to a negative power, and a stability of nought would
    /// make the next interval infinite — a word answered badly four times in a
    /// minute would be filed away for ever.
    static let minimumStability = 0.01
    static let maximumStability = 36_500.0

    init(weights: [Double] = defaultWeights) {
        self.weights = weights.count == Self.defaultWeights.count ? weights : Self.defaultWeights
    }

    private func w(_ index: Int) -> Double { weights[index] }

    /// How sharply the forgetting curve bends, and the constant that makes it
    /// pass through nine-in-ten at exactly one stability.
    private var decay: Double { -w(20) }
    private var factor: Double { pow(0.9, 1 / decay) - 1 }

    // MARK: - The curve

    /// The chance the card is still known, `days` after it was last seen.
    func retrievability(afterDays days: Double, stability: Double) -> Double {
        pow(1 + factor * max(0, days) / max(stability, 0.001), decay)
    }

    /// The wait after which recall falls to `retention`. At the default nine in
    /// ten this is the stability itself — that is what stability means.
    func interval(stability: Double, retention: Double) -> Double {
        stability / factor * (pow(retention, 1 / decay) - 1)
    }

    /// The stability that makes a given wait come out at `retention` — the
    /// curve read the other way, for a memory that is declared rather than
    /// measured.
    func stability(forInterval days: Double, retention: Double) -> Double {
        bounded(days * factor / (pow(retention, 1 / decay) - 1))
    }

    // MARK: - A word met for the first time

    func initialStability(_ grade: ReviewGrade) -> Double {
        bounded(w(rating(grade) - 1))
    }

    func initialDifficulty(_ grade: ReviewGrade) -> Double {
        clamped(w(4) - exp(w(5) * Double(rating(grade) - 1)) + 1)
    }

    // MARK: - What an answer does

    /// Difficulty drifts towards what an Easy first answer would have meant, so
    /// that one bad morning does not mark a word as hard for ever.
    func nextDifficulty(_ difficulty: Double, _ grade: ReviewGrade) -> Double {
        let delta = -w(6) * Double(rating(grade) - 3)
        let damped = difficulty + delta * (10 - difficulty) / 9
        return clamped(w(7) * initialDifficulty(.easy) + (1 - w(7)) * damped)
    }

    /// Stability after a word came back. The longer it had already been waiting
    /// and the less likely recall was, the more the memory gains from it.
    func recallStability(
        difficulty: Double,
        stability: Double,
        retrievability: Double,
        grade: ReviewGrade
    ) -> Double {
        let hardPenalty = grade == .hard ? w(15) : 1
        let easyBonus = grade == .easy ? w(16) : 1
        let growth = exp(w(8))
            * (11 - difficulty)
            * pow(stability, -w(9))
            * (exp((1 - retrievability) * w(10)) - 1)
            * hardPenalty
            * easyBonus
        return bounded(stability * (1 + growth))
    }

    /// Stability after a word was forgotten. Never more than it was: a lapse
    /// cannot leave a memory stronger than it found it.
    func forgetStability(difficulty: Double, stability: Double, retrievability: Double) -> Double {
        let ceiling = stability / exp(w(17) * w(18))
        let value = w(11)
            * pow(difficulty, -w(12))
            * (pow(stability + 1, w(13)) - 1)
            * exp((1 - retrievability) * w(14))
        return bounded(min(value, ceiling))
    }

    /// Stability after an answer given minutes rather than days after the last
    /// one — the learning steps. Seeing a word again the same afternoon is
    /// worth something, but much less than seeing it again next week.
    func shortTermStability(_ stability: Double, _ grade: ReviewGrade) -> Double {
        var increase = exp(w(17) * (Double(rating(grade)) - 3 + w(18))) * pow(stability, -w(19))
        if rating(grade) >= 3 { increase = max(increase, 1) }
        return bounded(stability * increase)
    }

    // MARK: - Reading an older library

    /// What a card scheduled by the previous algorithm was worth in these two
    /// numbers.
    ///
    /// The interval a word had reached *is* a measurement of its stability, and
    /// the ease factor is invertible into a difficulty. Nothing is guessed and
    /// no due date moves: a library carries on from where it stood.
    func converted(intervalDays: Double, ease: Double) -> (stability: Double, difficulty: Double) {
        let stability = bounded(intervalDays)
        let denominator = exp(w(8)) * pow(stability, -w(9)) * (exp(0.1 * w(10)) - 1)
        let difficulty = clamped(11 - (ease - 1) / denominator)
        return (stability, difficulty)
    }

    // MARK: - Bookkeeping

    /// FSRS counts the answers from one, in the order they appear on screen.
    private func rating(_ grade: ReviewGrade) -> Int {
        switch grade {
        case .again: 1
        case .hard: 2
        case .good: 3
        case .easy: 4
        }
    }

    private func clamped(_ difficulty: Double) -> Double {
        min(max(difficulty.rounded(places: 2), 1), 10)
    }

    private func bounded(_ stability: Double) -> Double {
        guard stability.isFinite else { return Self.maximumStability }
        return min(max(stability.rounded(places: 2), Self.minimumStability), Self.maximumStability)
    }
}

fileprivate extension Double {

    /// FSRS keeps its two numbers to two decimals, so that the same history
    /// always produces the same schedule.
    nonisolated func rounded(places: Int) -> Double {
        // Written out: inside an extension of Double, a bare `pow` finds the
        // static one that MLX's numerics bring in with it.
        let scale = Foundation.pow(10.0, Double(places))
        return (self * scale).rounded() / scale
    }
}
