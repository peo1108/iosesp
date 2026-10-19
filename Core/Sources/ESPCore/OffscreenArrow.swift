import Foundation

/// Where to pin an edge arrow for a player outside the view (screen points, origin top-left).
public enum OffscreenArrow {
    public static func place(target: Vec2, isBehind: Bool, viewSize: Vec2, inset: Float = 36) -> (point: Vec2, angle: Float)? {
        let center = viewSize / 2
        let t = isBehind ? center - (target - center) : target
        let inside = t.x >= inset && t.x <= viewSize.x - inset && t.y >= inset && t.y <= viewSize.y - inset
        if inside && !isBehind { return nil }

        var d = t - center
        if d == .zero { d = Vec2(0, 1) }
        let halfW = center.x - inset, halfH = center.y - inset
        let sx = d.x == 0 ? Float.infinity : halfW / abs(d.x)
        let sy = d.y == 0 ? Float.infinity : halfH / abs(d.y)
        return (center + d * min(sx, sy), atan2f(d.y, d.x))
    }
}
