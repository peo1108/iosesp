/// What a COCO class label means to the app: people and the animals it tracks; everything else is ignored.
public enum COCOClass: Sendable, Equatable {
    case person
    case animal(AnimalKind)
    case other

    public init(label: String) {
        let key = label.lowercased()
        if key == "person" {
            self = .person
        } else if let animal = AnimalKind(rawValue: key) {
            self = .animal(animal)
        } else {
            self = .other
        }
    }
}
