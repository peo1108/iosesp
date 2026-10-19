import ARKit
import AVFoundation
import Observation

enum CameraAuth {
    case unknown, granted, denied
}

/// Owns the ARSession: configures world tracking with LiDAR depth and fans each
/// frame out to `frameHandler` on `frameQueue`. Knows nothing about people.
@MainActor @Observable
final class CaptureEngine: NSObject {
    nonisolated static let frameQueue = DispatchQueue(label: "esp.frames", qos: .userInitiated)

    let session = ARSession()
    private(set) var hasDepth = false
    private(set) var authorization: CameraAuth = .unknown
    private(set) var isInterrupted = false
    private(set) var isRunning = false

    @ObservationIgnored private nonisolated let handlerLock = NSLock()
    @ObservationIgnored private nonisolated(unsafe) var storedHandler: ((ARFrame) -> Void)?

    /// Called on `frameQueue` for every ARFrame. Must not retain the frame after returning.
    nonisolated var frameHandler: ((ARFrame) -> Void)? {
        get { handlerLock.withLock { storedHandler } }
        set { handlerLock.withLock { storedHandler = newValue } }
    }

    override init() {
        super.init()
        session.delegate = self
        session.delegateQueue = Self.frameQueue
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
        session.pause()
        isRunning = false
    }

    private func run(reset: Bool) {
        guard ARWorldTrackingConfiguration.isSupported else { return }
        let config = ARWorldTrackingConfiguration()
        let sixty = ARWorldTrackingConfiguration.supportedVideoFormats.filter { $0.framesPerSecond == 60 }
        if let best = sixty.max(by: { pixels($0) < pixels($1) }) {
            config.videoFormat = best
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics.insert(.smoothedSceneDepth)
            hasDepth = true
        } else {
            hasDepth = false
        }
        config.planeDetection = []
        session.run(config, options: reset ? [.resetTracking, .removeExistingAnchors] : [])
        isRunning = true
    }

    private func pixels(_ format: ARConfiguration.VideoFormat) -> CGFloat {
        format.imageResolution.width * format.imageResolution.height
    }
}

extension CaptureEngine: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        frameHandler?(frame)
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor in self.isInterrupted = true }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor in
            self.isInterrupted = false
            if self.isRunning { self.run(reset: true) }
        }
    }
}
