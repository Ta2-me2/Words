import Foundation

/// A language the learner added themselves.
///
/// Everything the app does for a language it has never heard of, it already
/// does: the thirty-one it ships with include twelve that mark no gender, and
/// those work by having no rules rather than by being special. A custom
/// language is the same thing with a name and a flag the learner chose, which
/// is why it carries nothing else — no gender rules, because inventing the
/// grammar of a language the app has never seen is the one thing it must not
/// do.
nonisolated struct CustomLanguage: Identifiable, Codable, Hashable, Sendable {

    /// The code this language lives under in a profile, and its identity.
    ///
    /// A private-use BCP-47 tag, so it can never collide with a real language
    /// code — including one a later version of the app starts supporting. If
    /// Serbian arrives next year, a learner's hand-made "Serbian" keeps its
    /// own words and its own history, and the two sit side by side.
    var id: String

    /// What the learner calls it. Shown everywhere a language name is shown.
    var name: String

    var flag: String

    var createdAt: Date

    init(id: String = Self.newCode(), name: String, flag: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.flag = flag
        self.createdAt = createdAt
    }

    static func newCode() -> String {
        "x-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
    }

    /// Whether a code belongs to a language somebody added rather than one the
    /// app ships with.
    static func isCustom(_ code: String) -> Bool {
        code.hasPrefix("x-")
    }

    /// A name worth saving: a language with no name could not be told from
    /// another one in the switcher.
    var isUsable: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
