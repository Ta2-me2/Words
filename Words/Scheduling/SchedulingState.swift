import Foundation

/// Where a card stands in its own history.
///
/// A card is new until it is first answered, spends a short while in learning,
/// and then lives in review with a growing interval. A forgotten review card
/// goes back through relearning rather than all the way back to new — it is not
/// a word you have never seen.
nonisolated enum LearningStage: String, Codable, Sendable {
    case new
    case learning
    case review
    case relearning

    var title: String {
        switch self {
        case .new: "New"
        case .learning: "Learning"
        case .review: "Review"
        case .relearning: "Relearning"
        }
    }
}

/// Everything a scheduler needs to know about one card, and nothing about the
/// word on it.
///
/// This is deliberately a plain value with no behaviour: the rules for changing
/// it live in `ReviewScheduler`, so a better algorithm can replace them without
/// touching the stored shape of a card.
nonisolated struct SchedulingState: Codable, Hashable, Sendable {

    var stage: LearningStage = .new

    /// Position in the scheduler's learning or relearning steps.
    var step: Int = 0

    /// The interval that produced the current due date, in days. Sub-day
    /// learning delays are not intervals and are not recorded here.
    var intervalDays: Double = 0

    /// How many days this word can go before recall falls to nine in ten.
    /// Nought means it has never been measured — a word not yet met.
    var stability: Double = 0

    /// How hard this particular word is to keep, from 1 to 10. Nought until
    /// there is an answer to judge it by.
    var difficulty: Double = 0

    /// A number of this card's own, drawn once and never changed.
    ///
    /// Intervals are spread by a few percent so that fifty words learned in one
    /// sitting do not all come back on the same Tuesday for the rest of their
    /// lives. The spread has to be the card's own — two cards in identical
    /// health must be pushed apart, not together — and it has to be settled in
    /// advance, or the interval written on the Good button would not be the
    /// interval the button then gives.
    var spread: UInt64 = .random(in: .min ... .max)

    /// When the card next wants to be seen. `nil` means it has never been
    /// scheduled, which is what makes a card new.
    var dueDate: Date?

    var reviewCount: Int = 0

    /// How many times a known word was forgotten. The honest measure of a
    /// difficult word, and the one the statistics will want later.
    var lapses: Int = 0

    var firstReviewedAt: Date?
    var lastReviewedAt: Date?

    init() {}

    /// Reads a card written by an older version.
    ///
    /// Cards scheduled by the previous algorithm carried an ease factor and an
    /// interval instead of a stability and a difficulty. They are converted on
    /// the way in — once, silently, and without moving a single due date — so
    /// that a library in use carries on from exactly where it stood.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stage = try container.decodeIfPresent(LearningStage.self, forKey: .stage) ?? .new
        step = try container.decodeIfPresent(Int.self, forKey: .step) ?? 0
        intervalDays = try container.decodeIfPresent(Double.self, forKey: .intervalDays) ?? 0
        reviewCount = try container.decodeIfPresent(Int.self, forKey: .reviewCount) ?? 0
        lapses = try container.decodeIfPresent(Int.self, forKey: .lapses) ?? 0
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        firstReviewedAt = try container.decodeIfPresent(Date.self, forKey: .firstReviewedAt)
        lastReviewedAt = try container.decodeIfPresent(Date.self, forKey: .lastReviewedAt)

        let storedStability = try container.decodeIfPresent(Double.self, forKey: .stability)
        let storedDifficulty = try container.decodeIfPresent(Double.self, forKey: .difficulty)

        if let storedStability, let storedDifficulty {
            stability = storedStability
            difficulty = storedDifficulty
        } else if stage != .new, intervalDays > 0,
                  let ease = try? decoder.container(keyedBy: LegacyKeys.self).decodeIfPresent(Double.self, forKey: .ease) {
            (stability, difficulty) = FSRS().converted(intervalDays: intervalDays, ease: ease)
        }

        // A card written before the spread existed still needs one, and it must
        // be the same one every time the file is opened.
        spread = try container.decodeIfPresent(UInt64.self, forKey: .spread)
            ?? Self.derivedSpread(firstReviewedAt: firstReviewedAt, dueDate: dueDate, intervalDays: intervalDays)
    }

    /// The ease factor of the algorithm this one replaced. Read, never written.
    private enum LegacyKeys: String, CodingKey { case ease }

    private static func derivedSpread(firstReviewedAt: Date?, dueDate: Date?, intervalDays: Double) -> UInt64 {
        var value: UInt64 = 0x9E37_79B9_7F4A_7C15
        for part in [firstReviewedAt?.timeIntervalSinceReferenceDate, dueDate?.timeIntervalSinceReferenceDate, intervalDays] {
            value ^= (part ?? 0).bitPattern
            value = value &* 0xBF58_476D_1CE4_E5B9
            value ^= value >> 27
        }
        return value
    }

    var isNew: Bool { stage == .new }

    var isInLearning: Bool { stage == .learning || stage == .relearning }

    /// How many times a word may be forgotten before the card itself, rather
    /// than the schedule, is the thing at fault. Anki's own threshold.
    static let attentionThreshold = 8

    /// A word that keeps going however often it is asked. No algorithm fixes
    /// this one: it wants an example, a picture, or to be split in two.
    var needsAttention: Bool { lapses >= Self.attentionThreshold }

    func isDue(asOf date: Date) -> Bool {
        guard let dueDate else { return true }
        return dueDate <= date
    }

    /// Whether the card is part of a given day's work.
    ///
    /// A learning step is measured in minutes, so a card answered at four
    /// o'clock is wanted again at ten past — still today, and still unfinished.
    /// Counting only the cards that are ready *this minute* would let a session
    /// abandoned half-way report the day as done. Reviews are unaffected: their
    /// dates are whole days already, and one set for tomorrow stays there.
    func isDue(onDayOf date: Date, calendar: Calendar) -> Bool {
        guard let dueDate else { return true }
        return dueDate <= date || calendar.isDate(dueDate, inSameDayAs: date)
    }

    /// Whether the card was first seen on a given day, which is how the daily
    /// allowance of new words knows what it has already spent.
    func wasIntroduced(on day: Date, calendar: Calendar) -> Bool {
        guard let firstReviewedAt else { return false }
        return calendar.isDate(firstReviewedAt, inSameDayAs: day)
    }

    /// Whether the card was answered at all on a given day.
    func wasAnswered(on day: Date, calendar: Calendar) -> Bool {
        guard let lastReviewedAt else { return false }
        return calendar.isDate(lastReviewedAt, inSameDayAs: day)
    }

    /// Whether a card from an earlier day was taken on this one — which is what
    /// a daily limit on reviews counts. Once, however many times it was
    /// answered: a word that lapses and comes back three times this afternoon
    /// is one review, not four.
    func wasReviewed(on day: Date, calendar: Calendar) -> Bool {
        wasAnswered(on: day, calendar: calendar) && !wasIntroduced(on: day, calendar: calendar)
    }
}
