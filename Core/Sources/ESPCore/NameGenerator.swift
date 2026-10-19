public struct PlayerIdentity: Equatable, Sendable {
    public var name: String
    public var level: Int
    public var rankSymbol: String

    public init(name: String, level: Int, rankSymbol: String) {
        self.name = name
        self.level = level
        self.rankSymbol = rankSymbol
    }
}

/// Fake gamer identities, fixed per track id so a person keeps the same name.
public enum NameGenerator {
    static let names = [
        "xX_Sniper_Xx", "NoobMaster69", "Player_####", "ProGamer_vn", "HeadshotKing",
        "CampingPro", "LagSwitch", "AFK_Bot", "NotACheater", "Sweaty_Tryhard",
    ]
    static let ranks = ["shield.fill", "star.fill", "crown.fill", "bolt.fill", "flame.fill"]

    public static func identity(for id: Int) -> PlayerIdentity {
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(id)) &* 0x9E37_79B9_7F4A_7C15)
        var name = names[Int(rng.next() % UInt64(names.count))]
        if name.hasSuffix("####") {
            let digits = String(rng.next() % 10_000)
            name = "Player_" + String(repeating: "0", count: 4 - digits.count) + digits
        }
        let level = Int(rng.next() % 99) + 1
        let rank = ranks[Int(rng.next() % UInt64(ranks.count))]
        return PlayerIdentity(name: name, level: level, rankSymbol: rank)
    }
}
