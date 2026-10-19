import Testing
@testable import ESPCore

@Test func filterPassesConstantSignal() {
    var f = OneEuroFilter<Vec2>()
    for i in 0..<10 { _ = f.filter(Vec2(1, 2), at: Double(i) / 30) }
    #expect(f.filter(Vec2(1, 2), at: 0.4) == Vec2(1, 2))
}

@Test func filterSmoothsJitter() {
    var f = OneEuroFilter<Vec2>()
    _ = f.filter(Vec2(0, 0), at: 0)
    let y = f.filter(Vec2(1, 0), at: 1.0 / 30)
    #expect(y.x > 0 && y.x < 1)
}

@Test func filterFollowsFastMotionCloserThanSlow() {
    // beta makes the cutoff rise with speed: a big jump is tracked more closely than a small one, relatively.
    var slow = OneEuroFilter<Vec2>(), fast = OneEuroFilter<Vec2>()
    _ = slow.filter(Vec2(0, 0), at: 0); _ = fast.filter(Vec2(0, 0), at: 0)
    let s = slow.filter(Vec2(0.01, 0), at: 1.0 / 30).x / 0.01
    let f = fast.filter(Vec2(100, 0), at: 1.0 / 30).x / 100
    #expect(f > s)
}

@Test func nonIncreasingTimeReturnsLastOutput() {
    var f = OneEuroFilter<Vec2>()
    let a = f.filter(Vec2(1, 1), at: 1)
    #expect(f.filter(Vec2(5, 5), at: 1) == a)
}

@Test func resetForgetsHistory() {
    var f = OneEuroFilter<Vec2>()
    _ = f.filter(Vec2(0, 0), at: 0)
    f.reset()
    #expect(f.filter(Vec2(3, 3), at: 0.1) == Vec2(3, 3))
}
