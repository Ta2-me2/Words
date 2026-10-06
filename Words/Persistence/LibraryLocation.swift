import Foundation

/// Where the library lives on disk.
///
/// One folder in Application Support, which is where a Mac application keeps
/// data the user does not open by hand. No document to lose track of, no
/// sandbox permission to ask for, and nothing to configure.
nonisolated enum LibraryLocation {

    static let folderName = "Words"
    static let libraryFilename = "Library.json"

    /// Recordings and drawings: everything that belongs to a word but is too
    /// big to live inside a document meant to stay readable.
    static let mediaFolder = "Media"

    /// `~/Library/Application Support/Words`
    static var folder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support", directoryHint: .isDirectory)
        return support.appending(path: folderName, directoryHint: .isDirectory)
    }

    static var libraryURL: URL {
        folder.appending(path: libraryFilename)
    }
}
