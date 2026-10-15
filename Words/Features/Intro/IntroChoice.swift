import Foundation

/// The language the introduction settled on.
///
/// Two kinds, and they travel the same road: one the app already knows, and
/// one somebody made up on the spot because theirs was not in the list. The
/// second is not a lesser case to be handled at the end — it is the reason
/// somebody with an unusual language does not have to lie about which one they
/// are learning in order to get past the first screen.
nonisolated enum IntroChoice: Equatable, Sendable {

    case known(String)
    case invented(name: String, flag: String)

    var displayName: String {
        switch self {
        case .known(let code): LanguageCatalog.name(for: code)
        case .invented(let name, _): name
        }
    }

    var flag: String {
        switch self {
        case .known(let code): LanguageCatalog.defaultFlag(for: code)
        case .invented(_, let flag): flag
        }
    }

    /// How the companion says hello back, where it knows how.
    ///
    /// Nothing for a language it has never heard of, and nothing is the right
    /// answer there: a made-up greeting in somebody's own language would be
    /// the one wrong note in the whole introduction.
    var reply: String? {
        switch self {
        case .known(let code): Greetings.reply(for: code)
        case .invented: nil
        }
    }

    /// The code to lay the greeting out in, so an Arabic hello reads the way
    /// Arabic reads.
    var code: String? {
        switch self {
        case .known(let code): code
        case .invented: nil
        }
    }
}
