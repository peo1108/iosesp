import ESPCore

/// A person straight out of Vision: normalized captured-image coordinates, top-left origin.
struct RawDetection {
    var box: Rect
    var joints: [Joint: Vec2]
}
