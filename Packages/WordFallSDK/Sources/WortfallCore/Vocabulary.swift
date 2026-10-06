import Foundation

public struct VocabularyCard: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let word: String
    public let translation: String
    public let categoryIDs: [String]
    private enum CodingKeys: String, CodingKey { case id, word, translation, categoryIDs }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        word = try c.decode(String.self, forKey: .word)
        translation = try c.decode(String.self, forKey: .translation)
        categoryIDs = try c.decodeIfPresent([String].self, forKey: .categoryIDs) ?? []
    }
    public init(id: String = UUID().uuidString, word: String, translation: String, categoryIDs: [String] = []) {
        self.id = id; self.word = word; self.translation = translation; self.categoryIDs = categoryIDs
    }
}

public enum VocabularyError: LocalizedError {
    case insufficientDistinctTranslations, emptyText, duplicateID, ambiguousDeck
    public var errorDescription: String? {
        switch self {
        case .insufficientDistinctTranslations: return "At least three distinct answers are required for this mode."
        case .emptyText: return "Words and translations must not be empty."
        case .duplicateID: return "Card identifiers must be unique."
        case .ambiguousDeck: return "Each prompt needs two unambiguous distractors in the selected mode."
        }
    }
}

public struct VocabularyDeck: Sendable {
    public let cards: [VocabularyCard]
    public let mode: StudyMode
    private let acceptedByMode: [StudyMode: [String: Set<String>]]
    func acceptedAnswers(for mode: StudyMode, prompt: String) -> Set<String> { acceptedByMode[mode]?[Self.key(prompt)] ?? [] }
    public init(cards: [VocabularyCard], mode: StudyMode = .wordToTranslation) throws {
        self.mode = mode
        guard cards.allSatisfy({ !$0.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw VocabularyError.emptyText }
        guard Set(cards.map(\.id)).count == cards.count else { throw VocabularyError.duplicateID }
        var maps: [StudyMode: [String: Set<String>]] = [:]
        for direction in mode == .mixed ? StudyMode.directions : [mode] {
            let count = Set(cards.map { Self.key(direction.answer(for: $0)) }).count
            guard count >= 3 else { throw VocabularyError.insufficientDistinctTranslations }
            var accepted: [String: Set<String>] = [:]
            for card in cards { accepted[Self.key(direction.prompt(for: card)), default: []].insert(Self.key(direction.answer(for: card))) }
            guard accepted.values.allSatisfy({ count - $0.count >= 2 }) else { throw VocabularyError.ambiguousDeck }
            maps[direction] = accepted
        }
        acceptedByMode = maps
        self.cards = cards
    }
    static func key(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU")) }
    public static let demo: VocabularyDeck = try! VocabularyDeck(cards: [
        ("der Himmel", "небо"), ("die Wolke", "облако"), ("die Sonne", "солнце"),
        ("der Regen", "дождь"), ("der Schnee", "снег"), ("der Wind", "ветер"),
        ("das Meer", "море"), ("der Berg", "гора"), ("der Wald", "лес"),
        ("der Fluss", "река"), ("die Blume", "цветок"), ("der Baum", "дерево"),
        ("das Haus", "дом"), ("die Tür", "дверь"), ("das Fenster", "окно"),
        ("das Wasser", "вода"), ("das Brot", "хлеб"), ("der Apfel", "яблоко"),
        ("die Katze", "кошка"), ("der Hund", "собака"), ("der Vogel", "птица"),
        ("das Buch", "книга"), ("die Zeit", "время"), ("der Weg", "путь"),
        ("die Freude", "радость"), ("der Traum", "мечта"), ("die Reise", "путешествие"),
        ("die Freundschaft", "дружба"), ("lernen", "учиться"), ("vergessen", "забывать"),
        ("erinnern", "напоминать"), ("fliegen", "летать"), ("schnell", "быстрый"),
        ("langsam", "медленный"), ("mutig", "смелый"), ("glücklich", "счастливый")
    ].enumerated().map { VocabularyCard(id: "demo-\($0.offset)", word: $0.element.0, translation: $0.element.1) })
}

public enum StudyMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case wordToTranslation, translationToWord, mixed
    public static let directions: [StudyMode] = [.wordToTranslation, .translationToWord]
    public var id: String { rawValue }
    public var title: String { switch self { case .wordToTranslation: return "Word → translation"; case .translationToWord: return "Translation → word"; case .mixed: return "Mixed directions" } }
    public func prompt(for card: VocabularyCard) -> String { self == .wordToTranslation ? card.word : card.translation }
    public func answer(for card: VocabularyCard) -> String { self == .wordToTranslation ? card.translation : card.word }
}

public struct AnswerRecord: Identifiable, Codable, Sendable {
    public let id: UUID
    public let runID: UUID
    public let challengeID: UUID
    public let timestamp: Date
    public let scopeID: String
    public let mode: StudyMode
    public var studyMode: StudyMode? = nil
    public let cardID: String
    public let categoryIDs: [String]
    public let word: String
    public let translation: String
    public let prompt: String
    public let correctAnswer: String
    public let selectedAnswer: String
    /// Compatibility alias; use selectedAnswer for either study direction.
    public var selectedTranslation: String { selectedAnswer }
    public let isCorrect: Bool
    public let attempt: Int
    public let responseTime: Double
    public let level: Int
    public let points: Int
}

public struct LevelResult: Identifiable, Codable, Sendable {
    public var id: UUID { runID }
    public let runID: UUID
    public let scopeID: String
    public let mode: StudyMode
    public let timestamp: Date
    public let level: Int
    public let completed: Bool
    public let score: Int
    public let answers: [AnswerRecord]
}

struct SeededRandom: RandomNumberGenerator, Sendable {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}
