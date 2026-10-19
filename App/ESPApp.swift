import SwiftUI

/// Long-lived objects for the app's lifetime.
@MainActor
final class AppModel {
    let capture = CaptureEngine()
    let store = ESPStore()
    let pipeline: ESPPipeline

    init() {
        pipeline = ESPPipeline(capture: capture, store: store)
    }
}

@main
struct ESPApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(capture: model.capture, store: model.store)
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
        }
    }
}
