import CoreImage
import CoreVideo
import ESPCore

/// Gets camera frames into the models' 640×480 (4:3). 4:3 frames go straight through (Vision scales them);
/// other aspects (ARKit's 16:9 4K) are scaled down and letterboxed here, so people aren't squashed and every
/// box can be mapped back exactly. Not thread-safe: call from one queue.
final class ModelInput {
    struct Prepared {
        let buffer: CVPixelBuffer
        /// Converts normalized model-input coordinates back to the camera image.
        let letterbox: Letterbox
    }

    static let size = Vec2(640, 480)

    private let context = CIContext(options: [.cacheIntermediates: false, .workingColorSpace: NSNull()])
    private var pool: CVPixelBufferPool?

    func prepare(_ image: CVPixelBuffer) -> Prepared {
        let imageSize = Vec2(Float(CVPixelBufferGetWidth(image)), Float(CVPixelBufferGetHeight(image)))
        let fit = Letterbox(imageSize: imageSize, inputSize: Self.size)
        guard !fit.isIdentity, let out = makeBuffer() else { return Prepared(buffer: image, letterbox: fit) }

        let scale = min(Self.size.x / imageSize.x, Self.size.y / imageSize.y)
        let offset = CGPoint(x: CGFloat(Self.size.x - imageSize.x * scale) / 2, y: CGFloat(Self.size.y - imageSize.y * scale) / 2)
        let canvas = CGRect(x: 0, y: 0, width: CGFloat(Self.size.x), height: CGFloat(Self.size.y))
        // Lanczos keeps thin, far-away people from aliasing away in a 6× reduction.
        let scaled = CIImage(cvPixelBuffer: image)
            .applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1])
            .transformed(by: CGAffineTransform(translationX: offset.x, y: offset.y))
        let framed = scaled.composited(over: CIImage(color: .black).cropped(to: canvas)).cropped(to: canvas)
        context.render(framed, to: out)
        return Prepared(buffer: out, letterbox: fit)
    }

    private func makeBuffer() -> CVPixelBuffer? {
        if pool == nil {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(Self.size.x),
                kCVPixelBufferHeightKey as String: Int(Self.size.y),
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            ]
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        }
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        return buffer
    }
}
