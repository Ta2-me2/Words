import Foundation

/// Where games keep what they remember about a learner.
///
/// One file per game per language, named after the language, inside the
/// library's own folder — so the vocabulary and everything that grew out of it
/// travel, and disappear, together. A game writes its own format; the app only
/// decides where the file lives and when it goes.
nonisolated enum GameStorage {

    static let folderName = "Games"

    /// `…/Words/Games/<game>/`
    static func folder(game: String, root: URL = LibraryLocation.folder) -> URL {
        root.appending(path: folderName, directoryHint: .isDirectory)
            .appending(path: game, directoryHint: .isDirectory)
    }

    /// `…/Words/Games/<game>/<language id>.json`
    static func progressURL(game: String, profileID: UUID, root: URL = LibraryLocation.folder) -> URL {
        folder(game: game, root: root).appending(path: "\(profileID.uuidString).json")
    }

    /// Files that belong to languages which no longer exist.
    ///
    /// A safety net, not the mechanism: deleting a language removes its file
    /// directly. This catches the rest — a write that landed a moment after the
    /// deletion, or a language deleted by a version of the app that knew
    /// nothing about games. Only files named after a language are ever
    /// considered; anything else in the folder is left alone.
    static func orphans(game: String, keeping profiles: Set<UUID>, root: URL = LibraryLocation.folder) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder(game: game, root: root),
            includingPropertiesForKeys: nil
        )) ?? []

        return files.filter { url in
            guard url.pathExtension == "json",
                  let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent)
            else { return false }
            return !profiles.contains(id)
        }
    }

    static func removeProgress(game: String, profileID: UUID, root: URL = LibraryLocation.folder) {
        try? FileManager.default.removeItem(at: progressURL(game: game, profileID: profileID, root: root))
    }

    /// Every game that has ever written anything, by the name of its folder.
    ///
    /// Read from the disk rather than from a list in the code, so that the
    /// clearing up below covers a game added later without anybody having to
    /// remember to add it here too.
    static func games(root: URL = LibraryLocation.folder) -> [String] {
        let folder = root.appending(path: folderName, directoryHint: .isDirectory)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []
        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
    }

    /// Throws away what every game remembered about one language, because the
    /// language is gone.
    static func removeProgress(forProfile profileID: UUID, root: URL = LibraryLocation.folder) {
        for game in games(root: root) {
            removeProgress(game: game, profileID: profileID, root: root)
        }
    }

    /// Clears up after every game at once: files belonging to languages that
    /// are no longer there.
    static func pruneOrphans(keeping profiles: Set<UUID>, root: URL = LibraryLocation.folder) {
        for game in games(root: root) {
            for url in orphans(game: game, keeping: profiles, root: root) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
