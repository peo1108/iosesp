import ARKit
import RealityKit
import SwiftUI

/// Full-screen camera feed. RealityKit only renders the ARSession's camera image;
/// the session itself is configured and run by CaptureEngine.
struct CameraView: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.session = session
        view.renderOptions = [.disableMotionBlur, .disableDepthOfField, .disableCameraGrain, .disableHDR]
        view.environment.background = .cameraFeed()
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
