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
    /// Latest animal/object-model objects (phones, cups, chairs…), captured-image coordinates; feeds activities.
    var objects: [DetectedObject] = []
    /// The YOLO models failed to load; people come from the weaker Vision fallback.
    var modelWarning = false

    /// What each person is doing, by track id.
    var activities: [Int: ActivityState] = [:]
    /// Recent "Người 01 ngồi xuống"-style events, oldest first.
    var events: [ActivityEvent] = []
    /// Timestamp of the latest results (camera clock), for "time in frame".
    var timestamp: TimeInterval = 0

    @ObservationIgnored private var labels = LabelBook()
    @ObservationIgnored private let activityTracker = ActivityTracker()
    @ObservationIgnored private var lastPublish: Date?

    var confirmed: [Track] { tracks.filter { $0.state == .confirmed } }

    /// "Người 01", "Chó 01"… stable per track.
    func label(for track: Track) -> String {
        labels.label(for: track.id, kind: track.kind)
    }

    /// The camera pose of the detection frame at `timestamp` (a track's `lastSeen`).
    func pose(at timestamp: TimeInterval) -> CameraPose? {
        poses.value(at: timestamp)
    }

    func clear() {
        tracks = []
        objects = []
        activities = [:]
        events = []
        activityTracker.reset()
        poses = TimedHistory(keep: 1.2)
        fps = 0
        lastPublish = nil
    }

    func publish(_ tracks: [Track], objects: [DetectedObject], orientation: VisionOrientation, pose: CameraPose,
                 at timestamp: TimeInterval, trackingNormal: Bool) {
        self.objects = objects
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
        activities = activityTracker.update(tracks: tracks.filter { $0.state == .confirmed }, objects: objects,
                                            orientation: orientation, label: { [unowned self] in label(for: $0) },
                                            at: timestamp)
        if events != activityTracker.events { events = activityTracker.events }
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
