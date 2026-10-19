import Testing
@testable import ESPCore

private let K = CameraIntrinsics(fx: 1000, fy: 1000, cx: 960, cy: 720, imageSize: Vec2(1920, 1440))

@Test func centerPixelUnprojectsStraightAhead() {
    let p = SpatialMath.unproject(pixel: Vec2(960, 720), depth: 3, intrinsics: K, cameraToWorld: .identity)
    #expect(p == Vec3(0, 0, -3))
}

@Test func pixelBelowCenterIsBelowInWorld() {
    let p = SpatialMath.unproject(pixel: Vec2(960, 1220), depth: 2, intrinsics: K, cameraToWorld: .identity)
    #expect(abs(p.y - (-1)) < 1e-5)
}

@Test func projectRoundTrips() {
    let cam = Mat4.translation(Vec3(0.3, 1.4, 2)) * Mat4.rotationY(0.4)
    let w = SpatialMath.unproject(pixel: Vec2(400, 300), depth: 5, intrinsics: K, cameraToWorld: cam)
    let px = SpatialMath.project(world: w, intrinsics: K, cameraToWorld: cam)!
    #expect(abs(px.x - 400) < 0.01 && abs(px.y - 300) < 0.01)
}

@Test func behindCameraProjectsNil() {
    #expect(SpatialMath.project(world: Vec3(0, 0, 1), intrinsics: K, cameraToWorld: .identity) == nil)
}

@Test func cameraSpaceOfTranslatedCamera() {
    let cam = Mat4.translation(Vec3(0, 0, 5))
    #expect(SpatialMath.cameraSpace(world: Vec3(0, 0, 2), cameraToWorld: cam) == Vec3(0, 0, -3))
}

@Test func scaledIntrinsics() {
    let s = K.scaled(to: Vec2(256, 192))
    #expect(abs(s.fx - 1000 * 256 / 1920) < 1e-3 && abs(s.cy - 720 * 192 / 1440) < 1e-3)
    #expect(s.imageSize == Vec2(256, 192))
}

@Test func medianIgnoresInvalidSamples() {
    let d = SpatialMath.medianDepth([2, .nan, 0, .infinity, 2.2, 1.8, 50, 2.1], confidences: [2, 2, 2, 2, 2, 2, 2, 0])
    #expect(d == 2)  // valid: 2, 2.2, 1.8 → median 2 (2.1 dropped for low confidence, 50 beyond 20 m)
}

@Test func medianNilWhenNoValidSamples() {
    #expect(SpatialMath.medianDepth([0, .nan], confidences: [2, 2]) == nil)
    #expect(SpatialMath.medianDepth([], confidences: []) == nil)
}

@Test func estimatedDistance() {
    #expect(abs(SpatialMath.estimatedDistance(boxHeightPixels: 425, fy: 1000) - 4) < 1e-4)
}

@Test func occlusionThreshold() {
    let near = [Float](repeating: 1.0, count: 4), far = [Float](repeating: 3.0, count: 6)
    #expect(SpatialMath.isPartiallyOccluded(sampleDepths: near + far, personDepth: 3))           // 40% > 35%
    #expect(!SpatialMath.isPartiallyOccluded(sampleDepths: [1, 1, 1] + far + [3], personDepth: 3)) // 30%
    #expect(!SpatialMath.isPartiallyOccluded(sampleDepths: [.nan, 0], personDepth: 3))
}

@Test func yawFacingCameraIsZero() {
    // Person facing +Z (toward a camera at the origin looking down −Z): left shoulder at +X from the camera's view is the person's right…
    let yaw = SpatialMath.yaw(leftShoulder: Vec3(0.2, 1.4, -3), rightShoulder: Vec3(-0.2, 1.4, -3))
    #expect(abs(yaw) < 1e-5)
    let turned = SpatialMath.yaw(leftShoulder: Vec3(0, 1.4, -3.2), rightShoulder: Vec3(0, 1.4, -2.8))
    #expect(abs(abs(turned) - .pi / 2) < 1e-4)
}
