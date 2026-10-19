/// Hands out "Người 01", "Chó 01"… numbered per kind in order of first appearance, stable per track id.
public struct LabelBook: Sendable {
    private var labels: [Int: String] = [:]
    private var counters: [EntityKind: Int] = [:]

    public init() {}

    public mutating func label(for id: Int, kind: EntityKind) -> String {
        if let existing = labels[id] { return existing }
        let n = (counters[kind] ?? 0) + 1
        counters[kind] = n
        let label = kind.name + " " + (n < 10 ? "0\(n)" : "\(n)")
        labels[id] = label
        return label
    }
}
