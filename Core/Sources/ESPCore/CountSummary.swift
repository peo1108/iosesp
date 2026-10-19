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
