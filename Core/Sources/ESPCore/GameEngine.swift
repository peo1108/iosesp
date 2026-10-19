import Foundation

public struct GameConfig: Sendable {
    public var maxHP: Float = 100
    public var bodyDamage: ClosedRange<Int> = 18...34
    public var headshotDamage: Float = 100
    public var regenPerSecond: Float = 5
    public var regenDelay: TimeInterval = 3
    public var regenMaxSpeed: Float = 0.3
    public var drainPerSecond: Float = 4
    public var drainMinSpeed: Float = 1.5
    public var drainFloor: Float = 10
    public var respawnDelay: TimeInterval = 5
    public var killFeedMax = 4
    public var killFeedTTL: TimeInterval = 6

    public init() {}
}

public struct PlayerStatus: Equatable, Sendable {
    public var id: Int
    public var hp: Float
    public var lastDamageAt: TimeInterval?
    public var eliminatedAt: TimeInterval?

    public init(id: Int, hp: Float, lastDamageAt: TimeInterval?, eliminatedAt: TimeInterval?) {
        self.id = id
        self.hp = hp
        self.lastDamageAt = lastDamageAt
        self.eliminatedAt = eliminatedAt
    }

    public var isEliminated: Bool { eliminatedAt != nil }
}

public struct DamageEvent: Equatable, Sendable {
    public var trackID: Int
    public var amount: Int
    public var isHeadshot: Bool
    public var killed: Bool
    public var time: TimeInterval

    public init(trackID: Int, amount: Int, isHeadshot: Bool, killed: Bool, time: TimeInterval) {
        self.trackID = trackID
        self.amount = amount
        self.isHeadshot = isHeadshot
        self.killed = killed
        self.time = time
    }
}

public struct KillFeedEntry: Equatable, Sendable, Identifiable {
    public var id: Int
    public var victim: String
    public var distance: Float
    public var isHeadshot: Bool
    public var time: TimeInterval

    public init(id: Int, victim: String, distance: Float, isHeadshot: Bool, time: TimeInterval) {
        self.id = id
        self.victim = victim
        self.distance = distance
        self.isHeadshot = isHeadshot
        self.time = time
    }
}

/// The fake game on top of the ESP: health, shots, eliminations, respawns and the kill feed.
public final class GameEngine {
    public let config: GameConfig
    private var rng: SplitMix64
    private var statuses: [Int: PlayerStatus] = [:]
    private var lastSync: TimeInterval?
    private var nextFeedID = 1
    public private(set) var killFeed: [KillFeedEntry] = []

    public init(config: GameConfig = .init(), seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        self.config = config
        rng = SplitMix64(seed: seed)
    }

    public func status(_ id: Int) -> PlayerStatus? {
        statuses[id]
    }

    public func sync(_ tracks: [Track], at time: TimeInterval, naturalHealth: Bool) {
        let dt = Float(max(0, time - (lastSync ?? time)))
        lastSync = time

        let present = Set(tracks.map(\.id))
        statuses = statuses.filter { present.contains($0.key) }

        for track in tracks {
            guard var status = statuses[track.id] else {
                if track.state == .confirmed {
                    statuses[track.id] = PlayerStatus(id: track.id, hp: config.maxHP, lastDamageAt: nil, eliminatedAt: nil)
                }
                continue
            }
            if let eliminatedAt = status.eliminatedAt {
                if time - eliminatedAt >= config.respawnDelay {
                    status = PlayerStatus(id: track.id, hp: config.maxHP, lastDamageAt: nil, eliminatedAt: nil)
                }
            } else if naturalHealth && dt > 0 {
                if track.speed > config.drainMinSpeed {
                    if status.hp > config.drainFloor {
                        status.hp = max(config.drainFloor, status.hp - config.drainPerSecond * dt)
                    }
                } else if track.speed < config.regenMaxSpeed,
                          status.lastDamageAt.map({ time - $0 >= config.regenDelay }) ?? true {
                    status.hp = min(config.maxHP, status.hp + config.regenPerSecond * dt)
                }
            }
            statuses[track.id] = status
        }

        killFeed.removeAll { time - $0.time > config.killFeedTTL }
    }

    /// Applies a shot. Returns nil for unknown or already-eliminated players.
    public func shoot(_ target: HitTarget, distance: Float, at time: TimeInterval) -> DamageEvent? {
        guard var status = statuses[target.id], !status.isEliminated else { return nil }
        let amount = target.isHead ? Int(config.headshotDamage) : Int.random(in: config.bodyDamage, using: &rng)
        status.hp = max(0, status.hp - Float(amount))
        status.lastDamageAt = time
        let killed = status.hp <= 0
        if killed {
            status.eliminatedAt = time
            killFeed.append(KillFeedEntry(id: nextFeedID, victim: NameGenerator.identity(for: target.id).name,
                                          distance: distance, isHeadshot: target.isHead, time: time))
            nextFeedID += 1
            if killFeed.count > config.killFeedMax {
                killFeed.removeFirst(killFeed.count - config.killFeedMax)
            }
        }
        statuses[target.id] = status
        return DamageEvent(trackID: target.id, amount: amount, isHeadshot: target.isHead, killed: killed, time: time)
    }
}
