import Foundation

/// One answer, written down and never changed.
///
/// The app does not need this to schedule anything — the card carries its own
/// state. It is kept because honest statistics, daily goals and a streak can
/// only ever be built from what actually happened, and a history that starts
/// being recorded the day the statistics screen is written starts empty.
nonisolated struct ReviewRecord: Identifiable, Codable, Hashable, Sendable {

    var id: UUID
    var profileID: UUID
    var entryID: UUID
    var cardID: UUID

    var reviewedAt: Date
    var grade: ReviewGrade

    var stageBefore: LearningStage
    var stageAfter: LearningStage

    var intervalBeforeDays: Double
    var intervalAfterDays: Double

    /// Where the answer put the card. Kept so a session can be replayed exactly
    /// as the learner saw it.
    var dueAfter: Date?

    /// How long the card was on screen, when the session knows.
    var seconds: Double?

    /// Whether this answer was practice: a card gone over again for its own
    /// sake, which moved no schedule and started no new word.
    ///
    /// Kept rather than thrown away, and excluded from every figure the app
    /// shows today. Time spent is time spent, and a later screen may want to
    /// say so — but it must never be mistaken for the work the scheduler did.
    var isPractice: Bool

    init(
        id: UUID = UUID(),
        profileID: UUID,
        entryID: UUID,
        cardID: UUID,
        reviewedAt: Date,
        grade: ReviewGrade,
        stageBefore: LearningStage,
        stageAfter: LearningStage,
        intervalBeforeDays: Double,
        intervalAfterDays: Double,
        dueAfter: Date?,
        seconds: Double? = nil,
        isPractice: Bool = false
    ) {
        self.id = id
        self.profileID = profileID
        self.entryID = entryID
        self.cardID = cardID
        self.reviewedAt = reviewedAt
        self.grade = grade
        self.stageBefore = stageBefore
        self.stageAfter = stageAfter
        self.intervalBeforeDays = intervalBeforeDays
        self.intervalAfterDays = intervalAfterDays
        self.dueAfter = dueAfter
        self.seconds = seconds
        self.isPractice = isPractice
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        profileID = try container.decode(UUID.self, forKey: .profileID)
        entryID = try container.decode(UUID.self, forKey: .entryID)
        cardID = try container.decode(UUID.self, forKey: .cardID)
        reviewedAt = try container.decode(Date.self, forKey: .reviewedAt)
        grade = try container.decode(ReviewGrade.self, forKey: .grade)
        stageBefore = try container.decode(LearningStage.self, forKey: .stageBefore)
        stageAfter = try container.decode(LearningStage.self, forKey: .stageAfter)
        intervalBeforeDays = try container.decodeIfPresent(Double.self, forKey: .intervalBeforeDays) ?? 0
        intervalAfterDays = try container.decodeIfPresent(Double.self, forKey: .intervalAfterDays) ?? 0
        dueAfter = try container.decodeIfPresent(Date.self, forKey: .dueAfter)
        seconds = try container.decodeIfPresent(Double.self, forKey: .seconds)
        isPractice = try container.decodeIfPresent(Bool.self, forKey: .isPractice) ?? false
    }

    /// A first sight of a word, as opposed to a repetition of one.
    var wasIntroduction: Bool { stageBefore == .new }
}
