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

    // Guarded by `lock`.
    private let lock = NSLock()
    private var busy = false
    private var gate = FrameGate()
    private var _targetHz: Double = 30
    private var _wantMask = true
    private var _visionOrientation: VisionOrientation = .up

    var targetHz: Double {
        get { lock.withLock { _targetHz } }
        set { lock.withLock { _targetHz = newValue } }
    }

    /// Whether to produce the Chams person mask.
    var wantMask: Bool {
        get { lock.withLock { _wantMask } }
        set { lock.withLock { _wantMask = newValue } }
    }

    /// Follows the interface orientation so Vision always sees people upright.
    var visionOrientation: VisionOrientation {
        get { lock.withLock { _visionOrientation } }
        set { lock.withLock { _visionOrientation = newValue } }
    }

    @MainActor
    init(capture: CaptureEngine, store: ESPStore) {
        self.store = store
        capture.frameHandler = { [weak self] frame in self?.offer(frame) }
    }

    /// Clears tracks and everything on screen, e.g. after an interruption or going to the background.
    func reset() {
        processingQueue.async { [tracker, store] in
            tracker.reset()
            Task { @MainActor in store.clear() }
        }
    }

    private func offer(_ frame: ARFrame) {
        let accept: Bool = lock.withLock {
            guard !busy, gate.shouldRun(at: frame.timestamp, hz: _targetHz) else { return false }
            busy = true
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

        let (wantMask, orientation) = lock.withLock { (_wantMask, _visionOrientation) }
        let found = perception.detect(in: frame.capturedImage, orientation: orientation, wantMask: wantMask)
        let detections = resolver.resolve(found.people, frame: frame)
        let tracks = tracker.update(detections, at: frame.timestamp)
        let hasDepth = frame.smoothedSceneDepth != nil || frame.sceneDepth != nil
        let camera = frame.camera
        let timestamp = frame.timestamp
        let mask = found.mask.flatMap { maskImage($0, orientation: orientation) }

        Task { @MainActor [store] in
            store.publish(tracks, camera: camera, at: timestamp, trackingNormal: trackingNormal, hasDepth: hasDepth)
            if let mask {
                store.chamsMask = mask
            } else if !wantMask {
                store.chamsMask = nil
            }
        }
    }

    /// Grayscale person mask → white image whose alpha is the mask, in captured-image orientation,
    /// ready to clip a gradient.
    private func maskImage(_ buffer: CVPixelBuffer, orientation: VisionOrientation) -> CGImage? {
        var mask = CIImage(cvPixelBuffer: buffer)
        if orientation == .down { mask = mask.oriented(.down) }
        let alpha = mask.applyingFilter("CIMaskToAlpha")
        return ciContext.createCGImage(alpha, from: alpha.extent)
    }
}
