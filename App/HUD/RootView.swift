import SwiftUI

/// Screen-level stack. Later layers (ESP, HUD, menu) are added above the camera.
struct RootView: View {
    let capture: CaptureEngine

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraView(session: capture.session)
                .ignoresSafeArea()
            if capture.authorization == .denied {
                PermissionView()
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}
