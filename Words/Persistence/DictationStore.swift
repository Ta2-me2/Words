import Foundation
import Observation

/// What the dictation game remembers, and the only thing that writes it.
///
/// One file per language, beside the library, like every other game's. The
/// schedule inside it is moved by the app's own FSRS — the same arithmetic the
/// cards get — but it is the game's schedule and nothing else: however well a
/// phrase is typed here, no card's due date moves. A game is practice.
@Observable
@MainActor
final class DictationStore {

    nonisolated static let gameName = "dictation"

    private(set) var progress = DictationProgress()
    private(set) var isLoaded = false
    private(set) var failure: String?

    private var profileID: UUID?
    private var pendingSave: Task<Void, Never>?
    private let scheduler: any ReviewScheduler
    private let root: URL

    init(scheduler: any ReviewScheduler = FSRSScheduler(), root: URL = LibraryLocation.folder) {
        self.scheduler = scheduler
        self.root = root
    }

    // MARK: - The file

    func load(for profileID: UUID) async {
        guard self.profileID != profileID else { return }
        await flush()
        self.profileID = profileID
        isLoaded = false
        failure = nil

        let url = Self.url(for: profileID, root: root)
        let loaded: Result<DictationProgress, Error> = await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url) else { return .success(DictationProgress()) }
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return .success(try decoder.decode(DictationProgress.self, from: data))
            } catch {
                return .failure(error)
            }
        }.value

        switch loaded {
        case .success(let progress):
            self.progress = progress
            isLoaded = true
        case .failure(let error):
            // Kept exactly as it is. Progress that cannot be read is not
            // progress to overwrite with an empty file.
            failure = error.localizedDescription
            isLoaded = false
        }
    }

    private func scheduleSave() {
        guard isLoaded, let profileID else { return }
        pendingSave?.cancel()
        let progress = progress
        let url = Self.url(for: profileID, root: root)
        pendingSave = Task { [root] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await Self.write(progress, to: url, root: root)
        }
    }

    /// Writes anything still waiting. Called when the game is left.
    func flush() async {
        guard isLoaded, let profileID else { return }
        pendingSave?.cancel()
        pendingSave = nil
        await Self.write(progress, to: Self.url(for: profileID, root: root), root: root)
    }

    private static func write(_ progress: DictationProgress, to url: URL, root: URL) async {
        await Task.detached(priority: .utility) {
            let folder = GameStorage.folder(game: gameName, root: root)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(progress) else { return }
            try? data.write(to: url, options: .atomic)
        }.value
    }

    private static func url(for profileID: UUID, root: URL) -> URL {
        GameStorage.progressURL(game: gameName, profileID: profileID, root: root)
    }

    // MARK: - Settings and sentences

    func update(_ change: (inout DictationSettings) -> Void) {
        change(&progress.settings)
        scheduleSave()
    }

    /// Adds sentences, leaving out the ones already there word for word.
    @discardableResult
    func add(_ sentences: [DictationSentence]) -> Int {
        var here = Set(progress.sentences.map { Self.key($0.text) })
        var added = 0
        for sentence in sentences {
            let text = sentence.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, here.insert(Self.key(text)).inserted else { continue }
            progress.sentences.append(DictationSentence(
                text: text,
                meaning: sentence.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
            added += 1
        }
        if added > 0 { scheduleSave() }
        return added
    }

    func remove(sentences ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        progress.sentences.removeAll { ids.contains($0.id) }
        for id in ids { progress.records[DictationItem.key(.written, id)] = nil }
        scheduleSave()
    }

    private static func key(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace }
    }

    // MARK: - Answering

    /// Writes down one answer: what it did to the phrase's schedule, and what
    /// it added to the day.
    func record(
        _ item: DictationItem,
        result: DictationResult,
        grade: ReviewGrade,
        seconds: Double,
        countsTowardsTheDay: Bool,
        retention: Double,
        at now: Date = .now
    ) {
        var record = progress.records[item.key] ?? DictationRecord()
        let wasNew = record.attempts == 0

        record.scheduling = scheduler.nextState(for: record.scheduling, grade: grade, at: now, retention: retention)
        record.attempts += 1
        if result.isPerfect { record.perfect += 1 }
        record.wordsWanted += result.words.count
        record.wordsRight += result.words.count { !$0.isFaulty }
        record.lastSeenAt = now
        progress.records[item.key] = record

        if countsTowardsTheDay {
            let key = DictationProgress.day(now)
            var day = progress.days[key] ?? DictationDay()
            day.exercises += 1
            if wasNew { day.newDone += 1 } else { day.reviewsDone += 1 }
            day.wordsWanted += result.words.count
            day.wordsRight += result.words.count { !$0.isFaulty }
            day.seconds += seconds
            progress.days[key] = day
        }

        scheduleSave()
    }

    /// Forgets a phrase's schedule, leaving the phrase itself alone.
    func forget(_ key: String) {
        progress.records[key] = nil
        scheduleSave()
    }
}
