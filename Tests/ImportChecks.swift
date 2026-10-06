import Foundation

/// Reading somebody else's word list. The format is simple; the text it arrives
/// in never is.
func checkImport() {
    section("The format")

    var plan = WordImport.plan(text: "Haus;house", language: "de")
    check("a word and a meaning are enough", plan.words.count == 1)
    check("the word is read", plan.words.first?.term == "Haus")
    check("and the meaning", plan.words.first?.meaning == "house")
    check("with no gender claimed", plan.words.first?.gender == nil)

    plan = WordImport.plan(text: "Mutter;mother;f", language: "de")
    check("a third field of f is a gender", plan.words.first?.gender == .feminine)
    check("and is not mistaken for an example", plan.words.first?.example.isEmpty == true)

    plan = WordImport.plan(text: "Mutter;mother;m\nVater;father;n", language: "de")
    check("m is masculine", plan.words.first?.gender == .masculine)
    check("n is neuter", plan.words.last?.gender == .neuter)

    plan = WordImport.plan(text: "gehen;to go;Ich gehe nach Hause.;I am going home.", language: "de")
    check("a third field that is not a gender is an example",
          plan.words.first?.example == "Ich gehe nach Hause.")
    check("and the fourth is its translation",
          plan.words.first?.exampleTranslation == "I am going home.")
    check("with no gender invented", plan.words.first?.gender == nil)

    plan = WordImport.plan(text: "Mutter;mother;f;Meine Mutter kocht.;My mother is cooking.", language: "de")
    check("all five fields read together", plan.words.first?.gender == .feminine)
    check("the example lands in the example", plan.words.first?.example == "Meine Mutter kocht.")
    check("and its translation after it", plan.words.first?.exampleTranslation == "My mother is cooking.")

    plan = WordImport.plan(text: "gehen;to go;;Ich gehe.;I go.", language: "de")
    check("an empty gender column is skipped, not read as an example",
          plan.words.first?.example == "Ich gehe.")

    plan = WordImport.plan(text: "Haus;house;", language: "de")
    check("a trailing semicolon is typing, not a column",
          plan.words.first?.example.isEmpty == true)

    section("What a person's file looks like")

    let messy = """
    # German words

    Haus;house
    - Mutter;mother;f

    ## Verbs
    gehen\tto go
    Brot — bread
    Wasser - water

    Fehler
    """
    plan = WordImport.plan(text: messy, language: "de")
    check("headings are not words", !plan.words.contains { $0.term.hasPrefix("#") })
    check("blank lines are skipped", plan.words.count == 5)
    check("a bullet is punctuation", plan.words.first { $0.term == "Mutter" }?.gender == .feminine)
    check("a tab separates as well as a semicolon",
          plan.words.first { $0.term == "gehen" }?.meaning == "to go")
    check("so does a dash between spaces",
          plan.words.first { $0.term == "Brot" }?.meaning == "bread")
    check("a plain hyphen too",
          plan.words.first { $0.term == "Wasser" }?.meaning == "water")
    check("a line with no meaning is reported, not guessed at", plan.problems.count == 1)
    check("and says which line it was", plan.problems.first?.line == 11)
    check("with the text that could not be read", plan.problems.first?.text == "Fehler")

    section("An article says the gender")

    plan = WordImport.plan(text: "die Mutter;mother", language: "de")
    check("an article typed in front of the word is read", plan.words.first?.gender == .feminine)
    check("and taken off the word", plan.words.first?.term == "Mutter")

    plan = WordImport.plan(text: "der Berg;mountain\ndas Brot;bread", language: "de")
    check("der is masculine", plan.words.first?.gender == .masculine)
    check("das is neuter", plan.words.last?.gender == .neuter)

    plan = WordImport.plan(text: "die Mutter;mother;n", language: "de")
    check("a written gender wins over the typed article", plan.words.first?.gender == .neuter)

    plan = WordImport.plan(text: "the house;house", language: "en")
    check("a language with no articles of ours leaves the word alone",
          plan.words.first?.term == "the house")

    section("Words the language already has")

    let existing = [
        Entry(profileID: UUID(), term: "Haus", meaning: "house"),
        Entry(profileID: UUID(), term: "Brot", meaning: "bread")
    ]
    plan = WordImport.plan(text: "haus;house\nWasser;water\nWasser;water again", language: "de", existing: existing)
    check("a word already in the library is marked", plan.words.first?.duplicate == .inLibrary)
    check("whatever its capitals", plan.duplicates.count == 2)
    check("the second copy in the file is marked too", plan.words.last?.duplicate == .inFile)
    check("only the new one would be added", plan.importable.map(\.term) == ["Wasser"])

    section("Genders and their articles")

    check("German gives feminine die", LanguageGenders.article(.feminine, language: "de") == "die")
    check("masculine der", LanguageGenders.article(.masculine, language: "de") == "der")
    check("neuter das", LanguageGenders.article(.neuter, language: "de") == "das")
    check("German marks gender", LanguageGenders.marksGender("de"))
    check("English does not", !LanguageGenders.marksGender("en"))
    check("a language we have no rules for says nothing rather than guessing",
          LanguageGenders.article(.feminine, language: "ja") == nil)

    check("f, m and n are read", Gender.parse("F") == .feminine && Gender.parse(" m ") == .masculine)
    check("so are the words themselves", Gender.parse("neuter") == .neuter)
    check("a sentence is not a gender", Gender.parse("Meine Mutter kocht.") == nil)
    check("nor is a word that merely starts with one", Gender.parse("fahren") == nil)

    let split = LanguageGenders.split(term: "die Mutter", language: "de")
    check("splitting takes the article off", split.term == "Mutter")
    check("and reports what it said", split.gender == .feminine)
    check("a word with no article is left as it is",
          LanguageGenders.split(term: "Mutter", language: "de").term == "Mutter")
    check("and a two-word phrase that starts with something else too",
          LanguageGenders.split(term: "guten Morgen", language: "de").gender == nil)
    check("a sentence that happens to start with an article is left alone",
          LanguageGenders.split(term: "das ist gut", language: "de").term == "das ist gut")

    section("Words written before genders existed")

    let libraryProfile = LanguageProfile(name: "German", learningCode: "de", nativeCode: "en")
    let legacy = """
    {
      "formatVersion": 1,
      "profiles": [{
        "id": "\(libraryProfile.id.uuidString)",
        "name": "German",
        "learningCode": "de",
        "nativeCode": "en",
        "dailyNewLimit": 20,
        "createdAt": "2026-01-01T00:00:00Z"
      }],
      "entries": [
        { "id": "\(UUID().uuidString)", "profileID": "\(libraryProfile.id.uuidString)",
          "term": "das Brot", "meaning": "bread" },
        { "id": "\(UUID().uuidString)", "profileID": "\(libraryProfile.id.uuidString)",
          "term": "Entschuldigung", "meaning": "sorry" },
        { "id": "\(UUID().uuidString)", "profileID": "\(libraryProfile.id.uuidString)",
          "term": "das ist gut", "meaning": "that is good" }
      ]
    }
    """
    let lifted = try! JSONDecoder.words.decode(Library.self, from: Data(legacy.utf8))
    let brot = lifted.entries.first { $0.meaning == "bread" }
    check("an article typed into the word becomes a gender", brot?.gender == .neuter)
    check("and comes off the word", brot?.term == "Brot")
    check("but still reads the same", brot?.displayTerm(in: libraryProfile) == "das Brot")
    check("a word with no article is untouched",
          lifted.entries.first { $0.meaning == "sorry" }?.term == "Entschuldigung")
    check("and a phrase is never taken apart",
          lifted.entries.first { $0.meaning == "that is good" }?.term == "das ist gut")
    check("the file is stamped forward", lifted.formatVersion == Library.currentFormatVersion)

    section("What the word is called on screen")

    let profile = LanguageProfile(name: "German", learningCode: "de", nativeCode: "en")
    var entry = Entry(profileID: profile.id, term: "Mutter", meaning: "mother", gender: .feminine)
    check("a gendered word is read with its article", entry.displayTerm(in: profile) == "die Mutter")
    check("but stored without one", entry.term == "Mutter")
    entry.gender = nil
    check("a word with no gender is itself", entry.displayTerm(in: profile) == "Mutter")

    let english = LanguageProfile(name: "English", learningCode: "en", nativeCode: "ru")
    let word = Entry(profileID: english.id, term: "house", meaning: "дом", gender: .feminine)
    check("a language with no articles shows none", word.displayTerm(in: english) == "house")

    section("Examples are kept with the word")

    let full = Entry(profileID: profile.id, term: "Mutter", meaning: "mother",
                     gender: .feminine, example: "Meine Mutter kocht.", exampleTranslation: "My mother cooks.")
    check("an example is searchable", full.matches("kocht"))
    check("so is its translation", full.matches("cooks"))

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let round = try! decoder.decode(Entry.self, from: try! encoder.encode(full))
    check("everything survives a round trip",
          round.gender == .feminine && round.example == "Meine Mutter kocht." && round.exampleTranslation == "My mother cooks.")

    let old = """
    {
      "id": "\(UUID().uuidString)",
      "profileID": "\(profile.id.uuidString)",
      "term": "Haus",
      "meaning": "house"
    }
    """
    let migrated = try! decoder.decode(Entry.self, from: Data(old.utf8))
    check("a word written before any of this reads as having none of it",
          migrated.gender == nil && migrated.example.isEmpty && migrated.cards.count == 1)
    check("and no transcription either", migrated.transcription.isEmpty)

    section("How a word is said")

    var spoken = WordImport.plan(text: "დედა;mother;[deda]", language: "ka")
    check("a bracketed field is a transcription", spoken.words.first?.transcription == "deda")
    check("and the brackets are not kept", spoken.words.first?.transcription.contains("[") == false)
    check("it is not read as an example", spoken.words.first?.example.isEmpty == true)

    spoken = WordImport.plan(text: "Wasser;water;n;[ˈvasɐ];Das Wasser ist kalt.;The water is cold.;das Wasser, die Wässer", language: "de")
    check("a gender before it is still a gender", spoken.words.first?.gender == .neuter)
    check("the transcription is read", spoken.words.first?.transcription == "ˈvasɐ")
    check("the example after it lands in the example", spoken.words.first?.example == "Das Wasser ist kalt.")
    check("its translation after that", spoken.words.first?.exampleTranslation == "The water is cold.")
    check("and the last field is the note", spoken.words.first?.note == "das Wasser, die Wässer")

    spoken = WordImport.plan(text: "sakhli;house;/saxli/", language: "ka")
    check("slashes mark a transcription too", spoken.words.first?.transcription == "saxli")

    spoken = WordImport.plan(text: "gehen;to go;Ich gehe.;I go.", language: "de")
    check("a list written before transcriptions existed still reads its example as one",
          spoken.words.first?.example == "Ich gehe." && spoken.words.first?.transcription.isEmpty == true)

    spoken = WordImport.plan(text: "დედა;mother;;;irregular", language: "ka")
    check("a language with no genders has no gender column to skip",
          spoken.words.first?.note == "irregular")
    check("and nothing is mistaken for an example", spoken.words.first?.example.isEmpty == true)

    spoken = WordImport.plan(text: "gehen;to go;;Ich gehe.;I go.;strong verb", language: "de")
    check("a language with genders still skips the empty one",
          spoken.words.first?.example == "Ich gehe." && spoken.words.first?.note == "strong verb")

    spoken = WordImport.plan(text: "\u{10E1}\u{10D0}\u{10EE}\u{10DA}\u{10D8};house;;;;no articles", language: "ka")
    check("a semicolon kept for a column the language has not still leaves the note last",
          spoken.words.first?.note == "no articles")
    check("and leaves the example empty", spoken.words.first?.example.isEmpty == true)

    spoken = WordImport.plan(text: "Haus;house;[]", language: "de")
    check("empty brackets are not a transcription", spoken.words.first?.transcription.isEmpty == true)

    let said = Entry(profileID: profile.id, term: "დედა", meaning: "mother", transcription: "deda")
    check("a transcription is searchable", said.matches("deda"))
    let saidAgain = try! decoder.decode(Entry.self, from: try! encoder.encode(said))
    check("and survives a round trip", saidAgain.transcription == "deda")

    section("Georgian")

    check("the language can be chosen", LanguageCatalog.codes.contains("ka"))
    check("it has its own flag", LanguageCatalog.defaultFlag(for: "ka") == "\u{1F1EC}\u{1F1EA}")
    check("and no gender to ask about", !LanguageGenders.marksGender("ka"))
}
