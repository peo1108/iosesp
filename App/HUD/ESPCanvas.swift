import ESPCore
import SwiftUI

/// Thin-line ESP drawing: boxes and the "lite" snaplines, with depth: near people get thick, bright lines and
/// a soft glow, far ones thin, faded lines; far ones are drawn first so near ones sit on top.
struct ESPCanvas: View {
    struct Options {
        var box = true
        var boxStyle: BoxStyle = .corner
        var snaplines = false
    }

    let layouts: [PlayerLayout]
    var options = Options()

    var body: some View {
        Canvas { context, size in
            for layout in layouts.sorted(by: { $0.distance > $1.distance }) {
                let width = CGFloat(DepthStyle.lineWidth(layout.distance))
                let opacity = Double(DepthStyle.opacity(layout.distance))
                let nearness = Double(DepthStyle.nearness(layout.distance))
                if options.snaplines {
                    drawSnapline(to: layout, from: CGPoint(x: size.width / 2, y: 0), opacity: opacity, in: &context)
                }
                if options.box {
                    let path = boxPath(layout)
                    if options.boxStyle == .glass {
                        // Frosted look: faint tint plus a sheen fading down from the top edge.
                        let r = layout.rect
                        context.fill(path, with: .color(layout.color.opacity(0.08 * opacity)))
                        context.fill(path, with: .linearGradient(Gradient(colors: [.white.opacity(0.18 * opacity), .clear]),
                                                                 startPoint: CGPoint(x: r.midX, y: r.minY),
                                                                 endPoint: CGPoint(x: r.midX, y: r.minY + r.height * 0.35)))
                    }
                    // Partly hidden behind something: dashed.
                    stroke(path, color: layout.color, width: width, opacity: opacity, glow: nearness,
                           dashed: layout.track.occlusion == .partial, in: &context)
                }
            }
        }
    }

    /// A hairline from the top edge that fades in toward the box and ends in a small dot on its top edge.
    private func drawSnapline(to layout: PlayerLayout, from origin: CGPoint, opacity: Double, in context: inout GraphicsContext) {
        let end = CGPoint(x: layout.rect.midX, y: layout.rect.minY)
        var line = Path()
        line.move(to: origin)
        line.addLine(to: end)
        context.stroke(line, with: .linearGradient(Gradient(colors: [layout.color.opacity(0), layout.color.opacity(0.7 * opacity)]),
                                                   startPoint: origin, endPoint: end),
                       style: StrokeStyle(lineWidth: 1, lineCap: .round))
        context.fill(Path(ellipseIn: CGRect(x: end.x - 2, y: end.y - 2, width: 4, height: 4)),
                     with: .color(layout.color.opacity(0.9 * opacity)))
    }

    private func boxPath(_ layout: PlayerLayout) -> Path {
        let r = layout.rect
        var path = Path()
        switch options.boxStyle {
        case .full:
            path.addRoundedRect(in: r, cornerSize: CGSize(width: 4, height: 4))
        case .glass:
            // Rounded rim; the frosted tint and sheen are filled in body().
            path.addRoundedRect(in: r, cornerSize: CGSize(width: 12, height: 12), style: .continuous)
        case .corner:
            let l = min(r.width, r.height) * 0.22
            for (corner, dx, dy) in [(CGPoint(x: r.minX, y: r.minY), 1.0, 1.0), (CGPoint(x: r.maxX, y: r.minY), -1.0, 1.0),
                                     (CGPoint(x: r.minX, y: r.maxY), 1.0, -1.0), (CGPoint(x: r.maxX, y: r.maxY), -1.0, -1.0)] {
                path.move(to: CGPoint(x: corner.x + dx * l, y: corner.y))
                path.addLine(to: corner)
                path.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * l))
            }
        }
        return path
    }

    /// Dark halo under the colored line keeps it readable on bright scenes; near people also get a colored glow.
    private func stroke(_ path: Path, color: Color, width: CGFloat, opacity: Double, glow: Double, dashed: Bool,
                        in context: inout GraphicsContext) {
        let dash: [CGFloat] = dashed ? [6, 5] : []
        func style(_ w: CGFloat) -> StrokeStyle { StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round, dash: dash) }
        if glow > 0.05 {
            context.stroke(path, with: .color(color.opacity(0.25 * glow)), style: style(width + 6 * glow))
        }
        context.stroke(path, with: .color(.black.opacity(0.35 * opacity)), style: style(width + 2))
        context.stroke(path, with: .color(color.opacity(opacity)), style: style(width))
    }
}
