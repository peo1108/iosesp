import ESPCore
import SwiftUI

/// Everything drawn over the camera — ESP on people and animals plus the HUD — re-laid-out every display
/// frame from the latest camera pose. Ignores the safe area; HUD pieces pad themselves by the window insets.
struct ESPOverlay: View {
    let capture: CaptureEngine
    let store: ESPStore
    let settings: Settings
    let budget: PerceptionBudget

    private var showsAnything: Bool {
        let s = settings
        return s.box || s.detailCard || s.snaplines || s.offscreenArrows || s.stats || s.playerList || s.eventLog || s.watermark
    }

    var body: some View {
        GeometryReader { geo in
            if showsAnything {
                TimelineView(.animation(minimumInterval: 1.0 / budget.hudHz)) { _ in
                    content(layout: currentLayout(size: geo.size), size: geo.size)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func content(layout: ESPFrameLayout?, size: CGSize) -> some View {
        let accent = Palette.accent(settings.accent)
        let insets = InterfaceOrientation.safeAreaInsets
        let players = visible(layout?.players ?? [])
        let now = layout?.timestamp ?? store.timestamp

        ZStack {
            ESPCanvas(layouts: players,
                      options: .init(box: settings.box, boxStyle: settings.boxStyle, snaplines: settings.snaplines))
            if settings.detailCard {
                DetailCardsView(layouts: players, now: now, viewWidth: size.width)
            }
            if settings.offscreenArrows {
                // Markers only exist for tracks outside the view; apply the same filter as on screen.
                OffscreenArrowsView(markers: (layout?.offscreen ?? []).filter { marker in
                    settings.showAnimals || store.tracks.first { $0.id == marker.id }?.kind.isPerson == true
                })
            }
        }
        .overlay(alignment: .topLeading) {
            if settings.stats {
                StatsView(fps: store.fps, summary: store.countSummary(showAnimals: settings.showAnimals),
                          isEmpty: players.isEmpty, trackingNormal: store.trackingNormal,
                          heatWarning: budget.showHeatWarning, ultraWide: capture.lens == .ultraWide, accent: accent)
                    .padding(.leading, insets.left + 4)
                    .padding(.top, max(insets.top, 12))
            }
        }
        .overlay(alignment: .topTrailing) {
            if settings.playerList {
                PlayerListView(rows: players.sorted { $0.distance < $1.distance }.prefix(8).map { p in
                    PlayerListView.Row(id: p.id, label: p.label, detail: kindEmoji(p.track.kind),
                                       distance: Readout.distance(p.distance, estimated: p.track.distanceIsEstimated),
                                       color: p.color)
                })
                .padding(.trailing, insets.right + 4)
                .padding(.top, max(insets.top, 12))
            }
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 6) {
                if settings.eventLog {
                    EventLogView(events: store.events, now: now)
                }
                if settings.watermark {
                    WatermarkView(text: settings.watermarkText)
                }
            }
            .padding(.leading, insets.left + 4)
            .padding(.bottom, max(insets.bottom, 12))
        }
    }

    /// People, plus animals when enabled.
    private func visible(_ players: [PlayerLayout]) -> [PlayerLayout] {
        settings.showAnimals ? players : players.filter { $0.track.kind.isPerson }
    }

    private func kindEmoji(_ kind: EntityKind) -> String {
        if case let .animal(animal) = kind { return animal.emoji }
        return ""
    }

    private func currentLayout(size: CGSize) -> ESPFrameLayout? {
        guard let current = capture.currentPose() else { return nil }
        return ESPLayout.compute(store: store, pose: current.pose, timestamp: current.timestamp, viewSize: size)
    }
}
