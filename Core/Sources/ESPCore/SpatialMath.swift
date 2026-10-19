import Foundation

/// Pinhole intrinsics in pixels of `imageSize`.
public struct CameraIntrinsics: Sendable {
    public var fx: Float
    public var fy: Float
    public var cx: Float
    public var cy: Float
    public var imageSize: Vec2

    public init(fx: Float, fy: Float, cx: Float, cy: Float, imageSize: Vec2) {
        self.fx = fx
        self.fy = fy
        self.cx = cx
        self.cy = cy
        self.imageSize = imageSize
    }

    /// Same camera expressed for another resolution of the same image (e.g. the 256×192 depth map).
    public func scaled(to size: Vec2) -> CameraIntrinsics {
        let s = size / imageSize
        return CameraIntrinsics(fx: fx * s.x, fy: fy * s.y, cx: cx * s.x, cy: cy * s.y, imageSize: size)
    }
}

/// ARKit conventions: camera space is +X right, +Y up, looking down −Z; pixels are +x right, +y down.
public enum SpatialMath {
    static let minValidDepth: Float = 0.05
    static let maxValidDepth: Float = 20

    public static func unproject(pixel: Vec2, depth: Float, intrinsics k: CameraIntrinsics, cameraToWorld: Mat4) -> Vec3 {
        let camera = Vec4((pixel.x - k.cx) / k.fx * depth, -(pixel.y - k.cy) / k.fy * depth, -depth, 1)
        let w = cameraToWorld * camera
        return Vec3(w.x, w.y, w.z)
    }

    public static func cameraSpace(world: Vec3, cameraToWorld: Mat4) -> Vec3 {
        let c = cameraToWorld.rigidInverse * Vec4(world.x, world.y, world.z, 1)
        return Vec3(c.x, c.y, c.z)
    }

    /// Pixel position of a world point, or nil when it is behind the camera.
    public static func project(world: Vec3, intrinsics k: CameraIntrinsics, cameraToWorld: Mat4) -> Vec2? {
        let c = cameraSpace(world: world, cameraToWorld: cameraToWorld)
        guard c.z < -0.01 else { return nil }
        let depth = -c.z
        return Vec2(k.fx * c.x / depth + k.cx, -k.fy * c.y / depth + k.cy)
    }

    /// Median of the trustworthy depth samples; ignores non-finite, too-near and too-far values.
    public static func medianDepth(_ samples: [Float], confidences: [UInt8], minConfidence: UInt8 = 1) -> Float? {
        var valid: [Float] = []
        for (i, d) in samples.enumerated() where i < confidences.count && confidences[i] >= minConfidence {
            if isValid(d) { valid.append(d) }
        }
        guard !valid.isEmpty else { return nil }
        valid.sort()
        let mid = valid.count / 2
        return valid.count % 2 == 1 ? valid[mid] : (valid[mid - 1] + valid[mid]) / 2
    }

    public static func estimatedDistance(boxHeightPixels: Float, fy: Float, personHeight: Float = 1.70) -> Float {
        fy * personHeight / max(boxHeightPixels, 1)
    }

    /// 8 corners of a person-sized box standing on `base`: 0–3 bottom ring, 4–7 top ring.
    public static func boxCorners(base: Vec3, height: Float, width: Float = 0.55, depth: Float = 0.35, yaw: Float) -> [Vec3] {
        let hw = width / 2, hd = depth / 2
        let c = cosf(yaw), s = sinf(yaw)
        let ring = [Vec2(-hw, -hd), Vec2(hw, -hd), Vec2(hw, hd), Vec2(-hw, hd)].map { l in
            base + Vec3(l.x * c + l.y * s, 0, -l.x * s + l.y * c)
        }
        return ring + ring.map { $0 + Vec3(0, height, 0) }
    }

    /// True when more than `fraction` of the valid samples sit at least `margin` in front of the person.
    public static func isPartiallyOccluded(sampleDepths: [Float], personDepth: Float, margin: Float = 0.5, fraction: Float = 0.35) -> Bool {
        let valid = sampleDepths.filter(isValid)
        guard !valid.isEmpty else { return false }
        let inFront = valid.filter { $0 < personDepth - margin }.count
        return Float(inFront) / Float(valid.count) > fraction
    }

    /// Rotation about +Y that aligns the box's width axis with the shoulder line.
    public static func yaw(leftShoulder: Vec3, rightShoulder: Vec3) -> Float {
        let d = leftShoulder - rightShoulder
        return atan2f(-d.z, d.x)
    }

    private static func isValid(_ d: Float) -> Bool {
        d.isFinite && d > minValidDepth && d <= maxValidDepth
    }
}
