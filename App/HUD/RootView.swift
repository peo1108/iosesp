import ESPCore
import SwiftUI

/// Screen-level stack, bottom to top: camera, ESP + HUD, touch layer, controls, menu, hint, splash.
struct RootView: View {
    let model: AppModel
    @State private var menuOpen = false
    @State private var showSplash = true
    @State private var toast: ToastEvent?

    private var settings: Settings { model.settings.settings }
    private var store: ESPStore { model.store }
    private var recorder: Recorder { model.recorder }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraView(session: model.capture.session)
                .ignoresSafeArea()
            ESPOverlay(capture: model.capture, store: store, settings: settings, budget: model.budget)

            GestureLayer(onToggleMenu: toggleMenu, onToggleRecording: toggleRecording, onTap: handleTap)
                .ignoresSafeArea()

            recordingControls

            if let toast {
                ToastView(event: toast) { Task { await recorder.retrySave() } }
                    .id(toast.id)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if menuOpen {
                HStack {
                    Spacer()
                    MenuPanel(store: model.settings, modelWarning: store.modelWarning, onClose: toggleMenu)
                        .containerRelativeFrame(.horizontal) { width, _ in width * 0.4 }
                }
                .padding(.vertical, 8)
                .padding(.trailing, 8)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if !settings.hasSeenHint && !showSplash {
                HintView { model.settings.settings.set(\.hasSeenHint, true) }
            }

            if model.capture.authorization == .denied {
                PermissionView()
            } else if let failure = model.capture.failure {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Palette.partial)
                    Text("Camera gặp lỗi").font(.title3.weight(.bold))
                    Text(failure).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Thử lại") { model.capture.restart() }
                        .buttonStyle(.glassProminent)
                }
                .frame(maxWidth: 360)
                .padding(28)
                .glassEffect(.regular, in: .rect(cornerRadius: 28))
            }

            if showSplash {
                SplashView(accent: Palette.accent(settings.accent)) {
                    withAnimation(.easeOut(duration: 0.35)) { showSplash = false }
                }
                .transition(.opacity)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .sensoryFeedback(.impact(flexibility: .rigid), trigger: recorder.isRecording) { _, _ in settings.haptics }
        .onChange(of: recorder.lastEvent) { _, event in
            guard let event else { return }
            withAnimation(.spring(duration: 0.35)) { toast = event }
        }
        .task(id: toast?.id) {
            guard let current = toast else { return }
            if case .failed(_, .some) = current.kind {
                try? await Task.sleep(for: .seconds(6))
            } else {
                try? await Task.sleep(for: .seconds(2.5))
            }
            if toast?.id == current.id {
                withAnimation(.easeOut(duration: 0.3)) { toast = nil }
            }
        }
    }

    @ViewBuilder
    private var recordingControls: some View {
        // Observable, so the button moves to the thumb side when the phone turns 180°.
        let islandLeading = model.orientation.islandOnLeading
        if settings.recordButton {
            RecordButton(isRecording: recorder.isRecording, action: toggleRecording)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: islandLeading ? .trailing : .leading)
                .padding(islandLeading ? .trailing : .leading, 8)
        }
        if settings.recordIndicator && recorder.isRecording {
            RecordingDot()
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 6)
                .allowsHitTesting(false)
        }
    }

    private func toggleMenu() {
        withAnimation(.spring(duration: 0.35, bounce: 0.15)) { menuOpen.toggle() }
    }

    private func toggleRecording() {
        if !recorder.isRecording && menuOpen { toggleMenu() }
        let microphone = settings.microphone
        Task { await recorder.toggle(microphone: microphone) }
    }

    private func handleTap(_ point: CGPoint, _ size: CGSize) {
        if menuOpen { toggleMenu() }
    }
}
