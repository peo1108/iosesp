import ESPCore
import SwiftUI

enum Palette {
    static let visible = Color(uiColor: .systemGreen)
    static let partial = Color(uiColor: .systemYellow)
    static let animal = Color(uiColor: .systemOrange)
    static let alert = Color(uiColor: .systemRed)

    static func accent(_ name: AccentName) -> Color {
        switch name {
        case .blue: Color(uiColor: .systemBlue)
        case .purple: Color(uiColor: .systemPurple)
        case .pink: Color(uiColor: .systemPink)
        case .red: Color(uiColor: .systemRed)
        case .orange: Color(uiColor: .systemOrange)
        case .green: Color(uiColor: .systemGreen)
        case .mint: Color(uiColor: .systemMint)
        case .cyan: Color(uiColor: .systemCyan)
        }
    }

    static func color(for track: Track) -> Color {
        if !track.kind.isPerson { return animal }
        return track.occlusion == .partial ? partial : visible
    }
}
