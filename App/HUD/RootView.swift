import ESPCore
import SwiftUI

/// Screen-level stack, bottom to top: camera, ESP, touch layer, menu, hint.
struct RootView: View {
    let model: AppModel
    @State private var menuOpen = false

    private var settings: Settings { model.settings.settings }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraView(session: model.capture.session)
                .ignoresSafeArea()
            ESPOverlay(capture: model.capture, store: model.store, settings: settings, budget: model.budget)

            GestureLayer(onToggleMenu: toggleMenu, onToggleRecording: {}, onTap: handleTap)
                .ignoresSafeArea()

            if menuOpen {
                HStack {
                    Spacer()
                    MenuPanel(store: model.settings, onClose: toggleMenu)
                        .containerRelativeFrame(.horizontal) { width, _ in width * 0.4 }
                }
                .padding(.vertical, 8)
                .padding(.trailing, 8)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if !settings.hasSeenHint {
                HintView { model.settings.settings.set(\.hasSeenHint, true) }
            }

            if model.capture.authorization == .denied {
                PermissionView()
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    private func toggleMenu() {
        withAnimation(.spring(duration: 0.35, bounce: 0.15)) { menuOpen.toggle() }
    }

    private func handleTap(_ point: CGPoint) {
        if menuOpen { toggleMenu() }
    }
}
