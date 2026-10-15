import Foundation
import Observation

/// Where the introduction has got to.
///
/// One value for the whole scene, because every part of it — what the
/// companion is feeling, what is written under it, what is on screen beside it
/// — is a different view of the same moment. Views that each keep their own
/// idea of "are we there yet" drift apart, and a sequence that drifts reads as
/// broken rather than as slow.
nonisolated enum IntroStage: Equatable, Sendable {

    /// Nothing yet. The companion is arriving.
    case waking

    /// Asking for a hello.
    case asking

    /// Working out what was typed. The only stage with a wait in it, and the
    /// wait is the point: a reply that lands the instant you press Return does
    /// not read as somebody considering it.
    case thinking

    /// Several languages write it that way, so it asks.
    case choosing([String])

    /// It did not recognise what was typed.
    case lost

    /// It knows, and is saying hello back.
    case greeting(IntroChoice)

    /// Beside the tour.
    case touring(IntroChoice)

    /// Coming apart into the wordmark.
    case becoming(IntroChoice)

    /// Finished. The library has a language in it and the app is behind this.
    case done(IntroChoice)

    var mood: CompanionMood {
        switch self {
        case .waking: .asleep
        case .asking: .curious
        case .thinking: .thinking
        case .choosing: .curious
        case .lost: .puzzled
        case .greeting: .delighted
        case .touring: .watching
        case .becoming, .done: .leaving
        }
    }

    /// The language that has been settled on, where one has.
    var choice: IntroChoice? {
        switch self {
        case .greeting(let choice), .touring(let choice), .becoming(let choice), .done(let choice): choice
        default: nil
        }
    }
}

/// The introduction, as a thing that happens rather than a screen that is
/// drawn.
@MainActor @Observable
final class IntroModel {

    private(set) var stage: IntroStage = .waking

    /// What has been typed into the field.
    var typed = ""

    /// Said under the field when what was typed was understood but was not an
    /// answer to the question — most often because it was the language the
    /// learner already speaks.
    private(set) var nudge: String?

    /// The language the learner already speaks, used to tell them so.
    let nativeCode: String

    private var work: Task<Void, Never>?

    init(nativeCode: String = LanguageCatalog.systemCode) {
        self.nativeCode = nativeCode
    }

    // MARK: - The sequence

    func begin() {
        guard stage == .waking else { return }
        schedule(after: .milliseconds(900)) { $0.stage = .asking }
    }

    /// Return was pressed.
    func submit() {
        let asked = typed
        guard !Greetings.normalise(asked).isEmpty else { return }

        nudge = nil
        stage = .thinking

        // The pause is theatre, and honest theatre: the table answers at once,
        // and a companion that replied in nought seconds would be a lookup
        // rather than somebody listening. Long enough to read as thought,
        // short enough never to be a wait.
        schedule(after: .milliseconds(950)) {
            $0.settle(on: Greetings.match(asked))
        }
    }

    private func settle(on match: GreetingMatch) {
        switch match {
        case .one(let code) where code == nativeCode:
            // Asked for the language they want to learn, answered with the one
            // they already have. Worth saying out loud, or they will type it
            // again.
            nudge = "That is the language you already speak. Try the one you want to learn."
            typed = ""
            stage = .asking

        case .one(let code):
            choose(.known(code))

        case .several(let codes):
            stage = .choosing(codes)

        case .unknown:
            stage = .lost
        }
    }

    /// A language was picked — from the two or three it was unsure about, or
    /// from the whole list, or made up on the spot.
    func choose(_ choice: IntroChoice) {
        stage = .greeting(choice)
        schedule(after: .milliseconds(2400)) { model in
            guard case .greeting(let choice) = model.stage else { return }
            model.stage = .touring(choice)
        }
    }

    /// The tour is over, by its own end or because it was skipped.
    func endTour() {
        guard case .touring(let choice) = stage else { return }
        stage = .becoming(choice)
    }

    /// The wordmark has formed.
    func finish() {
        guard case .becoming(let choice) = stage else { return }
        stage = .done(choice)
    }

    /// Start again from the question, after the list was opened and closed
    /// without a choice.
    func askAgain() {
        work?.cancel()
        typed = ""
        nudge = nil
        stage = .asking
    }

    /// The one place a beat of the sequence is set going.
    ///
    /// Weakly held and cancellable, so a window closed in the middle of the
    /// introduction takes its unfinished beats with it rather than waking up
    /// a model nobody is looking at any more.
    private func schedule(after delay: Duration, _ step: @escaping @MainActor (IntroModel) -> Void) {
        work?.cancel()
        work = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            step(self)
        }
    }
}
