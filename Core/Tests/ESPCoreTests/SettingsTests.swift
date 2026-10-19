import Foundation
import Testing
@testable import ESPCore

@Test func defaultIsOff() {
    #expect(Settings.default.preset == .off && !Settings.default.box && Settings.default.haptics)
    #expect(Settings.default.watermarkText == "ESP v2.6 · Undetected")
}

@Test func legitPreset() {
    var s = Settings.default
    s.apply(.legit)
    #expect(s.box && s.distance && !s.name && !s.skeleton && s.boxStyle == .corner && s.preset == .legit)
}

@Test func ragePresetEnablesEverything() {
    var s = Settings.default
    s.apply(.rage)
    #expect(s.aimbot && s.chams && s.radar && s.shooting && s.recordButton && s.recordIndicator && s.boxStyle == .threeD)
    #expect(s.box && s.skeleton && s.snaplines && s.name && s.health && s.distance && s.headDot && s.offscreenArrows)
    #expect(s.fovCircle && s.crosshair && s.killFeed && s.naturalHealth && s.stats && s.fakeIsland && s.watermark)
}

@Test func streamerHidesHud() {
    var s = Settings.default
    s.apply(.streamer)
    #expect(s.box && s.name && s.health && s.distance && s.skeleton && s.watermark)
    #expect(!s.stats && !s.radar && !s.recordButton && !s.recordIndicator && !s.aimbot && !s.chams)
}

@Test func offPresetClearsEverything() {
    var s = Settings.default
    s.apply(.rage)
    s.apply(.off)
    #expect(!s.box && !s.aimbot && !s.radar && !s.watermark && !s.recordButton && s.preset == .off)
}

@Test func presetKeepsPersonalization() {
    var s = Settings.default
    s.watermarkText = "hi"; s.fovRadius = 300; s.accent = .pink; s.microphone = true; s.hasSeenHint = true
    s.apply(.rage)
    s.apply(.off)
    #expect(s.watermarkText == "hi" && s.fovRadius == 300 && s.accent == .pink && s.microphone && s.hasSeenHint && !s.box)
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
    s.apply(.rage)
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

@Test func thermalBudgets() {
    #expect(ThermalPolicy.budget(.nominal, isRecording: false) == PerceptionBudget(hz: 30, chamsAllowed: true, showHeatWarning: false))
    #expect(ThermalPolicy.budget(.fair, isRecording: false) == PerceptionBudget(hz: 20, chamsAllowed: true, showHeatWarning: false))
    #expect(ThermalPolicy.budget(.serious, isRecording: false) == PerceptionBudget(hz: 10, chamsAllowed: false, showHeatWarning: false))
    #expect(ThermalPolicy.budget(.nominal, isRecording: true).hz == 20)
    #expect(ThermalPolicy.budget(.critical, isRecording: true) == PerceptionBudget(hz: 5, chamsAllowed: false, showHeatWarning: true))
}
