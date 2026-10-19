import Foundation

/// Column-major 4×4 matrix (same layout as simd_float4x4), so ARKit transforms
/// convert column by column.
public struct Mat4: Equatable, Sendable {
    public var columns: (Vec4, Vec4, Vec4, Vec4)

    public init(columns: (Vec4, Vec4, Vec4, Vec4)) {
        self.columns = columns
    }

    public static let identity = Mat4(columns: (Vec4(1, 0, 0, 0), Vec4(0, 1, 0, 0), Vec4(0, 0, 1, 0), Vec4(0, 0, 0, 1)))

    public static func translation(_ t: Vec3) -> Mat4 {
        Mat4(columns: (Vec4(1, 0, 0, 0), Vec4(0, 1, 0, 0), Vec4(0, 0, 1, 0), Vec4(t.x, t.y, t.z, 1)))
    }

    /// Right-handed rotation about +Y (positive turns −Z toward −X).
    public static func rotationY(_ radians: Float) -> Mat4 {
        let c = cosf(radians), s = sinf(radians)
        return Mat4(columns: (Vec4(c, 0, -s, 0), Vec4(0, 1, 0, 0), Vec4(s, 0, c, 0), Vec4(0, 0, 0, 1)))
    }

    public var translation: Vec3 {
        Vec3(columns.3.x, columns.3.y, columns.3.z)
    }

    /// Inverse of a rotation + translation matrix: transpose the rotation, negate the rotated translation.
    public var rigidInverse: Mat4 {
        let (c0, c1, c2, _) = columns
        let t = translation
        let r0 = Vec3(c0.x, c0.y, c0.z), r1 = Vec3(c1.x, c1.y, c1.z), r2 = Vec3(c2.x, c2.y, c2.z)
        return Mat4(columns: (
            Vec4(c0.x, c1.x, c2.x, 0),
            Vec4(c0.y, c1.y, c2.y, 0),
            Vec4(c0.z, c1.z, c2.z, 0),
            Vec4(-dot(r0, t), -dot(r1, t), -dot(r2, t), 1)
        ))
    }

    public static func * (m: Mat4, v: Vec4) -> Vec4 {
        m.columns.0 * v.x + m.columns.1 * v.y + m.columns.2 * v.z + m.columns.3 * v.w
    }

    public static func * (a: Mat4, b: Mat4) -> Mat4 {
        Mat4(columns: (a * b.columns.0, a * b.columns.1, a * b.columns.2, a * b.columns.3))
    }

    public static func == (a: Mat4, b: Mat4) -> Bool {
        a.columns.0 == b.columns.0 && a.columns.1 == b.columns.1
            && a.columns.2 == b.columns.2 && a.columns.3 == b.columns.3
    }
}
