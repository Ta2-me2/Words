import Foundation

/// The whole loop as the app runs it: a language, a word, a session, an answer,
/// and the same schedule waiting after a restart.
func checkStore() async {
    let fileManager = FileManager.default
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appending(path: "words-store-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? fileManager.removeItem(at: root) }

    let fileURL = root.appending(path: "Library.json")
    let now = moment(2026, 3, 2, 9)

    section("The learning loop")

    let store = LibraryStore(persistence: FileLibraryPersistence(fileURL: fileURL))
    await store.load()
    check("a new library opens ready", store.loadState == .ready)
    check("with nothing in it", store.library.isEmpty)

    let profile = store.addProfile(name: "German", learningCode: "de", nativeCode: "en")
    check("a language can be created", store.library.profiles.count == 1)
    check("it is named", store.library.profiles[0].displayName == "German")
    check("and reads as a pair of languages", profile.languagePair == "German → English")

    check("a word needs both halves",
          store.addEntry(profileID: profile.id, term: "Haus", meaning: "  ") == nil)
    check("and neither may be blank",
          store.addEntry(profileID: profile.id, term: " ", meaning: "house") == nil)

    let entry = store.addEntry(profileID: profile.id, term: "  Haus ", meaning: " house ")
    check("a word is added", entry != nil)
    check("trimmed", entry?.term == "Haus" && entry?.meaning == "house")

    var counts = store.library.counts(for: profile.id, asOf: now)
    check("it is waiting today", counts.new == 1)
    check("and nothing is overdue", counts.due == 0)
    check("the vocabulary has one word in it", counts.words == 1)

    let queue = store.library.queue(for: profile.id, asOf: now)
    check("the sitting has one card in it", queue.count == 1)

    let state = store.answer(queue[0], grade: .good, at: now, seconds: 4.2)
    check("answering moves the card on", state?.stage == .learning)
    check("the answer is in the history", store.library.reviews.count == 1)
    check("with the time it took", store.library.reviews[0].seconds == 4.2)

    counts = store.library.counts(for: profile.id, asOf: now)
    check("a word answered once is no longer a new word", counts.new == 0)
    check("but it is still the day's work until it is learned", counts.due == 1)
    check("the word is still in the vocabulary", counts.words == 1)

    let second = store.answer(queue[0], grade: .good, at: now.addingTimeInterval(600))
    check("a second answer graduates it", second?.stage == .review)
    check("with an interval its own memory asked for",
          days(between: now, and: second!.dueDate!) == 2)
    check("which the app says as a day of the week, not as arithmetic",
          DueText.describe(second?.dueDate, now: now, calendar: calendar) == "Wednesday")
    check("and then the day's work really is done",
          store.library.counts(for: profile.id, asOf: now).total == 0)

    await store.saveNow()
    check("saving succeeds", store.saveState == .saved)
    check("and is remembered", store.lastSavedAt != nil)

    section("Closing and opening again")

    let reopened = LibraryStore(persistence: FileLibraryPersistence(fileURL: fileURL))
    await reopened.load()

    check("the language is still there", reopened.library.profiles.count == 1)
    check("the word is still there", reopened.library.entries.count == 1)
    check("its schedule is exactly where it was",
          reopened.library.entries[0].recognitionCard?.scheduling.dueDate == second?.dueDate)
    check("the history came back too", reopened.library.reviews.count == 2)
    check("nothing is due until the day it was promised for",
          reopened.library.counts(for: profile.id, asOf: now.addingTimeInterval(3600)).total == 0)
    check("and then it is",
          reopened.library.counts(for: profile.id, asOf: now.addingTimeInterval(2 * 86_400)).due == 1)

    section("Deleting a language")

    reopened.deleteProfile(id: profile.id)
    await reopened.saveNow()
    let afterDeletion = LibraryStore(persistence: FileLibraryPersistence(fileURL: fileURL))
    await afterDeletion.load()
    check("the language is gone for good", afterDeletion.library.profiles.isEmpty)
    check("its words with it", afterDeletion.library.entries.isEmpty)
    check("and the app is back to its empty state", afterDeletion.library.isEmpty)
}
