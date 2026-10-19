import ARKit
import ESPCore

extension Mat4 {
    /// simd_float4 is SIMD4<Float>, so columns carry over unchanged.
    init(_ m: simd_float4x4) {
        self.init(columns: (m.columns.0, m.columns.1, m.columns.2, m.columns.3))
    }
}

extension CameraIntrinsics {
    init(_ camera: ARCamera) {
        let k = camera.intrinsics
        self.init(fx: k.columns.0.x, fy: k.columns.1.y, cx: k.columns.2.x, cy: k.columns.2.y,
                  imageSize: Vec2(Float(camera.imageResolution.width), Float(camera.imageResolution.height)))
    }
}
