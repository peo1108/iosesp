import ESPCore

/// Vision (iOS 18+) also declares a `Joint`; the app module's own alias wins over both imports.
typealias Joint = ESPCore.Joint

/// A person or animal straight out of a detector: normalized captured-image coordinates, top-left origin.
struct RawDetection {
    var box: Rect
    var kind: EntityKind = .person
    var confidence: Float = 1
    var joints: [Joint: Vec2] = [:]
}
