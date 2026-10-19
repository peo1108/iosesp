import CoreImage
import CoreVideo
import ESPCore

/// Gets camera frames into a model's 4:3 input (896×672 for people, 640×480 for animals). 4:3 frames go straight
/// through (Vision scales them); other aspects (ARKit's 16:9 4K) are scaled down and letterboxed here, so people
/// aren't squashed and every box can be mapped back exactly. Not thread-safe: call from one queue.
final class ModelInput {
    struct Prepared {
        let buffer: CVPixelBuffer
        /// Converts normalized model-input coordinates back to the camera image.
        let letterbox: Letterbox
    }

    /// People (pose) model input.
    static let poseSize = Vec2(896, 672)
    /// Animal/backup-people model input.
    static let objectSize = Vec2(640, 480)

    private let context = CIContext(options: [.cacheIntermediates: false, .workingColorSpace: NSNull()])
    private var pools: [Int: CVPixelBufferPool] = [:]

    func prepare(_ image: CVPixelBuffer, size: Vec2) -> Prepared {
        let imageSize = Vec2(Float(CVPixelBufferGetWidth(image)), Float(CVPixelBufferGetHeight(image)))
        let fit = Letterbox(imageSize: imageSize, inputSize: size)
        guard !fit.isIdentity, let out = makeBuffer(size) else { return Prepared(buffer: image, letterbox: fit) }

        let scale = min(size.x / imageSize.x, size.y / imageSize.y)
        let offset = CGPoint(x: CGFloat(size.x - imageSize.x * scale) / 2, y: CGFloat(size.y - imageSize.y * scale) / 2)
        let canvas = CGRect(x: 0, y: 0, width: CGFloat(size.x), height: CGFloat(size.y))
        // Lanczos keeps thin, far-away people from aliasing away in a 6× reduction.
        let scaled = CIImage(cvPixelBuffer: image)
            .applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1])
            .transformed(by: CGAffineTransform(translationX: offset.x, y: offset.y))
        let framed = scaled.composited(over: CIImage(color: .black).cropped(to: canvas)).cropped(to: canvas)
        context.render(framed, to: out)
        return Prepared(buffer: out, letterbox: fit)
    }

    private func makeBuffer(_ size: Vec2) -> CVPixelBuffer? {
        let key = Int(size.x)
        if pools[key] == nil {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.x),
                kCVPixelBufferHeightKey as String: Int(size.y),
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            ]
            var pool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
            pools[key] = pool
        }
        guard let pool = pools[key] else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        return buffer
    }
}
