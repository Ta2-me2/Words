import Foundation

/// Reading a deck made for Anki, guessing where its fields go, and bringing it
/// in — checked against small packages built to have the shapes real shared
/// decks were found to have. See Fixtures/make-anki-fixtures.py.
func checkAnki() async {
    let vocabURL = URL(fileURLWithPath: "Fixtures/legacy2-vocab.apkg")
    let picturesURL = URL(fileURLWithPath: "Fixtures/legacy1-pictures.apkg")
    let german = LanguageProfile(name: "German", learningCode: "de", nativeCode: "ru")
    let french = LanguageProfile(name: "French", learningCode: "fr", nativeCode: "en")

    section("Opening a package")

    guard let vocab = try? AnkiPackage.open(vocabURL), let pictures = try? AnkiPackage.open(picturesURL) else {
        check("the fixture packages open", false)
        return
    }

    check("the real collection is read, not the stub that says “please update”", vocab.notes.count == 7)
    check("a note type with no notes is left out", vocab.usedNoteTypes.map(\.name) == ["Vocab List"])
    check("the fields come in their order", vocab.usedNoteTypes.first?.fields.first == "Note ID")
    check("two templates make two cards a note", vocab.cardsPerNote[11] == 2)
    check("the deck is named after its top level, not a chapter inside it", vocab.mainDeckName == "Goethe")
    check("the media map is read", vocab.hasMedia(named: "tts-0.mp3"))
    check("a recording's bytes come out of the archive", vocab.mediaData(named: "tts-0.mp3")?.prefix(3) == Data("ID3".utf8))
    check("and its size is known without reading it", (vocab.mediaSize(named: "tts-0.mp3") ?? 0) > 1000)
    check("the oldest format opens too", pictures.notes.count == 3)

    do {
        _ = try AnkiPackage.open(URL(fileURLWithPath: "Fixtures/newest.apkg"))
        check("the newest format is refused", false)
    } catch let failure as AnkiPackage.Failure {
        check("the newest format is refused", failure.errorDescription?.contains("recent version of Anki") == true)
        check("with what to do about it", failure.recoverySuggestion?.contains("Support older Anki versions") == true)
    } catch {
        check("the newest format is refused with a reason", false)
    }

    let notAPackage = FileManager.default.temporaryDirectory.appending(path: "words-not-a-package.apkg")
    try? Data("just some text".utf8).write(to: notAPackage)
    check("a file that is not a package says so", (try? AnkiPackage.open(notAPackage)) == nil)

    section("What a field holds once the markup is off")

    check("entities become characters", AnkiText.parse("le&nbsp;chat &amp; Caf&#233;").text == "le chat & Café")
    check("tags go", AnkiText.parse("<div>the <b>cat</b></div>").text == "the cat")
    check("line breaks stay line breaks", AnkiText.parse("one<br>two").text == "one\ntwo")
    check("a table keeps its rows", AnkiText.parse("<table><tr><td>le</td><td>the</td></tr><tr><td>chien</td><td>dog</td></tr></table>").text == "le · the\nchien · dog")
    check("a recording is pulled out", AnkiText.parse(" [sound:w1.mp3]") == AnkiValue(text: "", sounds: ["w1.mp3"], images: []))
    check("so is a picture, in either kind of quotes", AnkiText.parse("<img src='dog.png'>").images == ["dog.png"])
    check("scripts are not text", AnkiText.parse("<script>alert(1)</script>visible").text == "visible")
    check("“N/A” means nothing is there", AnkiText.isPlaceholder("N/A") && !AnkiText.isPlaceholder("nah"))

    section("Guessing where the fields go")

    let vocabType = vocab.usedNoteTypes[0]
    let vocabNotes = vocab.notes(of: vocabType.id).map(ParsedAnkiNote.init)
    var mapping = AnkiMapping.suggest(for: vocabType, notes: vocabNotes, package: vocab, profile: german)
    func slot(_ field: String, in mapping: AnkiMapping, type: AnkiPackage.NoteType) -> WordsSlot? {
        type.fields.firstIndex(of: field).map { mapping.slots[$0] }
    }

    check("an identifier is not imported", slot("Note ID", in: mapping, type: vocabType) == .skip)
    check("the learning language's word is the word", slot("de_word", in: mapping, type: vocabType) == .word)
    check("the other language's word is the meaning", slot("en_word", in: mapping, type: vocabType) == .meaning)
    check("the learning language's sentence is the example", slot("de_sentence", in: mapping, type: vocabType) == .example)
    check("and its translation is the example's translation", slot("en_sentence", in: mapping, type: vocabType) == .exampleTranslation)
    check("a recording that grows with the sentence is the example's",
          slot("de_audio", in: mapping, type: vocabType) == .exampleAudio)
    check("the guess can be imported as it is", mapping.problem == nil)

    let pictureType = pictures.usedNoteTypes[0]
    let pictureNotes = pictures.notes(of: pictureType.id).map(ParsedAnkiNote.init)
    let pictureMapping = AnkiMapping.suggest(for: pictureType, notes: pictureNotes, package: pictures, profile: french)
    check("a field of pictures is the picture", slot("Picture", in: pictureMapping, type: pictureType) == .picture)
    check("a recording with no sentence to follow is the word's", slot("Sound", in: pictureMapping, type: pictureType) == .wordAudio)
    check("a field that says the same thing in every note is not imported", slot("Author", in: pictureMapping, type: pictureType) == .skip)
    check("the front is the word and the back the meaning",
          slot("Front", in: pictureMapping, type: pictureType) == .word && slot("Back", in: pictureMapping, type: pictureType) == .meaning)

    section("Correcting the guess")

    let wordField = vocabType.fields.firstIndex(of: "de_word")!
    let meaningField = vocabType.fields.firstIndex(of: "en_word")!
    mapping.assign(.word, toField: meaningField)
    check("choosing a different field as the word takes it from the old one",
          mapping.slots[meaningField] == .word && mapping.slots[wordField] == .skip)
    check("and says what is now missing", mapping.problem == "Choose which field holds the meaning.")
    mapping.assign(.meaning, toField: wordField)
    check("swapping the two back is two choices", mapping.problem == nil)
    mapping.assign(.meaning, toField: vocabType.fields.firstIndex(of: "en_sentence")!)
    check("the meaning can gather several fields", mapping.fields(for: .meaning).count == 2)

    section("What the import would bring in")

    let suggested = AnkiMapping.suggest(for: vocabType, notes: vocabNotes, package: vocab, profile: german)
    let plan = AnkiImport.plan(notes: vocabNotes, mapping: suggested, fieldNames: vocabType.fields, profile: german, audio: .deck, package: vocab, existing: [])
    let ansage = plan.words.first { $0.term == "Ansage" }
    check("a dictionary form gives up its article as a gender", ansage?.gender == .feminine)
    check("and its plural as a note", ansage?.note == "Plural: -n")
    check("an umlaut plural is kept as it was written", plan.words.first { $0.term == "Arzt" }?.note == "Plural: -ä, e")
    check("the same word with the same meaning comes in once", plan.words.count { $0.term == "gehen" && !$0.isDuplicate } == 1)
    check("the same word with another meaning is another word",
          plan.usable.count { $0.term == "Anschluss" } == 2)
    check("a note with no meaning is left out and counted", plan.incomplete == 1)
    check("five words are ready", plan.usable.count == 5)
    check("with the deck's recordings of their examples", plan.usable.allSatisfy { $0.exampleAudio != nil && $0.wordAudio == nil })

    let voiced = AnkiImport.plan(notes: vocabNotes, mapping: suggested, fieldNames: vocabType.fields, profile: german, audio: .ourVoice, package: vocab, existing: [])
    check("choosing Words' voice brings in no recordings at all", voiced.recordings == 0)

    let pictured = AnkiImport.plan(notes: pictureNotes, mapping: pictureMapping, fieldNames: pictureType.fields, profile: french, audio: .deck, package: pictures, existing: [])
    check("a picture called “cat.jpg!d” is still found", pictured.words.first?.picture == "cat.jpg!d")
    check("a language without articles keeps the word whole", pictured.words.first?.term == "le chat")
    check("a table in the back becomes lines in the meaning", pictured.words[1].meaning == "le · the\nchien · dog")
    check("a placeholder is not a note", pictured.words[0].note.isEmpty)
    check("a note from a field with a name of its own says which it is", pictured.words[1].note == "Antonyms: chat")

    let alreadyHere = Entry(profileID: german.id, term: "Arzt", meaning: "doctor")
    let again = AnkiImport.plan(notes: vocabNotes, mapping: suggested, fieldNames: vocabType.fields, profile: german, audio: .deck, package: vocab, existing: [alreadyHere])
    check("a word the library already has is not added twice", again.usable.count == 4 && again.duplicates == 2)

    section("An article kept in a field of its own")

    // The shape of a real shared German deck: the word bare, the article in a
    // field called "Artikel" that is empty for everything but nouns, the plural
    // beside it.
    let articleType = AnkiPackage.NoteType(
        id: 99,
        name: "Basic (and reversed card)",
        fields: ["Wort_DE", "Wort_EN", "Artikel", "Plural", "Satz1_DE", "Satz1_EN"],
        templates: [AnkiPackage.Template(
            name: "Card 1",
            front: "{{Wort_DE}}",
            back: "{{#Artikel}}{{Artikel}}{{/Artikel}} {{Wort_DE}} {{Plural}}<hr id=answer>{{Wort_EN}} {{Satz1_DE}} {{Satz1_EN}}"
        )],
        sortField: 0,
        isCloze: false
    )
    let articleRows: [[String]] = [
        ["Adresse", "address", "die", "-n", "Können Sie mir Ihre Adresse geben?", "Can you give me your address?"],
        ["aber", "but", "", "", "Heute nicht, aber morgen.", "Not today, but tomorrow."],
        ["Angebot", "offer", "das", "-e", "Heute sind Bananen im Angebot.", "Bananas are on offer today."],
        ["anbieten", "to offer", "", "", "Er hat mir Hilfe angeboten.", "He offered me help."],
        ["Anfang", "beginning", "der", "\"-e", "Am Anfang war es schwer.", "At the beginning it was hard."],
        ["anders", "different", "", "", "Anders geht das nicht.", "It doesn't work any other way."],
        ["der Tisch", "table", "der", "\"-e", "Der Tisch ist neu.", "The table is new."],
    ]
    let articleNotes = articleRows.enumerated().map { index, fields in
        ParsedAnkiNote(AnkiPackage.Note(id: Int64(500 + index), guid: "a\(index)", noteTypeID: 99, fields: fields, tags: []))
    }
    let articleMapping = AnkiMapping.suggest(for: articleType, notes: articleNotes, package: vocab, profile: german)
    check("a field of nothing but articles is recognised as the article",
          slot("Artikel", in: articleMapping, type: articleType) == .gender)
    check("though it is empty for every word that is not a noun",
          articleNotes.count { $0.values[2].text.isEmpty } == 3)
    check("the word is still the word", slot("Wort_DE", in: articleMapping, type: articleType) == .word)
    check("and the meaning still the meaning", slot("Wort_EN", in: articleMapping, type: articleType) == .meaning)
    check("a guess with an article in it can be imported as it is", articleMapping.problem == nil)

    let articlePlan = AnkiImport.plan(notes: articleNotes, mapping: articleMapping, fieldNames: articleType.fields, profile: german, audio: .deck, package: vocab, existing: [])
    check("a noun comes in with its gender", articlePlan.words.first { $0.term == "Adresse" }?.gender == .feminine)
    check("neuter", articlePlan.words.first { $0.term == "Angebot" }?.gender == .neuter)
    check("and masculine", articlePlan.words.first { $0.term == "Anfang" }?.gender == .masculine)
    check("a word that is not a noun comes in with none", articlePlan.words.first { $0.term == "aber" }?.gender == nil)
    check("an article typed into the word as well is not left in it",
          articlePlan.words.first { $0.meaning == "table" }?.term == "Tisch")
    check("the word reads with its article", articlePlan.words.first { $0.term == "Adresse" }?.previewEntry(profileID: german.id).displayTerm(in: german) == "die Adresse")

    var chosenByHand = AnkiMapping(slots: Array(repeating: .skip, count: articleType.fields.count))
    chosenByHand.assign(.word, toField: 0)
    chosenByHand.assign(.meaning, toField: 1)
    chosenByHand.assign(.gender, toField: 2)
    check("the article can be chosen by hand", chosenByHand.problem == nil && chosenByHand.fields(for: .gender) == [2])
    chosenByHand.assign(.gender, toField: 3)
    check("and only one field can be it", chosenByHand.fields(for: .gender) == [3] && chosenByHand.slots[2] == .skip)

    let plural = articlePlan.words.first { $0.term == "Adresse" }?.note
    check("a plural in a field of its own is labelled, not a bare “-n”", plural == "Plural: -n")

    let soundType = AnkiPackage.NoteType(
        id: 98, name: "Sounds", fields: ["Wort_DE", "Wort_EN", "Audio_Satz", "Audio_Wort"],
        templates: [AnkiPackage.Template(name: "Card 1", front: "{{Wort_DE}}{{Audio_Wort}}", back: "{{Wort_EN}}")],
        sortField: 0, isCloze: false
    )
    let soundNotes = (0..<4).map { index in
        ParsedAnkiNote(AnkiPackage.Note(
            id: Int64(600 + index), guid: "s\(index)", noteTypeID: 98,
            fields: ["Wort \(index)", "word \(index)", "[sound:satz\(index).mp3]", "[sound:wort\(index).mp3]"], tags: []
        ))
    }
    let soundMapping = AnkiMapping.suggest(for: soundType, notes: soundNotes, package: vocab, profile: german)
    check("a recording called the word's reads the word, whatever it weighs",
          slot("Audio_Wort", in: soundMapping, type: soundType) == .wordAudio)
    check("and one called the sentence's reads the example",
          slot("Audio_Satz", in: soundMapping, type: soundType) == .exampleAudio)

    let measured = AnkiFieldProfile.measure(type: articleType, notes: articleNotes)
    check("a field of sentences is not taken for articles", measured[4].genders == 0)
    check("nor is the plural", measured[3].genders == 0)

    section("Words written the way a dictionary writes them")

    check("two genders are not guessed at", LanguageGenders.dictionaryForm("der/die Bekannte, -n", language: "de").gender == nil)
    check("nor is a word with a bracket", LanguageGenders.dictionaryForm("gern(e)", language: "de") == ("gern(e)", nil, nil))
    check("a plain noun still has its article taken", LanguageGenders.dictionaryForm("das Haus", language: "de").gender == .neuter)

    section("What a file is, by its first bytes")

    check("a JPEG", MediaKind.sniff(Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0])) == .jpeg)
    check("a PNG", MediaKind.sniff(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])) == .png)
    check("an MP3 with a tag", MediaKind.sniff(Data("ID3xxxx".utf8)) == .mp3)
    check("a name with rubbish after the extension", MediaKind(fileName: "photo.jpg!d") == .jpeg)

    section("Bringing a deck in")

    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "words-anki-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = LibraryStore(persistence: FileLibraryPersistence(fileURL: root.appending(path: "Library.json")))
    await store.load()
    let profile = store.addProfile(name: "German", learningCode: "de", nativeCode: "ru")
    let deck = store.addDeck(profileID: profile.id, name: vocab.mainDeckName)

    let planned = AnkiImport.plan(notes: vocabNotes, mapping: suggested, fieldNames: vocabType.fields, profile: profile, audio: .deck, package: vocab, existing: [])
    var reported: [Double] = []
    let imported = await store.importAnki(planned.usable, from: vocab, profileID: profile.id, deckID: deck?.id) { reported.append($0) }

    check("every planned word is added", imported == 5 && store.library.entries.count == 5)
    check("into the deck that was chosen", store.library.entries.allSatisfy { $0.deckID == deck?.id })
    check("with its gender", store.library.entries.first { $0.term == "Ansage" }?.gender == .feminine)
    check("its example's recording is hung on it", store.library.entries.allSatisfy { $0.exampleAudio != nil })
    check("as a file in the library's own folder",
          store.library.entries.allSatisfy { entry in
              entry.exampleAudio.map { FileManager.default.fileExists(atPath: root.appending(path: $0.file).path) } ?? false
          })
    check("and the progress reached the end", reported.last == 1)

    let pictureProfile = store.addProfile(name: "French", learningCode: "fr", nativeCode: "en")
    let picturePlan = AnkiImport.plan(notes: pictureNotes, mapping: pictureMapping, fieldNames: pictureType.fields, profile: pictureProfile, audio: .deck, package: pictures, existing: [])
    await store.importAnki(picturePlan.usable, from: pictures, profileID: pictureProfile.id, deckID: nil)
    let cat = store.library.entries.first { $0.term == "le chat" }
    check("a picture is hung on its word", cat?.picture != nil)
    check("named for what it is, not what it was called", cat?.picture?.file.hasSuffix(".jpg") == true)
    check("a word's own recording is its audio", cat?.audio != nil && cat?.exampleAudio == nil)

    section("A photo and a drawing share one place")

    if let cat {
        let drawn = await store.attachAssociation(Data("drawing".utf8), strokeCount: 2, to: cat.id)
        check("a word with a photo does not also get a drawing", !drawn && store.library.entry(id: cat.id)?.association == nil)

        store.removePicture(from: cat.id)
        await store.attachAssociation(Data("drawing".utf8), strokeCount: 2, to: cat.id)
        check("without the photo, it can", store.library.entry(id: cat.id)?.hasAssociation == true)

        await store.attachPicture(Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]), fileExtension: "jpg", to: cat.id)
        check("and a photo put on a drawn word replaces the drawing",
              store.library.entry(id: cat.id)?.picture != nil && store.library.entry(id: cat.id)?.association == nil)
    }

    let older = Data("""
    {"id":"\(UUID().uuidString)","profileID":"\(UUID().uuidString)","term":"Haus","meaning":"house"}
    """.utf8)
    let read = try? JSONDecoder().decode(Entry.self, from: older)
    check("a word written before any of this has no example recording and no photo",
          read != nil && read?.exampleAudio == nil && read?.picture == nil)
}

/// Anki's own decks brought in as decks and subdecks — at most two levels, as
/// Words has, whatever depth the author used.
func checkAnkiDecks() async {
    let profileID = UUID()

    section("Where each note sits in an Anki deck")

    let course = AnkiDeckLayout(deckNames: [
        1: "Course::Chapter 1::Animals",
        2: "Course::Chapter 1::Animals",
        3: "Course::Chapter 1::Food",
        4: "Course::Chapter 2",
        5: "Course",
    ], fallbackName: "course file")

    check("the top every note shares is the deck", course.baseName == "Course")
    check("its levels are counted below that top", course.depth == 2)
    check("a note in the top deck itself has no subdeck", course.subdeckName(forNote: 5, style: .firstLevel) == nil)
    check("the level under the top becomes the subdeck", course.subdeckName(forNote: 1, style: .firstLevel) == "Chapter 1")
    check("and anything deeper goes into the subdeck above it", course.subdeckName(forNote: 3, style: .firstLevel) == "Chapter 1")
    check("or every level is kept, run into one name", course.subdeckName(forNote: 3, style: .allLevels) == "Chapter 1 · Food")
    check("a shallower note keeps its one level either way", course.subdeckName(forNote: 4, style: .allLevels) == "Chapter 2")
    check("no subdecks means none at all", course.subdeckName(forNote: 1, style: .none) == nil)
    check("three levels offer all three choices", course.styles == [.none, .firstLevel, .allLevels])
    check("chapters are counted", course.subdecks(for: [1, 2, 3, 4, 5], style: .firstLevel).map(\.count) == [3, 1])
    check("topics are counted", course.subdecks(for: [1, 2, 3, 4, 5], style: .allLevels).map(\.name)
          == ["Chapter 1 · Animals", "Chapter 1 · Food", "Chapter 2"])

    let flat = AnkiDeckLayout(deckNames: [1: "Goethe A1", 2: "Goethe A1"], fallbackName: "file")
    check("a deck with no structure offers no subdecks", !flat.hasSubdecks && flat.styles == [.none])

    let twoTops = AnkiDeckLayout(deckNames: [1: "Verbs", 2: "Nouns::Animals", 3: "Default"], fallbackName: "My Package")
    check("notes with no top in common are held under the package's name", twoTops.baseName == "My Package")
    check("and each of their decks is a subdeck", twoTops.subdeckName(forNote: 2, style: .firstLevel) == "Nouns")
    check("a note left in Anki's Default deck is in no subdeck", twoTops.subdeckName(forNote: 3, style: .firstLevel) == nil)

    let defaults = AnkiDeckLayout(deckNames: [1: "Default", 2: "Default"], fallbackName: "Package")
    check("a package that is all Default is named after the package", defaults.baseName == "Package" && !defaults.hasSubdecks)

    section("Which decks an import makes")

    var library = Library()
    let german = LanguageProfile(id: profileID, name: "German", learningCode: "de", nativeCode: "en")
    library.upsert(german)

    let fresh = AnkiDeckPlacement.resolve(target: .newDeck("Course"), style: .firstLevel, layout: course,
                                          noteIDs: [1, 2, 3, 4, 5], profileID: profileID, library: library)
    check("a new deck is made", fresh.top?.isNew == true && fresh.top?.deck.name == "Course")
    check("with a subdeck for each chapter", fresh.subdecks.map(\.deck.name) == ["Chapter 1", "Chapter 2"])
    check("each inside it", fresh.subdecks.allSatisfy { $0.deck.parentID == fresh.top?.deck.id })
    check("parents are made before the decks inside them", fresh.newDecks.first?.id == fresh.top?.deck.id)
    check("every word has a place", fresh.deckOfNote.count == 5)
    check("the word in the top deck goes in the top deck", fresh.deckOfNote[5] == fresh.top?.deck.id && fresh.top?.wordCount == 1)
    check("and the chapters count their own words", fresh.subdecks.map(\.wordCount) == [3, 1])

    let courseDeck = Deck(profileID: profileID, name: "course")
    let chapterOne = Deck(profileID: profileID, name: "Chapter 1", parentID: courseDeck.id)
    library.upsert(courseDeck)
    library.upsert(chapterOne)

    let again = AnkiDeckPlacement.resolve(target: .newDeck("Course"), style: .firstLevel, layout: course,
                                          noteIDs: [1, 2, 3, 4, 5], profileID: profileID, library: library)
    check("a deck already called that is used, whatever its capitals", again.top?.deck.id == courseDeck.id && again.top?.isNew == false)
    check("so is a subdeck already called that", again.subdecks.first { $0.deck.name == "Chapter 1" }?.deck.id == chapterOne.id)
    check("and only what is missing is made", again.newDecks.map(\.name) == ["Chapter 2"])

    let intoSubdeck = AnkiDeckPlacement.resolve(target: .existing(chapterOne.id), style: .allLevels, layout: course,
                                                noteIDs: [1, 2, 3, 4, 5], profileID: profileID, library: library)
    check("a subdeck cannot hold subdecks", !intoSubdeck.canHoldSubdecks && intoSubdeck.subdecks.isEmpty)
    check("so everything goes straight into it", Set(intoSubdeck.deckOfNote.values) == [chapterOne.id] && intoSubdeck.newDecks.isEmpty)

    let nowhere = AnkiDeckPlacement.resolve(target: .none, style: .firstLevel, layout: course,
                                            noteIDs: [1, 2], profileID: profileID, library: library)
    check("no deck makes no decks and files nothing", nowhere.top == nil && nowhere.deckOfNote.isEmpty && nowhere.newDecks.isEmpty)

    let oneDeck = AnkiDeckPlacement.resolve(target: .newDeck("Other"), style: .none, layout: course,
                                            noteIDs: [1, 2, 3], profileID: profileID, library: library)
    check("choosing no subdecks puts everything in the one deck", oneDeck.subdecks.isEmpty && oneDeck.top?.wordCount == 3)

    section("A course three levels deep, brought in")

    guard let pictures = try? AnkiPackage.open(URL(fileURLWithPath: "Fixtures/legacy1-pictures.apkg")) else {
        check("the course fixture opens", false)
        return
    }
    let type = pictures.usedNoteTypes[0]
    let notes = pictures.notes(of: type.id).map(ParsedAnkiNote.init)
    let layout = pictures.deckLayout(forNotes: notes.map(\.id))
    check("the package's decks are read as a path", layout.baseName == "Course" && layout.depth == 2)

    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "words-anki-decks-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = LibraryStore(persistence: FileLibraryPersistence(fileURL: root.appending(path: "Library.json")))
    await store.load()
    let french = store.addProfile(name: "French", learningCode: "fr", nativeCode: "en")

    let mapping = AnkiMapping.suggest(for: type, notes: notes, package: pictures, profile: french)
    let plan = AnkiImport.plan(notes: notes, mapping: mapping, fieldNames: type.fields, profile: french,
                               audio: .deck, package: pictures, existing: [])
    let result = await store.importAnki(plan.usable, from: pictures, profileID: french.id,
                                        target: .newDeck(layout.baseName), style: .firstLevel, layout: layout)

    let top = store.library.topLevelDecks(in: french.id)
    check("one deck is made at the top", top.map(\.name) == ["Course"])
    check("with its chapters inside it", store.library.subdecks(of: top[0].id).map(\.name) == ["Chapter 1", "Chapter 2"])
    check("the topic under a chapter is merged into it",
          store.library.entries.first { $0.term == "le chien" }?.deckID == store.library.subdecks(of: top[0].id).first?.id)
    check("the deck counts every word inside it", store.library.wordCount(inDeck: top[0].id) == 3)
    check("and the result says where they went", result.count == 3 && result.placement.subdecks.count == 2)

    let secondPlan = AnkiImport.plan(notes: notes, mapping: mapping, fieldNames: type.fields, profile: french,
                                     audio: .deck, package: pictures, existing: store.library.entries)
    check("importing it again finds nothing new", secondPlan.usable.isEmpty)
}
