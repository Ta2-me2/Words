import Foundation
import Observation

/// One sitting: the cards it was built from, the one on screen, and what
/// happens to each answer.
///
/// The session owns the order of the queue and nothing else. Deciding when a
/// card is next wanted belongs to the scheduler, and writing it down belongs to
/// the store — so a different algorithm changes nothing here.
@Observable
final class StudySession {

    /// A card sent back for another go lands at the end of the queue if it is
    /// wanted again soon enough to still be this sitting.
    private static let sameSessionWindow: TimeInterval = 20 * 60

    let profile: LanguageProfile

    /// The deck being studied, or `nil` for the whole language.
    let deck: Deck?

    let mode: StudyMode

    /// Which way round the cards are asked, as the language was set when the
    /// sitting began. Changing it mid-sitting would turn a card over under the
    /// learner's eyes.
    let direction: StudyDirection

    /// This sitting's own draw for a mixed direction.
    private let directionSeed: UInt64

    private let store: LibraryStore

    private(set) var remaining: [QueuedCard] = []

    /// An endless sitting draws its next card rather than taking it off a
    /// queue. `remaining` then holds the one card on screen and nothing else.
    ///
    /// Not observed: no view reads it, and a value type mutated in place is not
    /// something the observation machinery can hand out by reference.
    @ObservationIgnored private var stream: EndlessDeck?

    /// Cards that are done for today, counted once however many times they came
    /// back during the sitting.
    private(set) var finished: Set<UUID> = []

    private(set) var plannedCount = 0

    /// Every answer given, repeats included. The honest measure of the work.
    private(set) var answerCount = 0

    private(set) var isRevealed = false

    /// Whether this sitting was picked up where it was left rather than begun.
    private(set) var isResumed = false

    private var shownAt = Date.now

    private let calendar: Calendar

    init(
        profile: LanguageProfile,
        deck: Deck? = nil,
        mode: StudyMode = .scheduled,
        store: LibraryStore,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        self.profile = profile
        self.deck = deck
        self.mode = mode
        self.direction = profile.studyDirection
        self.directionSeed = .random(in: .min ... .max)
        self.store = store
        self.calendar = calendar

        if let saved = mode.isResumable
            ? store.library.snapshot(profileID: profile.id, deckID: deck?.id, mode: mode, asOf: now, calendar: calendar)
            : nil {
            // Picked up where it was left. A word deleted in the meantime is
            // dropped rather than asked about, and the count comes down with
            // it: the sitting is honest about what is actually left.
            remaining = saved.remaining.filter { exists($0) }
            finished = Set(saved.finished)
            plannedCount = min(saved.plannedCount, finished.count + remaining.count)
            answerCount = saved.answerCount
            isResumed = true

            if isFinished { store.forgetSession(profileID: profile.id, deckID: deck?.id, mode: mode) }
        } else {
            switch mode {
            case .scheduled:
                remaining = store.library.queue(for: profile.id, deckID: deck?.id, asOf: now, calendar: calendar)
            case .practiceToday:
                remaining = store.library.practiceQueue(for: profile.id, deckID: deck?.id, asOf: now, calendar: calendar)
            case .endless(let pool):
                let scope = EndlessDeck(cards: store.library.endlessQueue(for: profile.id, deckID: deck?.id, pool: pool))
                plannedCount = scope.cards.count
                stream = scope
                remaining = []
            }
            if !mode.isEndless { plannedCount = remaining.count }
        }

        if mode.isEndless { remaining = draw() }
        shownAt = now
    }

    /// The next card of an endless sitting, skipping any that has been deleted
    /// since the sitting began.
    ///
    /// Only the card about to be shown is checked. Validating the whole scope
    /// after every answer would be a search of the library for every word in
    /// it, which on a real vocabulary is thousands of comparisons to catch
    /// something that almost never happens.
    private func draw() -> [QueuedCard] {
        guard var scope = stream else { return [] }
        defer { stream = scope }

        for _ in 0..<(scope.cards.count + 1) {
            guard let card = scope.next() else { return [] }
            if exists(card) { return [card] }
            scope.drop(card.cardID)
        }
        return []
    }

    private func exists(_ card: QueuedCard) -> Bool {
        store.library.entry(id: card.entryID)?.card(id: card.cardID) != nil
    }

    // MARK: - What is on screen

    var current: QueuedCard? { remaining.first }

    var currentEntry: Entry? {
        current.flatMap { store.library.entry(id: $0.entryID) }
    }

    var currentState: SchedulingState? {
        guard let current, let entry = store.library.entry(id: current.entryID) else { return nil }
        return entry.card(id: current.cardID)?.scheduling
    }

    /// What the card on screen shows before its answer.
    var currentPrompt: CardPrompt {
        guard let current else { return .word }
        return direction.prompt(for: current.cardID, seed: directionSeed)
    }

    /// Whether the card on screen has never been answered, in a sitting whose
    /// answers count. Its Easy is then "I know this word".
    var isFirstSight: Bool {
        mode == .scheduled && currentState?.stage == .new
    }

    /// What an answer button says for the card on screen.
    func title(for grade: ReviewGrade) -> String {
        grade == .easy && isFirstSight ? "I Know This Word" : grade.title
    }

    /// An endless sitting is never finished; it is left.
    var isFinished: Bool { !mode.isEndless && remaining.isEmpty }

    var finishedCount: Int { finished.count }

    /// `nil` where there is nothing to be a fraction of.
    var progress: Double? {
        guard !mode.isEndless, plannedCount > 0 else { return nil }
        return min(1, Double(finished.count) / Double(plannedCount))
    }

    /// "3 of 12" while there is an end in sight, and a count of the work
    /// otherwise. A sitting that was picked up says so, or coming back to it
    /// would look exactly like starting it again.
    var progressText: String {
        if mode.isEndless {
            return "\(answerCount) answered · \(finished.count) of \(plannedCount) seen"
        }
        let place = "\(min(finished.count + (isFinished ? 0 : 1), plannedCount)) of \(plannedCount)"
        return isResumed ? "Resumed · \(place)" : place
    }

    // MARK: - Answering

    func reveal() {
        guard !isRevealed else { return }
        isRevealed = true
    }

    /// What each button promises, worked out by the same scheduler that will
    /// keep the promise. Practice promises nothing, so it says nothing.
    func intervalText(for grade: ReviewGrade, at date: Date = .now) -> String? {
        guard mode == .scheduled, let state = currentState else { return nil }
        let next = store.scheduler.nextState(
            for: state,
            grade: grade,
            at: date,
            retention: profile.desiredRetention
        )
        return IntervalText.short(for: next, from: date)
    }

    func answer(_ grade: ReviewGrade, at date: Date = .now) {
        guard let card = current else { return }

        let seconds = max(0, date.timeIntervalSince(shownAt))

        switch mode {
        case .scheduled:
            let state = store.answer(card, grade: grade, at: date, seconds: seconds)
            remaining.removeFirst()

            if let state, state.isInLearning,
               let due = state.dueDate,
               due.timeIntervalSince(date) <= Self.sameSessionWindow {
                // Still being learned, and wanted again soon: it comes back at
                // the end of the queue rather than immediately, so the sitting
                // is not a staring contest with one word.
                remaining.append(card)
            } else {
                finished.insert(card.cardID)
            }

        case .practiceToday:
            store.practise(card, grade: grade, at: date, seconds: seconds)
            remaining.removeFirst()

            // Only a word that would not come at all is asked again.
            if grade == .again {
                remaining.append(card)
            } else {
                finished.insert(card.cardID)
            }

        case .endless:
            store.practise(card, grade: grade, at: date, seconds: seconds)
            finished.insert(card.cardID)
            stream?.record(card, grade: grade)
            remaining = draw()
        }

        answerCount += 1

        // A word deleted in another window must not be asked about. An endless
        // sitting checks this as it draws instead.
        if !mode.isEndless { remaining.removeAll { !exists($0) } }

        isRevealed = false
        shownAt = date
        persist(at: date)
    }

    /// Written down after every answer rather than when the window closes: a
    /// sitting can also end by the lid coming down, and the work up to that
    /// point is the learner's either way.
    private func persist(at date: Date) {
        guard mode.isResumable else { return }

        guard !isFinished else {
            store.forgetSession(profileID: profile.id, deckID: deck?.id, mode: mode)
            return
        }

        store.keep(
            StudySnapshot(
                profileID: profile.id,
                deckID: deck?.id,
                mode: mode,
                day: calendar.startOfDay(for: date),
                remaining: remaining,
                finished: Array(finished),
                plannedCount: plannedCount,
                answerCount: answerCount,
                updatedAt: date
            )
        )
    }

}
