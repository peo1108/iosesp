import ESPCore
import SwiftUI

/// Thin-line ESP drawing: boxes, skeletons, head dots and snaplines.
struct ESPCanvas: View {
    struct Options {
        var box = true
        var boxStyle: BoxStyle = .corner
        var skeleton = true
        var headDot = true
        var snaplines = true
    }

    let layouts: [PlayerLayout]
    var options = Options()

    var body: some View {
        Canvas { context, size in
            for layout in layouts {
                if options.snaplines {
                    var line = Path()
                    line.move(to: CGPoint(x: size.width / 2, y: size.height))
                    line.addLine(to: CGPoint(x: layout.rect.midX, y: layout.rect.maxY))
                    stroke(line, color: layout.color.opacity(0.8), in: &context)
                }
                if options.box {
                    stroke(boxPath(layout), color: layout.color, in: &context)
                }
                if options.skeleton {
                    drawSkeleton(layout, in: &context)
                }
                if options.headDot {
                    let h = layout.head
                    let dot = Path(ellipseIn: CGRect(x: h.x - 4, y: h.y - 4, width: 8, height: 8))
                    context.fill(dot, with: .color(layout.color))
                    context.stroke(dot, with: .color(.black.opacity(0.35)), lineWidth: 1)
                }
            }
        }
    }

    private func boxPath(_ layout: PlayerLayout) -> Path {
        let r = layout.rect
        var path = Path()
        switch options.boxStyle {
        case .threeD:
            if let c = layout.corners3D {
                for i in 0..<4 {
                    path.move(to: c[i]); path.addLine(to: c[(i + 1) % 4])
                    path.move(to: c[i + 4]); path.addLine(to: c[(i + 1) % 4 + 4])
                    path.move(to: c[i]); path.addLine(to: c[i + 4])
                }
            } else {
                path.addRoundedRect(in: r, cornerSize: CGSize(width: 4, height: 4))
            }
        case .full:
            path.addRoundedRect(in: r, cornerSize: CGSize(width: 4, height: 4))
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

    private func drawSkeleton(_ layout: PlayerLayout, in context: inout GraphicsContext) {
        var bones = Path()
        for (a, b) in Joint.bones {
            guard let p = layout.joint(a), let q = layout.joint(b) else { continue }
            bones.move(to: p)
            bones.addLine(to: q)
        }
        stroke(bones, color: .white, in: &context)
        for joint in Joint.allCases {
            guard let p = layout.joint(joint) else { continue }
            context.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(.white))
        }
    }

    /// Dark halo under the colored line keeps it readable on bright scenes.
    private func stroke(_ path: Path, color: Color, in context: inout GraphicsContext) {
        context.stroke(path, with: .color(.black.opacity(0.35)), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }
}
