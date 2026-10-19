/// Maps the landscape camera image onto the landscape screen the way the camera feed is drawn: scaled to
/// fill (aspect fill, centered) and, in landscapeLeft, turned 180°. Owning this math avoids ARKit's
/// orientation-dependent helpers, which rotate everything 90° if the orientation they get is not landscape.
public struct ViewMapping: Sendable {
    public let imageSize: Vec2
    public let viewSize: Vec2
    /// Interface landscapeLeft: the captured image shows the scene upside down.
    public let upsideDown: Bool
    /// Points per image pixel.
    public let scale: Float
    /// How much of the scaled image hangs past the top-left corner of the view.
    public let overhang: Vec2

    public init(imageSize: Vec2, viewSize: Vec2, upsideDown: Bool) {
        self.imageSize = imageSize
        self.viewSize = viewSize
        self.upsideDown = upsideDown
        scale = max(viewSize.x / imageSize.x, viewSize.y / imageSize.y)
        overhang = (imageSize * scale - viewSize) / 2
    }

    /// View point for a normalized image point (0…1, top-left origin).
    public func view(fromNormalized p: Vec2) -> Vec2 {
        let q = upsideDown ? Vec2(1 - p.x, 1 - p.y) : p
        return q * imageSize * scale - overhang
    }

    public func view(fromPixel p: Vec2) -> Vec2 {
        view(fromNormalized: p / imageSize)
    }

    /// The same mapping as x' = a·x + tx, y' = d·y + ty on normalized image coordinates.
    public var affine: (a: Float, d: Float, tx: Float, ty: Float) {
        let size = imageSize * scale
        return upsideDown
            ? (-size.x, -size.y, size.x - overhang.x, size.y - overhang.y)
            : (size.x, size.y, -overhang.x, -overhang.y)
    }
}
