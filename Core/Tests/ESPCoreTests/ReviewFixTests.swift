import Foundation
import Testing
@testable import ESPCore

// MARK: Vision results → captured-image coordinates (Critical #1)

@Test func uprightVisionPointFlipsY() {
    #expect(VisionMapping.point(Vec2(0.2, 0.3), orientation: .up) == Vec2(0.2, 0.7))
}

@Test func upsideDownVisionPointFlipsX() {
    // Image analysed rotated 180°: bottom-left Vision coords map to (1 − x, y) in the captured image.
    #expect(VisionMapping.point(Vec2(0.2, 0.3), orientation: .down) == Vec2(0.8, 0.3))
}

@Test func uprightVisionRect() {
    let r = VisionMapping.rect(Rect(x: 0.1, y: 0.2, width: 0.3, height: 0.4), orientation: .up)
    #expect(abs(r.x - 0.1) < 1e-6 && abs(r.y - 0.4) < 1e-6 && r.width == 0.3 && r.height == 0.4)
}

@Test func upsideDownVisionRect() {
    let r = VisionMapping.rect(Rect(x: 0.1, y: 0.2, width: 0.3, height: 0.4), orientation: .down)
    #expect(abs(r.x - 0.6) < 1e-6 && abs(r.y - 0.2) < 1e-6 && r.width == 0.3 && r.height == 0.4)
}

// MARK: Per-detection camera lookup (Important #2)

@Test func historyReturnsValueStoredAtThatTime() {
    var h = TimedHistory<String>(keep: 1.0)
    h.insert("a", at: 1.0)
    h.insert("b", at: 1.033)
    h.insert("c", at: 1.066)
    #expect(h.value(at: 1.033) == "b")
    #expect(h.latest == "c")
}

@Test func historyFallsBackToNearestOlder() {
    var h = TimedHistory<String>(keep: 1.0)
    h.insert("a", at: 1.0)
    h.insert("b", at: 2.0)
    #expect(h.value(at: 1.5) == "a")
    #expect(h.value(at: 0.5) == "a")  // older than anything kept: oldest available
}

@Test func historyDropsOldEntries() {
    var h = TimedHistory<String>(keep: 1.0)
    h.insert("a", at: 1.0)
    h.insert("b", at: 2.5)
    #expect(h.count == 1 && h.value(at: 1.0) == "b")
}

// MARK: Perception rate gate (Important #3)

@Test func gateHitsTargetRateOn60fpsInput() {
    var gate = FrameGate()
    var rng = SplitMix64(seed: 3)
    var runs = 0
    for i in 0..<600 {  // 10 s of 60 fps with random ±1 ms timestamp jitter
        let jitter = Double(rng.next() % 2001) / 1_000_000 - 0.001
        if gate.shouldRun(at: Double(i) / 60 + jitter, hz: 30) { runs += 1 }
    }
    #expect(runs >= 290 && runs <= 301)
}

@Test func gateHoldsBackFasterFrames() {
    var gate = FrameGate()
    let first = gate.shouldRun(at: 0, hz: 10)
    let early = gate.shouldRun(at: 0.05, hz: 10)
    let onTime = gate.shouldRun(at: 0.1, hz: 10)
    #expect(first && !early && onTime)
}

// MARK: 3D box stability (Important #6)

private func det(yaw: Float, height: Float = 1.7) -> Detection {
    Detection(box: Rect(x: 0.2, y: 0.3, width: 0.1, height: 0.4), kind: .person, confidence: 0.9, joints: [:], worldPosition: Vec3(0, 0, -3),
              distance: 3, distanceIsEstimated: false, heightMeters: height, yaw: yaw, occlusion: .visible)
}

@Test func trackerSmoothsYawJitter() {
    let t = Tracker()
    var last: [Track] = []
    for i in 0..<30 { last = t.update([det(yaw: i.isMultiple(of: 2) ? 0.4 : -0.4)], at: Double(i) / 30) }
    #expect(abs(last[0].yaw) < 0.2)
}

@Test func trackerYawSmoothingWrapsAroundPi() {
    let t = Tracker()
    var last: [Track] = []
    for i in 0..<30 { last = t.update([det(yaw: i.isMultiple(of: 2) ? 3.1 : -3.1)], at: Double(i) / 30) }
    #expect(abs(abs(last[0].yaw) - 3.14) < 0.1)  // stays near ±π, never averages through 0
}

@Test func trackerSmoothsHeight() {
    let t = Tracker()
    var last: [Track] = []
    for i in 0..<30 { last = t.update([det(yaw: 0, height: i.isMultiple(of: 2) ? 1.9 : 1.5)], at: Double(i) / 30) }
    #expect(abs(last[0].heightMeters - 1.7) < 0.1)
}

@Test func shoulderDepthFarFromTorsoIsDistrusted() {
    #expect(SpatialMath.trustedDepth(5.0, near: 3.0) == 3.0)
    #expect(SpatialMath.trustedDepth(3.2, near: 3.0) == 3.2)
    #expect(SpatialMath.trustedDepth(nil, near: 3.0) == 3.0)
}

