import ESPCore
import SwiftUI

/// Glass card beside a person: distance & speed, posture, facing, what they hold/carry, time in frame.
struct DetailCardView: View {
    let layout: PlayerLayout
    let state: ActivityState
    /// ARFrame clock now, for the time-in-frame counter.
    let now: TimeInterval

    private var frame: ActivityFrame { state.frame }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            row("ruler", String(format: "%.1f m · %.1f m/s", layout.distance, layout.track.speed))
            row(nil, "\(frame.posture.emoji) \(frame.posture.text) · \(frame.motion.emoji) \(frame.motion.text)")
            row(nil, "\(frame.facing.emoji) \(frame.facing.text)")
            if frame.gesture != .none {
                row(nil, "\(frame.gesture.emoji) \(frame.gesture.text)")
            }
            if frame.objectAction != .none {
                row(nil, "\(frame.objectAction.emoji) \(frame.objectAction.text)")
            }
            if !frame.carrying.isEmpty {
                row(nil, frame.carrying.map { "\($0.emoji) \($0.text)" }.joined(separator: " · "))
            }
            row("timer", Self.clock(now - state.firstSeen))
        }
        .font(.caption2.weight(.medium))
        .monospacedDigit()
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .fixedSize()
        .glassEffect(.regular.tint(layout.color.opacity(0.12)), in: .rect(cornerRadius: 14))
    }

    private func row(_ symbol: String?, _ text: String) -> some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol).foregroundStyle(layout.color).frame(width: 12)
            }
            Text(text)
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(Int(seconds), 0)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
