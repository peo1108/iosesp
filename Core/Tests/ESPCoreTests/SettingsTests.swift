import Foundation
import Testing
@testable import ESPCore

@Test func defaultIsBareCamera() {
    let s = Settings.default
    for flag in Settings.visibilityToggles { #expect(!s[keyPath: flag]) }
    #expect(s.lens == .wide && s.quality == .uhd30 && s.boxStyle == .corner && s.haptics)
    #expect(s.watermarkText == "ESP v3 · Undetected")
}

@Test func roundTripsThroughJSON() throws {
    var s = Settings.default
    s.box = true; s.boxStyle = .glass; s.lens = .ultraWide; s.quality = .hd60; s.watermarkText = "xin chào"
    let data = try JSONEncoder().encode(s)
    #expect(Settings.decodeOrDefault(data) == s)
}

@Test func decodesMissingKeysWithDefaults() {
    let s = Settings.decodeOrDefault(#"{"stats":true}"#.data(using: .utf8))
    #expect(s.stats && s.watermarkText == "ESP v3 · Undetected" && s.haptics && s.lens == .wide)
}

@Test func unknownEnumValueFallsBackPerField() {
    let s = Settings.decodeOrDefault(#"{"boxStyle":"hexagon","lens":"fisheye","stats":true}"#.data(using: .utf8))
    #expect(s.boxStyle == .corner && s.lens == .wide && s.stats)
}

@Test func garbageFallsBackToDefault() {
    #expect(Settings.decodeOrDefault(Data("nope".utf8)) == .default)
    #expect(Settings.decodeOrDefault(nil) == .default)
}

@Test func v2SaveKeepsSurvivingFlags() {
    // v2 file: VIP preset with removed features (skeleton, radar, 3D box…). Kept features carry over, the rest is ignored.
    let json = #"{"preset":"vip","box":true,"boxStyle":"threeD","skeleton":true,"radar":true,"detailCard":true,"#
        + #""offscreenArrows":true,"snaplines":true,"showAnimals":true,"stats":true,"playerList":true,"eventLog":true,"#
        + #""watermark":true,"watermarkText":"hi","recordIndicator":true,"microphone":true,"maxDistance":12}"#
    let s = Settings.decodeOrDefault(json.data(using: .utf8))
    for flag in Settings.visibilityToggles where flag != \Settings.recordButton { #expect(s[keyPath: flag]) }
    #expect(s.boxStyle == .corner && s.watermarkText == "hi" && s.microphone && !s.recordButton)
}

@Test func v1SettingsFileLoads() {
    let s = Settings.decodeOrDefault(#"{"preset":"rage","aimbot":true,"name":true,"fovRadius":200,"box":true}"#.data(using: .utf8))
    #expect(s.box && !s.detailCard)
}
