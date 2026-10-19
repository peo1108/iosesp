public struct HitTarget: Equatable, Sendable {
    public var id: Int
    public var isHead: Bool

    public init(id: Int, isHead: Bool) {
        self.id = id
        self.isHead = isHead
    }
}

/// Which player a tap lands on, in screen space. Overlapping boxes resolve to the smallest (nearest-looking) one.
public enum HitTest {
    public static func target(at p: Vec2, boxes: [(id: Int, box: Rect, head: Vec2?)]) -> HitTarget? {
        guard let hit = boxes.filter({ $0.box.contains(p) }).min(by: { $0.box.area < $1.box.area }) else { return nil }
        let isHead: Bool
        if let head = hit.head {
            let d = p - head
            isHead = (d * d).sum().squareRoot() <= 0.25 * hit.box.width
        } else {
            isHead = p.y <= hit.box.y + 0.18 * hit.box.height
        }
        return HitTarget(id: hit.id, isHead: isHead)
    }
}
