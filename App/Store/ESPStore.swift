import ESPCore
import Foundation
import Observation

/// Latest perception results for the HUD. Main-actor only.
@MainActor @Observable
final class ESPStore {
    var tracks: [Track] = []
    /// Camera poses of recent detection frames by timestamp, for re-projecting each track from the frame it was
    /// last seen in to the current frame.
    @ObservationIgnored private var poses = TimedHistory<CameraPose>(keep: 1.2)
    /// Perception results per second (smoothed).
    var fps: Double = 0
    var trackingNormal = true
    /// The YOLO models failed to load; people come from the weaker Vision fallback.
    var modelWarning = false

    /// Recent "Người vừa vào khung hình"-style events, oldest first.
    var events: [ActivityEvent] = []
    /// Timestamp of the latest results (camera clock), for "time in frame".
    var timestamp: TimeInterval = 0

    @ObservationIgnored private let presence = PresenceLog()
    @ObservationIgnored private var lastPublish: Date?

    var confirmed: [Track] { tracks.filter { $0.state == .confirmed } }

    /// Just what it is — "Người", "Chó"… — no per-track number.
    func label(for track: Track) -> String {
        track.kind.name
    }

    /// The camera pose of the detection frame at `timestamp` (a track's `lastSeen`).
    func pose(at timestamp: TimeInterval) -> CameraPose? {
        poses.value(at: timestamp)
    }

    func clear() {
        tracks = []
        events = []
        presence.reset()
        poses = TimedHistory(keep: 1.2)
        fps = 0
        lastPublish = nil
    }

    func publish(_ tracks: [Track], pose: CameraPose, at timestamp: TimeInterval, trackingNormal: Bool) {
        self.timestamp = timestamp
        let now = Date()
        if let last = lastPublish {
            let instant = 1 / max(now.timeIntervalSince(last), 0.001)
            fps = fps == 0 ? instant : fps * 0.9 + instant * 0.1
        }
        lastPublish = now
        poses.insert(pose, at: timestamp)
        self.tracks = tracks
        self.trackingNormal = trackingNormal
        presence.update(tracks: confirmed, label: { [unowned self] in label(for: $0) }, at: timestamp)
        if events != presence.events { events = presence.events }
    }

    /// People and animals as the HUD counter text, with the same filter as the ESP on screen.
    func countSummary(showAnimals: Bool) -> String {
        var animals: [AnimalKind: Int] = [:]
        if showAnimals {
            for track in confirmed {
                if case let .animal(kind) = track.kind { animals[kind, default: 0] += 1 }
            }
        }
        return CountSummary.text(people: confirmed.filter { $0.kind.isPerson }.count, animals: animals)
    }
}
