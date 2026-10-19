import ESPCore
import SwiftUI

/// Liquid Glass pieces that float with each person or animal: label above, distance below.
struct PlayerGlassViews: View {
    struct Options {
        var label = true
        var distance = true
    }

    let layouts: [PlayerLayout]
    var options = Options()

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            ZStack {
                Color.clear
                ForEach(layouts) { layout in
                    if options.label {
                        LabelTag(layout: layout)
                            .position(x: layout.rect.midX, y: layout.rect.minY - 16)
                    }
                    if options.distance {
                        DistanceTag(layout: layout)
                            .position(x: layout.rect.midX, y: layout.rect.maxY + 16)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct LabelTag: View {
    let layout: PlayerLayout

    private var prefix: String {
        if case let .animal(animal) = layout.track.kind { return animal.emoji + " " }
        return ""
    }

    var body: some View {
        Text(prefix + layout.label)
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
