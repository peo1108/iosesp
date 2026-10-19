import Foundation

public struct TrackerConfig: Sendable {
    /// Detections at or above this start tracks and match first (ByteTrack "high"). Lower than ByteTrack's
    /// 0.5 so small, far people on the street are picked up; three hits still filter one-off false positives.
    public var highConfidence: Float = 0.4
    /// Detections between this and `highConfidence` only keep existing tracks alive.
    public var lowConfidence: Float = 0.15
    public var highIoU: Float = 0.2
    public var lowIoU: Float = 0.5
    public var worldMatchDistance: Float = 0.6
    /// New tracks also match a confident detection whose centre is within this many box heights, when the
    /// boxes no longer overlap: a rider passing fast moves more than a box width between frames before the
    /// Kalman filter knows the velocity (or when a hot phone runs at 20 Hz).
    public var fastReach: Float = 1.2
    /// Image width / height, so centre distances are measured in square units.
    public var imageAspect: Float = 4.0 / 3.0
    public var confirmHits = 3
    /// A new track may miss this long (a few 60 Hz frames) without starting over.
    public var tentativeGrace: TimeInterval = 0.1
    /// Unmatched confirmed tracks keep their (predicted) box this long, then disappear from screen.
    public var lostAfter: TimeInterval = 0.5
    public var forgetAfter: TimeInterval = 10
    public var maxTracks = 30

    public init() {}
}

/// ByteTrack-style tracker: each track's box is predicted with a constant-velocity Kalman filter before
/// matching, confident detections match first, weak ones only extend existing tracks, and leftovers are
/// matched by world position. A second Kalman filter on the feet position gives real-world velocity.
public final class Tracker {
    private struct Entry {
        var track: Track
        /// (cx, cy, w, h) in normalized image units.
        var boxKalman: KalmanCV<Vec4>
        var boxTime: TimeInterval
        var predictedBox: Rect
        var worldKalman: KalmanCV<Vec3>?
        var jointFilters: [Joint: OneEuroFilter<Vec2>] = [:]
        /// Yaw is filtered as a unit vector (cos, sin) so it never averages through 0 at ±π.
        var yawFilter = OneEuroFilter<Vec2>(minCutoff: 0.5, beta: 0.3)
        var heightFilter = OneEuroFilter<Vec2>(minCutoff: 0.5, beta: 0.2)
    }

    public let config: TrackerConfig
    private var entries: [Entry] = []
    private var nextID = 1

    public init(config: TrackerConfig = .init()) {
        self.config = config
    }

    public func reset() {
        entries.removeAll()
    }

    /// Returns confirmed tracks (nearest first) followed by lost ones, at most `maxTracks`.
    /// `animalsObserved` is false on frames where the (slower) animal detector did not run: animal tracks are
    /// then left untouched instead of being aged or dropped.
    @discardableResult
    public func update(_ detections: [Detection], at time: TimeInterval, animalsObserved: Bool = true) -> [Track] {
        for i in entries.indices { predictBox(&entries[i], to: time) }

        var freeTracks = Set(entries.indices)
        let usable = detections.indices.filter { detections[$0].confidence >= config.lowConfidence }
        let high = usable.filter { detections[$0].confidence >= config.highConfidence }
        let low = usable.filter { detections[$0].confidence < config.highConfidence }
        var freeHigh = Set(high)

        // 1. Confident detections against every live track's predicted box.
        // Confirmed tracks pick first, so a tentative duplicate can't steal a person's detection (and id).
        matchByOverlap(Set(high), &freeHigh, &freeTracks, threshold: config.highIoU, detections, at: time, states: [.confirmed])
        matchByOverlap(Set(high), &freeHigh, &freeTracks, threshold: config.highIoU, detections, at: time, states: [.tentative])
        // 1b. Fast movers whose new tracks don't overlap their next detection yet. Only tentative tracks, so a
        // confirmed person missed for a frame can't hand their id to someone stepping out next to them.
        matchFastNewTracks(&freeHigh, &freeTracks, detections, at: time)
        // 2. Weak detections only extend the tracks still unmatched, and need a tighter overlap.
        var freeLow = Set(low)
        matchByOverlap(Set(low), &freeLow, &freeTracks, threshold: config.lowIoU, detections, at: time, states: [.confirmed, .tentative])
        // 3. Confident leftovers by world proximity (this is also how lost tracks come back).
        matchByWorld(&freeHigh, &freeTracks, detections, at: time)

        // 4. Age out unmatched tracks (only kinds this frame actually looked for).
        var removed = Set<Int>()
        for t in freeTracks where animalsObserved || entries[t].track.kind.isPerson {
            let unseen = time - entries[t].track.lastSeen
            switch entries[t].track.state {
            case .tentative where unseen > config.tentativeGrace:
                removed.insert(t)
            case .confirmed where unseen > config.lostAfter:
                entries[t].track.state = .lost
            case .lost where unseen > config.forgetAfter:
                removed.insert(t)
            default:
                break
            }
        }
        entries = entries.indices.filter { !removed.contains($0) }.map { entries[$0] }

        // 5. Only confident detections start tracks.
        for d in freeHigh.sorted() {
            entries.append(makeEntry(detections[d], at: time))
        }

        let visible = entries.map(\.track).filter { $0.state != .tentative }
        let ordered = visible.sorted { a, b in
            if (a.state == .confirmed) != (b.state == .confirmed) { return a.state == .confirmed }
            return a.distance < b.distance
        }
        return Array(ordered.prefix(config.maxTracks))
    }

    // MARK: Matching

    private func matchByOverlap(_ candidates: Set<Int>, _ freeDetections: inout Set<Int>, _ freeTracks: inout Set<Int>,
                                threshold: Float, _ detections: [Detection], at time: TimeInterval, states: Set<TrackState>) {
        var pairs: [(t: Int, d: Int, iou: Float)] = []
        for t in freeTracks where states.contains(entries[t].track.state) {
            for d in candidates where detections[d].kind == entries[t].track.kind {
                let iou = entries[t].predictedBox.iou(detections[d].box)
                if iou >= threshold { pairs.append((t, d, iou)) }
            }
        }
        for pair in pairs.sorted(by: { $0.iou > $1.iou })
        where freeTracks.contains(pair.t) && freeDetections.contains(pair.d) {
            absorb(detections[pair.d], into: &entries[pair.t], at: time)
            freeTracks.remove(pair.t)
            freeDetections.remove(pair.d)
        }
    }

    private func matchFastNewTracks(_ freeDetections: inout Set<Int>, _ freeTracks: inout Set<Int>,
                                    _ detections: [Detection], at time: TimeInterval) {
        var pairs: [(t: Int, d: Int, reach: Float)] = []
        for t in freeTracks where entries[t].track.state == .tentative {
            let box = entries[t].predictedBox
            for d in freeDetections where detections[d].kind == entries[t].track.kind {
                let other = detections[d].box
                let ratio = other.height / max(box.height, 0.001)
                guard ratio > 0.67, ratio < 1.5 else { continue }
                let delta = (other.center - box.center) * Vec2(config.imageAspect, 1)
                let reach = delta.squareLength.squareRoot() / max(box.height, other.height)
                if reach < config.fastReach { pairs.append((t, d, reach)) }
            }
        }
        for pair in pairs.sorted(by: { $0.reach < $1.reach })
        where freeTracks.contains(pair.t) && freeDetections.contains(pair.d) {
            absorb(detections[pair.d], into: &entries[pair.t], at: time)
            freeTracks.remove(pair.t)
            freeDetections.remove(pair.d)
        }
    }

    private func matchByWorld(_ freeDetections: inout Set<Int>, _ freeTracks: inout Set<Int>,
                              _ detections: [Detection], at time: TimeInterval) {
        var pairs: [(t: Int, d: Int, distance: Float)] = []
        for t in freeTracks {
            // Where the track would be by now (a walker hidden for a second has moved on), up to 2 s ahead.
            let track = entries[t].track
            guard let last = track.worldPosition else { continue }
            let a = last + track.velocity * Float(min(max(time - track.lastSeen, 0), 2))
            for d in freeDetections where detections[d].kind == entries[t].track.kind {
                guard let b = detections[d].worldPosition else { continue }
                let distance = length(a - b)
                if distance < config.worldMatchDistance { pairs.append((t, d, distance)) }
            }
        }
        for pair in pairs.sorted(by: { $0.distance < $1.distance })
        where freeTracks.contains(pair.t) && freeDetections.contains(pair.d) {
            if entries[pair.t].track.state == .lost {
                // Revived somewhere else on screen: restart the image motion model and joints.
                restartBox(&entries[pair.t], at: detections[pair.d].box, time: time)
                entries[pair.t].jointFilters.removeAll()
            }
            absorb(detections[pair.d], into: &entries[pair.t], at: time)
            freeTracks.remove(pair.t)
            freeDetections.remove(pair.d)
        }
    }

    // MARK: Filters

    private static func state(_ r: Rect) -> Vec4 {
        Vec4(r.x + r.width / 2, r.y + r.height / 2, r.width, r.height)
    }

    private static func rect(_ s: Vec4) -> Rect {
        let w = max(s.z, 0.001), h = max(s.w, 0.001)
        return Rect(x: s.x - w / 2, y: s.y - h / 2, width: w, height: h)
    }

    private static func boxKalman(_ r: Rect) -> KalmanCV<Vec4> {
        KalmanCV(position: state(r), processNoise: 2, measurementNoise: 1e-4)
    }

    private func predictBox(_ entry: inout Entry, to time: TimeInterval) {
        entry.boxKalman.predict(dt: Float(time - entry.boxTime))
        entry.boxTime = max(entry.boxTime, time)
        entry.predictedBox = Self.rect(entry.boxKalman.position)
    }

    private func restartBox(_ entry: inout Entry, at box: Rect, time: TimeInterval) {
        entry.boxKalman = Self.boxKalman(box)
        entry.boxTime = time
        entry.predictedBox = box
    }

    private func makeEntry(_ d: Detection, at time: TimeInterval) -> Entry {
        let track = Track(id: nextID, state: .tentative, box: d.box, kind: d.kind, confidence: d.confidence,
                          joints: [:], worldPosition: nil, velocity: .zero, distance: d.distance,
                          distanceIsEstimated: d.distanceIsEstimated, heightMeters: d.heightMeters, yaw: d.yaw,
                          occlusion: d.occlusion, hits: 0, lastSeen: time, firstSeen: time)
        nextID += 1
        var entry = Entry(track: track, boxKalman: Self.boxKalman(d.box), boxTime: time, predictedBox: d.box)
        absorb(d, into: &entry, at: time, fresh: true)
        return entry
    }

    private func absorb(_ d: Detection, into entry: inout Entry, at time: TimeInterval, fresh: Bool = false) {
        var track = entry.track
        if !fresh { entry.boxKalman.update(Self.state(d.box)) }
        track.box = Self.rect(entry.boxKalman.position)
        entry.predictedBox = track.box

        var joints: [Joint: Vec2] = [:]
        var filters: [Joint: OneEuroFilter<Vec2>] = [:]
        for (joint, point) in d.joints {
            var f = entry.jointFilters[joint] ?? OneEuroFilter<Vec2>(minCutoff: 1.2, beta: 4)
            joints[joint] = f.filter(point, at: time)
            filters[joint] = f
        }
        track.joints = joints
        entry.jointFilters = filters

        if let world = d.worldPosition {
            if var k = entry.worldKalman {
                k.predict(dt: Float(time - track.lastSeen))
                k.update(world)
                entry.worldKalman = k
            } else {
                // Low process noise: feet positions jitter several cm frame to frame, and a twitchy
                // velocity would make people standing still read as walking.
                entry.worldKalman = KalmanCV(position: world, processNoise: 0.5, measurementNoise: 0.005, initialVelocityVariance: 4)
            }
            track.worldPosition = entry.worldKalman?.position
            track.velocity = entry.worldKalman?.velocity ?? .zero
        }

        track.confidence = d.confidence
        track.distance = d.distance
        track.distanceIsEstimated = d.distanceIsEstimated
        track.heightMeters = entry.heightFilter.filter(Vec2(d.heightMeters, 0), at: time).x
        let heading = entry.yawFilter.filter(Vec2(cosf(d.yaw), sinf(d.yaw)), at: time)
        track.yaw = atan2f(heading.y, heading.x)
        track.occlusion = d.occlusion
        track.hits += 1
        track.lastSeen = time
        if track.state == .lost || (track.state == .tentative && track.hits >= config.confirmHits) {
            track.state = .confirmed
        }
        entry.track = track
    }
}
