/// Axis-aligned rectangle, origin top-left. Used both in normalized image space and screen points.
public struct Rect: Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var width: Float
    public var height: Float

    public init(x: Float, y: Float, width: Float, height: Float) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var center: Vec2 { Vec2(x + width / 2, y + height / 2) }
    public var minY: Float { y }
    public var maxY: Float { y + height }
    public var area: Float { width * height }

    public func iou(_ other: Rect) -> Float {
        let w = min(x + width, other.x + other.width) - max(x, other.x)
        let h = min(maxY, other.maxY) - max(y, other.y)
        guard w > 0, h > 0 else { return 0 }
        let inter = w * h
        return inter / (area + other.area - inter)
    }

    public func contains(_ p: Vec2) -> Bool {
        p.x >= x && p.x <= x + width && p.y >= y && p.y <= maxY
    }

    public static func bounding(_ points: [Vec2]) -> Rect? {
        guard let first = points.first else { return nil }
        var lo = first, hi = first
        for p in points.dropFirst() {
            lo = pointwiseMin(lo, p)
            hi = pointwiseMax(hi, p)
        }
        return Rect(x: lo.x, y: lo.y, width: hi.x - lo.x, height: hi.y - lo.y)
    }
}
