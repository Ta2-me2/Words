import Foundation
import Synchronization

/// The languages a profile can be built from.
///
/// Thirty-one of them, chosen by what people actually study rather than by how
/// many speak it — those are different lists, and the second one is the wrong
/// one. Nineteen have gender rules written for them; twelve mark no gender at
/// all, which is the honest answer for Turkish or Japanese rather than a gap.
///
/// Only the codes are ours; every name comes from the system, so the list is
/// spelled the way the Mac spells it and follows the user's own language. The
/// exception is a language the learner added, whose name is theirs.
nonisolated enum LanguageCatalog {

    /// A short list rather than the six hundred codes the system knows: a
    /// picker nobody can scroll is not a picker.
    ///
    /// Norwegian is here as `nb` — Bokmål — and not as `no`. `no` is a
    /// macrolanguage above Bokmål and Nynorsk, and macOS ships its Norwegian
    /// voices under `nb`, so a profile stored as `no` finds no voice and loses
    /// every listen button and the dictation game with them.
    static let codes: [String] = [
        "ar", "cs", "da", "de", "el", "en", "es", "fi", "fr", "he", "hi",
        "hr", "hu", "id", "it", "ja", "ka", "kk", "ko", "nb", "nl", "pl",
        "pt", "ro", "ru", "sv", "th", "tr", "uk", "vi", "zh"
    ]

    // MARK: - Languages the learner added

    /// The custom languages this library holds.
    ///
    /// A mirror of what is in the library document, kept here because a
    /// language's name is asked for from everywhere — a card's header, a
    /// profile's subtitle, the text handed to the model — and threading the
    /// library through all of it would be a worse answer than one registration
    /// at the two points where the library changes.
    private static let added = Mutex<[CustomLanguage]>([])

    /// Called by the store whenever the library is loaded or changed.
    static func register(_ languages: [CustomLanguage]) {
        added.withLock { $0 = languages }
    }

    static var customLanguages: [CustomLanguage] {
        added.withLock { $0 }
    }

    static func custom(_ code: String) -> CustomLanguage? {
        guard CustomLanguage.isCustom(code) else { return nil }
        return added.withLock { list in list.first { $0.id == code } }
    }

    /// Custom languages in the order they should be offered: by name, like the
    /// others.
    static var customCodes: [String] {
        customLanguages
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map(\.id)
    }

    // MARK: - Names and flags

    /// The language's name in English, whatever the Mac is set to: for text
    /// written for a model rather than read by the learner.
    static func englishName(for code: String) -> String {
        if let custom = custom(code) { return custom.name }
        guard let name = Locale(identifier: "en").localizedString(forLanguageCode: code) else { return code.uppercased() }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// "German", "Русский" — whatever the Mac calls it.
    static func name(for code: String) -> String {
        if let custom = custom(code) { return custom.name }
        let locale = Locale.current
        guard let name = locale.localizedString(forLanguageCode: code) else { return code.uppercased() }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Codes in the order they should be offered: alphabetical by the name the
    /// user will actually read, not by the code.
    static var sortedCodes: [String] {
        codes.sorted { name(for: $0).localizedStandardCompare(name(for: $1)) == .orderedAscending }
    }

    /// Every code that can be chosen: the ones the app knows, then the ones
    /// the learner made.
    static var offeredCodes: [String] {
        sortedCodes + customCodes
    }

    /// The flags worth offering for a language, best-known first.
    ///
    /// Several, not one, because a language is not a country: Portuguese is
    /// spoken in two places that would both be surprised to be given the
    /// other's flag.
    static func flags(for code: String) -> [String] {
        if let custom = custom(code) { return [custom.flag] }
        return switch code {
        case "ar": ["🇸🇦", "🇦🇪", "🇪🇬", "🇲🇦"]
        case "cs": ["🇨🇿"]
        case "da": ["🇩🇰"]
        case "de": ["🇩🇪", "🇦🇹", "🇨🇭"]
        case "el": ["🇬🇷", "🇨🇾"]
        case "en": ["🇬🇧", "🇺🇸", "🇦🇺", "🇨🇦", "🇮🇪"]
        case "es": ["🇪🇸", "🇲🇽", "🇦🇷", "🇨🇴"]
        case "fa": ["🇮🇷"]
        case "fi": ["🇫🇮"]
        case "fr": ["🇫🇷", "🇨🇦", "🇧🇪", "🇨🇭"]
        case "he": ["🇮🇱"]
        case "hi": ["🇮🇳"]
        case "hr": ["🇭🇷"]
        case "hu": ["🇭🇺"]
        case "id": ["🇮🇩"]
        case "it": ["🇮🇹", "🇨🇭"]
        case "ja": ["🇯🇵"]
        case "ka": ["🇬🇪"]
        case "kk": ["🇰🇿"]
        case "ko": ["🇰🇷"]
        case "nb", "no": ["🇳🇴"]
        case "nl": ["🇳🇱", "🇧🇪"]
        case "pl": ["🇵🇱"]
        case "pt": ["🇵🇹", "🇧🇷"]
        case "ro": ["🇷🇴", "🇲🇩"]
        case "ru": ["🇷🇺"]
        case "sv": ["🇸🇪"]
        case "th": ["🇹🇭"]
        case "tr": ["🇹🇷"]
        case "uk": ["🇺🇦"]
        case "vi": ["🇻🇳"]
        case "zh": ["🇨🇳", "🇹🇼", "🇭🇰", "🇸🇬"]
        default: ["🏳️"]
        }
    }

    static func defaultFlag(for code: String) -> String {
        flags(for: code).first ?? "🏳️"
    }

    // MARK: - First guesses

    /// The Mac's own language, used as the first guess at what the learner
    /// already speaks.
    static var systemCode: String {
        let preferred = Locale.current.language.languageCode?.identifier ?? "en"
        return codes.contains(preferred) ? preferred : "en"
    }

    /// A sensible language to offer as the one being learned: anything but the
    /// one the Mac is already in.
    static var suggestedLearningCode: String {
        systemCode == "en" ? "de" : "en"
    }
}
