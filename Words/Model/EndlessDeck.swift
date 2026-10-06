import Foundation

/// The order of an endless sitting.
///
/// Not a queue. A queue of fixed length is a loop: answer the first dozen words
/// and they are reinserted just far enough ahead to come round again, and the
/// learner circles those twelve for ever while the rest of the library is never
/// reached. This draws instead. Every card in scope carries a weight, the next
/// one is picked at random in proportion to it, and the weight is simply what
/// the last answer said about the word.
///
/// Three things follow from that, and they are the whole point of the mode:
///
/// - the sitting never begins the same way twice;
/// - a word that would not come back is seen many times more often than one
///   that came easily, without ever being the only word on offer;
/// - nothing is unreachable, because no weight is ever nought — and a word this
///   sitting has not shown yet outweighs one it has, so the first pass covers
///   new ground rather than drilling the first handful.
///
/// Within the sitting only. Nothing here is written down or remembered
/// tomorrow; that is what makes it practice rather than review.
nonisolated struct EndlessDeck: Sendable {

    /// What a word's last answer says about how often it should come back.
    ///
    /// A word answered Again is worth showing nine times as often as one
    /// answered Good, and thirty times as often as one answered Easy. If the
    /// learner knows it, there is nothing to gain by showing it; if they do not,
    /// showing it is the only thing that will help.
    static func weight(after grade: ReviewGrade) -> Double {
        switch grade {
        case .again: 9
        case .hard: 4
        case .good: 1
        case .easy: 0.3
        }
    }

    /// A word this sitting has not shown yet.
    ///
    /// Above every answered word but the failed ones, so an endless sitting
    /// works through the library rather than hammering its opening dozen — and
    /// below Again, so a word just missed does not have to wait for the end of
    /// the alphabet to come round again.
    static let unseenWeight: Double = 6

    /// How many of the most recent cards are held out of the draw. A word
    /// answered Again is meant to come back soon; it is not meant to be the
    /// next card, and the one after that.
    static let restBetween = 3

    private(set) var cards: [QueuedCard]
    private var weights: [UUID: Double] = [:]
    private var recent: [UUID] = []

    init(cards: [QueuedCard]) {
        self.cards = cards
    }

    var isEmpty: Bool { cards.isEmpty }

    /// How many cards are held back, given how many there are to hold back
    /// from. A short sitting rests fewer, or the weights would stop mattering
    /// and four words would simply take it in turns.
    private var rest: Int {
        min(Self.restBetween, max(1, (cards.count - 1) / 3))
    }

    /// What the sitting has been told about this word so far.
    func weight(of card: QueuedCard) -> Double {
        weights[card.cardID] ?? Self.unseenWeight
    }

    var hasUnseen: Bool { cards.contains { weights[$0.cardID] == nil } }

    mutating func record(_ card: QueuedCard, grade: ReviewGrade) {
        weights[card.cardID] = Self.weight(after: grade)
    }

    /// Takes a word out of the sitting — it was deleted in another window.
    mutating func drop(_ cardID: UUID) {
        cards.removeAll { $0.cardID == cardID }
        weights[cardID] = nil
        recent.removeAll { $0 == cardID }
    }

    mutating func next() -> QueuedCard? {
        var generator = SystemRandomNumberGenerator()
        return next(using: &generator)
    }

    mutating func next<G: RandomNumberGenerator>(using generator: inout G) -> QueuedCard? {
        guard !cards.isEmpty else { return nil }

        // Never the same card twice running, nor one of the last few.
        let resting = Set(recent)
        let eligible = cards.filter { !resting.contains($0.cardID) }
        let choices = eligible.isEmpty ? cards : eligible

        let total = choices.reduce(0) { $0 + weight(of: $1) }
        var remainder = Double.random(in: 0..<total, using: &generator)
        var chosen = choices[choices.count - 1]
        for card in choices {
            remainder -= weight(of: card)
            if remainder < 0 {
                chosen = card
                break
            }
        }

        recent.append(chosen.cardID)
        while recent.count > rest { recent.removeFirst() }

        return chosen
    }
}
