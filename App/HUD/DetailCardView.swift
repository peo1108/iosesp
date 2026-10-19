import ESPCore
import SwiftUI

/// Liquid Glass cards floating beside each box, flipping to the left near the screen edge. Far people get
/// smaller, fainter cards, drawn underneath the near ones.
struct DetailCardsView: View {
    let layouts: [PlayerLayout]
    /// Camera clock now, for the time-in-frame counter.
    let now: TimeInterval
    let viewWidth: CGFloat

    private static let width: CGFloat = 116

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            ZStack {
                Color.clear
                ForEach(layouts.sorted { $0.distance > $1.distance }) { layout in
                    let right = layout.rect.maxX + 8 + Self.width < viewWidth
                    DetailCardView(layout: layout, now: now)
                        .scaleEffect(CGFloat(DepthStyle.cardScale(layout.distance)), anchor: right ? .topLeading : .topTrailing)
                        .opacity(Double(0.35 + 0.65 * DepthStyle.opacity(layout.distance)))
                        .frame(width: Self.width, alignment: right ? .topLeading : .topTrailing)
                        .position(x: right ? layout.rect.maxX + 8 + Self.width / 2 : layout.rect.minX - 8 - Self.width / 2,
                                  y: layout.rect.minY + 34)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// "Người" / "🐕 Chó", then distance, speed and time in frame.
struct DetailCardView: View {
    let layout: PlayerLayout
    let now: TimeInterval

    private var title: String {
        if case let .animal(animal) = layout.track.kind { return animal.emoji + " " + layout.label }
        return layout.label
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.bold))
            row("ruler", Readout.distance(layout.distance, estimated: layout.track.distanceIsEstimated))
            row("speedometer", Readout.speed(layout.track.floorSpeed))
            row("timer", Readout.clock(now - layout.track.firstSeen))
        }
        .font(.caption2.weight(.medium))
        .monospacedDigit()
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .fixedSize()
        .glassEffect(.regular.tint(layout.color.opacity(0.14)), in: .rect(cornerRadius: 13))
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).foregroundStyle(layout.color).frame(width: 12)
            Text(text)
        }
    }
}
