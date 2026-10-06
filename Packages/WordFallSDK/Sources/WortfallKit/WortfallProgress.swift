import SwiftUI
import WortfallCore

/// Own once per learner in the host app. No disk work is done inside the game frame callback.
@MainActor
public final class WortfallProgress: ObservableObject {
    @Published public private(set) var snapshot: ProgressSnapshot
    @Published public private(set) var saveError: String?
    private let storage: (any ProgressStorage)?
    private var saveTask: Task<Void, Never>?
    public init(snapshot: ProgressSnapshot = ProgressSnapshot()) {
        self.snapshot = snapshot; storage = nil
    }
    private init(snapshot: ProgressSnapshot, storage: any ProgressStorage) {
        self.snapshot = snapshot; self.storage = storage
    }
    /// Throws on corrupt or unsupported data; never silently overwrites it with empty progress.
    public static func open(storage: any ProgressStorage) async throws -> WortfallProgress {
        let snapshot = try await storage.load()
        guard snapshot.schemaVersion == 1 else { throw ProgressStorageError.unsupportedVersion(snapshot.schemaVersion) }
        return WortfallProgress(snapshot: snapshot, storage: storage)
    }
    public func record(_ answer: AnswerRecord) {
        if snapshot.record(answer) { scheduleSave() }
    }
    public func record(_ result: LevelResult) {
        if snapshot.record(result) { scheduleSave() }
    }
    private func scheduleSave() {
        guard let storage else { return }
        let value = snapshot, previous = saveTask
        saveTask = Task { [weak self] in
            await previous?.value
            do { try await storage.save(value); self?.saveError = nil }
            catch { self?.saveError = error.localizedDescription }
        }
    }
    /// Await before dismissing the experience or completing a host save/quit workflow.
    /// Retries the latest state and surfaces any failure to the caller.
    public func flush() async throws {
        await saveTask?.value
        guard let storage else { return }
        do { try await storage.save(snapshot); saveError = nil }
        catch { saveError = error.localizedDescription; throw error }
    }
}
