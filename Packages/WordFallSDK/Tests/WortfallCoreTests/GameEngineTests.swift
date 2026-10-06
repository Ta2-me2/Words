import XCTest
@testable import WortfallCore

final class GameEngineTests: XCTestCase {
    func passGate(_ game: inout GameEngine, lane: Int? = nil) {
        let serial = game.eventSerial
        game.selectLane(lane ?? game.challenge.correctLane)
        for _ in 0..<3000 {
            game.advance(1.0 / 60)
            if game.eventSerial != serial { return }
        }
        XCTFail("Gate was not reached")
    }
    func testLengthMilestonesAndReadingBudget() {
        let lengths: [Double] = [100, 200, 500, 1000, 2000, 5000, 8000, 10000, 15000]
        var previousWords = 0
        for (index, length) in lengths.enumerated() {
            let profile = LevelProfile(number: index + 1)
            XCTAssertEqual(profile.length, length)
            XCTAssertGreaterThan(profile.words, previousWords)
            XCTAssertEqual(profile.spacing / profile.maximumSpeed, 2.5, accuracy: 0.001)
            XCTAssertLessThan(profile.length / profile.baseSpeed, 170)
            XCTAssertLessThanOrEqual(profile.maximumSpeed * profile.visualScale, 20)
            previousWords = profile.words
        }
        XCTAssertEqual(LevelProfile(number: 10).length, 20000)
        XCTAssertGreaterThan(LevelProfile(number: 1000).length, LevelProfile(number: 999).length)
    }
    func testFirstAnswerMakesAccelerationNoticeable() {
        var game = GameEngine(seed: 42); game.start()
        let initial = game.speed
        passGate(&game)
        for _ in 0..<60 { game.advance(1.0 / 60) }
        XCTAssertGreaterThan(game.speed, initial * 1.15)
        XCTAssertLessThanOrEqual(game.speed, game.maximumSpeed)
    }
    func testCorrectScoringAndMultiplier() {
        var game = GameEngine(seed: 42); game.start()
        passGate(&game); XCTAssertEqual(game.score, 100)
        passGate(&game); passGate(&game)
        XCTAssertEqual(game.multiplier, 2); XCTAssertEqual(game.score, 400)
        XCTAssertEqual(game.records.count, 3)
    }
    func testWrongReboundsAndPreservesQuestion() {
        var game = GameEngine(seed: 123); game.start()
        let id = game.challenge.card.id
        let wrong = (game.challenge.correctLane + 1) % 3
        passGate(&game, lane: wrong)
        XCTAssertEqual(game.lives, 2); XCTAssertEqual(game.phase, .rebound)
        XCTAssertEqual(game.challenge.card.id, id)
        let distance = game.distance
        for _ in 0..<39 { game.advance(1.0 / 60) }
        XCTAssertLessThan(game.distance, distance - game.profile.baseSpeed * 1.4)
        XCTAssertEqual(game.lives, 2)
        passGate(&game)
        XCTAssertEqual(game.records.last?.attempt, 2)
        XCTAssertEqual(game.answered, 1)
    }
    func testHealOnlyAfterFourConsecutiveCorrectAnswers() {
        var game = GameEngine(seed: 8, startingLevel: 2); game.start()
        passGate(&game, lane: (game.challenge.correctLane + 1) % 3)
        for _ in 0..<3 { passGate(&game) }
        XCTAssertEqual(game.lives, 2); XCTAssertEqual(game.healedProgress, 3)
        passGate(&game)
        XCTAssertEqual(game.lives, 3); XCTAssertEqual(game.healedProgress, 0)
    }
    func testErrorResetsHealingAndMultiplier() {
        var game = GameEngine(seed: 8, startingLevel: 2); game.start()
        for _ in 0..<3 { passGate(&game) }
        passGate(&game, lane: (game.challenge.correctLane + 1) % 3)
        XCTAssertEqual(game.multiplier, 1); XCTAssertEqual(game.streak, 0)
        XCTAssertEqual(game.healedProgress, 0)
    }
    func testThreeErrorsLoseAndRetryRollsBackScore() {
        var game = GameEngine(seed: 6); game.start(); passGate(&game)
        for _ in 0..<3 { passGate(&game, lane: (game.challenge.correctLane + 1) % 3) }
        XCTAssertEqual(game.phase, .lost); XCTAssertEqual(game.lives, 0)
        let records = game.records.count
        game.advance(0.1); XCTAssertEqual(game.records.count, records)
        XCTAssertFalse(game.result.completed)
        game.retry(); XCTAssertEqual(game.score, 0); XCTAssertEqual(game.lives, 3)
        XCTAssertEqual(game.phase, .ready)
    }
    func testFinishAndIncreasingLevelsPreserveHealth() {
        var game = GameEngine(seed: 5)
        var previousLength = 0.0
        for level in 1...12 {
            XCTAssertEqual(game.level, level)
            XCTAssertGreaterThan(game.finishDistance, previousLength)
            previousLength = game.finishDistance
            game.start()
            while game.answered < game.gateCount { passGate(&game) }
            XCTAssertEqual(game.phase, .finishing)
            for _ in 0..<300 { game.advance(1.0 / 60) }
            XCTAssertEqual(game.phase, .won)
            XCTAssertTrue(game.result.completed)
            XCTAssertLessThanOrEqual(game.speed, game.maximumSpeed)
            XCTAssertGreaterThanOrEqual(game.gateSpacing / game.speed, 2.5)
            game.nextLevel()
        }
    }
    func testNextLevelDoesNotRestoreLives() {
        var game = GameEngine(seed: 8, startingLevel: 2); game.start()
        for _ in 0..<4 { passGate(&game) }
        passGate(&game, lane: (game.challenge.correctLane + 1) % 3)
        passGate(&game)
        for _ in 0..<300 { game.advance(1.0 / 60) }
        XCTAssertEqual(game.phase, .won); XCTAssertEqual(game.lives, 2)
        game.nextLevel()
        XCTAssertEqual(game.lives, 2); XCTAssertEqual(game.level, 3)
    }
    func testPauseAndSuspensionDoNotSkipQuestions() {
        var game = GameEngine(seed: 2); game.start()
        game.isPaused = true; game.advance(10); XCTAssertEqual(game.distance, 0)
        game.isPaused = false; game.advance(100)
        XCTAssertLessThan(game.distance, 1)
        game.advance(.nan); XCTAssertTrue(game.distance.isFinite)
    }
    func testSeededQuestionsHaveExactlyThreeDistinctOptions() {
        var a = GameEngine(seed: 99, startingLevel: 2), b = GameEngine(seed: 99, startingLevel: 2)
        a.start(); b.start()
        for _ in 0..<5 {
            XCTAssertEqual(a.challenge.card, b.challenge.card)
            XCTAssertEqual(a.challenge.options, b.challenge.options)
            XCTAssertEqual(Set(a.challenge.options).count, 3)
            XCTAssertEqual(a.challenge.options[a.challenge.correctLane], a.challenge.card.translation)
            passGate(&a); passGate(&b)
        }
    }
    func testInvalidDecksAndSynonyms() throws {
        XCTAssertThrowsError(try VocabularyDeck(cards: [.init(word: "a", translation: "а")]))
        XCTAssertThrowsError(try VocabularyDeck(cards: [.init(id: "x", word: "a", translation: "а"), .init(id: "x", word: "b", translation: "б"), .init(word: "c", translation: "в")]))
        let deck = try VocabularyDeck(cards: [
            .init(word: "schnell", translation: "быстрый"), .init(word: "schnell", translation: "скорый"),
            .init(word: "langsam", translation: "медленный"), .init(word: "mutig", translation: "смелый")
        ])
        for seed in 1...40 {
            let game = GameEngine(deck: deck, seed: UInt64(seed))
            if game.challenge.card.word == "schnell" {
                XCTAssertFalse(game.challenge.options.contains(game.challenge.card.translation == "быстрый" ? "скорый" : "быстрый"))
            }
        }
    }
    func testContiguousZonesCoverEveryPositionIncludingBoundaries() {
        for x in stride(from: -6.0, through: 6.0, by: 0.125) {
            let lane = GameEngine.lane(at: x)
            XCTAssertTrue((0..<3).contains(lane))
            XCTAssertEqual(lane, x < -2 ? 0 : (x < 2 ? 1 : 2))
        }
        XCTAssertEqual(GameEngine.lane(at: -2), 1)
        XCTAssertEqual(GameEngine.lane(at: 2), 2)
    }
    func testFormerGapAlwaysRegistersAnAnswer() {
        var game = GameEngine(seed: 2); game.start(); game.targetX = 1.65
        for _ in 0..<600 {
            game.advance(1.0 / 60)
            if !game.records.isEmpty { break }
        }
        XCTAssertEqual(game.records.count, 1)
        if case .missed = game.lastEvent { XCTFail("There must be no between-zone collision") }
    }
}
