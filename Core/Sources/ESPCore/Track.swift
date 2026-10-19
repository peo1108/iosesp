import Foundation

public enum TrackState: Sendable {
    case tentative, confirmed, lost
}

/// A person or animal followed across frames with a stable id and smoothed geometry.
public struct Track: Identifiable, Sendable {
    public var id: Int
    public var state: TrackState
    public var box: Rect
    public var kind: EntityKind
    public var confidence: Float
    public var joints: [Joint: Vec2]
    public var worldPosition: Vec3?
    public var velocity: Vec3
    public var distance: Float
    public var distanceIsEstimated: Bool
    public var heightMeters: Float
    public var yaw: Float
    public var occlusion: Occlusion
    public var hits: Int
    public var lastSeen: TimeInterval

    public init(id: Int, state: TrackState, box: Rect, kind: EntityKind, confidence: Float, joints: [Joint: Vec2],
                worldPosition: Vec3?, velocity: Vec3, distance: Float, distanceIsEstimated: Bool, heightMeters: Float,
                yaw: Float, occlusion: Occlusion, hits: Int, lastSeen: TimeInterval) {
        self.id = id
        self.state = state
        self.box = box
        self.kind = kind
        self.confidence = confidence
        self.joints = joints
        self.worldPosition = worldPosition
        self.velocity = velocity
        self.distance = distance
        self.distanceIsEstimated = distanceIsEstimated
        self.heightMeters = heightMeters
        self.yaw = yaw
        self.occlusion = occlusion
        self.hits = hits
        self.lastSeen = lastSeen
    }

    public var speed: Float { length(velocity) }

    /// Where the feet probably are at `time`: the last position carried forward by the velocity, at most 0.3 s.
    public func predictedWorld(at time: TimeInterval) -> Vec3? {
        guard let worldPosition else { return nil }
        let dt = Float(min(max(time - lastSeen, 0), 0.3))
        return worldPosition + velocity * dt
    }
}
