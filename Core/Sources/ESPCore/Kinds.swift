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
}
