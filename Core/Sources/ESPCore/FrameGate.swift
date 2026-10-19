import Foundation

/// Lets frames through at most `hz` times per second.
public struct FrameGate: Sendable {
    /// Camera timestamps jitter by a millisecond or so; without slack, a gap that comes out a hair short
    /// of the period skips a whole extra frame and the real rate drops by about a quarter.
    static let slack: TimeInterval = 0.004

    private var lastRun: TimeInterval?

    public init() {}

    public mutating func shouldRun(at time: TimeInterval, hz: Double) -> Bool {
        if let lastRun, time - lastRun < 1 / hz - Self.slack { return false }
        lastRun = time
        return true
    }
}
