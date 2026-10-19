import ARKit
import CoreImage
import ESPCore

/// Capture → Perception → Spatial → Tracker → Store. Heavy work runs on `processingQueue`;
/// frames that arrive while it is busy, or faster than `poseHz`, are dropped. The animal/object model runs
/// on its own slower gate (`objectHz`) inside the same pass.
final class ESPPipeline: @unchecked Sendable {
    /// YOLO when the compiled models are bundled; otherwise people come from Vision. Loaded lazily on the
    /// processing queue: the first Neural Engine load can take seconds and must not block launch.
    private lazy var yolo: YOLOPerception? = {
        let loaded = YOLOPerception()
        let store = self.store
        Task { @MainActor in store.modelWarning = loaded == nil }
        return loaded
    }()
    private let vision = PerceptionPipeline()
    private let resolver = SpatialResolver()
    private let tracker = Tracker()
    private let processingQueue = DispatchQueue(label: "esp.perception", qos: .userInitiated)
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let store: ESPStore

    // Processing-queue only.
    private var objectGate = FrameGate()
    private var objects: [DetectedObject] = []

    // Guarded by `lock`.
    private let lock = NSLock()
    private var busy = false
    private var poseGate = FrameGate()
    private var _poseHz: Double = 30
    private var _objectHz: Double = 15
    private var _wantMask = true
    private var _visionOrientation: VisionOrientation = .up

    var poseHz: Double {
        get { lock.withLock { _poseHz } }
        set { lock.withLock { _poseHz = newValue } }
    }

    /// 0 turns the animal/object model off.
    var objectHz: Double {
        get { lock.withLock { _objectHz } }
        set { lock.withLock { _objectHz = newValue } }
    }

    /// Whether to produce the Chams person mask.
    var wantMask: Bool {
        get { lock.withLock { _wantMask } }
        set { lock.withLock { _wantMask = newValue } }
    }

    /// Follows the interface orientation so the models always see people upright.
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
        processingQueue.async { [self] in
            tracker.reset()
            objects = []
            Task { @MainActor [store] in store.clear() }
        }
    }

    private func offer(_ frame: ARFrame) {
        let accept: Bool = lock.withLock {
            guard !busy, poseGate.shouldRun(at: frame.timestamp, hz: _poseHz) else { return false }
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

        let (wantMask, orientation, objectHz) = lock.withLock { (_wantMask, _visionOrientation, _objectHz) }
        let image = frame.capturedImage
        let yolo = self.yolo

        // People: YOLO-pose, or Vision as a fallback. Vision also makes the Chams mask.
        let visionPass = vision.detect(in: image, orientation: orientation, wantPeople: yolo == nil, wantMask: wantMask)
        var raw = yolo?.people(in: image, orientation: orientation) ?? visionPass.people

        // Animals & objects on their own slower gate.
        var animalsObserved = false
        if let yolo, objectHz > 0, objectGate.shouldRun(at: frame.timestamp, hz: objectHz) {
            let things = yolo.things(in: image, orientation: orientation)
            raw += things.animals
            objects = things.objects
            animalsObserved = true
        } else if objectHz <= 0 {
            // The animal model is off: let existing animal tracks age out instead of freezing on screen.
            objects = []
            animalsObserved = true
        }

        let detections = resolver.resolve(raw, frame: frame)
        let tracks = tracker.update(detections, at: frame.timestamp, animalsObserved: animalsObserved)
        let hasDepth = frame.smoothedSceneDepth != nil || frame.sceneDepth != nil
        let camera = frame.camera
        let timestamp = frame.timestamp
        let objects = self.objects
        let mask = visionPass.mask.flatMap { maskImage($0, orientation: orientation) }

        Task { @MainActor [store] in
            store.publish(tracks, objects: objects, orientation: orientation, camera: camera, at: timestamp,
                          trackingNormal: trackingNormal, hasDepth: hasDepth)
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
