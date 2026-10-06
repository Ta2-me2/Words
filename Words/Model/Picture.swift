import Foundation

/// A photograph or an image kept with a word.
///
/// A different thing from an association, although the two share a place on
/// the word. A drawing is something the learner made to hold a word they keep
/// losing, and it is offered, not imposed. A picture is part of the word —
/// the apple next to "der Apfel" — and it is shown with the word every time.
/// A word has one or the other: two images fighting for one card would make
/// neither of them memorable.
nonisolated struct Picture: Codable, Hashable, Sendable {

    /// Where the file sits, relative to the library folder.
    var file: String

    var addedAt: Date

    init(file: String, addedAt: Date = .now) {
        self.file = file
        self.addedAt = addedAt
    }
}
