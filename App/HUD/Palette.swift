import ESPCore
import SwiftUI

enum Palette {
    static let visible = Color(uiColor: .systemGreen)
    static let partial = Color(uiColor: .systemYellow)
    static let locked = Color(uiColor: .systemRed)

    static func color(for track: Track, locked isLocked: Bool) -> Color {
        if isLocked { return locked }
        return track.occlusion == .partial ? partial : visible
    }
}
