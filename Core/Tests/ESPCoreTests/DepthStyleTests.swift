import Testing
@testable import ESPCore

@Test func nearnessRunsFromOneToZero() {
    #expect(DepthStyle.nearness(1) == 1 && DepthStyle.nearness(1.5) == 1)
    #expect(DepthStyle.nearness(18) == 0 && DepthStyle.nearness(40) == 0)
    #expect(DepthStyle.nearness(.nan) == 1)
}

@Test func nearnessIsLogarithmic() {
    // Each doubling of distance takes off the same amount.
    let a = DepthStyle.nearness(2) - DepthStyle.nearness(4), b = DepthStyle.nearness(6) - DepthStyle.nearness(12)
    #expect(abs(a - b) < 1e-5)
}

@Test func farThingsAreThinnerFainterSmaller() {
    #expect(DepthStyle.lineWidth(1) > DepthStyle.lineWidth(10) && DepthStyle.lineWidth(30) == 0.8 && DepthStyle.lineWidth(1) <= 1.6)
    #expect(DepthStyle.opacity(30) == 0.45 && DepthStyle.opacity(1) == 1)
    #expect(DepthStyle.cardScale(2) > DepthStyle.cardScale(12))
}
