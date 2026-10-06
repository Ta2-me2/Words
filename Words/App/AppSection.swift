import Foundation

/// The places the window can be.
///
/// The sidebar is navigation and nothing else: which language is being studied
/// is a separate question, answered by the switcher above it.
nonisolated enum AppSection: String, CaseIterable, Identifiable, Sendable {

    /// What is waiting today, how the last months went, and what is proving
    /// hard. The screen the app opens on.
    case home

    /// Where words are added.
    case add

    /// Every word in the language, and the decks it is divided into.
    case library

    /// The long view: charts, forecast, accuracy.
    case statistics

    /// Games played with the language's own words. Practice by another name:
    /// nothing here touches a schedule.
    case games

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .add: "Add Words"
        case .library: "Library"
        case .statistics: "Statistics"
        case .games: "Games"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .add: "square.and.pencil"
        case .library: "books.vertical"
        case .statistics: "chart.bar"
        case .games: "gamecontroller"
        }
    }
}

/// A row in the sidebar. Decks are rows too — they live under the Library and
/// select it with a filter already applied.
nonisolated enum SidebarItem: Hashable, Sendable {
    case section(AppSection)
    case deck(UUID)
}
