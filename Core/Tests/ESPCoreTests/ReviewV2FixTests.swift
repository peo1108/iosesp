import Foundation
import Testing
@testable import ESPCore

// MARK: Confirmed tracks match before tentative duplicates

private func det(_ x: Float, world: Vec3? = nil) -> Detection {
    Detection(box: Rect(x: x, y: 0.3, width: 0.1, height: 0.4), kind: .person, confidence: 0.9, joints: [:],
              worldPosition: world, distance: 3, distanceIsEstimated: false, heightMeters: 1.7, yaw: 0, occlusion: .visible)
}

@Test func confirmedTrackWinsOverTentativeDuplicate() {
    let t = Tracker()
    for i in 0..<3 { t.update([det(0.2)], at: Double(i) / 30) }
    t.update([det(0.2), det(0.205)], at: 3.0 / 30)          // a duplicate box spawns a tentative twin
    var r: [Track] = []
    for i in 4..<40 { r = t.update([det(0.205)], at: Double(i) / 30) }
    #expect(r.map(\.id) == [1] && r[0].state == .confirmed)
}

// MARK: Lost tracks revive where they would be by now

@Test func revivalUsesPredictedPosition() {
    let t = Tracker()
    for i in 0..<30 {   // walking +x at 1.2 m/s for a second
        let time = Double(i) / 30
        t.update([det(0.1 + Float(i) * 0.005, world: Vec3(1.2 * Float(time), 0, -4))], at: time)
    }
    for i in 30..<66 { t.update([], at: Double(i) / 30) }   // hidden for 1.2 s
    let back = 66.0 / 30
    let r = t.update([det(0.7, world: Vec3(1.2 * Float(back), 0, -4))], at: back)
    #expect(r.contains { $0.id == 1 && $0.state == .confirmed })
}
