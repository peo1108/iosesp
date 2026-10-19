import Testing
@testable import ESPCore

@Test func identityIsDeterministicAndInRange() {
    #expect(NameGenerator.identity(for: 7) == NameGenerator.identity(for: 7))
    let ids = (0..<50).map(NameGenerator.identity(for:))
    #expect(ids.allSatisfy { (1...99).contains($0.level) })
    #expect(Set(ids.map(\.name)).count > 5)
    #expect(Set(ids.map(\.rankSymbol)).isSubset(of: ["shield.fill", "star.fill", "crown.fill", "bolt.fill", "flame.fill"]))
}

@Test func playerNumberHasFourDigits() {
    let numbered = (0..<200).map(NameGenerator.identity(for:)).map(\.name).filter { $0.hasPrefix("Player_") }
    #expect(!numbered.isEmpty)
    #expect(numbered.allSatisfy { $0.count == "Player_0000".count && Int($0.dropFirst(7)) != nil })
}

@Test func splitMixIsDeterministic() {
    var a = SplitMix64(seed: 42), b = SplitMix64(seed: 42)
    #expect(a.next() == b.next())
}
