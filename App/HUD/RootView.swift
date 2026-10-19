import ESPCore
import SwiftUI

/// Screen-level stack, bottom to top: camera, ESP + HUD, game effects, touch layer, menu, hint.
struct RootView: View {
    let model: AppModel
    @State private var menuOpen = false

    private var settings: Settings { model.settings.settings }
    private var store: ESPStore { model.store }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraView(session: model.capture.session)
                .ignoresSafeArea()
            ESPOverlay(capture: model.capture, store: store, settings: settings, budget: model.budget)

            DamageFXView(damage: store.damageFX, hitMarkers: store.hitMarkers, eliminations: store.eliminations,
                         accent: Palette.accent(settings.accent))
                .ignoresSafeArea()

            if settings.killFeed {
                KillFeedView(entries: store.killFeed)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 12)
                    .padding(.trailing, 4)
            }

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
        .sensoryFeedback(trigger: store.lastHit) { _, hit in
            guard settings.haptics, let hit else { return nil }
            return hit.killed ? .impact(weight: .heavy) : .impact(weight: .medium)
        }
    }

    private func toggleMenu() {
        withAnimation(.spring(duration: 0.35, bounce: 0.15)) { menuOpen.toggle() }
    }

    private func handleTap(_ point: CGPoint, _ size: CGSize) {
        if menuOpen {
            toggleMenu()
            return
        }
        guard settings.shooting, let frame = model.capture.session.currentFrame else { return }
        let layout = ESPLayout.compute(store: store, frame: frame, viewSize: size, lockedID: nil)
        store.shoot(at: point, players: layout.players)
    }
}
