import Foundation

/// A word and what it means: the thing the learner actually adds.
///
/// The fields that will arrive later — examples, audio, an image, a gender —
/// hang off this type. The cards hang off it too, so deleting a word takes its
/// schedule with it and nothing is left behind pointing at nothing.
nonisolated struct Entry: Identifiable, Codable, Hashable, Sendable {

    var id: UUID
    var profileID: UUID

    /// The deck this word is filed under, or `nil` for the words that have not
    /// been filed anywhere. A deck is a shelf, not a container: a word with no
    /// deck is still a word in the language.
    var deckID: UUID?

    /// The word in the language being learned.
    var term: String

    /// What it means, in the language the learner already speaks.
    var meaning: String

    /// The word's grammatical gender, where its language has one. Stored as a
    /// gender rather than as an article: the article is the language's business.
    var gender: Gender?

    /// How the word is said, written however the learner likes: IPA, the sounds
    /// spelled out in an alphabet they read, a rhyme. Free text on purpose —
    /// the languages that need this most are the ones no voice will ever read
    /// aloud, and their learners each have their own way of writing sounds down.
    var transcription: String

    /// A sentence the word is used in, and what that sentence means.
    var example: String
    var exampleTranslation: String

    /// Anything worth remembering with it: a gender, a plural, a sentence.
    var note: String

    /// A recording of the word, if it has one. Absent means the system voice
    /// reads it instead.
    var audio: AudioClip?

    /// A recording of the example sentence, if it has one. Absent means the
    /// system voice reads the example.
    var exampleAudio: AudioClip?

    /// A photograph kept with the word and shown with it. Never at the same
    /// time as an association: see `Picture`.
    var picture: Picture?

    /// A picture the learner drew for it, if they drew one.
    var association: Association?

    var createdAt: Date
    var updatedAt: Date

    /// The questions asked about this word. One for now.
    var cards: [Card]

    init(
        id: UUID = UUID(),
        profileID: UUID,
        deckID: UUID? = nil,
        term: String,
        meaning: String,
        gender: Gender? = nil,
        transcription: String = "",
        example: String = "",
        exampleTranslation: String = "",
        note: String = "",
        audio: AudioClip? = nil,
        exampleAudio: AudioClip? = nil,
        picture: Picture? = nil,
        association: Association? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        cards: [Card] = [Card()]
    ) {
        self.id = id
        self.profileID = profileID
        self.deckID = deckID
        self.term = term
        self.meaning = meaning
        self.gender = gender
        self.transcription = transcription
        self.example = example
        self.exampleTranslation = exampleTranslation
        self.note = note
        self.audio = audio
        self.exampleAudio = exampleAudio
        self.picture = picture
        self.association = association
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.cards = cards
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        profileID = try container.decode(UUID.self, forKey: .profileID)
        deckID = try container.decodeIfPresent(UUID.self, forKey: .deckID)
        term = try container.decode(String.self, forKey: .term)
        meaning = try container.decode(String.self, forKey: .meaning)
        gender = try container.decodeIfPresent(Gender.self, forKey: .gender)
        transcription = try container.decodeIfPresent(String.self, forKey: .transcription) ?? ""
        example = try container.decodeIfPresent(String.self, forKey: .example) ?? ""
        exampleTranslation = try container.decodeIfPresent(String.self, forKey: .exampleTranslation) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        audio = try container.decodeIfPresent(AudioClip.self, forKey: .audio)
        exampleAudio = try container.decodeIfPresent(AudioClip.self, forKey: .exampleAudio)
        picture = try container.decodeIfPresent(Picture.self, forKey: .picture)
        association = try container.decodeIfPresent(Association.self, forKey: .association)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        let stored = try container.decodeIfPresent([Card].self, forKey: .cards) ?? []
        // A word with no card could never be studied, and would sit in the list
        // as something the app quietly refuses to teach.
        cards = stored.isEmpty ? [Card()] : stored
    }

    /// How this word can be heard, given what the language has to read it with.
    func audioAvailability(hasVoice: Bool) -> AudioAvailability {
        if let audio { return .clip(audio.source) }
        return hasVoice ? .voice : .none
    }

    /// Every file this word owns, for taking with it when it goes.
    var mediaFiles: [String] {
        [audio?.file, exampleAudio?.file, picture?.file, association?.file].compactMap { $0 }
    }

    /// Whether there is a drawing worth showing.
    var hasAssociation: Bool {
        guard let association else { return false }
        return !association.isEmpty
    }

    /// The card the first version studies.
    var recognitionCard: Card? {
        cards.first { $0.direction == .recognition } ?? cards.first
    }

    func card(id: UUID) -> Card? {
        cards.first { $0.id == id }
    }

    /// The word as it should be read: with its article, where the language has
    /// one. What is stored stays the bare word, so sorting and searching are
    /// not thrown by a hundred entries beginning with "die".
    func displayTerm(in profile: LanguageProfile) -> String {
        guard let article = articlePrefix(in: profile) else { return term }
        return "\(article) \(term)"
    }

    func articlePrefix(in profile: LanguageProfile) -> String? {
        guard let gender else { return nil }
        return LanguageGenders.article(gender, language: profile.learningCode)
    }

    /// Everything a search should look through.
    var searchableText: String {
        [term, meaning, transcription, example, exampleTranslation, note].joined(separator: " ")
    }

    func matches(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return searchableText.localizedCaseInsensitiveContains(trimmed)
    }
}
