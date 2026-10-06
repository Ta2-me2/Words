import Foundation

/// The games the Games section offers.
///
/// One today. The section is laid out as a shelf rather than as one big button
/// because there will be more, and a shelf with one thing on it still reads as
/// a shelf.
enum GameKind: String, CaseIterable, Identifiable {
    case wordFall

    var id: String { rawValue }

    /// The game's own name, as it appears on its title screen.
    var title: String {
        switch self {
        case .wordFall: "WordFall"
        }
    }

    var summary: String {
        switch self {
        case .wordFall: "A downhill race. Steer through the gate that holds the right answer."
        }
    }

    /// The image in the asset catalog: the game's own icon.
    var icon: String {
        switch self {
        case .wordFall: "WordFallIcon"
        }
    }
}
