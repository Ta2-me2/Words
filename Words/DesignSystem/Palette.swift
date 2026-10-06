import SwiftUI

/// The complete colour vocabulary.
///
/// Nothing here is picked by eye. Every value comes from the system, which is
/// what keeps the app correct in both themes, at any accent colour, and in the
/// next version of macOS.
enum Palette {

    // MARK: - Meaning

    /// Selection and interactive emphasis. Follows the user's accent colour.
    static let selection = Color.accentColor

    /// A word that was known and has been forgotten.
    static let critical = Color.red

    /// Something that wants attention but is not wrong.
    static let warning = Color.orange

    /// A word that came back easily; a finished session.
    static let complete = Color.green

    /// A day that kept the streak going.
    static let streak = Color.orange

    /// A day the streak was frozen.
    static let frozen = Color.cyan

    // MARK: - Surfaces

    /// Card and row surface, sitting on the window background.
    static let card = Color(nsColor: .controlBackgroundColor)

    /// The page itself.
    static let page = Color(nsColor: .windowBackgroundColor)

    /// Hairline rules between rows and around cards.
    static let separator = Color(nsColor: .separatorColor)

    /// Fill for chips and wells.
    static let subtleFill = Color(nsColor: .quaternaryLabelColor).opacity(0.5)

    // MARK: - Text

    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
}

extension LearningStage {

    /// Stages are not colour-coded. Four coloured labels down a list of words
    /// stop being information and become decoration; the word is what the eye
    /// should land on.
    nonisolated var symbol: String {
        switch self {
        case .new: "circle.dotted"
        case .learning: "circle.lefthalf.filled"
        case .relearning: "arrow.counterclockwise.circle"
        case .review: "checkmark.circle"
        }
    }
}
