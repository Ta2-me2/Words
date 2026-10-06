import Foundation

/// What a sitting is made of: what is asked first, how many new words a day may
/// start, and what happens when there is nothing left.
func checkQueue() {
    let scheduler = FSRSScheduler()
    let today = moment(2026, 3, 2, 9)

    func library(newWords: Int, limit: Int = 20) -> (Library, LanguageProfile) {
        var library = Library()
        let profile = LanguageProfile(name: "German", learningCode: "de", nativeCode: "en", dailyNewLimit: limit)
        library.upsert(profile)
        for index in 0..<newWords {
            library.upsert(
                Entry(
                    profileID: profile.id,
                    term: "Wort \(index)",
                    meaning: "word \(index)",
                    createdAt: today.addingTimeInterval(Double(index))
                )
            )
        }
        return (library, profile)
    }

    section("The day's allowance")

    var (small, profile) = library(newWords: 5, limit: 2)
    check("only as many new words as the day allows",
          small.queue(for: profile.id, asOf: today).count == 2)
    check("and the count agrees with the queue",
          small.counts(for: profile.id, asOf: today).new == 2)
    check("every word is still in the vocabulary",
          small.counts(for: profile.id, asOf: today).words == 5)

    let first = small.queue(for: profile.id, asOf: today)[0]
    small.recordReview(entryID: first.entryID, cardID: first.cardID, grade: .good, at: today, using: scheduler)
    check("starting one spends one of the day's allowance",
          small.counts(for: profile.id, asOf: today).new == 1)
    check("a word part-way through learning is still the day's work",
          small.counts(for: profile.id, asOf: today.addingTimeInterval(60)).due == 1)
    check("and is still there when its step comes round",
          small.counts(for: profile.id, asOf: today.addingTimeInterval(700)).due == 1)
    check("but it is not counted again the day after",
          small.counts(for: profile.id, asOf: today.addingTimeInterval(86_400)).due == 1)
    check("tomorrow the allowance is full again",
          small.counts(for: profile.id, asOf: today.addingTimeInterval(86_400)).new == 2)

    var (none, silent) = library(newWords: 3, limit: 0)
    check("a language that starts nothing new offers nothing new",
          none.counts(for: silent.id, asOf: today).new == 0)
    check("and its queue is empty", none.queue(for: silent.id, asOf: today).isEmpty)
    none.upsert(Entry(profileID: silent.id, term: "x", meaning: "y"))
    check("adding words does not change that",
          none.queue(for: silent.id, asOf: today).isEmpty)

    section("The order things are asked in")

    var mixed = Library()
    let learner = LanguageProfile(name: "German", learningCode: "de", nativeCode: "en")
    mixed.upsert(learner)

    func word(_ term: String, stage: LearningStage, due: Date?, interval: Double = 0) -> Entry {
        var state = SchedulingState()
        state.stage = stage
        state.dueDate = due
        state.intervalDays = interval
        state.firstReviewedAt = due.map { $0.addingTimeInterval(-86_400) }
        return Entry(
            profileID: learner.id,
            term: term,
            meaning: term,
            cards: [Card(scheduling: state)]
        )
    }

    mixed.upsert(word("new", stage: .new, due: nil))
    mixed.upsert(word("review-later", stage: .review, due: today.addingTimeInterval(-60), interval: 10))
    mixed.upsert(word("review-earlier", stage: .review, due: today.addingTimeInterval(-3600), interval: 10))
    mixed.upsert(word("learning", stage: .learning, due: today.addingTimeInterval(-30)))
    mixed.upsert(word("not-yet", stage: .review, due: today.addingTimeInterval(86_400), interval: 10))

    let queue = mixed.queue(for: learner.id, asOf: today)
    let terms = queue.compactMap { mixed.entry(id: $0.entryID)?.term }
    check("a card part-way through learning is asked first", terms.first == "learning")
    check("then reviews, oldest first",
          Array(terms.dropFirst().prefix(2)) == ["review-earlier", "review-later"])
    check("new words come last", terms.last == "new")
    check("nothing that is not due yet is in the sitting", !terms.contains("not-yet"))
    check("the counts say the same thing",
          mixed.counts(for: learner.id, asOf: today).due == 3)

    section("When there is nothing to do")

    var quiet = Library()
    let rested = LanguageProfile(name: "German", learningCode: "de", nativeCode: "en")
    quiet.upsert(rested)
    var state = SchedulingState()
    state.stage = .review
    state.intervalDays = 3
    state.dueDate = today.addingTimeInterval(3 * 86_400)
    state.firstReviewedAt = today
    quiet.upsert(Entry(profileID: rested.id, term: "Haus", meaning: "house", cards: [Card(scheduling: state)]))

    check("an up-to-date language has an empty queue",
          quiet.queue(for: rested.id, asOf: today).isEmpty)
    check("and says so", quiet.counts(for: rested.id, asOf: today).isEmpty)
    check("it can still say when the next word is due",
          quiet.nextDueDate(for: rested.id, after: today) == state.dueDate)
    check("a language with nothing scheduled says nothing",
          Library().nextDueDate(for: UUID(), after: today) == nil)
}
