import Foundation

/// The instructions A List hands to an AI. They are only worth anything if a
/// list written the way they say is a list the import reads, so most of what
/// is checked here is the parser reading lines built from the prompt's words.
func checkListPrompt() {
    section("The prompt for a language that marks gender")

    let german = ListPrompt.standard(learning: "de", native: "ru")
    check("it gives the format, transcription and note included", german.contains("word;meaning;gender;[transcription];example;example translation;note"))
    check("it names the language being learned", german.contains("German word"))
    check("and the one meanings are written in", german.contains("in Russian"))
    check("feminine is f, with its article", german.contains("f for feminine (die)"))
    check("masculine is m", german.contains("m for masculine (der)"))
    check("neuter is n", german.contains("n for neuter (das)"))
    check("nouns come without their article", german.contains("without their article"))
    check("a transcription goes in square brackets", german.contains("inside square brackets"))
    check("and needs no empty column when there is none", german.contains("never needs an empty column"))
    check("a note is asked for last", german.contains("- note:"))
    check("it asks for the list in one code block", german.contains("single code block"))
    check("it describes the format and asks for nothing else",
          !german.contains("100") && !german.lowercased().contains("a1"))

    section("The prompt for a language that does not")

    let english = ListPrompt.standard(learning: "en", native: "ru")
    check("it gives the format without a gender column", english.contains("word;meaning;[transcription];example;example translation;note"))
    check("and says nothing about gender", !english.lowercased().contains("gender"))
    check("it names English", english.contains("English word"))

    section("Lists written the way the prompt says")

    // The line the prompt itself gives as the example of an empty middle field.
    let skipped = german.range(of: "word;meaning;;").map { start in
        String(german[start.lowerBound...].prefix { $0 != "\n" })
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
    check("the prompt shows a line with an empty gender", skipped == "word;meaning;;example;example translation")
    var plan = WordImport.plan(text: skipped ?? "", language: "de")
    check("and that line reads its example as the example", plan.words.first?.example == "example")
    check("and its translation as the translation", plan.words.first?.exampleTranslation == "example translation")

    let answer = """
    ```text
    Haus;дом;n;Das Haus ist groß.;Дом большой.
    Mutter;мама;f
    gehen;идти;;Ich gehe nach Hause.;Я иду домой.
    schnell;быстрый, скорый
    ```
    """
    plan = WordImport.plan(text: answer, language: "de")
    check("the fences around a code block are not words", plan.words.count == 4 && plan.problems.isEmpty)
    let haus = plan.words.first { $0.term == "Haus" }
    check("a noun gets its gender", haus?.gender == .neuter)
    check("its example", haus?.example == "Das Haus ist groß.")
    check("and the example's translation", haus?.exampleTranslation == "Дом большой.")
    check("a noun with nothing after its gender is still a word",
          plan.words.first { $0.term == "Mutter" }?.gender == .feminine)
    let gehen = plan.words.first { $0.term == "gehen" }
    check("a verb keeps its empty gender field and no gender", gehen?.gender == nil)
    check("and its example lands where it belongs", gehen?.example == "Ich gehe nach Hause.")
    check("several meanings stay one meaning",
          plan.words.first { $0.term == "schnell" }?.meaning == "быстрый, скорый")

    plan = WordImport.plan(
        text: "```\nhouse;дом;This is my house.;Это мой дом.\nquickly;быстро\n```",
        language: "en"
    )
    check("a four-field line reads for a language without gender", plan.words.count == 2)
    check("with its example", plan.words.first?.example == "This is my house.")
    check("and its translation", plan.words.first?.exampleTranslation == "Это мой дом.")

    section("A prompt the learner changed")

    var profile = LanguageProfile(name: "German", learningCode: "de", nativeCode: "ru")
    check("a language nobody changed uses the standard prompt",
          ListPrompt.current(for: profile) == ListPrompt.standard(for: profile))
    check("the standard text is not stored", ListPrompt.stored(ListPrompt.standard(for: profile), for: profile) == nil)
    check("nor is it with a stray newline after it",
          ListPrompt.stored(ListPrompt.standard(for: profile) + "\n", for: profile) == nil)
    check("an emptied box goes back to the standard", ListPrompt.stored("  \n", for: profile) == nil)
    check("a changed prompt is stored as it was written",
          ListPrompt.stored("Only nouns, please.", for: profile) == "Only nouns, please.")

    profile.listPrompt = "Only nouns, please."
    check("and is what the language uses from then on", ListPrompt.current(for: profile) == "Only nouns, please.")

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let round = try! JSONDecoder.words.decode(LanguageProfile.self, from: try! encoder.encode(profile))
    check("it survives being saved", round.listPrompt == "Only nouns, please.")

    let old = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"German","learningCode":"de","nativeCode":"ru"}"#
    let decoded = try? JSONDecoder.words.decode(LanguageProfile.self, from: Data(old.utf8))
    check("a language saved before prompts existed still opens", decoded != nil)
    check("and has the standard one", decoded?.listPrompt == nil)
}
