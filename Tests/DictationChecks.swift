import Foundation

/// The dictation game: splitting a phrase into words, marking what was typed
/// against it, and deciding what today asks for.
func checkDictation() {
    section("What counts as a word")

    check("a plain sentence splits on the spaces",
          DictationText.words(of: "I want to be here") == ["I", "want", "to", "be", "here"])
    check("an apostrophe stays inside the word",
          DictationText.words(of: "I don't want to") == ["I", "don't", "want", "to"])
    check("so does a hyphen",
          DictationText.words(of: "a well-known face") == ["a", "well-known", "face"])
    check("punctuation at the end is not a word",
          DictationText.words(of: "Das Haus ist groß.") == ["Das", "Haus", "ist", "groß"])
    check("nor is anything between sentences",
          DictationText.words(of: "Hello! How are you?") == ["Hello", "How", "are", "you"])
    check("an empty phrase has no words", DictationText.words(of: "   ").isEmpty)
    check("a number is a word", DictationText.words(of: "I am 30") == ["I", "am", "30"])

    section("The hint")

    check("the first letter and a dot for the rest",
          DictationHint.firstLetter.drawn(for: "don't") == "d····")
    check("a one-letter word is just itself",
          DictationHint.firstLetter.drawn(for: "I") == "I")
    check("lengths give nothing away",
          DictationHint.length.drawn(for: "house") == "·····")
    check("and nothing gives nothing", DictationHint.none.drawn(for: "house") == "—")

    section("Marking an answer")

    var result = DictationCheck.mark("I don't want to be here every day",
                                     against: "I don't want to be here every day")
    check("a right answer is right", result.isRight && result.isPerfect)
    check("with nothing wrong in it", result.mistakes == 0)
    check("and counts every word", result.words.count == 8)
    check("its accuracy is whole", result.accuracy == 1)

    result = DictationCheck.mark("i dont want to be here every day",
                                 against: "I don't want to be here every day")
    check("case is not what is being practised", result.words[0].mark == .right)
    check("nor is an apostrophe", result.words[1].mark == .right)
    check("so the answer still stands", result.isRight)

    result = DictationCheck.mark("Das Haus ist gross", against: "Das Haus ist groß")
    check("ß written out as ss is almost, not wrong", result.words[3].mark == .almost)
    check("and does not count as a mistake", result.isRight)
    check("but the answer is not called perfect", !result.isPerfect)

    result = DictationCheck.mark("I want to be there every day",
                                 against: "I don't want to be here every day")
    check("a word in the wrong place is marked", result.words.contains { $0.mark == .wrong })
    check("a short answer leaves the rest missing", result.words.contains { $0.mark == .missing })
    check("and it is not right", !result.isRight)

    result = DictationCheck.mark("the house is big and warm", against: "the house is big")
    check("words nobody asked for are counted", result.extra == ["and", "warm"])
    check("and spoil the answer", !result.isRight)

    result = DictationCheck.mark("", against: "the house is big")
    check("an empty answer misses everything", result.words.allSatisfy { $0.mark == .missing })
    check("and scores nothing", result.accuracy == 0)

    result = DictationCheck.mark("the house is small", against: "the house is big")
    check("three words of four is three quarters", abs(result.accuracy - 0.75) < 0.001)

    section("What an answer is worth")

    let perfect = DictationCheck.mark("the house is big", against: "the house is big")
    check("heard once and typed exactly is easy",
          DictationCheck.grade(perfect, replays: 0, revealed: false) == .easy)
    check("heard twice is good",
          DictationCheck.grade(perfect, replays: 1, revealed: false) == .good)
    check("looked up is again, however it was typed",
          DictationCheck.grade(perfect, replays: 0, revealed: true) == .again)

    let oneOff = DictationCheck.mark("the house is small", against: "the house is big")
    check("one word wrong is hard", DictationCheck.grade(oneOff, replays: 0, revealed: false) == .hard)
    let twoOff = DictationCheck.mark("a house was small", against: "the house is big")
    check("two is again", DictationCheck.grade(twoOff, replays: 0, revealed: false) == .again)

    let dropped = DictationCheck.mark("Der Bar ist hier", against: "Der Bär ist hier")
    check("a mark simply dropped is almost too", dropped.words[1].mark == .almost)
    let spelled = DictationCheck.mark("Der Baer ist hier", against: "Der Bär ist hier")
    check("and so is the letter written out", spelled.words[1].mark == .almost)
    let wrongWord = DictationCheck.mark("Der Ball ist hier", against: "Der Bär ist hier")
    check("but a different word is still wrong", wrongWord.words[1].mark == .wrong)

    let accented = DictationCheck.mark("Das Haus ist gross", against: "Das Haus ist groß")
    check("an accent missed is good rather than easy",
          DictationCheck.grade(accented, replays: 0, revealed: false) == .good)

    section("What the game is played with")

    let day = moment(2026, 6, 1, 9)
    var library = Library()
    let german = LanguageProfile(name: "German", learningCode: "de", nativeCode: "en")
    library.upsert(german)
    let a1 = Deck(profileID: german.id, name: "A1", createdAt: day)
    let a2 = Deck(profileID: german.id, name: "A2", createdAt: day)
    library.upsert(a1)
    library.upsert(a2)

    let haus = Entry(profileID: german.id, deckID: a1.id, term: "Haus", meaning: "house",
                     gender: .neuter, example: "Das Haus ist groß.", exampleTranslation: "The house is big.",
                     createdAt: day)
    let brot = Entry(profileID: german.id, deckID: a2.id, term: "Brot", meaning: "bread", createdAt: day)
    library.upsert(haus)
    library.upsert(brot)

    let written = [DictationSentence(text: "Ich gehe nach Hause.", meaning: "I am going home.")]

    var settings = DictationSettings(sources: [.word], dailyNew: 10)
    var items = DictationMaterial.items(for: german, in: library, settings: settings, sentences: written)
    check("words come one each", items.count == 2)
    check("and are said with their article", items.contains { $0.text == "das Haus" })
    check("a word carries its meaning", items.first { $0.entryID == brot.id }?.meaning == "bread")

    settings.sources = [.example]
    items = DictationMaterial.items(for: german, in: library, settings: settings, sentences: written)
    check("only words with an example have one", items.count == 1)
    check("and it is the example that is said", items.first?.text == "Das Haus ist groß.")
    check("with the example's own translation", items.first?.meaning == "The house is big.")

    settings.sources = [.written]
    items = DictationMaterial.items(for: german, in: library, settings: settings, sentences: written)
    check("a sentence of one's own is played too", items.first?.text == "Ich gehe nach Hause.")
    check("and belongs to no word", items.first?.entryID == nil)

    settings.sources = [.word, .example, .written]
    items = DictationMaterial.items(for: german, in: library, settings: settings, sentences: written)
    check("all three together", items.count == 4)
    check("and every key is its own", Set(items.map(\.key)).count == 4)

    settings.deckID = a1.id
    items = DictationMaterial.items(for: german, in: library, settings: settings, sentences: written)
    check("a deck narrows the words", !items.contains { $0.entryID == brot.id })
    check("but not the sentences of one's own", items.contains { $0.source == .written })

    check("words with nothing to say about them are what the companion is for",
          library.entriesWithoutExamples(in: german.id).map(\.term) == ["Brot"])

    section("The day")

    settings = DictationSettings(sources: [.word, .example, .written], dailyNew: 2)
    items = DictationMaterial.items(for: german, in: library, settings: settings, sentences: written)

    var queue = DictationQueue(items: items, records: [:], allowance: 2, now: day, shuffle: false)
    check("a day starts only as many as it promised", queue.total == 2)
    check("all of them new", queue.newCount == 2 && queue.dueCount == 0)
    check("and there is something in front", queue.current != nil)

    // One answered a week ago and due, one answered today and not.
    var seen = DictationRecord()
    seen.attempts = 1
    seen.scheduling.dueDate = day.addingTimeInterval(-86_400)
    var later = DictationRecord()
    later.attempts = 1
    later.scheduling.dueDate = day.addingTimeInterval(86_400)
    let records = [items[0].key: seen, items[1].key: later]

    queue = DictationQueue(items: items, records: records, allowance: 2, now: day, shuffle: false)
    check("what has come round again is in", queue.dueCount == 1)
    check("what has not is left for its day", !queue.pending.contains { $0.key == items[1].key })
    check("and the rest of the day is new phrases", queue.newCount == 2)
    check("repeats are asked first", queue.current?.key == items[0].key)

    queue = DictationQueue(items: items, records: records, allowance: 0, now: day, shuffle: false)
    check("a day already spent starts nothing new", queue.newCount == 0)
    check("but still asks for its repeats", queue.total == 1)

    section("Getting one wrong")

    queue = DictationQueue(items: items, records: [:], allowance: 4, now: day, shuffle: false)
    let first = queue.current
    check("answering it counts", queue.finish(.good))
    check("and moves on", queue.current?.key != first?.key)
    check("one of four is done", queue.done == 1)

    let faltered = queue.current
    check("a phrase that fell apart counts the first time", queue.finish(.again))
    check("and is still waiting", queue.pending.contains { $0.key == faltered?.key })
    check("but not straight away", queue.current?.key != faltered?.key)

    while queue.current?.key != faltered?.key, !queue.isFinished { queue.finish(.good) }
    check("it comes back before the sitting ends", queue.current?.key == faltered?.key)
    check("answering it again does not count twice", !queue.finish(.good))
    check("so four phrases are four", queue.done == 4)
    check("and then the day is over", queue.isFinished)

    section("Typing")

    var typing = DictationSession(queue: DictationQueue(
        items: [DictationItem(key: "written:1", text: "the house is big", meaning: "", source: .written, entryID: nil)],
        records: [:], allowance: 1, now: day, shuffle: false
    ))
    check("a box for every word of the phrase", typing.boxes.count == 4)
    check("nothing typed yet", typing.isEmpty)
    typing.setBox(0, to: "   ")
    check("and whitespace is still nothing", typing.isEmpty)

    typing.fill(from: 0, with: ["the", "house", "is", "big"])
    check("what was typed is what is marked",
          DictationCheck.mark(boxes: typing.boxes, against: "the house is big").isPerfect)
    check("and the boxes read as one line", typing.typed == "the house is big")

    // A box per word, so a word in the middle can be changed on its own
    // without the words after it being retyped.
    typing.setBox(3, to: "small")
    check("a word in the middle can be changed on its own", typing.typed == "the house is small")
    check("and only that word is marked wrong",
          DictationCheck.mark(boxes: typing.boxes, against: "the house is big").words.count { $0.isFaulty } == 1)

    // A word that was never caught leaves its box empty, and the box holds its
    // place: the word after it is not marked wrong for standing where it did.
    typing.setBox(1, to: "")
    typing.setBox(3, to: "big")
    let gapped = DictationCheck.mark(boxes: typing.boxes, against: "the house is big")
    check("an empty box is the word that was missed", gapped.words[1].mark == .missing)
    check("and the words after it are still right",
          gapped.words[2].mark == .right && gapped.words[3].mark == .right)

    // Two words in one box are both given up, in order: a box is a field, and
    // a field can be typed into freely.
    var crowded = DictationSession(queue: DictationQueue(
        items: [DictationItem(key: "written:3", text: "the house is big", meaning: "", source: .written, entryID: nil)],
        records: [:], allowance: 1, now: day, shuffle: false
    ))
    crowded.setBox(0, to: "the house")
    crowded.setBox(1, to: "is")
    crowded.setBox(2, to: "big")
    let spilled = DictationCheck.mark(boxes: crowded.boxes, against: "the house is big")
    check("two words in one box are read as two", spilled.words.count { $0.mark == .right } == 4)
    check("and nothing is counted as said after the phrase", spilled.extra.isEmpty)

    typing = DictationSession(queue: DictationQueue(
        items: [DictationItem(key: "written:2", text: "guten Tag", meaning: "", source: .written, entryID: nil)],
        records: [:], allowance: 1, now: day, shuffle: false
    ))
    typing.reveal()
    check("showing it fills the boxes in", typing.boxes == ["guten", "Tag"])
    check("and the answer counts as given", !typing.isEmpty)
    check("but it is worth nothing", DictationCheck.grade(
        DictationCheck.mark(boxes: typing.boxes, against: "guten Tag"), replays: 0, revealed: true) == .again)

    section("What is remembered")

    var progress = DictationProgress()
    let today = DictationProgress.day(day)
    progress.days[today] = DictationDay(newDone: 2, reviewsDone: 3, exercises: 5,
                                        wordsWanted: 20, wordsRight: 18, seconds: 90)
    check("a day knows what it did", progress.day(on: day).exercises == 5)
    check("and how accurate it was", abs(progress.day(on: day).accuracy - 0.9) < 0.001)
    check("what is left of today's new phrases",
          DictationMaterial.allowance(DictationSettings(dailyNew: 10), done: progress.day(on: day)) == 8)
    check("a day already met asks for nothing more",
          DictationMaterial.allowance(DictationSettings(dailyNew: 2), done: progress.day(on: day)) == 0)

    check("one day worked is a streak of one", progress.streak(on: day) == 1)
    let yesterday = day.addingTimeInterval(-86_400)
    progress.days[DictationProgress.day(yesterday)] = DictationDay(exercises: 3)
    check("two days running is two", progress.streak(on: day) == 2)
    let gap = day.addingTimeInterval(-3 * 86_400)
    progress.days[DictationProgress.day(gap)] = DictationDay(exercises: 3)
    check("a day missed ends it", progress.streak(on: day) == 2)

    var record = DictationRecord()
    record.attempts = 4
    record.wordsWanted = 20
    record.wordsRight = 15
    record.scheduling.intervalDays = 30
    progress.records["word:1"] = record
    progress.records["word:2"] = DictationRecord()
    check("a phrase answered is a phrase started", progress.started == 1)
    check("one past three weeks is known", progress.known == 1)
    check("and the accuracy is of every word ever asked",
          abs(progress.lifetimeAccuracy - 0.75) < 0.001)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let round = try! decoder.decode(DictationProgress.self, from: try! encoder.encode(progress))
    check("everything survives being saved", round.records.count == 2 && round.days.count == 3)
    check("including what the game is set to", round.settings.hint == progress.settings.hint)

    let old = try? decoder.decode(DictationProgress.self, from: Data("{}".utf8))
    check("a file written before any of this still opens", old != nil)
    check("and starts the game at its defaults", old?.settings.dailyNew == 10)
}
