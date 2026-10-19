import ESPCore
import SwiftUI

/// Glass arrows on the screen edge pointing at people and animals out of view.
struct OffscreenArrowsView: View {
    let markers: [OffscreenMarker]

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            ZStack {
                Color.clear
                ForEach(markers) { marker in
                    VStack(spacing: 2) {
                        Image(systemName: "arrowtriangle.right.fill")
                            .font(.system(size: 12, weight: .bold))
                            .rotationEffect(.radians(marker.angle))
                            .frame(width: 30, height: 30)
                            .glassEffect(.regular.tint(marker.color.opacity(0.25)), in: .circle)
                        Text(String(format: "%@%.0fm", marker.estimated ? "~" : "", marker.distance))
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .shadow(color: .black.opacity(0.5), radius: 2)
                    }
                    .scaleEffect(CGFloat(DepthStyle.cardScale(marker.distance)))
                    .opacity(Double(DepthStyle.opacity(marker.distance)))
                    .position(marker.point)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
