import Testing
@testable import ESPCore

@Test func vectorHelpers() {
    #expect(length(Vec3(3, 4, 0)) == 5)
    #expect(normalize(Vec3(0, 0, 2)) == Vec3(0, 0, 1))
    #expect(dot(Vec3(1, 2, 3), Vec3(4, 5, 6)) == 32)
    #expect(Vec2(3, 4).squareLength == 25)
}
