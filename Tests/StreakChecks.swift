import Foundation

/// Days in a row, and the two a week that may be frozen.
func checkStreak() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    calendar.firstWeekday = 2   // Monday, as most of the world counts a week.

    func day(_ number: Int, _ hour: Int = 18) -> Date {
        // June 2026: the 1st is a Monday.
        calendar.date(from: DateComponents(year: 2026, month: 6, day: number, hour: hour))!
    }

    let profileID = UUID()
    func answer(on date: Date, practice: Bool = false, language: UUID? = nil) -> ReviewRecord {
        ReviewRecord(
            profileID: language ?? profileID, entryID: UUID(), cardID: UUID(),
            reviewedAt: date, grade: .good, stageBefore: .review, stageAfter: .review,
            intervalBeforeDays: 1, intervalAfterDays: 2, dueAfter: nil, isPractice: practice
        )
    }

    section("A streak is days in a row")

    var status = Streak.status(reviews: [], freezes: [], asOf: day(3), calendar: calendar)
    check("nothing studied is no streak", status.length == 0)
    check("and there is nothing for a freeze to keep", !status.canFreezeToday)

    let three = [answer(on: day(1)), answer(on: day(2)), answer(on: day(3, 8))]
    status = Streak.status(reviews: three, freezes: [], asOf: day(3, 20), calendar: calendar)
    check("three days running is three", status.length == 3)
    check("today counts once something is answered", status.studiedToday)

    status = Streak.status(reviews: Array(three.prefix(2)), freezes: [], asOf: day(3, 20), calendar: calendar)
    check("a day not yet studied does not break it yet", status.length == 2)
    check("and says it is still waiting", !status.studiedToday && status.week[2].state == .today)

    status = Streak.status(reviews: Array(three.prefix(2)), freezes: [], asOf: day(4, 9), calendar: calendar)
    check("a whole day missed ends it", status.length == 0)

    let many = [answer(on: day(1)), answer(on: day(1, 19)), answer(on: day(1, 20))]
    check("several answers in a day are one day",
          Streak.status(reviews: many, freezes: [], asOf: day(1, 21), calendar: calendar).length == 1)

    let practice = [answer(on: day(1)), answer(on: day(2), practice: true)]
    check("practice counts, even a single card of it",
          Streak.status(reviews: practice, freezes: [], asOf: day(2, 21), calendar: calendar).length == 2)

    let languages = [answer(on: day(1)), answer(on: day(2), language: UUID())]
    check("and so does any language", Streak.status(reviews: languages, freezes: [], asOf: day(2, 21), calendar: calendar).length == 2)

    section("A frozen day keeps the streak without adding to it")

    let studied = [answer(on: day(1)), answer(on: day(2)), answer(on: day(3))]
    status = Streak.status(reviews: studied, freezes: [], asOf: day(4, 9), calendar: calendar)
    check("a day with a streak behind it can be frozen", status.canFreezeToday)
    check("with two freezes to the week", status.freezesLeft == 2)

    status = Streak.status(reviews: studied, freezes: [day(4, 0)], asOf: day(4, 12), calendar: calendar)
    check("frozen today, the streak stays at three", status.length == 3)
    check("and says so", status.frozenToday && status.week[3].state == .frozen)
    check("one freeze is spent", status.freezesLeft == 1)
    check("today cannot be frozen twice", !status.canFreezeToday)

    status = Streak.status(reviews: studied + [answer(on: day(5))], freezes: [day(4, 0)], asOf: day(5, 20), calendar: calendar)
    check("the day after, studying carries it on to four", status.length == 4)

    status = Streak.status(reviews: studied, freezes: [day(4, 0)], asOf: day(5, 20), calendar: calendar)
    check("a frozen yesterday still holds while today is open", status.length == 3)

    status = Streak.status(reviews: studied, freezes: [day(4, 0)], asOf: day(6, 9), calendar: calendar)
    check("but a day after it that was neither ends it", status.length == 0)

    status = Streak.status(reviews: studied, freezes: [day(4, 0), day(5, 0)], asOf: day(6, 9), calendar: calendar)
    check("two frozen days in a row are both kept", status.length == 3)
    check("and that is the week's two", status.freezesLeft == 0)
    check("so a third cannot be had", !status.canFreezeToday)

    status = Streak.status(reviews: studied + [answer(on: day(4, 15))], freezes: [day(4, 0)], asOf: day(4, 16), calendar: calendar)
    check("a frozen day that was studied after all counts as studied", status.length == 4)
    check("and gives its freeze back", status.freezesLeft == 2)
    check("it is not reported as frozen", !status.frozenToday)

    section("Freezes are a week's")

    let lastWeek = (3...7).map { answer(on: day($0)) }
    status = Streak.status(reviews: lastWeek, freezes: [day(4, 0), day(5, 0)], asOf: day(8, 9), calendar: calendar)
    check("a new week starts with two again", status.freezesLeft == 2)
    check("and its row starts on its first day", calendar.isDate(status.week[0].date, inSameDayAs: day(8)))
    check("seven days long", status.week.count == 7)
    check("with the days to come still to come", status.week[6].state == .ahead)

    section("Freezing, in the library")

    var library = Library()
    library.reviews = studied
    library.freezeStreak(asOf: day(4, 10), calendar: calendar)
    check("a freeze is kept", library.streakFreezes.count == 1)
    library.freezeStreak(asOf: day(4, 11), calendar: calendar)
    check("asking again the same day keeps one", library.streakFreezes.count == 1)
    library.unfreezeStreak(asOf: day(4, 12), calendar: calendar)
    check("and it can be taken back", library.streakFreezes.isEmpty)

    var empty = Library()
    empty.freezeStreak(asOf: day(4, 10), calendar: calendar)
    check("with no streak there is nothing to freeze", empty.streakFreezes.isEmpty)

    library.freezeStreak(asOf: day(4, 10), calendar: calendar)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let round = try! JSONDecoder.words.decode(Library.self, from: try! encoder.encode(library))
    check("freezes survive being saved", round.streakFreezes.count == 1)
    let old = try! JSONDecoder.words.decode(Library.self, from: Data(#"{"profiles":[]}"#.utf8))
    check("a library from before streaks opens with none", old.streakFreezes.isEmpty)
}
