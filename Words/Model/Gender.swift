import Foundation
import Synchronization

/// The grammatical gender of a word.
///
/// Stored on the word as a fact about it, never as an article: which article a
/// gender takes is a property of the language, and the same word imported into
/// two languages would take two different ones.
nonisolated enum Gender: String, Codable, CaseIterable, Identifiable, Sendable {
    case feminine = "f"
    case masculine = "m"
    case neuter = "n"

    /// One class covering what used to be masculine and feminine: Dutch
    /// *de*-words, Swedish *en*-ord, Danish *en*-ord.
    ///
    /// Its own case rather than a borrowed masculine, because filing a Dutch
    /// *de*-word as masculine would be a lie in stored data — it would leave
    /// "feminine" permanently empty, travel into exported packages, and reach
    /// the model in the word-list prompt as a fact about the language that is
    /// not true of it.
    case common = "c"

    var id: String { rawValue }

    /// The single letter used in import files and in tight spaces.
    var short: String { rawValue }

    var title: String {
        switch self {
        case .feminine: "Feminine"
        case .masculine: "Masculine"
        case .neuter: "Neuter"
        case .common: "Common"
        }
    }

    /// Reads the third field of an import line.
    ///
    /// Deliberately narrow: one token, and one of the ones a word list actually
    /// uses. Anything else is not a gender, which is how the parser knows the
    /// field was an example instead.
    ///
    /// Language-blind on purpose. The caller knows which language it is
    /// reading and refuses a gender that language does not have; this only has
    /// to recognise a token as *meaning* a gender, and a list written in one
    /// language is often marked up in another.
    /// Where the language is known it decides, and it also refuses: a gender
    /// the language does not mark is not a gender, so a word list for Turkish
    /// has no gender column at all and its third field is an example.
    ///
    /// It has to decide, because some tokens mean two things. "den" is the
    /// German accusative masculine and the Swedish definite common; "en" is
    /// masculine in Norwegian and common in Swedish. Those are left out of the
    /// language-blind table entirely rather than resolved by a coin toss.
    static func parse(_ text: String, language code: String? = nil) -> Gender? {
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !token.isEmpty, !token.contains(" ") else { return nil }

        guard let code else {
            return Self.universalTokens[token] ?? LanguageGenders.markTokens[token]
        }

        let marked = LanguageGenders.genders(for: code)
        guard !marked.isEmpty else { return nil }

        guard let gender = LanguageGenders.tokens(for: code)[token]
            ?? Self.universalTokens[token]
            ?? LanguageGenders.markTokens[token]
        else { return nil }

        return marked.contains(gender) ? gender : nil
    }

    /// The abbreviations that mean a gender in no language in particular: the
    /// letters a word list is marked up with, and the English words.
    private static let universalTokens: [String: Gender] = [
        "f": .feminine, "f.": .feminine, "fem": .feminine, "fem.": .feminine,
        "feminine": .feminine, "w": .feminine,
        "m": .masculine, "m.": .masculine, "masc": .masculine, "masc.": .masculine,
        "masculine": .masculine,
        "n": .neuter, "n.": .neuter, "neut": .neuter, "neut.": .neuter,
        "neuter": .neuter, "s": .neuter, "s.": .neuter,
        "c": .common, "c.": .common, "comm": .common, "comm.": .common,
        "common": .common, "utrum": .common, "fælleskøn": .common
    ]
}

/// Everything a language does with gender, in one value.
///
/// Three questions that have to agree with each other: which genders the
/// language marks, what it shows for each of them, and what a learner might
/// type in front of a word. They were three separate switches once, and three
/// switches can disagree — a language could offer a gender it had no mark for,
/// which is how a French learner would have been shown a bare "n" as the third
/// article. One row per language, or none.
nonisolated struct GenderRule: Sendable {

    /// The genders this language marks, in the order a learner of it meets
    /// them. Never empty: a language with no genders has no rule at all.
    var genders: [Gender]

    /// What the language shows for each gender it marks.
    ///
    /// Either every gender takes an article or every gender takes a label,
    /// never a mixture, because the card shows them in one place and the voice
    /// has to know whether to read what is there.
    var marks: [Gender: GenderMark]

    /// Articles a learner might type in front of a word, and the gender each
    /// one proves.
    ///
    /// Read as a *citation form* — the nominative singular a dictionary lists
    /// a noun under — because that is what the word field asks for. It matters,
    /// because most of these articles mean something else elsewhere in the
    /// paradigm: German "der" is also the feminine dative (*der Mutter*) and
    /// Dutch "de" is the plural of every noun, neuters included (*de huizen*).
    /// Somebody filing a declined form or a plural as a headword gets the
    /// gender of the headword they did not type, and the picker beside the
    /// field is how they put it right.
    var typed: [String: Gender]

    /// Articles a learner might type that prove nothing about gender: Dutch
    /// *een* goes in front of any word, Italian *l'* in front of either.
    ///
    /// Worth knowing separately rather than leaving out, because the article
    /// still has to come off the word — *l'eau* is filed under E — and a
    /// guess at the gender would be worse than the empty picker the learner
    /// can fill in themselves.
    var vague: Set<String>

    init(genders: [Gender], marks: [Gender: GenderMark], typed: [String: Gender], vague: Set<String> = []) {
        self.genders = genders
        self.marks = marks
        self.typed = typed
        self.vague = vague
    }

    /// A language whose genders are written as articles in front of the noun.
    static func articles(_ pairs: KeyValuePairs<Gender, String>, typed: [String: Gender], vague: Set<String> = []) -> GenderRule {
        GenderRule(
            genders: pairs.map(\.key),
            marks: Dictionary(uniqueKeysWithValues: pairs.map { ($0.key, GenderMark.article($0.value)) }),
            typed: typed,
            vague: vague
        )
    }

    /// A language whose gender no article of it can say, so the gender is
    /// shown as the short form its own dictionaries print.
    ///
    /// Two reasons a language lands here. Russian, Polish, Czech, Ukrainian
    /// and Hindi have no article at all. Arabic and Hebrew do have a definite
    /// article — ال and ה — but it is written onto the front of the word and
    /// is the same for every gender, so it marks definiteness and says nothing
    /// about which gender the word is.
    static func labels(_ pairs: KeyValuePairs<Gender, String>) -> GenderRule {
        GenderRule(
            genders: pairs.map(\.key),
            marks: Dictionary(uniqueKeysWithValues: pairs.map { ($0.key, GenderMark.label($0.value)) }),
            typed: [:]
        )
    }
}

/// What each language does with gender.
///
/// Adding a language is adding one row. A language with no row marks no
/// gender, which is the honest answer for the twelve that genuinely do not
/// have it — English, Turkish, Japanese, Georgian and the rest — and for a
/// language the learner invented.
nonisolated enum LanguageGenders {

    /// The rule for a language, or `nil` where it marks no gender.
    ///
    /// A language is in here only if its marks tell its genders *apart*. That
    /// is why Romanian is written with labels although it has free indefinite
    /// articles: *un scaun* and *un pom* are both correct, so "un" cannot say
    /// which of the two genders a word is, and a picker offering "un" twice
    /// would be asking a question with no answer. Its difference shows in the
    /// plural, which a single stored gender cannot carry.
    static func rule(for code: String) -> GenderRule? {
        switch code {

        // MARK: Articles said with the word

        case "de":
            // "ein" is masculine and neuter both — ein Mann, ein Haus — so it
            // proves nothing, and reading it as masculine filed every
            // "ein Haus" wrongly.
            //
            // The accusative "den" and "einen" are deliberately absent: they
            // are not forms a noun is cited in, and "den" is the dative plural
            // as well.
            .articles([.masculine: "der", .feminine: "die", .neuter: "das"],
                      typed: ["der": .masculine, "die": .feminine, "das": .neuter,
                              "eine": .feminine],
                      vague: ["ein"])
        case "el":
            // The nominative forms never change before a vowel, which is why
            // Greek needs no shaping rule. The accusative does — the final-ν
            // rule — but a card cites a noun, it does not decline it.
            .articles([.masculine: "ο", .feminine: "η", .neuter: "το"],
                      typed: ["ο": .masculine, "η": .feminine, "το": .neuter,
                              "τον": .masculine, "την": .feminine, "τη": .feminine,
                              "ένας": .masculine, "ενας": .masculine,
                              "έναν": .masculine, "εναν": .masculine,
                              "μία": .feminine, "μια": .feminine,
                              "ένα": .neuter, "ενα": .neuter])
        case "es":
            // The one language here whose article can lie: a feminine noun
            // whose first syllable is a stressed /a/ takes el and un — el
            // agua, un alma — and stays feminine throughout. Both directions
            // are served by the one list below: "el agua" is read as
            // feminine, and a feminine *agua* is written back as "el agua"
            // rather than the "la agua" nobody says.
            .articles([.masculine: "el", .feminine: "la"],
                      typed: ["el": .masculine, "la": .feminine,
                              "un": .masculine, "una": .feminine])
        case "pt":
            .articles([.masculine: "o", .feminine: "a"],
                      typed: ["o": .masculine, "a": .feminine,
                              "um": .masculine, "uma": .feminine])
        case "fr":
            .articles([.masculine: "le", .feminine: "la"],
                      typed: ["le": .masculine, "la": .feminine,
                              "un": .masculine, "une": .feminine],
                      vague: ["l'", "l’"])
        case "it":
            .articles([.masculine: "il", .feminine: "la"],
                      typed: ["il": .masculine, "lo": .masculine, "la": .feminine,
                              "un": .masculine, "uno": .masculine, "una": .feminine,
                              // un' only ever stands before a feminine: un'amica.
                              "un'": .feminine, "un’": .feminine],
                      vague: ["l'", "l’"])
        case "nl":
            // With exactly two classes "de" is not vague at all: it proves
            // the common one. The old masculine/feminine split inside it
            // survives only in pronoun reference, which a card does not show.
            .articles([.common: "de", .neuter: "het"],
                      typed: ["de": .common, "het": .neuter,
                              "'t": .neuter, "’t": .neuter],
                      vague: ["een", "'n", "’n"])

        // The Scandinavian three put their *definite* article on the end of
        // the word — bil/bilen, hus/huset — so the article in front is the
        // indefinite one, and that is also the form their dictionaries and
        // their learners cite gender with.
        //
        // den/det are read on the way in but never printed: free-standing,
        // they are only grammatical with an adjective after them — den nya
        // flaskan — so a card showing "det hus" would be wrong.
        //
        // The definite suffix is spelled like the indefinite article in all
        // three — dreng/drengen, en dreng — which is safe here only because
        // an article is taken off a word as a separate token, never as a
        // prefix of one.
        case "sv":
            .articles([.common: "en", .neuter: "ett"],
                      typed: ["en": .common, "ett": .neuter,
                              "den": .common, "det": .neuter],
                      vague: ["de"])
        case "da":
            .articles([.common: "en", .neuter: "et"],
                      typed: ["en": .common, "et": .neuter,
                              "den": .common, "det": .neuter],
                      vague: ["de"])
        case "nb":
            // "en" proves nothing in Bokmål: a feminine noun may legally take
            // the masculine forms, so "en bok" and "ei bok" are both right.
            // "ei" and "et" do prove one.
            .articles([.masculine: "en", .feminine: "ei", .neuter: "et"],
                      typed: ["ei": .feminine, "et": .neuter, "det": .neuter],
                      vague: ["en", "den", "de"])

        // MARK: Genders shown, never said

        case "ru":
            // муж./жен./ср. is what the Ожегов–Шведова edition prints. The
            // dominant printed convention across Ожегов, МАС, БТС and Даль is
            // the shorter м./ж./ср.; the longer forms are chosen here because
            // two letters of a word beside a word read as part of it.
            .labels([.masculine: "муж.", .feminine: "жен.", .neuter: "ср."])
        case "uk":
            // ч./ж./с., as the Словник української мови tradition prints it —
            // not the Russian forms with the letters changed. Each of these
            // languages abbreviates the same gender differently, and sharing
            // one table across a family is the surest way to print something
            // no dictionary of that language ever has.
            .labels([.masculine: "ч.", .feminine: "ж.", .neuter: "с."])
        case "pl":
            // No full stop: the Słownik gramatyczny języka polskiego writes
            // m, ż, n bare. Polish also marks animacy inside the masculine
            // (m1 personal, m2 animate, m3 inanimate), which one stored
            // gender per word cannot carry — so "m" here is true but not the
            // whole truth, and the note field is where the rest goes.
            .labels([.masculine: "m", .feminine: "ż", .neuter: "n"])
        case "cs":
            .labels([.masculine: "m.", .feminine: "ž.", .neuter: "s."])
        case "hr":
            // No full stop, and the neuter is two letters: the Hrvatski
            // jezični portal's own list of abbreviations gives m, ž, sr.
            .labels([.masculine: "m", .feminine: "ž", .neuter: "sr"])
        case "ro":
            .labels([.masculine: "s.m.", .feminine: "s.f.", .neuter: "s.n."])
        case "ar":
            // Written out in full because Arabic monolingual lexicography has
            // no settled abbreviation for gender — a shortening here would be
            // one the app invented.
            .labels([.masculine: "مذكر", .feminine: "مؤنث"])
        case "he":
            // The mark after the letter is a geresh (U+05F3), not an
            // apostrophe. This is correctness rather than typography: a
            // geresh is strongly right-to-left, while both apostrophes are
            // bidirectionally neutral and would be reordered to the wrong
            // side of the letter beside a left-to-right word.
            .labels([.masculine: "\u{05D6}\u{05F3}", .feminine: "\u{05E0}\u{05F3}"])
        case "hi":
            // The devanagari abbreviation sign (U+0970), not a full stop,
            // which is what हिंदी शब्दसागर prints.
            .labels([.masculine: "\u{092A}\u{0941}\u{0902}\u{0970}",
                     .feminine: "\u{0938}\u{094D}\u{0924}\u{094D}\u{0930}\u{0940}\u{0970}"])

        default:
            nil
        }
    }

    /// Every language with gender rules written for it.
    ///
    /// Spelled out rather than derived, because a switch cannot be asked what
    /// it has cases for — and because this is the list a test walks to check
    /// that each row is sound.
    static let ruledCodes: [String] = [
        "ar", "cs", "da", "de", "el", "es", "fr", "he", "hi", "hr",
        "it", "nb", "nl", "pl", "pt", "ro", "ru", "sv", "uk"
    ]

    /// Every token one language writes for a gender: the marks it prints and
    /// the articles a learner types.
    static func tokens(for code: String) -> [String: Gender] {
        if let cached = tokenCache.withLock({ $0[code] }) { return cached }

        var tokens: [String: Gender] = [:]
        if let rule = rule(for: code) {
            for (gender, mark) in rule.marks {
                for token in variants(of: mark.text) { tokens[token] = gender }
            }
            for (article, gender) in rule.typed {
                for token in variants(of: article) { tokens[token] = gender }
            }
        }
        tokenCache.withLock { $0[code] = tokens }
        return tokens
    }

    private static let tokenCache = Mutex<[String: [String: Gender]]>([:])

    /// Every mark any language writes, as a token an import can recognise
    /// without being told which language it is reading.
    ///
    /// Built from the table above rather than typed out a second time, so a
    /// language added there is understood on import the same day — the way
    /// "ż" and "ср." and "sr" would otherwise each have had to be remembered
    /// twice, in two files, by somebody who had no reason to look.
    ///
    /// A token two languages disagree about is left out rather than guessed:
    /// "den" is masculine in German and common in Swedish, and a list that did
    /// not say which language it was for has not said which gender it meant.
    static let markTokens: [String: Gender] = {
        var claims: [String: Set<Gender>] = [:]
        for code in ruledCodes {
            for (token, gender) in tokens(for: code) {
                claims[token, default: []].insert(gender)
            }
        }
        return claims.compactMapValues { $0.count == 1 ? $0.first : nil }
    }()

    /// A mark as a list might write it: as printed, and without the full stop
    /// or abbreviation sign it is printed with.
    private static func variants(of text: String) -> [String] {
        let token = text.lowercased()
        let bare = token.trimmingCharacters(in: abbreviationMarks)
        return bare == token || bare.isEmpty ? [token] : [token, bare]
    }

    private static let abbreviationMarks = CharacterSet(charactersIn: ".\u{0970}\u{05F3}'’")

    /// The genders a language marks, in the order a learner meets them.
    ///
    /// The one list every gender control is built from. Empty means the
    /// language does not mark gender, and the control is not there at all.
    static func genders(for code: String) -> [Gender] {
        rule(for: code)?.genders ?? []
    }

    /// Whether a language is worth asking about gender at all.
    ///
    /// Its own fact, not something derived from whether an article exists:
    /// Russian marks three genders and has no articles, and the two questions
    /// were one for as long as this returned "has an article".
    static func marksGender(_ code: String) -> Bool {
        !genders(for: code).isEmpty
    }

    /// What a language shows for a gender, with no particular word in hand.
    ///
    /// For a picker, where the word has not been typed yet, and for the
    /// word-list prompt, which describes the language rather than a noun.
    static func mark(_ gender: Gender, language code: String) -> GenderMark? {
        rule(for: code)?.marks[gender]
    }

    /// What a language shows in front of one particular word.
    ///
    /// The same as above except where the word changes the article: French and
    /// Italian elide it, and *la eau* is not a thing anybody should see on a
    /// card.
    static func mark(_ gender: Gender, before term: String, language code: String) -> GenderMark? {
        guard let mark = mark(gender, language: code) else { return nil }
        guard case .article(let article) = mark else { return mark }
        return .article(fitted(article, before: term, language: code))
    }

    /// The definite article a language puts in front of a noun of this gender,
    /// where it has one that is said aloud.
    ///
    /// `nil` both for a language with no genders and for a language whose
    /// gender is shown rather than spoken, which is exactly the question the
    /// voice needs answered.
    static func article(_ gender: Gender, language code: String) -> String? {
        guard case .article(let text) = mark(gender, language: code) else { return nil }
        return text
    }

    /// The articles a learner might type in front of a word, and the gender
    /// each one means.
    private static func typedArticles(for code: String) -> [String: Gender] {
        rule(for: code)?.typed ?? [:]
    }

    /// Takes an article off the front of a typed word and reports what it said.
    ///
    /// This is the whole of the "choosing a gender" interface for a single
    /// word: a German learner types "die Mutter" without being asked to, and
    /// the app files it as Mutter, feminine.
    static func split(term: String, language code: String) -> (term: String, gender: Gender?) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rule = rule(for: code) else { return (trimmed, nil) }

        // An elided article is joined to the word, so there is no space to
        // split on: "l'eau" and "un'amica" are one token each and still have
        // an article on them. The longest match wins, so the answer does not
        // depend on what order a dictionary happens to be in.
        let elided = rule.typed.map { ($0.key, Optional($0.value)) }
            + rule.vague.map { ($0, Gender?.none) }
        for (article, gender) in elided
            .filter({ $0.0.hasSuffix("'") || $0.0.hasSuffix("’") })
            .sorted(by: { $0.0.count > $1.0.count })
        where trimmed.count > article.count && trimmed.lowercased().hasPrefix(article) {
            return (String(trimmed.dropFirst(article.count)), gender)
        }

        // Exactly two words, or it is a phrase rather than an article and a
        // noun: "das ist gut" is a sentence, and taking "das" off it would
        // leave the learner with a word they never wrote.
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 2 else { return (trimmed, nil) }

        let head = parts[0].lowercased()
        if let gender = rule.typed[head] {
            return (String(parts[1]), gender)
        }
        if rule.vague.contains(head) {
            return (String(parts[1]), nil)
        }
        return (trimmed, nil)
    }

    /// A noun the way a dictionary writes it — "die Ansage, -n", "der Arzt, -ä, e"
    /// — taken apart into the word, its gender and its plural.
    ///
    /// Only when the part before the comma really is an article and a noun;
    /// "gern(e)" and "der/die Bekannte" are left exactly as they were written,
    /// because a wrong guess about a word is worse than no guess.
    static func dictionaryForm(_ text: String, language code: String) -> (term: String, gender: Gender?, plural: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comma = trimmed.firstIndex(of: ",") else {
            let (term, gender) = split(term: trimmed, language: code)
            return (term, gender, nil)
        }

        let head = String(trimmed[..<comma])
        let tail = trimmed[trimmed.index(after: comma)...].trimmingCharacters(in: .whitespaces)
        let (term, gender) = split(term: head, language: code)
        guard gender != nil else { return (trimmed, nil, nil) }
        return (term, gender, tail.isEmpty ? nil : tail)
    }

    // MARK: - The shape of an article

    /// The article as it is written in front of one particular word.
    ///
    /// Three languages change it, for two different reasons. French and
    /// Italian elide before a vowel — *l'eau*, *l'amico* — and Spanish swaps
    /// the feminine article for the masculine one in front of a stressed a-:
    /// *el agua*, which stays a feminine word throughout.
    ///
    /// Spelling is all there is to go on, and twice that is not quite enough:
    /// nothing in the letters of *homme* and *hibou* says that the first
    /// elides and the second does not, and nothing in *agua* says its a is
    /// stressed while the a of *amiga* is not. Both are therefore listed
    /// rather than guessed — the words a learner actually meets — because the
    /// alternative is being wrong about *l'heure* and *el agua*, which are
    /// words they meet on the first day.
    private static func fitted(_ article: String, before term: String, language code: String) -> String {
        let word = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !word.isEmpty else { return article }

        switch code {
        case "fr":
            guard article == "le" || article == "la" else { return article }
            return elidesInFrench(word) ? "l’" : article

        case "it":
            // The semivowel is asked about before the vowel, or "lo iato"
            // would come out as "l'iato" and "la iena" as "l'iena": the letter
            // is a vowel and the sound is not.
            if article == "la" {
                if startsWithSemivowelInItalian(word) { return "la" }
                return startsWithVowelSoundInItalian(word) ? "l’" : "la"
            }
            guard article == "il" else { return article }
            if takesLoInItalian(word) { return "lo" }
            return startsWithVowelSoundInItalian(word) ? "l’" : "il"

        case "es":
            guard article == "la", spanishStressedA.contains(word) else { return article }
            return "el"

        default:
            return article
        }
    }

    private static func startsWithVowel(_ word: String) -> Bool {
        guard let first = word.unicodeScalars.first else { return false }
        return vowels.contains(Character(first))
    }

    private static let vowels: Set<Character> = [
        "a", "e", "i", "o", "u",
        "à", "á", "â", "ä", "è", "é", "ê", "ë", "ì", "í", "î", "ï",
        "ò", "ó", "ô", "ö", "ù", "ú", "û", "ü"
    ]

    // MARK: French

    private static func elidesInFrench(_ word: String) -> Bool {
        if startsWithVowel(word) { return true }
        guard word.hasPrefix("h") else { return false }
        return !frenchAspirates.contains { word == $0 || word.hasPrefix($0) }
    }

    /// French words whose h is aspirate, so the article stays whole.
    ///
    /// Not every one in the language — the long tail is rare enough that a
    /// learner adding it can fix the article by hand — but the ones a beginner
    /// actually meets.
    private static let frenchAspirates: Set<String> = [
        "hache", "haie", "haine", "hall", "halte", "hamac", "hamster", "hanche",
        "handicap", "hangar", "hareng", "haricot", "harpe", "hasard", "hâte",
        "hausse", "haut", "hauteur", "havre", "hennin", "hérisson", "hernie",
        "héros", "hêtre", "heurt", "hibou", "hiérarchie", "hochet", "hockey",
        "hollande", "homard", "hongrois", "honte", "hoquet", "horde", "hors",
        "hotte", "houle", "housse", "hublot", "huche", "huguenot", "huit",
        "hurlement", "hutte"
    ]

    // MARK: Italian

    /// Italian h is always silent, so *hotel* begins with a vowel sound and
    /// takes *l'* — unlike in French, where the h decides.
    private static func startsWithVowelSoundInItalian(_ word: String) -> Bool {
        if word.hasPrefix("h"), word.count > 1 { return true }
        return startsWithVowel(word)
    }

    /// Italian masculines that take *lo* rather than *il*: s + consonant, and
    /// the clusters that behave the same way.
    private static func takesLoInItalian(_ word: String) -> Bool {
        if word.hasPrefix("s"), let second = word.dropFirst().first,
           second.isLetter, !vowels.contains(second) {
            return true
        }
        if italianLoClusters.contains(where: { word.hasPrefix($0) }) { return true }
        return startsWithSemivowelInItalian(word)
    }

    /// An i read as a consonant because another vowel follows it: *lo iato*,
    /// *la iena*.
    private static func startsWithSemivowelInItalian(_ word: String) -> Bool {
        guard word.hasPrefix("i"), let second = word.dropFirst().first else { return false }
        return vowels.contains(second)
    }

    /// Where *lo* is settled. Left out on purpose: j- and w- loanwords, where
    /// usage genuinely has two norms (*il judo*, *il whisky*) and *il* is the
    /// commoner one, so the learner's own typing decides rather than this.
    private static let italianLoClusters: [String] = [
        "z", "gn", "gli", "sci", "ps", "pn", "x", "mn", "y"
    ]

    // MARK: Spanish

    /// Feminine nouns whose first syllable is a stressed /a/, which take *el*
    /// and *un* in the singular and are feminine all the same.
    ///
    /// The list exists so that both directions agree: "el agua" typed in is
    /// read as feminine, and a feminine *agua* is written back out as "el
    /// agua". A feminine noun missing from it is shown as "la", which is the
    /// safe way to be wrong — it is a word, not a crash, and the picker is
    /// right there.
    private static let spanishStressedA: Set<String> = [
        "agua", "águila", "ala", "alba", "alga", "alma", "ama", "ancla",
        "ánfora", "ánima", "ansia", "arca", "área", "arma", "arpa", "asa",
        "ascua", "asma", "asta", "aula", "ave", "aya",
        "haba", "habla", "hacha", "hada", "hambre", "hampa", "haya"
    ]
}
