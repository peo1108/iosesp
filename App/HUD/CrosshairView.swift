import SwiftUI

/// FOV circle around the screen center and a crosshair that springs toward the locked target.
struct CrosshairView: View {
    let showCrosshair: Bool
    let showFOV: Bool
    let fovRadius: CGFloat
    let center: CGPoint
    /// Where the crosshair wants to be: the locked aim point, or the center.
    let target: CGPoint
    /// 0…1 from settings: higher is lazier.
    let smooth: Double
    let accent: Color

    var body: some View {
        ZStack {
            if showFOV {
                Circle()
                    .stroke(accent.opacity(0.6), lineWidth: 1.5)
                    .frame(width: fovRadius * 2, height: fovRadius * 2)
                    .position(center)
            }
            if showCrosshair {
                Canvas { context, size in
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)
                    var plus = Path()
                    plus.move(to: CGPoint(x: c.x - 9, y: c.y)); plus.addLine(to: CGPoint(x: c.x - 3, y: c.y))
                    plus.move(to: CGPoint(x: c.x + 3, y: c.y)); plus.addLine(to: CGPoint(x: c.x + 9, y: c.y))
                    plus.move(to: CGPoint(x: c.x, y: c.y - 9)); plus.addLine(to: CGPoint(x: c.x, y: c.y - 3))
                    plus.move(to: CGPoint(x: c.x, y: c.y + 3)); plus.addLine(to: CGPoint(x: c.x, y: c.y + 9))
                    context.stroke(plus, with: .color(.black.opacity(0.4)), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    context.stroke(plus, with: .color(.white), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    context.fill(Path(ellipseIn: CGRect(x: c.x - 1.5, y: c.y - 1.5, width: 3, height: 3)), with: .color(.white))
                }
                .frame(width: 24, height: 24)
                .position(target)
                .animation(.spring(response: 0.08 + smooth * 0.5, dampingFraction: 0.85), value: target)
            }
        }
        .allowsHitTesting(false)
    }
}
