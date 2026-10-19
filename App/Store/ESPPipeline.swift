import ARKit
import CoreImage
import ESPCore

/// Capture → Perception → Spatial → Tracker → Store. Heavy work runs on `processingQueue`;
/// frames that arrive while it is busy, or faster than `targetHz`, are dropped.
final class ESPPipeline: @unchecked Sendable {
    private let perception = PerceptionPipeline()
    private let resolver = SpatialResolver()
    private let tracker = Tracker()
    private let processingQueue = DispatchQueue(label: "esp.perception", qos: .userInitiated)
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let store: ESPStore

    private let lock = NSLock()
    private var busy = false
    private var lastRun: TimeInterval = 0
    private var _targetHz: Double = 30
    private var _wantMask = true

    var targetHz: Double {
        get { lock.withLock { _targetHz } }
        set { lock.withLock { _targetHz = newValue } }
    }

    /// Whether to produce the Chams person mask.
    var wantMask: Bool {
        get { lock.withLock { _wantMask } }
        set { lock.withLock { _wantMask = newValue } }
    }

    @MainActor
    init(capture: CaptureEngine, store: ESPStore) {
        self.store = store
        capture.frameHandler = { [weak self] frame in self?.offer(frame) }
    }

    /// Clears tracks, e.g. after an interruption.
    func reset() {
        processingQueue.async { [tracker] in tracker.reset() }
    }

    private func offer(_ frame: ARFrame) {
        let accept: Bool = lock.withLock {
            guard !busy, frame.timestamp - lastRun >= 1 / _targetHz else { return false }
            busy = true
            lastRun = frame.timestamp
            return true
        }
        guard accept else { return }
        processingQueue.async { [self] in
            process(frame)
            lock.withLock { busy = false }
        }
    }

    private func process(_ frame: ARFrame) {
        let trackingNormal: Bool
        switch frame.camera.trackingState {
        case .normal: trackingNormal = true
        case .notAvailable:
            tracker.reset()
            trackingNormal = false
        case .limited: trackingNormal = false
        }

        let wantMask = self.wantMask
        let found = perception.detect(in: frame.capturedImage, wantMask: wantMask)
        let detections = resolver.resolve(found.people, frame: frame)
        let tracks = tracker.update(detections, at: frame.timestamp)
        let hasDepth = frame.smoothedSceneDepth != nil || frame.sceneDepth != nil
        let camera = frame.camera
        let mask = found.mask.flatMap(maskImage)

        Task { @MainActor [store] in
            store.publish(tracks, camera: camera, trackingNormal: trackingNormal, hasDepth: hasDepth)
            if let mask {
                store.chamsMask = mask
            } else if !wantMask {
                store.chamsMask = nil
            }
        }
    }

    /// Grayscale person mask → white image whose alpha is the mask, ready to clip a gradient.
    private func maskImage(_ buffer: CVPixelBuffer) -> CGImage? {
        let alpha = CIImage(cvPixelBuffer: buffer).applyingFilter("CIMaskToAlpha")
        return ciContext.createCGImage(alpha, from: alpha.extent)
    }
}
