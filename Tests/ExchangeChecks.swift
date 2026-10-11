import Foundation

/// Handing a deck to somebody else, and taking one from them.
///
/// Three things are checked, in the order they happen: what a tick in the
/// export tree actually comes to, whether a package written here can be read
/// back byte for byte, and what opening one does to a library that already has
/// words in it.
func checkExchange() {
    section("What a tick takes with it")

    let day = moment(2026, 5, 4, 10)
    var library = Library()

    let german = LanguageProfile(name: "German", learningCode: "de", nativeCode: "en")
    let greek = LanguageProfile(name: "Greek", learningCode: "el", nativeCode: "en")
    library.upsert(german)
    library.upsert(greek)

    let germany = Deck(profileID: german.id, name: "Germany", icon: .emoji("🇩🇪"), createdAt: day)
    let a1 = Deck(profileID: german.id, name: "A1", parentID: germany.id, createdAt: day.addingTimeInterval(1))
    let a2 = Deck(profileID: german.id, name: "A2", parentID: germany.id, createdAt: day.addingTimeInterval(2))
    for deck in [germany, a1, a2] { library.upsert(deck) }

    let haus = Entry(profileID: german.id, deckID: a1.id, term: "Haus", meaning: "house",
                     gender: .neuter, transcription: "haʊs",
                     picture: Picture(file: "Media/haus.jpg"),
                     createdAt: day.addingTimeInterval(10))
    let brot = Entry(profileID: german.id, deckID: a2.id, term: "Brot", meaning: "bread",
                     audio: AudioClip(file: "Media/brot.m4a", source: .recorded),
                     createdAt: day.addingTimeInterval(11))
    let loose = Entry(profileID: german.id, term: "ja", meaning: "yes",
                      createdAt: day.addingTimeInterval(12))
    let nero = Entry(profileID: greek.id, term: "νερό", meaning: "water",
                     createdAt: day.addingTimeInterval(13))
    for entry in [haus, brot, loose, nero] { library.upsert(entry) }

    var selection = ExportSelection()
    selection.set(.deck(a1.id), to: true)
    var plan = ExportPlan.make(from: library, selection: selection)
    check("one subdeck takes its own words", plan.entries.map(\.term) == ["Haus"])
    check("and nobody else's", !plan.entries.contains { $0.term == "Brot" })
    check("a subdeck on its own comes out at the top", plan.decks.first?.parentID == nil)
    check("and is still itself", plan.decks.map(\.name) == ["A1"])
    check("its language comes with it", plan.profiles.map(\.name) == ["German"])

    selection.set(.deck(germany.id), to: true)
    plan = ExportPlan.make(from: library, selection: selection)
    check("ticking the deck above it keeps the deck above it",
          plan.decks.first { $0.name == "A1" }?.parentID == plan.decks.first { $0.name == "Germany" }?.id)
    check("a deck's icon travels", plan.decks.first { $0.name == "Germany" }?.icon == .emoji("🇩🇪"))
    check("an empty deck is still worth exporting", plan.decks.count == 2 && plan.entries.count == 1)

    selection.set([.deck(a2.id), .unfiled(german.id)], to: true)
    plan = ExportPlan.make(from: library, selection: selection)
    check("words in no deck come when they are asked for",
          plan.entries.map(\.term).sorted() == ["Brot", "Haus", "ja"])
    check("another language stays behind", !plan.entries.contains { $0.term == "νερό" })
    check("the transcription travels", plan.entries.first { $0.term == "Haus" }?.transcription == "haʊs")
    check("so does the gender", plan.entries.first { $0.term == "Haus" }?.gender == .neuter)
    check("the files the words own are listed",
          Set(plan.mediaFiles) == ["Media/haus.jpg", "Media/brot.m4a"])

    section("Leaving things behind")

    selection.includesPhotos = false
    plan = ExportPlan.make(from: library, selection: selection)
    check("photos off takes the photo off the word", plan.entries.first { $0.term == "Haus" }?.picture == nil)
    check("and the file out of the package", plan.mediaFiles == ["Media/brot.m4a"])
    check("but leaves the word", plan.entries.contains { $0.term == "Haus" })

    selection.includesPhotos = true
    selection.includesRecordings = false
    plan = ExportPlan.make(from: library, selection: selection)
    check("recordings off takes the recording off", plan.entries.first { $0.term == "Brot" }?.audio == nil)
    check("and leaves the photo alone", plan.mediaFiles == ["Media/haus.jpg"])

    selection.includesRecordings = true
    var withVoice = german
    withVoice.voiceIdentifier = "com.apple.voice.premium.de-DE.Anna"
    library.upsert(withVoice)
    plan = ExportPlan.make(from: library, selection: selection)
    check("the voice is a fact about this Mac and stays on it",
          plan.profiles.first?.voiceIdentifier == nil)

    section("A schedule is nobody else's business")

    var studied = haus
    var schedule = SchedulingState()
    schedule.stage = .review
    schedule.dueDate = day.addingTimeInterval(86_400)
    schedule.intervalDays = 12
    schedule.stability = 9
    schedule.difficulty = 5
    schedule.reviewCount = 4
    schedule.lapses = 1
    schedule.lastReviewedAt = day
    studied.cards[0].scheduling = schedule
    library.upsert(studied)
    library.reviews.append(ReviewRecord(
        profileID: german.id, entryID: haus.id, cardID: haus.cards[0].id,
        reviewedAt: day, grade: .good, stageBefore: .learning, stageAfter: .review,
        intervalBeforeDays: 1, intervalAfterDays: 12, dueAfter: day.addingTimeInterval(86_400)
    ))
    library.reviews.append(ReviewRecord(
        profileID: greek.id, entryID: nero.id, cardID: nero.cards[0].id,
        reviewedAt: day, grade: .again, stageBefore: .new, stageAfter: .learning,
        intervalBeforeDays: 0, intervalAfterDays: 0, dueAfter: nil
    ))

    plan = ExportPlan.make(from: library, selection: selection)
    check("without progress a studied word arrives new",
          plan.entries.first { $0.term == "Haus" }?.cards.first?.scheduling.stage == .new)
    check("and carries no answers", plan.reviews.isEmpty)
    check("and the package says so", !plan.includesProgress)

    selection.includesProgress = true
    plan = ExportPlan.make(from: library, selection: selection)
    check("with progress the schedule comes too",
          plan.entries.first { $0.term == "Haus" }?.cards.first?.scheduling.intervalDays == 12)
    check("and the answers behind it", plan.reviews.count == 1)
    check("but only for the words that were exported",
          plan.reviews.allSatisfy { $0.entryID == haus.id })
    check("and the package says so", plan.includesProgress)

    section("Written and read back")

    let folder = FileManager.default.temporaryDirectory
        .appending(path: "words-exchange-\(UUID().uuidString)", directoryHint: .isDirectory)
    try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    // Two files standing in for a photograph and a recording.
    let photo = Data((0 ..< 5_000).map { UInt8($0 % 251) })
    let sound = Data("not really an m4a, but bytes are bytes".utf8)
    try! photo.write(to: folder.appending(path: "haus.jpg"))
    try! sound.write(to: folder.appending(path: "brot.m4a"))

    let packageURL = folder.appending(path: "Germany.wordspack")
    let missing = try! WordsPackage.write(
        plan, to: packageURL, appVersion: "Words checks",
        mediaURL: { folder.appending(path: ($0 as NSString).lastPathComponent) }
    )
    check("every file was found", missing.isEmpty)
    check("the package is a file on disk", FileManager.default.fileExists(atPath: packageURL.path))

    let reopened = try! WordsPackage(reading: packageURL)
    check("it says which format it is", reopened.manifest.format == WordsPackage.currentFormat)
    check("it says who wrote it", reopened.manifest.createdBy == "Words checks")
    check("the words came back", reopened.manifest.entries.count == plan.entries.count)
    check("in the same order", reopened.manifest.entries.map(\.term) == plan.entries.map(\.term))
    check("the decks came back", reopened.manifest.decks.map(\.name).sorted() == ["A1", "A2", "Germany"])
    check("the schedule came back",
          reopened.manifest.entries.first { $0.term == "Haus" }?.cards.first?.scheduling.intervalDays == 12)
    check("the answers came back", reopened.manifest.reviews.count == 1)
    check("a photograph came back byte for byte", reopened.media("Media/haus.jpg") == photo)
    check("and a recording too", reopened.media("Media/brot.m4a") == sound)
    check("the package knows what it holds", reopened.mediaFiles == ["Media/haus.jpg", "Media/brot.m4a"])
    check("a file nobody packed is not claimed", reopened.media("Media/nothing.jpg") == nil)

    // A photograph the library has lost: the export must not fail over it.
    let gapURL = folder.appending(path: "gap.wordspack")
    let gaps = try! WordsPackage.write(
        plan, to: gapURL, appVersion: "Words checks",
        mediaURL: { _ in folder.appending(path: "not-here.jpg") }
    )
    check("a file that has gone missing is reported", gaps.count == plan.mediaFiles.count)
    let withGaps = try! WordsPackage(reading: gapURL)
    check("and the words are written all the same", withGaps.manifest.entries.count == plan.entries.count)
    check("the package admits it holds none of them", withGaps.mediaFiles.isEmpty)
    let repaired = PackageImport.plan(
        withGaps.manifest, into: Library(),
        destinations: [withGaps.manifest.profiles[0].id: .newLanguage],
        mediaInPackage: withGaps.mediaFiles
    )
    check("so the words arrive without pointing at anything",
          repaired.entries.allSatisfy { $0.picture == nil && $0.audio == nil } && repaired.media.isEmpty)

    let plainZip = try! ZipArchive(url: packageURL)
    check("it is an ordinary zip anybody can open", plainZip.contains(WordsPackage.manifestName))
    check("with a note for whoever opens it", plainZip.contains(WordsPackage.readmeName))

    let notAPackage = folder.appending(path: "notes.txt")
    try! Data("just some text".utf8).write(to: notAPackage)
    var refused = false
    do { _ = try WordsPackage(reading: notAPackage) } catch { refused = true }
    check("something that is not a package is refused", refused)

    section("Opening somebody else's package")

    var theirs = Library()
    let mine = LanguageProfile(name: "Deutsch", learningCode: "de", nativeCode: "en")
    theirs.upsert(mine)
    theirs.upsert(Entry(profileID: mine.id, term: "Brot", meaning: "bread", createdAt: day))

    let manifest = reopened.manifest
    let packaged = manifest.profiles.first!
    check("the language it belongs in is recognised by its pair",
          PackageImport.suggestedDestination(for: packaged, in: theirs) == .existing(mine.id))

    var imported = PackageImport.plan(
        manifest, into: theirs,
        destinations: [packaged.id: .existing(mine.id)],
        mediaInPackage: reopened.mediaFiles
    )
    check("a word already here is left alone", imported.duplicates == 1)
    check("the rest arrive", imported.entries.map(\.term).sorted() == ["Haus", "ja"])
    check("no language is created", imported.profiles.isEmpty)
    check("the decks arrive", imported.decks.map(\.name).sorted() == ["A1", "A2", "Germany"])
    check("with the tree they had",
          imported.decks.first { $0.name == "A1" }?.parentID == imported.decks.first { $0.name == "Germany" }?.id)
    check("filed into the language they were sent to",
          imported.decks.allSatisfy { $0.profileID == mine.id })
    check("nothing keeps the identifier it had there",
          !imported.entries.contains { entry in manifest.entries.contains { $0.id == entry.id } })
    check("a word keeps the deck it was in",
          imported.entries.first { $0.term == "Haus" }?.deckID == imported.decks.first { $0.name == "A1" }?.id)
    check("the photograph is given a name of its own",
          imported.media["Media/haus.jpg"]?.hasPrefix("Media/") == true
            && imported.media["Media/haus.jpg"] != "Media/haus.jpg")
    check("and the word points at the new name",
          imported.entries.first { $0.term == "Haus" }?.picture?.file == imported.media["Media/haus.jpg"])
    check("the answers come with the word they belong to",
          imported.reviews.count == 1 && imported.reviews.first?.entryID == imported.entries.first { $0.term == "Haus" }?.id)
    check("and are filed under the language they landed in",
          imported.reviews.first?.profileID == mine.id)

    // Apply it, then do the whole thing again.
    for profile in imported.profiles { theirs.upsert(profile) }
    for deck in imported.decks { theirs.upsert(deck) }
    for entry in imported.entries { theirs.upsert(entry) }
    theirs.reviews.append(contentsOf: imported.reviews)

    let again = PackageImport.plan(
        manifest, into: theirs,
        destinations: [packaged.id: .existing(mine.id)],
        mediaInPackage: reopened.mediaFiles
    )
    check("opening the same package twice adds no words", again.entries.isEmpty)
    check("and makes no second A1", again.decks.isEmpty)
    check("it says what it skipped — all three this time", again.duplicates == 3)

    section("Where it lands")

    var empty = Library()
    let fresh = PackageImport.plan(
        manifest, into: empty,
        destinations: [packaged.id: .newLanguage],
        mediaInPackage: reopened.mediaFiles
    )
    check("a language is made for it", fresh.profiles.count == 1)
    check("named as it was named", fresh.profiles.first?.name == "German")
    check("with a new identifier", fresh.profiles.first?.id != packaged.id)
    check("and everything filed under it",
          fresh.entries.allSatisfy { $0.profileID == fresh.profiles.first?.id })
    check("nothing is called a duplicate in an empty library", fresh.duplicates == 0)

    let skipped = PackageImport.plan(
        manifest, into: empty, destinations: [:], mediaInPackage: reopened.mediaFiles
    )
    check("a language nobody chose a place for is left out", skipped.isEmpty)

    let withoutMedia = PackageImport.plan(
        manifest, into: empty,
        destinations: [packaged.id: .newLanguage],
        mediaInPackage: []
    )
    check("a word whose photograph was not packed arrives without one",
          withoutMedia.entries.first { $0.term == "Haus" }?.picture == nil)
    check("and nothing is promised that is not there", withoutMedia.media.isEmpty)

    empty.upsert(LanguageProfile(name: "German", learningCode: "de", nativeCode: "en"))
    check("a language with the same pair is the suggestion",
          PackageImport.suggestedDestination(for: packaged, in: empty) != .newLanguage)
    let greekPackaged = LanguageProfile(name: "Greek", learningCode: "el", nativeCode: "en")
    check("one with no match is a new language",
          PackageImport.suggestedDestination(for: greekPackaged, in: empty) == .newLanguage)

    section("A package written by a later Words")

    var ahead = manifest
    ahead.format = WordsPackage.currentFormat + 1
    let aheadURL = folder.appending(path: "ahead.wordspack")
    let writer = try! ZipWriter(creating: aheadURL)
    try! writer.add(WordsPackage.manifestName, data: try! WordsPackage.encoder.encode(ahead))
    try! writer.finish()
    var explained = ""
    do { _ = try WordsPackage(reading: aheadURL) } catch { explained = error.localizedDescription }
    check("is refused", !explained.isEmpty)
    check("and says to update rather than blaming the file",
          explained.contains("newer version") && !explained.contains("damaged"))
}
