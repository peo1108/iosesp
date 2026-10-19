import ARKit
import ESPCore
import Foundation
import Observation

struct DamageFX: Identifiable {
    let id = UUID()
    let point: CGPoint
    let text: String
    let isHeadshot: Bool
}

struct HitMarkerFX: Identifiable {
    let id = UUID()
    let point: CGPoint
}

struct EliminationFX: Identifiable {
    let id = UUID()
    let center: CGPoint
    let name: String
}

/// Latest perception results and game state for the HUD. Main-actor only.
@MainActor @Observable
final class ESPStore {
    var tracks: [Track] = []
    /// Cameras of recent detection frames by timestamp, for re-projecting each track from the frame it was
    /// last seen in to the current frame.
    @ObservationIgnored private var cameras = TimedHistory<ARCamera>(keep: 1.2)
    /// Perception results per second (smoothed).
    var fps: Double = 0
    var trackingNormal = true
    var hasDepth = false
    /// Person-segmentation mask in captured-image space (white, alpha = person), refreshed ~10 Hz.
    var chamsMask: CGImage?

    // Game
    @ObservationIgnored let game = GameEngine()
    @ObservationIgnored var naturalHealth = false
    var killFeed: [KillFeedEntry] = []
    var damageFX: [DamageFX] = []
    var hitMarkers: [HitMarkerFX] = []
    var eliminations: [EliminationFX] = []
    /// Last shot, for haptics.
    var lastHit: DamageEvent?

    @ObservationIgnored private var identities: [Int: PlayerIdentity] = [:]
    @ObservationIgnored private var lastPublish: Date?

    var confirmed: [Track] { tracks.filter { $0.state == .confirmed } }

    static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// 0…100; 0 while eliminated.
    func health(for id: Int) -> Float {
        guard let status = game.status(id) else { return 100 }
        return status.isEliminated ? 0 : status.hp
    }

    func isEliminated(_ id: Int) -> Bool {
        game.status(id)?.isEliminated ?? false
    }

    func identity(for id: Int) -> PlayerIdentity {
        if let cached = identities[id] { return cached }
        let identity = NameGenerator.identity(for: id)
        identities[id] = identity
        return identity
    }

    /// The camera of the detection frame at `timestamp` (a track's `lastSeen`).
    func camera(at timestamp: TimeInterval) -> ARCamera? {
        cameras.value(at: timestamp)
    }

    func clear() {
        tracks = []
        chamsMask = nil
        cameras = TimedHistory(keep: 1.2)
    }

    func publish(_ tracks: [Track], camera: ARCamera, at timestamp: TimeInterval, trackingNormal: Bool, hasDepth: Bool) {
        let now = Date()
        if let last = lastPublish {
            let instant = 1 / max(now.timeIntervalSince(last), 0.001)
            fps = fps == 0 ? instant : fps * 0.9 + instant * 0.1
        }
        lastPublish = now
        cameras.insert(camera, at: timestamp)
        self.tracks = tracks
        self.trackingNormal = trackingNormal
        self.hasDepth = hasDepth
        game.sync(tracks, at: Self.now, naturalHealth: naturalHealth)
        syncKillFeed()
    }

    /// Fires at a screen point against the players currently on screen.
    func shoot(at point: CGPoint, players: [PlayerLayout]) {
        let boxes = players.map { p -> (id: Int, box: Rect, head: Vec2?) in
            let r = p.rect
            return (p.id, Rect(x: Float(r.minX), y: Float(r.minY), width: Float(r.width), height: Float(r.height)),
                    p.joint(.nose).map { Vec2(Float($0.x), Float($0.y)) })
        }
        guard let target = HitTest.target(at: Vec2(Float(point.x), Float(point.y)), boxes: boxes),
              let player = players.first(where: { $0.id == target.id }),
              let event = game.shoot(target, distance: player.track.distance, at: Self.now) else { return }

        lastHit = event
        add(HitMarkerFX(point: point), to: \.hitMarkers, lifetime: 0.4)
        add(DamageFX(point: CGPoint(x: player.rect.midX, y: player.rect.minY),
                     text: event.isHeadshot ? "HEADSHOT -\(event.amount)" : "-\(event.amount)",
                     isHeadshot: event.isHeadshot), to: \.damageFX, lifetime: 1.2)
        if event.killed {
            add(EliminationFX(center: CGPoint(x: player.rect.midX, y: player.rect.midY), name: player.identity.name),
                to: \.eliminations, lifetime: 1.6)
        }
        syncKillFeed()
    }

    private func syncKillFeed() {
        if killFeed != game.killFeed { killFeed = game.killFeed }
    }

    private func add<T: Identifiable>(_ item: T, to list: ReferenceWritableKeyPath<ESPStore, [T]>, lifetime: Double) {
        self[keyPath: list].append(item)
        let id = item.id
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(lifetime))
            self?[keyPath: list].removeAll { $0.id == id }
        }
    }
}
