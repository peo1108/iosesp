public enum ThermalLevel: Sendable {
    case nominal, fair, serious, critical
}

public struct PerceptionBudget: Equatable, Sendable {
    public var hz: Double
    public var chamsAllowed: Bool
    public var showHeatWarning: Bool

    public init(hz: Double, chamsAllowed: Bool, showHeatWarning: Bool) {
        self.hz = hz
        self.chamsAllowed = chamsAllowed
        self.showHeatWarning = showHeatWarning
    }
}

/// How hard perception may run for the phone's temperature; recording caps it further.
public enum ThermalPolicy {
    public static func budget(_ level: ThermalLevel, isRecording: Bool) -> PerceptionBudget {
        var budget: PerceptionBudget
        switch level {
        case .nominal: budget = PerceptionBudget(hz: 30, chamsAllowed: true, showHeatWarning: false)
        case .fair: budget = PerceptionBudget(hz: 20, chamsAllowed: true, showHeatWarning: false)
        case .serious: budget = PerceptionBudget(hz: 10, chamsAllowed: false, showHeatWarning: false)
        case .critical: budget = PerceptionBudget(hz: 5, chamsAllowed: false, showHeatWarning: true)
        }
        if isRecording { budget.hz = min(budget.hz, 20) }
        return budget
    }
}
