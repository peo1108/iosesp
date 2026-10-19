import ESPCore
import SwiftUI

/// Everything drawn over the camera — ESP on people plus the HUD — re-laid-out every display frame
/// from the latest camera pose. Ignores the safe area; HUD pieces pad themselves by the window insets.
struct ESPOverlay: View {
    let capture: CaptureEngine
    let store: ESPStore
    let settings: Settings
    let budget: PerceptionBudget

    private var showsChams: Bool { settings.chams && budget.chamsAllowed }

    private var showsAnything: Bool {
        let s = settings
        return s.box || s.skeleton || s.headDot || s.snaplines || s.name || s.distance || s.health
            || s.offscreenArrows || showsChams || s.aimbot || s.fovCircle || s.crosshair
            || s.stats || s.radar || s.fakeIsland || s.watermark
    }

    var body: some View {
        GeometryReader { geo in
            if showsAnything {
                TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
                    content(frame: frameState(size: geo.size), size: geo.size, time: timeline.date)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func content(frame: FrameState, size: CGSize, time: Date) -> some View {
        let accent = Palette.accent(settings.accent)
        let insets = InterfaceOrientation.safeAreaInsets
        let islandLeading = InterfaceOrientation.islandOnLeading
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        ZStack {
            if showsChams {
                ChamsView(mask: store.chamsMask, mapper: frame.layout?.mapper, accent: accent, time: time)
            }
            ESPCanvas(layouts: frame.players,
                      options: .init(box: settings.box, boxStyle: settings.boxStyle.effective(trackingNormal: store.trackingNormal),
                                     skeleton: settings.skeleton, headDot: settings.headDot, snaplines: settings.snaplines))
            PlayerGlassViews(layouts: frame.players,
                             options: .init(name: settings.name, distance: settings.distance, health: settings.health))
            if settings.offscreenArrows {
                OffscreenArrowsView(markers: frame.layout?.offscreen ?? [])
            }
            CrosshairView(showCrosshair: settings.crosshair, showFOV: settings.fovCircle,
                          fovRadius: CGFloat(settings.fovRadius), center: center, target: frame.aimTarget ?? center,
                          smooth: settings.smooth, accent: accent)
        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 10) {
                if settings.stats {
                    StatsView(fps: store.fps, players: store.confirmed.count, trackingNormal: store.trackingNormal,
                              heatWarning: budget.showHeatWarning, accent: accent)
                }
                if settings.radar, store.trackingNormal, let mapper = frame.layout?.mapper {
                    RadarView(blips: Radar.blips(store.tracks.compactMap { t in t.worldPosition.map { (id: t.id, world: $0) } },
                                                 cameraToWorld: mapper.cameraToWorld, range: Float(settings.radarRange)),
                              lockedID: frame.lockedID, accent: accent, time: time)
                }
            }
            .padding(.leading, insets.left + 4)
            .padding(.top, max(insets.top, 12))
        }
        .overlay(alignment: islandLeading ? .leading : .trailing) {
            if settings.fakeIsland {
                FakeIslandView(lockedDistance: frame.lockedDistance, accent: accent)
                    .padding(islandLeading ? .leading : .trailing, (islandLeading ? insets.left : insets.right) + 4)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if settings.watermark {
                WatermarkView(text: settings.watermarkText)
                    .padding(.leading, insets.left + 4)
                    .padding(.bottom, max(insets.bottom, 12))
            }
        }
        .sensoryFeedback(.impact(flexibility: .rigid), trigger: frame.lockedID) { old, new in
            old == nil && new != nil && settings.haptics
        }
    }

    // MARK: Per-frame state

    struct FrameState {
        var layout: ESPFrameLayout?
        var players: [PlayerLayout] = []
        var lockedID: Int?
        var aimTarget: CGPoint?
        var lockedDistance: Float?
    }

    private func frameState(size: CGSize) -> FrameState {
        guard let arFrame = capture.session.currentFrame else { return FrameState() }
        let layout = ESPLayout.compute(store: store, frame: arFrame, viewSize: size, lockedID: nil)
        var state = FrameState(layout: layout, players: layout.players)

        guard settings.aimbot else { return state }
        let center = Vec2(Float(size.width / 2), Float(size.height / 2))
        let candidates = state.players.map { p -> (id: Int, aimPoint: Vec2) in
            let a = p.aimPoint(settings.aimTarget)
            return (p.id, Vec2(Float(a.x), Float(a.y)))
        }
        guard let locked = Aimbot.selectTarget(candidates, center: center, fovRadius: Float(settings.fovRadius)),
              let index = state.players.firstIndex(where: { $0.id == locked }) else { return state }
        state.players[index].color = Palette.locked
        state.lockedID = locked
        state.aimTarget = state.players[index].aimPoint(settings.aimTarget)
        state.lockedDistance = state.players[index].track.distance
        return state
    }
}
