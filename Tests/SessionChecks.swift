import Foundation

/// A library that never touches the disk, so a sitting can be run in a check.
actor MemoryPersistence: LibraryPersistence {
    private var stored = Library()
    private var media: [String: Data] = [:]

    func load() async throws -> Library { stored }
    func save(_ library: Library) async throws { stored = library }

    nonisolated func mediaURL(for relativePath: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: relativePath)
    }

    func importMedia(from source: URL, as name: String) async throws -> String {
        media[name] = try Data(contentsOf: source)
        return "Media/\(name)"
    }

    func writeMedia(_ data: Data, as name: String) async throws -> String {
        media[name] = data
        return "Media/\(name)"
    }

    func readMedia(at relativePath: String) async -> Data? {
        media[(relativePath as NSString).lastPathComponent]
    }

    func removeMedia(at relativePath: String) async {
        media[(relativePath as NSString).lastPathComponent] = nil
    }
}

/// The sitting itself: what each mode does with an answer, and the promise that
/// two of the three do nothing at all.
func checkSession() async {
    let today = moment(2026, 5, 6, 9)

    func makeStore() async -> (LibraryStore, LanguageProfile) {
        let store = LibraryStore(persistence: MemoryPersistence())
        await store.load()
        let profile = store.addProfile(name: "German", learningCode: "de", nativeCode: "en", dailyNewLimit: 10)
        for word in ["Haus", "Berg", "Fluss", "Wiese", "Brot"] {
            store.addEntry(profileID: profile.id, term: word, meaning: word.lowercased())
        }
        return (store, profile)
    }

    section("A sitting that counts")

    var (store, profile) = await makeStore()
    let session = StudySession(profile: profile, mode: .scheduled, store: store, now: today)

    check("it is built from what is ready", session.plannedCount == 5)
    check("and starts on the first card", session.currentEntry != nil)
    check("with the intervals its buttons will keep", session.intervalText(for: .good) == "15 m")

    let firstCard = session.current!
    session.answer(.good, at: today)
    check("an answer is written down", store.library.reviews.count == 1)
    check("it moved the card", store.library.entry(id: firstCard.entryID)?.recognitionCard?.scheduling.stage == .learning)
    check("a card still being learned comes back in the same sitting",
          session.remaining.contains(firstCard))
    check("so the sitting is not finished", !session.isFinished)
    check("and it is not counted as done", session.finishedCount == 0)

    section("Practice writes nothing into the schedule")

    let before = store.library.entry(id: firstCard.entryID)!.recognitionCard!.scheduling
    let reviewsBefore = store.library.reviews.count

    let practice = StudySession(profile: profile, mode: .practiceToday, store: store, now: today)
    check("today's practice is built from what was answered today", practice.plannedCount == 1)
    check("it says nothing about intervals", practice.intervalText(for: .good) == nil)

    practice.answer(.again, at: today.addingTimeInterval(60))
    let after = store.library.entry(id: firstCard.entryID)!.recognitionCard!.scheduling
    check("the card did not move", after == before)
    check("but the answer was recorded", store.library.reviews.count == reviewsBefore + 1)
    check("as practice", store.library.reviews.last?.isPractice == true)
    check("a card answered Again comes round again even here", !practice.isFinished)

    practice.answer(.good, at: today.addingTimeInterval(120))
    check("and is done when it comes back", practice.isFinished)
    check("with nothing rescheduled",
          store.library.entry(id: firstCard.entryID)!.recognitionCard!.scheduling == before)

    section("A sitting with no end")

    (store, profile) = await makeStore()
    let endless = StudySession(profile: profile, mode: .endless(.everything), store: store, now: today)

    check("it holds every word", endless.plannedCount == 5)
    check("and has no fraction to show", endless.progress == nil)

    // What the sitting shows next is drawn rather than queued — the weights
    // themselves are checked where they live, in `checkEndless`. What has to
    // be true here is that the drawing is wired up at all.
    let missed = endless.current!
    endless.answer(.again, at: today)
    check("answering brings up another word", endless.current != nil)
    check("and never the same one twice running", endless.current != missed)

    var shown: Set<UUID> = []
    for index in 0..<11 {
        shown.insert(endless.current!.cardID)
        endless.answer(.good, at: today.addingTimeInterval(Double(index)))
    }
    check("it never runs out", !endless.isFinished)
    check("every answer is counted", endless.answerCount == 12)
    check("the sitting knows how much of the language it has been over",
          endless.finishedCount == shown.union([missed.cardID]).count)
    check("which is never more than there is", endless.finishedCount <= endless.plannedCount)
    check("and none of it touched a schedule",
          store.library.entries.allSatisfy { $0.recognitionCard?.scheduling.isNew == true })
    check("though all of it was written down",
          store.library.reviews.count == 12 && store.library.reviews.allSatisfy(\.isPractice))

    section("Only words that have been seen")

    let seen = StudySession(profile: profile, mode: .endless(.seen), store: store, now: today)
    check("a language nobody has studied has nothing to go over", seen.plannedCount == 0)
}

/// Stopping in the middle of a sitting, and what has to be true when the
/// learner comes back to it — an hour later, and the next morning.
func checkResume() async {
    let today = moment(2026, 5, 6, 9)
    let tomorrow = moment(2026, 5, 7, 9)

    func makeStore() async -> (LibraryStore, LanguageProfile) {
        let store = LibraryStore(persistence: MemoryPersistence())
        await store.load()
        let profile = store.addProfile(name: "German", learningCode: "de", nativeCode: "en", dailyNewLimit: 10)
        for word in ["Haus", "Berg", "Fluss", "Wiese", "Brot", "Baum"] {
            store.addEntry(profileID: profile.id, term: word, meaning: word.lowercased())
        }
        return (store, profile)
    }

    section("A sitting that was stopped, not finished")

    let (store, profile) = await makeStore()
    let first = StudySession(profile: profile, mode: .scheduled, store: store, now: today)
    check("it starts with the day's cards", first.plannedCount == 6)
    check("and is not a sitting that was resumed", !first.isResumed)

    first.answer(.good, at: today)
    first.answer(.easy, at: today.addingTimeInterval(10))
    check("stopping half-way leaves the sitting written down", store.library.sessions.count == 1)

    let leftover = store.library.snapshot(profileID: profile.id, asOf: today)
    check("under today", leftover?.belongs(toDayOf: today) == true)
    check("with the work already done", leftover?.answerCount == 2)

    check("and the day is not reported as finished",
          store.library.counts(for: profile.id, asOf: today.addingTimeInterval(120)).total > 0)

    section("Coming back to it")

    let resumed = StudySession(profile: profile, mode: .scheduled, store: store, now: today.addingTimeInterval(300))
    check("it is picked up rather than begun", resumed.isResumed)
    check("with the same plan", resumed.plannedCount == 6)
    check("the same work behind it", resumed.answerCount == 2)
    check("and the same cards in front of it", resumed.remaining == first.remaining)
    check("the card answered Easy is not asked again", resumed.finishedCount == 1)

    section("A word deleted while the sitting was away")

    let doomed = resumed.remaining.last!
    store.deleteEntries(ids: [doomed.entryID])
    let afterDeletion = StudySession(profile: profile, mode: .scheduled, store: store, now: today.addingTimeInterval(600))
    check("it is not asked about", !afterDeletion.remaining.contains(doomed))
    check("and the count comes down with it", afterDeletion.plannedCount == 5)

    section("Tomorrow it is a new sitting")

    let nextDay = StudySession(profile: profile, mode: .scheduled, store: store, now: tomorrow)
    check("yesterday's sitting is not resumed", !nextDay.isResumed)

    // Five words are left in the language: one stopped part-way through
    // learning, one put off for four days, and three never started. Nothing
    // was skipped — the unfinished card is overdue and the untouched words are
    // still new.
    check("what was left unfinished is due again", nextDay.plannedCount == 4)

    nextDay.answer(.good, at: tomorrow)
    check("and writing today's sitting throws yesterday's away",
          store.library.sessions.count == 1 && store.library.snapshot(profileID: profile.id, asOf: today) == nil)

    section("A sitting that finishes leaves nothing behind")

    let (other, second) = await makeStore()
    let run = StudySession(profile: second, mode: .scheduled, store: other, now: today)
    var guardRail = 0
    while !run.isFinished, guardRail < 100 {
        run.answer(.easy, at: today.addingTimeInterval(Double(guardRail)))
        guardRail += 1
    }
    check("it ends", run.isFinished)
    check("with nothing left to come back to", other.library.sessions.isEmpty)

    section("An endless sitting is not kept")

    let stream = StudySession(profile: second, mode: .endless(.everything), store: other, now: today)
    stream.answer(.good, at: today)
    check("a stream has no place to return to", other.library.sessions.isEmpty)

    section("A mode survives being written down")

    let modes: [StudyMode] = [.scheduled, .practiceToday, .endless(.everything), .endless(.seen)]
    let data = try! JSONEncoder().encode(modes)
    check("every kind of sitting reads back as itself",
          (try? JSONDecoder().decode([StudyMode].self, from: data)) == modes)
}
