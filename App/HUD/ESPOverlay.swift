import ESPCore
import SwiftUI

/// Everything drawn over the camera — ESP on people and animals plus the HUD — re-laid-out every display
/// frame from the latest camera pose. Ignores the safe area; HUD pieces pad themselves by the window insets.
struct ESPOverlay: View {
    let capture: CaptureEngine
    let store: ESPStore
    let settings: Settings
    let budget: PerceptionBudget

    private var showsChams: Bool { settings.chams && budget.chamsAllowed }

    private var showsAnything: Bool {
        let s = settings
        return s.box || s.skeleton || s.headDot || s.snaplines || s.label || s.distance || s.offscreenArrows
            || showsChams || s.stats || s.radar || s.fakeIsland || s.watermark
    }

    var body: some View {
        GeometryReader { geo in
            if showsAnything {
                TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
                    content(layout: currentLayout(size: geo.size), time: timeline.date)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func content(layout: ESPFrameLayout?, time: Date) -> some View {
        let accent = Palette.accent(settings.accent)
        let insets = InterfaceOrientation.safeAreaInsets
        let islandLeading = InterfaceOrientation.islandOnLeading
        let players = visible(layout?.players ?? [])

        ZStack {
            if showsChams {
                ChamsView(mask: store.chamsMask, mapper: layout?.mapper, accent: accent, time: time)
            }
            ESPCanvas(layouts: players,
                      options: .init(box: settings.box, boxStyle: settings.boxStyle.effective(trackingNormal: store.trackingNormal),
                                     skeleton: settings.skeleton, headDot: settings.headDot, snaplines: settings.snaplines))
            PlayerGlassViews(layouts: players, options: .init(label: settings.label, distance: settings.distance))
            if settings.offscreenArrows {
                OffscreenArrowsView(markers: (layout?.offscreen ?? []).filter { marker in
                    settings.showAnimals || store.tracks.first { $0.id == marker.id }?.kind.isPerson ?? true
                })
            }
        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 10) {
                if settings.stats {
                    StatsView(fps: store.fps, players: store.confirmedPeople.count, trackingNormal: store.trackingNormal,
                              heatWarning: budget.showHeatWarning, accent: accent)
                }
                if settings.radar, store.trackingNormal, let mapper = layout?.mapper {
                    let tracked = store.tracks.filter { settings.showAnimals || $0.kind.isPerson }
                    RadarView(blips: Radar.blips(tracked.compactMap { t in t.worldPosition.map { (id: t.id, world: $0) } },
                                                 cameraToWorld: mapper.cameraToWorld, range: Float(settings.radarRange)),
                              animalIDs: Set(tracked.filter { !$0.kind.isPerson }.map(\.id)), accent: accent, time: time)
                }
            }
            .padding(.leading, insets.left + 4)
            .padding(.top, max(insets.top, 12))
        }
        .overlay(alignment: islandLeading ? .leading : .trailing) {
            if settings.fakeIsland {
                FakeIslandView(text: nearestPersonText(players), accent: accent)
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
    }

    /// People always; animals only when enabled.
    private func visible(_ players: [PlayerLayout]) -> [PlayerLayout] {
        players.filter { settings.showAnimals || $0.track.kind.isPerson }
    }

    private func nearestPersonText(_ players: [PlayerLayout]) -> String? {
        guard let nearest = players.filter({ $0.track.kind.isPerson }).min(by: { $0.track.distance < $1.track.distance }) else {
            return nil
        }
        return nearest.label + String(format: " · %.1f m", nearest.track.distance)
    }

    private func currentLayout(size: CGSize) -> ESPFrameLayout? {
        guard let frame = capture.session.currentFrame else { return nil }
        return ESPLayout.compute(store: store, frame: frame, viewSize: size)
    }
}
