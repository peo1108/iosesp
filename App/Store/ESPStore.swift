import ARKit
import ESPCore
import Foundation
import Observation

/// Latest perception results for the HUD. Main-actor only.
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
    /// Latest animal/object-model objects (phones, cups, chairs…), captured-image coordinates.
    var objects: [DetectedObject] = []
    /// The YOLO models failed to load; people come from the weaker Vision fallback.
    var modelWarning = false

    /// What each person is doing, by track id.
    var activities: [Int: ActivityState] = [:]
    /// Recent "Người 01 ngồi xuống"-style events, oldest first.
    var events: [ActivityEvent] = []
    /// Timestamp of the latest results (ARFrame clock), for "time in frame".
    var timestamp: TimeInterval = 0

    /// Footprint trails by track id (world space).
    @ObservationIgnored private(set) var trails: [Int: Trail] = [:]

    @ObservationIgnored private var labels = LabelBook()
    @ObservationIgnored private let activityTracker = ActivityTracker()
    @ObservationIgnored private var lastPublish: Date?

    var confirmed: [Track] { tracks.filter { $0.state == .confirmed } }
    var confirmedPeople: [Track] { confirmed.filter { $0.kind.isPerson } }

    /// "Người 01", "Chó 01"… stable per track.
    func label(for track: Track) -> String {
        labels.label(for: track.id, kind: track.kind)
    }

    /// The camera of the detection frame at `timestamp` (a track's `lastSeen`).
    func camera(at timestamp: TimeInterval) -> ARCamera? {
        cameras.value(at: timestamp)
    }

    func clear() {
        tracks = []
        objects = []
        activities = [:]
        events = []
        trails = [:]
        activityTracker.reset()
        chamsMask = nil
        cameras = TimedHistory(keep: 1.2)
    }

    func publish(_ tracks: [Track], objects: [DetectedObject], orientation: VisionOrientation, camera: ARCamera,
                 at timestamp: TimeInterval, trackingNormal: Bool, hasDepth: Bool) {
        self.objects = objects
        self.timestamp = timestamp
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
        activities = activityTracker.update(tracks: tracks.filter { $0.state == .confirmed }, objects: objects,
                                            orientation: orientation, label: { [unowned self] in label(for: $0) },
                                            at: timestamp)
        if events != activityTracker.events { events = activityTracker.events }

        for track in tracks where track.state == .confirmed && track.kind.isPerson {
            if let feet = track.worldPosition { trails[track.id, default: Trail()].add(feet, at: timestamp) }
        }
        trails = trails.filter { !$0.value.points(at: timestamp).isEmpty }
    }

    /// People and animals as the HUD counter text, with the same filters as the ESP on screen.
    func countSummary(showAnimals: Bool, maxDistance: Float) -> String {
        let inRange = confirmed.filter { $0.distance <= maxDistance }
        var animals: [AnimalKind: Int] = [:]
        if showAnimals {
            for track in inRange {
                if case let .animal(kind) = track.kind { animals[kind, default: 0] += 1 }
            }
        }
        return CountSummary.text(people: inRange.filter { $0.kind.isPerson }.count, animals: animals)
    }
}
