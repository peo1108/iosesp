import Testing
@testable import ESPCore

private func track(_ id: Int, _ joints: [Joint: Vec2], kind: EntityKind = .person, at time: Double) -> Track {
    Track(id: id, state: .confirmed, box: Rect(x: 0.36, y: 0.18, width: 0.28, height: 0.74), kind: kind, confidence: 0.9,
          joints: joints, worldPosition: Vec3(0, 0, -3), velocity: .zero, distance: 3, distanceIsEstimated: false,
          heightMeters: 1.7, yaw: 0, occlusion: .visible, hits: 5, lastSeen: time)
}

private func label(_ t: Track) -> String {
    t.kind.isPerson ? "Người 0\(t.id)" : "Chó 0\(t.id)"
}

private func flipped(_ joints: [Joint: Vec2]) -> [Joint: Vec2] {
    joints.mapValues { Vec2(1 - $0.x, 1 - $0.y) }
}

@Test func stabilizerHoldsForPointFourSeconds() {
    var s = Stabilizer<String>()
    #expect(s.update("a", at: 0) == "a")
    #expect(s.update("b", at: 0.1) == "a")
    #expect(s.update("b", at: 0.3) == "a")
    #expect(s.update("b", at: 0.51) == "b")
}

@Test func stabilizerFlickerResets() {
    var s = Stabilizer<String>()
    _ = s.update("a", at: 0)
    _ = s.update("b", at: 0.1)
    _ = s.update("a", at: 0.3)
    #expect(s.update("b", at: 0.45) == "a")   // candidate restarted at 0.45
    #expect(s.update("b", at: 0.86) == "b")
}

@Test func rulesWorkOnUpsideDownInput() {
    let tracker = ActivityTracker()
    let t = track(1, flipped(sittingSkeleton()), at: 0)
    let states = tracker.update(tracks: [t], objects: [], orientation: .down, label: label, at: 0)
    #expect(states[1]?.frame.posture == .sitting)
    #expect(states[1]?.frame.facing == .toward)
}

@Test func wavingDetectedFromOscillation() {
    let tracker = ActivityTracker()
    var last: [Int: ActivityState] = [:]
    for step in 0...14 {
        var s = standingSkeleton()
        s[.leftWrist] = Vec2(step.isMultiple(of: 2) ? 0.66 : 0.54, 0.26)  // above the shoulder, below the nose
        let time = Double(step) * 0.1
        last = tracker.update(tracks: [track(1, s, at: time)], objects: [], orientation: .up, label: label, at: time)
    }
    #expect(last[1]?.frame.gesture == .waving)
    #expect(last[1]?.mainText == "Vẫy tay")
}

@Test func steadyRaisedWristIsNotWaving() {
    let tracker = ActivityTracker()
    var last: [Int: ActivityState] = [:]
    for step in 0...14 {
        var s = standingSkeleton()
        s[.leftWrist] = Vec2(0.6, 0.26)
        let time = Double(step) * 0.1
        last = tracker.update(tracks: [track(1, s, at: time)], objects: [], orientation: .up, label: label, at: time)
    }
    #expect(last[1]?.frame.gesture == GestureKind.none)
}

@Test func eventsOnEnterSitAndRateLimit() {
    let tracker = ActivityTracker()
    func step(_ i: Int, _ joints: [Joint: Vec2]) {
        let time = Double(i) * 0.1
        _ = tracker.update(tracks: [track(1, joints, at: time)], objects: [], orientation: .up, label: label, at: time)
    }
    for i in 0..<25 { step(i, standingSkeleton()) }
    for i in 25..<31 { step(i, sittingSkeleton()) }   // sits at 2.5, stabilised at 2.9 → event
    for i in 31..<37 { step(i, standingSkeleton()) }  // stands at 3.1, stabilised at 3.5: within 2 s → suppressed
    #expect(tracker.events.map(\.text) == ["Người 01 vừa vào khung hình", "Người 01 ngồi xuống"])
}

@Test func eventsOnLeave() {
    let tracker = ActivityTracker()
    _ = tracker.update(tracks: [track(1, standingSkeleton(), at: 0)], objects: [], orientation: .up, label: label, at: 0)
    _ = tracker.update(tracks: [], objects: [], orientation: .up, label: label, at: 0.5)
    #expect(tracker.events.count == 1)
    _ = tracker.update(tracks: [], objects: [], orientation: .up, label: label, at: 2.6)
    #expect(tracker.events.last?.text == "Người 01 rời khung hình")
}

@Test func animalAppears() {
    let tracker = ActivityTracker()
    let states = tracker.update(tracks: [track(4, [:], kind: .animal(.dog), at: 0)], objects: [], orientation: .up,
                                label: label, at: 0)
    #expect(states[4] == nil)
    #expect(tracker.events.map(\.text) == ["🐕 Chó 04 xuất hiện"])
}

@Test func eventsExpireAndKeepFive() {
    let tracker = ActivityTracker()
    let people = (1...7).map { track($0, standingSkeleton(), at: 0) }
    _ = tracker.update(tracks: people, objects: [], orientation: .up, label: label, at: 0)
    #expect(tracker.events.count == 5)
    _ = tracker.update(tracks: people.map { var t = $0; t.lastSeen = 9; return t }, objects: [], orientation: .up,
                       label: label, at: 9)
    #expect(tracker.events.isEmpty)
}

@Test func firstSeenIsKept() {
    let tracker = ActivityTracker()
    _ = tracker.update(tracks: [track(1, standingSkeleton(), at: 3)], objects: [], orientation: .up, label: label, at: 3)
    let s = tracker.update(tracks: [track(1, standingSkeleton(), at: 10)], objects: [], orientation: .up, label: label, at: 10)
    #expect(s[1]?.firstSeen == 3)
}
