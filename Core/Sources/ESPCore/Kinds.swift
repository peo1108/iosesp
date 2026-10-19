/// Animals the object detector can see (the COCO animal classes).
public enum AnimalKind: String, CaseIterable, Sendable {
    case dog, cat, bird, horse, sheep, cow, elephant, bear, zebra, giraffe

    public var name: String {
        switch self {
        case .dog: "Chó"
        case .cat: "Mèo"
        case .bird: "Chim"
        case .horse: "Ngựa"
        case .sheep: "Cừu"
        case .cow: "Bò"
        case .elephant: "Voi"
        case .bear: "Gấu"
        case .zebra: "Ngựa vằn"
        case .giraffe: "Hươu cao cổ"
        }
    }

    public var emoji: String {
        switch self {
        case .dog: "🐕"
        case .cat: "🐈"
        case .bird: "🐦"
        case .horse: "🐎"
        case .sheep: "🐑"
        case .cow: "🐄"
        case .elephant: "🐘"
        case .bear: "🐻"
        case .zebra: "🦓"
        case .giraffe: "🦒"
        }
    }

    /// Rough box height in meters, for guessing distance when there is no depth.
    public var typicalHeight: Float {
        switch self {
        case .dog: 0.55
        case .cat: 0.3
        case .bird: 0.25
        case .horse: 1.7
        case .sheep: 0.9
        case .cow: 1.5
        case .elephant: 3
        case .bear: 1.2
        case .zebra: 1.4
        case .giraffe: 4.5
        }
    }
}

/// What a tracked thing is. Tracks only ever match detections of the same kind.
public enum EntityKind: Hashable, Sendable {
    case person
    case animal(AnimalKind)

    public var name: String {
        switch self {
        case .person: "Người"
        case let .animal(animal): animal.name
        }
    }

    public var isPerson: Bool { self == .person }

    /// Rough box height in meters of a standing person or a typical animal.
    public var typicalHeight: Float {
        switch self {
        case .person: 1.7
        case let .animal(animal): animal.typicalHeight
        }
    }
}
