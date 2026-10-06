import Foundation

/// How well a word came back.
///
/// Four answers, not a percentage: the point of the grade is that it can be
/// given in half a second without thinking about the grading itself.
nonisolated enum ReviewGrade: String, Codable, CaseIterable, Identifiable, Sendable {

    /// Did not come back at all.
    case again

    /// Came back, but slowly and with effort.
    case hard

    /// Came back.
    case good

    /// Came back instantly; the interval was too short.
    case easy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .again: "Again"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
        }
    }

    /// The digit that answers with this grade during a session.
    var shortcut: Character {
        switch self {
        case .again: "1"
        case .hard: "2"
        case .good: "3"
        case .easy: "4"
        }
    }

    /// A lapse is a word that was known and is not any more. It is the only
    /// grade that costs the card its interval.
    var isLapse: Bool { self == .again }
}
