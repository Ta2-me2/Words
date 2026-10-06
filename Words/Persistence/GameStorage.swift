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
}
