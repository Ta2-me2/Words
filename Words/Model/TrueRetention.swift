import Foundation

/// How often a word that was due came back.
///
/// The schedule makes a promise — nine words in ten by default — and this is
/// the only figure that says whether it is being kept. Anki calls it true
/// retention, and "true" is the point: it counts the answer to a card that had
/// been waiting on an interval, and nothing else. A learning step answered
/// three minutes after the last one is not a memory being tested, and counting
/// it would quietly turn a hard month into a good one.
///
/// What is left out, and why:
///
/// - **Practice.** It moves no schedule and it is chosen, not asked for.
/// - **Learning and relearning steps.** A word being got in, or got back, is
///   not a word being remembered.
/// - **Nothing else.** Every scheduled review ever given is counted, including
///   the ones from a language since deleted — but a language's own screen asks
///   only for its own.
nonisolated enum TrueRetention {

    /// Where a card stops being young and starts being known, as Anki draws
    /// the line: three weeks.
    static let matureDays: Double = 21

    /// Below this there is not enough to say anything with: a dozen answers
    /// can read as 60% or 90% on the same memory.
    static let enoughToJudge = 30

    /// Whether an answer says anything about remembering.
    static func counts(_ record: ReviewRecord) -> Bool {
        !record.isPractice && record.stageBefore == .review
    }

    // MARK: - Over time

    static func periods(
        reviews: [ReviewRecord],
        profileID: UUID,
        asOf date: Date,
        calendar: Calendar = .current
    ) -> [RetentionPeriod] {
        let counted = reviews.filter { $0.profileID == profileID && counts($0) }
        let today = calendar.startOfDay(for: date)

        func start(daysBack days: Int) -> Date {
            calendar.date(byAdding: .day, value: -days, to: today) ?? today
        }

        return RetentionSpan.allCases.map { span in
            let within: [ReviewRecord]
            switch span {
            case .today:
                within = counted.filter { $0.reviewedAt >= today }
            case .yesterday:
                let yesterday = start(daysBack: 1)
                within = counted.filter { $0.reviewedAt >= yesterday && $0.reviewedAt < today }
            case .week:
                let from = start(daysBack: 6)
                within = counted.filter { $0.reviewedAt >= from }
            case .month:
                let from = start(daysBack: 29)
                within = counted.filter { $0.reviewedAt >= from }
            case .year:
                let from = start(daysBack: 364)
                within = counted.filter { $0.reviewedAt >= from }
            case .all:
                within = counted
            }
            return RetentionPeriod(span: span, young: tally(within) { $0 < matureDays }, mature: tally(within) { $0 >= matureDays })
        }
    }

    /// The span worth putting at the top of the screen: the most recent one
    /// with enough answers in it to mean something, and the longest view there
    /// is when none of them has.
    static func headline(_ periods: [RetentionPeriod]) -> RetentionPeriod? {
        let wanted: [RetentionSpan] = [.month, .year, .all]
        for span in wanted {
            guard let period = periods.first(where: { $0.span == span }) else { continue }
            if period.all.total >= enoughToJudge { return period }
        }
        return periods.first { $0.span == .all && $0.all.total > 0 }
            ?? periods.first { $0.all.total > 0 }
    }

    // MARK: - By how long the word waited

    /// Every band, including the ones nothing has reached yet: an empty row is
    /// a fact about the library, and dropping it would make the table move
    /// around as the weeks pass.
    static func bands(
        reviews: [ReviewRecord],
        profileID: UUID,
        since: Date? = nil
    ) -> [RetentionBand] {
        let counted = reviews.filter {
            $0.profileID == profileID && counts($0) && (since == nil || $0.reviewedAt >= since!)
        }
        return RetentionWait.allCases.map { wait in
            RetentionBand(wait: wait, count: tally(counted) { wait.contains($0) })
        }
    }

    // MARK: - The words that were already known

    /// What became of the words answered Easy the first time they were ever
    /// seen — the ones the learner said they knew before the app did, and
    /// which the scheduler set aside for a month on that word alone.
    ///
    /// It is the app's own rule rather than FSRS's, so it is the app's job to
    /// show whether it holds.
    static func declaredKnown(reviews: [ReviewRecord], profileID: UUID) -> DeclaredKnown {
        var byCard: [UUID: [ReviewRecord]] = [:]
        for record in reviews where record.profileID == profileID && !record.isPractice {
            byCard[record.cardID, default: []].append(record)
        }

        var result = DeclaredKnown()
        for (_, records) in byCard {
            let ordered = records.sorted { $0.reviewedAt < $1.reviewedAt }
            guard let first = ordered.first, first.wasIntroduction, first.grade == .easy else { continue }
            result.declared += 1
            guard let back = ordered.dropFirst().first(where: { counts($0) }) else {
                result.waiting += 1
                continue
            }
            result.count.add(back)
        }
        return result
    }

    // MARK: -

    private static func tally(_ records: [ReviewRecord], where wait: (Double) -> Bool) -> RecallCount {
        var count = RecallCount()
        for record in records where wait(record.intervalBeforeDays) {
            count.add(record)
        }
        return count
    }
}

/// Answers of one kind, split into the ones that came back and the ones that
/// did not.
nonisolated struct RecallCount: Hashable, Sendable {
    var remembered = 0
    var forgotten = 0

    var total: Int { remembered + forgotten }

    /// `nil` while nothing has been counted: a share of no answers is not
    /// nought, it is not yet a question.
    var share: Double? {
        total == 0 ? nil : Double(remembered) / Double(total)
    }

    mutating func add(_ record: ReviewRecord) {
        if record.grade == .again { forgotten += 1 } else { remembered += 1 }
    }
}

/// The stretches of time the table is cut into — Anki's own, so that two
/// learners comparing notes are comparing the same thing.
nonisolated enum RetentionSpan: String, CaseIterable, Identifiable, Sendable {
    case today, yesterday, week, month, year, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .week: "Last week"
        case .month: "Last month"
        case .year: "Last year"
        case .all: "All time"
        }
    }
}

/// One line of the table: how a stretch of time went, with the young cards and
/// the known ones apart.
nonisolated struct RetentionPeriod: Identifiable, Hashable, Sendable {
    var span: RetentionSpan
    var young: RecallCount
    var mature: RecallCount

    var id: String { span.rawValue }

    var all: RecallCount {
        RecallCount(
            remembered: young.remembered + mature.remembered,
            forgotten: young.forgotten + mature.forgotten
        )
    }
}

/// How long a word had been left alone before it was asked again.
nonisolated enum RetentionWait: String, CaseIterable, Identifiable, Sendable {
    case days1to3, days4to7, weeks1to3, weeks3toMonths3, beyond

    var id: String { rawValue }

    var title: String {
        switch self {
        case .days1to3: "1–3 days"
        case .days4to7: "4–7 days"
        case .weeks1to3: "1–3 weeks"
        case .weeks3toMonths3: "3 weeks – 3 months"
        case .beyond: "Over 3 months"
        }
    }

    /// Whether a wait of this many days belongs in this band. The first one
    /// takes everything below it, so a card somehow asked a day early is
    /// counted rather than lost.
    func contains(_ days: Double) -> Bool {
        switch self {
        case .days1to3: days < 4
        case .days4to7: days >= 4 && days < 8
        case .weeks1to3: days >= 8 && days < 22
        case .weeks3toMonths3: days >= 22 && days < 91
        case .beyond: days >= 91
        }
    }
}

/// One line of the by-wait table.
nonisolated struct RetentionBand: Identifiable, Hashable, Sendable {
    var wait: RetentionWait
    var count: RecallCount

    var id: String { wait.rawValue }
}

/// The app's own rule, measured: words declared known on sight.
nonisolated struct DeclaredKnown: Hashable, Sendable {
    /// How many words were ever answered Easy the first time they were seen.
    var declared = 0
    /// How many of those have not come back round yet.
    var waiting = 0
    /// How the ones that did come back went.
    var count = RecallCount()
}
