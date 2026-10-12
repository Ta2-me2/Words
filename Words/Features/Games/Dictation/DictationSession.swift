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

    /// What the learner has typed, as one line.
    ///
    /// One field rather than a box per word, after trying it the other way:
    /// moving the cursor between boxes cannot be made to happen before the
    /// next keystroke arrives, so a letter typed quickly after a space lands
    /// in the box that was just left. One field has no such seam — and it is
    /// the thing that lets the third word of eight be clicked into and fixed
    /// without deleting the five after it, which is the whole reason for
    /// having a real field at all.
    var typed = ""

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
    }

    var isEmpty: Bool {
        typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        typed = item.text
    }

    /// Marks what was typed. Returns what it was worth, and how long it took.
    @discardableResult
    func check() -> (result: DictationResult, grade: ReviewGrade, seconds: Double)? {
        guard phase == .typing, let item else { return nil }
        let result = DictationCheck.mark(typed, against: item.text)
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
        typed = ""
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
        typed = ""
        replays = 0
        revealed = false
        phase = .typing
        startedAt = .now
    }
}
