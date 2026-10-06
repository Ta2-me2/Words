import Foundation

/// What a sitting is for.
///
/// Only one of these moves a schedule. The other two exist because a learner
/// who has finished today's cards should not have to wait until tomorrow to
/// use the app — and going over words again must never be a way of quietly
/// bringing tomorrow's work forward.
nonisolated enum StudyMode: Hashable, Sendable {

    /// The real thing: the cards the scheduler says are ready, answered once,
    /// written down, and given new dates.
    case scheduled

    /// Today's work, gone over again. Changes nothing.
    case practiceToday

    /// A sitting with no end, drawn at random from the words in scope.
    /// Changes nothing; within the sitting, a word answered badly comes back
    /// sooner and more often.
    case endless(StudyQueue.PracticePool)

    var isPractice: Bool { self != .scheduled }

    var isEndless: Bool {
        if case .endless = self { return true }
        return false
    }

    /// Whether a sitting of this kind is worth coming back to.
    ///
    /// The first two have a plan: a number of cards, in an order, with a count
    /// underneath. An endless sitting has none — it is a stream rather than a
    /// queue, there is no place in it to return to, and writing a copy of the
    /// whole library into the file after every answer to pretend otherwise
    /// would be a cost with nothing on the other side of it.
    var isResumable: Bool {
        switch self {
        case .scheduled, .practiceToday: true
        case .endless: false
        }
    }

    var title: String {
        switch self {
        case .scheduled: "Review"
        case .practiceToday: "Practice"
        case .endless(let pool): "Endless · \(pool.title)"
        }
    }
}

/// Written down only because a sitting left half-finished has to be found
/// again. Nothing else stores a mode.
extension StudyMode: Codable {

    private enum CodingKeys: String, CodingKey { case kind, pool }

    private enum Kind: String, Codable { case scheduled, practiceToday, endless }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .scheduled:
            self = .scheduled
        case .practiceToday:
            self = .practiceToday
        case .endless:
            self = .endless(try container.decode(StudyQueue.PracticePool.self, forKey: .pool))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .scheduled:
            try container.encode(Kind.scheduled, forKey: .kind)
        case .practiceToday:
            try container.encode(Kind.practiceToday, forKey: .kind)
        case .endless(let pool):
            try container.encode(Kind.endless, forKey: .kind)
            try container.encode(pool, forKey: .pool)
        }
    }
}
