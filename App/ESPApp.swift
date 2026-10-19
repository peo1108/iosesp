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
    let recorder = Recorder()
    let orientation = OrientationModel()
    let pipeline: ESPPipeline

    init() {
        pipeline = ESPPipeline(capture: capture, store: store)
    }

    var budget: PerceptionBudget {
        ThermalPolicy.budget(thermal.level, isRecording: recorder.isRecording)
    }

    /// Anything on screen that needs fresh perception results.
    private var needsPerception: Bool {
        let s = settings.settings
        return s.box || s.skeleton || s.chams || s.snaplines || s.label || s.activity || s.detailCard || s.distance
            || s.headDot || s.trails || s.offscreenArrows || s.radar || s.stats || s.playerList || s.eventLog
            || s.fakeIsland || s.showObjects
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
                    case .active:
                        model.orientation.attach()
                        model.capture.start()
                        Task { await model.recorder.savePendingIfAllowed() }
                    case .background:
                        model.recorder.stopForBackground()
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
                .onChange(of: model.orientation.interfaceOrientation, initial: true) {
                    model.pipeline.visionOrientation = model.orientation.visionOrientation
                }
        }
    }
}
