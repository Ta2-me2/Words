import Foundation

/// What every language does with gender, checked language by language.
///
/// The table in `LanguageGenders` is the one place in the app where being
/// wrong teaches somebody something false about their language, so it is
/// checked twice: once for the facts of each row, and once for the invariants
/// every row has to satisfy whatever language is added next.
func checkLanguageRules() {
    section("Language rules — the invariants every row must satisfy")

    for code in LanguageGenders.ruledCodes {
        guard let rule = LanguageGenders.rule(for: code) else {
            check("\(code) has a rule", false)
            continue
        }

        check("\(code) marks at least one gender", !rule.genders.isEmpty)

        // Every gender the language offers has something to show for it, or a
        // picker would have a button with nothing written on it.
        let marks = rule.genders.compactMap { LanguageGenders.mark($0, language: code) }
        check("\(code) has a mark for every gender it marks", marks.count == rule.genders.count)

        // No two genders may share a mark: a mark whose job is to tell two
        // things apart and does not is a question with no answer. This is why
        // Romanian is written with labels although it has un/o — its
        // masculine and its neuter both take "un".
        check("\(code) tells its genders apart", Set(marks.map(\.text)).count == marks.count)

        // All spoken or all shown, never a mixture: the card draws them in one
        // place and the voice has to know whether to read what is there.
        check("\(code) is all articles or all labels", Set(marks.map(\.isSpoken)).count == 1)

        // A typed article cannot mean a gender the language does not have.
        let strays = rule.typed.filter { !rule.genders.contains($0.value) }
        check("\(code) types only genders it marks", strays.isEmpty)

        // An article and a vague article are different answers to the same
        // question, so nothing may be both.
        check("\(code) has no article that is both proof and not", rule.typed.keys.allSatisfy { !rule.vague.contains($0) })
    }

    // A language with no row marks no gender at all, and that is the answer
    // for twelve of the thirty-one rather than a gap in the table.
    for code in ["en", "fi", "hu", "tr", "ka", "kk", "id", "ja", "zh", "ko", "th", "vi"] {
        check("\(code) marks no gender", !LanguageGenders.marksGender(code))
        check("\(code) offers no gender to choose", LanguageGenders.genders(for: code).isEmpty)
        check("\(code) shows nothing beside a word", LanguageGenders.mark(.feminine, language: code) == nil)
    }

    check("a language the learner invented marks no gender", !LanguageGenders.marksGender("x-1a2b3c4d"))

    section("Language rules — articles said with the word")

    check("German still gives die", LanguageGenders.article(.feminine, language: "de") == "die")
    check("and der", LanguageGenders.article(.masculine, language: "de") == "der")
    check("and das", LanguageGenders.article(.neuter, language: "de") == "das")
    check("Greek gives three too", LanguageGenders.genders(for: "el").count == 3)
    check("Greek feminine is η", LanguageGenders.article(.feminine, language: "el") == "η")
    check("Dutch has a common gender, not a masculine", LanguageGenders.genders(for: "nl") == [.common, .neuter])
    check("Dutch common is de", LanguageGenders.article(.common, language: "nl") == "de")
    check("Dutch has no masculine to offer", LanguageGenders.mark(.masculine, language: "nl") == nil)
    check("Swedish cites gender with the indefinite article", LanguageGenders.article(.common, language: "sv") == "en")
    check("because its definite one is a suffix", LanguageGenders.article(.neuter, language: "sv") == "ett")
    check("Norwegian Bokmål offers three", LanguageGenders.genders(for: "nb").count == 3)
    check("and its feminine is ei", LanguageGenders.article(.feminine, language: "nb") == "ei")

    section("Language rules — genders shown but never said")

    check("Russian marks gender", LanguageGenders.marksGender("ru"))
    check("with no article to say", LanguageGenders.article(.feminine, language: "ru") == nil)
    check("but a label to show", LanguageGenders.mark(.feminine, language: "ru")?.text == "жен.")
    check("which is never spoken", LanguageGenders.mark(.feminine, language: "ru")?.isSpoken == false)
    check("Ukrainian does not borrow the Russian forms", LanguageGenders.mark(.masculine, language: "uk")?.text == "ч.")
    check("Polish writes no full stop", LanguageGenders.mark(.feminine, language: "pl")?.text == "ż")
    check("Croatian's neuter is two letters", LanguageGenders.mark(.neuter, language: "hr")?.text == "sr")
    check("Czech keeps its full stops", LanguageGenders.mark(.neuter, language: "cs")?.text == "s.")
    check("Arabic is written out in full", LanguageGenders.mark(.feminine, language: "ar")?.text == "مؤنث")
    check("Hebrew uses a geresh, not an apostrophe",
          LanguageGenders.mark(.feminine, language: "he")?.text == "\u{05E0}\u{05F3}")
    check("Hindi uses the devanagari abbreviation sign",
          LanguageGenders.mark(.masculine, language: "hi")?.text.hasSuffix("\u{0970}") == true)
    check("Romanian is shown rather than said, because un cannot tell m from n",
          LanguageGenders.mark(.neuter, language: "ro")?.isSpoken == false)

    section("Language rules — the shape an article takes in front of a word")

    check("l'eau, not la eau", LanguageGenders.mark(.feminine, before: "eau", language: "fr")?.text == "l’")
    check("l'homme, because its h is mute", LanguageGenders.mark(.masculine, before: "homme", language: "fr")?.text == "l’")
    check("le hibou, because its h is not", LanguageGenders.mark(.masculine, before: "hibou", language: "fr")?.text == "le")
    check("la honte likewise", LanguageGenders.mark(.feminine, before: "honte", language: "fr")?.text == "la")
    check("la maison is untouched", LanguageGenders.mark(.feminine, before: "maison", language: "fr")?.text == "la")
    check("lo studente, not il studente", LanguageGenders.mark(.masculine, before: "studente", language: "it")?.text == "lo")
    check("il libro stays il", LanguageGenders.mark(.masculine, before: "libro", language: "it")?.text == "il")
    check("l'amico", LanguageGenders.mark(.masculine, before: "amico", language: "it")?.text == "l’")
    check("l'hotel, because Italian h is always silent",
          LanguageGenders.mark(.masculine, before: "hotel", language: "it")?.text == "l’")
    check("lo iato, where the i is a consonant", LanguageGenders.mark(.masculine, before: "iato", language: "it")?.text == "lo")
    check("la iena, for the same reason", LanguageGenders.mark(.feminine, before: "iena", language: "it")?.text == "la")
    check("lo zio", LanguageGenders.mark(.masculine, before: "zio", language: "it")?.text == "lo")
    check("lo gnomo", LanguageGenders.mark(.masculine, before: "gnomo", language: "it")?.text == "lo")
    check("el agua is feminine and still takes el",
          LanguageGenders.mark(.feminine, before: "agua", language: "es")?.text == "el")
    check("la casa does not", LanguageGenders.mark(.feminine, before: "casa", language: "es")?.text == "la")
    check("German changes for nothing", LanguageGenders.mark(.feminine, before: "Oper", language: "de")?.text == "die")
    check("nor does Greek", LanguageGenders.mark(.masculine, before: "άνθρωπος", language: "el")?.text == "ο")

    section("Language rules — what is said and what is only shown")

    check("an elided article joins its word",
          LanguageGenders.mark(.feminine, before: "eau", language: "fr")?.spacer == "")
    check("an ordinary one does not",
          LanguageGenders.mark(.feminine, language: "de")?.spacer == " ")
    check("die Mutter", LanguageGenders.mark(.feminine, language: "de")?.phrase(with: "Mutter") == "die Mutter")
    check("l'eau", LanguageGenders.mark(.feminine, before: "eau", language: "fr")?.phrase(with: "eau") == "l’eau")
    check("жен. мама", LanguageGenders.mark(.feminine, language: "ru")?.phrase(with: "мама") == "жен. мама")

    let german = LanguageProfile(name: "German", learningCode: "de", nativeCode: "en")
    let russian = LanguageProfile(name: "Russian", learningCode: "ru", nativeCode: "en")
    let french = LanguageProfile(name: "French", learningCode: "fr", nativeCode: "en")

    let mutter = Entry(profileID: german.id, term: "Mutter", meaning: "mother", gender: .feminine)
    let mama = Entry(profileID: russian.id, term: "мама", meaning: "mother", gender: .feminine)
    let eau = Entry(profileID: french.id, term: "eau", meaning: "water", gender: .feminine)

    check("a German word is read with its article", mutter.displayTerm(in: german) == "die Mutter")
    check("a Russian word is read without its label", mama.displayTerm(in: russian) == "мама")
    check("though the label is there to show", mama.genderMark(in: russian)?.text == "жен.")
    check("a French word is read elided", eau.displayTerm(in: french) == "l’eau")
    check("the article alone, where there is one", mutter.articlePrefix(in: german) == "die")
    check("and nothing where the gender is only shown", mama.articlePrefix(in: russian) == nil)

    section("Language rules — reading what a learner typed")

    check("die Mutter is Mutter, feminine", LanguageGenders.split(term: "die Mutter", language: "de") == ("Mutter", .feminine))
    check("ein Haus is Haus, and no gender, because ein is masculine and neuter both",
          LanguageGenders.split(term: "ein Haus", language: "de") == ("Haus", nil))
    check("das ist gut is left exactly as written",
          LanguageGenders.split(term: "das ist gut", language: "de").term == "das ist gut")
    check("Mutter on its own is untouched", LanguageGenders.split(term: "Mutter", language: "de").term == "Mutter")
    check("der/die Bekannte is not guessed at",
          LanguageGenders.dictionaryForm("der/die Bekannte, -n", language: "de").gender == nil)
    check("a plain noun still has its article taken",
          LanguageGenders.dictionaryForm("das Haus", language: "de").gender == .neuter)
    check("la casa is casa, feminine", LanguageGenders.split(term: "la casa", language: "es") == ("casa", .feminine))
    check("el agua loses its article", LanguageGenders.split(term: "el agua", language: "es").term == "agua")
    check("l'eau has no space and still loses it", LanguageGenders.split(term: "l’eau", language: "fr").term == "eau")
    check("a straight apostrophe works the same", LanguageGenders.split(term: "l'eau", language: "fr").term == "eau")
    check("and proves nothing, because l' is either gender",
          LanguageGenders.split(term: "l’eau", language: "fr").gender == nil)
    check("un'amica proves feminine", LanguageGenders.split(term: "un’amica", language: "it").gender == .feminine)
    check("en bok proves nothing in Bokmål", LanguageGenders.split(term: "en bok", language: "nb").gender == nil)
    check("ei bok proves feminine", LanguageGenders.split(term: "ei bok", language: "nb") == ("bok", .feminine))
    check("a Danish definite suffix is not an article",
          LanguageGenders.split(term: "drengen", language: "da").term == "drengen")
    check("a Russian word has no article to lose", LanguageGenders.split(term: "мама", language: "ru").term == "мама")

    section("Language rules — recognising a gender column")

    check("f is feminine anywhere", Gender.parse("f") == .feminine)
    check("so is ж", Gender.parse("ж") == .feminine)
    check("and жен.", Gender.parse("жен.") == .feminine)
    check("sr is Croatian neuter", Gender.parse("sr") == .neuter)
    check("the devanagari abbreviation reads too", Gender.parse("स्त्री\u{0970}") == .feminine)
    check("en is not resolved without a language, because it is two genders",
          Gender.parse("en") == nil)
    check("German reads der as the citation form it is", Gender.parse("der", language: "de") == .masculine)
    check("but not the accusative den, which is also a dative plural",
          Gender.parse("den", language: "de") == nil)
    check("Swedish den is common", Gender.parse("den", language: "sv") == .common)
    check("Norwegian en is masculine", Gender.parse("en", language: "nb") == .masculine)
    check("Swedish en is common", Gender.parse("en", language: "sv") == .common)
    check("a language with no genders has no gender column", Gender.parse("m", language: "tr") == nil)
    check("nor does Japanese", Gender.parse("f", language: "ja") == nil)
    check("a gender the language does not mark is refused", Gender.parse("m", language: "nl") == nil)
    check("while the one it does is read", Gender.parse("de", language: "nl") == .common)
    check("an example is not a gender", Gender.parse("the mother of my father") == nil)

    section("Language rules — which way a language is read")

    check("Arabic reads right to left", LanguageCatalog.isRightToLeft("ar"))
    check("so does Hebrew", LanguageCatalog.isRightToLeft("he"))
    check("Persian too, for a profile written before it was dropped", LanguageCatalog.isRightToLeft("fa"))
    check("English does not", !LanguageCatalog.isRightToLeft("en"))
    check("nor Russian", !LanguageCatalog.isRightToLeft("ru"))
    check("nor Japanese", !LanguageCatalog.isRightToLeft("ja"))
    check("nor a language the learner invented", !LanguageCatalog.isRightToLeft("x-1a2b3c4d"))

    section("Language rules — the catalogue")

    check("thirty-one languages are offered", LanguageCatalog.codes.count == 31)
    check("nineteen of them have rules", LanguageGenders.ruledCodes.count == 19)
    check("every ruled language is one the app offers",
          LanguageGenders.ruledCodes.allSatisfy { LanguageCatalog.codes.contains($0) })
    check("Norwegian is offered as nb, which is where macOS keeps its voices",
          LanguageCatalog.codes.contains("nb") && !LanguageCatalog.codes.contains("no"))
    check("and nb still has a flag", LanguageCatalog.defaultFlag(for: "nb") == "🇳🇴")
    check("Croatian is offered", LanguageCatalog.codes.contains("hr"))
    check("Kazakh is offered", LanguageCatalog.codes.contains("kk"))
    check("Persian is not, having neither a voice nor a course anywhere",
          !LanguageCatalog.codes.contains("fa"))
    check("no code appears twice", Set(LanguageCatalog.codes).count == LanguageCatalog.codes.count)
}

/// Languages somebody added themselves.
func checkCustomLanguages() {
    section("Custom languages")

    let made = CustomLanguage(name: "Sindarin", flag: "🌙")
    check("it gets a private-use code", made.id.hasPrefix("x-"))
    check("which is recognised as one somebody added", CustomLanguage.isCustom(made.id))
    check("a real language code is not", !CustomLanguage.isCustom("de"))
    check("two of them do not collide", CustomLanguage(name: "A", flag: "🅰️").id != CustomLanguage(name: "B", flag: "🅱️").id)
    check("a nameless one is not usable", !CustomLanguage(name: "  ", flag: "🏳️").isUsable)

    var library = Library()
    library.upsert(made)
    LanguageCatalog.register(library.customLanguages)

    check("the catalogue knows its name", LanguageCatalog.name(for: made.id) == "Sindarin")
    check("in English too, for the model", LanguageCatalog.englishName(for: made.id) == "Sindarin")
    check("and its flag", LanguageCatalog.defaultFlag(for: made.id) == "🌙")
    check("it is offered after the ones the app knows", LanguageCatalog.customCodes == [made.id])
    check("it marks no gender", !LanguageGenders.marksGender(made.id))

    // A profile studying it holds the language down.
    let profile = LanguageProfile(name: "Sindarin", learningCode: made.id, nativeCode: "en")
    library.upsert(profile)
    check("the library can say what is studying it", library.profilesUsing(made.id).count == 1)
    check("so deleting it is refused", library.removeCustomLanguage(id: made.id) == false)
    check("and it is still there", library.customLanguage(id: made.id) != nil)

    library.removeProfile(id: profile.id)
    check("with the profile gone it can be deleted", library.removeCustomLanguage(id: made.id) == true)
    check("and it is gone", library.customLanguage(id: made.id) == nil)

    // Renaming is an upsert, not a second language.
    var renamed = made
    renamed.name = "Quenya"
    library.upsert(made)
    library.upsert(renamed)
    check("renaming replaces rather than adds", library.customLanguages.count == 1)
    check("and the name changed", library.customLanguage(id: made.id)?.name == "Quenya")

    LanguageCatalog.register([])
    check("an unregistered code falls back to itself", LanguageCatalog.name(for: made.id) == made.id.uppercased())
}

/// The move from "no" to "nb", and the second lift of typed articles.
func checkLanguageMigration() {
    section("Reading a library written before the languages were fixed")

    let norwegian = """
    {
      "formatVersion": 3,
      "libraryID": "11111111-1111-1111-1111-111111111111",
      "createdAt": "2025-01-01T09:00:00Z",
      "profiles": [{
        "id": "22222222-2222-2222-2222-222222222222",
        "name": "Norsk",
        "learningCode": "no",
        "nativeCode": "en",
        "flag": "🇳🇴",
        "dailyNewLimit": 20,
        "desiredRetention": 0.9,
        "speechRate": 0.45,
        "speaksOnReveal": false,
        "speaksExampleOnReveal": false,
        "newWordOrder": "added",
        "studyDirection": "wordToMeaning",
        "createdAt": "2025-01-01T09:00:00Z"
      }],
      "decks": [], "entries": [], "reviews": [], "sessions": [], "extras": [], "streakFreezes": []
    }
    """

    guard let library = try? JSONDecoder.words.decode(Library.self, from: Data(norwegian.utf8)) else {
        check("a Norwegian library written as no can be read", false)
        return
    }
    check("a Norwegian library written as no can be read", true)
    check("and is now nb, where the voices are", library.profiles.first?.learningCode == "nb")
    check("the format is stamped up to date", library.formatVersion == Library.currentFormatVersion)

    // The second lift: a Spanish word that carried its own article.
    let spanish = """
    {
      "formatVersion": 3,
      "libraryID": "33333333-3333-3333-3333-333333333333",
      "createdAt": "2025-01-01T09:00:00Z",
      "profiles": [{
        "id": "44444444-4444-4444-4444-444444444444",
        "name": "Español",
        "learningCode": "es",
        "nativeCode": "en",
        "flag": "🇪🇸",
        "dailyNewLimit": 20,
        "desiredRetention": 0.9,
        "speechRate": 0.45,
        "speaksOnReveal": false,
        "speaksExampleOnReveal": false,
        "newWordOrder": "added",
        "studyDirection": "wordToMeaning",
        "createdAt": "2025-01-01T09:00:00Z"
      }],
      "decks": [],
      "entries": [{
        "id": "55555555-5555-5555-5555-555555555555",
        "profileID": "44444444-4444-4444-4444-444444444444",
        "term": "la casa",
        "meaning": "house",
        "transcription": "",
        "example": "", "exampleTranslation": "", "note": "",
        "createdAt": "2025-01-01T09:00:00Z",
        "updatedAt": "2025-01-01T09:00:00Z",
        "cards": []
      }],
      "reviews": [], "sessions": [], "extras": [], "streakFreezes": []
    }
    """

    guard let lifted = try? JSONDecoder.words.decode(Library.self, from: Data(spanish.utf8)) else {
        check("a Spanish library can be read", false)
        return
    }
    check("a Spanish word that carried its article is lifted", lifted.entries.first?.term == "casa")
    check("and the article it carried became its gender", lifted.entries.first?.gender == .feminine)
}
