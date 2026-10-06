import Foundation

/// A generator that always tells the same story, so that a check about chance
/// is still a check.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// How an endless sitting decides what to show next: often for the words that
/// are being lost, rarely for the ones that are known, and never so narrowly
/// that the rest of the library is out of reach.
func checkEndless() {
    func deck(_ count: Int) -> (EndlessDeck, [QueuedCard]) {
        let cards = (0..<count).map { _ in QueuedCard(entryID: UUID(), cardID: UUID()) }
        return (EndlessDeck(cards: cards), cards)
    }

    section("An endless sitting with nothing in it")

    var empty = EndlessDeck(cards: [])
    check("draws nothing", empty.next() == nil)
    check("and says so", empty.isEmpty)

    section("The same word is never the next word")

    var (small, _) = deck(2)
    var generator = SeededGenerator(seed: 1)
    var previous: UUID?
    var repeats = 0
    for _ in 0..<400 {
        let drawn = small.next(using: &generator)!
        if drawn.cardID == previous { repeats += 1 }
        previous = drawn.cardID
    }
    check("even a sitting of two words alternates", repeats == 0)

    var (roomy, cards) = deck(10)
    var recent: [UUID] = []
    var tooSoon = 0
    for _ in 0..<600 {
        let drawn = roomy.next(using: &generator)!
        if recent.suffix(EndlessDeck.restBetween).contains(drawn.cardID) { tooSoon += 1 }
        recent.append(drawn.cardID)
    }
    check("and a word waits a few cards before coming round again", tooSoon == 0)

    section("What the last answer is worth")

    var weighted = EndlessDeck(cards: cards)
    weighted.record(cards[0], grade: .again)
    weighted.record(cards[1], grade: .hard)
    weighted.record(cards[2], grade: .good)
    weighted.record(cards[3], grade: .easy)
    for card in cards.dropFirst(4) { weighted.record(card, grade: .good) }

    var seen: [UUID: Int] = [:]
    for _ in 0..<6_000 {
        let drawn = weighted.next(using: &generator)!
        seen[drawn.cardID, default: 0] += 1
    }
    let again = seen[cards[0].cardID] ?? 0
    let hard = seen[cards[1].cardID] ?? 0
    let good = seen[cards[2].cardID] ?? 0
    let easy = seen[cards[3].cardID] ?? 0

    check("a word that would not come at all comes back most often",
          again > hard && hard > good && good > easy)
    check("more than twice as often as one that came normally", again > good * 2)
    check("and a word answered Easy is hardly asked for at all", easy * 2 < good)
    check("but it is still asked for: nothing is dropped from the sitting", easy > 0)

    // In a sitting of ten there is a ceiling on how often any one word can
    // come round, because a word just shown has to let a few others past. A
    // real vocabulary is bigger, and there the weights have room to speak.
    section("A vocabulary big enough for the weights to matter")

    var (forty, forties) = deck(40)
    let stubborn = Set(forties.prefix(5).map(\.cardID))
    var shownStubborn = 0
    var shownRest = 0
    var everyWord: Set<UUID> = []
    for _ in 0..<400 {
        let drawn = forty.next(using: &generator)!
        everyWord.insert(drawn.cardID)
        if stubborn.contains(drawn.cardID) {
            shownStubborn += 1
            forty.record(drawn, grade: .again)
        } else {
            shownRest += 1
            forty.record(drawn, grade: .good)
        }
    }
    check("five words the learner keeps missing take up nearly half the sitting",
          shownStubborn > shownRest / 2)
    check("which is several times their share of the vocabulary",
          Double(shownStubborn) / 5 > 3 * Double(shownRest) / 35)
    check("and the other thirty-five are all seen anyway", everyWord.count == 40)

    section("The whole library is reachable")

    var (library, _) = deck(60)
    var met: Set<UUID> = []
    var draws = 0
    while met.count < 60, draws < 400 {
        let drawn = library.next(using: &generator)!
        met.insert(drawn.cardID)
        // A learner going through a long list, knowing every word.
        library.record(drawn, grade: .good)
        draws += 1
    }
    check("sixty words are all seen, and quickly", met.count == 60)
    check("without labouring it", draws < 200)
    check("a word not yet shown outweighs one already known",
          EndlessDeck.unseenWeight > EndlessDeck.weight(after: .good))
    check("but not one that was just failed",
          EndlessDeck.unseenWeight < EndlessDeck.weight(after: .again))

    section("A word deleted in another window")

    var (shrinking, doomed) = deck(6)
    shrinking.drop(doomed[0].cardID)
    check("is out of the sitting", shrinking.cards.count == 5)
    var drawnAfter: Set<UUID> = []
    for _ in 0..<300 { drawnAfter.insert(shrinking.next(using: &generator)!.cardID) }
    check("and is never asked about again", !drawnAfter.contains(doomed[0].cardID))
}
