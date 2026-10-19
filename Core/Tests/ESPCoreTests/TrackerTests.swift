import Testing
@testable import ESPCore

private func det(_ x: Float, _ y: Float = 0.3, world: Vec3? = nil, distance: Float = 3,
                 kind: EntityKind = .person) -> Detection {
    Detection(box: Rect(x: x, y: y, width: 0.1, height: 0.4), kind: kind, confidence: 0.9, joints: [:], worldPosition: world,
              distance: distance, distanceIsEstimated: false, heightMeters: 1.7, yaw: 0, occlusion: .visible)
}

@Test func animalTracksSurviveFramesWithoutObjectPass() {
    // Animals come from the slower object model: frames without that pass must not age or drop them.
    let t = Tracker()
    var r: [Track] = []
    for i in 0..<9 {
        let objectPass = i.isMultiple(of: 3)
        r = t.update(objectPass ? [det(0.6, kind: .animal(.cat))] : [], at: Double(i) / 30, animalsObserved: objectPass)
    }
    #expect(r.contains { $0.kind == .animal(.cat) && $0.state == .confirmed })
}

@Test func differentKindsNeverMatch() {
    let t = Tracker()
    for i in 0..<3 { t.update([det(0.2)], at: Double(i) / 30) }
    for i in 3..<6 { t.update([det(0.2, kind: .animal(.dog))], at: Double(i) / 30) }
    let r = t.update([det(0.2, kind: .animal(.dog))], at: 0.3)
    #expect(r.contains { $0.kind == .animal(.dog) && $0.id != 1 })
    #expect(!r.contains { $0.id == 1 && $0.kind != .person })
}

@Test func confirmsAfterThreeHits() {
    let t = Tracker()
    #expect(t.update([det(0.2)], at: 0).isEmpty)
    #expect(t.update([det(0.2)], at: 0.033).isEmpty)
    let r = t.update([det(0.2)], at: 0.066)
    #expect(r.count == 1 && r[0].state == .confirmed && r[0].id == 1)
}

@Test func tentativeSurvivesAMissedFrame() {
    // At 60 Hz a borderline detection flickers; one miss must not restart the track.
    let t = Tracker()
    t.update([det(0.2)], at: 0)
    t.update([], at: 1.0 / 60)
    t.update([det(0.2)], at: 2.0 / 60)
    let r = t.update([det(0.2)], at: 3.0 / 60)
    #expect(r.count == 1 && r[0].id == 1 && r[0].state == .confirmed)
}

@Test func tentativeMissingLongerThanGraceIsDropped() {
    let t = Tracker()
    t.update([det(0.2)], at: 0)
    t.update([], at: 0.15)
    t.update([det(0.2)], at: 0.2)
    t.update([det(0.2)], at: 0.233)
    let r = t.update([det(0.2)], at: 0.266)
    #expect(r.count == 1 && r[0].id == 2)
}

@Test func confirmsWithinFiftyMillisecondsAt60Hz() {
    let t = Tracker()
    for i in 0..<2 { #expect(t.update([det(0.2)], at: Double(i) / 60).isEmpty) }
    #expect(t.update([det(0.2)], at: 2.0 / 60).first?.state == .confirmed)
}

@Test func farPersonAtModerateScoreStartsTrack() {
    let t = Tracker()
    var r: [Track] = []
    for i in 0..<3 { r = t.update([scored(0.2, 0.45)], at: Double(i) / 60) }
    #expect(r.count == 1 && r[0].state == .confirmed)
}

@Test func firstSeenIsKeptAcrossUpdates() {
    let t = Tracker()
    var r: [Track] = []
    for i in 0..<20 { r = t.update([det(0.2)], at: 5 + Double(i) / 30) }
    #expect(r[0].firstSeen == 5)
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
    #expect(t.update([], at: 0.4).first?.state == .confirmed)
    #expect(t.update([], at: 0.7).first?.state == .lost)
    #expect(t.update([], at: 11).isEmpty)
}

@Test func revivesLostByWorldPosition() {
    let t = Tracker()
    for i in 0..<3 { t.update([det(0.2, world: Vec3(0, 0, -3))], at: Double(i) / 30) }
    t.update([], at: 1.5)
    let r = t.update([det(0.7, world: Vec3(0.3, 0, -3))], at: 2)
    #expect(r.count == 1 && r.first?.id == 1 && r.first?.state == .confirmed)
}

@Test func capsAtMaxTracks() {
    var config = TrackerConfig()
    config.maxTracks = 8
    let t = Tracker(config: config)
    let many = (0..<10).map { det(Float($0) * 0.1, 0) }
    for i in 0..<3 { t.update(many, at: Double(i) / 30) }
    #expect(t.update(many, at: 0.1).count == 8)
    #expect(TrackerConfig().maxTracks == 30)
}

private func scored(_ x: Float, _ confidence: Float) -> Detection {
    var d = det(x)
    d.confidence = confidence
    return d
}

@Test func lowConfidenceKeepsTrackAlive() {
    let t = Tracker()
    for i in 0..<3 { t.update([det(0.2)], at: Double(i) / 30) }
    var r: [Track] = []
    for i in 3..<33 { r = t.update([scored(0.2, 0.3)], at: Double(i) / 30) }  // a full second of weak detections
    #expect(r.count == 1 && r[0].id == 1 && r[0].state == .confirmed)
}

@Test func middlingConfidenceNeedsMoreHits() {
    // A half-hidden person scoring 0.3: no box after 6 hits, a box after 8.
    let t = Tracker()
    var r: [Track] = []
    for i in 0..<6 { r = t.update([scored(0.2, 0.3)], at: Double(i) / 60) }
    #expect(r.isEmpty)
    for i in 6..<8 { r = t.update([scored(0.2, 0.3)], at: Double(i) / 60) }
    #expect(r.count == 1 && r[0].state == .confirmed)
}

@Test func veryWeakDetectionsNeverStartTracks() {
    let t = Tracker()
    var r: [Track] = []
    for i in 0..<30 { r = t.update([scored(0.2, 0.2)], at: Double(i) / 60) }
    #expect(r.isEmpty)
}

@Test func aConfidentHitSpeedsUpASlowTrack() {
    let t = Tracker()
    t.update([scored(0.2, 0.3)], at: 0)
    t.update([scored(0.2, 0.6)], at: 1.0 / 60)
    let r = t.update([scored(0.2, 0.3)], at: 2.0 / 60)
    #expect(r.count == 1 && r[0].state == .confirmed)
}

@Test func veryLowConfidenceIsIgnored() {
    let t = Tracker()
    for i in 0..<3 { t.update([det(0.2)], at: Double(i) / 30) }
    let r = t.update([scored(0.2, 0.05)], at: 1.0)
    #expect(r.first?.state == .lost)
}

@Test func predictionBridgesMissedFrames() {
    // Fast mover: 0.02 per frame; after 3 missed frames the stale box barely overlaps, the predicted one does.
    let t = Tracker()
    for i in 0..<10 { t.update([det(0.1 + Float(i) * 0.02)], at: Double(i) / 30) }
    for i in 10..<13 { t.update([], at: Double(i) / 30) }
    let r = t.update([det(0.1 + 13 * 0.02)], at: 13.0 / 30)
    #expect(r.count == 1 && r[0].id == 1)
}

@Test func crossingPeopleKeepIds() {
    let t = Tracker()
    var r: [Track] = []
    for i in 0..<50 {
        let a = det(0.1 + Float(i) * 0.01)   // walks right
        let b = det(0.6 - Float(i) * 0.01)   // walks left
        r = t.update(i < 1 ? [a] : [a, b], at: Double(i) / 30)
    }
    let rightWalker = r.first { $0.id == 1 }
    let leftWalker = r.first { $0.id == 2 }
    #expect(rightWalker != nil && leftWalker != nil)
    #expect(rightWalker!.box.x > 0.5 && leftWalker!.box.x < 0.2)
}

@Test func predictedWorldExtrapolatesAndClamps() {
    let track = Track(id: 1, state: .confirmed, box: Rect(x: 0, y: 0, width: 0.1, height: 0.1), kind: .person, confidence: 1,
                      joints: [:], worldPosition: Vec3(0, 0, -3), velocity: Vec3(1, 0, 0), distance: 3,
                      distanceIsEstimated: false, heightMeters: 1.7, yaw: 0, occlusion: .visible, hits: 3, lastSeen: 1)
    #expect(abs(track.predictedWorld(at: 1.1)!.x - 0.1) < 1e-5)
    #expect(abs(track.predictedWorld(at: 5)!.x - 0.3) < 1e-5)
    #expect(track.predictedWorld(at: 0.5)! == Vec3(0, 0, -3))
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

// MARK: Fast movers

private func rider(_ x: Float, confidence: Float = 0.8) -> Detection {
    Detection(box: Rect(x: x, y: 0.4, width: 0.05, height: 0.15), kind: .person, confidence: confidence, joints: [:],
              worldPosition: nil, distance: 12, distanceIsEstimated: true, heightMeters: 1.7, yaw: 0, occlusion: .visible)
}

@Test func fastRiderConfirmsAndKeepsOneId() {
    // A far rider moving more than a box width per frame on a hot phone (20 Hz): boxes never overlap.
    let t = Tracker()
    var r: [Track] = []
    for i in 0..<12 { r = t.update([rider(0.05 + Float(i) * 0.06)], at: Double(i) / 20) }
    #expect(r.count == 1 && r[0].id == 1 && r[0].state == .confirmed)
    #expect(r[0].box.x > 0.65)
}

@Test func withoutFastMatchingTheRiderNeverConfirms() {
    // The same rider with the fast stage off: every frame starts a new tentative track.
    var config = TrackerConfig()
    config.fastReach = 0
    let t = Tracker(config: config)
    var r: [Track] = []
    for i in 0..<12 { r = t.update([rider(0.05 + Float(i) * 0.06)], at: Double(i) / 20) }
    #expect(r.isEmpty)
}

@Test func confirmedTrackIsNotHandedToSomeoneNearby() {
    let t = Tracker()
    for i in 0..<3 { t.update([det(0.2)], at: Double(i) / 30) }
    var r: [Track] = []
    for i in 3..<6 { r = t.update([det(0.32)], at: Double(i) / 30) }   // person 1 hidden, someone new beside them
    let newcomer = r.first { abs($0.box.x - 0.32) < 0.02 }
    #expect(newcomer != nil && newcomer?.id != 1)
    #expect(r.contains { $0.id == 1 && abs($0.box.x - 0.2) < 0.02 })
}

@Test func differentSizedBoxesDontCountAsTheSameFastMover() {
    let t = Tracker()
    t.update([rider(0.1)], at: 0)
    var big = rider(0.18)
    big.box.height = 0.4
    t.update([big], at: 0.05)
    t.update([big], at: 0.1)
    let r = t.update([big], at: 0.15)
    #expect(r.count == 1 && r[0].id == 2)
}

@Test func guessedDistanceJitterDoesNotLookLikeWalking() {
    // Standing still at ~3 m with no depth: the guess jumps ±25 cm along the view ray every frame.
    var rng = SplitMix64(seed: 7)
    let t = Tracker()
    var speeds: [Float] = []
    for i in 0..<120 {
        var d = det(0.4, world: Vec3(0, 0, -3 + Float.random(in: -0.25...0.25, using: &rng)))
        d.distanceIsEstimated = true
        if let track = t.update([d], at: Double(i) / 60).first, i > 30 { speeds.append(track.floorSpeed) }
    }
    #expect(speeds.reduce(0, +) / Float(speeds.count) < 0.3)   // reads as 0 km/h
}
