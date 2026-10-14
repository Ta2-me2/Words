import Foundation
import Observation

/// One sitting of the dictation game.
///
/// Holds the queue, what is being typed, and what happened to the last answer.
/// It plays nothing and writes nothing: the screen owns the voice, and the
/// store owns the file.
@Observable
@MainActor
final class DictationSession {

    enum Phase: Equatable {
        /// Listening and typing.
        case typing
        /// Answered, and marked.
        case marked(DictationResult, ReviewGrade)
    }

    private(set) var queue: DictationQueue
    private(set) var phase: Phase = .typing

    /// What the learner has typed: one box per word of the phrase.
    ///
    /// The shape of the answer is the shape of the phrase, which is the point
    /// of the game — how many words there are is the first thing heard. The
    /// boxes are kept here rather than in the view so that what was typed
    /// survives a redraw, and so that marking can see which box was left
    /// empty rather than only that a word is missing from the end.
    private(set) var boxes: [String] = []

    private(set) var replays = 0

    /// Whether the answer was looked up before it was given.
    private(set) var revealed = false

    /// Words right out of words asked, over the whole sitting.
    private(set) var wordsWanted = 0
    private(set) var wordsRight = 0
    private(set) var perfect = 0

    /// Answered without a single mistake, one after another.
    private(set) var run = 0
    private(set) var bestRun = 0

    /// How long the phrase in front took, measured when it was checked rather
    /// than when it is written down: the answer screen is for reading, and
    /// reading it is not time spent answering.
    private(set) var lastSeconds: Double = 0

    private var startedAt = Date.now

    init(queue: DictationQueue) {
        self.queue = queue
        emptyTheBoxes()
    }

    var isEmpty: Bool {
        boxes.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// What was typed, as one line — for anything that wants the answer rather
    /// than the shape of it.
    var typed: String {
        boxes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Typing

    func box(_ index: Int) -> String {
        boxes.indices.contains(index) ? boxes[index] : ""
    }

    func setBox(_ index: Int, to text: String) {
        guard boxes.indices.contains(index) else { return }
        boxes[index] = text
    }

    /// Several words at once, from the box they were typed or pasted into
    /// onwards. Returns the box the cursor should land in — the one after the
    /// last that was filled, or the last of them if there is nothing after.
    @discardableResult
    func fill(from index: Int, with words: [String]) -> Int {
        guard !words.isEmpty else { return index }
        var at = index
        for word in words {
            guard boxes.indices.contains(at) else { break }
            boxes[at] = word
            at += 1
        }
        return min(at, max(0, boxes.count - 1))
    }

    /// A box for every word of the phrase in front, all of them empty.
    private func emptyTheBoxes() {
        boxes = Array(repeating: "", count: words.count)
    }

    var item: DictationItem? { queue.current }
    var isFinished: Bool { queue.isFinished }

    var accuracy: Double {
        wordsWanted == 0 ? 0 : Double(wordsRight) / Double(wordsWanted)
    }

    /// The words of the phrase in front, for drawing the hint.
    var words: [String] {
        guard let item else { return [] }
        return DictationText.words(of: item.text)
    }

    // MARK: - Playing

    func heardAgain() {
        guard phase == .typing else { return }
        replays += 1
    }

    /// Gives the answer away. The phrase comes round again whatever is typed
    /// after it: a phrase read is not a phrase heard.
    func reveal() {
        guard phase == .typing, let item else { return }
        revealed = true
        boxes = DictationText.words(of: item.text)
    }

    /// Marks what was typed. Returns what it was worth, and how long it took.
    @discardableResult
    func check() -> (result: DictationResult, grade: ReviewGrade, seconds: Double)? {
        guard phase == .typing, let item else { return nil }
        let result = DictationCheck.mark(boxes: boxes, against: item.text)
        let grade = DictationCheck.grade(result, replays: replays, revealed: revealed)
        lastSeconds = max(0, Date.now.timeIntervalSince(startedAt))

        wordsWanted += result.words.count
        wordsRight += result.words.count { !$0.isFaulty }
        if result.isPerfect {
            perfect += 1
            run += 1
            bestRun = max(bestRun, run)
        } else {
            run = 0
        }

        phase = .marked(result, grade)
        return (result, grade, lastSeconds)
    }

    /// Puts the answer behind and brings the next phrase up.
    ///
    /// Returns whether this was the first answer to that phrase in the
    /// sitting — a phrase sent round again for being wrong is not counted
    /// towards the day twice.
    @discardableResult
    func advance() -> Bool {
        guard case .marked(_, let grade) = phase else { return false }
        let counted = queue.finish(grade)
        emptyTheBoxes()
        replays = 0
        revealed = false
        phase = .typing
        startedAt = .now
        return counted
    }

    /// Leaves the phrase in front unanswered — for one whose sentence has just
    /// been deleted.
    func skip() {
        queue.skip()
        emptyTheBoxes()
        replays = 0
        revealed = false
        phase = .typing
        startedAt = .now
    }
}
