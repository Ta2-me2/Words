import Foundation

/// A card in the middle of its life, built by hand so the arithmetic has
/// something definite to work on.
func reviewState(
    stability: Double,
    difficulty: Double,
    intervalDays: Double,
    lastReviewed: Date,
    spread: UInt64 = 0x0123_4567_89AB_CDEF
) -> SchedulingState {
    var state = SchedulingState()
    state.stage = .review
    state.stability = stability
    state.difficulty = difficulty
    state.intervalDays = intervalDays
    state.dueDate = lastReviewed.addingTimeInterval(intervalDays * 86_400)
    state.firstReviewedAt = lastReviewed
    state.lastReviewedAt = lastReviewed
    state.reviewCount = 4
    state.spread = spread
    return state
}

/// The rules a learner is promised: a word met twice is a review card, a word
/// forgotten keeps its history, no two words are told the same story about
/// themselves, and the interval written on a button is the interval it gives.
func checkScheduler() {
    let scheduler = FSRSScheduler()
    let now = moment(2026, 3, 2, 9)

    section("A word met for the first time")

    var fresh = SchedulingState()
    fresh.spread = 0xDEAD_BEEF_0000_0001
    check("a new card is due immediately", fresh.isDue(asOf: now))
    check("and has no date of its own", fresh.dueDate == nil)
    check("nothing is known about it yet", fresh.stability == 0 && fresh.difficulty == 0)

    let firstGood = scheduler.nextState(for: fresh, grade: .good, at: now)
    check("answering it starts learning", firstGood.stage == .learning)
    check("and brings it back a quarter of an hour later",
          firstGood.dueDate == now.addingTimeInterval(900))
    check("the first sighting is remembered", firstGood.firstReviewedAt == now)
    check("it is not yet an interval", firstGood.intervalDays == 0)
    check("but the memory has been measured", firstGood.stability == 2.31)
    check("and the word judged", firstGood.difficulty == 2.12)

    let firstAgain = scheduler.nextState(for: fresh, grade: .again, at: now)
    check("Again puts it back to the first step",
          firstAgain.stage == .learning && firstAgain.step == 0)
    check("three minutes away", firstAgain.dueDate == now.addingTimeInterval(180))
    check("a word that would not come is a harder word", firstAgain.difficulty > firstGood.difficulty)
    check("and a weaker memory", firstAgain.stability < firstGood.stability)

    let firstHard = scheduler.nextState(for: fresh, grade: .hard, at: now)
    check("Hard sits halfway between the two steps",
          firstHard.dueDate == now.addingTimeInterval(540))
    check("without advancing", firstHard.step == 0)

    let firstEasy = scheduler.nextState(for: fresh, grade: .easy, at: now)
    check("Easy leaves the steps altogether", firstEasy.stage == .review)
    check("and, as a first answer, means the word was already known: a month out",
          (28...33).contains(Int(firstEasy.intervalDays)))

    check("every answer says something different",
          Set([firstAgain, firstHard, firstGood, firstEasy].map(\.dueDate)).count == 4)

    section("Two good answers make a review card")

    let graduated = scheduler.nextState(for: firstGood, grade: .good, at: now.addingTimeInterval(900))
    check("it leaves learning", graduated.stage == .review)
    check("with the interval its own memory asks for", graduated.intervalDays == 2)
    check("waiting at the start of that day",
          graduated.dueDate == calendar.startOfDay(for: graduated.dueDate!))
    // A word answered badly all morning graduates at one day, not two: Hard
    // cannot graduate a learning card at all, so it must not push Good out.
    var struggled = firstGood
    struggled.stability = 0.01
    struggled.difficulty = 9.8
    check("a word barely known graduates at a single day",
          scheduler.nextState(for: struggled, grade: .good, at: now.addingTimeInterval(900)).intervalDays == 1)

    check("Easy on the second step goes further than Good",
          scheduler.nextState(for: firstGood, grade: .easy, at: now.addingTimeInterval(900)).intervalDays
              > graduated.intervalDays)

    section("No two words are told the same story")

    let easyWord = reviewState(stability: 30, difficulty: 2, intervalDays: 30, lastReviewed: now.addingTimeInterval(-30 * 86_400))
    let hardWord = reviewState(stability: 30, difficulty: 9, intervalDays: 30, lastReviewed: now.addingTimeInterval(-30 * 86_400))

    let easyNext = scheduler.nextState(for: easyWord, grade: .good, at: now)
    let hardNext = scheduler.nextState(for: hardWord, grade: .good, at: now)
    check("the same answer on two words gives two intervals",
          easyNext.intervalDays != hardNext.intervalDays)
    check("and the word the learner finds easy waits longer",
          easyNext.intervalDays > hardNext.intervalDays)
    check("both are further out than they were",
          easyNext.intervalDays > 30 && hardNext.intervalDays > 30)

    let hardAnswer = scheduler.nextState(for: easyWord, grade: .hard, at: now)
    let easyAnswer = scheduler.nextState(for: easyWord, grade: .easy, at: now)
    check("Hard is never longer than Good", hardAnswer.intervalDays <= easyNext.intervalDays)
    check("and Easy is always at least a day beyond it",
          easyAnswer.intervalDays >= easyNext.intervalDays + 1)
    check("Hard still moves the word forward", hardAnswer.intervalDays > 30)
    check("but marks it harder", hardAnswer.difficulty > easyWord.difficulty)

    section("Forgetting a word does not forget its history")

    let known = reviewState(stability: 60, difficulty: 5, intervalDays: 60, lastReviewed: now.addingTimeInterval(-60 * 86_400))
    let lapsed = scheduler.nextState(for: known, grade: .again, at: now)
    check("Again is a lapse", lapsed.lapses == 1)
    check("it is relearned, not met anew", lapsed.stage == .relearning)
    check("coming back in ten minutes", lapsed.dueDate == now.addingTimeInterval(600))
    check("the memory is cut, not erased",
          lapsed.stability < known.stability && lapsed.stability > 0)
    check("and the word is marked harder", lapsed.difficulty > known.difficulty)
    check("the interval it had is still on the card", lapsed.intervalDays == 60)

    let recovered = scheduler.nextState(for: lapsed, grade: .good, at: now.addingTimeInterval(600))
    check("recovering it returns it to review", recovered.stage == .review)
    check("at least a day out", recovered.intervalDays >= 1)
    check("but nowhere near where it was", recovered.intervalDays < known.intervalDays)
    check("the lapse is still counted", recovered.lapses == 1)

    let rushed = scheduler.nextState(for: lapsed, grade: .easy, at: now.addingTimeInterval(600))
    check("Easy cannot buy back the two months the word just lost",
          rushed.intervalDays < known.intervalDays)

    var leech = known
    leech.lapses = SchedulingState.attentionThreshold - 1
    check("a word forgotten once more than the app will tolerate asks for help",
          scheduler.nextState(for: leech, grade: .again, at: now).needsAttention)
    check("and one forgotten less than that does not", !lapsed.needsAttention)

    section("What the rules never allow")

    var growing = reviewState(stability: 5, difficulty: 5, intervalDays: 5, lastReviewed: now.addingTimeInterval(-5 * 86_400))
    var previous = growing.intervalDays
    var answeredAt = now
    var everShrank = false
    for _ in 0..<12 {
        growing = scheduler.nextState(for: growing, grade: .good, at: answeredAt)
        if growing.intervalDays <= previous { everShrank = true }
        previous = growing.intervalDays
        answeredAt = growing.dueDate!
    }
    check("a word answered well is asked for later every single time", !everShrank)
    check("and after a year of Good answers it is left alone for years", previous > 365)

    // Four Agains inside a minute is a real thing a real person does, and the
    // arithmetic must survive it: several of the formulas raise stability to a
    // negative power, where nought becomes infinity and the word is filed away
    // for a hundred years.
    var hammered = SchedulingState()
    hammered.spread = 7
    var hammeredAt = now
    for _ in 0..<20 {
        hammered = scheduler.nextState(for: hammered, grade: .again, at: hammeredAt)
        hammeredAt = hammeredAt.addingTimeInterval(12)
    }
    check("a memory is never worth exactly nothing", hammered.stability >= FSRS.minimumStability)
    let rescued = scheduler.nextState(for: hammered, grade: .good, at: hammeredAt.addingTimeInterval(600))
    check("and a word hammered into the ground still comes back tomorrow",
          rescued.intervalDays.isFinite && rescued.intervalDays <= 2)

    let enormous = reviewState(stability: 40_000, difficulty: 1, intervalDays: 30_000, lastReviewed: now)
    check("nothing waits longer than the ceiling",
          scheduler.nextState(for: enormous, grade: .easy, at: now).intervalDays <= 36_500)

    section("A hundred words learned together do not return together")

    var landings: Set<Double> = []
    for index in 0..<40 {
        let card = reviewState(
            stability: 100,
            difficulty: 5,
            intervalDays: 90,
            lastReviewed: now.addingTimeInterval(-90 * 86_400),
            spread: UInt64(index) &* 0x9E37_79B9_7F4A_7C15
        )
        landings.insert(scheduler.nextState(for: card, grade: .good, at: now).intervalDays)
    }
    check("forty identical words are spread over several days", landings.count > 3)
    check("but none of them by more than a few percent",
          (landings.max()! - landings.min()!) / landings.min()! < 0.2)

    let steady = reviewState(stability: 100, difficulty: 5, intervalDays: 90, lastReviewed: now)
    check("the same card answered the same way always lands on the same day",
          scheduler.nextState(for: steady, grade: .good, at: now).dueDate
              == scheduler.nextState(for: steady, grade: .good, at: now).dueDate)

    section("The buttons keep their promises")

    let preview = scheduler.preview(for: fresh, at: now)
    check("every button knows what it will do", preview.count == 4)
    check("Again is three minutes", IntervalText.short(seconds: preview[.again]!) == "3 m")
    check("Good is a quarter of an hour", IntervalText.short(seconds: preview[.good]!) == "15 m")

    for grade in ReviewGrade.allCases {
        let promised = scheduler.preview(for: steady, at: now)[grade]!
        let kept = scheduler.nextState(for: steady, grade: grade, at: now).dueDate!.timeIntervalSince(now)
        check("what the \(grade.title) button says is what it does", promised == kept)
    }

    check("a day interval is said in days, not in hours",
          IntervalText.short(for: graduated, from: now.addingTimeInterval(900)).hasSuffix(" d"))
    check("a month is said in months", IntervalText.days(45) == "1 mo")
    check("a year is said in years", IntervalText.days(400) == "1.1 y")
    check("ten minutes is said in minutes", IntervalText.short(seconds: 600) == "10 m")

    section("How much forgetting the learner will put up with")

    let careful = scheduler.nextState(for: steady, grade: .good, at: now, retention: 0.95)
    let relaxed = scheduler.nextState(for: steady, grade: .good, at: now, retention: 0.85)
    check("wanting to remember more means being asked more often",
          careful.intervalDays < relaxed.intervalDays)
    check("a goal outside what the algorithm can do is brought back inside it",
          Retention.clamped(0.5) == 0.80 && Retention.clamped(1.0) == 0.97)

    section("Days, not hours")

    let lateEvening = moment(2026, 3, 2, 23, 30)
    let earlyMorning = moment(2026, 3, 2, 6, 15)
    let fromEvening = scheduler.nextState(for: known, grade: .good, at: lateEvening)
    let fromMorning = scheduler.nextState(for: known, grade: .good, at: earlyMorning)
    check("the hour of the answer does not change the day it comes back",
          calendar.isDate(fromEvening.dueDate!, inSameDayAs: fromMorning.dueDate!))
    check("and it is waiting at the start of that day",
          fromEvening.dueDate == calendar.startOfDay(for: fromEvening.dueDate!))

    section("A library written by the algorithm this one replaced")

    let legacy = Data("""
    {"stage":"review","step":0,"intervalDays":40,"ease":1.9,
     "dueDate":"2026-03-10T00:00:00Z","reviewCount":7,"lapses":2,
     "firstReviewedAt":"2025-11-01T09:00:00Z","lastReviewedAt":"2026-01-29T09:00:00Z"}
    """.utf8)
    let carried = try! JSONDecoder.words.decode(SchedulingState.self, from: legacy)
    let promised = ISO8601DateFormatter().date(from: "2026-03-10T00:00:00Z")

    check("the interval a word had reached is what it knew", carried.stability == 40)
    check("its ease becomes a difficulty on the new scale",
          carried.difficulty > 1 && carried.difficulty < 10)
    check("a word the old algorithm found hard is a hard word here too",
          carried.difficulty > FSRS().converted(intervalDays: 40, ease: 2.6).difficulty)
    check("not one due date moves", carried.dueDate == promised)
    check("and no history is lost", carried.lapses == 2 && carried.reviewCount == 7)
    check("the same file always reads the same way",
          try! JSONDecoder.words.decode(SchedulingState.self, from: legacy).spread == carried.spread)

    let untouched = try! JSONDecoder.words.decode(SchedulingState.self, from: Data("""
    {"stage":"new","step":0,"intervalDays":0,"ease":2.5,"reviewCount":0,"lapses":0}
    """.utf8))
    check("a word never studied has nothing to carry over",
          untouched.stability == 0 && untouched.difficulty == 0)

    let rewritten = try! JSONEncoder().encode(carried)
    check("and the ease factor is not written back",
          !String(decoding: rewritten, as: UTF8.self).contains("ease"))

    section("A scheduler is a value, not a rule carved in")

    var straight = FSRSScheduler.Configuration()
    straight.learningSteps = []
    straight.spreadsIntervals = false
    let atOnce = FSRSScheduler(configuration: straight).nextState(for: fresh, grade: .good, at: now)
    check("a scheduler with no learning steps still answers",
          atOnce.stage == .review && atOnce.intervalDays == 2)
}
