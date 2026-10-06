import SwiftUI
import WortfallCore

@MainActor
final class GateProjection: ObservableObject {
    @Published var anchors: [CGPoint] = []
}

@MainActor
final class GameSession: ObservableObject {
    var engine: GameEngine
    @Published var snapshot: GameEngine
    @Published var soundEnabled = true
    @Published var reducedMotion = false
    @Published var error: String?
    @Published private(set) var isLoading = false
    @Published private(set) var loadingProgress: Double = 0
    @Published private(set) var loadingStage = "Preparing words"
    private var pauseAfterLoading = false
    let projection = GateProjection()
    @Published var feedback: String?
    private var feedbackTime: Double = 0
    private var deck: VocabularyDeck
    var inputSuspended = false
    var onAnswer: ((AnswerRecord) -> Void)?
    var onLevelEnd: ((LevelResult) -> Void)?
    var elapsed: Double = 0
    var scene: GameScene?
    init(deck: VocabularyDeck, startingLevel: Int = 1, onAnswer: ((AnswerRecord) -> Void)?, onLevelEnd: ((LevelResult) -> Void)?, scopeID: String = "default") {
        self.deck = deck
        let e = GameEngine(deck: deck, startingLevel: startingLevel, scopeID: scopeID); engine = e; snapshot = e
        self.onAnswer = onAnswer; self.onLevelEnd = onLevelEnd
    }
    func prepare(deck: VocabularyDeck, level: Int, scopeID: String) async {
        await transition {
            self.deck = deck
            engine = GameEngine(deck: deck, startingLevel: level, scopeID: scopeID)
        }
    }
    private func transition(_ change: () -> Void) async {
        guard !isLoading else { return }
        isLoading = true; loadingProgress = 0; loadingStage = "Preparing words"
        pauseAfterLoading = false
        // Commit the overlay before creating meshes on the main actor.
        try? await Task.sleep(for: .milliseconds(32))
        change(); sync()
        feedback = nil; feedbackTime = 0; elapsed = 0
        loadingProgress = 0.04
        await scene?.rebuildWithProgress { fraction, stage in
            loadingProgress = 0.04 + fraction * 0.92; loadingStage = stage
        }
        loadingProgress = 1; loadingStage = "Ready to slide"
        sync()
        try? await Task.sleep(for: .milliseconds(32))
        isLoading = false
    }
    func start() {
        guard !isLoading else { return }
        inputSuspended = false; engine.start()
        if pauseAfterLoading { engine.isPaused = true }
        scene?.focus(); sync()
    }
    func resume() { guard !isLoading else { return }; inputSuspended = false; engine.isPaused = false; scene?.focus(); sync() }
    func retry() async { await transition { engine.retry() }; start() }
    func next() async { await transition { engine.nextLevel() } }
    func togglePause() {
        guard !isLoading else { return }
        guard [.playing, .rebound, .finishing].contains(engine.phase) else { return }
        engine.isPaused.toggle(); sync()
    }
    func pause() {
        if isLoading { pauseAfterLoading = true; return }
        guard [.playing, .rebound, .finishing].contains(engine.phase) else { return }
        engine.isPaused = true; sync()
    }
    func point(_ fraction: Double) { guard !inputSuspended && !isLoading else { return }; engine.targetX = (fraction - 0.5) * 10.4 }
    func lane(_ index: Int) { guard !inputSuspended && !isLoading else { return }; engine.selectLane(index) }
    func translation(for id: String) -> String { deck.cards.first { $0.id == id }?.translation ?? "" }
    func tick(_ dt: Double) {
        guard !isLoading, engine.phase != .ready else { return }
        if !engine.isPaused && feedbackTime > 0 { feedbackTime -= dt; if feedbackTime <= 0 { feedback = nil } }
        let count = engine.records.count
        let serial = engine.eventSerial
        engine.advance(dt)
        if engine.records.count > count, let answer = engine.records.last { onAnswer?(answer) }
        if engine.eventSerial != serial {
            scene?.event(engine.lastEvent)
            feedbackTime = 1.8
            switch engine.lastEvent {
            case .correct(let points, let healed): feedback = healed ? "+\(points) · Life restored!" : "+\(points) · Streak \(engine.streak)"
            case .wrong: feedback = "Try another answer · −1 ♥"
            case .missed: feedback = "Choose an answer zone"
            default: feedback = nil
            }
            if engine.phase == .lost || engine.phase == .won { onLevelEnd?(engine.result) }
            sync()
        }
        elapsed += dt
        if elapsed >= 1.0 / 30 { elapsed = 0; sync() }
    }
    func sync() { snapshot = engine }
}
