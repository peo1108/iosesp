import SwiftUI

/// Screen-level stack. Later layers (HUD, menu) are added above the ESP overlay.
struct RootView: View {
    let capture: CaptureEngine
    let store: ESPStore

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraView(session: capture.session)
                .ignoresSafeArea()
            ESPOverlay(capture: capture, store: store)
            if capture.authorization == .denied {
                PermissionView()
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}
