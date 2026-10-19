import SwiftUI

/// Floating damage numbers, hitmarkers, elimination bursts and the ELIMINATED banner.
struct DamageFXView: View {
    let damage: [DamageFX]
    let hitMarkers: [HitMarkerFX]
    let eliminations: [EliminationFX]
    let accent: Color

    var body: some View {
        ZStack {
            Color.clear
            ForEach(hitMarkers) { HitMarker().position($0.point) }
            ForEach(damage) { FloatingNumber(fx: $0).position($0.point) }
            ForEach(eliminations) { Burst(color: accent).position($0.center) }
            if let last = eliminations.last {
                EliminatedBanner(name: last.name)
                    .id(last.id)
                    .transition(.scale(scale: 1.3).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: eliminations.last?.id)
        .allowsHitTesting(false)
    }
}

private struct FloatingNumber: View {
    let fx: DamageFX
    @State private var gone = false

    var body: some View {
        Text(fx.text)
            .font(fx.isHeadshot ? .headline.weight(.heavy) : .subheadline.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(fx.isHeadshot ? Palette.locked : .white)
            .shadow(color: .black.opacity(0.6), radius: 3)
            .fixedSize()
            .offset(y: gone ? -40 : 0)
            .opacity(gone ? 0 : 1)
            .onAppear { withAnimation(.easeOut(duration: 1.2)) { gone = true } }
    }
}

private struct HitMarker: View {
    @State private var gone = false

    var body: some View {
        Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            var path = Path()
            for (dx, dy) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] {
                path.move(to: CGPoint(x: c.x + dx * 4, y: c.y + dy * 4))
                path.addLine(to: CGPoint(x: c.x + dx * 11, y: c.y + dy * 11))
            }
            context.stroke(path, with: .color(.black.opacity(0.4)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .frame(width: 28, height: 28)
        .scaleEffect(gone ? 1.15 : 0.9)
        .opacity(gone ? 0 : 1)
        .onAppear { withAnimation(.easeOut(duration: 0.35)) { gone = true } }
    }
}

private struct Burst: View {
    let color: Color
    @State private var out = false

    var body: some View {
        ZStack {
            ForEach(0..<24, id: \.self) { i in
                let angle = Double(i) / 24 * 2 * .pi
                let reach: Double = i.isMultiple(of: 2) ? 70 : 48
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                    .offset(x: out ? cos(angle) * reach : 0, y: out ? sin(angle) * reach : 0)
                    .opacity(out ? 0 : 1)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.6)) { out = true } }
    }
}

private struct EliminatedBanner: View {
    let name: String

    var body: some View {
        VStack(spacing: 2) {
            Text("ELIMINATED")
                .font(.title2.weight(.heavy))
                .tracking(2)
            Text(name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(Palette.locked.opacity(0.35)), in: .capsule)
    }
}
