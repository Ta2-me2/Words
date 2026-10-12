import Foundation
import FoundationModels
import Observation
import WordsCompanion

/// Asking the companion for one example sentence.
///
/// The companion writes examples in three places: one word at a time in Add
/// Words, row by row in a pasted list, and in a run over every word in the
/// library that has none. All three ask the same thing in the same words, and
/// what is shared lives here — how the session is made, what is asked, what
/// counts as an answer, and how a model that has gone wrong is described.
/// `SentenceMaker` is the run over many words; this is one word at a time,
/// which is the case where the answer lands in a field somebody is editing.
///
/// One request at a time, on purpose. The model answers one at a time whatever
/// is asked of it, and a second spinner would promise work that has not
/// started.
@Observable
@MainActor
final class SentenceWriter {

    /// What is going on, and which word it is about.
    enum State: Equatable {
        case idle
        /// The word being written for, named so a row can show its own spinner.
        case writing(String)
        /// The word that was asked for, and why what came back was no use.
        case refused(String, String)
    }

    private(set) var state: State = .idle

    @ObservationIgnored private var work: Task<Void, Never>?

    var isWriting: Bool {
        if case .writing = state { return true }
        return false
    }

    func isWriting(_ key: String) -> Bool { state == .writing(key) }

    /// Why the last attempt for this word came to nothing, if it did.
    func refusal(for key: String) -> String? {
        guard case .refused(let asked, let reason) = state, asked == key else { return nil }
        return reason
    }

    /// The same, whichever word it was about, for a screen with one place to
    /// say it rather than one per row.
    var lastRefusal: String? {
        guard case .refused(_, let reason) = state else { return nil }
        return reason
    }

    /// Forgets what was said about the last attempt, for when the word it was
    /// about has been typed over.
    func forget() {
        guard case .refused = state else { return }
        state = .idle
    }

    // MARK: - Asking

    /// Asks for one sentence, and hands back what came if anything did.
    ///
    /// `filled` is given the sentence and its translation, and is called only
    /// once both have been read and checked — never with half an answer, and
    /// never after the request was let go of.
    func write(
        _ key: String,
        word: String,
        meaning: String,
        for profile: LanguageProfile,
        companion: CompanionModel?,
        filled: @escaping (String, String) -> Void
    ) {
        let word = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isWriting, !word.isEmpty else { return }
        state = .writing(key)

        work = Task { [weak self] in
            do {
                let session = try Self.session(for: profile, companion: companion)
                let made = try await Self.make(word: word, meaning: meaning, with: session)
                guard let self, !Task.isCancelled else { return }
                filled(made.sentence, made.translation)
                state = .idle
            } catch is CancellationError {
                self?.state = .idle
            } catch {
                self?.state = .refused(key, Self.reason(for: error, word: word))
            }
        }
    }

    /// Lets go of a request in flight. Whatever the model does with it
    /// afterwards is its own business; none of it reaches the field.
    func cancel() {
        work?.cancel()
        work = nil
        state = .idle
    }

    // MARK: - The model

    /// A session with whichever companion was chosen in Settings, told how to
    /// write an example for this language pair.
    static func session(for profile: LanguageProfile, companion: CompanionModel?) throws -> LanguageModelSession {
        let instructions = SentencePrompt.instructions(for: profile)
        if let companion, #available(macOS 27, *) {
            return LanguageModelSession(
                model: CompanionStore.languageModel(for: companion),
                instructions: instructions
            )
        }
        return LanguageModelSession(instructions: instructions)
    }

    /// One sentence, asked for and read, or `SentenceError` if what came back
    /// was not one.
    static func make(
        word: String,
        meaning: String,
        with session: LanguageModelSession
    ) async throws -> (sentence: String, translation: String) {
        var options = GenerationOptions()
        // Low: an example sentence is wanted correct, not interesting.
        options.temperature = 0.3
        // Two short lines is the whole answer. A model that has started
        // rambling is stopped here rather than read and refused — and a
        // runaway answer on a Mac costs the learner the wait.
        options.maximumResponseTokens = 200

        let response = try await session.respond(
            to: SentencePrompt.ask(word: word, meaning: meaning),
            options: options
        )
        guard let made = SentencePrompt.read(response.content, word: word) else {
            throw SentenceError(reason: "What came back wasn’t a sentence using “\(word)”.")
        }
        return made
    }

    /// What went wrong, said in a line that fits beside a field.
    static func reason(for error: any Error, word: String) -> String {
        if let error = error as? SentenceError { return error.reason }
        if #available(macOS 27, *), let error = error as? LanguageModelError {
            switch error {
            case .unsupportedLanguageOrLocale:
                return "This companion doesn’t write that language yet."
            case .guardrailViolation, .refusal:
                return "The companion wouldn’t write a sentence for “\(word)”."
            case .rateLimited:
                return "Too many at once — wait a moment and try again."
            case .timeout:
                return "It took too long. Try again."
            default:
                return error.localizedDescription
            }
        }
        return error.localizedDescription
    }

    /// Whether the companion chosen in Settings can be asked at all, and what
    /// to say when it cannot. Four screens ask this now, and somebody looking
    /// at a dimmed button is owed the same answer in each.
    static func problem(with companion: CompanionModel?) -> String? {
        switch CardAssistant.readiness(for: companion) {
        case .ready:
            nil
        case .turnedOff:
            "Apple Intelligence is turned off. Turn it on in System Settings, or install a companion in Settings."
        case .preparing:
            "Apple Intelligence is still getting ready on this Mac. Try again in a few minutes."
        case .unsupported:
            "This Mac can’t run the companion."
        case .notInstalled(let name):
            "\(name) isn’t installed. Install it in Settings, or choose Apple Intelligence there."
        }
    }
}

/// What came back could not be used as an example, and why — in a line meant
/// to be read by the person who asked, not logged.
nonisolated struct SentenceError: Error {
    let reason: String
}
