import ESPCore
import Observation
import SwiftUI

/// The menu's settings, saved to UserDefaults on every change.
@MainActor @Observable
final class SettingsStore {
    private static let key = "esp.settings.v1"

    var settings: Settings {
        didSet {
            if let data = try? JSONEncoder().encode(settings) {
                UserDefaults.standard.set(data, forKey: Self.key)
            }
        }
    }

    init() {
        settings = Settings.decodeOrDefault(UserDefaults.standard.data(forKey: Self.key))
    }

    /// Binding for a menu control; edits mark the preset as Custom.
    func binding<V>(_ keyPath: WritableKeyPath<Settings, V>) -> Binding<V> {
        Binding(get: { self.settings[keyPath: keyPath] },
                set: { self.settings.set(keyPath, $0) })
    }

    func apply(_ preset: Preset) {
        settings.apply(preset)
    }
}
