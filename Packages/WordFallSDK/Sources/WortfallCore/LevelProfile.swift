import Foundation

/// Arcade meters and reading cadence scale together; each level remains a short session.
public struct LevelProfile: Sendable {
    public let number: Int
    public var length: Double {
        let milestones: [Double] = [100, 200, 500, 1_000, 2_000, 5_000, 8_000, 10_000, 15_000]
        if number <= milestones.count { return milestones[max(0, number - 1)] }
        return 15_000 + Double(number - 9) * 5_000
    }
    public var words: Int {
        let counts = [3, 5, 8, 12, 16, 24, 30, 36, 44]
        return number <= counts.count ? counts[max(0, number - 1)] : 44 + (number - 9) * 2
    }
    public var spacing: Double { length / (Double(words) + 0.5) }
    public var baseSpeed: Double { spacing / 3.7 }
    public var maximumSpeed: Double { spacing / 2.5 }
    /// Long courses are compressed longitudinally in the miniature game world.
    /// This keeps labels readable and geometry bounded while the distance HUD uses arcade meters.
    public var visualScale: Double { min(1, 13 / baseSpeed) }
    public init(number: Int) { self.number = max(1, number) }
}
