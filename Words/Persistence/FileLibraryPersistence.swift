import Foundation

/// The library as one readable JSON file.
///
/// An actor, so disk work never runs on the main thread and two saves can never
/// interleave. Writes go to a temporary file and are swapped in atomically:
/// a power cut leaves either the old library or the new one, never half of
/// either. An unreadable file is set aside rather than overwritten — a
/// vocabulary built over months is not something to replace with an empty one
/// because a decoder was unhappy.
actor FileLibraryPersistence: LibraryPersistence {

    private let fileURL: URL
    private let folderURL: URL
    private let fileManager = FileManager.default

    private var mediaFolderURL: URL {
        folderURL.appending(path: LibraryLocation.mediaFolder, directoryHint: .isDirectory)
    }

    init(fileURL: URL = LibraryLocation.libraryURL) {
        self.fileURL = fileURL
        self.folderURL = fileURL.deletingLastPathComponent()
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        // Readable on purpose: a local-first app owes the owner a file they can
        // open, read and copy without the app that wrote it.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func load() async throws -> Library {
        try makeFolderIfNeeded()

        guard fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            let library = Library()
            try write(library)
            return library
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw LibraryError.unreadable(error.localizedDescription)
        }

        do {
            return try decoder.decode(Library.self, from: data)
        } catch {
            try? quarantine()
            throw LibraryError.unreadable(error.localizedDescription)
        }
    }

    func save(_ library: Library) async throws {
        try makeFolderIfNeeded()
        try write(library)
    }

    // MARK: - Files that belong to a word

    nonisolated func mediaURL(for relativePath: String) -> URL {
        fileURL.deletingLastPathComponent().appending(path: relativePath)
    }

    func importMedia(from source: URL, as name: String) async throws -> String {
        try makeMediaFolderIfNeeded()
        let relativePath = "\(LibraryLocation.mediaFolder)/\(name)"
        let destination = mediaURL(for: relativePath)

        do {
            // The learner's own file stays where it is; the library keeps a copy
            // of its own, because a library that breaks when a folder is tidied
            // up is not a library.
            if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            throw LibraryError.mediaFailed(error.localizedDescription)
        }

        return relativePath
    }

    func writeMedia(_ data: Data, as name: String) async throws -> String {
        try makeMediaFolderIfNeeded()
        let relativePath = "\(LibraryLocation.mediaFolder)/\(name)"
        do {
            try data.write(to: mediaURL(for: relativePath), options: .atomic)
        } catch {
            throw LibraryError.mediaFailed(error.localizedDescription)
        }
        return relativePath
    }

    func readMedia(at relativePath: String) async -> Data? {
        try? Data(contentsOf: mediaURL(for: relativePath))
    }

    func removeMedia(at relativePath: String) async {
        try? fileManager.removeItem(at: mediaURL(for: relativePath))
    }

    private func makeMediaFolderIfNeeded() throws {
        guard !fileManager.fileExists(atPath: mediaFolderURL.path(percentEncoded: false)) else { return }
        do {
            try fileManager.createDirectory(at: mediaFolderURL, withIntermediateDirectories: true)
        } catch {
            throw LibraryError.mediaFailed(error.localizedDescription)
        }
    }

    // MARK: - Disk

    private func makeFolderIfNeeded() throws {
        guard !fileManager.fileExists(atPath: folderURL.path(percentEncoded: false)) else { return }
        do {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        } catch {
            throw LibraryError.unwritable(error.localizedDescription)
        }
    }

    private func write(_ library: Library) throws {
        do {
            let data = try encoder.encode(library)
            let temporary = folderURL.appending(path: "\(UUID().uuidString).tmp")
            try data.write(to: temporary, options: .atomic)

            if fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) {
                _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: fileURL)
            }
        } catch {
            throw LibraryError.unwritable(error.localizedDescription)
        }
    }

    /// Moves an unreadable library aside under a dated name, so it can be
    /// looked at or repaired by hand instead of being lost.
    private func quarantine() throws {
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let aside = folderURL.appending(path: "Library (unreadable \(stamp)).json")
        try fileManager.moveItem(at: fileURL, to: aside)
    }
}
