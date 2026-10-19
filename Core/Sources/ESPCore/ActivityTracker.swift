import Foundation

/// Holds a value until a different one has been seen continuously for `hold` seconds, so labels don't flicker.
public struct Stabilizer<T: Equatable>: Sendable where T: Sendable {
    public let hold: TimeInterval
    private var current: T?
    private var candidate: T?
    private var candidateSince: TimeInterval = 0

    public init(hold: TimeInterval = 0.4) {
        self.hold = hold
    }

    public mutating func update(_ value: T, at time: TimeInterval) -> T {
        guard let current else {
            self.current = value
            return value
        }
        if value == current {
            candidate = nil
            return current
        }
        if value != candidate {
            candidate = value
            candidateSince = time
        }
        if time - candidateSince >= hold - 1e-6 {
            self.current = value
            candidate = nil
            return value
        }
        return current
    }
}

public struct ActivityState: Equatable, Sendable {
    public var frame: ActivityFrame
    public var firstSeen: TimeInterval
    public var mainEmoji: String { frame.main.emoji }
    public var mainText: String { frame.main.text }

    public init(frame: ActivityFrame, firstSeen: TimeInterval) {
        self.frame = frame
        self.firstSeen = firstSeen
    }
}

public struct ActivityEvent: Identifiable, Equatable, Sendable {
    public var id: Int
    public var text: String
    public var time: TimeInterval

    public init(id: Int, text: String, time: TimeInterval) {
        self.id = id
        self.text = text
        self.time = time
    }
}

/// Per-track activity over time: stabilised labels, waving from wrist history, and the event log.
public final class ActivityTracker {
    public static let eventGap: TimeInterval = 2
    public static let eventTTL: TimeInterval = 8
    public static let eventsShown = 5
    public static let leaveAfter: TimeInterval = 1

    private struct PersonState {
        var posture = Stabilizer<Posture>()
        var motion = Stabilizer<Motion>()
        var gesture = Stabilizer<GestureKind>()
        var facing = Stabilizer<Facing>()
        var action = Stabilizer<ObjectAction>()
        var carrying = Stabilizer<[Carry]>()
        var wrists: [Joint: [(time: TimeInterval, offset: Float)]] = [:]
        /// Recent floor positions (x, z) for a displacement-based speed.
        var path: [(time: TimeInterval, position: Vec2)] = []
        var last: ActivityFrame?
    }

    /// Window for the walking/running speed: displacement over ~0.5 s ignores frame-to-frame depth jitter.
    static let speedWindow: TimeInterval = 0.5

    private struct Known {
        var label: String
        var kind: EntityKind
        var firstSeen: TimeInterval
        var lastSeen: TimeInterval
        var lastEvent: TimeInterval
        var person = PersonState()
    }

    private var known: [Int: Known] = [:]
    private var nextEventID = 1
    public private(set) var events: [ActivityEvent] = []

    public init() {}

    public func reset() {
        known.removeAll()
        events.removeAll()
    }

    /// `tracks` are the confirmed tracks; `objects` and track geometry are in captured-image coordinates,
    /// turned upright here when Vision ran with `.down`. Returns the state of every person by track id.
    /// `aspect` is the camera image's width / height: normalized x is stretched by it so the rules measure
    /// angles and distances in square units (a 4:3 image otherwise squashes horizontal lengths by 25%).
    public func update(tracks: [Track], objects: [DetectedObject], orientation: VisionOrientation,
                       label: (Track) -> String, at time: TimeInterval, aspect: Float = 4.0 / 3.0) -> [Int: ActivityState] {
        func square(_ p: Vec2) -> Vec2 { Vec2(p.x * aspect, p.y) }
        func square(_ r: Rect) -> Rect { Rect(x: r.x * aspect, y: r.y, width: r.width * aspect, height: r.height) }
        func upright(_ p: Vec2) -> Vec2 { square(orientation == .down ? VisionMapping.topLeftPoint(p, orientation: .down) : p) }
        func upright(_ r: Rect) -> Rect { square(orientation == .down ? VisionMapping.topLeftRect(r, orientation: .down) : r) }
        let uprightObjects = objects.map { DetectedObject(kind: $0.kind, box: upright($0.box), confidence: $0.confidence) }

        var states: [Int: ActivityState] = [:]
        for track in tracks {
            if known[track.id] == nil {
                let name = label(track)
                known[track.id] = Known(label: name, kind: track.kind, firstSeen: track.lastSeen, lastSeen: track.lastSeen,
                                        lastEvent: time)
                if case let .animal(animal) = track.kind {
                    log("\(animal.emoji) \(name) xuất hiện", at: time)
                } else {
                    log("\(name) vừa vào khung hình", at: time)
                }
            }
            known[track.id]?.lastSeen = track.lastSeen
            guard track.kind.isPerson, var entry = known[track.id] else { continue }

            let joints = track.joints.mapValues(upright)
            let box = upright(track.box)
            let speed = Self.floorSpeed(&entry.person, track: track)
            var raw = ActivityRules.evaluate(joints: joints, box: box, speed: speed, objects: uprightObjects)
            if isWaving(&entry.person, joints: joints, at: time) { raw.gesture = .waving }

            var p = entry.person
            let frame = ActivityFrame(posture: p.posture.update(raw.posture, at: time),
                                      motion: p.motion.update(raw.motion, at: time),
                                      gesture: p.gesture.update(raw.gesture, at: time),
                                      facing: p.facing.update(raw.facing, at: time),
                                      objectAction: p.action.update(raw.objectAction, at: time),
                                      carrying: p.carrying.update(raw.carrying, at: time))
            if let previous = p.last, let text = changeEvent(from: previous, to: frame), time - entry.lastEvent >= Self.eventGap {
                log("\(entry.label) \(text)", at: time)
                entry.lastEvent = time
            }
            p.last = frame
            entry.person = p
            known[track.id] = entry
            states[track.id] = ActivityState(frame: frame, firstSeen: entry.firstSeen)
        }

        // Gone for a while: say so and forget.
        let present = Set(tracks.map(\.id))
        for (id, entry) in known where !present.contains(id) && time - entry.lastSeen > Self.leaveAfter {
            log("\(entry.label) rời khung hình", at: time)
            known[id] = nil
        }

        events.removeAll { time - $0.time > Self.eventTTL }
        return states
    }

    // MARK: Private

    private func log(_ text: String, at time: TimeInterval) {
        events.append(ActivityEvent(id: nextEventID, text: text, time: time))
        nextEventID += 1
        if events.count > Self.eventsShown { events.removeFirst(events.count - Self.eventsShown) }
    }

    private func changeEvent(from old: ActivityFrame, to new: ActivityFrame) -> String? {
        if new.objectAction != old.objectAction {
            if new.objectAction == .calling { return "đang gọi điện" }
            if new.objectAction == .usingPhone { return "cầm điện thoại lên" }
        }
        if new.posture != old.posture {
            switch new.posture {
            case .sitting: return "ngồi xuống"
            case .lying: return "nằm xuống"
            case .standing where [.sitting, .squatting, .lying].contains(old.posture): return "đứng dậy"
            default: break
            }
        }
        if new.motion == .running && old.motion != .running { return "bắt đầu chạy" }
        if new.facing == .toward && old.facing != .toward { return "đang nhìn bạn" }
        return nil
    }

    /// Horizontal speed from how far the feet moved over the last `speedWindow`; falls back to the tracker's
    /// velocity until enough history exists.
    private static func floorSpeed(_ person: inout PersonState, track: Track) -> Float {
        let instant = (track.velocity.x * track.velocity.x + track.velocity.z * track.velocity.z).squareRoot()
        guard let world = track.worldPosition else { return instant }
        let now = track.lastSeen
        if person.path.last?.time != now { person.path.append((now, Vec2(world.x, world.z))) }
        person.path.removeAll { now - $0.time > speedWindow + 0.05 }
        guard let first = person.path.first, let last = person.path.last, last.time - first.time >= speedWindow * 0.6 else {
            return instant
        }
        return (last.position - first.position).squareLength.squareRoot() / Float(last.time - first.time)
    }

    /// Wrist above the shoulder swinging sideways: ≥ 2 direction changes of ≥ 0.25 L within 1.2 s.
    private func isWaving(_ person: inout PersonState, joints j: [Joint: Vec2], at time: TimeInterval) -> Bool {
        guard let ls = j[.leftShoulder], let rs = j[.rightShoulder] else {
            person.wrists = [:]
            return false
        }
        // Torso length, or (hips out of frame, e.g. waving close to the camera) from the shoulder width.
        let torso = ActivityRules.mid(j[.leftHip], j[.rightHip]).map { ActivityRules.distance((ls + rs) / 2, $0) }
        let L = max(torso ?? ActivityRules.distance(ls, rs) * 1.6, 0.01)
        var waving = false
        for (wrist, shoulder) in [(Joint.leftWrist, ls), (Joint.rightWrist, rs)] {
            guard let w = j[wrist], w.y < shoulder.y else {
                person.wrists[wrist] = nil
                continue
            }
            var history = person.wrists[wrist, default: []]
            history.append((time, (w.x - shoulder.x) / L))
            history.removeAll { time - $0.time > 1.2 }
            person.wrists[wrist] = history
            if Self.reversals(history.map(\.offset), amplitude: 0.25) >= 2 { waving = true }
        }
        return waving
    }

    static func reversals(_ values: [Float], amplitude: Float) -> Int {
        guard var extreme = values.first else { return 0 }
        var direction: Float = 0
        var count = 0
        for v in values.dropFirst() {
            let delta = v - extreme
            if direction == 0 {
                if abs(delta) >= amplitude { direction = delta > 0 ? 1 : -1; extreme = v }
            } else if delta * direction > 0 {
                extreme = v
            } else if abs(delta) >= amplitude {
                count += 1
                direction = -direction
                extreme = v
            }
        }
        return count
    }
}
