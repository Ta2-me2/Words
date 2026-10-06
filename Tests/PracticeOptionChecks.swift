import Foundation

/// The choices a learner makes about how a sitting goes: which new words come
/// first, which way round the cards are asked, and what Easy means on a word
/// seen for the first time.
func checkPracticeOptions() async {
    let today = moment(2026, 6, 1, 9)
    let scheduler = FSRSScheduler()

    func library(words: Int, limit: Int, order: NewWordOrder) -> (Library, LanguageProfile) {
        var library = Library()
        let profile = LanguageProfile(
            name: "German", learningCode: "de", nativeCode: "en",
            dailyNewLimit: limit, newWordOrder: order
        )
        library.upsert(profile)
        for index in 0..<words {
            library.upsert(Entry(
                profileID: profile.id,
                term: "Wort \(index)",
                meaning: "word \(index)",
                createdAt: today.addingTimeInterval(Double(index))
            ))
        }
        return (library, profile)
    }

    func terms(_ library: Library, _ queue: [QueuedCard]) -> [String] {
        queue.compactMap { library.entry(id: $0.entryID)?.term }
    }

    section("New words in the order they were added")

    let (ordered, orderedProfile) = library(words: 60, limit: 10, order: .added)
    check("the first ten added come first",
          terms(ordered, ordered.queue(for: orderedProfile.id, asOf: today)) == (0..<10).map { "Wort \($0)" })

    section("New words in random order")

    var (shuffled, shuffledProfile) = library(words: 60, limit: 10, order: .random)
    let morning = shuffled.queue(for: shuffledProfile.id, asOf: today)
    check("still only the day's allowance", morning.count == 10)
    check("not simply the first ten added",
          terms(shuffled, morning) != (0..<10).map { "Wort \($0)" })
    check("drawn from the whole list, not the start of it",
          terms(shuffled, morning).contains { Int($0.dropFirst(5))! >= 30 })
    check("the same words all day, so a sitting begun again goes on with them",
          shuffled.queue(for: shuffledProfile.id, asOf: today.addingTimeInterval(5 * 3600)) == morning)
    check("and different ones the next day",
          shuffled.queue(for: shuffledProfile.id, asOf: today.addingTimeInterval(86_400)) != morning)
    check("the count on the button agrees", shuffled.counts(for: shuffledProfile.id, asOf: today).new == 10)

    let started = morning[0]
    shuffled.recordReview(entryID: started.entryID, cardID: started.cardID, grade: .good, at: today, using: scheduler)
    let later = shuffled.queue(for: shuffledProfile.id, asOf: today.addingTimeInterval(60))
    check("a word started is not started twice",
          later.filter { $0 == started }.count == 1)
    check("and the rest of the day's words are the ones it drew",
          Set(later.map(\.cardID)).isSuperset(of: Set(morning.dropFirst().map(\.cardID))))

    section("Which way round a card is asked")

    let cards = (0..<200).map { _ in UUID() }
    check("the usual way shows the word",
          cards.allSatisfy { StudyDirection.wordToMeaning.prompt(for: $0, seed: 7) == .word })
    check("turned around, the meaning",
          cards.allSatisfy { StudyDirection.meaningToWord.prompt(for: $0, seed: 7) == .meaning })
    let mixed = cards.map { StudyDirection.mixed.prompt(for: $0, seed: 7) }
    let turned = mixed.count { $0 == .meaning }
    check("mixed asks about half of them each way", (70...130).contains(turned))
    check("and the same card the same way every time in one sitting",
          cards.map { StudyDirection.mixed.prompt(for: $0, seed: 7) } == mixed)
    check("while another sitting draws again",
          cards.map { StudyDirection.mixed.prompt(for: $0, seed: 8) } != mixed)

    let store = LibraryStore(persistence: MemoryPersistence())
    await store.load()
    var profile = store.addProfile(name: "German", learningCode: "de", nativeCode: "en")
    store.addEntry(profileID: profile.id, term: "Haus", meaning: "house")
    profile.studyDirection = .meaningToWord
    store.save(profile)
    let turnedSession = StudySession(profile: store.library.profile(id: profile.id)!, mode: .scheduled, store: store, now: today)
    check("a sitting takes its direction from the language", turnedSession.direction == .meaningToWord)
    check("and shows the meaning first", turnedSession.currentPrompt == .meaning)

    section("Easy on a word never seen before")

    let firstSight = StudySession(profile: store.library.profile(id: profile.id)!, mode: .scheduled, store: store, now: today)
    check("is offered as knowing the word", firstSight.title(for: .easy) == "I Know This Word")
    check("the other buttons keep their names", firstSight.title(for: .good) == "Good")
    let promise = firstSight.intervalText(for: .easy, at: today) ?? ""
    check("and it promises about a month", ["28 d", "29 d", "30 d", "1 mo"].contains(promise))

    let practice = StudySession(profile: store.library.profile(id: profile.id)!, mode: .endless(.everything), store: store, now: today)
    check("practice changes nothing, so it promises nothing either", practice.title(for: .easy) == "Easy")

    let word = firstSight.current!
    firstSight.answer(.easy, at: today)
    let known = store.library.entry(id: word.entryID)!.card(id: word.cardID)!.scheduling
    check("the word goes straight to review", known.stage == .review)
    check("a month out", (28...33).contains(Int(known.intervalDays)))
    check("which counts it as known well", known.intervalDays >= 21)
    check("with the memory of an easy word", known.difficulty == FSRS().initialDifficulty(.easy))
    check("and the answer is written down as Easy", store.library.reviews.last?.grade == .easy)

    var fresh = SchedulingState()
    fresh.spread = 42
    let careful = scheduler.nextState(for: fresh, grade: .easy, at: today, retention: 0.95)
    let relaxed = scheduler.nextState(for: fresh, grade: .easy, at: today, retention: 0.85)
    check("a month whatever the learner's retention",
          careful.intervalDays == relaxed.intervalDays)
    check("which a stricter goal reaches by believing in a stronger memory",
          careful.stability > relaxed.stability)

    let dates = Set((0..<40).map { index -> Date? in
        var state = SchedulingState()
        state.spread = UInt64(index) &* 0x9E37_79B9_7F4A_7C15
        return scheduler.nextState(for: state, grade: .easy, at: today).dueDate
    })
    check("forty words known on the same day do not all come back on the same day", dates.count > 1)

    let firstAgain = scheduler.nextState(for: fresh, grade: .again, at: today)
    let easyAfterward = scheduler.nextState(for: firstAgain, grade: .easy, at: today.addingTimeInterval(180))
    check("once a word has had any other answer, Easy is the ordinary Easy",
          easyAfterward.intervalDays < 21)

    let secondSight = StudySession(profile: store.library.profile(id: profile.id)!, mode: .scheduled, store: store, now: today)
    check("and a word already answered is not offered as unseen", secondSight.current == nil || !secondSight.isFirstSight)

    let due = known.dueDate!
    let forgotten = scheduler.nextState(for: known, grade: .again, at: due)
    check("a word that was not known after all lapses like any other",
          forgotten.stage == .relearning && forgotten.lapses == 1)
    let remembered = scheduler.nextState(for: known, grade: .good, at: due)
    check("and one that was known waits longer still", remembered.intervalDays > known.intervalDays)

    section("Old languages")

    let old = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"German","learningCode":"de","nativeCode":"ru"}"#
    let decoded = try? JSONDecoder.words.decode(LanguageProfile.self, from: Data(old.utf8))
    check("start new words in the order they were added", decoded?.newWordOrder == .added)
    check("and ask cards the usual way round", decoded?.studyDirection == .wordToMeaning)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    var chosen = LanguageProfile(name: "German", learningCode: "de", nativeCode: "ru")
    chosen.newWordOrder = .random
    chosen.studyDirection = .mixed
    let round = try! JSONDecoder.words.decode(LanguageProfile.self, from: try! encoder.encode(chosen))
    check("both choices survive being saved", round.newWordOrder == .random && round.studyDirection == .mixed)
}
