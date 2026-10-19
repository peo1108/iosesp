import ESPCore
import SwiftUI

/// Round glass minimap: the phone sits in the middle facing up, players are dots.
struct RadarView: View {
    let blips: [RadarBlip]
    let lockedID: Int?
    let accent: Color
    let time: Date

    private let size: CGFloat = 110

    var body: some View {
        Canvas { context, canvasSize in
            let c = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let r = canvasSize.width / 2 - 4

            for fraction in [1.0 / 3, 2.0 / 3, 1] {
                let ring = Path(ellipseIn: CGRect(x: c.x - r * fraction, y: c.y - r * fraction, width: 2 * r * fraction, height: 2 * r * fraction))
                context.stroke(ring, with: .color(.white.opacity(0.15)), lineWidth: 1)
            }

            // 60° field of view, pointing up.
            var cone = Path()
            cone.move(to: c)
            cone.addArc(center: c, radius: r, startAngle: .degrees(-120), endAngle: .degrees(-60), clockwise: false)
            cone.closeSubpath()
            context.fill(cone, with: .color(accent.opacity(0.15)))

            // Sweep line, one turn every 3 s.
            let sweep = time.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3) / 3 * 2 * .pi
            var line = Path()
            line.move(to: c)
            line.addLine(to: CGPoint(x: c.x + cos(sweep) * r, y: c.y + sin(sweep) * r))
            context.stroke(line, with: .color(accent.opacity(0.5)), lineWidth: 1.5)

            for blip in blips {
                let p = CGPoint(x: c.x + CGFloat(blip.position.x) * r, y: c.y - CGFloat(blip.position.y) * r)
                let color = blip.id == lockedID ? Palette.locked : Palette.visible
                context.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)), with: .color(color))
            }

            var me = Path()
            me.move(to: CGPoint(x: c.x, y: c.y - 6))
            me.addLine(to: CGPoint(x: c.x + 4.5, y: c.y + 4))
            me.addLine(to: CGPoint(x: c.x - 4.5, y: c.y + 4))
            me.closeSubpath()
            context.fill(me, with: .color(.white))
        }
        .frame(width: size, height: size)
        .glassEffect(.regular, in: .circle)
    }
}
