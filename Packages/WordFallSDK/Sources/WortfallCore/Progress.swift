import Foundation

public struct WordStatistics: Codable, Sendable, Identifiable {
    public var id: String { cardID }
    public let cardID: String
    public var word: String
    public var translation: String
    public var categoryIDs: [String]
    public var directions: [String: DirectionStatistics] = [:]
    public var attempts: Int { directions.values.reduce(0) { $0 + $1.attempts } }
    public var mistakes: Int { directions.values.reduce(0) { $0 + $1.mistakes } }
    public var firstAttempts: Int { directions.values.reduce(0) { $0 + $1.firstAttempts } }
    public var firstTryCorrect: Int { directions.values.reduce(0) { $0 + $1.firstTryCorrect } }
    public var firstTryAccuracy: Double { firstAttempts == 0 ? 0 : Double(firstTryCorrect) / Double(firstAttempts) }
}
public struct DirectionStatistics: Codable, Sendable {
    public var attempts = 0
    public var mistakes = 0
    public var firstAttempts = 0
    public var firstTryCorrect = 0
    public var responseSeconds: Double = 0
    public var lastPracticed: Date?
    public var confusedAnswers: [String: Int] = [:]
    public var meanResponseSeconds: Double { attempts == 0 ? 0 : responseSeconds / Double(attempts) }
    public init() {}
}
public struct LevelStatistics: Codable, Sendable, Identifiable {
    public var id: String { Self.key(scopeID: scopeID, mode: mode, level: level) }
    public let scopeID: String
    public let mode: StudyMode
    public let level: Int
    public var runs = 0
    public var completions = 0
    public var bestScore = 0
    public var lastPlayed: Date?
    static func key(scopeID: String, mode: StudyMode, level: Int) -> String {
        "\(Data(scopeID.utf8).base64EncodedString())/\(mode.rawValue)/\(level)"
    }
}

/// Versioned portable data. Stable card IDs should be unique within a learner's library.
/// Records can be delivered more than once; UUIDs prevent double counting.
public struct ProgressSnapshot: Codable, Sendable {
    public var schemaVersion = 1
    public private(set) var revision: UInt64 = 0
    public private(set) var words: [String: WordStatistics] = [:]
    public private(set) var levels: [String: LevelStatistics] = [:]
    public private(set) var earnedPoints = 0
    public private(set) var answerIDs: Set<UUID> = []
    public private(set) var completedRunIDs: Set<UUID> = []
    public var totalCompletedLevels: Int { levels.values.reduce(0) { $0 + $1.completions } }
    public var totalAttempts: Int { words.values.reduce(0) { $0 + $1.attempts } }
    public var totalCorrectAnswers: Int { words.values.reduce(0) { $0 + $1.attempts - $1.mistakes } }
    public var correctAnswerRate: Double { totalAttempts == 0 ? 0 : Double(totalCorrectAnswers) / Double(totalAttempts) }
    public init() {}
    public func unlockedLevel(scopeID: String, mode: StudyMode) -> Int {
        max(1, (levels.values.filter { $0.scopeID == scopeID && $0.mode == mode && $0.completions > 0 }.map(\.level).max() ?? 0) + 1)
    }
    @discardableResult public mutating func record(_ answer: AnswerRecord) -> Bool {
        guard answerIDs.insert(answer.id).inserted else { return false }
        var word = words[answer.cardID] ?? WordStatistics(cardID: answer.cardID, word: answer.word, translation: answer.translation, categoryIDs: answer.categoryIDs)
        word.word = answer.word; word.translation = answer.translation; word.categoryIDs = answer.categoryIDs
        var stats = word.directions[answer.mode.rawValue] ?? DirectionStatistics()
        stats.attempts += 1; stats.responseSeconds += answer.responseTime
        stats.lastPracticed = max(stats.lastPracticed ?? .distantPast, answer.timestamp)
        if !answer.isCorrect { stats.mistakes += 1; stats.confusedAnswers[answer.selectedAnswer, default: 0] += 1 }
        if answer.attempt == 1 { stats.firstAttempts += 1; if answer.isCorrect { stats.firstTryCorrect += 1 } }
        word.directions[answer.mode.rawValue] = stats; words[answer.cardID] = word
        earnedPoints += answer.points; revision += 1
        return true
    }
    @discardableResult public mutating func record(_ result: LevelResult) -> Bool {
        guard !completedRunIDs.contains(result.runID) else { return false }
        for answer in result.answers { record(answer) }
        completedRunIDs.insert(result.runID)
        let key = LevelStatistics.key(scopeID: result.scopeID, mode: result.mode, level: result.level)
        var stats = levels[key] ?? LevelStatistics(scopeID: result.scopeID, mode: result.mode, level: result.level)
        stats.runs += 1; stats.completions += result.completed ? 1 : 0
        stats.bestScore = max(stats.bestScore, result.score); stats.lastPlayed = result.timestamp
        levels[key] = stats; revision += 1
        return true
    }
}

/// Implement this protocol in the host to use SwiftData, SQLite or a cloud-backed repository.
/// A store must serialize writes and reject snapshots older than its latest saved revision.
public protocol ProgressStorage: Sendable {
    func load() async throws -> ProgressSnapshot
    func save(_ snapshot: ProgressSnapshot) async throws
}
public enum ProgressStorageError: LocalizedError {
    case unsupportedVersion(Int)
    public var errorDescription: String? {
        switch self { case .unsupportedVersion(let version): return "Unsupported progress format (version \(version))." }
    }
}
/// Atomic local JSON persistence. Use one actor per file and one progress model per learner.
public actor JSONProgressStorage: ProgressStorage {
    public let url: URL
    private var savedRevision: UInt64 = 0
    public init(url: URL) { self.url = url }
    public func load() throws -> ProgressSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else { return ProgressSnapshot() }
        let snapshot = try JSONDecoder().decode(ProgressSnapshot.self, from: Data(contentsOf: url))
        guard snapshot.schemaVersion == 1 else { throw ProgressStorageError.unsupportedVersion(snapshot.schemaVersion) }
        savedRevision = snapshot.revision
        return snapshot
    }
    public func save(_ snapshot: ProgressSnapshot) throws {
        guard snapshot.schemaVersion == 1 else { throw ProgressStorageError.unsupportedVersion(snapshot.schemaVersion) }
        guard snapshot.revision >= savedRevision else { return }
        let data = try JSONEncoder().encode(snapshot)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        savedRevision = snapshot.revision
    }
}
