import CoreGraphics
import Foundation

/// Where every day of the activity calendar sits, and which day is under a
/// point.
///
/// Kept out of the view so it can be checked without a window. The calendar
/// once read the pointer two rows too low — the height of the month names above
/// the grid — and nothing caught it, because the arithmetic lived inside a view
/// body where no check could reach it.
nonisolated struct ActivityLayout {

    /// Columns of seven, `nil` where a week runs off either end of the range.
    let weeks: [[ActivityDay?]]

    /// The side of one square, in points.
    let cell: CGFloat

    let gap: CGFloat
    let months: [Month]

    nonisolated struct Month: Identifiable, Hashable {
        let id: Int
        let title: String
        let columns: Int
    }

    init(days: [ActivityDay], calendar: Calendar, available: CGFloat, gap: CGFloat) {
        self.gap = gap

        guard let first = days.first else {
            weeks = []
            cell = 8
            months = []
            return
        }

        // The first column has to start on the week's first day, or every
        // square would be in the wrong row.
        let weekday = calendar.component(.weekday, from: first.date)
        let leading = (weekday - calendar.firstWeekday + 7) % 7

        var slots: [ActivityDay?] = Array(repeating: nil, count: leading)
        slots.append(contentsOf: days.map { Optional($0) })
        while slots.count % 7 != 0 { slots.append(nil) }

        let weeks = stride(from: 0, to: slots.count, by: 7).map { Array(slots[$0..<$0 + 7]) }
        self.weeks = weeks

        // Sized to fill the width on offer, the way a chart would, within
        // limits that keep a square a square.
        if available > 0, !weeks.isEmpty {
            let columns = CGFloat(weeks.count)
            cell = min(max((available - (columns - 1) * gap) / columns, 7), 16)
        } else {
            cell = 8
        }

        var labels: [Month] = []
        for (index, week) in weeks.enumerated() {
            guard let day = week.compactMap({ $0 }).first else { continue }
            let title = day.date.formatted(.dateTime.month(.abbreviated))
            if let last = labels.last, last.title == title {
                labels[labels.count - 1] = Month(id: last.id, title: title, columns: last.columns + 1)
            } else {
                labels.append(Month(id: index, title: title, columns: 1))
            }
        }
        months = labels
    }

    private var step: CGFloat { cell + gap }

    var gridWidth: CGFloat { width(ofColumns: weeks.count) }
    var gridHeight: CGFloat { 7 * cell + 6 * gap }

    func width(ofColumns count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * cell + CGFloat(count - 1) * gap
    }

    func rect(column: Int, row: Int) -> CGRect {
        CGRect(x: CGFloat(column) * step, y: CGFloat(row) * step, width: cell, height: cell)
    }

    /// Which square a point in the grid's own coordinates is over, and the
    /// middle of that square's top edge — where a note about it belongs.
    func day(at point: CGPoint) -> (day: ActivityDay, anchor: CGPoint)? {
        guard cell > 0, point.x >= 0, point.y >= 0 else { return nil }
        let column = Int(point.x / step)
        let row = Int(point.y / step)
        guard weeks.indices.contains(column), (0..<7).contains(row) else { return nil }
        guard let day = weeks[column][row] else { return nil }

        // Inside the square itself, not in the gap beside it.
        let square = rect(column: column, row: row)
        guard square.contains(point) else { return nil }
        return (day, CGPoint(x: square.midX, y: square.minY))
    }

    /// The same, for a point measured from the top-left of the whole calendar
    /// — which is where the pointer is tracked — given where the grid sits in
    /// it. Everything above the grid has to be taken off first.
    func day(atCalendarPoint point: CGPoint, gridOrigin: CGPoint) -> (day: ActivityDay, anchor: CGPoint)? {
        day(at: CGPoint(x: point.x - gridOrigin.x, y: point.y - gridOrigin.y))
    }
}
