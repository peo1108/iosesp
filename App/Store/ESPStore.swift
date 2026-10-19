import ARKit
import ESPCore
import Foundation
import Observation

/// Latest perception results for the HUD. Main-actor only.
@MainActor @Observable
final class ESPStore {
    var tracks: [Track] = []
    /// Camera of the frame `tracks` were detected in, for re-projecting them to the current frame.
    @ObservationIgnored var detectionCamera: ARCamera?
    /// Perception results per second (smoothed).
    var fps: Double = 0
    var trackingNormal = true
    var hasDepth = false

    @ObservationIgnored private var identities: [Int: PlayerIdentity] = [:]
    @ObservationIgnored private var lastPublish: Date?

    var confirmed: [Track] { tracks.filter { $0.state == .confirmed } }

    func identity(for id: Int) -> PlayerIdentity {
        if let cached = identities[id] { return cached }
        let identity = NameGenerator.identity(for: id)
        identities[id] = identity
        return identity
    }

    func publish(_ tracks: [Track], camera: ARCamera, trackingNormal: Bool, hasDepth: Bool) {
        detectionCamera = camera
        let now = Date()
        if let last = lastPublish {
            let instant = 1 / max(now.timeIntervalSince(last), 0.001)
            fps = fps == 0 ? instant : fps * 0.9 + instant * 0.1
        }
        lastPublish = now
        self.tracks = tracks
        self.trackingNormal = trackingNormal
        self.hasDepth = hasDepth
    }
}
