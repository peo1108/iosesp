import ESPCore
import SwiftUI

/// Where one person or animal is drawn this display frame.
///
/// Detections arrive at ≤60 Hz with some delay. Each track's world point is projected with the camera of the
/// frame it was last detected in and, Kalman-predicted to now, with the current camera; the difference (shift +
/// depth scale) is applied to the detected box, so boxes stay on people while the phone pans or they walk.
struct PlayerLayout: Identifiable {
    let id: Int
    let track: Track
    let label: String
    /// What the person is doing (nil for animals, or before the first activity pass).
    var activity: ActivityState?
    var color: Color
    /// Meters along the floor from the phone, from the predicted position when available: smooth, and the
    /// same measure the edge arrows use.
    let distance: Float
    let rect: CGRect

    /// `base` is the predicted feet position for this display frame when the track is world-anchored.
    init(track: Track, label: String, color: Color, mapper: ScreenMapper,
         thenAnchor: CGPoint, nowAnchor: CGPoint, scale: CGFloat, base: Vec3?) {
        id = track.id
        self.track = track
        self.label = label
        self.color = color
        let r = mapper.rect(track.box)
        func move(_ p: CGPoint) -> CGPoint {
            CGPoint(x: nowAnchor.x + (p.x - thenAnchor.x) * scale, y: nowAnchor.y + (p.y - thenAnchor.y) * scale)
        }
        let a = move(CGPoint(x: r.minX, y: r.minY)), b = move(CGPoint(x: r.maxX, y: r.maxY))
        rect = CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)

        if let base {
            let eye = mapper.cameraToWorld.translation
            distance = Vec2(base.x - eye.x, base.z - eye.z).squareLength.squareRoot()
        } else {
            distance = track.distance
        }
    }
}

struct OffscreenMarker: Identifiable {
    let id: Int
    let point: CGPoint
    let angle: Double
    let distance: Float
    let estimated: Bool
    let color: Color
}

/// One display frame's worth of layout: the mapper plus every track and edge arrow.
struct ESPFrameLayout {
    let mapper: ScreenMapper
    let players: [PlayerLayout]
    let offscreen: [OffscreenMarker]
    /// Camera clock of this display frame (same clock as `Track.lastSeen`).
    let timestamp: TimeInterval
}

enum ESPLayout {
    @MainActor
    static func compute(store: ESPStore, pose: CameraPose, timestamp: TimeInterval, viewSize: CGSize) -> ESPFrameLayout {
        let orientation = InterfaceOrientation.current
        let now = ScreenMapper(pose: pose, viewSize: viewSize, orientation: orientation)

        let players = store.confirmed.map { track in
            var thenAnchor = CGPoint.zero, nowAnchor = CGPoint.zero, scale: CGFloat = 1
            var base: Vec3?
            // Then: where the track was, seen by the camera of the frame it was last detected in.
            // Now: where it probably is at this display frame (Kalman velocity), seen by the current camera.
            if store.trackingNormal, let world = track.worldPosition, let then = store.pose(at: track.lastSeen),
               let predicted = track.predictedWorld(at: timestamp),
               let p0 = now.point(world: world, camera: then), let p1 = now.point(world: predicted) {
                thenAnchor = p0
                nowAnchor = p1
                let d0 = now.depth(of: world, camera: then), d1 = now.depth(of: predicted)
                scale = CGFloat(min(max(d0 / max(d1, 0.1), 0.5), 2))
                base = predicted
            }
            var layout = PlayerLayout(track: track, label: store.label(for: track), color: Palette.color(for: track),
                                      mapper: now, thenAnchor: thenAnchor, nowAnchor: nowAnchor, scale: scale, base: base)
            layout.activity = store.activities[track.id]
            return layout
        }

        var offscreen: [OffscreenMarker] = []
        if store.trackingNormal {
            let size = Vec2(Float(viewSize.width), Float(viewSize.height))
            let eye = now.cameraToWorld.translation
            for track in store.tracks {
                guard let world = track.predictedWorld(at: timestamp) else { continue }
                let p = now.naivePoint(world: world)
                guard let placed = OffscreenArrow.place(target: Vec2(Float(p.x), Float(p.y)),
                                                        isBehind: now.depth(of: world) <= 0, viewSize: size) else { continue }
                offscreen.append(OffscreenMarker(id: track.id, point: CGPoint(x: CGFloat(placed.point.x), y: CGFloat(placed.point.y)),
                                                 angle: Double(placed.angle),
                                                 distance: Vec2(world.x - eye.x, world.z - eye.z).squareLength.squareRoot(),
                                                 estimated: track.distanceIsEstimated, color: Palette.color(for: track)))
            }
        }
        return ESPFrameLayout(mapper: now, players: players, offscreen: offscreen, timestamp: timestamp)
    }
}
