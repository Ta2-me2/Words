import Foundation

/// A recording of a word, kept as a file beside the library.
///
/// Only a real recording is a clip. A word spoken by the system voice has no
/// clip and never gets one: the voice is chosen per language and can be changed
/// at any time, and a library full of files made by last month's voice would be
/// a library that quietly went out of date.
nonisolated struct AudioClip: Codable, Hashable, Sendable {

    nonisolated enum Source: String, Codable, Sendable {
        /// Spoken into the microphone by the learner.
        case recorded
        /// A file the learner already had.
        case imported

        var title: String {
            switch self {
            case .recorded: "Recorded"
            case .imported: "Imported"
            }
        }
    }

    var id: UUID
    /// Where the file sits, relative to the library folder.
    var file: String
    var source: Source
    var addedAt: Date
    var seconds: Double?

    init(id: UUID = UUID(), file: String, source: Source, addedAt: Date = .now, seconds: Double? = nil) {
        self.id = id
        self.file = file
        self.source = source
        self.addedAt = addedAt
        self.seconds = seconds
    }
}

/// How a word can be heard.
nonisolated enum AudioAvailability: Hashable, Sendable {
    /// A file of its own.
    case clip(AudioClip.Source)
    /// No file, but the language has a voice that can read it.
    case voice
    /// Nothing: no file, and no voice installed for this language.
    case none

    var hasClip: Bool {
        if case .clip = self { return true }
        return false
    }
}
