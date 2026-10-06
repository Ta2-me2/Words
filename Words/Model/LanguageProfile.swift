import Foundation

/// One language being learned, and the language it is being learned from.
///
/// Everything else in the library belongs to a profile: words, cards and the
/// review history. Learning two languages is two profiles, never two apps.
nonisolated struct LanguageProfile: Identifiable, Codable, Hashable, Sendable {

    var id: UUID
    var name: String

    /// The language of the words being learned.
    var learningCode: String

    /// The language their meanings are written in.
    var nativeCode: String

    /// The flag shown in the language switcher.
    ///
    /// A language is not a country, which is why this is a choice and not a
    /// lookup: the switcher has to be recognisable in a glance, and the learner
    /// knows better than the app whether their Portuguese is Lisbon or Brazil.
    var flag: String

    /// How many unseen words this profile is willing to start in a day.
    ///
    /// Without it, adding fifty words on a Sunday means fifty reviews every day
    /// for a fortnight, and the learner stops. The cap is per profile because
    /// appetite differs per language.
    var dailyNewLimit: Int

    /// How many words from earlier days this profile will take on in a day, or
    /// `nil` for as many as are due.
    ///
    /// No limit by default, because a limit on reviews does not make the work
    /// go away — it only moves it to tomorrow. It is for the day after a week
    /// away, when two hundred cards are waiting and fifty is what there is time
    /// for.
    var dailyReviewLimit: Int?

    /// How much of this language the learner means to still know when a word
    /// comes round again.
    ///
    /// The one setting that decides how much work a day holds: at nine words in
    /// ten the intervals are generous, and every point above that costs sharply
    /// more reviews for a little more memory. It belongs to the language rather
    /// than to the app because appetite differs — a language being used at work
    /// is not a language being read on holiday.
    var desiredRetention: Double

    /// The system voice that reads this language's words, by identifier.
    ///
    /// Stored by identifier rather than by name: voices come and go with system
    /// updates, and a name would silently point at a different voice.
    var voiceIdentifier: String?

    /// How fast that voice reads, on `AVSpeechUtterance`'s own scale.
    var speechRate: Double

    /// Whether the word is spoken the moment its meaning is shown.
    var speaksOnReveal: Bool

    /// Whether its example sentence is spoken when the meaning is shown. Its own
    /// switch, not an addition to the one above: hearing a word and hearing it
    /// used are two different exercises, and either can be wanted alone.
    var speaksExampleOnReveal: Bool

    /// The learner's own version of the prompt that asks an AI for a word list,
    /// or `nil` for the standard one. Kept per language because the standard
    /// one names the language, and whatever the learner changed in it — a
    /// level, a style of example — is usually about that language too.
    var listPrompt: String?

    /// The order this language's new words are started in.
    var newWordOrder: NewWordOrder

    /// Which way round this language's cards are asked. Chosen beside the
    /// button that starts a sitting and remembered, because it is a way of
    /// studying rather than a setting looked up once.
    var studyDirection: StudyDirection

    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        learningCode: String,
        nativeCode: String,
        flag: String? = nil,
        dailyNewLimit: Int = 20,
        dailyReviewLimit: Int? = nil,
        desiredRetention: Double = Retention.standard,
        voiceIdentifier: String? = nil,
        speechRate: Double = 0.45,
        speaksOnReveal: Bool = false,
        speaksExampleOnReveal: Bool = false,
        listPrompt: String? = nil,
        newWordOrder: NewWordOrder = .added,
        studyDirection: StudyDirection = .wordToMeaning,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.learningCode = learningCode
        self.nativeCode = nativeCode
        self.flag = flag ?? LanguageCatalog.defaultFlag(for: learningCode)
        self.dailyNewLimit = max(0, dailyNewLimit)
        self.dailyReviewLimit = dailyReviewLimit.map { max(0, $0) }
        self.desiredRetention = Retention.clamped(desiredRetention)
        self.voiceIdentifier = voiceIdentifier
        self.speechRate = speechRate
        self.speaksOnReveal = speaksOnReveal
        self.speaksExampleOnReveal = speaksExampleOnReveal
        self.listPrompt = listPrompt
        self.newWordOrder = newWordOrder
        self.studyDirection = studyDirection
        self.createdAt = createdAt
    }

    /// Profiles written before flags existed get the obvious one for their
    /// language rather than a blank space in the switcher.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        learningCode = try container.decode(String.self, forKey: .learningCode)
        nativeCode = try container.decode(String.self, forKey: .nativeCode)
        flag = try container.decodeIfPresent(String.self, forKey: .flag)
            ?? LanguageCatalog.defaultFlag(for: learningCode)
        dailyNewLimit = try container.decodeIfPresent(Int.self, forKey: .dailyNewLimit) ?? 20
        dailyReviewLimit = try container.decodeIfPresent(Int.self, forKey: .dailyReviewLimit).map { max(0, $0) }
        desiredRetention = Retention.clamped(
            try container.decodeIfPresent(Double.self, forKey: .desiredRetention) ?? Retention.standard
        )
        voiceIdentifier = try container.decodeIfPresent(String.self, forKey: .voiceIdentifier)
        speechRate = try container.decodeIfPresent(Double.self, forKey: .speechRate) ?? 0.45
        speaksOnReveal = try container.decodeIfPresent(Bool.self, forKey: .speaksOnReveal) ?? false
        speaksExampleOnReveal = try container.decodeIfPresent(Bool.self, forKey: .speaksExampleOnReveal) ?? false
        listPrompt = try container.decodeIfPresent(String.self, forKey: .listPrompt)
        newWordOrder = try container.decodeIfPresent(NewWordOrder.self, forKey: .newWordOrder) ?? .added
        studyDirection = try container.decodeIfPresent(StudyDirection.self, forKey: .studyDirection) ?? .wordToMeaning
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
    }

    /// "German → English", for the line under the title.
    var languagePair: String {
        "\(LanguageCatalog.name(for: learningCode)) → \(LanguageCatalog.name(for: nativeCode))"
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? LanguageCatalog.name(for: learningCode) : trimmed
    }
}
