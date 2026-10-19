import ESPCore
import Foundation
import Observation

/// Mirrors ProcessInfo's thermal state as an ESPCore ThermalLevel.
@MainActor @Observable
final class ThermalMonitor {
    private(set) var level: ThermalLevel = ThermalMonitor.read()
    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.level = ThermalMonitor.read() }
        }
    }

    private nonisolated static func read() -> ThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .nominal
        }
    }
}
