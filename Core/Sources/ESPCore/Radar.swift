public struct RadarBlip: Equatable, Sendable {
    public var id: Int
    /// −1…1 relative to the radar range; +y is the direction the phone faces, +x is to its right.
    public var position: Vec2

    public init(id: Int, position: Vec2) {
        self.id = id
        self.position = position
    }
}

/// Top-down minimap that turns with the phone's heading (pitch and roll are ignored).
public enum Radar {
    public static func blips(_ players: [(id: Int, world: Vec3)], cameraToWorld: Mat4, range: Float) -> [RadarBlip] {
        let (_, up, back, _) = cameraToWorld.columns
        var forward = Vec2(-back.x, -back.z)
        if (forward * forward).sum() < 1e-6 {
            // Looking straight down: the top of the image points forward.
            forward = Vec2(up.x, up.z)
        }
        forward /= (forward * forward).sum().squareRoot()
        let right = Vec2(-forward.y, forward.x)
        let origin = cameraToWorld.translation

        return players.compactMap { player in
            let rel = Vec2(player.world.x - origin.x, player.world.z - origin.z)
            guard (rel * rel).sum().squareRoot() <= range else { return nil }
            return RadarBlip(id: player.id, position: Vec2((rel * right).sum(), (rel * forward).sum()) / range)
        }
    }
}
