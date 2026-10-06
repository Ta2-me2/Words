import Foundation

/// When the app offers to draw a picture for a word — and, the half that
/// matters more, when it stops.
func checkAssociations() async {
    let day = moment(2026, 6, 1, 9)
    let card = UUID()
    let other = UUID()
    let profile = UUID()
    let entry = UUID()

    func answer(_ grade: ReviewGrade, dayOffset: Int, cardID: UUID = card, practice: Bool = false) -> ReviewRecord {
        ReviewRecord(
            profileID: profile,
            entryID: entry,
            cardID: cardID,
            reviewedAt: day.addingTimeInterval(Double(dayOffset) * 86_400),
            grade: grade,
            stageBefore: .review,
            stageAfter: .review,
            intervalBeforeDays: 3,
            intervalAfterDays: 3,
            dueAfter: nil,
            isPractice: practice
        )
    }

    func struggling(_ history: [ReviewRecord]) -> Bool {
        AssociationPrompt.isStruggling(cardID: card, reviews: history)
    }

    section("A word the learner keeps losing")

    check("a word nobody has answered says nothing", !struggling([]))
    check("nor does one answered badly twice",
          !struggling([answer(.again, dayOffset: 0), answer(.hard, dayOffset: 1)]))

    let inARow = [answer(.again, dayOffset: 0), answer(.again, dayOffset: 1), answer(.hard, dayOffset: 2)]
    check("three bad answers in a row ask for help", struggling(inARow))

    let overTime = [
        answer(.again, dayOffset: 0), answer(.good, dayOffset: 7),
        answer(.again, dayOffset: 20), answer(.good, dayOffset: 30),
        answer(.again, dayOffset: 60),
    ]
    check("so does a word forgotten again and again over a month", struggling(overTime))

    check("but not one that was lost long ago and has been fine since",
          !struggling(overTime + [
              answer(.good, dayOffset: 61), answer(.good, dayOffset: 65), answer(.easy, dayOffset: 80),
          ]))

    check("the offer takes itself away without anybody dismissing it",
          !struggling(inARow + [
              answer(.good, dayOffset: 3), answer(.good, dayOffset: 6), answer(.easy, dayOffset: 12),
          ]))

    section("What does not count as evidence")

    check("practice is not evidence: it moved no schedule",
          !struggling([
              answer(.again, dayOffset: 0, practice: true),
              answer(.again, dayOffset: 1, practice: true),
              answer(.again, dayOffset: 2, practice: true),
          ]))

    check("and neither is another card's bad morning",
          !struggling([
              answer(.again, dayOffset: 0, cardID: other),
              answer(.again, dayOffset: 1, cardID: other),
              answer(.again, dayOffset: 2, cardID: other),
          ]))

    section("A drawing hung on a word")

    var word = Entry(profileID: profile, term: "gehen", meaning: "to go")
    check("a word starts without one", !word.hasAssociation)

    word.association = Association(file: "Media/x.drawing", strokeCount: 0, updatedAt: day)
    check("an empty board is not an association", !word.hasAssociation)

    word.association = Association(file: "Media/x.drawing", strokeCount: 4, updatedAt: day)
    check("a drawing with marks in it is", word.hasAssociation)

    let written = try! JSONEncoder().encode(word)
    let read = try! JSONDecoder().decode(Entry.self, from: written)
    check("it survives a round trip", read.association == word.association)

    let older = Data("""
    {"id":"\(UUID().uuidString)","profileID":"\(profile.uuidString)","term":"Haus","meaning":"house"}
    """.utf8)
    check("and a word written before drawings existed simply has none",
          try! JSONDecoder().decode(Entry.self, from: older).association == nil)

    section("The file belongs to the word")

    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "words-drawings-\(UUID().uuidString)")
    let store = LibraryStore(persistence: FileLibraryPersistence(fileURL: root.appending(path: "Library.json")))
    await store.load()
    defer { try? FileManager.default.removeItem(at: root) }
    let german = store.addProfile(name: "German", learningCode: "de", nativeCode: "en")
    let added = store.addEntry(profileID: german.id, term: "Haus", meaning: "house")!

    let drawn = Data("not really a drawing, but bytes are bytes".utf8)
    let attached = await store.attachAssociation(drawn, strokeCount: 3, to: added.id)
    check("a drawing can be hung on a word", attached)
    check("the word knows it has one", store.library.entry(id: added.id)?.hasAssociation == true)
    check("named after the word, so redrawing overwrites rather than piles up",
          store.library.entry(id: added.id)?.association?.file == "Media/\(added.id.uuidString).drawing")
    check("and the bytes come back exactly as they went in",
          store.associationData(for: store.library.entry(id: added.id)!.association!) == drawn)
    check("as a file of its own, in the folder beside the library",
          FileManager.default.fileExists(atPath: root.appending(path: "Media/\(added.id.uuidString).drawing").path))

    await store.attachAssociation(Data(), strokeCount: 0, to: added.id)
    check("saving an empty board takes the drawing off the word",
          store.library.entry(id: added.id)?.association == nil)

    await store.attachAssociation(drawn, strokeCount: 3, to: added.id)
    store.deleteEntries(ids: [added.id])
    check("deleting the word takes its drawing with it", store.library.entries.isEmpty)

    // The file is discarded in the background, so give it a moment to happen.
    try? await Task.sleep(for: .milliseconds(120))
    check("and the file goes with the word",
          !FileManager.default.fileExists(atPath: root.appending(path: "Media/\(added.id.uuidString).drawing").path))
}
