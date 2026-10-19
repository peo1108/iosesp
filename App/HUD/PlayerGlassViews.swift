import ESPCore
import SwiftUI

/// Liquid Glass pieces that float with each player: name tag above, distance below, health bar at the side.
struct PlayerGlassViews: View {
    struct Options {
        var name = true
        var distance = true
        var health = true
    }

    let layouts: [PlayerLayout]
    var options = Options()

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            ZStack {
                Color.clear
                ForEach(layouts) { layout in
                    if options.name {
                        NameTag(layout: layout)
                            .position(x: layout.rect.midX, y: layout.rect.minY - 16)
                    }
                    if options.distance {
                        DistanceTag(layout: layout)
                            .position(x: layout.rect.midX, y: layout.rect.maxY + 16)
                    }
                    if options.health {
                        HealthBar(layout: layout)
                            .position(x: layout.rect.minX - 9, y: layout.rect.midY - 8)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct NameTag: View {
    let layout: PlayerLayout

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: layout.identity.rankSymbol)
                .font(.caption2)
                .foregroundStyle(layout.color)
            Text("\(layout.identity.name) · Lv \(layout.identity.level)")
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .fixedSize()
        .glassEffect(.regular.tint(layout.color.opacity(0.25)), in: .capsule)
    }
}

private struct DistanceTag: View {
    let layout: PlayerLayout

    var body: some View {
        Text(String(format: "%@%.1f m", layout.track.distanceIsEstimated ? "~" : "", layout.track.distance))
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .fixedSize()
            .glassEffect(.regular.tint(layout.color.opacity(0.2)), in: .capsule)
    }
}

private struct HealthBar: View {
    let layout: PlayerLayout

    var body: some View {
        let height = max(layout.rect.height, 24)
        let fraction = CGFloat(min(max(layout.hp / 100, 0), 1))
        VStack(spacing: 3) {
            Text("\(Int(layout.hp.rounded()))")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .fixedSize()
                .shadow(color: .black.opacity(0.5), radius: 2)
            ZStack(alignment: .bottom) {
                Capsule().fill(.black.opacity(0.2))
                Capsule().fill(Self.color(for: layout.hp)).frame(height: height * fraction)
            }
            .frame(width: 6, height: height)
            .glassEffect(.regular, in: .capsule)
        }
        .animation(.spring(duration: 0.4, bounce: 0.3), value: layout.hp)
    }

    /// Green at full health, yellow at half, red when empty.
    static func color(for hp: Float) -> Color {
        let green = Color(uiColor: .systemGreen), yellow = Color(uiColor: .systemYellow), red = Color(uiColor: .systemRed)
        return hp >= 50 ? yellow.mix(with: green, by: Double((hp - 50) / 50)) : red.mix(with: yellow, by: Double(max(hp, 0) / 50))
    }
}
