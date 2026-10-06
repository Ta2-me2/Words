import XCTest
@testable import WortfallCore

final class IntegrationTests: XCTestCase {
    private let cards = [
        VocabularyCard(id: "a", word: "cat", translation: "кошка", categoryIDs: ["animals"]),
        VocabularyCard(id: "b", word: "dog", translation: "собака", categoryIDs: ["animals"]),
        VocabularyCard(id: "c", word: "bird", translation: "птица", categoryIDs: ["animals"])
    ]
    private func answer(mode: StudyMode = .wordToTranslation, correct: Bool = false, attempt: Int = 1) -> AnswerRecord {
        AnswerRecord(id: UUID(), runID: UUID(), challengeID: UUID(), timestamp: Date(), scopeID: "animals", mode: mode, cardID: "a", categoryIDs: ["animals"], word: "cat", translation: "кошка", prompt: mode == .wordToTranslation ? "cat" : "кошка", correctAnswer: mode == .wordToTranslation ? "кошка" : "cat", selectedAnswer: correct ? (mode == .wordToTranslation ? "кошка" : "cat") : "wrong", isCorrect: correct, attempt: attempt, responseTime: 2, level: 1, points: correct ? 100 : 0)
    }
    func testBothModesKeepHostIDsAndEmitModeAwareAnswers() throws {
        for mode in StudyMode.directions {
            var engine = GameEngine(deck: try VocabularyDeck(cards: cards, mode: mode), seed: 1, scopeID: "animals")
            XCTAssertEqual(engine.challenge.prompt, mode.prompt(for: engine.challenge.card))
            XCTAssertEqual(engine.challenge.options[engine.challenge.correctLane], mode.answer(for: engine.challenge.card))
            engine.start()
            for _ in 0..<4000 {
                engine.selectLane(engine.challenge.correctLane); engine.advance(1.0 / 60)
                if engine.phase == .won { break }
            }
            XCTAssertEqual(engine.phase, .won)
            XCTAssertEqual(engine.result.score, engine.records.reduce(0) { $0 + $1.points })
            XCTAssertTrue(engine.records.allSatisfy { $0.mode == mode && $0.scopeID == "animals" && $0.categoryIDs == ["animals"] && $0.selectedAnswer == $0.correctAnswer })
            XCTAssertTrue(engine.records.allSatisfy { ["a", "b", "c"].contains($0.cardID) })
        }
    }
    func testMixedQuestionsPreserveDirectionOnRetryAndValidateBothSides() throws {
        var engine = GameEngine(deck: try VocabularyDeck(cards: cards, mode: .mixed), seed: 19)
        engine.start()
        for _ in 0..<5000 {
            let lane = engine.records.isEmpty ? (engine.challenge.correctLane + 1) % 3 : engine.challenge.correctLane
            engine.selectLane(lane); engine.advance(1.0 / 60)
            if engine.phase == .won { break }
        }
        XCTAssertEqual(engine.phase, .won)
        XCTAssertEqual(engine.result.mode, .mixed)
        XCTAssertEqual(Set(engine.records.map(\.mode)), Set(StudyMode.directions))
        XCTAssertTrue(engine.records.allSatisfy { $0.studyMode == .mixed })
        XCTAssertEqual(engine.records[0].challengeID, engine.records[1].challengeID)
        XCTAssertEqual(engine.records[0].mode, engine.records[1].mode)
        XCTAssertFalse(engine.records[0].isCorrect)
        var stats = ProgressSnapshot(); stats.record(engine.result)
        XCTAssertEqual(stats.totalAttempts, 4)
        XCTAssertEqual(stats.totalCorrectAnswers, 3)
        XCTAssertEqual(stats.correctAnswerRate, 0.75)
        XCTAssertEqual(stats.totalCompletedLevels, 1)
        XCTAssertEqual(stats.unlockedLevel(scopeID: "default", mode: .mixed), 2)
        XCTAssertEqual(stats.unlockedLevel(scopeID: "default", mode: .wordToTranslation), 1)
        let ambiguous = (0..<4).map { VocabularyCard(id: "\($0)", word: $0 < 2 ? "a" : "b", translation: "answer \($0)") }
        XCTAssertNoThrow(try VocabularyDeck(cards: ambiguous))
        XCTAssertThrowsError(try VocabularyDeck(cards: ambiguous, mode: .mixed))
    }
    func testReverseModeRejectsAmbiguousDistractors() throws {
        let words = [VocabularyCard(id: "a", word: "fast", translation: "быстрый"), VocabularyCard(id: "b", word: "quick", translation: "быстрый"), VocabularyCard(id: "c", word: "slow", translation: "медленный"), VocabularyCard(id: "d", word: "bright", translation: "яркий")]
        let deck = try VocabularyDeck(cards: words, mode: .translationToWord)
        for seed in 1...30 {
            let engine = GameEngine(deck: deck, seed: UInt64(seed))
            if engine.challenge.prompt == "быстрый" {
                XCTAssertEqual(engine.challenge.options.filter { ["fast", "quick"].contains($0) }.count, 1)
            }
        }
        XCTAssertThrowsError(try VocabularyDeck(cards: Array(words.prefix(3)), mode: .translationToWord))
        XCTAssertThrowsError(try VocabularyDeck(cards: Array(cards.prefix(2))))
    }
    func testStatisticsDistinguishRetriesDirectionsAndDeduplicate() throws {
        var snapshot = ProgressSnapshot()
        let wrong = answer(), retry = answer(correct: true, attempt: 2), reverse = answer(mode: .translationToWord, correct: true)
        snapshot.record(wrong); snapshot.record(wrong); snapshot.record(retry); snapshot.record(reverse)
        let stats = try XCTUnwrap(snapshot.words["a"])
        XCTAssertEqual(stats.attempts, 3); XCTAssertEqual(stats.mistakes, 1)
        XCTAssertEqual(stats.firstTryCorrect, 1); XCTAssertEqual(stats.firstAttempts, 2)
        XCTAssertEqual(stats.firstTryAccuracy, 0.5)
        XCTAssertEqual(stats.directions[StudyMode.wordToTranslation.rawValue]?.confusedAnswers["wrong"], 1)
        XCTAssertEqual(snapshot.earnedPoints, 200)
        let result = LevelResult(runID: UUID(), scopeID: "animals", mode: .wordToTranslation, timestamp: Date(), level: 1, completed: true, score: 100, answers: [wrong, retry])
        snapshot.record(result); snapshot.record(result)
        XCTAssertEqual(snapshot.levels.values.first?.runs, 1)
        XCTAssertEqual(snapshot.unlockedLevel(scopeID: "animals", mode: .wordToTranslation), 2)
        XCTAssertEqual(snapshot.unlockedLevel(scopeID: "animals", mode: .translationToWord), 1)
        XCTAssertEqual(snapshot.unlockedLevel(scopeID: "other", mode: .wordToTranslation), 1)
        XCTAssertEqual(snapshot.earnedPoints, 200)
        let decoded = try JSONDecoder().decode(ProgressSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded.words["a"]?.attempts, 3)
        XCTAssertFalse(snapshot.record(result))
    }
    func testLegacyCardsWithoutCategoryDecode() throws {
        let data = Data(#"{"id":"host-id","word":"cat","translation":"кошка"}"#.utf8)
        let card = try JSONDecoder().decode(VocabularyCard.self, from: data)
        XCTAssertEqual(card.categoryIDs, []); XCTAssertEqual(card.id, "host-id")
    }
    func testPersistenceRoundTripStaleWritesAndCorruption() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("progress.json")
        let store = JSONProgressStorage(url: url)
        let empty = try await store.load()
        var snapshot = empty; snapshot.record(answer())
        try await store.save(snapshot); try await store.save(empty)
        let reopened = try await JSONProgressStorage(url: url).load()
        XCTAssertEqual(reopened.words["a"]?.mistakes, 1)
        try Data("corrupt".utf8).write(to: url)
        do { _ = try await store.load(); XCTFail("Corrupt files must not silently reset progress") } catch {}
        var future = ProgressSnapshot(); future.schemaVersion = 99
        try JSONEncoder().encode(future).write(to: url)
        do { _ = try await store.load(); XCTFail("Future schema must be rejected") } catch {}
    }
}
