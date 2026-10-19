import Foundation

/// What it takes to project world points onto one camera image: its intrinsics and where it is.
public struct CameraPose: Sendable {
    public var intrinsics: CameraIntrinsics
    public var cameraToWorld: Mat4

    public init(intrinsics: CameraIntrinsics, cameraToWorld: Mat4) {
        self.intrinsics = intrinsics
        self.cameraToWorld = cameraToWorld
    }
}

/// How to read CoreMotion's attitude matrix. Its docs don't say which way it maps, so the app works it out
/// from gravity (`MotionPose.convention`).
public enum AttitudeConvention: Sendable {
    /// v_reference = M · v_device
    case deviceToReference
    /// v_device = M · v_reference (what Apple's AR sample code assumes)
    case referenceToDevice
}

/// Camera pose for the ultra-wide camera, which ARKit can't track: rotation only, from the gyroscope, with the
/// phone fixed at the world origin. World axes follow ARKit (+Y up), so floor distances, re-projection while
/// panning and edge arrows work as with ARKit; walking with the phone is not compensated.
public enum MotionPose {
    /// Back-camera axes in the device frame for an image in the sensor's native landscape orientation (ARKit's
    /// convention): +X from the front camera toward the bottom of the phone, +Y toward the phone's right edge,
    /// +Z out of the screen.
    static let cameraToDevice = Mat4(columns: (Vec4(0, -1, 0, 0), Vec4(1, 0, 0, 0), Vec4(0, 0, 1, 0), Vec4(0, 0, 0, 1)))
    /// CoreMotion reference frame (+Z up) → world (+Y up; the reference's +Y becomes −Z).
    static let referenceToWorld = Mat4(columns: (Vec4(1, 0, 0, 0), Vec4(0, 0, -1, 0), Vec4(0, 1, 0, 0), Vec4(0, 0, 0, 1)))

    /// Which reading of the attitude matrix puts "up" (−gravity, device frame) on the reference's +Z, or nil
    /// while that's unclear (both readings agree when the screen normal happens to point up the same way).
    /// `rows` is the matrix as CoreMotion reports it: (m11, m12, m13), (m21…), (m31…).
    public static func convention(attitudeRows rows: (Vec3, Vec3, Vec3), gravity: Vec3) -> AttitudeConvention? {
        let up = -normalize(gravity)
        let rowFit = dot(rows.2, up)                                // reference +Z seen from the device: 3rd row
        let columnFit = dot(Vec3(rows.0.z, rows.1.z, rows.2.z), up) // … or 3rd column
        if rowFit > 0.9 && columnFit < 0.5 { return .deviceToReference }
        if columnFit > 0.9 && rowFit < 0.5 { return .referenceToDevice }
        return nil
    }

    public static func cameraToWorld(attitudeRows rows: (Vec3, Vec3, Vec3), convention: AttitudeConvention) -> Mat4 {
        let deviceToReference: Mat4
        switch convention {
        case .deviceToReference:
            deviceToReference = Mat4(columns: (Vec4(rows.0.x, rows.1.x, rows.2.x, 0), Vec4(rows.0.y, rows.1.y, rows.2.y, 0),
                                               Vec4(rows.0.z, rows.1.z, rows.2.z, 0), Vec4(0, 0, 0, 1)))
        case .referenceToDevice:
            // The transpose maps back; its columns are the matrix's rows.
            deviceToReference = Mat4(columns: (Vec4(rows.0, 0), Vec4(rows.1, 0), Vec4(rows.2, 0), Vec4(0, 0, 0, 1)))
        }
        return referenceToWorld * deviceToReference * cameraToDevice
    }

    /// Pinhole intrinsics from the horizontal field of view, for cameras that don't deliver a matrix.
    public static func intrinsics(horizontalFOVDegrees fov: Float, imageSize: Vec2) -> CameraIntrinsics {
        let f = imageSize.x / 2 / tanf(fov * .pi / 360)
        return CameraIntrinsics(fx: f, fy: f, cx: imageSize.x / 2, cy: imageSize.y / 2, imageSize: imageSize)
    }
}
