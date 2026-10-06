import Foundation

/// A picture the learner drew to hold a word down.
///
/// It is kept as a file beside the library rather than inside it, in Apple's own
/// drawing format — the same one PencilKit reads and writes — so that a drawing
/// is a document in its own right: it survives a library export, it can be read
/// by anything that understands the format, and nothing about it depends on this
/// app's JSON.
///
/// What is stored here is only what a list needs to know without opening the
/// file: whether there is anything in it, and when it was last touched.
nonisolated struct Association: Codable, Hashable, Sendable {

    /// Where the drawing sits, relative to the library folder.
    var file: String

    /// How many strokes it holds. A drawing with none is not an association,
    /// and this saves reading the file to find that out.
    var strokeCount: Int

    var updatedAt: Date

    init(file: String, strokeCount: Int, updatedAt: Date = .now) {
        self.file = file
        self.strokeCount = strokeCount
        self.updatedAt = updatedAt
    }

    var isEmpty: Bool { strokeCount == 0 }
}

/// When the app should offer to draw one, and — the harder half — when it
/// should stop.
///
/// A learner who is asked to invent a picture for every word will draw none.
/// The offer has to arrive for the words that are actually being lost, at the
/// moment the learner has just seen why, and then it has to get out of the way
/// on its own once the word starts sticking.
nonisolated enum AssociationPrompt {

    /// How far back the app looks.
    static let window = 5

    /// How many of those answers have to have gone badly.
    static let threshold = 3

    /// A word the learner keeps losing.
    ///
    /// Of the last five answers, three or more were Again or Hard. One rule
    /// covers both of the cases worth catching — three bad answers in a row,
    /// and a word forgotten again and again over a month — and, because the
    /// window moves, it lets go by itself: three good answers push the bad ones
    /// out of it and the offer disappears without anybody dismissing anything.
    ///
    /// Practice is not counted. Going over a word again changes no schedule and
    /// must not change the app's opinion of the word either.
    static func isStruggling(
        cardID: UUID,
        reviews: [ReviewRecord],
        window: Int = window,
        threshold: Int = threshold
    ) -> Bool {
        let recent = reviews
            .filter { $0.cardID == cardID && !$0.isPractice }
            .sorted { $0.reviewedAt > $1.reviewedAt }
            .prefix(window)

        guard recent.count >= threshold else { return false }
        return recent.count { $0.grade == .again || $0.grade == .hard } >= threshold
    }
}
