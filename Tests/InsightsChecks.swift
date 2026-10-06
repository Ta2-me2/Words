import Foundation

/// The numbers the home and statistics screens show. Every one of them is
/// counted here rather than in a view, so every one of them can be checked.
func checkInsights() {
    let scheduler = FSRSScheduler()
    let today = moment(2026, 3, 12, 9)

    var library = Library()
    let german = LanguageProfile(name: "German", learningCode: "de", nativeCode: "en", dailyNewLimit: 3)
    let french = LanguageProfile(name: "French", learningCode: "fr", nativeCode: "en")
    library.upsert(german)
    library.upsert(french)

    /// A card in a given state, so the counts have something with a history.
    func word(_ term: String, profile: LanguageProfile, stage: LearningStage,
              due: Date?, interval: Double = 0, lapses: Int = 0, difficulty: Double = 5,
              firstSeen: Date? = nil) -> Entry {
        var state = SchedulingState()
        state.stage = stage
        state.dueDate = due
        state.intervalDays = interval
        state.lapses = lapses
        state.difficulty = difficulty
        state.firstReviewedAt = firstSeen
        return Entry(profileID: profile.id, term: term, meaning: term, cards: [Card(scheduling: state)])
    }

    section("The day's plan")

    let longAgo = today.addingTimeInterval(-30 * 86_400)
    library.upsert(word("überfällig", profile: german, stage: .review, due: today.addingTimeInterval(-3600), interval: 5, firstSeen: longAgo))
    library.upsert(word("morgen", profile: german, stage: .review, due: today.addingTimeInterval(86_400), interval: 3, firstSeen: longAgo))
    library.upsert(word("übermorgen", profile: german, stage: .review, due: today.addingTimeInterval(3 * 86_400), interval: 9, firstSeen: longAgo))
    for index in 0..<5 {
        library.upsert(Entry(profileID: german.id, term: "neu \(index)", meaning: "new \(index)",
                             createdAt: today.addingTimeInterval(Double(index))))
    }

    let plan = Insights.today(profile: german, entries: library.entries, asOf: today)
    check("today asks for what is ready", plan.reviews == 1)
    check("and for the day's allowance of new words", plan.newWords == 3)
    check("which is what the sitting holds",
          library.queue(for: german.id, asOf: today).count == plan.total)

    let next = Insights.tomorrow(profile: german, entries: library.entries, asOf: today)
    check("tomorrow asks for what is scheduled for tomorrow", next.reviews == 1)
    check("and for what is left of the new words, capped by the day's limit",
          next.newWords == 2)
    check("a day further out is not tomorrow's problem", next.total == 3)

    section("Activity")

    // Three sittings: today, yesterday, and a fortnight ago.
    var busy = library
    let card = busy.queue(for: german.id, asOf: today)[0]
    for _ in 0..<4 {
        busy.reviews.append(ReviewRecord(profileID: german.id, entryID: card.entryID, cardID: card.cardID,
                                         reviewedAt: today, grade: .good, stageBefore: .review, stageAfter: .review,
                                         intervalBeforeDays: 5, intervalAfterDays: 12, dueAfter: today))
    }
    busy.reviews.append(ReviewRecord(profileID: german.id, entryID: card.entryID, cardID: card.cardID,
                                     reviewedAt: today.addingTimeInterval(-86_400), grade: .again,
                                     stageBefore: .review, stageAfter: .relearning,
                                     intervalBeforeDays: 10, intervalAfterDays: 5, dueAfter: today))
    busy.reviews.append(ReviewRecord(profileID: french.id, entryID: card.entryID, cardID: card.cardID,
                                     reviewedAt: today, grade: .good, stageBefore: .new, stageAfter: .learning,
                                     intervalBeforeDays: 0, intervalAfterDays: 0, dueAfter: today))

    let days = Insights.activity(reviews: busy.reviews, profileID: german.id, days: 30, asOf: today)
    check("a day is asked for every day in the window", days.count == 30)
    check("the last day is today", calendar.isDate(days.last!.date, inSameDayAs: today))
    check("today is counted", days.last?.count == 4)
    check("and it is the busiest shade", days.last?.level == 4)
    check("a quieter day is a quieter shade", days[days.count - 2].level == 1)
    check("a day with nothing on it has no shade", days[0].level == 0)
    check("another language's answers are not counted here", days.last?.count == 4)
    check("asked across all languages, they are",
          Insights.activity(reviews: busy.reviews, profileID: nil, days: 30, asOf: today).last?.count == 5)

    check("a first review is always visible", Insights.level(1, busiest: 1) == 4)
    check("nothing is nothing", Insights.level(0, busiest: 9) == 0)

    section("Where the language stands")

    var counted = library
    counted.upsert(word("alt", profile: german, stage: .review, due: today, interval: 40, lapses: 2, difficulty: 7.5, firstSeen: longAgo))
    counted.upsert(word("lernend", profile: german, stage: .learning, due: today, firstSeen: longAgo))
    counted.reviews = busy.reviews

    let summary = Insights.summary(entries: counted.entries, reviews: counted.reviews,
                                   profileID: german.id, asOf: today)
    check("every word is counted", summary.words == 10)
    check("the ones on an interval are known", summary.known == 4)
    check("the ones past three weeks are known well", summary.mature == 1)
    check("the ones part way through are learning", summary.learning == 1)
    check("the untouched ones are not started", summary.newWords == 5)
    check("answers are counted", summary.reviews == 5)
    check("today's answers are counted separately", summary.reviewsToday == 4)
    check("a lapse is counted", summary.lapses == 1)
    check("accuracy is the share that were not Again",
          summary.accuracy.map { abs($0 - 0.8) < 0.001 } == true)
    check("a language with no answers has no accuracy to report",
          Insights.summary(entries: counted.entries, reviews: [], profileID: german.id, asOf: today).accuracy == nil)
    check("the daily average counts the empty days too",
          abs(summary.averagePerDay - 5.0 / 30.0) < 0.001)

    section("Words that will not stick")

    let hard = Insights.difficult(entries: counted.entries, profileID: german.id)
    check("a word that has been forgotten is listed", hard.count == 1)
    check("with the count of times", hard.first?.lapses == 2)
    check("a word that has never been forgotten is not",
          !hard.contains { $0.entry.term == "überfällig" })

    var many = counted
    many.upsert(word("schwer", profile: german, stage: .review, due: today, interval: 2, lapses: 5, difficulty: 9.2, firstSeen: longAgo))
    many.upsert(word("mittel", profile: german, stage: .review, due: today, interval: 4, lapses: 3, difficulty: 6.0, firstSeen: longAgo))
    let ranked = Insights.difficult(entries: many.entries, profileID: german.id, limit: 2)
    check("the worst come first", ranked.map(\.entry.term) == ["schwer", "mittel"])
    check("and no more than asked for", ranked.count == 2)

    section("What is coming")

    let forecast = Insights.forecast(entries: library.entries, profileID: german.id, days: 14, asOf: today)
    check("a column for every day asked for", forecast.count == 14)
    check("what is overdue is met on the first day", forecast[0].count == 1)
    check("tomorrow's card is on tomorrow", forecast[1].count == 1)
    check("and the one after on its own day", forecast[3].count == 1)
    check("a day with nothing due is a day with nothing due", forecast[2].count == 0)
    check("new words are not a forecast: they are a choice",
          forecast.reduce(0) { $0 + $1.count } == 3)

    section("Across languages")

    let grades = Insights.grades(reviews: busy.reviews, profileID: german.id)
    check("every answer has a bar, even at nought", grades.count == 4)
    check("counted correctly", grades.first { $0.grade == .good }?.count == 4)

    let totals = Insights.totals(profiles: library.profiles, entries: library.entries,
                                 reviews: busy.reviews, asOf: today)
    check("every language is in the summary", totals.count == 2)
    check("with its words", totals.first { $0.profile.id == german.id }?.words == 8)
    check("and its week", totals.first { $0.profile.id == german.id }?.reviewsThisWeek == 5)

    check("one language studied is not a comparison",
          Insights.studiedLanguageCount(profiles: library.profiles, reviews: [busy.reviews[0]]) == 1)
    check("two are", Insights.studiedLanguageCount(profiles: library.profiles, reviews: busy.reviews) == 2)
    check("a language nobody has studied does not count",
          Insights.studiedLanguageCount(profiles: library.profiles, reviews: []) == 0)

    _ = scheduler
}
