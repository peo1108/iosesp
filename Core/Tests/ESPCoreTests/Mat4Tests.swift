import Testing
@testable import ESPCore

@Test func rigidInverseUndoesTransform() {
    let m = Mat4.translation(Vec3(1, 2, 3)) * Mat4.rotationY(.pi / 3)
    let p = Vec4(0.5, -1, 2, 1)
    let back = m.rigidInverse * (m * p)
    #expect(abs(back.x - p.x) < 1e-5 && abs(back.y - p.y) < 1e-5 && abs(back.z - p.z) < 1e-5)
}

@Test func translationIsReadBack() {
    #expect((Mat4.translation(Vec3(1, 2, 3)) * Mat4.rotationY(0.7)).translation == Vec3(1, 2, 3))
}

@Test func rotationYTurnsForwardLeft() {
    // +90° about +Y maps -Z (forward) to -X (left), right-handed like ARKit.
    let v = Mat4.rotationY(.pi / 2) * Vec4(0, 0, -1, 0)
    #expect(abs(v.x - (-1)) < 1e-6 && abs(v.z) < 1e-6)
}
