import Foundation

/// The library itself: what an edit touches, what a deletion takes with it, and
/// what survives being written to disk and read back.
func checkLibrary() {
    let scheduler = FSRSScheduler()
    let today = moment(2026, 3, 2, 9)

    let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    section("A word and its card")

    var library = Library()
    let german = LanguageProfile(name: "German", learningCode: "de", nativeCode: "en")
    library.upsert(german)

    let haus = Entry(profileID: german.id, term: "Haus", meaning: "house")
    library.upsert(haus)

    check("a new word comes with a card", haus.cards.count == 1)
    check("asked in the direction the first version studies",
          haus.recognitionCard?.direction == .recognition)
    check("and the card has never been seen", haus.cards[0].scheduling.isNew)
    check("the word is in its language", library.entries(in: german.id).count == 1)

    section("Answering")

    let queued = library.queue(for: german.id, asOf: today)[0]
    let after = library.recordReview(entryID: queued.entryID, cardID: queued.cardID,
                                     grade: .good, at: today, using: scheduler)

    check("the answer moves the card on", after?.stage == .learning)
    check("the card in the library moved with it",
          library.entry(id: haus.id)?.recognitionCard?.scheduling.stage == .learning)
    check("the answer is written down", library.reviews.count == 1)
    check("with the word it was about", library.reviews[0].entryID == haus.id)
    check("what was given", library.reviews[0].grade == .good)
    check("where the card came from", library.reviews[0].stageBefore == .new)
    check("and where it went", library.reviews[0].dueAfter == after?.dueDate)
    check("a first sighting knows it was one", library.reviews[0].wasIntroduction)

    check("answering a word that is not there changes nothing",
          library.recordReview(entryID: UUID(), cardID: UUID(), grade: .good,
                               at: today, using: scheduler) == nil)
    check("and writes nothing down", library.reviews.count == 1)

    section("Editing")

    library.editEntry(id: haus.id, term: "das Haus", meaning: "house, building",
                      gender: .neuter, example: "", exampleTranslation: "", note: "brick", at: today)
    check("the word changes", library.entry(id: haus.id)?.term == "das Haus")
    check("the meaning changes", library.entry(id: haus.id)?.meaning == "house, building")
    check("the note changes", library.entry(id: haus.id)?.note == "brick")
    check("and the gender", library.entry(id: haus.id)?.gender == .neuter)
    check("the schedule does not",
          library.entry(id: haus.id)?.recognitionCard?.scheduling.stage == .learning)
    check("and the history does not", library.reviews.count == 1)

    section("Deleting")

    var deleting = library
    deleting.removeEntries(ids: [haus.id])
    check("the word is gone", deleting.entry(id: haus.id) == nil)
    check("its card went with it", deleting.queue(for: german.id, asOf: today).isEmpty)
    check("its history stayed", deleting.reviews.count == 1)

    var closing = library
    closing.upsert(Entry(profileID: german.id, term: "Brot", meaning: "bread"))
    closing.removeProfile(id: german.id)
    check("deleting a language deletes its words", closing.entries.isEmpty)
    check("and the language itself", closing.profiles.isEmpty)
    check("the study that happened is still recorded", closing.reviews.count == 1)

    section("Written down and read back")

    var round = library
    round.upsert(Entry(profileID: german.id, term: "Brot", meaning: "bread", note: "das"))
    let restored = try! decoder.decode(Library.self, from: try! encoder.encode(round))

    check("the language survives", restored.profiles.count == 1)
    check("with its daily allowance", restored.profiles[0].dailyNewLimit == 20)
    check("the words survive", restored.entries.count == 2)
    check("the schedule survives",
          restored.entry(id: haus.id)?.recognitionCard?.scheduling.stage == .learning)
    check("to the second",
          restored.entry(id: haus.id)?.recognitionCard?.scheduling.dueDate == after?.dueDate)
    check("the history survives", restored.reviews.count == 1)
    check("and the format is stamped", restored.formatVersion == Library.currentFormatVersion)

    section("A file that has been got at")

    let orphaned = """
    {
      "formatVersion": 1,
      "libraryID": "\(UUID().uuidString)",
      "createdAt": "2026-01-01T00:00:00Z",
      "profiles": [],
      "entries": [{
        "id": "\(UUID().uuidString)",
        "profileID": "\(UUID().uuidString)",
        "term": "Ghost",
        "meaning": "ghost",
        "createdAt": "2026-01-01T00:00:00Z",
        "updatedAt": "2026-01-01T00:00:00Z",
        "cards": []
      }],
      "reviews": []
    }
    """
    let cleaned = try! decoder.decode(Library.self, from: Data(orphaned.utf8))
    check("a word whose language is gone is dropped", cleaned.entries.isEmpty)

    let sparse = """
    {
      "profiles": [{
        "id": "\(german.id.uuidString)",
        "name": "German",
        "learningCode": "de",
        "nativeCode": "en",
        "dailyNewLimit": 20,
        "createdAt": "2026-01-01T00:00:00Z"
      }],
      "entries": [{
        "id": "\(UUID().uuidString)",
        "profileID": "\(german.id.uuidString)",
        "term": "Baum",
        "meaning": "tree"
      }]
    }
    """
    let filled = try! decoder.decode(Library.self, from: Data(sparse.utf8))
    check("a file missing its optional parts still reads", filled.entries.count == 1)
    check("a word that lost its card is given one back", filled.entries[0].cards.count == 1)
    check("and it can be studied", filled.queue(for: german.id, asOf: today).count == 1)
}

/// Starting a word over, and the promise that starting over is not deleting.
func checkForgetting() {
    let now = moment(2026, 4, 1, 9)
    var library = Library()
    let profile = LanguageProfile(name: "German", learningCode: "de", nativeCode: "en")
    library.upsert(profile)

    let entry = Entry(profileID: profile.id, term: "Haus", meaning: "house")
    library.upsert(entry)
    let card = library.entry(id: entry.id)!.recognitionCard!

    library.recordReview(entryID: entry.id, cardID: card.id, grade: .good, at: now, using: FSRSScheduler())
    library.recordReview(entryID: entry.id, cardID: card.id, grade: .good, at: now.addingTimeInterval(900), using: FSRSScheduler())

    section("Starting a word over")

    let studied = library.entry(id: entry.id)!.recognitionCard!.scheduling
    check("the word has a schedule to lose", studied.stage == .review && studied.stability > 0)

    library.forget(entries: [entry.id])
    let restarted = library.entry(id: entry.id)!.recognitionCard!.scheduling

    check("it is a word never met again", restarted.isNew)
    check("with nothing known about it", restarted.stability == 0 && restarted.difficulty == 0)
    check("and no date", restarted.dueDate == nil)
    check("the word itself is untouched", library.entry(id: entry.id)?.term == "Haus")
    check("and what happened is still on the record", library.reviews.count == 2)
    check("so it is waiting today", library.counts(for: profile.id, asOf: now).new == 1)
}

/// The order of the vocabulary table, which is worked out in Swift rather than
/// left to a table that knew its rows' key paths.
func checkWordTableOrder() {
    section("The order of the vocabulary table")

    let profile = LanguageProfile(name: "German", learningCode: "de", nativeCode: "en")
    let now = moment(2026, 6, 1, 9)
    var soon = Entry(profileID: profile.id, term: "Zug", meaning: "train", gender: .masculine)
    soon.cards[0].scheduling.stage = .review
    soon.cards[0].scheduling.dueDate = now.addingTimeInterval(86_400)
    var later = Entry(profileID: profile.id, term: "Apfel", meaning: "apple", gender: .masculine)
    later.cards[0].scheduling.stage = .review
    later.cards[0].scheduling.dueDate = now.addingTimeInterval(5 * 86_400)
    let fresh = Entry(profileID: profile.id, term: "ändern", meaning: "to change")
    let alsoFresh = Entry(profileID: profile.id, term: "Brot", meaning: "bread", gender: .neuter)

    let rows = [fresh, later, alsoFresh, soon].map { WordRow(entry: $0, profile: profile, now: now) }
    func terms(_ sort: WordSort) -> [String] { WordRow.sorted(rows, by: sort).map(\.term) }

    check("by due date, the soonest first and the unstarted last",
          terms(WordSort(column: .due, ascending: true)) == ["Zug", "Apfel", "ändern", "Brot"])
    check("words that tie are in the order of the alphabet, not of the file",
          terms(WordSort(column: .stage, ascending: true)) == ["ändern", "Brot", "Apfel", "Zug"])
    check("by word, the way a dictionary sorts an umlaut",
          terms(WordSort(column: .word, ascending: true)) == ["ändern", "Apfel", "Brot", "Zug"])
    check("and backwards when asked", terms(WordSort(column: .word, ascending: false)) == ["Zug", "Brot", "Apfel", "ändern"])
    check("the article is shown but never sorted on", rows.first { $0.term == "Zug" }?.article == "der")
}
