import Foundation

/// How "near" something looks on screen, so the ESP reads in depth: 1 at arm's length, 0 far down the street.
/// Logarithmic, like perspective itself — the step from 2 m to 4 m looks as big as from 8 m to 16 m.
public enum DepthStyle {
    public static let near: Float = 1.5
    public static let far: Float = 18

    public static func nearness(_ distance: Float) -> Float {
        guard distance.isFinite, distance > near else { return 1 }
        let t = logf(distance / near) / logf(far / near)
        return 1 - min(max(t, 0), 1)
    }

    /// Box line width in points.
    public static func lineWidth(_ distance: Float) -> Float { 0.8 + 0.8 * nearness(distance) }
    /// Opacity of lines and cards: far things fade but never vanish.
    public static func opacity(_ distance: Float) -> Float { 0.45 + 0.55 * nearness(distance) }
    /// Scale of the detail card.
    public static func cardScale(_ distance: Float) -> Float { 0.72 + 0.28 * nearness(distance) }
}
