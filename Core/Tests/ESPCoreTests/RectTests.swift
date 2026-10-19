import Testing
@testable import ESPCore

@Test func iouOfIdenticalIsOneAndDisjointIsZero() {
    let a = Rect(x: 0.1, y: 0.1, width: 0.2, height: 0.4)
    #expect(a.iou(a) == 1)
    #expect(a.iou(Rect(x: 0.6, y: 0.6, width: 0.1, height: 0.1)) == 0)
    #expect(abs(a.iou(Rect(x: 0.2, y: 0.1, width: 0.2, height: 0.4)) - 1.0 / 3.0) < 1e-5)
}

@Test func boundingOfPoints() {
    let r = Rect.bounding([Vec2(0.2, 0.3), Vec2(0.5, 0.9)])!
    #expect(abs(r.x - 0.2) < 1e-6 && abs(r.y - 0.3) < 1e-6)
    #expect(abs(r.width - 0.3) < 1e-6 && abs(r.height - 0.6) < 1e-6)
    #expect(Rect.bounding([]) == nil)
}

@Test func centerAndContains() {
    let r = Rect(x: 0, y: 0, width: 2, height: 4)
    #expect(r.center == Vec2(1, 2) && r.maxY == 4 && r.minY == 0)
    #expect(r.contains(Vec2(1, 1)) && !r.contains(Vec2(3, 1)))
}

@Test func skeletonHas18Bones() {
    #expect(Joint.allCases.count == 19)
    #expect(Joint.bones.count == 18)
}
