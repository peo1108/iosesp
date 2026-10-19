import Foundation
import Testing
@testable import ESPCore

private func label(_ t: Track) -> String { "Người 0\(t.id)" }

private func personTrack(_ joints: [Joint: Vec2], at time: Double, velocity: Vec3 = .zero) -> Track {
    Track(id: 1, state: .confirmed, box: Rect(x: 0.3, y: 0.3, width: 0.4, height: 0.5), kind: .person, confidence: 0.9,
          joints: joints, worldPosition: Vec3(0, 0, -3), velocity: velocity, distance: 3, distanceIsEstimated: false,
          heightMeters: 1.7, yaw: 0, occlusion: .visible, hits: 5, lastSeen: time)
}

// MARK: Important 1 — rules must measure in square units, not 4:3-squashed ones

@Test func recliningSixtyTwoDegreesInRealPixelsIsLying() {
    // Built in 1920×1440 camera pixels, then normalized per axis like real detections.
    let hip = Vec2(960, 900), torso: Float = 300, tilt: Float = 62 * .pi / 180
    let shoulder = hip + Vec2(sinf(tilt), -cosf(tilt)) * torso
    let across = Vec2(cosf(tilt), sinf(tilt)) * 40   // shoulder/hip width, perpendicular to the torso
    func n(_ p: Vec2) -> Vec2 { p / Vec2(1920, 1440) }
    let joints: [Joint: Vec2] = [
        .leftShoulder: n(shoulder + across), .rightShoulder: n(shoulder - across),
        .leftHip: n(hip + across), .rightHip: n(hip - across),
    ]
    let states = ActivityTracker().update(tracks: [personTrack(joints, at: 0)], objects: [], orientation: .up,
                                          label: label, at: 0)
    #expect(states[1]?.frame.posture == .lying)
}

// MARK: Important 2 — depth jitter must not make a standing person "walk"

@Test func noisyStandingPersonStaysStill() {
    var rng = SplitMix64(seed: 11)
    func noise() -> Float {  // ≈ N(0, 5 cm): sum of three uniforms
        (0..<3).map { _ in Float(rng.next() % 10_001) / 10_000 * 0.174 - 0.087 }.reduce(0, +)
    }
    let tracker = Tracker(), activity = ActivityTracker()
    var walkingFrames = 0
    for i in 0..<120 {
        let t = Double(i) / 30
        let d = Detection(box: Rect(x: 0.36, y: 0.18, width: 0.28, height: 0.74), kind: .person, confidence: 0.9,
                          joints: standingSkeleton(), worldPosition: Vec3(noise(), 0, -3 + noise()), distance: 3,
                          distanceIsEstimated: false, heightMeters: 1.7, yaw: 0, occlusion: .visible)
        let tracks = tracker.update([d], at: t).filter { $0.state == .confirmed }
        let states = activity.update(tracks: tracks, objects: [], orientation: .up, label: label, at: t)
        if t > 1, let s = states.values.first, s.frame.motion != .still { walkingFrames += 1 }
    }
    #expect(walkingFrames == 0)
}

@Test func walkingPersonStillReadsWalking() {
    let tracker = Tracker(), activity = ActivityTracker()
    var last: ActivityState?
    for i in 0..<60 {
        let t = Double(i) / 30
        let d = Detection(box: Rect(x: 0.36, y: 0.18, width: 0.28, height: 0.74), kind: .person, confidence: 0.9,
                          joints: standingSkeleton(), worldPosition: Vec3(Float(t), 0, -3), distance: 3,
                          distanceIsEstimated: false, heightMeters: 1.7, yaw: 0, occlusion: .visible)
        let tracks = tracker.update([d], at: t).filter { $0.state == .confirmed }
        last = activity.update(tracks: tracks, objects: [], orientation: .up, label: label, at: t).values.first
    }
    #expect(last?.frame.motion == .walking)
}

// MARK: Important 3 — a v1 preset loads as the v2 preset it names

@Test func v1RagePresetLoadsFullVIP() {
    let s = Settings.decodeOrDefault(#"{"preset":"rage","aimbot":true,"box":true,"boxStyle":"threeD","watermarkText":"hi","microphone":true}"#.data(using: .utf8))
    var expected = Settings.default
    expected.watermarkText = "hi"
    expected.microphone = true
    expected.apply(.vip)
    #expect(s == expected)
}

@Test func v1LegitPresetGetsLabel() {
    let s = Settings.decodeOrDefault(#"{"preset":"legit","box":true,"distance":true}"#.data(using: .utf8))
    #expect(s.preset == .legit && s.label && s.box && s.distance)
}

@Test func v1CustomSettingsKeepTheirFlags() {
    let s = Settings.decodeOrDefault(#"{"preset":"custom","box":true,"name":true}"#.data(using: .utf8))
    #expect(s.preset == .custom && s.box && s.label && !s.skeleton)
}

// MARK: Confirmed tracks match before tentative duplicates

private func det(_ x: Float, world: Vec3? = nil) -> Detection {
    Detection(box: Rect(x: x, y: 0.3, width: 0.1, height: 0.4), kind: .person, confidence: 0.9, joints: [:],
              worldPosition: world, distance: 3, distanceIsEstimated: false, heightMeters: 1.7, yaw: 0, occlusion: .visible)
}

@Test func confirmedTrackWinsOverTentativeDuplicate() {
    let t = Tracker()
    for i in 0..<3 { t.update([det(0.2)], at: Double(i) / 30) }
    t.update([det(0.2), det(0.205)], at: 3.0 / 30)          // a duplicate box spawns a tentative twin
    var r: [Track] = []
    for i in 4..<40 { r = t.update([det(0.205)], at: Double(i) / 30) }
    #expect(r.map(\.id) == [1] && r[0].state == .confirmed)
}

// MARK: Lost tracks revive where they would be by now

@Test func revivalUsesPredictedPosition() {
    let t = Tracker()
    for i in 0..<30 {   // walking +x at 1.2 m/s for a second
        let time = Double(i) / 30
        t.update([det(0.1 + Float(i) * 0.005, world: Vec3(1.2 * Float(time), 0, -4))], at: time)
    }
    for i in 30..<66 { t.update([], at: Double(i) / 30) }   // hidden for 1.2 s
    let back = 66.0 / 30
    let r = t.update([det(0.7, world: Vec3(1.2 * Float(back), 0, -4))], at: back)
    #expect(r.contains { $0.id == 1 && $0.state == .confirmed })
}

// MARK: Waving close to the camera, hips out of frame

@Test func wavingWithoutHips() {
    let tracker = ActivityTracker()
    var last: [Int: ActivityState] = [:]
    for step in 0...14 {
        var s = standingSkeleton()
        for j in [Joint.leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle] { s[j] = nil }
        s[.leftWrist] = Vec2(step.isMultiple(of: 2) ? 0.66 : 0.54, 0.26)
        let time = Double(step) * 0.1
        last = tracker.update(tracks: [personTrack(s, at: time)], objects: [], orientation: .up, label: label, at: time)
    }
    #expect(last[1]?.frame.gesture == .waving)
}
