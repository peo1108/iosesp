public enum Occlusion: Sendable {
    case visible, partial
}

/// One person or animal found in one frame, already placed in 3D when depth was available.
/// `box` and `joints` are normalized image coordinates (top-left origin).
public struct Detection: Sendable {
    public var box: Rect
    public var kind: EntityKind
    /// Detector score 0…1; low scores can keep a track alive but never start one.
    public var confidence: Float
    public var joints: [Joint: Vec2]
    /// Feet-center point in world space.
    public var worldPosition: Vec3?
    public var distance: Float
    public var distanceIsEstimated: Bool
    public var heightMeters: Float
    public var yaw: Float
    public var occlusion: Occlusion

    public init(box: Rect, kind: EntityKind, confidence: Float, joints: [Joint: Vec2], worldPosition: Vec3?,
                distance: Float, distanceIsEstimated: Bool, heightMeters: Float, yaw: Float, occlusion: Occlusion) {
        self.box = box
        self.kind = kind
        self.confidence = confidence
        self.joints = joints
        self.worldPosition = worldPosition
        self.distance = distance
        self.distanceIsEstimated = distanceIsEstimated
        self.heightMeters = heightMeters
        self.yaw = yaw
        self.occlusion = occlusion
    }
}
