import Foundation
import WortfallCore
import WortfallKit

/// Everything the app keeps for WordFall: one progress model per language, and
/// the deck each language last played.
///
/// A single owner rather than one per screen, for two reasons the game's own
/// documentation insists on. A progress model must be loaded once and kept, or
/// two copies would race each other to the same file. And before a language's
/// file is deleted, its queued writes have to be allowed to land — otherwise a
/// save that was already on its way would put the file straight back.
@MainActor
final class WortfallHost {

    static let shared = WortfallHost()

    /// The folder under `Games/`.
    ///
    /// Still the game's old name. The rename to WordFall was a change of
    /// display name only — the developer kept the modules and the progress
    /// format as they were — and this folder already holds learners' progress.
    /// Renaming it would mean moving that progress for the sake of a name
    /// nobody sees.
    static let storageName = "Wortfall"

    private var models: [UUID: WortfallProgress] = [:]

    /// Languages whose progress has been thrown away. Nothing is written for
    /// them again, whatever a screen that is still closing asks for.
    private var discarded: Set<UUID> = []

    /// The collection each language was last playing, so reopening the game
    /// opens it where the learner left it.
    var selectedDeck: [UUID: String] = [:]

    private init() {}

    /// The language's progress, read from disk the first time it is asked for.
    ///
    /// A file the game cannot read is reported, not replaced: the game refuses
    /// to overwrite progress it does not understand, and so does the app.
    func progress(for profileID: UUID) async throws -> WortfallProgress {
        if let model = models[profileID] { return model }

        let storage = JSONProgressStorage(url: GameStorage.progressURL(game: Self.storageName, profileID: profileID))
        let model = try await WortfallProgress.open(storage: storage)

        // Another screen may have asked while this one was reading.
        if let existing = models[profileID] { return existing }
        models[profileID] = model
        discarded.remove(profileID)
        return model
    }

    /// Writes whatever the game has not written yet. Failures are left on the
    /// model, where the game's own menu shows them and offers a retry.
    func flush(_ profileID: UUID) async {
        guard !discarded.contains(profileID), let model = models[profileID] else { return }
        try? await model.flush()
    }

    /// Every language at once: the app is quitting.
    func flushAll() async {
        for (id, model) in models where !discarded.contains(id) {
            try? await model.flush()
        }
    }

    /// Throws a language's progress away, because the language is gone.
    func discard(_ profileID: UUID) async {
        discarded.insert(profileID)
        selectedDeck[profileID] = nil

        // Let anything already queued land first; then the file can go without
        // a late write bringing it back.
        if let model = models.removeValue(forKey: profileID) {
            try? await model.flush()
        }
        GameStorage.removeProgress(game: Self.storageName, profileID: profileID)
    }

    /// Removes files left behind by languages that no longer exist.
    func pruneOrphans(keeping profiles: Set<UUID>) {
        for url in GameStorage.orphans(game: Self.storageName, keeping: profiles) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
