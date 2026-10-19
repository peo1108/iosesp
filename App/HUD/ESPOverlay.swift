import ESPCore
import SwiftUI

/// Everything drawn on people, re-laid-out every display frame from the latest camera pose.
struct ESPOverlay: View {
    let capture: CaptureEngine
    let store: ESPStore

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 60)) { _ in
                let layouts = currentLayouts(size: geo.size)
                ZStack {
                    ESPCanvas(layouts: layouts, boxStyle: .corner)
                    PlayerGlassViews(layouts: layouts)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func currentLayouts(size: CGSize) -> [PlayerLayout] {
        guard let frame = capture.session.currentFrame else { return [] }
        return ESPLayout.compute(store: store, frame: frame, viewSize: size, lockedID: nil)
    }
}
