import AVFoundation
import CoreMotion
import ESPCore
import simd

/// The 0.5× ultra-wide camera, which ARKit can't use: AVCaptureSession for the images and CoreMotion for how
/// the phone is turned (no position, no LiDAR). Frames arrive on `CaptureEngine.frameQueue`.
final class UltraWideCamera: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()

    static var isAvailable: Bool { device != nil }
    private static var device: AVCaptureDevice? {
        AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
    }

    /// Session setup and start/stop block, so they run here.
    private let queue = DispatchQueue(label: "esp.ultrawide", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    private let motion = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()
    private var configured = false
    /// The format applied last (4K 30 or 1920×1440 60), so a restart only reconfigures on a change.
    private var appliedHighRes: Bool?

    // Guarded by `lock`.
    private let lock = NSLock()
    private var handler: ((CameraFrame) -> Void)?
    /// Camera → world rotations by motion timestamp, so each image gets the attitude of the moment it was taken.
    private var rotations = TimedHistory<Mat4>(keep: 0.5)
    private var convention: AttitudeConvention?
    /// Horizontal field of view of the active format, degrees.
    private var fieldOfView: Float = 108
    private var latest: (pose: CameraPose, timestamp: TimeInterval)?

    /// Called on `CaptureEngine.frameQueue` for every image.
    var frameHandler: ((CameraFrame) -> Void)? {
        get { lock.withLock { handler } }
        set { lock.withLock { handler = newValue } }
    }

    /// Pose and time of the newest image, for drawing the HUD.
    var latestPose: (pose: CameraPose, timestamp: TimeInterval)? {
        lock.withLock { latest }
    }

    /// `highRes` picks 4K at 30 fps instead of 1920×1440 at 60. `completion` gets an error message, or nil once
    /// the camera runs. Called on a background queue.
    func start(highRes: Bool, completion: @escaping @Sendable (String?) -> Void) {
        queue.async { [self] in
            do {
                if !configured {
                    try configure()
                    configured = true
                }
                if appliedHighRes != highRes {
                    try applyFormat(highRes: highRes)
                    appliedHighRes = highRes
                }
                lock.withLock {
                    rotations = TimedHistory(keep: 0.5)
                    latest = nil
                }
                startMotion()
                session.startRunning()
                completion(nil)
            } catch {
                completion(error.localizedDescription)
            }
        }
    }

    /// `completion` runs once the camera is released (so ARKit can take it), on a background queue.
    func stop(completion: (@Sendable () -> Void)? = nil) {
        queue.async { [self] in
            motion.stopDeviceMotionUpdates()
            if session.isRunning { session.stopRunning() }
            completion?()
        }
    }

    // MARK: Setup

    private struct SetupError: LocalizedError {
        let errorDescription: String?
    }

    private func configure() throws {
        guard let device = Self.device else { throw SetupError(errorDescription: "Máy này không có camera góc siêu rộng.") }
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw SetupError(errorDescription: "Không mở được camera góc siêu rộng.") }
        session.addInput(input)

        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: CaptureEngine.frameQueue)
        guard session.canAddOutput(output) else { throw SetupError(errorDescription: "Không đọc được hình từ camera góc siêu rộng.") }
        session.addOutput(output)

        try device.lockForConfiguration()
        // Straight lines stay straight, so the pinhole maths (and the boxes) line up with the picture.
        if device.isGeometricDistortionCorrectionSupported { device.isGeometricDistortionCorrectionEnabled = true }
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        device.unlockForConfiguration()

        if let connection = output.connection(with: .video) {
            // The sensor's own landscape orientation, the same as ARKit's captured image.
            if connection.isVideoRotationAngleSupported(0) { connection.videoRotationAngle = 0 }
            // Stabilization crops, warps and delays the picture; the ESP wants it raw.
            if connection.isVideoStabilizationSupported { connection.preferredVideoStabilizationMode = .off }
            if connection.isCameraIntrinsicMatrixDeliverySupported { connection.isCameraIntrinsicMatrixDeliveryEnabled = true }
        }
    }

    /// Switches between 4K 30 fps and 1920×1440 60 fps (falling back to what the camera has).
    private func applyFormat(highRes: Bool) throws {
        guard let device = Self.device else { return }
        let fps: Double = highRes ? 30 : 60
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        if let format = Self.bestFormat(device, maxWidth: highRes ? 4096 : 1920, fps: fps) {
            device.activeFormat = format
            let top = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? fps
            let duration = CMTime(value: 1, timescale: CMTimeScale(min(top, fps)))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
        }
        device.activeMaxExposureDuration = MotionBlur.cap(for: device.activeFormat)
        let format = device.activeFormat
        let fov = device.isGeometricDistortionCorrectionEnabled ? format.geometricDistortionCorrectedVideoFieldOfView
                                                                : format.videoFieldOfView
        lock.withLock { fieldOfView = fov > 0 ? fov : 108 }
    }

    /// 4:3 like the models' input, up to `maxWidth`, reaching `fps` if any can: the largest such format.
    private static func bestFormat(_ device: AVCaptureDevice, maxWidth: Int32, fps: Double) -> AVCaptureDevice.Format? {
        func size(_ f: AVCaptureDevice.Format) -> CMVideoDimensions { CMVideoFormatDescriptionGetDimensions(f.formatDescription) }
        let fourThree = device.formats.filter { f in
            let d = size(f)
            return CMFormatDescriptionGetMediaSubType(f.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                && d.width <= maxWidth && abs(Double(d.width) / Double(d.height) - 4.0 / 3) < 0.01
        }
        let fastEnough = fourThree.filter { f in f.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= fps } }
        return (fastEnough.isEmpty ? fourThree : fastEnough).max { size($0).width < size($1).width }
    }

    private func startMotion() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 100
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: motionQueue) { [weak self] sample, _ in
            guard let self, let sample else { return }
            let m = sample.attitude.rotationMatrix
            let rows = (Vec3(Float(m.m11), Float(m.m12), Float(m.m13)),
                        Vec3(Float(m.m21), Float(m.m22), Float(m.m23)),
                        Vec3(Float(m.m31), Float(m.m32), Float(m.m33)))
            let gravity = Vec3(Float(sample.gravity.x), Float(sample.gravity.y), Float(sample.gravity.z))
            self.lock.withLock {
                // Settle the matrix's reading once, on the first sample that tells them apart.
                if self.convention == nil { self.convention = MotionPose.convention(attitudeRows: rows, gravity: gravity) }
                let rotation = MotionPose.cameraToWorld(attitudeRows: rows, convention: self.convention ?? .referenceToDevice)
                self.rotations.insert(rotation, at: sample.timestamp)
            }
        }
    }
}

extension UltraWideCamera: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let image = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let size = Vec2(Float(CVPixelBufferGetWidth(image)), Float(CVPixelBufferGetHeight(image)))

        let (rotation, fov, handler) = lock.withLock { (rotations.value(at: timestamp), fieldOfView, self.handler) }
        let intrinsics = Self.intrinsics(of: sampleBuffer, size: size)
            ?? MotionPose.intrinsics(horizontalFOVDegrees: fov, imageSize: size)
        let pose = CameraPose(intrinsics: intrinsics, cameraToWorld: rotation ?? .identity)
        lock.withLock { latest = (pose, timestamp) }
        handler?(CameraFrame(image: image, timestamp: timestamp, pose: pose,
                             tracking: rotation == nil ? .limited : .normal, depth: nil))
    }

    /// The per-frame intrinsic matrix, when the connection delivers one.
    private static func intrinsics(of buffer: CMSampleBuffer, size: Vec2) -> CameraIntrinsics? {
        guard let data = CMGetAttachment(buffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix,
                                         attachmentModeOut: nil) as? Data,
              data.count >= MemoryLayout<matrix_float3x3>.size
        else { return nil }
        let k = data.withUnsafeBytes { $0.loadUnaligned(as: matrix_float3x3.self) }
        guard k.columns.0.x > 0, k.columns.1.y > 0 else { return nil }
        return CameraIntrinsics(fx: k.columns.0.x, fy: k.columns.1.y, cx: k.columns.2.x, cy: k.columns.2.y, imageSize: size)
    }
}
