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

    @ObservationIgnored private var labels = LabelBook()
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
    }
}
