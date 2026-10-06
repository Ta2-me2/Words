import Foundation
import FoundationModels
import HuggingFace
import MLXFoundationModels
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import MLXVLM
import Tokenizers

/// A model the learner can install on this Mac to talk to about their cards.
public struct CompanionModel: Identifiable, Hashable, Sendable {
    /// Stable, for remembering which one was chosen.
    public let id: String
    public let name: String
    /// Who made it, said beside the name.
    public let maker: String
    /// The Hugging Face repository the weights come from.
    public let repository: String
    /// About how much is downloaded, for saying so before it starts.
    public let downloadBytes: Int64
    public let licenseName: String
    public let licenseURL: URL
    /// Whether it can look at a card's picture.
    public let seesPictures: Bool

    /// Google's Gemma 3 with four billion parameters, in the version Google
    /// trained to keep its quality at four bits — the size that runs well on
    /// an Apple silicon Mac with room to spare. It speaks some 140 languages,
    /// Russian among them, and reads pictures.
    public static let gemma3 = CompanionModel(
        id: "gemma-3-4b",
        name: "Gemma 3 4B",
        maker: "Google",
        repository: "mlx-community/gemma-3-4b-it-qat-4bit",
        downloadBytes: 3_030_000_000,
        licenseName: "Gemma Terms of Use",
        licenseURL: URL(string: "https://ai.google.dev/gemma/terms")!,
        seesPictures: true
    )

    public static let all: [CompanionModel] = [.gemma3]

    public static func named(_ id: String) -> CompanionModel? {
        all.first { $0.id == id }
    }
}

public enum CompanionError: LocalizedError {
    case notInstalled(String)
    case badRepository(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled(let name): "\(name) isn’t installed. Install it in Settings."
        case .badRepository(let id): "“\(id)” is not a model this app knows how to fetch."
        }
    }
}

/// Where installed models live, and installing and removing them.
///
/// In the app's own folder rather than the shared Hugging Face cache: a model
/// is several gigabytes the learner chose to add, and removing it from
/// Settings has to leave nothing of it behind.
public enum CompanionStore {

    /// `~/Library/Application Support/Words/Models`.
    public static var directory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support")
        return support.appending(path: "Words/Models", directoryHint: .isDirectory)
    }

    /// What a model is made of: its weights, its configuration and tokenizer,
    /// and its chat template. Nothing else in the repository is needed.
    static let files = ["*.safetensors", "*.json", "*.jinja"]

    static var cache: HubCache {
        HubCache(cacheDirectory: directory)
    }

    /// The downloaded copy of a model, if a whole one is on disk.
    public static func location(of model: CompanionModel) -> URL? {
        guard let repo = Repo.ID(rawValue: model.repository),
              let commit = cache.resolveRevision(repo: repo, kind: .model, ref: "main"),
              let snapshot = try? cache.snapshotPath(repo: repo, kind: .model, commitHash: commit)
        else { return nil }

        let manager = FileManager.default
        guard manager.fileExists(atPath: snapshot.appending(path: "config.json").path),
              let names = try? manager.contentsOfDirectory(atPath: snapshot.path),
              names.contains(where: { $0.hasSuffix(".safetensors") })
        else { return nil }
        return snapshot
    }

    public static func isInstalled(_ model: CompanionModel) -> Bool {
        location(of: model) != nil
    }

    /// Bytes the model takes on disk, counting each stored file once.
    public static func sizeOnDisk(of model: CompanionModel) -> Int64 {
        guard let repo = Repo.ID(rawValue: model.repository) else { return 0 }
        let root = cache.repoDirectory(repo: repo, kind: .model).appending(path: "blobs")
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in files {
            total += Int64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return total
    }

    /// Downloads a model. A download that was interrupted picks up the files
    /// it had already finished.
    public static func install(
        _ model: CompanionModel,
        progress: @escaping @MainActor @Sendable (Progress) -> Void
    ) async throws {
        guard let repo = Repo.ID(rawValue: model.repository) else {
            throw CompanionError.badRepository(model.repository)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let client = HubClient(host: HubClient.defaultHost, tokenProvider: .none, cache: cache)
        _ = try await client.downloadSnapshot(
            of: repo,
            revision: "main",
            matching: files,
            progressHandler: progress
        )
    }

    /// Lets go of every model in memory — gigabytes of it — until one is asked
    /// for again, which reads it back from disk in a few seconds.
    public static func unload() async {
        if #available(macOS 27, *) {
            await MLXLanguageModel.evictAll()
        }
    }

    /// Deletes a model and lets go of it in memory.
    public static func remove(_ model: CompanionModel) async throws {
        if #available(macOS 27, *) {
            await MLXLanguageModel.evictAll()
        }
        guard let repo = Repo.ID(rawValue: model.repository) else { return }
        let folder = cache.repoDirectory(repo: repo, kind: .model)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }

    /// The model, ready to hand to a Foundation Models session. It is read
    /// from disk only — asking a question never downloads anything.
    @available(macOS 27, *)
    public static func languageModel(for model: CompanionModel) -> MLXLanguageModel {
        let registered = registeredConfiguration(for: model)
        return MLXLanguageModel(
            configuration: registered,
            capabilities: model.seesPictures ? [.vision] : [],
            weightsLocation: { _ in location(of: model) ?? directory },
            load: { _, _ in
                guard let folder = location(of: model) else {
                    throw CompanionError.notInstalled(model.name)
                }
                // From the folder, but with everything the registry knows
                // about the model — above all Gemma's end-of-turn token,
                // without which an answer does not stop.
                let local = ModelConfiguration(
                    directory: folder,
                    defaultPrompt: registered.defaultPrompt,
                    extraEOSTokens: registered.extraEOSTokens
                )
                return try await loadModelContainer(
                    from: #hubDownloader(HubClient(host: HubClient.defaultHost, tokenProvider: .none, cache: cache)),
                    using: #huggingFaceTokenizerLoader(),
                    configuration: local
                )
            }
        )
    }

    private static func registeredConfiguration(for model: CompanionModel) -> ModelConfiguration {
        switch model.id {
        case CompanionModel.gemma3.id: VLMRegistry.gemma3_4B_qat_4bit
        default: ModelConfiguration(id: model.repository)
        }
    }
}
