import ESPCore
import SwiftUI

/// Thin-line ESP drawing (boxes now; skeleton, snaplines and 3D boxes join later).
struct ESPCanvas: View {
    let layouts: [PlayerLayout]
    var boxStyle: BoxStyle = .corner

    var body: some View {
        Canvas { context, _ in
            for layout in layouts {
                let path = boxPath(layout.rect)
                stroke(path, color: layout.color, in: &context)
            }
        }
    }

    private func boxPath(_ r: CGRect) -> Path {
        var path = Path()
        switch boxStyle {
        case .full, .threeD:
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

    /// Dark halo under the colored line keeps it readable on bright scenes.
    private func stroke(_ path: Path, color: Color, in context: inout GraphicsContext) {
        context.stroke(path, with: .color(.black.opacity(0.35)), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }
}
