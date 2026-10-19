import Foundation

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

/// The HUD event log from track presence and speed alone (no pose or object rules): someone came into view,
/// left, an animal appeared, someone rode past fast.
public final class PresenceLog {
    public static let eventTTL: TimeInterval = 8
    public static let eventsShown = 5
    /// Unseen this long counts as gone.
    public static let leaveAfter: TimeInterval = 1
    /// Horizontal speed (m/s, ~23 km/h) above which someone is on a vehicle, not on foot.
    public static let ridingSpeed: Float = 6.5
    /// Consecutive fast updates needed, so a velocity spike on a standing person doesn't count.
    static let ridingUpdates = 3

    private struct Known {
        var label: String
        var lastSeen: TimeInterval
        /// The "vừa vào khung hình" line, which a riding announcement replaces while it's fresh.
        var entryEvent: Int?
        var fastUpdates = 0
        var announcedRiding = false
    }

    private var known: [Int: Known] = [:]
    private var nextEventID = 1
    public private(set) var events: [ActivityEvent] = []

    public init() {}

    public func reset() {
        known.removeAll()
        events.removeAll()
    }

    /// `tracks` are the confirmed tracks of this frame.
    public func update(tracks: [Track], label: (Track) -> String, at time: TimeInterval) {
        for track in tracks {
            if known[track.id] == nil {
                let name = label(track)
                var entry = Known(label: name, lastSeen: track.lastSeen)
                if case let .animal(animal) = track.kind {
                    log("\(animal.emoji) \(name) xuất hiện", at: time)
                } else {
                    entry.entryEvent = log("\(name) vừa vào khung hình", at: time)
                }
                known[track.id] = entry
            }
            guard var entry = known[track.id] else { continue }
            entry.lastSeen = track.lastSeen

            let speed = (track.velocity.x * track.velocity.x + track.velocity.z * track.velocity.z).squareRoot()
            entry.fastUpdates = track.kind.isPerson && speed >= Self.ridingSpeed ? entry.fastUpdates + 1 : 0
            if entry.fastUpdates >= Self.ridingUpdates && !entry.announcedRiding {
                announceRiding(&entry, speed: speed, at: time)
            }
            known[track.id] = entry
        }

        let present = Set(tracks.map(\.id))
        for (id, entry) in known where !present.contains(id) && time - entry.lastSeen > Self.leaveAfter {
            log("\(entry.label) rời khung hình", at: time)
            known[id] = nil
        }
        events.removeAll { time - $0.time > Self.eventTTL }
    }

    @discardableResult
    private func log(_ text: String, at time: TimeInterval) -> Int {
        let id = nextEventID
        events.append(ActivityEvent(id: id, text: text, time: time))
        nextEventID += 1
        if events.count > Self.eventsShown { events.removeFirst(events.count - Self.eventsShown) }
        return id
    }

    /// "🛵 Người phóng qua · 32 km/h", in place of the entry line when that is under 2 s old.
    private func announceRiding(_ entry: inout Known, speed: Float, at time: TimeInterval) {
        let text = "🛵 \(entry.label) phóng qua · \(Readout.speed(speed))"
        if let id = entry.entryEvent, let i = events.firstIndex(where: { $0.id == id }), time - events[i].time < 2 {
            events[i] = ActivityEvent(id: id, text: text, time: time)
        } else {
            log(text, at: time)
        }
        entry.announcedRiding = true
    }
}
