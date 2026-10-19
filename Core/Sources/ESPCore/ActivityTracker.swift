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
        var last: ActivityFrame?
    }

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
    public func update(tracks: [Track], objects: [DetectedObject], orientation: VisionOrientation,
                       label: (Track) -> String, at time: TimeInterval) -> [Int: ActivityState] {
        let upright = orientation == .down
            ? objects.map { DetectedObject(kind: $0.kind, box: VisionMapping.topLeftRect($0.box, orientation: .down), confidence: $0.confidence) }
            : objects

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

            let joints = orientation == .down ? track.joints.mapValues { VisionMapping.topLeftPoint($0, orientation: .down) } : track.joints
            let box = orientation == .down ? VisionMapping.topLeftRect(track.box, orientation: .down) : track.box
            let speed = (track.velocity.x * track.velocity.x + track.velocity.z * track.velocity.z).squareRoot()
            var raw = ActivityRules.evaluate(joints: joints, box: box, speed: speed, objects: upright)
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

    /// Wrist above the shoulder swinging sideways: ≥ 2 direction changes of ≥ 0.25 L within 1.2 s.
    private func isWaving(_ person: inout PersonState, joints j: [Joint: Vec2], at time: TimeInterval) -> Bool {
        guard let ls = j[.leftShoulder], let rs = j[.rightShoulder], let lh = j[.leftHip], let rh = j[.rightHip] else {
            person.wrists = [:]
            return false
        }
        let L = max(ActivityRules.distance((ls + rs) / 2, (lh + rh) / 2), 0.01)
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
