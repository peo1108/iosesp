import ESPCore
import Observation
import SwiftUI

/// Long-lived objects for the app's lifetime.
@MainActor @Observable
final class AppModel {
    let capture = CaptureEngine()
    let store = ESPStore()
    let settings = SettingsStore()
    let thermal = ThermalMonitor()
    let pipeline: ESPPipeline
    var isRecording = false

    init() {
        pipeline = ESPPipeline(capture: capture, store: store)
    }

    var budget: PerceptionBudget {
        ThermalPolicy.budget(thermal.level, isRecording: isRecording)
    }

    /// Anything on screen that needs fresh perception results.
    private var needsPerception: Bool {
        let s = settings.settings
        return s.box || s.skeleton || s.chams || s.snaplines || s.name || s.health || s.distance || s.headDot
            || s.offscreenArrows || s.aimbot || s.radar || s.stats || s.fakeIsland || s.shooting
    }

    /// Pushes the thermal budget and current settings into the perception pipeline.
    func applyBudget() {
        let budget = budget
        // Idle at 10 Hz when nothing is shown, so a reveal is instant without heating the phone.
        pipeline.targetHz = needsPerception ? budget.hz : min(budget.hz, 10)
        pipeline.wantMask = settings.settings.chams && budget.chamsAllowed
    }
}

@main
struct ESPApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    switch phase {
                    case .active: model.capture.start()
                    case .background:
                        model.capture.pause()
                        model.pipeline.reset()
                    default: break
                    }
                }
                .onChange(of: model.capture.isInterrupted) { _, interrupted in
                    if interrupted { model.pipeline.reset() }
                }
                .onChange(of: model.settings.settings, initial: true) { model.applyBudget() }
                .onChange(of: model.budget) { model.applyBudget() }
        }
    }
}
