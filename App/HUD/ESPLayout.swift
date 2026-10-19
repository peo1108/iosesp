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
    let color: Color
    let rect: CGRect
    private let mapper: ScreenMapper
    private let thenAnchor: CGPoint
    private let nowAnchor: CGPoint
    private let scale: CGFloat

    init(track: Track, identity: PlayerIdentity, color: Color, mapper: ScreenMapper,
         thenAnchor: CGPoint, nowAnchor: CGPoint, scale: CGFloat) {
        id = track.id
        self.track = track
        self.identity = identity
        self.color = color
        self.mapper = mapper
        self.thenAnchor = thenAnchor
        self.nowAnchor = nowAnchor
        self.scale = scale
        let r = mapper.rect(track.box)
        let a = Self.move(CGPoint(x: r.minX, y: r.minY), thenAnchor, nowAnchor, scale)
        let b = Self.move(CGPoint(x: r.maxX, y: r.maxY), thenAnchor, nowAnchor, scale)
        rect = CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
    }

    /// Screen point of a normalized image point from this player's detection.
    func screen(_ p: Vec2) -> CGPoint {
        Self.move(mapper.point(normalized: p), thenAnchor, nowAnchor, scale)
    }

    func joint(_ j: Joint) -> CGPoint? {
        track.joints[j].map(screen)
    }

    private static func move(_ p: CGPoint, _ then: CGPoint, _ now: CGPoint, _ s: CGFloat) -> CGPoint {
        CGPoint(x: now.x + (p.x - then.x) * s, y: now.y + (p.y - then.y) * s)
    }
}

enum ESPLayout {
    @MainActor
    static func compute(store: ESPStore, frame: ARFrame, viewSize: CGSize, lockedID: Int?) -> [PlayerLayout] {
        let orientation = InterfaceOrientation.current
        let now = ScreenMapper(frame: frame, viewSize: viewSize, orientation: orientation)
        let then = store.detectionCamera
        return store.confirmed.prefix(8).map { track in
            var thenAnchor = CGPoint.zero, nowAnchor = CGPoint.zero, scale: CGFloat = 1
            if store.trackingNormal, let world = track.worldPosition, let then,
               let p0 = now.point(world: world, camera: then), let p1 = now.point(world: world) {
                thenAnchor = p0
                nowAnchor = p1
                let d0 = now.depth(of: world, camera: then), d1 = now.depth(of: world)
                scale = CGFloat(min(max(d0 / max(d1, 0.1), 0.5), 2))
            }
            return PlayerLayout(track: track, identity: store.identity(for: track.id),
                                color: Palette.color(for: track, locked: track.id == lockedID),
                                mapper: now, thenAnchor: thenAnchor, nowAnchor: nowAnchor, scale: scale)
        }
    }
}
