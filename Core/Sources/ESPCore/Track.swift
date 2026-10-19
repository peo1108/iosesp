import Foundation

public enum TrackState: Sendable {
    case tentative, confirmed, lost
}

/// A person followed across frames with a stable id and smoothed geometry.
public struct Track: Identifiable, Sendable {
    public var id: Int
    public var state: TrackState
    public var box: Rect
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

    public init(id: Int, state: TrackState, box: Rect, joints: [Joint: Vec2], worldPosition: Vec3?,
                velocity: Vec3, distance: Float, distanceIsEstimated: Bool, heightMeters: Float,
                yaw: Float, occlusion: Occlusion, hits: Int, lastSeen: TimeInterval) {
        self.id = id
        self.state = state
        self.box = box
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
}
