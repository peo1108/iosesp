import Testing
@testable import ESPCore

private func track(_ id: Int, speed: Float = 0) -> Track {
    Track(id: id, state: .confirmed, box: Rect(x: 0.2, y: 0.2, width: 0.1, height: 0.4), joints: [:],
          worldPosition: Vec3(0, 0, -3), velocity: Vec3(speed, 0, 0), distance: 3, distanceIsEstimated: false,
          heightMeters: 1.7, yaw: 0, occlusion: .visible, hits: 3, lastSeen: 0)
}

@Test func headHitByJointRadius() {
    let b: [(id: Int, box: Rect, head: Vec2?)] = [(1, Rect(x: 100, y: 100, width: 80, height: 240), Vec2(140, 120))]
    #expect(HitTest.target(at: Vec2(150, 125), boxes: b) == HitTarget(id: 1, isHead: true))
    #expect(HitTest.target(at: Vec2(140, 250), boxes: b) == HitTarget(id: 1, isHead: false))
    #expect(HitTest.target(at: Vec2(10, 10), boxes: b) == nil)
}

@Test func headHitFallsBackToTopOfBox() {
    let b: [(id: Int, box: Rect, head: Vec2?)] = [(1, Rect(x: 0, y: 0, width: 100, height: 100), nil)]
    #expect(HitTest.target(at: Vec2(50, 10), boxes: b)?.isHead == true)
    #expect(HitTest.target(at: Vec2(50, 60), boxes: b)?.isHead == false)
}

@Test func overlappingBoxesPickSmallest() {
    let b: [(id: Int, box: Rect, head: Vec2?)] = [
        (1, Rect(x: 0, y: 0, width: 300, height: 600), nil),
        (2, Rect(x: 100, y: 200, width: 50, height: 100), nil),
    ]
    #expect(HitTest.target(at: Vec2(120, 250), boxes: b)?.id == 2)
}

@Test func bodyDamageInRange() {
    let g = GameEngine(seed: 1)
    g.sync([track(1)], at: 0, naturalHealth: false)
    let e = g.shoot(HitTarget(id: 1, isHead: false), distance: 3, at: 0.1)!
    #expect((18...34).contains(e.amount) && !e.isHeadshot && !e.killed)
    #expect(g.status(1)!.hp == 100 - Float(e.amount))
}

@Test func headshotKillsAndFeeds() {
    let g = GameEngine(seed: 1)
    g.sync([track(1)], at: 0, naturalHealth: false)
    let e = g.shoot(HitTarget(id: 1, isHead: true), distance: 4, at: 0.1)!
    #expect(e.killed && e.isHeadshot && e.amount == 100)
    #expect(g.killFeed.count == 1 && g.killFeed[0].isHeadshot && g.killFeed[0].distance == 4)
    #expect(g.killFeed[0].victim == NameGenerator.identity(for: 1).name)
    #expect(g.status(1)!.isEliminated && g.status(1)!.hp == 0)
}

@Test func shootingUnknownTrackIsIgnored() {
    let g = GameEngine(seed: 1)
    #expect(g.shoot(HitTarget(id: 9, isHead: true), distance: 4, at: 0) == nil)
}

@Test func tentativeTracksGetNoStatus() {
    let g = GameEngine(seed: 1)
    var t = track(1); t.state = .tentative
    g.sync([t], at: 0, naturalHealth: false)
    #expect(g.status(1) == nil)
}

@Test func shootingEliminatedIsIgnored() {
    let g = GameEngine(seed: 1)
    g.sync([track(1)], at: 0, naturalHealth: false)
    _ = g.shoot(HitTarget(id: 1, isHead: true), distance: 4, at: 0.1)
    #expect(g.shoot(HitTarget(id: 1, isHead: true), distance: 4, at: 0.2) == nil && g.killFeed.count == 1)
}

@Test func respawnsAfterFiveSeconds() {
    let g = GameEngine(seed: 1)
    g.sync([track(1)], at: 0, naturalHealth: false)
    _ = g.shoot(HitTarget(id: 1, isHead: true), distance: 4, at: 1)
    g.sync([track(1)], at: 5.9, naturalHealth: false)
    #expect(g.status(1)!.isEliminated)
    g.sync([track(1)], at: 6.1, naturalHealth: false)
    #expect(g.status(1)!.hp == 100 && !g.status(1)!.isEliminated)
}

@Test func drainStopsAtFloor() {
    let g = GameEngine(seed: 1)
    g.sync([track(1, speed: 2)], at: 0, naturalHealth: true)
    for i in 1...300 { g.sync([track(1, speed: 2)], at: Double(i) * 0.1, naturalHealth: true) }
    #expect(g.status(1)!.hp == 10)
}

@Test func regenWaitsThreeSecondsAfterDamage() {
    let g = GameEngine(seed: 1)
    g.sync([track(1)], at: 0, naturalHealth: true)
    _ = g.shoot(HitTarget(id: 1, isHead: false), distance: 3, at: 1)
    let hp = g.status(1)!.hp
    g.sync([track(1)], at: 3.5, naturalHealth: true)
    #expect(g.status(1)!.hp == hp)   // 2.5 s after the hit: no regen yet
    g.sync([track(1)], at: 4.5, naturalHealth: true)
    #expect(g.status(1)!.hp > hp)
}

@Test func regenNeverExceedsMax() {
    let g = GameEngine(seed: 1)
    g.sync([track(1)], at: 0, naturalHealth: true)
    g.sync([track(1)], at: 100, naturalHealth: true)
    #expect(g.status(1)!.hp == 100)
}

@Test func noNaturalHealthWhenDisabled() {
    let g = GameEngine(seed: 1)
    g.sync([track(1, speed: 2)], at: 0, naturalHealth: false)
    g.sync([track(1, speed: 2)], at: 10, naturalHealth: false)
    #expect(g.status(1)!.hp == 100)
}

@Test func killFeedSurvivesTrackRemoval() {
    let g = GameEngine(seed: 1)
    g.sync([track(1)], at: 0, naturalHealth: false)
    _ = g.shoot(HitTarget(id: 1, isHead: true), distance: 4, at: 0.1)
    g.sync([], at: 1, naturalHealth: false)
    #expect(g.status(1) == nil && g.killFeed.count == 1)
    g.sync([], at: 7, naturalHealth: false)
    #expect(g.killFeed.isEmpty)
}

@Test func killFeedKeepsNewestFour() {
    let g = GameEngine(seed: 1)
    g.sync((1...6).map { track($0) }, at: 0, naturalHealth: false)
    for id in 1...6 { _ = g.shoot(HitTarget(id: id, isHead: true), distance: 2, at: 0.1) }
    #expect(g.killFeed.count == 4)
    #expect(g.killFeed.map(\.victim) == (3...6).map { NameGenerator.identity(for: $0).name })
}

@Test func sameSeedSameDamage() {
    func roll() -> Int {
        let g = GameEngine(seed: 7)
        g.sync([track(1)], at: 0, naturalHealth: false)
        return g.shoot(HitTarget(id: 1, isHead: false), distance: 3, at: 0.1)!.amount
    }
    #expect(roll() == roll())
}
