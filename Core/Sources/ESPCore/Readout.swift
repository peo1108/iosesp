import Foundation

/// Number formats shared by the detail card, list and edge arrows.
public enum Readout {
    /// "2.3 m", whole meters from 10 m; "~" in front when the distance is a guess (no depth).
    public static func distance(_ meters: Float, estimated: Bool) -> String {
        (estimated ? "~" : "") + String(format: meters < 10 ? "%.1f m" : "%.0f m", meters)
    }

    /// km/h. Under 0.3 m/s is position jitter of someone standing still, shown as 0.
    public static func speed(_ metersPerSecond: Float) -> String {
        guard metersPerSecond >= 0.3 else { return "0 km/h" }
        let kmh = metersPerSecond * 3.6
        return String(format: kmh < 10 ? "%.1f km/h" : "%.0f km/h", kmh)
    }

    /// "00:42"; minutes keep counting past 59.
    public static func clock(_ seconds: TimeInterval) -> String {
        let s = max(Int(seconds), 0)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
