import Foundation

/// Practice: going over words again, and the promise that it costs nothing.
func checkPractice() async {
    let scheduler = FSRSScheduler()
    let today = moment(2026, 4, 8, 10)
    let yesterday = today.addingTimeInterval(-86_400)

    var library = Library()
    let german = LanguageProfile(name: "German", learningCode: "de", nativeCode: "en", dailyNewLimit: 3)
    let french = LanguageProfile(name: "French", learningCode: "fr", nativeCode: "en")
    library.upsert(german)
    library.upsert(french)

    let deck = Deck(profileID: german.id, name: "Nature")
    library.upsert(deck)

    let berg = Entry(profileID: german.id, deckID: deck.id, term: "Berg", meaning: "mountain",
                     createdAt: today.addingTimeInterval(1))
    let fluss = Entry(profileID: german.id, term: "Fluss", meaning: "river",
                      createdAt: today.addingTimeInterval(2))
    let wiese = Entry(profileID: german.id, term: "Wiese", meaning: "meadow",
                      createdAt: today.addingTimeInterval(3))
    for entry in [berg, fluss, wiese] { library.upsert(entry) }

    section("Today's cards, again")

    check("nothing has been studied, so there is nothing to repeat",
          library.practiceQueue(for: german.id, asOf: today).isEmpty)

    for card in library.queue(for: german.id, asOf: today) {
        library.recordReview(entryID: card.entryID, cardID: card.cardID, grade: .good, at: today, using: scheduler)
    }

    var repeatable = library.practiceQueue(for: german.id, asOf: today)
    check("everything answered today can be gone over again", repeatable.count == 3)

    // Answering one of them twice must not put it in the list twice.
    let bergCard = library.entry(id: berg.id)!.cards[0].id
    library.recordReview(entryID: berg.id, cardID: bergCard, grade: .good,
                         at: today.addingTimeInterval(700), using: scheduler)
    repeatable = library.practiceQueue(for: german.id, asOf: today)
    check("a card answered twice is still one card", repeatable.count == 3)

    check("yesterday's work is not today's",
          library.practiceQueue(for: german.id, asOf: today.addingTimeInterval(86_400)).isEmpty)
    check("a deck repeats only its own",
          library.practiceQueue(for: german.id, deckID: deck.id, asOf: today).count == 1)

    section("An answer that changes nothing")

    let before = library.entry(id: berg.id)!.recognitionCard!.scheduling
    var practised = library
    practised.recordPractice(entryID: berg.id, cardID: bergCard, grade: .again, at: today, seconds: 3)
    let after = practised.entry(id: berg.id)!.recognitionCard!.scheduling

    check("the stage is where it was", after.stage == before.stage)
    check("the interval is where it was", after.intervalDays == before.intervalDays)
    check("the date is where it was", after.dueDate == before.dueDate)
    check("nothing was counted as a lapse", after.lapses == before.lapses)
    check("but the answer is written down", practised.reviews.count == library.reviews.count + 1)
    check("marked as practice", practised.reviews.last?.isPractice == true)

    section("Practice is not progress")

    let summary = Insights.summary(entries: practised.entries, reviews: practised.reviews,
                                   profileID: german.id, asOf: today)
    check("it is not counted as an answer given", summary.reviews == 4)
    check("it does not become a lapse", summary.lapses == 0)
    check("it does not move the accuracy", summary.accuracy == 1)
    check("nor the day's activity",
          Insights.activity(reviews: practised.reviews, profileID: german.id, days: 7, asOf: today).last?.count == 4)
    check("nor the answer counts",
          Insights.grades(reviews: practised.reviews, profileID: german.id)
              .first { $0.grade == .again }?.count == 0)

    var practiceOnly = Library()
    practiceOnly.upsert(german)
    practiceOnly.upsert(french)
    practiceOnly.upsert(berg)
    practiceOnly.recordPractice(entryID: berg.id, cardID: berg.cards[0].id, grade: .good, at: today)
    check("a language that has only been practised has not been studied",
          Insights.studiedLanguageCount(profiles: practiceOnly.profiles, reviews: practiceOnly.reviews) == 0)

    section("A sitting with no end")

    let everything = library.endlessQueue(for: german.id, pool: .everything)
    check("everything means every word", everything.count == 3)

    var half = library
    half.upsert(Entry(profileID: german.id, term: "Baum", meaning: "tree"))
    check("a word never answered is not one I have seen",
          half.endlessQueue(for: german.id, pool: .seen).count == 3)
    check("but it is in everything", half.endlessQueue(for: german.id, pool: .everything).count == 4)
    check("a deck's endless sitting is its own",
          half.endlessQueue(for: german.id, deckID: deck.id, pool: .everything).count == 1)
    check("another language's words are never in it",
          half.endlessQueue(for: french.id, pool: .everything).isEmpty)

    section("A deck has its own appetite")

    var decked = Library()
    let profile = LanguageProfile(name: "German", learningCode: "de", nativeCode: "en", dailyNewLimit: 2)
    decked.upsert(profile)
    let serials = Deck(profileID: profile.id, name: "Serials", dailyNewLimit: 3)
    let travel = Deck(profileID: profile.id, name: "Travel")
    decked.upsert(serials)
    decked.upsert(travel)

    for index in 0..<5 {
        decked.upsert(Entry(profileID: profile.id, deckID: serials.id, term: "s\(index)", meaning: "s\(index)",
                            createdAt: today.addingTimeInterval(Double(index))))
        decked.upsert(Entry(profileID: profile.id, deckID: travel.id, term: "t\(index)", meaning: "t\(index)",
                            createdAt: today.addingTimeInterval(Double(index))))
    }

    check("a deck with its own limit uses it",
          decked.counts(for: profile.id, deckID: serials.id, asOf: today).new == 3)
    check("a deck without one follows the language",
          decked.counts(for: profile.id, deckID: travel.id, asOf: today).new == 2)

    for card in decked.queue(for: profile.id, deckID: serials.id, asOf: today) {
        decked.recordReview(entryID: card.entryID, cardID: card.cardID, grade: .good, at: today, using: scheduler)
    }

    check("what a deck spends is spent from that deck",
          decked.counts(for: profile.id, deckID: serials.id, asOf: today).new == 0)
    check("and another deck still has its own day",
          decked.counts(for: profile.id, deckID: travel.id, asOf: today).new == 2)
    check("the language as a whole has spent its limit",
          decked.counts(for: profile.id, asOf: today).new == 0)
    check("tomorrow the shelf offers what is left of it",
          decked.counts(for: profile.id, deckID: serials.id, asOf: today.addingTimeInterval(86_400)).new == 2)

    _ = yesterday
}
