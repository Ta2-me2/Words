import Foundation
import Observation

/// The current time, as something the interface can watch.
///
/// A card due in ten minutes has to become due while the window is open,
/// without the user touching anything. Views read `now` instead of calling
/// `Date()` themselves, so every count on screen agrees with every other one
/// and they all move together.
@Observable
final class AppClock {

    private(set) var now = Date.now

    private var ticker: Task<Void, Never>?

    /// Half a minute: fine enough that a ten-minute learning step arrives
    /// unnoticed, coarse enough to cost nothing.
    private let interval: Duration = .seconds(30)

    func start() {
        guard ticker == nil else { return }
        ticker = Task { [interval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                now = .now
            }
        }
    }

    /// Pulls the time forward at a moment when it is known to matter — an
    /// answer given, a session closed — rather than waiting for the next tick.
    func refresh() {
        now = .now
    }
}
