import Foundation

/// When a card is next wanted, in the words a person would use.
///
/// "In 3 days" is arithmetic; "Thursday" is a day you can picture. Anything
/// further out than a week gets a date, because "in 47 days" is not a fact
/// anybody can hold.
nonisolated enum DueText {

    static func describe(_ due: Date?, now: Date, calendar: Calendar = .current) -> String {
        guard let due else { return "—" }
        if due <= now { return "Ready" }

        let today = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: due)
        let days = calendar.dateComponents([.day], from: today, to: target).day ?? 0

        switch days {
        case ..<1: return "Later today"
        case 1: return "Tomorrow"
        case 2...6: return due.formatted(.dateTime.weekday(.wide))
        default: return due.formatted(.dateTime.day().month(.abbreviated))
        }
    }

    /// The same thing said in a sentence, for the day's summary.
    static func sentence(nextDue: Date?, now: Date, calendar: Calendar = .current) -> String {
        guard let nextDue else { return "Nothing scheduled yet." }
        let when = describe(nextDue, now: now, calendar: calendar)
        switch when {
        case "Ready": return "Ready to review."
        case "Later today": return "Next review later today."
        case "Tomorrow": return "Next review tomorrow."
        default: return "Next review \(when)."
        }
    }
}
