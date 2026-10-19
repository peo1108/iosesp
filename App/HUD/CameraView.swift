import ARKit
import AVFoundation
import RealityKit
import SwiftUI

/// Full-screen feed of whichever camera CaptureEngine is running. Both previews aspect-fill the sensor image
/// and turn it 180° in landscapeLeft, which is what ScreenMapper assumes.
struct CameraView: View {
    let capture: CaptureEngine
    let orientation: UIInterfaceOrientation

    var body: some View {
        switch capture.lens {
        case .wide:
            ARCameraView(session: capture.session)
        case .ultraWide:
            VideoPreviewView(session: capture.ultraWide.session, upsideDown: orientation == .landscapeLeft)
        }
    }
}

/// RealityKit only renders the ARSession's camera image; the session itself is run by CaptureEngine.
private struct ARCameraView: UIViewRepresentable {
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

private struct VideoPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let upsideDown: Bool

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.upsideDown = upsideDown
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.upsideDown = upsideDown
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        var upsideDown = false {
            didSet { applyRotation() }
        }

        private nonisolated(unsafe) var startObserver: NSObjectProtocol?

        override init(frame: CGRect) {
            super.init(frame: frame)
            // The camera is attached on a background queue; once it runs, the preview's connection exists.
            startObserver = NotificationCenter.default.addObserver(forName: AVCaptureSession.didStartRunningNotification,
                                                                   object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyRotation() }
            }
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not used")
        }

        deinit {
            if let startObserver { NotificationCenter.default.removeObserver(startObserver) }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            // The connection only exists once the session has its camera; catch it on the next layout.
            applyRotation()
        }

        private func applyRotation() {
            let angle: CGFloat = upsideDown ? 180 : 0
            guard let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(angle),
                  connection.videoRotationAngle != angle else { return }
            connection.videoRotationAngle = angle
        }
    }
}
