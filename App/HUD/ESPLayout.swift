import ARKit
import ESPCore
import SwiftUI

/// Where one player is drawn this display frame.
///
/// Perception runs at ≤30 Hz, the screen at 60 Hz. Between results, each player's world point is projected
/// with the camera of the detection frame and with the current camera; the difference (shift + depth scale)
/// is applied to everything that came from the image, so boxes stay on people while the phone pans.
struct PlayerLayout: Identifiable {
    let id: Int
    let track: Track
    let identity: PlayerIdentity
    var color: Color
    let hp: Float
    let rect: CGRect
    /// The 8 projected corners of the world-space box (0–3 bottom, 4–7 top), when every corner is in front.
    let corners3D: [CGPoint]?
    private let mapper: ScreenMapper
    private let thenAnchor: CGPoint
    private let nowAnchor: CGPoint
    private let scale: CGFloat

    init(track: Track, identity: PlayerIdentity, color: Color, hp: Float, mapper: ScreenMapper,
         thenAnchor: CGPoint, nowAnchor: CGPoint, scale: CGFloat, worldAnchored: Bool) {
        id = track.id
        self.track = track
        self.identity = identity
        self.color = color
        self.hp = hp
        self.mapper = mapper
        self.thenAnchor = thenAnchor
        self.nowAnchor = nowAnchor
        self.scale = scale
        let r = mapper.rect(track.box)
        let a = Self.move(CGPoint(x: r.minX, y: r.minY), thenAnchor, nowAnchor, scale)
        let b = Self.move(CGPoint(x: r.maxX, y: r.maxY), thenAnchor, nowAnchor, scale)
        rect = CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)

        if worldAnchored, let base = track.worldPosition {
            let points = SpatialMath.boxCorners(base: base, height: track.heightMeters, yaw: track.yaw).map(mapper.point(world:))
            corners3D = points.contains { $0 == nil } ? nil : points.compactMap { $0 }
        } else {
            corners3D = nil
        }
    }

    /// Screen point of a normalized image point from this player's detection.
    func screen(_ p: Vec2) -> CGPoint {
        Self.move(mapper.point(normalized: p), thenAnchor, nowAnchor, scale)
    }

    func joint(_ j: Joint) -> CGPoint? {
        track.joints[j].map(screen)
    }

    /// Head position: the nose joint, else a point near the top of the box.
    var head: CGPoint {
        joint(.nose) ?? CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.08)
    }

    /// Where the fake aimbot points: head, or between the shoulders for chest.
    func aimPoint(_ target: AimTarget) -> CGPoint {
        switch target {
        case .head:
            return head
        case .chest:
            if let l = joint(.leftShoulder), let r = joint(.rightShoulder) {
                return CGPoint(x: (l.x + r.x) / 2, y: (l.y + r.y) / 2 + rect.height * 0.05)
            }
            return joint(.neck) ?? CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.3)
        }
    }

    private static func move(_ p: CGPoint, _ then: CGPoint, _ now: CGPoint, _ s: CGFloat) -> CGPoint {
        CGPoint(x: now.x + (p.x - then.x) * s, y: now.y + (p.y - then.y) * s)
    }
}

struct OffscreenMarker: Identifiable {
    let id: Int
    let point: CGPoint
    let angle: Double
    let distance: Float
}

/// One display frame's worth of layout: the mapper plus every player and edge arrow.
struct ESPFrameLayout {
    let mapper: ScreenMapper
    let players: [PlayerLayout]
    let offscreen: [OffscreenMarker]
}

enum ESPLayout {
    @MainActor
    static func compute(store: ESPStore, frame: ARFrame, viewSize: CGSize, lockedID: Int?) -> ESPFrameLayout {
        let orientation = InterfaceOrientation.current
        let now = ScreenMapper(frame: frame, viewSize: viewSize, orientation: orientation)
        let then = store.detectionCamera

        // Eliminated players vanish until they respawn.
        let players = store.confirmed.filter { !store.isEliminated($0.id) }.prefix(8).map { track in
            var thenAnchor = CGPoint.zero, nowAnchor = CGPoint.zero, scale: CGFloat = 1
            var anchored = false
            if store.trackingNormal, let world = track.worldPosition, let then,
               let p0 = now.point(world: world, camera: then), let p1 = now.point(world: world) {
                thenAnchor = p0
                nowAnchor = p1
                let d0 = now.depth(of: world, camera: then), d1 = now.depth(of: world)
                scale = CGFloat(min(max(d0 / max(d1, 0.1), 0.5), 2))
                anchored = true
            }
            return PlayerLayout(track: track, identity: store.identity(for: track.id),
                                color: Palette.color(for: track, locked: track.id == lockedID),
                                hp: store.health(for: track.id), mapper: now,
                                thenAnchor: thenAnchor, nowAnchor: nowAnchor, scale: scale, worldAnchored: anchored)
        }

        var offscreen: [OffscreenMarker] = []
        if store.trackingNormal {
            let size = Vec2(Float(viewSize.width), Float(viewSize.height))
            let eye = now.cameraToWorld.translation
            for track in store.tracks {
                guard let world = track.worldPosition else { continue }
                let p = now.naivePoint(world: world)
                guard let placed = OffscreenArrow.place(target: Vec2(Float(p.x), Float(p.y)),
                                                        isBehind: now.depth(of: world) <= 0, viewSize: size) else { continue }
                offscreen.append(OffscreenMarker(id: track.id, point: CGPoint(x: CGFloat(placed.point.x), y: CGFloat(placed.point.y)),
                                                 angle: Double(placed.angle), distance: simd_distance(world, eye)))
            }
        }
        return ESPFrameLayout(mapper: now, players: players, offscreen: offscreen)
    }
}
