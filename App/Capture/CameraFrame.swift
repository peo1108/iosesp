import ARKit
import CoreVideo
import ESPCore

/// One camera image with everything perception needs, from ARKit (1×) or AVFoundation (0.5×).
struct CameraFrame: @unchecked Sendable {
    enum Tracking {
        /// The camera pose is good: boxes can be re-projected and edge arrows placed.
        case normal
        case limited
        /// No pose at all; world positions are meaningless.
        case unavailable
    }

    let image: CVPixelBuffer
    /// Host clock seconds (ARFrame and AVFoundation timestamps share it).
    let timestamp: TimeInterval
    let pose: CameraPose
    let tracking: Tracking
    /// LiDAR depth aligned with `image`; 1× camera only.
    let depth: ARDepthData?
}

extension CameraFrame {
    init(_ frame: ARFrame) {
        image = frame.capturedImage
        timestamp = frame.timestamp
        pose = CameraPose(frame.camera)
        switch frame.camera.trackingState {
        case .normal: tracking = .normal
        case .limited: tracking = .limited
        case .notAvailable: tracking = .unavailable
        }
        depth = frame.sceneDepth ?? frame.smoothedSceneDepth
    }
}
