import Foundation
import Testing
@testable import ESPCore

@Test func defaultIsOff() {
    #expect(Settings.default.preset == .off && !Settings.default.box && Settings.default.haptics)
    #expect(Settings.default.watermarkText == "ESP v2.6 · Undetected")
    #expect(Settings.default.maxDistance == 30 && Settings.default.maxPeople == 20)
}

@Test func legitPreset() {
    var s = Settings.default
    s.apply(.legit)
    #expect(s.box && s.label && s.distance && !s.skeleton && !s.activity && s.boxStyle == .corner && s.preset == .legit)
}

@Test func vipPresetEnablesEverything() {
    var s = Settings.default
    s.apply(.vip)
    #expect(s.boxStyle == .glass)
    for flag in Settings.visibilityToggles { #expect(s[keyPath: flag]) }
}

@Test func streamerPreset() {
    var s = Settings.default
    s.apply(.streamer)
    #expect(s.box && s.label && s.activity && s.skeleton && s.watermark && s.stats)
    #expect(!s.playerList && !s.radar && !s.recordButton && !s.recordIndicator && !s.chams && !s.detailCard)
}

@Test func offPresetClearsEverything() {
    var s = Settings.default
    s.apply(.vip)
    s.apply(.off)
    for flag in Settings.visibilityToggles { #expect(!s[keyPath: flag]) }
    #expect(s.preset == .off)
}

@Test func presetKeepsPersonalization() {
    var s = Settings.default
    s.watermarkText = "hi"; s.maxDistance = 12; s.accent = .pink; s.microphone = true; s.hasSeenHint = true; s.smoothMode = true
    s.apply(.vip)
    s.apply(.off)
    #expect(s.watermarkText == "hi" && s.maxDistance == 12 && s.accent == .pink && s.microphone && s.hasSeenHint && s.smoothMode)
}

@Test func editingMakesCustom() {
    var s = Settings.default
    s.apply(.legit)
    s.set(\.skeleton, true)
    #expect(s.preset == .custom && s.skeleton)
}

@Test func hintFlagDoesNotMakeCustom() {
    var s = Settings.default
    s.apply(.streamer)
    s.set(\.hasSeenHint, true)
    #expect(s.preset == .streamer)
}

@Test func roundTripsThroughJSON() throws {
    var s = Settings.default
    s.apply(.vip)
    s.watermarkText = "xin chào"
    let data = try JSONEncoder().encode(s)
    #expect(Settings.decodeOrDefault(data) == s)
}

@Test func decodesMissingKeysWithDefaults() {
    let s = Settings.decodeOrDefault(#"{"radar":true}"#.data(using: .utf8))
    #expect(s.radar && s.watermarkText == "ESP v2.6 · Undetected" && s.haptics && s.preset == .off)
}

@Test func unknownEnumValueFallsBackPerField() {
    let s = Settings.decodeOrDefault(#"{"boxStyle":"hexagon","radar":true}"#.data(using: .utf8))
    #expect(s.boxStyle == .corner && s.radar)
}

@Test func garbageFallsBackToDefault() {
    #expect(Settings.decodeOrDefault(Data("nope".utf8)) == .default)
    #expect(Settings.decodeOrDefault(nil) == .default)
}

@Test func numericSettingsClampedOnDecode() {
    let s = Settings.decodeOrDefault(#"{"radarRange":0,"maxPeople":99,"maxDistance":-1}"#.data(using: .utf8))
    #expect(s.radarRange == 5 && s.maxPeople == 20 && s.maxDistance == 5)
}

@Test func v1SettingsFileLoads() {
    let s = Settings.decodeOrDefault(#"{"preset":"rage","aimbot":true,"name":true,"fovRadius":200,"box":true}"#.data(using: .utf8))
    #expect(s.preset == .vip && s.label && s.box)
}

