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
        capture.setLens(settings.settings.lens)
    }

    var budget: PerceptionBudget {
        ThermalPolicy.budget(thermal.level, isRecording: recorder.isRecording)
    }

    /// Anything on screen that needs fresh perception results.
    private var needsPerception: Bool {
        let s = settings.settings
        return s.box || s.detailCard || s.snaplines || s.offscreenArrows || s.stats || s.playerList || s.eventLog
    }

    /// Pushes the thermal budget and current settings into the perception pipeline.
    func applyBudget() {
        let budget = budget
        // Idle at 10 Hz when nothing is shown, so a reveal is instant without heating the phone.
        pipeline.poseHz = needsPerception ? budget.poseHz : min(budget.poseHz, 10)
        // The plain detector runs at full rate for animals, at half rate otherwise just to catch half-hidden people.
        let showAnimals = settings.settings.showAnimals
        pipeline.objectHz = needsPerception ? (showAnimals ? budget.objectHz : budget.objectHz / 2) : 0
        pipeline.wantAnimals = showAnimals
    }

    /// Switches cameras; tracks from the old one mean nothing to the new one.
    func applyLens() {
        capture.setLens(settings.settings.lens)
        pipeline.reset()
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
                .onChange(of: model.settings.settings.lens) { model.applyLens() }
                .onChange(of: model.budget) { model.applyBudget() }
                .onChange(of: model.orientation.interfaceOrientation, initial: true) {
                    model.pipeline.visionOrientation = model.orientation.visionOrientation
                }
        }
    }
}
