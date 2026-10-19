public enum BoxStyle: String, Codable, CaseIterable, Sendable {
    case corner, full, threeD, glass

    /// The 3D box needs good world tracking; the 2D styles don't change.
    public func effective(trackingNormal: Bool) -> BoxStyle {
        self == .threeD && !trackingNormal ? .full : self
    }
}
