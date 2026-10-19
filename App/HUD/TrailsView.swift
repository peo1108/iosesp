import ESPCore
import SwiftUI

/// Footprint dots on the floor where each person walked in the last 5 s, fading with age.
/// Positions are in world space, so the dots stay on the floor while the phone moves.
struct TrailsView: View {
    let trails: [(color: Color, points: [(position: Vec3, age: Double)])]
    let mapper: ScreenMapper

    var body: some View {
        Canvas { context, _ in
            for trail in trails {
                for (i, point) in trail.points.enumerated() {
                    guard let p = mapper.point(world: point.position) else { continue }
                    // Smaller with distance, alternating left/right like footsteps.
                    let size = CGFloat(max(3, 9 / max(mapper.depth(of: point.position), 0.5)))
                    let side: CGFloat = i.isMultiple(of: 2) ? -size : size
                    let dot = Path(ellipseIn: CGRect(x: p.x - size / 2 + side * 0.6, y: p.y - size / 4,
                                                     width: size, height: size / 2))
                    context.fill(dot, with: .color(trail.color.opacity(0.75 * (1 - point.age))))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
