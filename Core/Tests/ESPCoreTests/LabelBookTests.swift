import Testing
@testable import ESPCore

@Test func numbersPerKindInOrder() {
    var book = LabelBook()
    #expect(book.label(for: 5, kind: .person) == "Người 01")
    #expect(book.label(for: 7, kind: .animal(.dog)) == "Chó 01")
    #expect(book.label(for: 9, kind: .person) == "Người 02")
    #expect(book.label(for: 11, kind: .animal(.cat)) == "Mèo 01")
}

@Test func sameIdKeepsLabel() {
    var book = LabelBook()
    _ = book.label(for: 5, kind: .person)
    _ = book.label(for: 6, kind: .person)
    #expect(book.label(for: 5, kind: .person) == "Người 01")
}

@Test func animalNamesAndEmoji() {
    #expect(AnimalKind.dog.name == "Chó" && AnimalKind.dog.emoji == "🐕")
    #expect(AnimalKind.giraffe.name == "Hươu cao cổ")
    #expect(EntityKind.person.name == "Người" && EntityKind.animal(.cat).name == "Mèo")
}
