import ESPCore
import Observation
import SwiftUI

/// The menu's settings, saved to UserDefaults on every change.
@MainActor @Observable
final class SettingsStore {
    /// Same key since v1: `Settings` decodes old saves tolerantly.
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
}
