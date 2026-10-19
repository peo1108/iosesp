import SwiftUI

@main
struct ESPApp: App {
    @State private var capture = CaptureEngine()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(capture: capture)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    switch phase {
                    case .active: capture.start()
                    case .background: capture.pause()
                    default: break
                    }
                }
        }
    }
}
