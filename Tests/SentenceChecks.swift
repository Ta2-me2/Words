import Foundation

/// Asking the companion for an example sentence: what it is told, and what is
/// made of what it says back.
///
/// The reading half is where the checks are, because it is the half that has
/// to survive a model going wrong — and because a wrong example sentence is
/// taught to somebody who cannot yet tell it is wrong.
func checkSentencePrompt() {
    let german = LanguageProfile(name: "German", learningCode: "de", nativeCode: "ru")

    section("What the companion is told")

    let told = SentencePrompt.instructions(for: german)
    check("both languages are named", told.contains("German") && told.contains("Russian"))
    check("so is how long a sentence may be", told.contains("3") && told.contains("16"))
    check("and that nothing may come with it", told.lowercased().contains("nothing else at all"))

    check("the word is asked for with its meaning",
          SentencePrompt.ask(word: "Haus", meaning: "дом") == "Word: Haus (дом)")
    check("and on its own when there is none",
          SentencePrompt.ask(word: "Haus", meaning: "  ") == "Word: Haus")

    section("Reading an answer")

    check("two tidy lines are read as they are",
          SentencePrompt.read("Das Haus ist sehr groß.\nДом очень большой.", word: "Haus")
          .map { $0 == ("Das Haus ist sehr groß.", "Дом очень большой.") } == true)

    check("a greeting in front of it is stepped over",
          SentencePrompt.read("Sure! Here you go:\nDas Haus ist sehr groß.\nДом очень большой.", word: "Haus")?
            .sentence == "Das Haus ist sehr groß.")

    check("labels come off",
          SentencePrompt.read("Sentence: Das Haus ist groß.\nTranslation: Дом большой.", word: "Haus")
          .map { $0 == ("Das Haus ist groß.", "Дом большой.") } == true)

    check("so do bullets, stars and quotation marks",
          SentencePrompt.read("- **“Das Haus ist groß.”**\n* „Дом большой.“", word: "Haus")?
            .sentence == "Das Haus ist groß.")

    check("an inflected word still counts as the word",
          SentencePrompt.read("Ich gehe jeden Tag nach Hause.\nЯ каждый день иду домой.", word: "gehen")?
            .sentence == "Ich gehe jeden Tag nach Hause.")

    check("both halves on one line are told apart",
          SentencePrompt.read("Das Haus ist groß. — Дом большой.", word: "Haus")
          .map { $0 == ("Das Haus ist groß.", "Дом большой.") } == true)

    check("a slash between them does as well",
          SentencePrompt.read("Das Haus ist groß. / Дом большой.", word: "Haus")?
            .translation == "Дом большой.")

    check("a hyphen inside a word is not a separator",
          SentencePrompt.read("Das ist ein gut-bekanntes Haus.\nЭто известный дом.", word: "Haus")?
            .sentence == "Das ist ein gut-bekanntes Haus.")

    section("Refusing an answer")

    check("a sentence without the word is no answer",
          SentencePrompt.read("Der Hund schläft im Garten.\nСобака спит в саду.", word: "Haus") == nil)
    check("nor is one word",
          SentencePrompt.read("Haus.\nДом.", word: "Haus") == nil)
    check("nor a paragraph",
          SentencePrompt.read(
            "Das Haus ist sehr groß und es steht am Ende der Straße neben dem Park wo die Kinder immer spielen.",
            word: "Haus"
          ) == nil)
    check("nor nothing at all", SentencePrompt.read("", word: "Haus") == nil)
    check("nor an apology", SentencePrompt.read("I’m sorry, I can’t help with that.", word: "Haus") == nil)

    check("a sentence buried in an explanation is still found",
          SentencePrompt.read(
            "Here is an example for the word Haus, which means house:\nDas Haus ist groß.\nДом большой.\nI used the simple present.",
            word: "Haus"
          ).map { $0 == ("Das Haus ist groß.", "Дом большой.") } == true)

    section("The translation on its own")

    check("the sentence repeated is not a translation",
          SentencePrompt.read("Das Haus ist groß.\nDas Haus ist groß.", word: "Haus")?
            .translation == "")
    check("an essay is not a translation either",
          SentencePrompt.read(
            "Das Haus ist groß.\nThis sentence uses the nominative case because the noun is the subject of the verb sein, and the adjective after it takes no ending at all.",
            word: "Haus"
          )?.translation == "")
    check("but the sentence is kept when its translation is not",
          SentencePrompt.read("Das Haus ist groß.", word: "Haus")
          .map { $0 == ("Das Haus ist groß.", "") } == true)

    section("Whether the word was used")

    check("the word itself", SentencePrompt.uses("Haus", in: "Das Haus ist groß."))
    check("whatever the case", SentencePrompt.uses("haus", in: "Das Haus ist groß."))
    check("a form of it", SentencePrompt.uses("gehen", in: "Ich gehe nach Hause."))
    check("a plural of it", SentencePrompt.uses("Haus", in: "Die Häuser sind alt.") == false)
    check("a short word has to be itself", SentencePrompt.uses("ich", in: "Ich bin hier."))
    check("and is not found inside another",
          SentencePrompt.uses("der", in: "Die Kinder spielen.") == false)
    check("a word that is not there is not there",
          SentencePrompt.uses("Haus", in: "Der Hund schläft.") == false)
}
