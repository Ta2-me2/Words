import SwiftUI

/// Months of study as one small grid: a column per week, a square per day,
/// brighter where the day was busier.
///
/// The shading is relative to the learner's own busiest day, so the calendar
/// says "for you, this was a lot" rather than comparing anyone to a target they
/// never set.
///
/// Drawn rather than built. Fifty-three weeks is three hundred and seventy-one
/// squares; three hundred and seventy-one views, each measured, laid out and
/// given a tooltip whose text was formatted whether anyone read it or not, cost
/// a third of a second every time Home opened. One `Canvas` draws the lot, and
/// the pointer is answered by working out which square it is over rather than
/// by asking every square whether it was hit.
struct ActivityCalendar: View {
    let days: [ActivityDay]
    var calendar: Calendar = .current

    /// The squares are sized to fill the width they are given, the way a chart
    /// would, rather than leaving half the card empty.
    @State private var available: CGFloat = 0

    @State private var hovered: HoverPoint?

    /// Where the grid sits inside the calendar. The pointer is tracked on the
    /// whole calendar, so its position has to be moved into the grid's frame
    /// before it can name a square — past the month names and the gap above.
    @State private var gridOrigin: CGPoint = .zero

    var body: some View {
        let layout = ActivityLayout(days: days, calendar: calendar, available: available, gap: Metrics.activityGap)

        VStack(alignment: .leading, spacing: 6) {
            // A zero-height ruler that takes the width on offer. The grid is
            // sized from this rather than from itself.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 0)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { available = $0 }

            if !layout.months.isEmpty {
                HStack(spacing: Metrics.activityGap) {
                    ForEach(layout.months) { month in
                        // A month that only just started has no room for its
                        // name; leaving it out beats stacking three letters
                        // vertically.
                        Text(month.columns >= 3 ? month.title : "")
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(Palette.secondaryText)
                            .frame(width: layout.width(ofColumns: month.columns), alignment: .leading)
                    }
                }
            }

            grid(layout)
                .onGeometryChange(for: CGPoint.self) {
                    $0.frame(in: .named(Self.calendarSpace)).origin
                } action: {
                    gridOrigin = $0
                }
                .hoverNote(hovered)

            HStack(spacing: 5) {
                Spacer(minLength: 0)
                Text("Less")
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryText)
                ForEach(0...4, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(Self.fill(for: level))
                        .frame(width: 10, height: 10)
                }
                Text("More")
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
        // The pointer is tracked on the whole calendar rather than on the
        // drawing inside it: a `Canvas` answers no hit test of its own.
        //
        // The position is read in the calendar's own space and then moved into
        // the grid's by subtracting where the grid sits. It used to ask for the
        // grid's named space directly — but a named space is only found among a
        // view's ancestors, the grid is a child, and SwiftUI quietly answered in
        // the calendar's coordinates instead. Every square was read two rows
        // too low: the height of the month names.
        .coordinateSpace(.named(Self.calendarSpace))
        .contentShape(.rect)
        .onContinuousHover(coordinateSpace: .named(Self.calendarSpace)) { phase in
            switch phase {
            case .active(let point):
                // Only a day with something on it has anything to say.
                guard let found = layout.day(atCalendarPoint: point, gridOrigin: gridOrigin), found.day.count > 0 else {
                    hovered = nil
                    return
                }
                hovered = HoverPoint(Self.description(of: found.day), at: found.anchor)
            case .ended:
                hovered = nil
            }
        }
    }

    nonisolated private static let calendarSpace = "activity-calendar"

    private func grid(_ layout: ActivityLayout) -> some View {
        Canvas { context, _ in
            for (column, week) in layout.weeks.enumerated() {
                for (row, day) in week.enumerated() {
                    // A day before the calendar begins is space, not an empty
                    // square.
                    guard let day else { continue }
                    context.fill(
                        Path(roundedRect: layout.rect(column: column, row: row), cornerRadius: 2.5, style: .continuous),
                        with: .color(Self.fill(for: day.level))
                    )
                }
            }
        }
        .frame(width: layout.gridWidth, height: layout.gridHeight)
    }

    /// The accent colour at four strengths. A day with nothing on it is a well,
    /// not a colour, so an empty stretch reads as quiet rather than as red.
    private static func fill(for level: Int) -> Color {
        switch level {
        case 1: Palette.selection.opacity(0.28)
        case 2: Palette.selection.opacity(0.5)
        case 3: Palette.selection.opacity(0.74)
        case 4: Palette.selection
        default: Palette.subtleFill
        }
    }

    private static func description(of day: ActivityDay) -> String {
        let date = day.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return "\(day.count) \(day.count == 1 ? "review" : "reviews") · \(date)"
    }
}
