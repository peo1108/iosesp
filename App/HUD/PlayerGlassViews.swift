import ESPCore
import SwiftUI

/// Liquid Glass pieces that float with each person or animal: label (+ activity) above, distance below,
/// detail card beside.
struct PlayerGlassViews: View {
    struct Options {
        var label = true
        var activity = true
        var distance = true
        var detailCard = false
    }

    let layouts: [PlayerLayout]
    var options = Options()
    /// ARFrame clock now (for the detail card's timer).
    var now: TimeInterval = 0
    var viewWidth: CGFloat = 0

    private static let cardWidth: CGFloat = 150

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            ZStack {
                Color.clear
                ForEach(layouts) { layout in
                    if options.label || (options.activity && layout.activity != nil) {
                        LabelTag(layout: layout, showName: options.label, showActivity: options.activity)
                            .position(x: layout.rect.midX, y: layout.rect.minY - 16)
                    }
                    if options.distance {
                        DistanceTag(layout: layout)
                            .position(x: layout.rect.midX, y: layout.rect.maxY + 16)
                    }
                    if options.detailCard, let state = layout.activity {
                        // Beside the box, flipping to the left near the screen edge.
                        let right = layout.rect.maxX + 10 + Self.cardWidth < viewWidth
                        DetailCardView(layout: layout, state: state, now: now)
                            .frame(width: Self.cardWidth, alignment: right ? .leading : .trailing)
                            .position(x: right ? layout.rect.maxX + 10 + Self.cardWidth / 2
                                               : layout.rect.minX - 10 - Self.cardWidth / 2,
                                      y: layout.rect.minY + 50)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct LabelTag: View {
    let layout: PlayerLayout
    let showName: Bool
    let showActivity: Bool

    private var text: String {
        var parts: [String] = []
        if showName {
            if case let .animal(animal) = layout.track.kind {
                parts.append(animal.emoji + " " + layout.label)
            } else {
                parts.append(layout.label)
            }
        }
        if showActivity, let state = layout.activity {
            parts.append(state.mainEmoji + " " + state.mainText)
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .fixedSize()
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: text)
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
