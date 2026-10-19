import Testing
@testable import ESPCore

@Test func sameAspectIsIdentity() {
    let fit = Letterbox(imageSize: Vec2(1920, 1440), inputSize: Vec2(640, 480))
    #expect(fit.isIdentity && fit.toImage(Vec2(0.3, 0.7)) == Vec2(0.3, 0.7))
}

@Test func wideImageGetsBarsTopAndBottom() {
    // 3840×2160 into 640×480: drawn 640×360, 60 px bars above and below.
    let fit = Letterbox(imageSize: Vec2(3840, 2160), inputSize: Vec2(640, 480))
    #expect(!fit.isIdentity)
    #expect(abs(fit.content.y - 0.125) < 1e-6 && abs(fit.content.height - 0.75) < 1e-6 && fit.content.width == 1)
    let top = fit.toImage(Vec2(0.5, 0.125)), bottom = fit.toImage(Vec2(0.5, 0.875))
    #expect(abs(top.y) < 1e-6 && abs(bottom.y - 1) < 1e-6)
    let r = fit.toImage(Rect(x: 0.2, y: 0.25, width: 0.1, height: 0.375))
    #expect(abs(r.y - 1.0 / 6) < 1e-5 && abs(r.height - 0.5) < 1e-5 && abs(r.x - 0.2) < 1e-6)
}

@Test func depthCropForWideVideo() {
    // 16:9 video inside a 4:3 depth map: the top of the video sits 12.5% down the depth map.
    let p = DepthCrop.depthPoint(Vec2(0.3, 0), imageAspect: 16.0 / 9, depthAspect: 4.0 / 3)
    #expect(abs(p.x - 0.3) < 1e-6 && abs(p.y - 0.125) < 1e-6)
    #expect(DepthCrop.depthPoint(Vec2(0.3, 0.6), imageAspect: 4.0 / 3, depthAspect: 4.0 / 3) == Vec2(0.3, 0.6))
}
