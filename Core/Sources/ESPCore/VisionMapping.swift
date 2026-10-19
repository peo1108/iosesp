/// How the captured image was turned before Vision analysed it.
public enum VisionOrientation: Sendable {
    /// As captured (interface landscapeRight).
    case up
    /// Turned 180° so people stand upright (interface landscapeLeft).
    case down
}

/// Converts Vision's normalized, bottom-left-origin results back to captured-image coordinates (top-left origin).
public enum VisionMapping {
    public static func point(_ p: Vec2, orientation: VisionOrientation) -> Vec2 {
        switch orientation {
        case .up: Vec2(p.x, 1 - p.y)
        case .down: Vec2(1 - p.x, p.y)
        }
    }

    public static func rect(_ r: Rect, orientation: VisionOrientation) -> Rect {
        switch orientation {
        case .up: Rect(x: r.x, y: 1 - r.y - r.height, width: r.width, height: r.height)
        case .down: Rect(x: 1 - r.x - r.width, y: r.y, width: r.width, height: r.height)
        }
    }
}
