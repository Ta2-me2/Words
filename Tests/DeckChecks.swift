import Foundation

/// Decks: a shelf inside a language. What they filter, what they share, and
/// what happens to the words when one is taken away.
func checkDecks() {
    let scheduler = FSRSScheduler()
    let today = moment(2026, 3, 2, 9)

    section("Shelves inside a language")

    var library = Library()
    let german = LanguageProfile(name: "German", learningCode: "de", nativeCode: "en", dailyNewLimit: 2)
    library.upsert(german)

    let nouns = Deck(profileID: german.id, name: "Nouns")
    let verbs = Deck(profileID: german.id, name: "Verbs")
    library.upsert(nouns)
    library.upsert(verbs)

    check("a language lists its decks by name",
          library.decks(in: german.id).map(\.displayName) == ["Nouns", "Verbs"])
    check("a deck with no name still reads",
          Deck(profileID: german.id, name: "  ").displayName == "Untitled Deck")

    let haus = Entry(profileID: german.id, deckID: nouns.id, term: "Haus", meaning: "house",
                     createdAt: today.addingTimeInterval(1))
    let brot = Entry(profileID: german.id, deckID: nouns.id, term: "Brot", meaning: "bread",
                     createdAt: today.addingTimeInterval(2))
    let gehen = Entry(profileID: german.id, deckID: verbs.id, term: "gehen", meaning: "to go",
                      createdAt: today.addingTimeInterval(3))
    let unfiled = Entry(profileID: german.id, term: "vielleicht", meaning: "perhaps",
                        createdAt: today.addingTimeInterval(4))
    for entry in [haus, brot, gehen, unfiled] { library.upsert(entry) }

    check("the whole language is every word", library.entries(in: german.id).count == 4)
    check("a deck is only its own", library.entries(in: german.id, deckID: nouns.id).count == 2)
    check("words can belong to no deck", library.unfiledCount(in: german.id) == 1)
    check("a deck knows how many words it holds", library.wordCount(inDeck: nouns.id) == 2)

    section("Studying one shelf")

    check("a deck's sitting is drawn from that deck",
          library.queue(for: german.id, deckID: verbs.id, asOf: today).count == 1)
    check("and the counts agree",
          library.counts(for: german.id, deckID: verbs.id, asOf: today).words == 1)

    // The daily allowance belongs to the language. Studying deck by deck must
    // not be a way of starting twenty new words in an afternoon.
    check("the whole language offers only the day's allowance",
          library.queue(for: german.id, asOf: today).count == 2)

    let first = library.queue(for: german.id, deckID: nouns.id, asOf: today)
    check("a deck may spend the allowance", first.count == 2)
    library.recordReview(entryID: first[0].entryID, cardID: first[0].cardID, grade: .good, at: today, using: scheduler)
    library.recordReview(entryID: first[1].entryID, cardID: first[1].cardID, grade: .good, at: today, using: scheduler)
    check("what one deck spends does not come out of another's day",
          library.queue(for: german.id, deckID: verbs.id, asOf: today).count == 1)
    check("but the language as a whole has spent its limit",
          library.counts(for: german.id, asOf: today).new == 0)

    section("Taking a shelf away")

    var removing = library
    removing.removeDeck(id: nouns.id)
    check("the deck is gone", removing.deck(id: nouns.id) == nil)
    check("its words are not", removing.entries(in: german.id).count == 4)
    check("they are simply unfiled", removing.unfiledCount(in: german.id) == 3)
    check("the other deck is untouched", removing.wordCount(inDeck: verbs.id) == 1)

    var moving = library
    moving.move(entries: [haus.id, unfiled.id], toDeck: verbs.id)
    check("words can be moved between decks", moving.wordCount(inDeck: verbs.id) == 3)
    check("and out of the deck they were in", moving.wordCount(inDeck: nouns.id) == 1)

    var closing = library
    closing.removeProfile(id: german.id)
    check("deleting a language takes its decks", closing.decks.isEmpty)

    section("A file that has been got at")

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    var dangling = library
    dangling.decks.removeAll { $0.id == nouns.id }
    let cleaned = try! decoder.decode(Library.self, from: try! encoder.encode(dangling))
    check("a word filed under a deck that is gone is unfiled, not lost",
          cleaned.entries(in: german.id).count == 4)
    check("and it reads as having no deck",
          cleaned.entries(in: german.id).allSatisfy { $0.deckID == nil || $0.deckID == verbs.id })

    let round = try! decoder.decode(Library.self, from: try! encoder.encode(library))
    check("decks survive a round trip", round.decks.count == 2)
    check("with the words still on them", round.wordCount(inDeck: nouns.id) == 2)

    section("Flags")

    check("a language gets the obvious flag for its code",
          LanguageProfile(name: "German", learningCode: "de", nativeCode: "en").flag == "🇩🇪")
    check("and a chosen one is kept",
          LanguageProfile(name: "Austrian", learningCode: "de", nativeCode: "en", flag: "🇦🇹").flag == "🇦🇹")
    check("a language spoken in several places offers several flags",
          LanguageCatalog.flags(for: "pt") == ["🇵🇹", "🇧🇷"])
    check("an unknown code still has something to show",
          LanguageCatalog.defaultFlag(for: "xx") == "🏳️")

    let old = """
    {
      "id": "\(UUID().uuidString)",
      "name": "German",
      "learningCode": "de",
      "nativeCode": "en",
      "dailyNewLimit": 20,
      "createdAt": "2026-01-01T00:00:00Z"
    }
    """
    let migrated = try! decoder.decode(LanguageProfile.self, from: Data(old.utf8))
    check("a profile written before flags existed gets one", migrated.flag == "🇩🇪")
}

/// Decks inside decks: what a parent contains, what each one's allowance is,
/// where words go when a deck is taken away, and the two levels nothing may
/// get past.
func checkSubdecks() async {
    let scheduler = FSRSScheduler()
    let today = moment(2026, 3, 2, 9)

    section("A deck with decks inside it")

    var library = Library()
    let german = LanguageProfile(name: "German", learningCode: "de", nativeCode: "en", dailyNewLimit: 5)
    library.upsert(german)

    let germany = Deck(profileID: german.id, name: "Germany", icon: .emoji("🇩🇪"))
    let a2 = Deck(profileID: german.id, name: "A2", parentID: germany.id)
    let a1 = Deck(profileID: german.id, name: "A1", parentID: germany.id, icon: .symbol("book.closed"))
    let travel = Deck(profileID: german.id, name: "Travel")
    for deck in [a2, travel, germany, a1] { library.upsert(deck) }

    check("a subdeck knows it is one", a1.isSubdeck && !germany.isSubdeck)
    check("the language lists each deck followed by the decks inside it",
          library.decks(in: german.id).map(\.displayName) == ["Germany", "A1", "A2", "Travel"])
    check("the top of the language is only the decks at the top",
          library.topLevelDecks(in: german.id).map(\.displayName) == ["Germany", "Travel"])
    check("a deck lists its subdecks by name", library.subdecks(of: germany.id).map(\.displayName) == ["A1", "A2"])
    check("a subdeck is read with the deck it sits in", library.path(of: a1) == "Germany › A1")
    check("and a deck at the top is read as itself", library.path(of: travel) == "Travel")

    var n = 0
    func word(_ term: String, in deck: Deck?) -> Entry {
        n += 1
        return Entry(profileID: german.id, deckID: deck?.id, term: term, meaning: term, createdAt: today.addingTimeInterval(Double(n)))
    }
    let direct = word("Land", in: germany)
    let haus = word("Haus", in: a1)
    let brot = word("Brot", in: a1)
    let zug = word("Zug", in: a2)
    let koffer = word("Koffer", in: travel)
    let loose = word("vielleicht", in: nil)
    for entry in [direct, haus, brot, zug, koffer, loose] { library.upsert(entry) }

    section("What a deck contains")

    check("a deck holds its own words and its subdecks' words",
          Set(library.entries(in: german.id, deckID: germany.id).map(\.term)) == ["Land", "Haus", "Brot", "Zug"])
    check("a subdeck holds only its own", Set(library.entries(in: german.id, deckID: a1.id).map(\.term)) == ["Haus", "Brot"])
    check("and not its sibling's", !library.entries(in: german.id, deckID: a1.id).contains { $0.term == "Zug" })
    check("nor the words filed in the deck above it", !library.entries(in: german.id, deckID: a1.id).contains { $0.term == "Land" })
    check("a deck's word count includes its subdecks", library.wordCount(inDeck: germany.id) == 4)
    check("the whole language is still every word", library.entries(in: german.id).count == 6)

    check("studying a deck studies the decks inside it",
          library.queue(for: german.id, deckID: germany.id, asOf: today).count == 4)
    check("and the number on its button is the number of cards behind it",
          library.counts(for: german.id, deckID: germany.id, asOf: today).total
              == library.queue(for: german.id, deckID: germany.id, asOf: today).count)
    check("studying a subdeck studies only that subdeck",
          library.queue(for: german.id, deckID: a1.id, asOf: today).count == 2)
    check("endless practice draws on the same words",
          library.endlessQueue(for: german.id, deckID: germany.id, pool: .everything).count == 4)

    section("Whose allowance")

    var limits = library
    var limitedGermany = germany
    limitedGermany.dailyNewLimit = 3
    limits.upsert(limitedGermany)

    check("a subdeck with no limit of its own works to the deck it sits in",
          limits.scope(forDeck: a1.id)?.dailyNewLimit == 3)
    check("a deck with no limit anywhere above follows the language",
          limits.scope(forDeck: travel.id)?.dailyNewLimit == nil
              && limits.queue(for: german.id, deckID: travel.id, asOf: today).count == 1)

    var limitedA1 = a1
    limitedA1.dailyNewLimit = 1
    limits.upsert(limitedA1)
    check("and a subdeck's own limit is its own", limits.queue(for: german.id, deckID: a1.id, asOf: today).count == 1)
    check("the deck above caps everything studied through it",
          limits.queue(for: german.id, deckID: germany.id, asOf: today).count == 3)

    let first = limits.queue(for: german.id, deckID: germany.id, asOf: today)
    for card in first {
        limits.recordReview(entryID: card.entryID, cardID: card.cardID, grade: .good, at: today, using: scheduler)
    }
    check("words started through the deck above spend its allowance",
          limits.counts(for: german.id, deckID: germany.id, asOf: today).new == 0)
    check("but a deck elsewhere in the language keeps its own day",
          limits.counts(for: german.id, deckID: travel.id, asOf: today).new == 1)

    section("Taking a deck away")

    var dropA1 = library
    dropA1.removeDeck(id: a1.id)
    check("a subdeck taken away is gone", dropA1.deck(id: a1.id) == nil)
    check("its words go up into the deck it sat in",
          dropA1.entries.filter { [haus.id, brot.id].contains($0.id) }.allSatisfy { $0.deckID == germany.id })
    check("so studying that deck asks for exactly what it asked for before",
          dropA1.queue(for: german.id, deckID: germany.id, asOf: today).count == 4)
    check("and its sibling is untouched", dropA1.deck(id: a2.id)?.parentID == germany.id)

    var dropGermany = library
    dropGermany.removeDeck(id: germany.id)
    check("a deck taken away takes the decks inside it", dropGermany.deck(id: a1.id) == nil && dropGermany.deck(id: a2.id) == nil)
    check("but not one word",  dropGermany.entries(in: german.id).count == 6)
    check("every word that was in it is back in the language, unfiled",
          dropGermany.unfiledCount(in: german.id) == 5)
    check("and a deck elsewhere keeps its words", dropGermany.wordCount(inDeck: travel.id) == 1)

    section("Taking a deck away with its words")

    check("a deck knows the words in it and in its subdecks",
          library.entryIDs(inDeck: germany.id) == [direct.id, haus.id, brot.id, zug.id])
    check("and a subdeck only its own", library.entryIDs(inDeck: a1.id) == [haus.id, brot.id])

    var historied = library
    historied.recordReview(entryID: haus.id, cardID: haus.cards[0].id, grade: .good, at: today, using: scheduler)

    var wipeGermany = historied
    wipeGermany.removeDeckAndWords(id: germany.id)
    check("a deck taken away with its words takes its subdecks",
          wipeGermany.deck(id: germany.id) == nil && wipeGermany.deck(id: a1.id) == nil && wipeGermany.deck(id: a2.id) == nil)
    check("and every word in any of them", wipeGermany.entries(in: german.id).map(\.term).sorted() == ["Koffer", "vielleicht"])
    check("but nothing outside it: another deck keeps its word", wipeGermany.wordCount(inDeck: travel.id) == 1)
    check("and a word with no deck stays", wipeGermany.entry(id: loose.id) != nil)
    check("while what was studied stays on the record", wipeGermany.reviews.count == 1)

    var wipeA1 = historied
    wipeA1.removeDeckAndWords(id: a1.id)
    check("a subdeck taken away with its words leaves its parent standing", wipeA1.deck(id: germany.id) != nil)
    check("with the parent's own words and its other subdeck's words",
          wipeA1.entryIDs(inDeck: germany.id) == [direct.id, zug.id])

    section("Two levels, and no further")

    check("a new deck can go inside a deck at the top", library.canNest(nil, inside: germany.id))
    check("but not inside a subdeck", !library.canNest(nil, inside: a1.id))
    check("a deck cannot go inside itself", !library.canNest(travel.id, inside: travel.id))
    check("a deck with decks inside it stays at the top", !library.canNest(germany.id, inside: travel.id))
    check("a deck without any can move under another", library.canNest(travel.id, inside: germany.id))

    var french = LanguageProfile(name: "French", learningCode: "fr", nativeCode: "en")
    french.id = UUID()
    library.upsert(french)
    let paris = Deck(profileID: french.id, name: "Paris")
    library.upsert(paris)
    check("and never inside another language's deck", !library.canNest(travel.id, inside: paris.id))

    let orphan = Deck(profileID: german.id, name: "Orphan", parentID: UUID())
    let selfish = Deck(id: UUID(), profileID: german.id, name: "Selfish")
    var looped = selfish
    looped.parentID = selfish.id
    let deep = Deck(profileID: german.id, name: "Deep", parentID: a1.id)
    let crossing = Deck(profileID: german.id, name: "Crossing", parentID: paris.id)

    let repaired = Library.normalised(library.decks + [orphan, looped, deep, crossing])
    func parent(of deck: Deck) -> UUID? { repaired.first { $0.id == deck.id }?.parentID }
    check("a deck inside a deck that is not there comes to the top", parent(of: orphan) == nil)
    check("so does a deck inside itself", parent(of: looped) == nil)
    check("so does a third level", parent(of: deep) == nil)
    check("so does a deck inside another language's", parent(of: crossing) == nil)
    check("and the decks that were right are left alone", parent(of: a1) == germany.id && parent(of: a2) == germany.id)
    check("nothing is deleted in the repair", repaired.count == library.decks.count + 4)

    var twoWay = Deck(profileID: german.id, name: "One")
    var otherWay = Deck(profileID: german.id, name: "Two")
    twoWay.parentID = otherWay.id
    otherWay.parentID = twoWay.id
    let untangled = Library.normalised([twoWay, otherWay])
    check("two decks inside each other both come to the top", untangled.allSatisfy { $0.parentID == nil })

    section("Icons")

    check("a deck with no icon shows the ordinary stack", travel.displayIcon == .standard)
    check("and a chosen one is kept", germany.displayIcon == .emoji("🇩🇪"))
    check("an emoji typed in is recognised", DeckIcon.emoji(in: "🧠") == .emoji("🧠"))
    check("a flag is one emoji, not two letters", DeckIcon.emoji(in: "🇦🇹") == .emoji("🇦🇹"))
    check("a sequence joined into one picture stays one", DeckIcon.emoji(in: "👩‍🏫") == .emoji("👩‍🏫"))
    check("only the first one counts", DeckIcon.emoji(in: " 📚🎓") == .emoji("📚"))
    check("a letter is not an emoji", DeckIcon.emoji(in: "A") == nil)
    check("nor is a digit, whatever Unicode thinks of it", DeckIcon.emoji(in: "7") == nil)
    check("nor is nothing at all", DeckIcon.emoji(in: "   ") == nil)

    section("On disk")

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let round = try! decoder.decode(Library.self, from: try! encoder.encode(library))
    check("subdecks survive a round trip", round.subdecks(of: germany.id).map(\.id) == [a1.id, a2.id])
    check("so do both kinds of icon",
          round.deck(id: germany.id)?.icon == .emoji("🇩🇪") && round.deck(id: a1.id)?.icon == .symbol("book.closed"))

    let written = """
    {"id":"\(UUID().uuidString)","profileID":"\(german.id.uuidString)","name":"Verbs","createdAt":"2026-01-01T00:00:00Z"}
    """
    let older = try! decoder.decode(Deck.self, from: Data(written.utf8))
    check("a deck written before subdecks existed is a deck at the top", older.parentID == nil)
    check("with the ordinary icon", older.icon == nil && older.displayIcon == .standard)

    var tampered = library
    tampered.decks.append(deep)
    let read = try! decoder.decode(Library.self, from: try! encoder.encode(tampered))
    check("a file with a third level in it opens with that deck at the top",
          read.deck(id: deep.id)?.parentID == nil)

    section("Making a deck with its subdecks")

    let store = LibraryStore(persistence: MemoryPersistence())
    await store.load()
    let spanish = store.addProfile(name: "Spanish", learningCode: "es", nativeCode: "en")
    let spain = store.addDeck(
        profileID: spanish.id,
        name: "Spain",
        icon: .emoji("🇪🇸"),
        subdecks: [("A1", nil), ("  ", nil), ("A2", .symbol("star"))]
    )!
    check("the deck is made", store.library.deck(id: spain.id) != nil)
    check("with the subdecks written in the same sheet",
          store.library.subdecks(of: spain.id).map(\.displayName) == ["A1", "A2"])
    check("a subdeck with no name is not made", store.library.decks(in: spanish.id).count == 3)
    check("each keeps its own icon", store.library.subdecks(of: spain.id).last?.icon == .symbol("star"))

    let a1ID = store.library.subdecks(of: spain.id)[0].id
    check("a deck cannot be made inside a subdeck", store.addDeck(profileID: spanish.id, name: "Deeper", parentID: a1ID) == nil)
    let late = store.addDeck(profileID: spanish.id, name: "B1", parentID: spain.id, subdecks: [("Ignored", nil)])
    check("a subdeck can be added later", late?.parentID == spain.id)
    check("and cannot bring decks of its own", store.library.subdecks(of: late!.id).isEmpty)

    section("A deck that arrived with its recordings")

    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "words-deck-delete-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let files = LibraryStore(persistence: FileLibraryPersistence(fileURL: root.appending(path: "Library.json")))
    await files.load()
    let francais = files.addProfile(name: "French", learningCode: "fr", nativeCode: "en")
    let verbs = files.addDeck(profileID: francais.id, name: "Verbs", subdecks: [("-er Verbs", nil)])!
    let er = files.library.subdecks(of: verbs.id)[0]
    let parler = files.addEntry(profileID: francais.id, deckID: er.id, term: "parler", meaning: "to speak")!
    let aimer = files.addEntry(profileID: francais.id, deckID: er.id, term: "aimer", meaning: "to love")!
    let rester = files.addEntry(profileID: francais.id, term: "rester", meaning: "to stay")!

    let sound = root.appending(path: "sound.m4a")
    try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try! Data("not really a sound".utf8).write(to: sound)
    await files.attachAudio(from: sound, to: parler.id, kind: .imported)
    await files.attachAudio(from: sound, to: aimer.id, kind: .imported)
    await files.attachAudio(from: sound, to: rester.id, kind: .imported)

    func onDisk(_ entryID: UUID, in library: Library) -> Bool {
        guard let path = library.entry(id: entryID)?.audio?.file else { return false }
        return FileManager.default.fileExists(atPath: root.appending(path: path).path)
    }
    let parlerFile = files.library.entry(id: parler.id)!.audio!.file
    check("the recordings are on disk to begin with", onDisk(parler.id, in: files.library) && onDisk(aimer.id, in: files.library))

    // A word outside the deck that happens to share a recording with one
    // inside it — a library merged or edited by hand.
    files.update { library in
        let index = library.entries.firstIndex { $0.id == rester.id }!
        library.entries[index].audio?.file = parlerFile
    }

    files.deleteDeck(id: verbs.id, includingWords: true)
    try? await Task.sleep(for: .milliseconds(150))

    check("deleting a deck with its words deletes the words in its subdecks", files.library.entry(id: aimer.id) == nil)
    check("and the recordings nobody else uses",
          !FileManager.default.fileExists(atPath: root.appending(path: "Media").appending(path: aimer.id.uuidString).path)
          && (try? FileManager.default.contentsOfDirectory(atPath: root.appending(path: "Media").path))?
              .contains { $0.hasPrefix(aimer.id.uuidString) } == false)
    check("but never a file a surviving word still plays",
          FileManager.default.fileExists(atPath: root.appending(path: parlerFile).path))
    check("the word outside the deck is untouched", files.library.entry(id: rester.id) != nil)

    let keepDeck = files.addDeck(profileID: francais.id, name: "Kept")!
    let kept = files.addEntry(profileID: francais.id, deckID: keepDeck.id, term: "garder", meaning: "to keep")!
    files.deleteDeck(id: keepDeck.id)
    check("deleting a deck without its words still keeps them, unfiled",
          files.library.entry(id: kept.id)?.deckID == nil)

    section("Games")

    // A choice of three needs three words, so A1 gets its third.
    var playable = library
    playable.upsert(word("Tisch", in: a1))
    let collections = GameVocabulary.collections(for: german, in: playable)
    check("a game offers a deck with its subdecks' words",
          collections.first { $0.deckID == germany.id }?.words.count == 5)
    check("and names a subdeck by where it sits",
          collections.contains { $0.name == "Germany › A1" })
}
