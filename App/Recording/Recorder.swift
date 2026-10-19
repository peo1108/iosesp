import Foundation
import Observation
import Photos
import ReplayKit
import UIKit

struct ToastEvent: Identifiable, Equatable {
    enum Kind: Equatable {
        case saved
        case failed(String, canRetry: Bool)
    }

    let id = UUID()
    let kind: Kind
}

/// In-app screen recording (ReplayKit captures the Liquid Glass HUD too) saved to Photos.
@MainActor @Observable
final class Recorder {
    private(set) var isRecording = false
    /// Latest outcome for the toast.
    private(set) var lastEvent: ToastEvent?
    /// A finished recording that could not be saved yet, kept for "Thử lại".
    @ObservationIgnored private var pendingURL: URL?

    func toggle(microphone: Bool) async {
        if isRecording {
            await stop()
        } else {
            await start(microphone: microphone)
        }
    }

    func stop() async {
        guard isRecording else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ESP-\(Self.stamp()).mp4")
        do {
            try await RPScreenRecorder.shared().stopRecording(withOutput: url)
            isRecording = false
            await save(url)
        } catch {
            isRecording = false
            lastEvent = ToastEvent(kind: .failed("Dừng quay thất bại", canRetry: false))
        }
    }

    /// Stops and saves when the app leaves the foreground mid-recording.
    func stopForBackground() {
        guard isRecording else { return }
        let task = UIApplication.shared.beginBackgroundTask(withName: "esp.save-recording")
        Task {
            await stop()
            UIApplication.shared.endBackgroundTask(task)
        }
    }

    func retrySave() async {
        guard let url = pendingURL else { return }
        await save(url)
    }

    private func start(microphone: Bool) async {
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else {
            lastEvent = ToastEvent(kind: .failed("Không quay được màn hình", canRetry: false))
            return
        }
        recorder.isMicrophoneEnabled = microphone
        do {
            try await recorder.startRecording()
            isRecording = true
        } catch {
            lastEvent = ToastEvent(kind: .failed("Không quay được màn hình", canRetry: false))
        }
    }

    private func save(_ url: URL) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            pendingURL = url
            lastEvent = ToastEvent(kind: .failed("Chưa cho phép lưu vào Ảnh", canRetry: true))
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
            lastEvent = ToastEvent(kind: .failed("Lưu thất bại", canRetry: true))
        }
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}
