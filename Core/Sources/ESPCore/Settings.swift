import Foundation

public enum AccentName: String, Codable, CaseIterable, Sendable {
    case blue, purple, pink, red, orange, green, mint, cyan
}

/// Which back camera feeds the ESP.
public enum CameraLens: String, Codable, CaseIterable, Sendable {
    /// 1× wide camera through ARKit: world tracking and LiDAR distances.
    case wide
    /// 0.5× ultra-wide through AVFoundation: wider view, distances estimated from box size, phone turns from
    /// the gyroscope (ARKit can't use this camera).
    case ultraWide
}

/// Everything the menu can change. Every flag defaults to off, so a fresh install is a bare camera.
public struct Settings: Codable, Equatable, Sendable {
    public var lens: CameraLens = .wide

    // ESP
    public var box = false
    public var boxStyle: BoxStyle = .corner
    /// Card beside each person/animal: name, distance, speed, time in frame.
    public var detailCard = false
    public var offscreenArrows = false
    /// Thin "lite" line from the bottom of the screen to each box.
    public var snaplines = false
    public var showAnimals = false

    // HUD
    public var stats = false
    public var playerList = false
    public var eventLog = false
    public var watermark = false
    public var watermarkText = "ESP v3 · Undetected"

    // Recording
    public var recordButton = false
    public var microphone = false
    public var haptics = true

    public var accent: AccentName = .blue
    public var hasSeenHint = false

    public init() {}

    public static let `default` = Settings()

    /// Everything that draws something over the camera.
    public static var visibilityToggles: [WritableKeyPath<Settings, Bool>] {
        [\.box, \.detailCard, \.offscreenArrows, \.snaplines, \.showAnimals,
         \.stats, \.playerList, \.eventLog, \.watermark, \.recordButton]
    }

    public static func decodeOrDefault(_ data: Data?) -> Settings {
        guard let data, let settings = try? JSONDecoder().decode(Settings.self, from: data) else { return .default }
        return settings
    }

    /// Tolerant decoding: a missing or unreadable key keeps its default, and keys of removed v1/v2 features
    /// (skeleton, radar, presets…) are ignored, so old or damaged saves still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        let d = Settings()
        lens = read(.lens, d.lens)
        box = read(.box, d.box)
        boxStyle = read(.boxStyle, d.boxStyle)
        detailCard = read(.detailCard, d.detailCard)
        offscreenArrows = read(.offscreenArrows, d.offscreenArrows)
        snaplines = read(.snaplines, d.snaplines)
        showAnimals = read(.showAnimals, d.showAnimals)
        stats = read(.stats, d.stats)
        playerList = read(.playerList, d.playerList)
        eventLog = read(.eventLog, d.eventLog)
        watermark = read(.watermark, d.watermark)
        watermarkText = read(.watermarkText, d.watermarkText)
        recordButton = read(.recordButton, d.recordButton)
        microphone = read(.microphone, d.microphone)
        haptics = read(.haptics, d.haptics)
        accent = read(.accent, d.accent)
        hasSeenHint = read(.hasSeenHint, d.hasSeenHint)
    }
}
