import Foundation
import Observation
import Photos
import ReplayKit
import UIKit

struct ToastEvent: Identifiable, Equatable {
    enum Action: Equatable {
        case retry, openSettings
    }

    enum Kind: Equatable {
        case saved
        case failed(String, action: Action?)
    }

    let id = UUID()
    let kind: Kind
}

/// In-app screen recording (ReplayKit captures the Liquid Glass HUD too) saved to Photos.
@MainActor @Observable
final class Recorder: NSObject, RPScreenRecorderDelegate {
    private static let pendingKey = "esp.pendingRecording"

    private(set) var isRecording = false
    /// Latest outcome for the toast.
    private(set) var lastEvent: ToastEvent?
    /// Start/stop in flight; further toggles are ignored until it finishes.
    @ObservationIgnored private var busy = false

    /// A finished recording that could not be saved yet. Survives relaunches (file name in UserDefaults).
    @ObservationIgnored private var pendingURL: URL? {
        didSet { UserDefaults.standard.set(pendingURL?.lastPathComponent, forKey: Self.pendingKey) }
    }

    override init() {
        super.init()
        RPScreenRecorder.shared().delegate = self
        if let name = UserDefaults.standard.string(forKey: Self.pendingKey) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            pendingURL = FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }

    func toggle(microphone: Bool) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        if isRecording {
            await stopAndSave()
        } else {
            await start(microphone: microphone)
        }
    }

    /// Stops and saves when the app leaves the foreground mid-recording.
    func stopForBackground() {
        guard isRecording, !busy else { return }
        busy = true
        var task = UIBackgroundTaskIdentifier.invalid
        task = UIApplication.shared.beginBackgroundTask(withName: "esp.save-recording") {
            UIApplication.shared.endBackgroundTask(task)
        }
        Task {
            await stopAndSave()
            busy = false
            UIApplication.shared.endBackgroundTask(task)
        }
    }

    /// Saves a kept recording when Photos access is now allowed, without prompting (e.g. back from Settings).
    func savePendingIfAllowed() async {
        guard let url = pendingURL, !busy else { return }
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard status == .authorized || status == .limited else { return }
        await save(url)
    }

    func retrySave() async {
        guard let url = pendingURL, !busy else { return }
        await save(url)
    }

    // MARK: RPScreenRecorderDelegate

    /// The system ended the recording on its own (Control Center, interruption, error).
    nonisolated func screenRecorder(_ screenRecorder: RPScreenRecorder,
                                    didStopRecordingWith previewViewController: RPPreviewViewController?, error: (any Error)?) {
        Task { @MainActor in
            guard self.isRecording, !self.busy else { return }
            self.isRecording = false
            self.lastEvent = ToastEvent(kind: .failed("Hệ thống đã dừng quay", action: nil))
        }
    }

    // MARK: Private

    private func start(microphone: Bool) async {
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else {
            lastEvent = ToastEvent(kind: .failed("Không quay được màn hình", action: nil))
            return
        }
        recorder.isMicrophoneEnabled = microphone
        do {
            try await recorder.startRecording()
            isRecording = true
        } catch {
            lastEvent = ToastEvent(kind: .failed("Không quay được màn hình", action: nil))
        }
    }

    private func stopAndSave() async {
        guard isRecording else { return }
        guard RPScreenRecorder.shared().isRecording else {
            isRecording = false
            lastEvent = ToastEvent(kind: .failed("Hệ thống đã dừng quay", action: nil))
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ESP-\(Self.stamp()).mp4")
        do {
            try await RPScreenRecorder.shared().stopRecording(withOutput: url)
            isRecording = false
            await save(url)
        } catch {
            isRecording = false
            lastEvent = ToastEvent(kind: .failed("Dừng quay thất bại", action: nil))
        }
    }

    private func save(_ url: URL) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            // Denied once means iOS won't ask again: send the person to Settings; the file waits.
            pendingURL = url
            lastEvent = ToastEvent(kind: .failed("Chưa cho phép lưu vào Ảnh", action: .openSettings))
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil)
            }
            try? FileManager.default.removeItem(at: url)
            pendingURL = nil
            lastEvent = ToastEvent(kind: .saved)
        } catch {
            pendingURL = url
            lastEvent = ToastEvent(kind: .failed("Lưu thất bại", action: .retry))
        }
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}
