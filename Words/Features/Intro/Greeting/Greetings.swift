import Foundation

/// What somebody typed when they were asked to say hello in the language they
/// want to learn.
nonisolated enum GreetingMatch: Equatable, Sendable {

    /// One language, and no doubt about it.
    case one(String)

    /// Several languages write it the same way. "hallo" is German and Dutch,
    /// "hej" is Danish and Swedish — so the companion asks rather than guesses,
    /// which is the only honest thing to do and also the best moment in the
    /// whole introduction.
    case several([String])

    /// Not a greeting this app knows. Not a failure either: the list is right
    /// there, and so is making a language of your own.
    case unknown
}

/// How to say hello in each language the app knows.
///
/// Two kinds of spelling, because two kinds of person type them. Somebody with
/// a Russian keyboard writes "привет"; somebody who has decided this morning to
/// learn Russian has no Cyrillic keyboard at all and writes "privet". Both have
/// to work, or the screen asks a question half its readers cannot answer.
///
/// Which forms are *shared* matters more than how many there are. A form listed
/// under one language that really belongs to three makes the app choose
/// silently and wrongly; a form listed under all three makes it ask. The table
/// is therefore checked for sharing rather than for completeness, and the
/// sharing is worked out from the table itself rather than written down twice.
nonisolated enum Greetings {

    /// What the companion writes back, in the language that was asked for.
    ///
    /// Shown, never spoken: it has no mouth, and a human voice coming out of a
    /// drawn face is the wrong kind of surprise.
    static func reply(for code: String) -> String {
        table[code]?.reply ?? "Hello!"
    }

    static func forms(for code: String) -> [String] {
        table[code]?.forms ?? []
    }

    /// Which language somebody meant.
    static func match(_ typed: String) -> GreetingMatch {
        let asked = normalise(typed)
        guard !asked.isEmpty else { return .unknown }

        if let exact = index[asked] { return result(exact) }
        if let folded = foldedIndex[fold(asked)] { return result(folded) }
        return .unknown
    }

    private static func result(_ codes: [String]) -> GreetingMatch {
        codes.count == 1 ? .one(codes[0]) : .several(codes)
    }

    // MARK: - Reading what was typed

    /// Lower case, no punctuation, one space between words.
    ///
    /// Punctuation goes because "Привет!" and "привет" are the same answer, and
    /// the inner spacing is evened out because "ni hao" and "ni  hao" are too.
    static func normalise(_ text: String) -> String {
        let stripped = text.lowercased().unicodeScalars.compactMap { scalar -> Character? in
            // An apostrophe inside a word is part of how it is written down
            // rather than a gap in it: strict Hepburn writes こんにちは as
            // and turning that mark into a space would make two
            // words out of one. Everything else that is punctuation is a gap.
            if Self.apostrophes.contains(scalar) { return nil }
            if CharacterSet.punctuationCharacters.contains(scalar)
                || CharacterSet.symbols.contains(scalar) { return " " }
            return Character(scalar)
        }
        return String(stripped)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static let apostrophes = CharacterSet(charactersIn: "'\u{2019}\u{02BC}\u{02BB}")

    /// The same without its accents, so a learner who cannot find the á on
    /// their keyboard still gets "olá" when they write "ola".
    ///
    /// Only ever a second attempt, after the exact spelling has been tried, so
    /// a language that distinguishes two words by an accent is never robbed of
    /// the distinction.
    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en"))
    }

    // MARK: - The table

    private struct Language {
        /// What the companion writes back.
        var reply: String
        /// Everything somebody might plausibly type to mean this language.
        var forms: [String]
    }

    private static let index: [String: [String]] = {
        var index: [String: [String]] = [:]
        for code in table.keys.sorted() {
            for form in table[code]!.forms {
                let key = normalise(form)
                guard !key.isEmpty else { continue }
                if index[key]?.contains(code) != true { index[key, default: []].append(code) }
            }
        }
        return index
    }()

    private static let foldedIndex: [String: [String]] = {
        var folded: [String: [String]] = [:]
        for (key, codes) in index {
            let plain = fold(key)
            for code in codes where folded[plain]?.contains(code) != true {
                folded[plain, default: []].append(code)
            }
        }
        return folded.mapValues { $0.sorted() }
    }()

    /// Every form that more than one language writes the same way, which is
    /// the only part of this table that can be wrong in a way nobody notices.
    static var shared: [String: [String]] {
        index.filter { $0.value.count > 1 }
    }

    /// Checked against Wiktionary, Omniglot and each language's own learner
    /// material, and then checked again by somebody looking for the one kind
    /// of mistake that matters: a form listed under one language that really
    /// belongs to several. Six of those were found and fixed — "ola" is
    /// Spanish as well as Portuguese, "hai" is Indonesian as well as Dutch,
    /// "salve" is Portuguese and Romanian as well as Italian, "hei" is Finnish
    /// as well as Norwegian, "dobry den" is Czech, Russian and Ukrainian — and
    /// every one of them would have chosen silently and wrongly.
    ///
    /// "hello" is the exception that proves the rule. Hungarian writes *helló*
    /// and *heló*, and a Hungarian learner who drops the accent lands on
    /// English — because "hello" unaccented is the most typed string there is
    /// and is almost always meant as English, and asking everybody about it to
    /// catch the rare case would be the wrong trade.
    private static let table: [String: Language] = [
        "ar": Language(reply: "مرحبا!", forms: [
            "ahlan", "assalamu alaikum", "marhaba", "marhaban", "salaam", "salam",
            "salam alaikum", "أهلا", "السلام عليكم", "سلام", "مرحبا", "مرحبًا"
        ]),
        "cs": Language(reply: "Ahoj!", forms: ["ahoj", "cau", "dobry den", "dobrý den", "nazdar", "čau"]),
        "da": Language(reply: "Hej!", forms: [
            "dav", "god dag", "goddag", "hallo", "halloj", "halløj", "hej", "hejsa"
        ]),
        "de": Language(reply: "Hallo!", forms: [
            "gruss gott", "grüß gott", "guten tag", "hallo", "hoi", "moin", "servus"
        ]),
        "el": Language(reply: "Γεια σου!", forms: [
            "geia", "geia sas", "geia sou", "herete", "kalimera", "yasas", "yasou", "yia sou",
            "γεια", "γεια σας", "γεια σου", "καλημέρα", "χαίρετε"
        ]),
        "en": Language(reply: "Hello!", forms: ["hello", "hey", "hi"]),
        "es": Language(reply: "¡Hola!", forms: ["buenas", "buenos dias", "buenos días", "hola", "ola"]),
        "fi": Language(reply: "Hei!", forms: [
            "hei", "hyvaa paivaa", "hyvää päivää", "moi", "moikka", "terve"
        ]),
        "fr": Language(reply: "Bonjour !", forms: ["bonjour", "coucou", "salut"]),
        "he": Language(reply: "שלום!", forms: ["ahalan", "shalom", "אהלן", "הי", "היי", "שלום"]),
        "hi": Language(reply: "नमस्ते!", forms: [
            "namaskaar", "namaskar", "namaste", "नमस्कार", "नमस्ते", "हेलो", "हैलो"
        ]),
        "hr": Language(reply: "Bok!", forms: ["bok", "cao", "dobar dan", "hej", "zdravo", "ćao"]),
        "hu": Language(reply: "Szia!", forms: [
            "helló", "heló", "jo napot", "jó napot", "szervusz", "szia", "sziasztok"
        ]),
        "id": Language(reply: "Halo!", forms: ["hai", "halo", "salam"]),
        "it": Language(reply: "Ciao!", forms: ["buon giorno", "buongiorno", "ciao", "salve"]),
        "ja": Language(reply: "こんにちは", forms: [
            "konichiwa", "konnichi wa", "konnichiha", "konnichiwa", "こんにちは",
            "こんにちわ", "やあ", "ハロー"
        ]),
        "ka": Language(reply: "გაგიმარჯოს!", forms: [
            "gamardjoba", "gamarjoba", "gamarjobat", "გამარჯობა", "გამარჯობათ", "ჰეი"
        ]),
        "kk": Language(reply: "Сәлем!", forms: [
            "salem", "salemetsiz be", "sälem", "ассалаумағалейкум", "сәлем", "сәлеметсіз бе",
            "сәлеметсіздер ме"
        ]),
        "ko": Language(reply: "안녕하세요!", forms: [
            "annyeong", "annyeong haseyo", "annyeonghaseyo", "annyong", "annyonghaseyo",
            "anyeonghaseyo", "안녕", "안녕하세요", "안녕하십니까"
        ]),
        "nb": Language(reply: "Hei!", forms: ["god dag", "goddag", "halla", "hallo", "hei", "heisann"]),
        "nl": Language(reply: "Hallo!", forms: ["dag", "goedendag", "goeiedag", "hai", "hallo", "hoi"]),
        "pl": Language(reply: "Cześć!", forms: [
            "czesc", "cześć", "dzien dobry", "dzień dobry", "hej", "siema", "witam"
        ]),
        "pt": Language(reply: "Olá!", forms: ["bom dia", "buenas", "oi", "ola", "olá", "salve"]),
        "ro": Language(reply: "Bună!", forms: [
            "buna", "buna ziua", "bună", "bună ziua", "ciao", "noroc", "salut", "salve",
            "servus"
        ]),
        "ru": Language(reply: "Привет!", forms: [
            "dobry den", "dobryi den", "dobryy den", "privet", "priviet", "privyet",
            "zdrastvuyte", "zdravstvujte", "zdravstvuyte", "добрый день", "здравствуй",
            "здравствуйте", "здрасте", "привет"
        ]),
        "sv": Language(reply: "Hej!", forms: [
            "god dag", "goddag", "halla", "hallå", "hej", "hejsan", "tja", "tjena"
        ]),
        "th": Language(reply: "สวัสดี", forms: [
            "sawadee", "sawasdee", "sawatdee", "sawatdi", "สวัสดี", "สวัสดีครับ", "สวัสดีค่ะ",
            "หวัดดี"
        ]),
        "tr": Language(reply: "Merhaba!", forms: ["merhaba", "merhabalar", "selam", "selamlar"]),
        "uk": Language(reply: "Привіт!", forms: [
            "dobry den", "dobryi den", "privit", "pryvit", "добридень", "добрий день",
            "здрастуйте", "привіт"
        ]),
        "vi": Language(reply: "Xin chào!", forms: [
            "chao", "chao ban", "chào", "chào bạn", "hế lô", "xin chao", "xin chào"
        ]),
        "zh": Language(reply: "你好！", forms: [
            "ni hao", "ni3 hao3", "nihao", "nin hao", "nǐ hǎo", "你好", "哈啰", "哈囉", "嗨", "您好"
        ]),
    ]
}