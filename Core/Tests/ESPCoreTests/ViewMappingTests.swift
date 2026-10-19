import Testing
@testable import ESPCore

// iPhone 16 Pro Max landscape: 956 × 440 pt; ARKit captured image 1920 × 1440 (4:3), aspect-filled.
private let image = Vec2(1920, 1440)
private let view = Vec2(956, 440)

private func close(_ a: Vec2, _ b: Vec2, _ eps: Float = 0.01) -> Bool {
    abs(a.x - b.x) < eps && abs(a.y - b.y) < eps
}

@Test func centerMapsToCenter() {
    let m = ViewMapping(imageSize: image, viewSize: view, upsideDown: false)
    #expect(close(m.view(fromNormalized: Vec2(0.5, 0.5)), Vec2(478, 220)))
}

@Test func aspectFillCropsTopAndBottom() {
    // Width fits (scale 956/1920); the scaled image is 717 pt tall, so 138.5 pt is cut off top and bottom.
    let m = ViewMapping(imageSize: image, viewSize: view, upsideDown: false)
    #expect(close(m.view(fromNormalized: Vec2(0, 0)), Vec2(0, -138.5)))
    #expect(close(m.view(fromNormalized: Vec2(1, 1)), Vec2(956, 578.5)))
    // An image x/y axis stays an x/y axis: no rotation in landscape.
    let a = m.view(fromNormalized: Vec2(0.2, 0.5)), b = m.view(fromNormalized: Vec2(0.8, 0.5))
    #expect(abs(a.y - b.y) < 1e-4 && b.x > a.x)
}

@Test func upsideDownTurnsHalfway() {
    let m = ViewMapping(imageSize: image, viewSize: view, upsideDown: true)
    #expect(close(m.view(fromNormalized: Vec2(0, 0)), Vec2(956, 578.5)))
    #expect(close(m.view(fromNormalized: Vec2(0.5, 0.5)), Vec2(478, 220)))
}

@Test func pixelsAndNormalizedAgree() {
    let m = ViewMapping(imageSize: image, viewSize: view, upsideDown: false)
    #expect(close(m.view(fromPixel: Vec2(960, 720)), m.view(fromNormalized: Vec2(0.5, 0.5))))
}

@Test func affineMatchesPointMapping() {
    for flipped in [false, true] {
        let m = ViewMapping(imageSize: image, viewSize: view, upsideDown: flipped)
        let t = m.affine
        let p = Vec2(0.3, 0.7)
        let viaAffine = Vec2(t.a * p.x + t.tx, t.d * p.y + t.ty)
        #expect(close(viaAffine, m.view(fromNormalized: p)))
    }
}

@Test func tallViewCropsSides() {
    let m = ViewMapping(imageSize: Vec2(1920, 1440), viewSize: Vec2(400, 400), upsideDown: false)
    #expect(close(m.view(fromNormalized: Vec2(0.5, 0)), Vec2(200, 0)))
    #expect(close(m.view(fromNormalized: Vec2(0, 0.5)), Vec2(-66.667, 200), 0.01))
}
