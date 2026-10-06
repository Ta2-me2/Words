import Foundation

/// The languages a profile can be built from.
///
/// Only the codes are ours; every name comes from the system, so the list is
/// spelled the way the Mac spells it and follows the user's own language.
nonisolated enum LanguageCatalog {

    /// A short list rather than the six hundred codes the system knows: a
    /// picker nobody can scroll is not a picker.
    static let codes: [String] = [
        "ar", "cs", "da", "de", "el", "en", "es", "fa", "fi", "fr", "he", "hi",
        "hu", "id", "it", "ja", "ka", "ko", "nl", "no", "pl", "pt", "ro", "ru",
        "sv", "th", "tr", "uk", "vi", "zh"
    ]

    /// "German", "Русский" — whatever the Mac calls it.
    /// The language's name in English, whatever the Mac is set to: for text
    /// written for a model rather than read by the learner.
    static func englishName(for code: String) -> String {
        guard let name = Locale(identifier: "en").localizedString(forLanguageCode: code) else { return code.uppercased() }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    static func name(for code: String) -> String {
        let locale = Locale.current
        guard let name = locale.localizedString(forLanguageCode: code) else { return code.uppercased() }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Codes in the order they should be offered: alphabetical by the name the
    /// user will actually read, not by the code.
    static var sortedCodes: [String] {
        codes.sorted { name(for: $0).localizedStandardCompare(name(for: $1)) == .orderedAscending }
    }

    /// The flags worth offering for a language, best-known first.
    ///
    /// Several, not one, because a language is not a country: Portuguese is
    /// spoken in two places that would both be surprised to be given the
    /// other's flag.
    static func flags(for code: String) -> [String] {
        switch code {
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
        case "hu": ["🇭🇺"]
        case "id": ["🇮🇩"]
        case "it": ["🇮🇹", "🇨🇭"]
        case "ja": ["🇯🇵"]
        case "ka": ["🇬🇪"]
        case "ko": ["🇰🇷"]
        case "nl": ["🇳🇱", "🇧🇪"]
        case "no": ["🇳🇴"]
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
