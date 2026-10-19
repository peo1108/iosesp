public enum ThermalLevel: Sendable {
    case nominal, fair, serious, critical
}

public struct PerceptionBudget: Equatable, Sendable {
    /// People (pose model) runs per second.
    public var poseHz: Double
    /// Animals & objects runs per second.
    public var objectHz: Double
    public var showHeatWarning: Bool
    /// HUD redraws per second.
    public var hudHz: Double

    public init(poseHz: Double, objectHz: Double, showHeatWarning: Bool, hudHz: Double) {
        self.poseHz = poseHz
        self.objectHz = objectHz
        self.showHeatWarning = showHeatWarning
        self.hudHz = hudHz
    }
}

/// How hard perception may run for the phone's temperature; recording caps it further.
/// A cool phone sees people every camera frame (60 Hz) and animals every other frame.
public enum ThermalPolicy {
    public static func budget(_ level: ThermalLevel, isRecording: Bool) -> PerceptionBudget {
        var budget: PerceptionBudget
        switch level {
        case .nominal:
            budget = PerceptionBudget(poseHz: 60, objectHz: 30, showHeatWarning: false, hudHz: 60)
        case .fair:
            budget = PerceptionBudget(poseHz: 30, objectHz: 15, showHeatWarning: false, hudHz: 60)
        case .serious:
            budget = PerceptionBudget(poseHz: 20, objectHz: 8, showHeatWarning: false, hudHz: 30)
        case .critical:
            budget = PerceptionBudget(poseHz: 12, objectHz: 4, showHeatWarning: true, hudHz: 30)
        }
        if isRecording {
            budget.poseHz = min(budget.poseHz, 30)
            budget.objectHz = min(budget.objectHz, 15)
        }
        return budget
    }
}
