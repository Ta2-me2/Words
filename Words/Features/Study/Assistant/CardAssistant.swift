import AppKit
import FoundationModels
import NaturalLanguage
import Observation
import Security
import WordsCompanion

/// A conversation about one card, with the companion the learner chose.
///
/// Apple's own model by default, on the Mac. An app that has been granted
/// Private Cloud Compute — Apple's larger model, run on Apple's servers under
/// the same privacy promise — uses that instead. Or a model the learner
/// installed in Settings, such as Gemma, run by MLX on this Mac. All three are
/// a `LanguageModel` to a Foundation Models session, so the conversation, the
/// prompts and every rule in them are the same whichever answers.
///
/// One conversation belongs to one card. The card is given with the first
/// question, its picture with it when the model can see pictures, and what
/// changes on screen afterwards — the card being turned over — is said when
/// it happens.
@Observable
final class CardAssistant {

    nonisolated struct Message: Identifiable, Equatable {
        let id = UUID()
        let isLearner: Bool
        var text: String
        var isProblem = false
        /// Words of the learner's library a question names, found by the app
        /// and shown by it: the model on the Mac, even told, still answered
        /// "do I know Wasser?" with "no".
        var libraryWords: [WordFact] = []
    }

    /// Whether the chosen companion can answer on this Mac, and if not, why.
    enum Readiness: Equatable {
        case ready
        /// Apple Intelligence is off in System Settings.
        case turnedOff
        /// The model is still being downloaded or prepared.
        case preparing
        /// This Mac cannot run it.
        case unsupported
        /// A model chosen in Settings that is not on disk.
        case notInstalled(String)
    }

    let entryID: UUID
    private(set) var card: CardBrief
    private(set) var messages: [Message] = []
    private(set) var isResponding = false

    /// Whether the answers come from Private Cloud Compute.
    let usesCloud: Bool

    /// The model installed on this Mac that answers, or `nil` for Apple's.
    let companion: CompanionModel?

    @ObservationIgnored private let learner: LearnerBrief
    @ObservationIgnored private let picture: NSImage?
    @ObservationIgnored private let library: [WordFact]
    @ObservationIgnored private var session: LanguageModelSession?
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Whether the model has been shown the card, and which way up.
    @ObservationIgnored private var toldCard: CardBrief?
    /// The language the learner last wrote in, for a question too short to tell.
    @ObservationIgnored private var lastLanguage: String?

    /// The languages a question is most likely written in: the Mac's own, the
    /// one being learned, the one the meanings are in.
    @ObservationIgnored private let expectedLanguages: Set<String>

    init(
        entryID: UUID,
        learner: LearnerBrief,
        card: CardBrief,
        picture: NSImage?,
        library: [WordFact],
        languageCodes: [String] = [],
        companion: CompanionModel? = nil
    ) {
        self.entryID = entryID
        let preferred = Locale.preferredLanguages.compactMap { Locale(identifier: $0).language.languageCode?.identifier }
        self.expectedLanguages = Set(preferred + languageCodes + ["en"])
        self.learner = learner
        self.card = card
        self.picture = picture
        self.library = library
        self.companion = companion
        self.usesCloud = companion == nil && Self.canUseCloud
    }

    /// Whether this Mac can run a model installed in Settings: the bridge from
    /// MLX to a Foundation Models session needs macOS 27.
    static var canRunLocalModels: Bool {
        if #available(macOS 27, *) { return true }
        return false
    }

    static func readiness(for companion: CompanionModel?) -> Readiness {
        if let companion {
            guard canRunLocalModels else { return .unsupported }
            return CompanionStore.isInstalled(companion) ? .ready : .notInstalled(companion.name)
        }
        switch SystemLanguageModel.default.availability {
        case .available: return .ready
        case .unavailable(.appleIntelligenceNotEnabled): return .turnedOff
        case .unavailable(.modelNotReady): return .preparing
        case .unavailable: return .unsupported
        }
    }

    /// The name the panel gives the model: "Gemma 3 4B", "Apple Intelligence".
    var modelName: String {
        companion?.name ?? "Apple Intelligence"
    }

    /// Where the answers are worked out.
    var sourceLabel: String {
        if usesCloud { return "Apple Intelligence · Private Cloud Compute" }
        return "\(modelName) · on this Mac"
    }

    var suggestions: [String] {
        AssistantText.suggestions(for: card)
    }

    /// Keeps the conversation's picture of the card in step with the screen.
    func update(isRevealed: Bool) {
        card.isRevealed = isRevealed
    }

    /// Starts loading the model before the first question, so the first answer
    /// does not also pay for that.
    func prewarm() {
        guard Self.readiness(for: companion) == .ready else { return }
        currentSession().prewarm()
    }

    func ask(_ question: String) {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isResponding else { return }

        messages.append(Message(isLearner: true, text: text, libraryWords: AssistantText.mentionedWords(in: text, library: library)))
        messages.append(Message(isLearner: false, text: ""))
        isResponding = true

        task = Task { [weak self] in
            await self?.answer(text, retrying: true)
            self?.isResponding = false
        }
    }

    func stop() {
        task?.cancel()
    }

    /// Forgets the conversation; the card stays.
    func startOver() {
        task?.cancel()
        messages = []
        session = nil
        toldCard = nil
        isResponding = false
    }

    // MARK: - Answering

    private func answer(_ question: String, retrying: Bool) async {
        let session = currentSession()
        let prompt = composePrompt(for: question)
        let attachesPicture = toldCard == nil && picture != nil && canSeePictures

        var options = GenerationOptions()
        // Low, because an explanation of grammar is not the place for variety.
        options.temperature = 0.3
        options.maximumResponseTokens = 500

        do {
            let stream: LanguageModelSession.ResponseStream<String>
            if attachesPicture, #available(macOS 27, *), let picture {
                stream = session.streamResponse(options: options) {
                    prompt
                    Attachment(picture)
                }
            } else {
                stream = session.streamResponse(to: prompt, options: options)
            }
            toldCard = card

            for try await snapshot in stream {
                try Task.checkCancellation()
                updateLastAnswer(snapshot.content)
            }
            if lastAnswer.isEmpty {
                updateLastAnswer("No answer came back. Try asking another way.", isProblem: true)
            }
        } catch is CancellationError {
            if lastAnswer.isEmpty { messages.removeLast() }
        } catch {
            if retrying, Self.isContextFull(error) {
                // The conversation outgrew what the model can hold. The card and
                // the question are what matter; the rest is let go.
                self.session = nil
                toldCard = nil
                updateLastAnswer("")
                await answer(question, retrying: false)
                return
            }
            updateLastAnswer(explanation(of: error), isProblem: true)
        }
    }

    private func composePrompt(for question: String) -> String {
        var parts: [String] = []
        if let told = toldCard {
            if told.isRevealed != card.isRevealed { parts.append(AssistantText.revealState(card)) }
        } else {
            parts.append(AssistantText.card(card))
        }
        if let withheld = AssistantText.withheld(card) { parts.append(withheld) }
        if let facts = AssistantText.libraryFacts(AssistantText.mentionedWords(in: question, library: library)) {
            parts.append(facts)
        }
        parts.append(AssistantText.question(question))
        parts.append(AssistantText.replyLanguage(language(of: question)))
        return parts.joined(separator: "\n\n")
    }

    /// The language a question is written in, by name. A question too short to
    /// tell — "baden?" — keeps the language of the last one, and the first
    /// one falls back to the language the Mac is set to.
    ///
    /// A short question leans towards the languages the learner uses: "Знаю
    /// ли я слово Wasser?" reads as Ukrainian to the recogniser, with Russian
    /// its second guess, and the answer came back in Ukrainian. A second guess
    /// that is one of the learner's languages wins over a first that is not;
    /// a question really written in another language keeps it.
    private func language(of question: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(question)
        let guesses = recognizer.languageHypotheses(withMaximum: 3).sorted { $0.value > $1.value }
        let expected = guesses.first { expectedLanguages.contains($0.key.rawValue) && $0.value >= 0.02 }
        if let (language, confidence) = expected ?? guesses.first,
           confidence >= 0.02,
           question.split(whereSeparator: \.isWhitespace).count >= 2 || lastLanguage == nil {
            let name = LanguageCatalog.englishName(for: language.rawValue)
            lastLanguage = name
            return name
        }
        if let lastLanguage { return lastLanguage }
        let system = Locale.preferredLanguages.first.flatMap { Locale(identifier: $0).language.languageCode?.identifier } ?? "en"
        return LanguageCatalog.englishName(for: system)
    }

    private var lastAnswer: String {
        messages.last?.text ?? ""
    }

    private func updateLastAnswer(_ text: String, isProblem: Bool = false) {
        guard let last = messages.indices.last, !messages[last].isLearner else { return }
        messages[last].text = text
        messages[last].isProblem = isProblem
    }

    private func currentSession() -> LanguageModelSession {
        if let session { return session }
        let made: LanguageModelSession
        if let companion, #available(macOS 27, *) {
            // The same rules as for Apple's model on the Mac, and no library
            // search: a small model's tool calls are the least reliable thing
            // about it, and the app states the library's facts itself.
            made = LanguageModelSession(
                model: CompanionStore.languageModel(for: companion),
                instructions: AssistantText.instructions(for: learner, canSearchLibrary: false)
            )
        } else if usesCloud, #available(macOS 27, *) {
            // Only the larger model is trusted with the library: the one on
            // the Mac did not reliably call the search, and answered without it.
            made = LanguageModelSession(
                model: PrivateCloudComputeLanguageModel(),
                tools: [LibrarySearchTool(words: library, current: card.word)],
                instructions: AssistantText.instructions(for: learner, canSearchLibrary: true)
            )
        } else {
            made = LanguageModelSession(instructions: AssistantText.instructions(for: learner, canSearchLibrary: false))
        }
        session = made
        return made
    }

    private var canSeePictures: Bool {
        guard #available(macOS 27, *) else { return false }
        if let companion { return companion.seesPictures }
        return usesCloud
            ? PrivateCloudComputeLanguageModel().capabilities.contains(.vision)
            : SystemLanguageModel.default.capabilities.contains(.vision)
    }

    // MARK: - The model to use

    /// Private Cloud Compute is a managed entitlement Apple grants to an app.
    /// Without it every request fails, so it is only tried by an app that has
    /// it — and then only when the service says it is ready.
    private static var canUseCloud: Bool {
        guard #available(macOS 27, *), hasCloudEntitlement else { return false }
        return PrivateCloudComputeLanguageModel().isAvailable
    }

    private static var hasCloudEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.private-cloud-compute" as CFString, nil)
        else { return false }
        return (value as? Bool) == true
    }

    // MARK: - When it goes wrong

    private static func isContextFull(_ error: any Error) -> Bool {
        guard #available(macOS 27, *), let error = error as? LanguageModelError else { return false }
        if case .contextSizeExceeded = error { return true }
        return false
    }

    /// What went wrong, said the way the learner can do something about it.
    private func explanation(of error: any Error) -> String {
        let learning = learner.learning
        if #available(macOS 27, *), let error = error as? LanguageModelError {
            switch error {
            case .unsupportedLanguageOrLocale:
                return "\(modelName) doesn’t support the language of this question yet. Try asking in English or \(learning)."
            case .guardrailViolation, .refusal:
                return "\(modelName) can’t help with that one. Try asking about the card another way."
            case .rateLimited:
                return "Too many questions at once. Wait a moment and ask again."
            case .timeout:
                return "The answer took too long. Try again."
            case .contextSizeExceeded:
                return "This conversation got too long. Start over to keep asking."
            default:
                return error.localizedDescription
            }
        }
        return error.localizedDescription
    }
}

/// Lets the assistant look through the learner's own words.
nonisolated struct LibrarySearchTool: Tool {
    let name = AssistantText.searchToolName
    let description = "Looks up words the learner already has in their library. Call it whenever the learner asks what words they have or know. Pass one short English keyword for the topic or the word, such as water, food or house."

    let words: [WordFact]
    let current: String

    @Generable
    struct Arguments {
        @Guide(description: "One short English keyword, such as water")
        var keyword: String
    }

    @concurrent
    func call(arguments: Arguments) async throws -> String {
        let embedding = NLEmbedding.wordEmbedding(for: .english)
        return AssistantText.findWords(arguments.keyword, in: words, excluding: current) { word, keyword in
            // Close enough that "water" finds "sea" and not "table".
            guard let embedding else { return false }
            return embedding.distance(between: word, and: keyword) < 0.9
        }
    }
}
