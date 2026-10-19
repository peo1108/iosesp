import Testing
@testable import ESPCore

@Test func trailSpacingAndExpiry() {
    var trail = Trail()
    trail.add(Vec3(0, 0, 0), at: 0)
    trail.add(Vec3(0.05, 0, 0), at: 0.1)   // too close to the last point: skipped
    trail.add(Vec3(0.2, 0, 0), at: 0.2)
    trail.add(Vec3(0.4, 0, 0), at: 4.0)
    let pts = trail.points(at: 4.0)
    #expect(pts.count == 3)
    #expect(abs(pts[0].age - 0.8) < 1e-6 && pts.last!.age == 0)
    #expect(trail.points(at: 5.5).count == 1)  // the first two are older than 5 s
}

@Test func countSummaryFormats() {
    #expect(CountSummary.text(people: 3, animals: [.cat: 1, .dog: 1]) == "3 người · 🐕 1 · 🐈 1")
    #expect(CountSummary.text(people: 1, animals: [:]) == "1 người")
    #expect(CountSummary.text(people: 0, animals: [.bird: 2]) == "🐦 2")
}

@Test func countSummaryEmpty() {
    #expect(CountSummary.text(people: 0, animals: [:]) == "Không có ai")
}
