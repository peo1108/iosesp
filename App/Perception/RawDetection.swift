import ESPCore

/// Vision (iOS 18+) also declares a `Joint`; the app module's own alias wins over both imports.
typealias Joint = ESPCore.Joint

/// A person straight out of Vision: normalized captured-image coordinates, top-left origin.
struct RawDetection {
    var box: Rect
    var joints: [Joint: Vec2]
}
