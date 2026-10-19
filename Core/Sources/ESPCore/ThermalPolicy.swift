public enum ThermalLevel: Sendable {
    case nominal, fair, serious, critical
}

public struct PerceptionBudget: Equatable, Sendable {
    /// People (pose model) runs per second.
    public var poseHz: Double
    /// Animals & objects runs per second.
    public var objectHz: Double
    public var chamsAllowed: Bool
    public var showHeatWarning: Bool
    /// HUD redraws per second.
    public var hudHz: Double

    public init(poseHz: Double, objectHz: Double, chamsAllowed: Bool, showHeatWarning: Bool, hudHz: Double) {
        self.poseHz = poseHz
        self.objectHz = objectHz
        self.chamsAllowed = chamsAllowed
        self.showHeatWarning = showHeatWarning
        self.hudHz = hudHz
    }
}

/// How hard perception may run for the phone's temperature; recording caps it further.
public enum ThermalPolicy {
    public static func budget(_ level: ThermalLevel, isRecording: Bool, smoothMode: Bool) -> PerceptionBudget {
        var budget: PerceptionBudget
        switch level {
        case .nominal:
            budget = PerceptionBudget(poseHz: smoothMode ? 60 : 30, objectHz: 15, chamsAllowed: true, showHeatWarning: false, hudHz: 60)
        case .fair:
            budget = PerceptionBudget(poseHz: 24, objectHz: 10, chamsAllowed: true, showHeatWarning: false, hudHz: 60)
        case .serious:
            budget = PerceptionBudget(poseHz: 15, objectHz: 5, chamsAllowed: false, showHeatWarning: false, hudHz: 30)
        case .critical:
            budget = PerceptionBudget(poseHz: 10, objectHz: 3, chamsAllowed: false, showHeatWarning: true, hudHz: 30)
        }
        if isRecording { budget.poseHz = min(budget.poseHz, 24) }
        return budget
    }
}
