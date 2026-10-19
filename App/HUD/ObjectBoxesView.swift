import ESPCore
import SwiftUI

/// Thin white boxes with a small label for detected objects (phones, cups, chairs…).
struct ObjectBoxesView: View {
    let objects: [DetectedObject]
    let mapper: ScreenMapper

    var body: some View {
        ZStack {
            Canvas { context, _ in
                for object in objects {
                    let r = mapper.rect(object.box)
                    let path = Path(roundedRect: r, cornerRadius: 6, style: .continuous)
                    context.stroke(path, with: .color(.black.opacity(0.3)), lineWidth: 2.5)
                    context.stroke(path, with: .color(.white.opacity(0.85)), lineWidth: 1)
                }
            }
            ForEach(Array(objects.enumerated()), id: \.offset) { _, object in
                let r = mapper.rect(object.box)
                Text("\(object.kind.emoji) \(object.kind.name)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .fixedSize()
                    .glassEffect(.regular, in: .capsule)
                    .position(x: r.midX, y: r.minY - 10)
            }
        }
        .allowsHitTesting(false)
    }
}
