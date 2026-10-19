import Foundation

public struct TrackerConfig: Sendable {
    public var iouThreshold: Float = 0.3
    public var worldMatchDistance: Float = 0.6
    public var confirmHits = 3
    public var lostAfter: TimeInterval = 0.7
    public var forgetAfter: TimeInterval = 10
    public var maxTracks = 8

    public init() {}
}

/// Turns per-frame detections into tracks with stable ids and smoothed geometry.
public final class Tracker {
    private struct Entry {
        var track: Track
        var boxFilter = OneEuroFilter<Vec4>(minCutoff: 1.2, beta: 4)
        var jointFilters: [Joint: OneEuroFilter<Vec2>] = [:]
        var worldFilter = OneEuroFilter<Vec3>(minCutoff: 1.0, beta: 0.7)
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
    @discardableResult
    public func update(_ detections: [Detection], at time: TimeInterval) -> [Track] {
        var freeTracks = Set(entries.indices)
        var freeDetections = Set(detections.indices)

        // 1. Overlap in the image, best IoU first. Lost tracks only come back through world position.
        var overlaps: [(t: Int, d: Int, iou: Float)] = []
        for t in entries.indices where entries[t].track.state != .lost {
            for d in detections.indices {
                let iou = entries[t].track.box.iou(detections[d].box)
                if iou >= config.iouThreshold { overlaps.append((t, d, iou)) }
            }
        }
        for pair in overlaps.sorted(by: { $0.iou > $1.iou })
        where freeTracks.contains(pair.t) && freeDetections.contains(pair.d) {
            apply(detections[pair.d], to: pair.t, at: time)
            freeTracks.remove(pair.t)
            freeDetections.remove(pair.d)
        }

        // 2. Proximity in the world, nearest first.
        var nearby: [(t: Int, d: Int, distance: Float)] = []
        for t in freeTracks {
            guard let a = entries[t].track.worldPosition else { continue }
            for d in freeDetections {
                guard let b = detections[d].worldPosition else { continue }
                let distance = length(a - b)
                if distance < config.worldMatchDistance { nearby.append((t, d, distance)) }
            }
        }
        for pair in nearby.sorted(by: { $0.distance < $1.distance })
        where freeTracks.contains(pair.t) && freeDetections.contains(pair.d) {
            apply(detections[pair.d], to: pair.t, at: time)
            freeTracks.remove(pair.t)
            freeDetections.remove(pair.d)
        }

        // 3. Age out unmatched tracks.
        var removed = Set<Int>()
        for t in freeTracks {
            let unseen = time - entries[t].track.lastSeen
            switch entries[t].track.state {
            case .tentative:
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

        // 4. New detections start tentative.
        for d in freeDetections.sorted() {
            entries.append(makeEntry(detections[d], at: time))
        }

        let visible = entries.map(\.track).filter { $0.state != .tentative }
        let ordered = visible.sorted { a, b in
            if (a.state == .confirmed) != (b.state == .confirmed) { return a.state == .confirmed }
            return a.distance < b.distance
        }
        return Array(ordered.prefix(config.maxTracks))
    }

    private func makeEntry(_ d: Detection, at time: TimeInterval) -> Entry {
        let track = Track(id: nextID, state: .tentative, box: d.box, joints: [:], worldPosition: nil,
                          velocity: .zero, distance: d.distance, distanceIsEstimated: d.distanceIsEstimated,
                          heightMeters: d.heightMeters, yaw: d.yaw, occlusion: d.occlusion, hits: 0, lastSeen: time)
        nextID += 1
        var entry = Entry(track: track)
        absorb(d, into: &entry, at: time)
        return entry
    }

    private func apply(_ d: Detection, to index: Int, at time: TimeInterval) {
        if entries[index].track.state == .lost {
            // Revived somewhere else on screen: don't slide the box across from where it vanished.
            entries[index].boxFilter.reset()
            entries[index].jointFilters.removeAll()
        }
        absorb(d, into: &entries[index], at: time)
    }

    private func absorb(_ d: Detection, into entry: inout Entry, at time: TimeInterval) {
        var track = entry.track
        let b = entry.boxFilter.filter(Vec4(d.box.x, d.box.y, d.box.width, d.box.height), at: time)
        track.box = Rect(x: b.x, y: b.y, width: b.z, height: b.w)

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
            let smoothed = entry.worldFilter.filter(world, at: time)
            if let previous = track.worldPosition, time > track.lastSeen {
                track.velocity = (smoothed - previous) / Float(time - track.lastSeen)
            }
            track.worldPosition = smoothed
        }

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
