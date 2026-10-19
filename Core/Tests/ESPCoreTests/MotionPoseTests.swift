import Foundation
import Testing
@testable import ESPCore

/// CoreMotion-style rows for a device → reference rotation given as columns (device axes in reference
/// coordinates). `transposed` gives the rows of the reference → device matrix instead (its rows are those columns).
private func rows(deviceToReference c: (Vec3, Vec3, Vec3), transposed: Bool) -> (Vec3, Vec3, Vec3) {
    transposed ? c : (Vec3(c.0.x, c.1.x, c.2.x), Vec3(c.0.y, c.1.y, c.2.y), Vec3(c.0.z, c.1.z, c.2.z))
}

private func near(_ a: Mat4, _ b: Mat4) -> Bool {
    let d = [a.columns.0 - b.columns.0, a.columns.1 - b.columns.1, a.columns.2 - b.columns.2, a.columns.3 - b.columns.3]
    return d.allSatisfy { v in (0..<4).allSatisfy { abs(v[$0]) < 1e-5 } }
}

private func axis(_ c: Vec4) -> Vec3 { Vec3(c.x, c.y, c.z) }

/// Phone upright in landscapeRight (top of the phone on the left), back camera looking along reference +Y.
private let upright = (Vec3(0, 0, 1), Vec3(-1, 0, 0), Vec3(0, -1, 0))
private let uprightGravity = Vec3(-1, 0, 0)

@Test func uprightLandscapeIsARKitStartPose() {
    for transposed in [false, true] {
        let r = rows(deviceToReference: upright, transposed: transposed)
        let convention = MotionPose.convention(attitudeRows: r, gravity: uprightGravity)
        #expect(convention == (transposed ? .referenceToDevice : .deviceToReference))
        #expect(near(MotionPose.cameraToWorld(attitudeRows: r, convention: convention!), .identity))
    }
}

@Test func panningRightLooksTowardWorldPlusX() {
    // Same posture turned 90° right: the camera now looks along reference +X.
    let turned = (Vec3(0, 0, 1), Vec3(0, 1, 0), Vec3(-1, 0, 0))
    let m = MotionPose.cameraToWorld(attitudeRows: rows(deviceToReference: turned, transposed: true), convention: .referenceToDevice)
    #expect(length(-axis(m.columns.2) - Vec3(1, 0, 0)) < 1e-5)
    #expect(length(axis(m.columns.1) - Vec3(0, 1, 0)) < 1e-5)  // image up stays world up
}

@Test func tiltedDownLooksBelowHorizon() {
    // Upright pose pitched 30° down: camera forward dips below the horizon.
    let a: Float = .pi / 6
    let tilted = (Vec3(0, sinf(a), cosf(a)), Vec3(-1, 0, 0), Vec3(0, -cosf(a), sinf(a)))
    let gravity = Vec3(-cosf(a), 0, -sinf(a))
    let r = rows(deviceToReference: tilted, transposed: true)
    #expect(MotionPose.convention(attitudeRows: r, gravity: gravity) == .referenceToDevice)
    let m = MotionPose.cameraToWorld(attitudeRows: r, convention: .referenceToDevice)
    #expect(abs(-axis(m.columns.2).y - (-sinf(a))) < 1e-5)
}

@Test func ambiguousAttitudeGivesNoConvention() {
    // Rows and columns put "up" in the same place: the readings can't be told apart.
    #expect(MotionPose.convention(attitudeRows: (Vec3(1, 0, 0), Vec3(0, 1, 0), Vec3(0, 0, 1)), gravity: Vec3(0, 0, -1)) == nil)
}

@Test func intrinsicsFromFieldOfView() {
    let k = MotionPose.intrinsics(horizontalFOVDegrees: 90, imageSize: Vec2(1920, 1440))
    #expect(abs(k.fx - 960) < 0.01 && k.fx == k.fy && k.cx == 960 && k.cy == 720)
}

// MARK: Distance without depth

@Test func standingPersonUsesBoxHeight() {
    let d = SpatialMath.estimatedDistance(boxHeight: 600, boxWidth: 200, torso: 150, clipped: false, fy: 1000, kind: .person)
    #expect(abs(d - 1000 * 1.7 / 600) < 1e-4)
}

@Test func clippedOrSittingPersonUsesTorso() {
    let clipped = SpatialMath.estimatedDistance(boxHeight: 300, boxWidth: 200, torso: 250, clipped: true, fy: 1000, kind: .person)
    #expect(abs(clipped - 2) < 1e-4)
    let sitting = SpatialMath.estimatedDistance(boxHeight: 300, boxWidth: 250, torso: 125, clipped: false, fy: 1000, kind: .person)
    #expect(abs(sitting - 4) < 1e-4)
}

@Test func animalsUseTheirOwnSize() {
    let cat = SpatialMath.estimatedDistance(boxHeight: 100, boxWidth: 150, torso: nil, clipped: false, fy: 1000, kind: .animal(.cat))
    #expect(abs(cat - 3) < 1e-4)
}

// MARK: Readouts

@Test func readoutFormats() {
    #expect(Readout.distance(2.34, estimated: false) == "2.3 m")
    #expect(Readout.distance(12.6, estimated: true) == "~13 m")
    #expect(Readout.speed(0.2) == "0 km/h")
    #expect(Readout.speed(1.4) == "5.0 km/h")
    #expect(Readout.speed(5) == "18 km/h")
    #expect(Readout.clock(42) == "00:42")
    #expect(Readout.clock(3725) == "62:05")
}
