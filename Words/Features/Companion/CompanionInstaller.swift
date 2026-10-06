import Foundation
import Observation
import WordsCompanion

/// Installing and removing the models that can answer about a card.
///
/// Lives as long as the app rather than as long as the Settings window: a
/// three-gigabyte download is not something closing a window should throw away.
@Observable
final class CompanionInstaller {

    enum State: Equatable {
        case notInstalled
        /// How far along, and how many bytes of how many.
        case downloading(fraction: Double, received: Int64, total: Int64)
        case installed(bytes: Int64)
        case failed(String)
    }

    private(set) var states: [String: State] = [:]

    @ObservationIgnored private var downloads: [String: Task<Void, Never>] = [:]

    init() {
        refresh()
    }

    func state(of model: CompanionModel) -> State {
        states[model.id] ?? .notInstalled
    }

    func isInstalled(_ model: CompanionModel) -> Bool {
        if case .installed = state(of: model) { return true }
        return false
    }

    /// Reads what is on disk again, leaving a download in progress alone.
    func refresh() {
        for model in CompanionModel.all where downloads[model.id] == nil {
            states[model.id] = CompanionStore.isInstalled(model)
                ? .installed(bytes: CompanionStore.sizeOnDisk(of: model))
                : .notInstalled
        }
    }

    /// - Parameter whenInstalled: run once the whole model is on disk, and not
    ///   when the download was stopped or failed. It is how installing a model
    ///   also chooses it: nobody downloads three gigabytes in order not to use
    ///   them.
    func install(_ model: CompanionModel, whenInstalled: (@MainActor () -> Void)? = nil) {
        guard downloads[model.id] == nil else { return }
        states[model.id] = .downloading(fraction: 0, received: 0, total: model.downloadBytes)

        downloads[model.id] = Task { [weak self] in
            do {
                try await CompanionStore.install(model) { progress in
                    self?.report(progress, for: model)
                }
                self?.finish(model, failure: nil, whenInstalled: whenInstalled)
            } catch is CancellationError {
                self?.finish(model, failure: nil)
            } catch {
                self?.finish(model, failure: Task.isCancelled ? nil : error.localizedDescription)
            }
        }
    }

    /// Stops a download. What had finished stays on disk, so installing again
    /// carries on from there.
    func cancel(_ model: CompanionModel) {
        downloads[model.id]?.cancel()
    }

    func remove(_ model: CompanionModel) async {
        do {
            try await CompanionStore.remove(model)
            refresh()
        } catch {
            states[model.id] = .failed(error.localizedDescription)
        }
    }

    private func report(_ progress: Progress, for model: CompanionModel) {
        guard downloads[model.id] != nil else { return }
        let fraction = min(max(progress.fractionCompleted, 0), 1)
        // The progress counts bytes when the server says how many there are,
        // and files when it does not; the model's own size is the fallback.
        let total = progress.totalUnitCount > 1_000_000 ? progress.totalUnitCount : model.downloadBytes
        states[model.id] = .downloading(fraction: fraction, received: Int64(Double(total) * fraction), total: total)
    }

    private func finish(
        _ model: CompanionModel,
        failure: String?,
        whenInstalled: (@MainActor () -> Void)? = nil
    ) {
        downloads[model.id] = nil
        if let failure {
            states[model.id] = .failed(failure)
        } else {
            refresh()
            if isInstalled(model) { whenInstalled?() }
        }
    }
}
