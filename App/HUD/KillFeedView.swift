import ESPCore
import SwiftUI

/// Top-trailing stack of recent eliminations, newest on top.
struct KillFeedView: View {
    let entries: [KillFeedEntry]

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(entries.reversed()) { entry in
                    HStack(spacing: 6) {
                        Text("You").fontWeight(.bold)
                        Image(systemName: "scope")
                            .foregroundStyle(entry.isHeadshot ? Palette.locked : .white)
                        Text(entry.victim)
                        Text(String(format: "· %.1fm", entry.distance))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(duration: 0.35), value: entries.map(\.id))
        .allowsHitTesting(false)
    }
}
