import Testing
@testable import ESPCore

private func det(_ x: Float, _ y: Float = 0.3, world: Vec3? = nil, distance: Float = 3) -> Detection {
    Detection(box: Rect(x: x, y: y, width: 0.1, height: 0.4), joints: [:], worldPosition: world,
              distance: distance, distanceIsEstimated: false, heightMeters: 1.7, yaw: 0, occlusion: .visible)
}

@Test func confirmsAfterThreeHits() {
    let t = Tracker()
    #expect(t.update([det(0.2)], at: 0).isEmpty)
    #expect(t.update([det(0.2)], at: 0.033).isEmpty)
    let r = t.update([det(0.2)], at: 0.066)
    #expect(r.count == 1 && r[0].state == .confirmed && r[0].id == 1)
}

@Test func tentativeMissingAFrameIsDropped() {
    let t = Tracker()
    t.update([det(0.2)], at: 0)
    t.update([], at: 0.033)
    t.update([det(0.2)], at: 0.066)
    t.update([det(0.2)], at: 0.1)
    let r = t.update([det(0.2)], at: 0.133)
    #expect(r.count == 1 && r[0].id == 2)
}

@Test func keepsIdWhileMoving() {
    let t = Tracker()
    for i in 0..<10 { t.update([det(0.2 + Float(i) * 0.01)], at: Double(i) / 30) }
    #expect(t.update([det(0.3)], at: 0.34).first?.id == 1)
}

@Test func oneToOneMatching() {
    let t = Tracker()
    for i in 0..<3 { t.update([det(0.2), det(0.26)], at: Double(i) / 30) }
    let r = t.update([det(0.21), det(0.25)], at: 0.1)
    #expect(r.count == 2 && Set(r.map(\.id)) == [1, 2])
}

@Test func losesThenForgets() {
    let t = Tracker()
    for i in 0..<3 { t.update([det(0.2)], at: Double(i) / 30) }
    #expect(t.update([], at: 0.5).first?.state == .confirmed)
    #expect(t.update([], at: 0.9).first?.state == .lost)
    #expect(t.update([], at: 11).isEmpty)
}

@Test func revivesLostByWorldPosition() {
    let t = Tracker()
    for i in 0..<3 { t.update([det(0.2, world: Vec3(0, 0, -3))], at: Double(i) / 30) }
    t.update([], at: 1.5)
    let r = t.update([det(0.7, world: Vec3(0.3, 0, -3))], at: 2)
    #expect(r.count == 1 && r.first?.id == 1 && r.first?.state == .confirmed)
}

@Test func capsAtEightTracks() {
    let t = Tracker()
    let many = (0..<10).map { det(Float($0) * 0.1, 0) }
    for i in 0..<3 { t.update(many, at: Double(i) / 30) }
    #expect(t.update(many, at: 0.1).count == 8)
}

@Test func sortsConfirmedByDistanceBeforeLost() {
    let t = Tracker()
    for i in 0..<3 { t.update([det(0.1, distance: 6), det(0.5, distance: 2), det(0.8, distance: 4)], at: Double(i) / 30) }
    t.update([det(0.1, distance: 6), det(0.5, distance: 2)], at: 0.5)
    let r = t.update([det(0.1, distance: 6), det(0.5, distance: 2)], at: 1.0)
    #expect(r.map(\.distance) == [2, 6, 4] && r.last?.state == .lost)
}

@Test func velocityFromWorldMotion() {
    let t = Tracker()
    var last: [Track] = []
    for i in 0..<30 { last = t.update([det(0.2, world: Vec3(Float(i) / 30, 0, -3))], at: Double(i) / 30) }
    #expect(last[0].speed > 0.5 && last[0].speed < 1.5)  // walking ~1 m/s, filtered
}
