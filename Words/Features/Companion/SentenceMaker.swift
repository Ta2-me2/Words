import Foundation
import FoundationModels
import Observation
import WordsCompanion

/// Asking the companion for one short, correct sentence per word, over a run
/// of words that have none.
///
/// The sentences are written onto the words themselves, as their examples, so
/// the work shows up everywhere a word does: on the card during an ordinary
/// sitting, and in the dictation game. Nothing is saved until the learner has
/// read it — a model writing grammar for somebody who cannot yet check it is
/// exactly the case where a review step is not optional.
///
/// One word at a time, in order, and the asking itself is `SentenceWriter`'s:
/// the prompt, the reading of the answer and the describing of a failure are
/// the same here as beside a single field in Add Words.
@Observable
@MainActor
final class SentenceMaker {

    /// One word, and what came back for it.
    struct Line: Identifiable {
        let id: UUID
        let term: String
        let meaning: String
        var sentence = ""
        var translation = ""
        var state: State = .waiting
        /// Whether it will be written to the library.
        var isKept = true

        enum State: Equatable {
            case waiting
            case writing
            case done
            /// What came back could not be used, and why.
            case refused(String)
        }
    }

    private(set) var lines: [Line] = []
    private(set) var isRunning = false
    private(set) var failure: String?

    private var work: Task<Void, Never>?

    var finished: Int { lines.count { $0.state == .done } }
    var usable: [Line] { lines.filter { $0.state == .done && $0.isKept && !$0.sentence.isEmpty } }

    // MARK: - Setting up

    func prepare(_ entries: [Entry]) {
        guard !isRunning else { return }
        lines = entries.map { Line(id: $0.id, term: $0.term, meaning: $0.meaning) }
        failure = nil
    }

    func setKept(_ kept: Bool, for id: UUID) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
        lines[index].isKept = kept
    }

    func edit(_ id: UUID, sentence: String? = nil, translation: String? = nil) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
        if let sentence { lines[index].sentence = sentence }
        if let translation { lines[index].translation = translation }
    }

    // MARK: - Running

    func start(for profile: LanguageProfile, companion: CompanionModel?) {
        guard !isRunning, !lines.isEmpty else { return }
        isRunning = true
        failure = nil

        work = Task { [weak self] in
            guard let self else { return }
            defer { self.isRunning = false }

            let session: LanguageModelSession
            do {
                session = try SentenceWriter.session(for: profile, companion: companion)
            } catch {
                self.failure = error.localizedDescription
                return
            }

            for index in lines.indices {
                if Task.isCancelled { return }
                guard lines[index].state == .waiting else { continue }
                lines[index].state = .writing

                do {
                    let made = try await SentenceWriter.make(
                        word: lines[index].term,
                        meaning: lines[index].meaning,
                        with: session
                    )
                    if Task.isCancelled { return }
                    lines[index].sentence = made.sentence
                    lines[index].translation = made.translation
                    lines[index].state = .done
                } catch is CancellationError {
                    lines[index].state = .waiting
                    return
                } catch {
                    lines[index].state = .refused(SentenceWriter.reason(for: error, word: lines[index].term))
                    // One bad answer is a bad answer; a model that has stopped
                    // responding is every answer after it, so it stops here.
                    if lines.count { if case .refused = $0.state { true } else { false } } > 3 {
                        self.failure = SentenceWriter.reason(for: error, word: lines[index].term)
                        return
                    }
                }
            }
        }
    }

    func stop() {
        work?.cancel()
        work = nil
        isRunning = false
        for index in lines.indices where lines[index].state == .writing {
            lines[index].state = .waiting
        }
    }

    /// Tries one word again, on its own.
    func retry(_ id: UUID, for profile: LanguageProfile, companion: CompanionModel?) {
        guard !isRunning, let index = lines.firstIndex(where: { $0.id == id }) else { return }
        lines[index].state = .waiting
        isRunning = true
        work = Task { [weak self] in
            guard let self else { return }
            defer { self.isRunning = false }
            guard let session = try? SentenceWriter.session(for: profile, companion: companion) else { return }
            lines[index].state = .writing
            do {
                let made = try await SentenceWriter.make(
                    word: lines[index].term, meaning: lines[index].meaning,
                    with: session
                )
                lines[index].sentence = made.sentence
                lines[index].translation = made.translation
                lines[index].state = .done
            } catch {
                lines[index].state = .refused(SentenceWriter.reason(for: error, word: lines[index].term))
            }
        }
    }
}
