/// An image fitted, centred and uniformly scaled, into a model input of another aspect (bars on two sides),
/// so a 16:9 4K frame reaches a 4:3 model without squashing people. Converts back from normalized input
/// coordinates to normalized image coordinates.
public struct Letterbox: Equatable, Sendable {
    /// Where the image sits inside the input, normalized to the input.
    public let content: Rect

    public init(imageSize: Vec2, inputSize: Vec2) {
        let scale = min(inputSize.x / imageSize.x, inputSize.y / imageSize.y)
        let w = imageSize.x * scale / inputSize.x, h = imageSize.y * scale / inputSize.y
        content = Rect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)
    }

    /// True when the aspects match (within a pixel or so) and nothing needs converting.
    public var isIdentity: Bool { abs(content.width - 1) < 0.002 && abs(content.height - 1) < 0.002 }

    public func toImage(_ p: Vec2) -> Vec2 {
        Vec2((p.x - content.x) / content.width, (p.y - content.y) / content.height)
    }

    public func toImage(_ r: Rect) -> Rect {
        let a = toImage(Vec2(r.x, r.y))
        return Rect(x: a.x, y: a.y, width: r.width / content.width, height: r.height / content.height)
    }
}

/// The LiDAR depth map covers the sensor's 4:3 view; a 16:9 video frame is the middle band of it. Maps a
/// normalized image point to the normalized depth-map point that sees the same thing (identity when the
/// aspects match).
public enum DepthCrop {
    public static func depthPoint(_ p: Vec2, imageAspect: Float, depthAspect: Float) -> Vec2 {
        if imageAspect > depthAspect + 0.01 {
            let f = depthAspect / imageAspect   // the image's share of the depth map's height
            return Vec2(p.x, 0.5 + (p.y - 0.5) * f)
        }
        if imageAspect < depthAspect - 0.01 {
            let f = imageAspect / depthAspect
            return Vec2(0.5 + (p.x - 0.5) * f, p.y)
        }
        return p
    }
}
