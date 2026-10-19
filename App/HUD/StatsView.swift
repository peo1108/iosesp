import SwiftUI

/// Top-leading counter capsule: "◉ 3 người · 🐕 1" · fps, plus lens / scanning / tracking / heat notices.
struct StatsView: View {
    let fps: Double
    /// e.g. "3 người · 🐕 1".
    let summary: String
    let isEmpty: Bool
    let trackingNormal: Bool
    let heatWarning: Bool
    /// Running on the 0.5× camera.
    let ultraWide: Bool
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "scope").foregroundStyle(accent)
            if isEmpty {
                Label("Đang quét…", systemImage: "dot.radiowaves.left.and.right")
                    .symbolEffect(.pulse)
                    .foregroundStyle(.secondary)
            } else {
                Text(summary).monospacedDigit()
            }
            Text("\(Int(fps.rounded())) fps").monospacedDigit().foregroundStyle(.secondary)
            if ultraWide {
                Text("0.5×").foregroundStyle(accent)
            }
            if !trackingNormal {
                Label("Tracking yếu", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.partial)
            }
            if heatWarning {
                Label("Máy đang nóng", systemImage: "thermometer.high")
                    .foregroundStyle(Palette.alert)
            }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
    }
}
