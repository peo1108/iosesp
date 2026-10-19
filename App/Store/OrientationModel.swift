import ESPCore
import Observation
import UIKit

/// Observable interface orientation. A landscapeLeft ↔ landscapeRight turn changes neither the view size
/// nor the (symmetric) safe-area insets, so SwiftUI would not re-render on it without this.
@MainActor @Observable
final class OrientationModel {
    private(set) var interfaceOrientation: UIInterfaceOrientation = .landscapeRight
    @ObservationIgnored private var observation: NSKeyValueObservation?

    /// In landscapeRight the top of the phone (and its Dynamic Island) is on the left.
    var islandOnLeading: Bool { interfaceOrientation != .landscapeLeft }

    /// Vision models expect upright people; in landscapeLeft the captured image is upside down.
    var visionOrientation: VisionOrientation { interfaceOrientation == .landscapeLeft ? .down : .up }

    /// Starts following the window scene. Safe to call repeatedly.
    func attach() {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        interfaceOrientation = scene.effectiveGeometry.interfaceOrientation
        guard observation == nil else { return }
        observation = scene.observe(\.effectiveGeometry, options: [.new]) { [weak self] scene, _ in
            MainActor.assumeIsolated {
                self?.interfaceOrientation = scene.effectiveGeometry.interfaceOrientation
            }
        }
    }
}
