import XCTest
import WortfallCore
@testable import WortfallKit

private actor TestStorage: ProgressStorage {
    var value = ProgressSnapshot()
    var failing = true
    struct Failure: LocalizedError { var errorDescription: String? { "Test write failure" } }
    func load() -> ProgressSnapshot { value }
    func save(_ snapshot: ProgressSnapshot) throws {
        if failing { throw Failure() }
        if snapshot.revision >= value.revision { value = snapshot }
    }
    func allowWrites() { failing = false }
}
final class ProgressModelTests: XCTestCase {
    @MainActor
    func testPauseMenuResumeKeepsCurrentRun() {
        let session = GameSession(deck: .demo, onAnswer: nil, onLevelEnd: nil)
        session.start(); session.tick(0.1)
        let before = session.engine
        session.pause(); session.inputSuspended = true
        session.tick(0.1); session.lane(2)
        XCTAssertEqual(session.engine.distance, before.distance)
        session.resume()
        XCTAssertEqual(session.engine.runID, before.runID)
        XCTAssertEqual(session.engine.challenge.prompt, before.challenge.prompt)
        XCTAssertEqual(session.engine.lives, before.lives)
        XCTAssertEqual(session.engine.distance, before.distance)
        XCTAssertFalse(session.engine.isPaused)
        XCTAssertFalse(session.inputSuspended)
    }
    @MainActor
    func testSaveFailureIsVisibleAndFlushRetriesWithoutLosingAnswers() async throws {
        let storage = TestStorage()
        let model = try await WortfallProgress.open(storage: storage)
        var engine = GameEngine(seed: 123)
        engine.start()
        for _ in 0..<1000 {
            engine.selectLane(engine.challenge.correctLane)
            engine.advance(1.0 / 60)
            if !engine.records.isEmpty { break }
        }
        let answer = try XCTUnwrap(engine.records.first)
        model.record(answer)
        do { try await model.flush(); XCTFail("Write failure must propagate") } catch {}
        XCTAssertNotNil(model.saveError)
        XCTAssertEqual(model.snapshot.earnedPoints, answer.points)
        await storage.allowWrites()
        try await model.flush()
        XCTAssertNil(model.saveError)
        let restored = try await WortfallProgress.open(storage: storage)
        XCTAssertEqual(restored.snapshot.words[answer.cardID]?.attempts, 1)
        restored.record(answer)
        try await restored.flush()
        XCTAssertEqual(restored.snapshot.words[answer.cardID]?.attempts, 1)
    }
    @MainActor
    func testQueuedWritesSaveLatestResultAndUnlock() async throws {
        let storage = TestStorage()
        await storage.allowWrites()
        let model = try await WortfallProgress.open(storage: storage)
        var engine = GameEngine(seed: 31, scopeID: "host-deck")
        engine.start()
        var recorded = 0
        for _ in 0..<5000 {
            engine.selectLane(engine.challenge.correctLane); engine.advance(1.0 / 60)
            if engine.records.count > recorded {
                model.record(engine.records.last!); recorded = engine.records.count
            }
            if engine.phase == .won { break }
        }
        XCTAssertEqual(engine.phase, .won)
        model.record(engine.result)
        try await model.flush()
        let saved = await storage.load()
        XCTAssertEqual(saved.unlockedLevel(scopeID: "host-deck", mode: .wordToTranslation), 2)
        XCTAssertEqual(saved.earnedPoints, engine.result.score)
        XCTAssertEqual(saved.answerIDs.count, recorded)
    }
}
