import Testing
@testable import ESPCore

private func track(_ id: Int, kind: EntityKind = .person, velocity: Vec3 = .zero, at time: Double) -> Track {
    Track(id: id, state: .confirmed, box: Rect(x: 0.4, y: 0.2, width: 0.2, height: 0.6), kind: kind, confidence: 0.9,
          joints: [:], worldPosition: Vec3(0, 0, -3), velocity: velocity, distance: 3, distanceIsEstimated: false,
          heightMeters: 1.7, yaw: 0, occlusion: .visible, hits: 5, lastSeen: time)
}

private func label(_ t: Track) -> String { t.kind.name }

@Test func entryAndLeave() {
    let log = PresenceLog()
    log.update(tracks: [track(1, at: 0)], label: label, at: 0)
    #expect(log.events.map(\.text) == ["Người vừa vào khung hình"])
    log.update(tracks: [], label: label, at: 0.5)
    #expect(log.events.count == 1)
    log.update(tracks: [], label: label, at: 1.2)
    #expect(log.events.last?.text == "Người rời khung hình")
}

@Test func animalAppears() {
    let log = PresenceLog()
    log.update(tracks: [track(2, kind: .animal(.dog), at: 0)], label: label, at: 0)
    #expect(log.events.map(\.text) == ["🐕 Chó xuất hiện"])
}

@Test func riderReplacesFreshEntryLineOnce() {
    let log = PresenceLog()
    for i in 0..<30 { log.update(tracks: [track(1, velocity: Vec3(8, 0, 0), at: Double(i) / 60)], label: label, at: Double(i) / 60) }
    #expect(log.events.map(\.text) == ["🛵 Người phóng qua · 29 km/h"])
}

@Test func oneFastSpikeIsNotARider() {
    let log = PresenceLog()
    for i in 0..<30 {
        let v = i == 10 ? Vec3(9, 0, 0) : Vec3(0.2, 0, 0)
        log.update(tracks: [track(1, velocity: v, at: Double(i) / 60)], label: label, at: Double(i) / 60)
    }
    #expect(!log.events.contains { $0.text.contains("phóng qua") })
}

@Test func eventsExpireAndCap() {
    let log = PresenceLog()
    log.update(tracks: (1...7).map { track($0, at: 0) }, label: label, at: 0)
    #expect(log.events.count == PresenceLog.eventsShown)
    log.update(tracks: (1...7).map { track($0, at: 9) }, label: label, at: 9)
    #expect(log.events.isEmpty)
}
