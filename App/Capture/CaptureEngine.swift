import ARKit
import AVFoundation
import ESPCore
import Observation

enum CameraAuth {
    case unknown, granted, denied
}

/// Owns the cameras: ARKit world tracking with LiDAR depth on the 1× camera, or the 0.5× ultra-wide through
/// AVFoundation. Either way every image goes to `frameHandler` on `frameQueue` as a `CameraFrame`.
/// Knows nothing about people.
@MainActor @Observable
final class CaptureEngine: NSObject {
    nonisolated static let frameQueue = DispatchQueue(label: "esp.frames", qos: .userInitiated)

    let session = ARSession()
    let ultraWide = UltraWideCamera()
    /// The camera feeding the screen. `.wide` when the ultra-wide was asked for but the phone has none.
    private(set) var lens: CameraLens = .wide
    /// The ultra-wide was asked for and this phone doesn't have one.
    private(set) var ultraWideMissing = false
    private(set) var authorization: CameraAuth = .unknown
    private(set) var isInterrupted = false
    private(set) var isRunning = false
    /// Why the camera isn't running (ARKit unsupported or the session failed); nil when fine.
    private(set) var failure: String?

    @ObservationIgnored private var requestedLens: CameraLens = .wide
    /// Bumped on every run/pause, so a slow ultra-wide stop can't start ARKit after the user switched again.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    @ObservationIgnored private nonisolated let handlerLock = NSLock()
    @ObservationIgnored private nonisolated(unsafe) var storedHandler: ((CameraFrame) -> Void)?

    /// Called on `frameQueue` for every image.
    nonisolated var frameHandler: ((CameraFrame) -> Void)? {
        get { handlerLock.withLock { storedHandler } }
        set { handlerLock.withLock { storedHandler = newValue } }
    }

    override init() {
        super.init()
        session.delegate = self
        session.delegateQueue = Self.frameQueue
        ultraWide.frameHandler = { [weak self] frame in self?.frameHandler?(frame) }

        // The ultra-wide session reports interruptions (calls, other camera apps) and failures by notification.
        let center = NotificationCenter.default, video = ultraWide.session
        observers = [
            center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: video, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isInterrupted = true }
            },
            center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: video, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isInterrupted = false }
            },
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: video, queue: .main) { [weak self] note in
                let message = (note.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.localizedDescription
                MainActor.assumeIsolated {
                    guard let self, self.lens == .ultraWide else { return }
                    self.failure = message ?? "Camera góc siêu rộng gặp lỗi."
                    self.isRunning = false
                }
            },
        ]
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorization = .granted
            run(reset: false)
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                authorization = granted ? .granted : .denied
                if granted { run(reset: false) }
            }
        default:
            authorization = .denied
        }
    }

    func pause() {
        generation += 1
        session.pause()
        ultraWide.stop()
        isRunning = false
    }

    /// Switches cameras; takes effect right away when running, else on the next `start`.
    func setLens(_ lens: CameraLens) {
        guard lens != requestedLens else { return }
        requestedLens = lens
        if isRunning { run(reset: true) }
    }

    /// Retry after a failure (the error card's button).
    func restart() {
        failure = nil
        run(reset: true)
    }

    /// The pose to draw this display frame with, and its time: ARKit's newest frame, or the newest ultra-wide image.
    func currentPose() -> (pose: CameraPose, timestamp: TimeInterval)? {
        switch lens {
        case .wide:
            guard let frame = session.currentFrame else { return nil }
            return (CameraPose(frame.camera), frame.timestamp)
        case .ultraWide:
            return ultraWide.latestPose
        }
    }

    private func run(reset: Bool) {
        generation += 1
        let current = generation
        failure = nil
        ultraWideMissing = requestedLens == .ultraWide && !UltraWideCamera.isAvailable
        lens = ultraWideMissing ? .wide : requestedLens
        isRunning = true

        switch lens {
        case .ultraWide:
            session.pause()
            ultraWide.start { message in
                guard let message else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.generation == current else { return }
                    self.failure = message
                    self.isRunning = false
                }
            }
        case .wide:
            // ARKit can only take the camera once AVFoundation has let go of it.
            ultraWide.stop {
                Task { @MainActor [weak self] in
                    guard let self, self.generation == current else { return }
                    self.runARKit(reset: reset)
                }
            }
        }
    }

    private func runARKit(reset: Bool) {
        guard ARWorldTrackingConfiguration.isSupported else {
            failure = "Máy này không hỗ trợ ARKit world tracking."
            isRunning = false
            return
        }
        let config = ARWorldTrackingConfiguration()
        let sixty = ARWorldTrackingConfiguration.supportedVideoFormats.filter { $0.framesPerSecond == 60 }
        if let best = sixty.max(by: { pixels($0) < pixels($1) }) {
            config.videoFormat = best
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics.insert(.smoothedSceneDepth)
        }
        config.planeDetection = []
        session.run(config, options: reset ? [.resetTracking, .removeExistingAnchors] : [])
    }

    private func pixels(_ format: ARConfiguration.VideoFormat) -> CGFloat {
        format.imageResolution.width * format.imageResolution.height
    }
}

extension CaptureEngine: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        frameHandler?(CameraFrame(frame))
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: any Error) {
        let message = (error as NSError).localizedDescription
        Task { @MainActor in
            guard self.lens == .wide else { return }
            self.failure = message
            self.isRunning = false
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor in
            if self.lens == .wide { self.isInterrupted = true }
        }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor in
            guard self.lens == .wide else { return }
            self.isInterrupted = false
            if self.isRunning { self.run(reset: true) }
        }
    }
}
