import Testing
@testable import ESPCore

private let view = Vec2(1000, 500)

@Test func onScreenHasNoArrow() {
    #expect(OffscreenArrow.place(target: Vec2(500, 250), isBehind: false, viewSize: view) == nil)
}

@Test func rightSideArrowClampsToEdge() {
    let a = OffscreenArrow.place(target: Vec2(3000, 250), isBehind: false, viewSize: view)!
    #expect(a.point == Vec2(964, 250) && abs(a.angle) < 1e-5)
}

@Test func cornerArrowStaysInsideInsetRect() {
    let a = OffscreenArrow.place(target: Vec2(-2000, -2000), isBehind: false, viewSize: view)!
    #expect(a.point.x >= 36 - 1e-3 && a.point.y >= 36 - 1e-3)
    #expect(abs(a.point.y - 36) < 1e-3 || abs(a.point.x - 36) < 1e-3)
}

@Test func behindIsMirrored() {
    let a = OffscreenArrow.place(target: Vec2(700, 250), isBehind: true, viewSize: view)!
    #expect(a.point.x == 36 && abs(abs(a.angle) - .pi) < 1e-5)
}




