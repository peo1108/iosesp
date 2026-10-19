import Foundation

public enum AimTarget: String, Codable, CaseIterable, Sendable {
    case head, chest
}

public enum AccentName: String, Codable, CaseIterable, Sendable {
    case blue, purple, pink, red, orange, green, mint, cyan
}

public enum Preset: String, Codable, CaseIterable, Sendable {
    case legit, rage, streamer, off, custom
}

/// Everything the menu can change. Every flag defaults to off, so a fresh install is a bare camera.
public struct Settings: Codable, Equatable, Sendable {
    public var preset: Preset = .off

    // ESP
    public var box = false
    public var boxStyle: BoxStyle = .corner
    public var skeleton = false
    public var chams = false
    public var snaplines = false
    public var name = false
    public var health = false
    public var distance = false
    public var headDot = false
    public var offscreenArrows = false

    // Aim
    public var aimbot = false
    public var fovCircle = false
    /// 50…400 pt
    public var fovRadius: Double = 150
    /// 0…1
    public var smooth: Double = 0.5
    public var aimTarget: AimTarget = .head
    public var crosshair = false

    // Game
    public var shooting = false
    public var killFeed = false
    public var naturalHealth = false

    // HUD
    public var stats = false
    public var radar = false
    /// 5…30 m
    public var radarRange: Double = 15
    public var fakeIsland = false
    public var watermark = false
    public var watermarkText = "ESP v2.6 · Undetected"

    // Recording
    public var recordButton = false
    public var recordIndicator = false
    public var microphone = false
    public var haptics = true

    public var accent: AccentName = .blue
    public var hasSeenHint = false

    public init() {}

    public static let `default` = Settings()

    /// Flags a preset turns on or off. Personal choices (texts, ranges, accent, mic, haptics) are left alone.
    static var visibilityToggles: [WritableKeyPath<Settings, Bool>] {
        [\.box, \.skeleton, \.chams, \.snaplines, \.name, \.health, \.distance, \.headDot, \.offscreenArrows,
         \.aimbot, \.fovCircle, \.crosshair,
         \.shooting, \.killFeed, \.naturalHealth,
         \.stats, \.radar, \.fakeIsland, \.watermark,
         \.recordButton, \.recordIndicator]
    }

    public mutating func apply(_ preset: Preset) {
        self.preset = preset
        guard preset != .custom else { return }

        let on: [WritableKeyPath<Settings, Bool>]
        switch preset {
        case .legit:
            on = [\.box, \.distance]
            boxStyle = .corner
        case .rage:
            on = Self.visibilityToggles
            boxStyle = .threeD
        case .streamer:
            on = [\.box, \.name, \.health, \.distance, \.skeleton, \.watermark]
            boxStyle = .corner
        case .off, .custom:
            on = []
            boxStyle = .corner
        }
        for flag in Self.visibilityToggles { self[keyPath: flag] = false }
        for flag in on { self[keyPath: flag] = true }
    }

    /// Menu edits go through here so the preset label turns into "Custom".
    public mutating func set<V>(_ keyPath: WritableKeyPath<Settings, V>, _ value: V) {
        self[keyPath: keyPath] = value
        let key = keyPath as AnyKeyPath
        if key != \Settings.preset as AnyKeyPath && key != \Settings.hasSeenHint as AnyKeyPath {
            preset = .custom
        }
    }

    public static func decodeOrDefault(_ data: Data?) -> Settings {
        guard let data, let settings = try? JSONDecoder().decode(Settings.self, from: data) else { return .default }
        return settings
    }

    /// Tolerant decoding: a missing or unreadable key keeps its default, so old or damaged saves still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        let d = Settings()
        preset = read(.preset, d.preset)
        box = read(.box, d.box)
        boxStyle = read(.boxStyle, d.boxStyle)
        skeleton = read(.skeleton, d.skeleton)
        chams = read(.chams, d.chams)
        snaplines = read(.snaplines, d.snaplines)
        name = read(.name, d.name)
        health = read(.health, d.health)
        distance = read(.distance, d.distance)
        headDot = read(.headDot, d.headDot)
        offscreenArrows = read(.offscreenArrows, d.offscreenArrows)
        aimbot = read(.aimbot, d.aimbot)
        fovCircle = read(.fovCircle, d.fovCircle)
        fovRadius = read(.fovRadius, d.fovRadius)
        smooth = read(.smooth, d.smooth)
        aimTarget = read(.aimTarget, d.aimTarget)
        crosshair = read(.crosshair, d.crosshair)
        shooting = read(.shooting, d.shooting)
        killFeed = read(.killFeed, d.killFeed)
        naturalHealth = read(.naturalHealth, d.naturalHealth)
        stats = read(.stats, d.stats)
        radar = read(.radar, d.radar)
        radarRange = read(.radarRange, d.radarRange)
        fakeIsland = read(.fakeIsland, d.fakeIsland)
        watermark = read(.watermark, d.watermark)
        watermarkText = read(.watermarkText, d.watermarkText)
        recordButton = read(.recordButton, d.recordButton)
        recordIndicator = read(.recordIndicator, d.recordIndicator)
        microphone = read(.microphone, d.microphone)
        haptics = read(.haptics, d.haptics)
        accent = read(.accent, d.accent)
        hasSeenHint = read(.hasSeenHint, d.hasSeenHint)
    }
}
