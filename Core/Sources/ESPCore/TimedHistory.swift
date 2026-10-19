import Foundation

/// Values remembered by timestamp for a short window, e.g. the camera of each recent detection frame.
public struct TimedHistory<Value> {
    private var entries: [(time: TimeInterval, value: Value)] = []
    public let keep: TimeInterval

    public init(keep: TimeInterval) {
        self.keep = keep
    }

    public var count: Int { entries.count }
    public var latest: Value? { entries.last?.value }

    /// Appends a value; timestamps are expected to increase. Drops entries older than `keep`.
    public mutating func insert(_ value: Value, at time: TimeInterval) {
        entries.append((time, value))
        entries.removeAll { time - $0.time > keep }
    }

    /// The value stored at `time`, else the newest one before it, else the oldest one kept.
    public func value(at time: TimeInterval) -> Value? {
        entries.last { $0.time <= time }?.value ?? entries.first?.value
    }
}
