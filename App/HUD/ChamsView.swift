import SwiftUI

/// Tints people's silhouettes with a slowly turning gradient, clipped by the segmentation mask.
struct ChamsView: View {
    let mask: CGImage?
    let mapper: ScreenMapper?
    let accent: Color
    let time: Date

    var body: some View {
        Canvas { context, size in
            guard let mask, let mapper else { return }
            let w = CGFloat(mask.width), h = CGFloat(mask.height)
            context.clipToLayer { layer in
                layer.concatenate(mapper.normalizedImageToView)
                layer.scaleBy(x: 1 / w, y: 1 / h)
                layer.draw(Image(decorative: mask, scale: 1), in: CGRect(x: 0, y: 0, width: w, height: h))
            }
            // One full turn every 4 s.
            let angle = time.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) / 4 * 2 * .pi
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let reach = max(size.width, size.height) / 2
            let offset = CGPoint(x: cos(angle) * reach, y: sin(angle) * reach)
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(Gradient(colors: [accent.opacity(0.45), accent.opacity(0.15)]),
                                               startPoint: CGPoint(x: center.x - offset.x, y: center.y - offset.y),
                                               endPoint: CGPoint(x: center.x + offset.x, y: center.y + offset.y)))
        }
        .allowsHitTesting(false)
    }
}
