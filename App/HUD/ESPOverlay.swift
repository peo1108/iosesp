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
        return s.box || s.skeleton || s.headDot || s.snaplines || s.label || s.activity || s.detailCard || s.distance
            || s.trails || s.offscreenArrows || showsChams || s.showObjects || s.stats || s.playerList || s.eventLog
            || s.radar || s.fakeIsland || s.watermark
    }

    var body: some View {
        GeometryReader { geo in
            if showsAnything {
                TimelineView(.animation(minimumInterval: 1.0 / budget.hudHz)) { timeline in
                    content(layout: currentLayout(size: geo.size), size: geo.size, time: timeline.date)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func content(layout: ESPFrameLayout?, size: CGSize, time: Date) -> some View {
        let accent = Palette.accent(settings.accent)
        let insets = InterfaceOrientation.safeAreaInsets
        let islandLeading = InterfaceOrientation.islandOnLeading
        let players = visible(layout?.players ?? [])

        ZStack {
            if showsChams {
                ChamsView(mask: store.chamsMask, mapper: layout?.mapper, accent: accent, time: time)
            }
            if settings.trails, let mapper = layout?.mapper {
                TrailsView(trails: players.compactMap { p in
                    store.trails[p.id].map { (color: p.color, points: $0.points(at: layout?.timestamp ?? 0)) }
                }, mapper: mapper)
            }
            if settings.showObjects, let mapper = layout?.mapper {
                ObjectBoxesView(objects: store.objects, mapper: mapper)
            }
            ESPCanvas(layouts: players,
                      options: .init(box: settings.box, boxStyle: settings.boxStyle.effective(trackingNormal: store.trackingNormal),
                                     skeleton: settings.skeleton, headDot: settings.headDot, snaplines: settings.snaplines))
            PlayerGlassViews(layouts: players,
                             options: .init(label: settings.label, activity: settings.activity, distance: settings.distance,
                                            detailCard: settings.detailCard),
                             now: layout?.timestamp ?? 0, viewWidth: size.width)
            if settings.offscreenArrows {
                // Markers only exist for tracks outside the view; apply the same filters as on screen.
                OffscreenArrowsView(markers: (layout?.offscreen ?? []).filter { marker in
                    guard let track = store.tracks.first(where: { $0.id == marker.id }) else { return false }
                    return (settings.showAnimals || track.kind.isPerson) && marker.distance <= Float(settings.maxDistance)
                })
            }
        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 10) {
                if settings.stats {
                    StatsView(fps: store.fps,
                              summary: store.countSummary(showAnimals: settings.showAnimals, maxDistance: Float(settings.maxDistance)),
                              isEmpty: players.isEmpty,
                              trackingNormal: store.trackingNormal, heatWarning: budget.showHeatWarning, accent: accent)
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
        .overlay(alignment: .topTrailing) {
            if settings.playerList {
                PlayerListView(rows: players.sorted { $0.distance < $1.distance }.prefix(6).map { p in
                    PlayerListView.Row(id: p.id, label: p.label,
                                       detail: p.activity.map { "\($0.mainEmoji) \($0.mainText)" } ?? kindEmoji(p.track.kind),
                                       distance: p.distance, color: p.color)
                })
                .padding(.trailing, insets.right + 4)
                .padding(.top, max(insets.top, 12))
            }
        }
        .overlay(alignment: islandLeading ? .leading : .trailing) {
            if settings.fakeIsland {
                FakeIslandView(text: nearestPersonText(players), accent: accent)
                    .padding(islandLeading ? .leading : .trailing, (islandLeading ? insets.left : insets.right) + 4)
            }
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 6) {
                if settings.eventLog {
                    EventLogView(events: store.events, now: layout?.timestamp ?? store.timestamp)
                }
                if settings.watermark {
                    WatermarkView(text: settings.watermarkText)
                }
            }
            .padding(.leading, insets.left + 4)
            .padding(.bottom, max(insets.bottom, 12))
        }
    }

    /// People within range, nearest first and at most `maxPeople`; animals only when enabled.
    private func visible(_ players: [PlayerLayout]) -> [PlayerLayout] {
        let inRange = players.filter { $0.distance <= Float(settings.maxDistance) }
        let people = inRange.filter { $0.track.kind.isPerson }
            .sorted { $0.distance < $1.distance }
            .prefix(Int(settings.maxPeople))
        let animals = settings.showAnimals ? inRange.filter { !$0.track.kind.isPerson } : []
        return Array(people) + animals
    }

    private func kindEmoji(_ kind: EntityKind) -> String {
        if case let .animal(animal) = kind { return animal.emoji }
        return ""
    }

    private func nearestPersonText(_ players: [PlayerLayout]) -> String? {
        guard let nearest = players.filter({ $0.track.kind.isPerson }).min(by: { $0.distance < $1.distance }) else {
            return nil
        }
        var text = nearest.label + String(format: " · %.1f m", nearest.distance)
        if let action = nearest.activity?.frame.objectAction, action != .none { text += " · " + action.emoji }
        return text
    }

    private func currentLayout(size: CGSize) -> ESPFrameLayout? {
        guard let frame = capture.session.currentFrame else { return nil }
        return ESPLayout.compute(store: store, frame: frame, viewSize: size)
    }
}
