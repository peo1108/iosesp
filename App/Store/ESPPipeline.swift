import ESPCore
import Foundation

/// Capture → Perception → Spatial → Tracker → Store. Heavy work runs on `processingQueue`;
/// frames that arrive while it is busy, or faster than `poseHz`, are dropped. The plain detector (animals, and
/// backup people for those half hidden) runs on its own slower gate (`objectHz`) inside the same pass.
final class ESPPipeline: @unchecked Sendable {
    /// YOLO when the compiled models are bundled; otherwise people come from Vision. Loaded lazily on the
    /// processing queue: the first Neural Engine load can take seconds and must not block launch.
    private lazy var yolo: YOLOPerception? = {
        let loaded = YOLOPerception()
        let store = self.store
        Task { @MainActor in store.modelWarning = loaded == nil }
        return loaded
    }()
    private lazy var vision = PerceptionPipeline()
    private let resolver = SpatialResolver()
    private let tracker = Tracker()
    private let processingQueue = DispatchQueue(label: "esp.perception", qos: .userInitiated)
    private let store: ESPStore

    // Processing-queue only.
    private var objectGate = FrameGate()

    // Guarded by `lock`.
    private let lock = NSLock()
    private var busy = false
    private var poseGate = FrameGate()
    private var _poseHz: Double = 60
    private var _objectHz: Double = 30
    private var _wantAnimals = false
    private var _visionOrientation: VisionOrientation = .up

    var poseHz: Double {
        get { lock.withLock { _poseHz } }
        set { lock.withLock { _poseHz = newValue } }
    }

    /// 0 turns the plain detector off.
    var objectHz: Double {
        get { lock.withLock { _objectHz } }
        set { lock.withLock { _objectHz = newValue } }
    }

    /// Animals become tracks only when shown.
    var wantAnimals: Bool {
        get { lock.withLock { _wantAnimals } }
        set { lock.withLock { _wantAnimals = newValue } }
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

    /// Clears tracks and everything on screen, e.g. after an interruption, a camera switch or going to the background.
    func reset() {
        processingQueue.async { [self] in
            tracker.reset()
            objectGate = FrameGate()
            Task { @MainActor [store] in store.clear() }
        }
    }

    private func offer(_ frame: CameraFrame) {
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

    private func process(_ frame: CameraFrame) {
        if frame.tracking == .unavailable { tracker.reset() }
        let (orientation, objectHz, wantAnimals) = lock.withLock { (_visionOrientation, _objectHz, _wantAnimals) }
        let image = frame.image

        // People: YOLO-pose, or Vision as a fallback.
        var raw: [RawDetection]
        if let yolo {
            raw = yolo.people(in: image, orientation: orientation)
        } else {
            raw = vision.detect(in: image, orientation: orientation)
        }

        // Plain detector on its own slower gate: animals, and people the pose model missed (half hidden).
        var animalsObserved = !wantAnimals   // animals off: let existing animal tracks age out
        if let yolo, objectHz > 0, objectGate.shouldRun(at: frame.timestamp, hz: objectHz) {
            let things = yolo.things(in: image, orientation: orientation)
            if wantAnimals { raw += things.animals }
            let posed = raw.filter { $0.kind.isPerson }.map(\.box)
            raw += PersonFusion.uncovered(things.people.map(\.box), by: posed).map { things.people[$0] }
            animalsObserved = true
        } else if objectHz <= 0 {
            animalsObserved = true
        }

        let detections = resolver.resolve(raw, frame: frame)
        let tracks = tracker.update(detections, at: frame.timestamp, animalsObserved: animalsObserved)
        let pose = frame.pose, timestamp = frame.timestamp, trackingNormal = frame.tracking == .normal

        Task { @MainActor [store] in
            store.publish(tracks, pose: pose, at: timestamp, trackingNormal: trackingNormal)
        }
    }
}
