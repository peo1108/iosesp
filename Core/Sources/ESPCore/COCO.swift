/// Things near people that tell what they are doing.
public enum ObjectKind: String, CaseIterable, Sendable {
    case phone, cup, bottle, wineGlass, laptop, book, umbrella, ball
    case chair, couch, bench, bed, backpack, handbag, bicycle, motorcycle

    public var name: String {
        switch self {
        case .phone: "Điện thoại"
        case .cup: "Cốc"
        case .bottle: "Chai"
        case .wineGlass: "Ly"
        case .laptop: "Laptop"
        case .book: "Sách"
        case .umbrella: "Ô"
        case .ball: "Bóng"
        case .chair: "Ghế"
        case .couch: "Sofa"
        case .bench: "Ghế băng"
        case .bed: "Giường"
        case .backpack: "Balo"
        case .handbag: "Túi"
        case .bicycle: "Xe đạp"
        case .motorcycle: "Xe máy"
        }
    }

    public var emoji: String {
        switch self {
        case .phone: "📱"
        case .cup: "☕"
        case .bottle: "🧴"
        case .wineGlass: "🍷"
        case .laptop: "💻"
        case .book: "📖"
        case .umbrella: "☂️"
        case .ball: "⚽"
        case .chair: "🪑"
        case .couch: "🛋"
        case .bench: "🪑"
        case .bed: "🛏"
        case .backpack: "🎒"
        case .handbag: "👜"
        case .bicycle: "🚲"
        case .motorcycle: "🏍"
        }
    }
}

/// An object from the detector, in captured-image coordinates (normalized, top-left origin).
public struct DetectedObject: Sendable, Equatable {
    public var kind: ObjectKind
    public var box: Rect
    public var confidence: Float

    public init(kind: ObjectKind, box: Rect, confidence: Float) {
        self.kind = kind
        self.box = box
        self.confidence = confidence
    }
}

/// What a COCO class label means to the app.
public enum COCOClass: Sendable, Equatable {
    case person
    case animal(AnimalKind)
    case object(ObjectKind)
    case other

    private static let objects: [String: ObjectKind] = [
        "cell phone": .phone, "cup": .cup, "bottle": .bottle, "wine glass": .wineGlass, "laptop": .laptop,
        "book": .book, "umbrella": .umbrella, "sports ball": .ball, "chair": .chair, "couch": .couch,
        "bench": .bench, "bed": .bed, "backpack": .backpack, "handbag": .handbag, "bicycle": .bicycle,
        "motorcycle": .motorcycle,
    ]

    public init(label: String) {
        let key = label.lowercased()
        if key == "person" {
            self = .person
        } else if let animal = AnimalKind(rawValue: key) {
            self = .animal(animal)
        } else if let object = Self.objects[key] {
            self = .object(object)
        } else {
            self = .other
        }
    }
}
