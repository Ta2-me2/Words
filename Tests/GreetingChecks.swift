import Foundation

/// Which language somebody meant when they typed one word.
///
/// The table this walks is the whole of how the first screen works, and the
/// mistake that matters is not a missing greeting — it is a form listed under
/// one language that belongs to several, because that one chooses silently and
/// wrongly instead of asking.
func checkGreetings() {
    section("Greetings — reading one typed word")

    check("привет is Russian", Greetings.match("привет") == .one("ru"))
    check("and so is privet, typed by somebody with no Cyrillic keyboard",
          Greetings.match("privet") == .one("ru"))
    check("bonjour is French", Greetings.match("bonjour") == .one("fr"))
    check("hola is Spanish", Greetings.match("hola") == .one("es"))
    check("ni hao is Chinese", Greetings.match("ni hao") == .one("zh"))
    check("nihao, written as one word, is too", Greetings.match("nihao") == .one("zh"))
    check("konnichiwa is Japanese", Greetings.match("konnichiwa") == .one("ja"))
    check("merhaba is Turkish", Greetings.match("merhaba") == .one("tr"))
    check("gamarjoba is Georgian", Greetings.match("gamarjoba") == .one("ka"))

    check("hello is English, which is what almost everybody who types it means",
          Greetings.match("hello") == .one("en"))
    check("but helló is Hungarian", Greetings.match("helló") == .one("hu"))

    section("Greetings — the ones that have to ask")

    if case .several(let codes) = Greetings.match("hallo") {
        check("hallo asks", true)
        check("and offers German and Dutch", codes.contains("de") && codes.contains("nl"))
        check("and the two Scandinavians that write it too", codes.contains("da") && codes.contains("nb"))
    } else {
        check("hallo asks", false)
    }

    if case .several(let codes) = Greetings.match("hej") {
        check("hej asks", true)
        check("and offers Danish and Swedish", codes.contains("da") && codes.contains("sv"))
    } else {
        check("hej asks", false)
    }

    check("hei is Finnish as well as Norwegian", Greetings.match("hei") == .several(["fi", "nb"]))
    check("ola is Spanish as well as Portuguese", Greetings.match("ola") == .several(["es", "pt"]))
    check("hai is Indonesian as well as Dutch", Greetings.match("hai") == .several(["id", "nl"]))
    check("salve is Italian, Portuguese and Romanian", Greetings.match("salve") == .several(["it", "pt", "ro"]))
    check("salut is French and Romanian", Greetings.match("salut") == .several(["fr", "ro"]))
    check("servus is German and Romanian", Greetings.match("servus") == .several(["de", "ro"]))
    check("dobry den is Czech, Russian and Ukrainian",
          Greetings.match("dobry den") == .several(["cs", "ru", "uk"]))

    section("Greetings — reading it loosely enough")

    check("a capital does not matter", Greetings.match("Привет") == .one("ru"))
    check("nor does an exclamation mark", Greetings.match("Привет!") == .one("ru"))
    check("nor does space around it", Greetings.match("  bonjour  ") == .one("fr"))
    check("nor does doubled space inside it", Greetings.match("ni  hao") == .one("zh"))
    check("an accent missing is forgiven", Greetings.match("ola") != .unknown)
    check("buna reaches Romanian without its breve", Greetings.match("buna") == .one("ro"))
    check("czesc reaches Polish without its accents", Greetings.match("czesc") == .one("pl"))

    check("something that is not a greeting is not guessed at",
          Greetings.match("wibble") == .unknown)
    check("nor is an empty answer", Greetings.match("   ") == .unknown)

    section("Greetings — what the table must satisfy")

    var unreachable: [String] = []
    var unwritten: [String] = []
    var unnormalised: [String] = []

    for code in LanguageCatalog.codes {
        let forms = Greetings.forms(for: code)
        if forms.isEmpty { unwritten.append(code); continue }

        // Every language needs at least one form nobody else uses, or there
        // is no way to reach it by typing at all — only by opening the list.
        let own = forms.filter { form in
            if case .one(let only) = Greetings.match(form) { return only == code }
            return false
        }
        if own.isEmpty { unreachable.append(code) }

        for form in forms where Greetings.normalise(form) != form {
            unnormalised.append("\(code):\(form)")
        }
    }

    check("every language the app offers has greetings written for it", unwritten.isEmpty)
    check("every language can be reached by typing, not only by pointing", unreachable.isEmpty)
    check("every form in the table is already written the way it will be read", unnormalised.isEmpty)

    for code in LanguageCatalog.codes where !Greetings.forms(for: code).isEmpty {
        if Greetings.reply(for: code) == "Hello!" && code != "en" {
            check("\(code) says hello back in its own language", false)
        }
    }
    check("every language says hello back in its own language", true)

    check("languages do share forms, which is the point of asking", !Greetings.shared.isEmpty)
    check("and the sharing is worked out rather than written down twice",
          Greetings.shared["hallo"]?.count ?? 0 >= 3)
}
