import SwiftUI

/// Every spacing and radius in the app, in one place.
///
/// Screens never invent their own numbers: consistent geometry is what makes a
/// window read as one piece of software rather than as a stack of screens that
/// were each drawn on a different day.
enum Metrics {

    /// Horizontal padding from the window edge to page content.
    static let gutter: CGFloat = 20

    /// Vertical padding above page content.
    static let pageTop: CGFloat = 16

    /// Between major sections of a page.
    static let sectionSpacing: CGFloat = 24

    /// Between a section header and its content.
    static let headerSpacing: CGFloat = 12

    /// Between sibling rows and cards.
    static let rowSpacing: CGFloat = 10

    /// Inside a card.
    static let cardPadding: CGFloat = 16

    static let cardRadius: CGFloat = 10
    static let smallRadius: CGFloat = 6

    /// Reading measure. A meaning stretched across a wide window is unreadable,
    /// so text is held to a column and centred in whatever space it is given.
    static let readableWidth: CGFloat = 560

    /// The column a page of cards is laid out in, centred in a wide window.
    static let pageWidth: CGFloat = 720

    /// One day in the activity calendar, and the gap between two of them.
    static let activityCell: CGFloat = 12
    static let activityGap: CGFloat = 3

    static let sidebarMin: CGFloat = 220
    static let sidebarIdeal: CGFloat = 240
    static let sidebarMax: CGFloat = 300

    static let windowMinWidth: CGFloat = 860
    static let windowMinHeight: CGFloat = 560

    /// The study sheet. Fixed, because a card being learned should be the same
    /// size every time it appears — a review is a rhythm, not a layout.
    static let sessionWidth: CGFloat = 620
    /// Tall enough for a card that carries a photo, a meaning, an example and
    /// its translation all at once; the photo gives way before anything else.
    static let sessionHeight: CGFloat = 540

    static let sheetWidth: CGFloat = 440
}
