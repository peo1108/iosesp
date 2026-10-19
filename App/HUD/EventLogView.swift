import ESPCore
import SwiftUI

/// Recent events ("Người 01 ngồi xuống"), newest at the bottom, each fading out over its lifetime.
struct EventLogView: View {
    let events: [ActivityEvent]
    /// ARFrame clock now.
    let now: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(events) { event in
                let age = (now - event.time) / ActivityTracker.eventTTL
                Text("▸ " + event.text)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassEffect(.regular, in: .capsule)
                    .opacity(age > 0.75 ? max(0, (1 - age) * 4) : 1)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: events.map(\.id))
    }
}
