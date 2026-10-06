import Foundation

/// The seam between the app and its storage.
///
/// Nothing above this protocol knows the library is a JSON file. Moving it to a
/// database, or to a folder of files, or to something that syncs, is one more
/// conformance and no changes to any screen.
nonisolated protocol LibraryPersistence: Sendable {

    /// Creates the library if it is not there yet, then reads it.
    func load() async throws -> Library

    /// Writes it whole, and atomically.
    func save(_ library: Library) async throws

    // MARK: - Files that belong to a word

    /// Where a stored file is, for handing to a player or a renderer.
    ///
    /// Not async: a view that is about to play a sound should not have to wait
    /// on an actor to find out where it is.
    nonisolated func mediaURL(for relativePath: String) -> URL

    /// Copies a file into the library and returns the path it was given.
    /// The original is never moved or altered.
    func importMedia(from source: URL, as name: String) async throws -> String

    /// Writes bytes into the library and returns the path they were given.
    func writeMedia(_ data: Data, as name: String) async throws -> String

    func readMedia(at relativePath: String) async -> Data?

    func removeMedia(at relativePath: String) async
}

nonisolated enum LibraryError: LocalizedError {
    case unreadable(String)
    case unwritable(String)
    case mediaFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let detail): "The library file could not be read. \(detail)"
        case .unwritable(let detail): "The library could not be saved. \(detail)"
        case .mediaFailed(let detail): "The file could not be added to the library. \(detail)"
        }
    }
}
