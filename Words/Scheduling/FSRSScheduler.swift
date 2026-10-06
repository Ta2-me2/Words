import Foundation

/// The scheduler the app ships with: short steps for a word being met, and
/// after that a date worked out by `FSRS` from what the card's own history says
/// about it.
///
/// The division of labour is deliberate. `FSRS` knows about memory and nothing
/// else — no stages, no clock, no calendar. This knows about the day: when a
/// word is still being learned, when a forgotten word has been recovered, that
/// intervals are whole days landing at midnight, and that two words in
/// identical health must not come back on the same morning for ever.
///
/// Everything it does is decided by `Configuration`, and everything outside
/// this file knows only the protocol.
nonisolated struct FSRSScheduler: ReviewScheduler {

    nonisolated struct Configuration: Hashable, Sendable {

        /// Delays for a word being met for the first time. Two of them, both
        /// well inside a sitting: seeing a word a third time the same afternoon
        /// buys almost nothing, and the evidence Anki cites says as much.
        var learningSteps: [TimeInterval] = [180, 900]

        /// Delays for a word that was known and was forgotten. One is enough —
        /// a lapsed word is not a new word, it keeps everything FSRS knows
        /// about it, and the work that matters is the review the next day.
        var relearningSteps: [TimeInterval] = [600]

        /// A word that has just been forgotten does not go straight back to a
        /// fortnight, whatever button was pressed to recover it.
        var minimumIntervalAfterRelearning: Double = 1

        /// Long enough that a word genuinely known can be left alone for years.
        var maximumIntervalDays: Double = 36_500

        /// How long a word waits when Easy is its very first answer — "I know
        /// this word". Past the three weeks at which a word counts as known
        /// well: a word a learner already had before they ever added it is not
        /// a word to be asked about again next week.
        var knownWordIntervalDays: Double = 30

        /// Whether intervals are spread by a few percent.
        var spreadsIntervals = true

        var memory = FSRS()

        init() {}
    }

    var configuration = Configuration()

    /// Day intervals land at the start of a day rather than at the hour of the
    /// last review, so a word answered at midnight and a word answered at noon
    /// are both waiting the next morning.
    var calendar: Calendar = .current

    init(configuration: Configuration = Configuration(), calendar: Calendar = .current) {
        self.configuration = configuration
        self.calendar = calendar
    }

    // MARK: - The answer

    func nextState(
        for state: SchedulingState,
        grade: ReviewGrade,
        at date: Date,
        retention: Double
    ) -> SchedulingState {
        var next = state
        next.reviewCount += 1
        next.lastReviewedAt = date
        if next.firstReviewedAt == nil { next.firstReviewedAt = date }

        if state.stage == .new, grade == .easy {
            alreadyKnown(&next, of: state, at: date, retention: retention)
            return next
        }

        let measured = memory(of: state, answered: grade, at: date)
        next.stability = measured.stability
        next.difficulty = measured.difficulty

        switch state.stage {
        case .new, .learning:
            step(&next, of: state, through: configuration.learningSteps, grade: grade, at: date, relearning: false, retention: retention)
        case .relearning:
            step(&next, of: state, through: configuration.relearningSteps, grade: grade, at: date, relearning: true, retention: retention)
        case .review:
            review(&next, of: state, grade: grade, at: date, retention: retention)
        }

        return next
    }

    /// The two numbers a card's own history implies, replayed answer by answer.
    ///
    /// A library that has kept every review since its first day does not have
    /// to guess what it knows about a word: the same arithmetic that will
    /// schedule tomorrow's answer can be run over every answer already given.
    /// It is how a vocabulary crosses from one algorithm to another without
    /// losing what it learned — and it is the reason the history was worth
    /// keeping in the first place.
    func memory(replaying answers: [ReplayedAnswer]) -> (stability: Double, difficulty: Double)? {
        guard !answers.isEmpty else { return nil }

        var state = SchedulingState()
        for answer in answers.sorted(by: { $0.at < $1.at }) {
            state.stage = answer.stage
            let measured = memory(of: state, answered: answer.grade, at: answer.at)
            state.stability = measured.stability
            state.difficulty = measured.difficulty
            state.lastReviewedAt = answer.at
        }
        return (state.stability, state.difficulty)
    }

    /// One line of a card's history: what was pressed, when, and what the card
    /// was at the time.
    nonisolated struct ReplayedAnswer: Hashable, Sendable {
        var grade: ReviewGrade
        var at: Date
        var stage: LearningStage

        init(grade: ReviewGrade, at: Date, stage: LearningStage) {
            self.grade = grade
            self.at = at
            self.stage = stage
        }
    }

    /// What the answer did to the two numbers that describe the memory.
    private func memory(
        of state: SchedulingState,
        answered grade: ReviewGrade,
        at date: Date
    ) -> (stability: Double, difficulty: Double) {
        let fsrs = configuration.memory

        // A word never measured — or a card from a library so old it has no
        // measurement — starts from the answer it was given.
        guard state.stage != .new, state.stability > 0 else {
            return (fsrs.initialStability(grade), fsrs.initialDifficulty(grade))
        }

        let difficulty = fsrs.nextDifficulty(state.difficulty, grade)

        switch state.stage {
        case .new:
            return (fsrs.initialStability(grade), fsrs.initialDifficulty(grade))
        case .learning, .relearning:
            return (fsrs.shortTermStability(state.stability, grade), difficulty)
        case .review:
            // Whole days, counted between one morning and another. A card is
            // due at the start of a day, so answering it before breakfast and
            // answering it at midnight are the same review — measuring the gap
            // in hours would quietly give two learners two different schedules
            // for the same work.
            let elapsed = Double(max(0, calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: state.lastReviewedAt ?? date),
                to: calendar.startOfDay(for: date)
            ).day ?? 0))
            let recall = fsrs.retrievability(afterDays: elapsed, stability: state.stability)
            let stability = grade == .again
                ? fsrs.forgetStability(difficulty: state.difficulty, stability: state.stability, retrievability: recall)
                : fsrs.recallStability(difficulty: state.difficulty, stability: state.stability, retrievability: recall, grade: grade)
            return (stability, difficulty)
        }
    }

    // MARK: - A word already known

    /// Easy on a word never answered before is not "that came quickly" — there
    /// is nothing yet for it to have come quickly compared with. It is the
    /// learner saying they knew the word before the app did.
    ///
    /// So the memory is declared rather than measured: a stability that makes
    /// the known-word interval come out at the learner's own retention, and the
    /// difficulty of an easy word. From then on it is an ordinary card. The
    /// next answer is measured against that stability like any other, so a
    /// word that turns out not to be known after all lapses and is relearned
    /// in the usual way.
    private func alreadyKnown(
        _ next: inout SchedulingState,
        of state: SchedulingState,
        at date: Date,
        retention: Double
    ) {
        let memory = configuration.memory
        next.stability = memory.stability(forInterval: configuration.knownWordIntervalDays, retention: retention)
        next.difficulty = memory.initialDifficulty(.easy)
        let days = interval(stability: next.stability, retention: retention, state: state, grade: .easy)
        settle(&next, days: days, at: date)
    }

    // MARK: - Learning and relearning

    private func step(
        _ next: inout SchedulingState,
        of state: SchedulingState,
        through steps: [TimeInterval],
        grade: ReviewGrade,
        at date: Date,
        relearning: Bool,
        retention: Double
    ) {
        // A scheduler configured with no steps at all still has to answer.
        guard !steps.isEmpty else {
            graduate(&next, of: state, grade: grade, at: date, relearning: relearning, retention: retention)
            return
        }

        let stage: LearningStage = relearning ? .relearning : .learning
        let index = min(max(state.step, 0), steps.count - 1)

        switch grade {
        case .again:
            next.stage = stage
            next.step = 0
            next.dueDate = date.addingTimeInterval(steps[0])

        case .hard:
            // On the first step, halfway to the next one; on any other step,
            // that step again; with only one step, half again as long. Never a
            // way of moving forward.
            let delay = index == 0
                ? (steps.count > 1 ? (steps[0] + steps[1]) / 2 : steps[0] * 1.5)
                : steps[index]
            next.stage = stage
            next.step = index
            next.dueDate = date.addingTimeInterval(delay)

        case .good:
            let advanced = index + 1
            if advanced >= steps.count {
                graduate(&next, of: state, grade: grade, at: date, relearning: relearning, retention: retention)
            } else {
                next.stage = stage
                next.step = advanced
                next.dueDate = date.addingTimeInterval(steps[advanced])
            }

        case .easy:
            // Easy leaves the steps behind wherever it is pressed. A word the
            // learner answers instantly does not need to be asked twice more
            // in the same quarter of an hour — and after a lapse, FSRS has
            // already cut the card's stability, so Easy cannot buy back the
            // fortnight the word just lost.
            graduate(&next, of: state, grade: grade, at: date, relearning: relearning, retention: retention)
        }
    }

    /// Out of the steps and onto a date.
    private func graduate(
        _ next: inout SchedulingState,
        of state: SchedulingState,
        grade: ReviewGrade,
        at date: Date,
        relearning: Bool,
        retention: Double
    ) {
        let choices = intervals(after: state, at: date, retention: retention)
        var days = choices[grade] ?? 1
        if relearning { days = max(days, configuration.minimumIntervalAfterRelearning) }
        settle(&next, days: days, at: date)
    }

    // MARK: - Review

    private func review(
        _ next: inout SchedulingState,
        of state: SchedulingState,
        grade: ReviewGrade,
        at date: Date,
        retention: Double
    ) {
        guard grade == .again else {
            settle(&next, days: intervals(after: state, at: date, retention: retention)[grade] ?? 1, at: date)
            return
        }

        next.lapses += 1

        guard let first = configuration.relearningSteps.first else {
            // Nothing to relearn through: back into review at the shortest
            // interval the lapse allows.
            let days = max(
                configuration.minimumIntervalAfterRelearning,
                intervals(after: state, at: date, retention: retention)[.again] ?? 1
            )
            settle(&next, days: days, at: date)
            return
        }

        next.stage = .relearning
        next.step = 0
        next.dueDate = date.addingTimeInterval(first)
    }

    // MARK: - Intervals

    /// What each answer would be worth in days, worked out together.
    ///
    /// Together, because they have to come out in order: Hard can never be
    /// longer than Good, and Easy is always at least a day beyond it. Four
    /// numbers calculated apart would sometimes cross, and a learner who sees
    /// Hard promise more than Good has been told a lie about the algorithm.
    private func intervals(
        after state: SchedulingState,
        at date: Date,
        retention: Double
    ) -> [ReviewGrade: Double] {
        var days: [ReviewGrade: Double] = [:]
        for grade in ReviewGrade.allCases {
            let stability = memory(of: state, answered: grade, at: date).stability
            days[grade] = interval(stability: stability, retention: retention, state: state, grade: grade)
        }

        // Hard only produces an interval on a card that has left learning. On
        // a card still being learned it repeats a step and never graduates, so
        // it has no business pushing Good a day further out.
        if state.stage == .review {
            days[.hard] = min(days[.hard]!, days[.good]!)
            days[.good] = max(days[.good]!, days[.hard]! + 1)
        }
        days[.easy] = max(days[.easy]!, days[.good]! + 1)
        return days
    }

    private func interval(
        stability: Double,
        retention: Double,
        state: SchedulingState,
        grade: ReviewGrade
    ) -> Double {
        let raw = configuration.memory.interval(stability: stability, retention: retention)
        let spread = configuration.spreadsIntervals
            ? self.spread(raw, previous: state.intervalDays, seed: seed(for: state, grade: grade))
            : raw
        return min(max(1, spread.rounded()), configuration.maximumIntervalDays)
    }

    /// A few percent either way, so that a hundred words learned together do
    /// not arrive together for the rest of their lives.
    ///
    /// Only intervals worth spreading are spread: shifting two days by five
    /// percent moves nothing, and would only make the buttons lie.
    private func spread(_ interval: Double, previous: Double, seed: UInt64) -> Double {
        guard interval >= 2.5 else { return interval }
        let value = interval.rounded()
        var lowest = max(2, (value * 0.95 - 1).rounded())
        let highest = (value * 1.05 + 1).rounded()
        // An interval that grew must still be longer than the one before it.
        if value > previous, previous > 0 { lowest = max(lowest, previous + 1) }
        guard highest > lowest else { return max(lowest, value) }
        let draw = Double(seed % 10_000) / 10_000
        return (draw * (highest - lowest + 1) + lowest).rounded(.down)
    }

    /// The card's own number, mixed with where it stands and what was pressed,
    /// so that every answer draws afresh and the same answer always draws the
    /// same. This is what lets the button say in advance what it will do.
    private func seed(for state: SchedulingState, grade: ReviewGrade) -> UInt64 {
        var value = state.spread
        for part in [UInt64(bitPattern: Int64(state.reviewCount)), UInt64(bitPattern: Int64(state.lapses)), grade.seedComponent] {
            value = (value ^ part) &* 0xBF58_476D_1CE4_E5B9
            value ^= value >> 31
        }
        return value
    }

    private func settle(_ next: inout SchedulingState, days: Double, at date: Date) {
        let clamped = min(max(1, days.rounded()), configuration.maximumIntervalDays)
        next.stage = .review
        next.step = 0
        next.intervalDays = clamped
        next.dueDate = calendar.startOfDay(for: date.addingTimeInterval(clamped * 86_400))
    }
}

private extension ReviewGrade {

    /// Distinct per button, so the four previews do not all draw the same
    /// spread and collapse onto one another.
    nonisolated var seedComponent: UInt64 {
        switch self {
        case .again: 0x1111_1111_1111_1111
        case .hard: 0x2222_2222_2222_2222
        case .good: 0x3333_3333_3333_3333
        case .easy: 0x4444_4444_4444_4444
        }
    }
}
