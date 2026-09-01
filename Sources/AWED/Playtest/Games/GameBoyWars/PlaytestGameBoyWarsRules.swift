import AWEDCore

/// Rules shared by the three staggered-grid Game Boy Wars variants.
///
/// Playtesting currently exposes the fifteen shared unit roles. GB Wars 1's
/// editor atlas additionally retains every cartridge silhouette in its stable
/// element slot, while each ruleset keeps its own cost/mobility profile; GBW3
/// uses its lower gold scale multiplied by ten to match the editor's 1,000 G
/// per-property economy.
enum PlaytestGameBoyWarsRules {
    static let weatherOptions: [PlaytestWeather] = [.clear]

    static let landUnits: [Element] = [
        .unitInfantry, .unitMech, .unitAPC, .unitRecon, .unitRocket,
        .unitAntiAir, .unitArtillery, .unitTank
    ]
    static let airUnits: [Element] = [.unitTCopter, .unitBCopter, .unitBomber]
    static let seaUnits: [Element] = [.unitLander, .unitSub, .unitCruiser, .unitBattleship]

    static func supportsFogOfWar(for ruleset: PlaytestRuleset) -> Bool {
        ruleset != .gameBoyWars
    }

    static func stats(for element: Element, ruleset: PlaytestRuleset) -> PlaytestUnitStats? {
        guard let generation = generation(for: ruleset) else { return nil }
        switch element.simplified {
        case .unitInfantry: return infantryStats
        case .unitMech: return mechStats(generation)
        case .unitAPC: return apcStats(generation)
        case .unitRecon: return reconStats(generation)
        case .unitRocket: return rocketStats(generation)
        case .unitAntiAir: return antiAirStats(generation)
        case .unitArtillery: return artilleryStats(generation)
        case .unitTank: return tankStats(generation)
        case .unitTCopter: return tcopterStats
        case .unitBCopter: return bcopterStats
        case .unitBomber: return bomberStats
        case .unitLander: return landerStats(generation)
        case .unitSub: return subStats
        case .unitCruiser: return cruiserStats
        case .unitBattleship: return battleshipStats(generation)
        default: return nil
        }
    }

    private static let infantryStats = PlaytestUnitStats(cost: 1_000, move: 3, minRange: 1, maxRange: 1, domain: .land, canCapture: true, attackPower: 55, movementType: .foot, maxFuel: 99, vision: 2)
    private static let tcopterStats = PlaytestUnitStats(cost: 5_000, move: 7, minRange: 0, maxRange: 0, domain: .air, canCapture: false, attackPower: 0, movementType: .air, maxFuel: 80, dailyFuelUse: 2, vision: 3, canCounterattack: false)
    private static let bcopterStats = PlaytestUnitStats(cost: 10_000, move: 7, minRange: 1, maxRange: 1, domain: .air, canCapture: false, attackPower: 75, movementType: .air, maxFuel: 90, dailyFuelUse: 2, vision: 4, primaryAmmo: 6)
    private static let bomberStats = PlaytestUnitStats(cost: 20_000, move: 8, minRange: 1, maxRange: 1, domain: .air, canCapture: false, attackPower: 110, movementType: .air, maxFuel: 99, dailyFuelUse: 5, vision: 3, primaryAmmo: 6)
    private static let subStats = PlaytestUnitStats(cost: 20_000, move: 5, minRange: 1, maxRange: 1, domain: .sea, canCapture: false, attackPower: 95, movementType: .ship, maxFuel: 60, dailyFuelUse: 1, vision: 5, primaryAmmo: 6)
    private static let cruiserStats = PlaytestUnitStats(cost: 18_000, move: 6, minRange: 1, maxRange: 1, domain: .sea, canCapture: false, attackPower: 100, movementType: .ship, maxFuel: 99, dailyFuelUse: 1, vision: 4, primaryAmmo: 6)
    private static func mechStats(_ generation: Int) -> PlaytestUnitStats { .init(cost: 2_000, move: 2, minRange: 1, maxRange: 1, domain: .land, canCapture: true, attackPower: 70, movementType: .mech, maxFuel: 70, vision: 2, primaryAmmo: generation == 3 ? 1 : 3) }
    private static func apcStats(_ generation: Int) -> PlaytestUnitStats { .init(cost: generation == 1 ? 4_200 : 5_000, move: generation == 3 ? 7 : 6, minRange: 0, maxRange: 0, domain: .land, canCapture: false, attackPower: 0, movementType: .tire, maxFuel: generation == 3 ? 50 : 70, vision: 2, canCounterattack: false) }
    private static func reconStats(_ generation: Int) -> PlaytestUnitStats { .init(cost: 4_000, move: generation == 3 ? 7 : 8, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 65, movementType: .tire, maxFuel: 80, vision: 5) }
    private static func rocketStats(_ generation: Int) -> PlaytestUnitStats { .init(cost: generation == 1 ? 13_000 : 15_000, move: 5, minRange: 3, maxRange: 5, domain: .land, canCapture: false, attackPower: 95, movementType: .tire, maxFuel: 50, primaryAmmo: 6, canMoveAndFire: false, canCounterattack: false) }
    private static func antiAirStats(_ generation: Int) -> PlaytestUnitStats { .init(cost: generation == 1 ? 5_500 : 7_000, move: 6, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 100, movementType: .tread, maxFuel: 60, vision: 3, primaryAmmo: 6) }
    private static func artilleryStats(_ generation: Int) -> PlaytestUnitStats { .init(cost: generation == 1 ? 5_500 : 6_000, move: 5, minRange: 2, maxRange: 3, domain: .land, canCapture: false, attackPower: 88, movementType: .tread, maxFuel: 50, primaryAmmo: 6, canMoveAndFire: false, canCounterattack: false) }
    private static func tankStats(_ generation: Int) -> PlaytestUnitStats { .init(cost: generation == 1 ? 6_000 : 7_000, move: 6, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 78, movementType: .tread, maxFuel: 70, primaryAmmo: 6) }
    private static func landerStats(_ generation: Int) -> PlaytestUnitStats { .init(cost: generation == 1 ? 18_500 : 12_000, move: 6, minRange: 0, maxRange: 0, domain: .sea, canCapture: false, attackPower: 0, movementType: .lander, maxFuel: 99, dailyFuelUse: 1, vision: 2, canCounterattack: false) }
    private static func battleshipStats(_ generation: Int) -> PlaytestUnitStats { .init(cost: generation == 1 ? 28_800 : 28_000, move: 6, minRange: 3, maxRange: 5, domain: .sea, canCapture: false, attackPower: 95, movementType: .ship, maxFuel: 99, dailyFuelUse: 1, vision: 3, primaryAmmo: 6, canMoveAndFire: false, canCounterattack: false) }

    private static func generation(for ruleset: PlaytestRuleset) -> Int? {
        switch ruleset {
        case .gameBoyWars: return 1
        case .gameBoyWars2: return 2
        case .gameBoyWars3: return 3
        default: return nil
        }
    }

    static func movementCost(for unit: Element, terrain: Element, ruleset: PlaytestRuleset) -> Int? {
        guard stats(for: unit, ruleset: ruleset) != nil else { return nil }
        return PlaytestAdvanceWarsRules.movementCost(for: unit, terrain: terrain, weather: .clear)
    }

    static func canTransport(_ transport: Element, cargo: Element, ruleset: PlaytestRuleset) -> Bool {
        guard transport.army == cargo.army, stats(for: cargo, ruleset: ruleset) != nil else { return false }
        switch transport.simplified {
        case .unitAPC, .unitTCopter:
            return cargo.simplified == .unitInfantry || cargo.simplified == .unitMech
        case .unitLander:
            return stats(for: cargo, ruleset: ruleset)?.domain == .land
        case .unitCruiser:
            return cargo.simplified == .unitBCopter || cargo.simplified == .unitTCopter
        default:
            return false
        }
    }
}
