import Foundation

public enum AccentName: String, Codable, CaseIterable, Sendable {
    case blue, purple, pink, red, orange, green, mint, cyan
}

public enum Preset: String, Codable, CaseIterable, Sendable {
    case legit, vip, streamer, off, custom
}

/// Everything the menu can change. Every flag defaults to off, so a fresh install is a bare camera.
public struct Settings: Codable, Equatable, Sendable {
    public var preset: Preset = .off

    // People
    public var box = false
    public var boxStyle: BoxStyle = .corner
    public var skeleton = false
    public var headDot = false
    /// "Người 01" tag.
    public var label = false
    /// What the person is doing, next to the label.
    public var activity = false
    public var detailCard = false
    public var distance = false
    public var trails = false
    public var chams = false
    public var snaplines = false
    public var offscreenArrows = false

    // Animals & objects
    public var showAnimals = false
    public var showObjects = false

    // HUD
    public var stats = false
    public var playerList = false
    public var eventLog = false
    public var radar = false
    /// 5…30 m
    public var radarRange: Double = 15
    public var fakeIsland = false
    public var watermark = false
    public var watermarkText = "ESP v2.6 · Undetected"

    // Filters & performance
    /// 5…30 m
    public var maxDistance: Double = 30
    /// 5…20
    public var maxPeople: Double = 20
    /// Pose detection at 60 Hz while the phone is cool.
    public var smoothMode = false

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
    public static var visibilityToggles: [WritableKeyPath<Settings, Bool>] {
        [\.box, \.skeleton, \.headDot, \.label, \.activity, \.detailCard, \.distance, \.trails, \.chams,
         \.snaplines, \.offscreenArrows,
         \.showAnimals, \.showObjects,
         \.stats, \.playerList, \.eventLog, \.radar, \.fakeIsland, \.watermark,
         \.recordButton, \.recordIndicator]
    }

    public mutating func apply(_ preset: Preset) {
        self.preset = preset
        guard preset != .custom else { return }

        let on: [WritableKeyPath<Settings, Bool>]
        switch preset {
        case .legit:
            on = [\.box, \.label, \.distance]
            boxStyle = .corner
        case .vip:
            on = Self.visibilityToggles
            boxStyle = .glass
        case .streamer:
            on = [\.box, \.label, \.activity, \.skeleton, \.watermark, \.stats]
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

    /// v1 keys that were renamed.
    private enum LegacyKeys: String, CodingKey {
        case name
    }

    /// Tolerant decoding: a missing or unreadable key keeps its default, so old or damaged saves still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        func read<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        let d = Settings()

        // v1 called the VIP preset "rage".
        let rawPreset = (try? c.decodeIfPresent(String.self, forKey: .preset)) ?? nil
        preset = rawPreset == "rage" ? .vip : rawPreset.flatMap(Preset.init(rawValue:)) ?? d.preset

        box = read(.box, d.box)
        boxStyle = read(.boxStyle, d.boxStyle)
        skeleton = read(.skeleton, d.skeleton)
        headDot = read(.headDot, d.headDot)
        let legacyName = ((try? legacy.decodeIfPresent(Bool.self, forKey: .name)) ?? nil) ?? d.label
        label = read(.label, legacyName)
        activity = read(.activity, d.activity)
        detailCard = read(.detailCard, d.detailCard)
        distance = read(.distance, d.distance)
        trails = read(.trails, d.trails)
        chams = read(.chams, d.chams)
        snaplines = read(.snaplines, d.snaplines)
        offscreenArrows = read(.offscreenArrows, d.offscreenArrows)
        showAnimals = read(.showAnimals, d.showAnimals)
        showObjects = read(.showObjects, d.showObjects)
        stats = read(.stats, d.stats)
        playerList = read(.playerList, d.playerList)
        eventLog = read(.eventLog, d.eventLog)
        radar = read(.radar, d.radar)
        // Sliders keep these in range; a damaged save must not (radar range 0 would divide by zero).
        radarRange = min(max(read(.radarRange, d.radarRange), 5), 30)
        fakeIsland = read(.fakeIsland, d.fakeIsland)
        watermark = read(.watermark, d.watermark)
        watermarkText = read(.watermarkText, d.watermarkText)
        maxDistance = min(max(read(.maxDistance, d.maxDistance), 5), 30)
        maxPeople = min(max(read(.maxPeople, d.maxPeople), 5), 20)
        smoothMode = read(.smoothMode, d.smoothMode)
        recordButton = read(.recordButton, d.recordButton)
        recordIndicator = read(.recordIndicator, d.recordIndicator)
        microphone = read(.microphone, d.microphone)
        haptics = read(.haptics, d.haptics)
        accent = read(.accent, d.accent)
        hasSeenHint = read(.hasSeenHint, d.hasSeenHint)

        // A v1 save (no v2 keys) with a named preset gets that preset's v2 features, not its old v1 flags.
        let isV1 = !c.contains(.label) && !c.contains(.activity)
        if isV1, rawPreset != nil, preset != .custom { apply(preset) }
    }
}
