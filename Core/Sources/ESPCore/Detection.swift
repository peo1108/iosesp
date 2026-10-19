public enum Occlusion: Sendable {
    case visible, partial
}

/// One person found in one frame, already placed in 3D when depth was available.
/// `box` and `joints` are normalized image coordinates (top-left origin).
public struct Detection: Sendable {
    public var box: Rect
    public var joints: [Joint: Vec2]
    /// Feet-center point in world space.
    public var worldPosition: Vec3?
    public var distance: Float
    public var distanceIsEstimated: Bool
    public var heightMeters: Float
    public var yaw: Float
    public var occlusion: Occlusion

    public init(box: Rect, joints: [Joint: Vec2], worldPosition: Vec3?, distance: Float,
                distanceIsEstimated: Bool, heightMeters: Float, yaw: Float, occlusion: Occlusion) {
        self.box = box
        self.joints = joints
        self.worldPosition = worldPosition
        self.distance = distance
        self.distanceIsEstimated = distanceIsEstimated
        self.heightMeters = heightMeters
        self.yaw = yaw
        self.occlusion = occlusion
    }
}
