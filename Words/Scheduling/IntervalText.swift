import Foundation

/// How an interval is said out loud.
///
/// The grade buttons carry these, which is the only honest way to show what a
/// scheduler is about to do: "Good · 3 d" is a promise the app then keeps.
nonisolated enum IntervalText {

    /// The wait a state represents, described the way the scheduler means it.
    ///
    /// A card graduating to one day is due at the start of tomorrow, which from
    /// an afternoon is ten hours away — but it is a one-day interval, and
    /// saying "10 h" would misrepresent it.
    static func short(for state: SchedulingState, from date: Date) -> String {
        if state.stage == .review {
            return days(state.intervalDays)
        }
        let seconds = max(0, (state.dueDate ?? date).timeIntervalSince(date))
        return short(seconds: seconds)
    }

    static func short(seconds: TimeInterval) -> String {
        let minutes = seconds / 60
        if minutes < 1 { return "<1 m" }
        if minutes < 60 { return "\(Int(minutes.rounded())) m" }
        let hours = minutes / 60
        if hours < 24 { return "\(Int(hours.rounded())) h" }
        return days(seconds / 86_400)
    }

    static func days(_ value: Double) -> String {
        let days = max(0, value.rounded())
        if days < 31 { return "\(Int(days)) d" }
        if days < 365 { return "\(Int((days / 30.44).rounded())) mo" }
        let years = days / 365.25
        return years < 10 ? String(format: "%.1f y", years) : "\(Int(years.rounded())) y"
    }
}
