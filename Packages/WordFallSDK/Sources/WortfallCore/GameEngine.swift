import Foundation

public enum GamePhase: String, Sendable { case ready, playing, rebound, finishing, won, lost }
public struct Challenge: Sendable {
    public let card: VocabularyCard
    public let options: [String]
    public var prompt: String = ""
    public var direction: StudyMode = .wordToTranslation
    public let correctLane: Int
    public var rejectedLanes: Set<Int> = []
}
public enum GameEvent: Sendable {
    case correct(points: Int, healed: Bool)
    case wrong(lane: Int)
    case missed
    case completed
    case died
}

/// Deterministic simulation independent of rendering. Distances are meters, time is seconds.
public struct GameEngine: Sendable {
    public static let laneCenters: [Double] = [-4, 0, 4]
    public private(set) var phase: GamePhase = .ready
    public private(set) var level: Int = 1
    public private(set) var lives = 3
    public private(set) var score = 0
    public private(set) var streak = 0
    public private(set) var healedProgress = 0
    public private(set) var distance: Double = 0
    public private(set) var speed: Double = 6
    public private(set) var x: Double = 0
    public private(set) var answered = 0
    public private(set) var challenge: Challenge
    public private(set) var records: [AnswerRecord] = []
    public private(set) var eventSerial = 0
    public private(set) var lastEvent: GameEvent?
    public var targetX: Double = 0
    public var isPaused = false
    public var profile: LevelProfile { LevelProfile(number: level) }
    public var gateCount: Int { profile.words }
    public var gateSpacing: Double { profile.spacing }
    public var maximumSpeed: Double { profile.maximumSpeed }
    public var gateDistance: Double { Double(answered + 1) * gateSpacing }
    public var finishDistance: Double { profile.length }
    public var boost: Double { min(1, max(0, (speed - profile.baseSpeed) / (maximumSpeed - profile.baseSpeed))) }
    public var progress: Double { min(1, max(0, distance / finishDistance)) }
    public var multiplier: Int { min(8, 1 + streak / 3) }
    /// Three equal contiguous zones across the twelve-unit track; boundaries belong to the zone on the right.
    public static func lane(at x: Double) -> Int {
        guard x.isFinite else { return 1 }
        return x < -2 ? 0 : (x < 2 ? 1 : 2)
    }
    public var selectedLane: Int { Self.lane(at: x) }
    public var result: LevelResult { LevelResult(runID: runID, scopeID: scopeID, mode: deck.mode, timestamp: Date(), level: level, completed: phase == .won, score: score - levelStartScore, answers: records) }
    public private(set) var runID = UUID()
    private var challengeID = UUID()
    public let scopeID: String
    private let deck: VocabularyDeck
    private var random: SeededRandom
    private var bag: [VocabularyCard] = []
    private var bagIndex = 0
    private var directionBag: [StudyMode] = []
    private var lastCardID: String?
    private var reboundTime: Double = 0
    private var reboundStart: Double = 0
    private var questionTime: Double = 0
    private var attempts = 0
    private var levelStartScore = 0

    public init(deck: VocabularyDeck = .demo, seed: UInt64 = UInt64.random(in: 1...UInt64.max), startingLevel: Int = 1, scopeID: String = "default") {
        self.scopeID = scopeID
        self.deck = deck
        level = max(1, startingLevel)
        speed = LevelProfile(number: max(1, startingLevel)).baseSpeed
        random = SeededRandom(state: seed)
        challenge = Challenge(card: deck.cards[0], options: [], correctLane: 0)
        makeChallenge()
    }
    public mutating func start() { if phase == .ready { phase = .playing } }
    public mutating func selectLane(_ lane: Int) { guard (0..<3).contains(lane) else { return }; targetX = Self.laneCenters[lane] }
    public mutating func retry() {
        score = levelStartScore; lives = 3; resetLevel()
    }
    public mutating func nextLevel() {
        guard phase == .won else { return }
        level += 1; levelStartScore = score; resetLevel()
    }
    private mutating func resetLevel() {
        runID = UUID()
        phase = .ready; distance = 0; answered = 0; speed = profile.baseSpeed
        x = 0; targetX = 0; streak = 0; healedProgress = 0
        records = []; isPaused = false; lastEvent = nil; makeChallenge()
    }
    private mutating func makeChallenge() {
        if bagIndex >= bag.count {
            bag = deck.cards.shuffled(using: &random)
            bagIndex = 0
            if bag.count > 1, bag.first?.id == lastCardID { bag.swapAt(0, bag.count - 1) }
        }
        let card = bag[bagIndex]; bagIndex += 1; lastCardID = card.id
        if deck.mode == .mixed && directionBag.isEmpty { directionBag = StudyMode.directions.shuffled(using: &random) }
        let direction = deck.mode == .mixed ? directionBag.removeLast() : deck.mode
        // All accepted translations of the same source word are excluded from distractors.
        let accepted = deck.acceptedAnswers(for: direction, prompt: direction.prompt(for: card))
        var keys = accepted
        var distractors: [String] = []
        // Sample instead of shuffling the entire dictionary at every answer.
        for _ in 0..<32 {
            let other = deck.cards[Int.random(in: deck.cards.indices, using: &random)]
            if keys.insert(VocabularyDeck.key(direction.answer(for: other))).inserted { distractors.append(direction.answer(for: other)) }
            if distractors.count == 2 { break }
        }
        if distractors.count < 2 {
            for other in deck.cards {
                if keys.insert(VocabularyDeck.key(direction.answer(for: other))).inserted { distractors.append(direction.answer(for: other)) }
                if distractors.count == 2 { break }
            }
        }
        let options = ([direction.answer(for: card)] + distractors).shuffled(using: &random)
        challenge = Challenge(card: card, options: options, correctLane: options.firstIndex(of: direction.answer(for: card))!)
        challenge.direction = direction
        challenge.prompt = direction.prompt(for: card)
        challengeID = UUID()
        questionTime = 0; attempts = 0
    }
    public mutating func advance(_ delta: Double) {
        guard delta.isFinite, delta > 0, !isPaused else { return }
        // Substeps avoid tunneling and repeated damage. A long suspension never fast-forwards play.
        var remaining = min(delta, 0.1)
        while remaining > 0 {
            let dt = min(remaining, 1.0 / 120); step(dt); remaining -= dt
        }
    }
    private mutating func step(_ dt: Double) {
        guard phase == .playing || phase == .rebound || phase == .finishing else { return }
        let target = targetX.isFinite ? min(4.5, max(-4.5, targetX)) : 0
        x += (target - x) * (1 - exp(-10 * dt))
        questionTime += dt
        if phase == .rebound {
            reboundTime += dt
            let t = min(1, reboundTime / 0.65)
            distance = reboundStart - profile.baseSpeed * 1.6 * (1 - pow(1 - t, 3))
            if t >= 1 { phase = .playing }
            return
        }
        let desired = min(maximumSpeed, profile.baseSpeed * (1 + Double(streak) * 0.16 + Double(answered) * 0.025))
        speed += (desired - speed) * (1 - exp(-3.2 * dt))
        distance += speed * dt
        if phase == .finishing {
            if distance >= finishDistance { phase = .won; emit(.completed) }
            return
        }
        if distance >= gateDistance {
            distance = gateDistance
            let lane = selectedLane
            attempts += 1
            let correct = lane == challenge.correctLane
            records.append(AnswerRecord(id: UUID(), runID: runID, challengeID: challengeID, timestamp: Date(), scopeID: scopeID, mode: challenge.direction, studyMode: deck.mode, cardID: challenge.card.id, categoryIDs: challenge.card.categoryIDs, word: challenge.card.word, translation: challenge.card.translation, prompt: challenge.prompt, correctAnswer: challenge.direction.answer(for: challenge.card), selectedAnswer: challenge.options[lane], isCorrect: correct, attempt: attempts, responseTime: questionTime, level: level, points: correct ? 100 * min(8, 1 + (streak + 1) / 3) : 0))
            questionTime = 0
            if correct {
                streak += 1; healedProgress += 1
                let heal = healedProgress == 4 && lives < 3
                if healedProgress == 4 { lives = min(3, lives + 1); healedProgress = 0 }
                let points = 100 * multiplier; score += points; answered += 1
                emit(.correct(points: points, healed: heal))
                if answered == gateCount { phase = .finishing } else { makeChallenge() }
            } else {
                lives -= 1; streak = 0; healedProgress = 0; speed = profile.baseSpeed
                challenge.rejectedLanes.insert(lane)
                if lives == 0 { phase = .lost; emit(.died) }
                else { bounce(); emit(.wrong(lane: lane)) }
            }
        }
    }
    private mutating func bounce() { phase = .rebound; reboundTime = 0; reboundStart = distance }
    private mutating func emit(_ event: GameEvent) { lastEvent = event; eventSerial += 1 }
}
