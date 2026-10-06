import XCTest
import RealityKit
import AppKit
import WortfallCore
@testable import WortfallKit

final class SceneReuseTests: XCTestCase {
    @MainActor
    func testSceneReusesEntitiesAcrossAnswersAndTerrainCycles() async throws {
            let view = ARView(frame: CGRect(x: 0, y: 0, width: 1000, height: 750))
            let session = GameSession(deck: .demo, startingLevel: 9, onAnswer: nil, onLevelEnd: nil)
            session.soundEnabled = false
            let scene = try GameScene(session: session, view: view)
            defer { scene.stop() }
            let count = scene.entityCountForTesting
            let identities = scene.entityIDsForTesting
            session.start()
            var frameTimes: [Double] = [], answerTimes: [Double] = []
            for frame in 0..<3000 {
                session.engine.selectLane(session.engine.challenge.correctLane)
                let before = session.engine.answered
                let start = ProcessInfo.processInfo.systemUptime
                scene.advanceForTesting(1.0 / 60)
                let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
                frameTimes.append(elapsed)
                if frame % 60 == 0 {
                    XCTAssertGreaterThanOrEqual(scene.contactClearanceForTesting, -0.012, "Animated body must not penetrate the rendered surface")
                    XCTAssertLessThan(scene.contactClearanceForTesting, 0.085, "At least one support must remain close to the track")
                }
                if session.engine.answered != before {
                    answerTimes.append(elapsed)
                    XCTAssertEqual(scene.entityCountForTesting, count, "Answer must not create or delete scene entities")
                }
            }
            XCTAssertEqual(scene.entityIDsForTesting, identities, "The exact same objects must be recycled")
            XCTAssertGreaterThan(session.engine.answered, 10)
            XCTAssertGreaterThan(session.engine.distance * session.engine.profile.visualScale, 288)
            XCTAssertEqual(scene.entityCountForTesting, count, "Terrain recycling must not grow the scene")
            await session.retry()
            XCTAssertEqual(scene.entityIDsForTesting, identities, "Retry must reuse prepared meshes and entities")
            await session.prepare(deck: try VocabularyDeck(cards: VocabularyDeck.demo.cards, mode: .translationToWord), level: 9, scopeID: "menu-selection")
            XCTAssertEqual(scene.entityIDsForTesting, identities, "Selecting a deck in the menu must reuse the scene")
            XCTAssertEqual(session.engine.phase, .ready)
            XCTAssertEqual(session.engine.challenge.prompt, session.engine.challenge.card.translation)
            XCTAssertEqual(session.engine.scopeID, "menu-selection")
            session.inputSuspended = true
            let target = session.engine.targetX
            session.lane(2); session.point(1)
            XCTAssertEqual(session.engine.targetX, target, "Menu input must not steer the player behind the panel")
            session.start()
            XCTAssertFalse(session.inputSuspended)
            let loading = Task { await session.prepare(deck: .demo, level: 10, scopeID: "loading-test") }
            await Task.yield()
            // Allow the transition to publish its initial state before the first mesh batch.
            try await Task.sleep(for: .milliseconds(5))
            XCTAssertTrue(session.isLoading)
            var samples: [Double] = []
            while session.isLoading {
                samples.append(session.loadingProgress)
                let distance = session.engine.distance
                session.tick(1)
                XCTAssertEqual(session.engine.distance, distance, "Preparation must not consume playing time")
                let x = session.engine.targetX
                session.point(0)
                XCTAssertEqual(session.engine.targetX, x, "Loading must ignore steering")
                try await Task.sleep(for: .milliseconds(10))
            }
            await loading.value
            XCTAssertTrue(samples.contains { $0 > 0.04 && $0 < 0.96 }, "Mesh preparation must yield intermediate progress")
            XCTAssertEqual(samples, samples.sorted(), "Progress must never move backwards")
            XCTAssertEqual(session.loadingProgress, 1)
            XCTAssertEqual(session.engine.level, 10)
            XCTAssertEqual(session.engine.phase, .ready)
            XCTAssertLessThan(scene.entityCountForTesting, 600, "New theme must retain a bounded scene")
            session.start()
            XCTAssertEqual(session.engine.phase, .playing)
            frameTimes.sort()
            print("SCENE_CPU_CALLBACK p95_ms=\(frameTimes[Int(Double(frameTimes.count) * 0.95)]) answer_max_ms=\(answerTimes.max() ?? 0) entities=\(count) answers=\(answerTimes.count)")
    }
    func testPeriodicTrackMeetsWithoutGaps() async {
        await MainActor.run {
            for d: Float in stride(from: 0, through: 288, by: 3) {
                let original = Geometry.course(d + 12, variation: 0.71) - Geometry.course(d, variation: 0.71)
                let recycled = Geometry.course(d + 300, variation: 0.71) - Geometry.course(d + 288, variation: 0.71)
                XCTAssertEqual(original.x, recycled.x, accuracy: 0.001)
                XCTAssertEqual(original.y, recycled.y, accuracy: 0.001)
            }
        }
    }
}
