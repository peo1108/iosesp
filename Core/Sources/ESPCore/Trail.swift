import Foundation

/// Recent floor positions of one person, for the footprint trail. Points closer than `spacing` to the last
/// one are skipped; points older than `ttl` are dropped.
public struct Trail: Sendable {
    public let spacing: Float
    public let ttl: TimeInterval
    private var stamps: [(position: Vec3, time: TimeInterval)] = []

    public init(spacing: Float = 0.12, ttl: TimeInterval = 5) {
        self.spacing = spacing
        self.ttl = ttl
    }

    public mutating func add(_ position: Vec3, at time: TimeInterval) {
        stamps.removeAll { time - $0.time > ttl }
        if let last = stamps.last, length(position - last.position) < spacing { return }
        stamps.append((position, time))
    }

    /// Oldest first; `age` is 0 for brand new and 1 for about to vanish.
    public func points(at time: TimeInterval) -> [(position: Vec3, age: Double)] {
        stamps.compactMap { s in
            let age = (time - s.time) / ttl
            return age <= 1 ? (s.position, max(age, 0)) : nil
        }
    }
}

/// "3 người · 🐕 1 · 🐈 1" for the HUD counter.
public enum CountSummary {
    public static func text(people: Int, animals: [AnimalKind: Int]) -> String {
        var parts: [String] = []
        if people > 0 { parts.append("\(people) người") }
        for kind in AnimalKind.allCases {
            if let n = animals[kind], n > 0 { parts.append("\(kind.emoji) \(n)") }
        }
        return parts.isEmpty ? "Không có ai" : parts.joined(separator: " · ")
    }
}
