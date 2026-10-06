import CoreGraphics
import Foundation

/// Which square of the activity calendar the pointer is over.
///
/// This used to be answered two rows too low: the pointer was measured from the
/// top of the whole calendar and read as though it were measured from the top
/// of the grid, so the height of the month names above it was never taken off.
func checkActivityLayout() {
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.firstWeekday = 2   // Monday, as a Russian or German Mac has it
    gregorian.timeZone = .current

    let today = gregorian.date(from: DateComponents(year: 2026, month: 9, day: 12))!   // a Saturday
    let start = gregorian.date(byAdding: .day, value: -370, to: today)!
    let days: [ActivityDay] = (0...370).map { offset in
        let date = gregorian.date(byAdding: .day, value: offset, to: start)!
        let count: Int
        switch gregorian.component(.day, from: date) {
        case 12 where gregorian.component(.month, from: date) == 9: count = 40
        case 7 where gregorian.component(.month, from: date) == 9: count = 1
        default: count = 0
        }
        return ActivityDay(date: date, count: count, level: count == 0 ? 0 : (count > 10 ? 4 : 1))
    }

    let layout = ActivityLayout(days: days, calendar: gregorian, available: 700, gap: 3)

    func column(of date: Date) -> (Int, Int)? {
        for (c, week) in layout.weeks.enumerated() {
            for (r, day) in week.enumerated() where day.map({ gregorian.isDate($0.date, inSameDayAs: date) }) == true {
                return (c, r)
            }
        }
        return nil
    }

    section("The squares")

    let saturday = column(of: today)
    let monday = column(of: gregorian.date(byAdding: .day, value: -5, to: today)!)
    check("today, a Saturday, is in the last column, sixth row",
          saturday?.0 == layout.weeks.count - 1 && saturday?.1 == 5)
    check("the Monday before it heads the same column", monday?.0 == saturday?.0 && monday?.1 == 0)

    var everySquareNamesItself = true
    for (c, week) in layout.weeks.enumerated() {
        for (r, day) in week.enumerated() {
            guard let day else { continue }
            let centre = CGPoint(x: layout.rect(column: c, row: r).midX, y: layout.rect(column: c, row: r).midY)
            if layout.day(at: centre)?.day != day { everySquareNamesItself = false }
        }
    }
    check("the middle of every square names that square's day", everySquareNamesItself)

    let gap = CGPoint(x: layout.rect(column: 10, row: 3).maxX + 1, y: layout.rect(column: 10, row: 3).midY)
    check("the gap between two squares names neither", layout.day(at: gap) == nil)
    check("nor does a point above the grid", layout.day(at: CGPoint(x: 5, y: -4)) == nil)

    let square = layout.rect(column: saturday!.0, row: saturday!.1)
    check("a note about a square sits on the middle of its top edge",
          layout.day(at: CGPoint(x: square.midX, y: square.midY))?.anchor == CGPoint(x: square.midX, y: square.minY))

    section("The pointer, measured from the top of the whole calendar")

    // The month names and the space around them: about two rows of squares.
    let gridOrigin = CGPoint(x: 0, y: 25)
    let pointer = CGPoint(x: square.midX, y: gridOrigin.y + square.midY)

    check("the square under the pointer is the square that answers",
          layout.day(atCalendarPoint: pointer, gridOrigin: gridOrigin)?.day.count == 40)

    check("reading that point as if it were the grid's lands two rows lower, on nothing — the bug as reported",
          layout.day(at: pointer) == nil)
    let twoRowsUp = CGPoint(x: pointer.x, y: pointer.y - gridOrigin.y)
    check("and pointing two squares higher was the only way to reach today — exactly as the learner found",
          layout.day(at: twoRowsUp)?.day.count == 40)
}
