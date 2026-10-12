import Foundation

/// What the schedule promised against what actually came back.
///
/// The figure is only worth showing if it counts the right answers, so most of
/// these checks are about what is left out: practice, learning steps, and the
/// other language's reviews.
func checkRetention() {
    let german = LanguageProfile(name: "German", learningCode: "de", nativeCode: "en")
    let french = LanguageProfile(name: "French", learningCode: "fr", nativeCode: "en")
    let today = moment(2026, 10, 12, 9)

    var reviews: [ReviewRecord] = []

    /// One answer, as the study session would have written it down.
    func answer(
        _ grade: ReviewGrade,
        waited: Double,
        at date: Date = today,
        stage: LearningStage = .review,
        practice: Bool = false,
        profile: LanguageProfile? = nil,
        card: UUID = UUID()
    ) {
        reviews.append(ReviewRecord(
            profileID: (profile ?? german).id,
            entryID: card,
            cardID: card,
            reviewedAt: date,
            grade: grade,
            stageBefore: stage,
            stageAfter: grade == .again ? .relearning : .review,
            intervalBeforeDays: waited,
            intervalAfterDays: waited * 2,
            dueAfter: date,
            isPractice: practice
        ))
    }

    section("What counts as remembering")

    answer(.good, waited: 5)
    answer(.again, waited: 5)
    answer(.hard, waited: 5)
    answer(.easy, waited: 5)

    var periods = TrueRetention.periods(reviews: reviews, profileID: german.id, asOf: today)
    var all = periods.first { $0.span == .all }!.all
    check("every answer that is not Again is remembered", all.remembered == 3)
    check("and Again is the only one that is not", all.forgotten == 1)
    check("so three in four came back", all.share == 0.75)

    answer(.again, waited: 5, practice: true)
    answer(.again, waited: 0, stage: .new)
    answer(.again, waited: 0, stage: .learning)
    answer(.again, waited: 3, stage: .relearning)
    answer(.again, waited: 5, profile: french)

    periods = TrueRetention.periods(reviews: reviews, profileID: german.id, asOf: today)
    all = periods.first { $0.span == .all }!.all
    check("practice is not a memory being tested", all.total == 4)
    check("nor is a word being met for the first time", all.forgotten == 1)
    check("nor a learning step, nor a word being got back",
          TrueRetention.counts(reviews[6]) == false && TrueRetention.counts(reviews[7]) == false)
    check("and another language is another language", all.remembered == 3)

    check("nothing counted is not nought per cent", RecallCount().share == nil)

    section("Young and known apart")

    reviews = []
    answer(.good, waited: 20)
    answer(.again, waited: 20)
    answer(.good, waited: 21)
    answer(.good, waited: 400)

    periods = TrueRetention.periods(reviews: reviews, profileID: german.id, asOf: today)
    let span = periods.first { $0.span == .all }!
    check("under three weeks is a young card", span.young.total == 2)
    check("three weeks is already a known one", span.mature.total == 2)
    check("each is counted on its own", span.young.share == 0.5 && span.mature.share == 1)

    section("Over time")

    reviews = []
    answer(.good, waited: 5)
    answer(.again, waited: 5, at: today.addingTimeInterval(-86_400))
    answer(.good, waited: 5, at: today.addingTimeInterval(-5 * 86_400))
    answer(.good, waited: 5, at: today.addingTimeInterval(-40 * 86_400))
    answer(.again, waited: 5, at: today.addingTimeInterval(-400 * 86_400))

    periods = TrueRetention.periods(reviews: reviews, profileID: german.id, asOf: today)
    func total(_ wanted: RetentionSpan) -> Int { periods.first { $0.span == wanted }!.all.total }
    check("today is today", total(.today) == 1)
    check("yesterday is only yesterday", total(.yesterday) == 1)
    check("a week holds both and the days between", total(.week) == 3)
    check("a month holds the last five weeks", total(.month) == 3)
    check("a year holds everything inside it", total(.year) == 4)
    check("and all time holds the lot", total(.all) == 5)

    section("How long the word waited")

    reviews = []
    answer(.good, waited: 1)
    answer(.good, waited: 3)
    answer(.again, waited: 7)
    answer(.good, waited: 14)
    answer(.good, waited: 30)
    answer(.again, waited: 200)

    let bands = TrueRetention.bands(reviews: reviews, profileID: german.id)
    func band(_ wait: RetentionWait) -> RecallCount { bands.first { $0.wait == wait }!.count }
    check("every band is there, even the empty ones", bands.count == RetentionWait.allCases.count)
    check("the first days are one band", band(.days1to3).total == 2)
    check("the first week another", band(.days4to7).total == 1)
    check("then up to three weeks", band(.weeks1to3).total == 1)
    check("then up to three months", band(.weeks3toMonths3).total == 1)
    check("and everything beyond", band(.beyond).total == 1)
    check("a band where everything was forgotten is nought", band(.days4to7).share == 0)

    let quiet = TrueRetention.bands(reviews: [], profileID: german.id)
    check("a band with nothing in it says nothing rather than nought",
          quiet.count == RetentionWait.allCases.count && quiet.allSatisfy { $0.count.share == nil })

    section("Enough to judge")

    reviews = []
    for _ in 0..<40 { answer(.good, waited: 5, at: today.addingTimeInterval(-200 * 86_400)) }
    for _ in 0..<3 { answer(.again, waited: 5) }
    periods = TrueRetention.periods(reviews: reviews, profileID: german.id, asOf: today)
    check("a headline is not built from three answers",
          TrueRetention.headline(periods)?.span == .year)

    reviews = []
    for _ in 0..<40 { answer(.good, waited: 5) }
    periods = TrueRetention.periods(reviews: reviews, profileID: german.id, asOf: today)
    check("but the last month is preferred once it has enough",
          TrueRetention.headline(periods)?.span == .month)

    check("and nothing at all has no headline",
          TrueRetention.headline(TrueRetention.periods(reviews: [], profileID: german.id, asOf: today)) == nil)

    section("The words already known")

    reviews = []
    let known = UUID(), knownBack = UUID(), knownLost = UUID(), ordinary = UUID()
    answer(.easy, waited: 0, at: today.addingTimeInterval(-30 * 86_400), stage: .new, card: known)
    answer(.easy, waited: 0, at: today.addingTimeInterval(-40 * 86_400), stage: .new, card: knownBack)
    answer(.good, waited: 30, at: today, card: knownBack)
    answer(.easy, waited: 0, at: today.addingTimeInterval(-40 * 86_400), stage: .new, card: knownLost)
    answer(.again, waited: 30, at: today, card: knownLost)
    answer(.good, waited: 0, at: today.addingTimeInterval(-40 * 86_400), stage: .new, card: ordinary)
    answer(.good, waited: 5, at: today, card: ordinary)

    let declared = TrueRetention.declaredKnown(reviews: reviews, profileID: german.id)
    check("a word declared known on sight is counted", declared.declared == 3)
    check("one that has not come back yet is still waiting", declared.waiting == 1)
    check("and the two that did are weighed", declared.count.total == 2)
    check("one of them kept", declared.count.remembered == 1)
    check("one of them not", declared.count.forgotten == 1)
    check("a word that was merely answered Good is none of this business",
          TrueRetention.declaredKnown(reviews: reviews.suffix(2).map { $0 }, profileID: german.id).declared == 0)
}
