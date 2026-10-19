import Testing
@testable import ESPCore

@Test func kalmanTracksConstantVelocity() {
    var k = KalmanCV<Vec2>(position: Vec2(0, 0), processNoise: 2, measurementNoise: 1e-4)
    for i in 1...20 {
        k.predict(dt: 1.0 / 30)
        k.update(Vec2(Float(i) / 30, 0))
    }
    #expect(abs(k.velocity.x - 1) < 0.1 && abs(k.velocity.y) < 0.05)
}

@Test func kalmanPredictsMotion() {
    var k = KalmanCV<Vec2>(position: Vec2(0, 0), processNoise: 2, measurementNoise: 1e-4)
    for i in 1...30 {
        k.predict(dt: 1.0 / 30)
        k.update(Vec2(Float(i) / 30, 0))
    }
    let before = k.position.x
    k.predict(dt: 0.1)
    #expect(abs(k.position.x - (before + 0.1)) < 0.01)
}

@Test func kalmanSmoothsNoise() {
    var k = KalmanCV<Vec2>(position: Vec2(2, 0), processNoise: 0.5, measurementNoise: 0.0025)
    for i in 1...60 {
        k.predict(dt: 1.0 / 30)
        k.update(Vec2(i.isMultiple(of: 2) ? 2.05 : 1.95, 0))
    }
    #expect(abs(k.position.x - 2) < 0.02)
}

@Test func kalmanStartsStill() {
    let k = KalmanCV<Vec3>(position: Vec3(1, 2, 3), processNoise: 1, measurementNoise: 0.01)
    #expect(k.position == Vec3(1, 2, 3) && k.velocity == .zero)
}
