import SwiftUI

extension View {

    /// Lays this text out the way its language is read.
    ///
    /// Applied to the run of text in one language rather than to a whole
    /// screen, because a card holds two languages at once: an Arabic word with
    /// an English meaning under it reads right to left on one line and left to
    /// right on the next, and a card flipped whole would put the meaning's
    /// listen button on the wrong side to say so.
    ///
    /// What it moves is the *order* of things in a row — the article to the
    /// right of the noun, the listen button to the left of the sentence — and
    /// the base direction a line of mixed text is laid out against, which is
    /// what decides where a full stop at the end of an Arabic sentence lands.
    func reads(_ code: String) -> some View {
        environment(\.layoutDirection, LanguageCatalog.isRightToLeft(code) ? .rightToLeft : .leftToRight)
    }
}
