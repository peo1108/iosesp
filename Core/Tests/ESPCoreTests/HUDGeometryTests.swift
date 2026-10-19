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

@Test func radarForwardIsUp() {
    let b = Radar.blips([(id: 1, world: Vec3(0, 0, -5))], cameraToWorld: .identity, range: 10)
    #expect(b == [RadarBlip(id: 1, position: Vec2(0, 0.5))])
}

@Test func radarRotatesWithHeading() {
    // camera turned 90° left: a player at world −Z now appears on the right
    let b = Radar.blips([(id: 1, world: Vec3(0, 0, -5))], cameraToWorld: .rotationY(.pi / 2), range: 10)[0]
    #expect(abs(b.position.x - 0.5) < 1e-4 && abs(b.position.y) < 1e-4)
}

@Test func radarIsRelativeToCameraPosition() {
    let b = Radar.blips([(id: 1, world: Vec3(2, 0, 0))], cameraToWorld: .translation(Vec3(2, 1.5, 5)), range: 10)[0]
    #expect(abs(b.position.x) < 1e-4 && abs(b.position.y - 0.5) < 1e-4)
}

@Test func radarDropsOutOfRange() {
    #expect(Radar.blips([(id: 1, world: Vec3(0, 0, -50))], cameraToWorld: .identity, range: 10).isEmpty)
}

@Test func aimbotPicksNearestInFov() {
    let c: [(id: Int, aimPoint: Vec2)] = [(1, Vec2(600, 250)), (2, Vec2(530, 260)), (3, Vec2(900, 250))]
    #expect(Aimbot.selectTarget(c, center: Vec2(500, 250), fovRadius: 150) == 2)
    #expect(Aimbot.selectTarget([(id: 3, aimPoint: Vec2(900, 250))], center: Vec2(500, 250), fovRadius: 150) == nil)
    #expect(Aimbot.selectTarget([], center: Vec2(500, 250), fovRadius: 150) == nil)
}
