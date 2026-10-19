import SwiftUI

/// Top-leading status capsule: ESP · fps · players, plus scanning / tracking / heat notices.
struct StatsView: View {
    let fps: Double
    let players: Int
    let trackingNormal: Bool
    let heatWarning: Bool
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "scope").foregroundStyle(accent)
            Text("ESP").fontWeight(.bold)
            Text("\(Int(fps.rounded()))fps").monospacedDigit().foregroundStyle(.secondary)
            if players == 0 {
                Label("Scanning…", systemImage: "dot.radiowaves.left.and.right")
                    .symbolEffect(.pulse)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(players) players").monospacedDigit()
            }
            if !trackingNormal {
                Label("Low tracking", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.partial)
            }
            if heatWarning {
                Label("Máy đang nóng", systemImage: "thermometer.high")
                    .foregroundStyle(Palette.locked)
            }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
    }
}
