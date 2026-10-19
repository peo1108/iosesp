import ESPCore
import SwiftUI

/// Everything drawn on people, re-laid-out every display frame from the latest camera pose.
struct ESPOverlay: View {
    let capture: CaptureEngine
    let store: ESPStore
    let settings: Settings
    let chamsAllowed: Bool

    private var showsAnything: Bool {
        settings.box || settings.skeleton || settings.headDot || settings.snaplines || settings.name
            || settings.distance || settings.health || settings.offscreenArrows || showsChams
    }

    private var showsChams: Bool { settings.chams && chamsAllowed }

    var body: some View {
        GeometryReader { geo in
            if showsAnything {
                TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
                    let layout = currentLayout(size: geo.size)
                    ZStack {
                        if showsChams {
                            ChamsView(mask: store.chamsMask, mapper: layout?.mapper,
                                      accent: Palette.accent(settings.accent), time: timeline.date)
                        }
                        ESPCanvas(layouts: layout?.players ?? [],
                                  options: .init(box: settings.box, boxStyle: settings.boxStyle, skeleton: settings.skeleton,
                                                 headDot: settings.headDot, snaplines: settings.snaplines))
                        PlayerGlassViews(layouts: layout?.players ?? [],
                                         options: .init(name: settings.name, distance: settings.distance, health: settings.health))
                        if settings.offscreenArrows {
                            OffscreenArrowsView(markers: layout?.offscreen ?? [])
                        }
                    }
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
