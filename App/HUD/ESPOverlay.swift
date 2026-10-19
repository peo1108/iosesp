import ESPCore
import SwiftUI

/// Everything drawn on people, re-laid-out every display frame from the latest camera pose.
struct ESPOverlay: View {
    let capture: CaptureEngine
    let store: ESPStore

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
                let layout = currentLayout(size: geo.size)
                ZStack {
                    ChamsView(mask: store.chamsMask, mapper: layout?.mapper, accent: Color(uiColor: .systemBlue), time: timeline.date)
                    ESPCanvas(layouts: layout?.players ?? [], options: .init(boxStyle: .threeD))
                    PlayerGlassViews(layouts: layout?.players ?? [])
                    OffscreenArrowsView(markers: layout?.offscreen ?? [])
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func currentLayout(size: CGSize) -> ESPFrameLayout? {
        guard let frame = capture.session.currentFrame else { return nil }
        return ESPLayout.compute(store: store, frame: frame, viewSize: size, lockedID: nil)
    }
}
