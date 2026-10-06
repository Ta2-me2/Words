import Foundation

/// A day's limit on reviews, and the extra a learner can ask for once the day
/// is done.
func checkDailyLimits() {
    let today = moment(2026, 5, 4, 9)
    let tomorrow = today.addingTimeInterval(86_400)
    let midnight = calendar.startOfDay(for: today)

    /// A word learned some time ago and due at `due`.
    func known(_ term: String, in profile: LanguageProfile, due: Date, deckID: UUID? = nil) -> Entry {
        var state = SchedulingState()
        state.stage = .review
        state.stability = 5
        state.difficulty = 5
        state.intervalDays = 5
        state.dueDate = due
        state.firstReviewedAt = today.addingTimeInterval(-10 * 86_400)
        state.lastReviewedAt = today.addingTimeInterval(-5 * 86_400)
        state.spread = 42
        return Entry(profileID: profile.id, deckID: deckID, term: term, meaning: term, cards: [Card(scheduling: state)])
    }

    func library(limit: Int?, due: Int, ahead: Int = 0, newWords: Int = 0, newLimit: Int = 20) -> (Library, LanguageProfile) {
        var library = Library()
        let profile = LanguageProfile(
            name: "German", learningCode: "de", nativeCode: "en",
            dailyNewLimit: newLimit, dailyReviewLimit: limit
        )
        library.upsert(profile)
        for index in 0..<due {
            library.upsert(known("fällig \(index)", in: profile, due: midnight.addingTimeInterval(-Double(index) * 3600)))
        }
        for index in 0..<ahead {
            library.upsert(known("bald \(index)", in: profile, due: midnight.addingTimeInterval(Double(index + 1) * 86_400)))
        }
        for index in 0..<newWords {
            library.upsert(Entry(profileID: profile.id, term: "neu \(index)", meaning: "new \(index)",
                                 createdAt: today.addingTimeInterval(Double(index))))
        }
        return (library, profile)
    }

    func due(_ queued: QueuedCard, in library: Library) -> Date {
        library.entry(id: queued.entryID)?.card(id: queued.cardID)?.scheduling.dueDate ?? .distantPast
    }

    func answer(_ queued: QueuedCard, _ grade: ReviewGrade, in library: inout Library, at date: Date = today) {
        library.recordReview(entryID: queued.entryID, cardID: queued.cardID, grade: grade, at: date, using: FSRSScheduler())
    }

    section("No limit on reviews, as before")

    let (open, free) = library(limit: nil, due: 8)
    check("every card that is due is asked", open.queue(for: free.id, asOf: today).count == 8)
    check("and counted", open.counts(for: free.id, asOf: today).due == 8)

    section("A limit on reviews")

    var capped: Library
    var learner: LanguageProfile
    (capped, learner) = library(limit: 5, due: 8)
    let firstFive = capped.queue(for: learner.id, asOf: today)
    check("only as many as the day allows", firstFive.count == 5)
    check("and the count agrees with the sitting", capped.counts(for: learner.id, asOf: today).due == 5)

    let asked = Set(firstFive.map(\.cardID))
    let waiting = capped.entries.flatMap(\.cards).filter { !asked.contains($0.id) }.compactMap(\.scheduling.dueDate)
    check("what is held back is what can best afford to wait",
          firstFive.map { due($0, in: capped) }.max()! <= waiting.min()!)

    answer(firstFive[0], .good, in: &capped)
    answer(firstFive[1], .good, in: &capped)
    check("each review answered is one fewer the day has room for",
          capped.counts(for: learner.id, asOf: today).due == 3)
    check("however many were waiting", capped.queue(for: learner.id, asOf: today).count == 3)

    section("Work already begun is never held back")

    (capped, learner) = library(limit: 2, due: 4)
    let pair = capped.queue(for: learner.id, asOf: today)
    answer(pair[0], .again, in: &capped)
    answer(pair[1], .good, in: &capped, at: today.addingTimeInterval(30))
    let afterLimit = capped.queue(for: learner.id, asOf: today.addingTimeInterval(60))
    check("with the limit spent, nothing new from earlier days comes in",
          afterLimit.count == 1)
    check("but a word forgotten this morning is not left half-learned",
          afterLimit.first?.cardID == pair[0].cardID)
    check("a word that lapses and comes back is one review, not several",
          StudyQueue.reviewAllowance(profile: learner, entries: capped.entries, asOf: today) == 0)

    check("tomorrow the limit starts again",
          capped.counts(for: learner.id, asOf: tomorrow).due == 2)

    section("A limit of nought")

    var silent: Library
    var resting: LanguageProfile
    (silent, resting) = library(limit: 0, due: 3, newWords: 1)
    check("takes on nothing from earlier days", silent.counts(for: resting.id, asOf: today).due == 0)
    let fresh = silent.queue(for: resting.id, asOf: today)
    check("but still starts new words", fresh.count == 1)
    answer(fresh[0], .good, in: &silent)
    check("and carries on with one met this morning",
          silent.queue(for: resting.id, asOf: today.addingTimeInterval(900)).count == 1)

    var leftover = SchedulingState()
    leftover.stage = .learning
    leftover.step = 1
    leftover.stability = 2
    leftover.difficulty = 5
    leftover.firstReviewedAt = today.addingTimeInterval(-86_400)
    leftover.lastReviewedAt = today.addingTimeInterval(-86_400)
    leftover.dueDate = today.addingTimeInterval(-86_400 + 900)
    silent.upsert(Entry(profileID: resting.id, term: "gestern", meaning: "yesterday", cards: [Card(scheduling: leftover)]))
    check("a word left half-learned yesterday counts as one of today's reviews",
          !silent.queue(for: resting.id, asOf: today).contains { silent.entry(id: $0.entryID)?.term == "gestern" })

    section("The limit belongs to the language, not the deck")

    var shelved = Library()
    let reader = LanguageProfile(name: "German", learningCode: "de", nativeCode: "en", dailyReviewLimit: 3)
    shelved.upsert(reader)
    let verbs = Deck(profileID: reader.id, name: "Verbs")
    let nouns = Deck(profileID: reader.id, name: "Nouns")
    shelved.upsert(verbs)
    shelved.upsert(nouns)
    for index in 0..<3 { shelved.upsert(known("gehen \(index)", in: reader, due: midnight, deckID: verbs.id)) }
    for index in 0..<3 { shelved.upsert(known("Haus \(index)", in: reader, due: midnight, deckID: nouns.id)) }
    for card in shelved.queue(for: reader.id, deckID: verbs.id, asOf: today) { answer(card, .good, in: &shelved) }
    check("three reviews in one deck spend the day's three",
          shelved.counts(for: reader.id, deckID: nouns.id, asOf: today).due == 0)

    section("More than today asked for")

    var keen: Library
    var eager: LanguageProfile
    (keen, eager) = library(limit: nil, due: 0, ahead: 6, newWords: 30, newLimit: 5)
    check("\"I want more\" waits while today's cards are still there",
          !keen.canStudyMore(for: eager.id, asOf: today))
    for card in keen.queue(for: eager.id, asOf: today) { answer(card, .easy, in: &keen) }
    check("the day is done", keen.counts(for: eager.id, asOf: today).total == 0)
    check("and then it is there to ask", keen.canStudyMore(for: eager.id, asOf: today))

    let (bare, nobody) = library(limit: nil, due: 0)
    check("but not in a language with nothing left to add",
          !bare.canStudyMore(for: nobody.id, asOf: today))

    let offer = keen.moreAvailable(for: eager.id, asOf: today)
    check("every word not yet started can be asked for", offer.newWords == 25)
    // Six learned on earlier days; the five answered this morning are not
    // offered — a word is not asked twice in one day.
    check("and every word learned before today, brought forward", offer.reviews.count == 6)
    check("soonest first", zip(offer.reviews, offer.reviews.dropFirst()).allSatisfy { due($0, in: keen) <= due($1, in: keen) })

    keen.addExtra(profileID: eager.id, newWords: 10, reviews: Array(offer.reviews.prefix(3)), asOf: today)
    let more = keen.queue(for: eager.id, asOf: today)
    check("ten more new words today", keen.counts(for: eager.id, asOf: today).new == 10)
    check("and three reviews brought forward", keen.counts(for: eager.id, asOf: today).due == 3)
    check("the sitting is exactly what the button says", more.count == keen.counts(for: eager.id, asOf: today).total)

    answer(more[0], .good, in: &keen)
    check("a card brought forward leaves the list by being answered",
          keen.counts(for: eager.id, asOf: today).due == 2)

    keen.addExtra(profileID: eager.id, newWords: 2, reviews: Array(offer.reviews.dropFirst(3).prefix(2)), asOf: today)
    check("asking again adds to what was asked", keen.counts(for: eager.id, asOf: today).due == 4)
    check("new words too", keen.counts(for: eager.id, asOf: today).new == 12)
    check("a card already in the list is not brought twice",
          keen.moreAvailable(for: eager.id, asOf: today).reviews.allSatisfy { card in
              !(keen.extra(for: eager.id, asOf: today)?.reviews.contains(card) ?? false)
          })

    check("tomorrow is an ordinary day", keen.counts(for: eager.id, asOf: tomorrow).new == 5)

    let stale = DailyExtra(profileID: eager.id, day: calendar.startOfDay(for: today.addingTimeInterval(-86_400)), newWords: 50)
    check("an extra from another day counts for nothing, even if it is handed in",
          StudyQueue.counts(profile: eager, entries: keen.entries, extra: stale, asOf: today).new
              == StudyQueue.counts(profile: eager, entries: keen.entries, asOf: today).new)

    keen.addExtra(profileID: eager.id, newWords: 1, reviews: [], asOf: tomorrow)
    check("and writing tomorrow's throws yesterday's away",
          keen.extras.count == 1 && keen.extras[0].belongs(toDayOf: tomorrow))

    section("What the limit held back comes first")

    var patient: Library
    var steady: LanguageProfile
    (patient, steady) = library(limit: 3, due: 6, ahead: 4)
    for card in patient.queue(for: steady.id, asOf: today) { answer(card, .good, in: &patient) }
    let behind = patient.moreAvailable(for: steady.id, asOf: today).reviews
    let isToday: (QueuedCard) -> Bool = { due($0, in: patient) <= today }
    check("first the three the limit kept back", behind.prefix(3).allSatisfy(isToday))
    check("then the words due in the coming days", !behind.dropFirst(3).contains(where: isToday))

    patient.addExtra(profileID: steady.id, newWords: 0, reviews: Array(behind.prefix(2)), asOf: today)
    check("asking for two of them lets two past the limit",
          patient.counts(for: steady.id, asOf: today).due == 2)

    section("Tomorrow's plan keeps to the limit")

    let (planned, sparing) = library(limit: 2, due: 0, ahead: 1)
    var busy = planned
    for index in 0..<4 { busy.upsert(known("morgen \(index)", in: sparing, due: calendar.startOfDay(for: tomorrow))) }
    check("five due tomorrow is two, if two is the limit",
          Insights.tomorrow(profile: sparing, entries: busy.entries, asOf: today).reviews == 2)

    section("Written down")

    let older = Data("""
    {"id":"\(UUID().uuidString)","name":"German","learningCode":"de","nativeCode":"en"}
    """.utf8)
    check("a language written before the limit existed has none",
          try! JSONDecoder.words.decode(LanguageProfile.self, from: older).dailyReviewLimit == nil)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let limited = LanguageProfile(name: "German", learningCode: "de", nativeCode: "en", dailyReviewLimit: 50)
    check("and one that has it keeps it",
          try! JSONDecoder.words.decode(LanguageProfile.self, from: encoder.encode(limited)).dailyReviewLimit == 50)
    check("a limit below nought is nought", LanguageProfile(name: "x", learningCode: "de", nativeCode: "en", dailyReviewLimit: -4).dailyReviewLimit == 0)

    let reread = try! JSONDecoder.words.decode(Library.self, from: encoder.encode(keen))
    check("today's extra survives closing the app", reread.extra(for: eager.id, asOf: tomorrow) != nil)
    check("a library written before extras existed has none",
          try! JSONDecoder.words.decode(Library.self, from: Data("{}".utf8)).extras.isEmpty)

    keen.removeProfile(id: eager.id)
    check("and deleting the language takes its extra with it", keen.extras.isEmpty)
}
