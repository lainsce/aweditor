import AWEDCore

/// Super Famicom Wars rules for the sixteen source units currently exposed by
/// the editor atlas. Railroad occupies the shared Pipe slot and is traversable.
enum PlaytestSuperFamicomWarsRules {
    static let weatherOptions: [PlaytestWeather] = [.clear]
    static let supportsFogOfWar = true

    static let landUnits = PlaytestFamicomWarsRules.landUnits
    static let airUnits = PlaytestFamicomWarsRules.airUnits
    static let seaUnits = PlaytestFamicomWarsRules.seaUnits

    private static let statsByValue: [Int: PlaytestUnitStats] = makeStats()

    private static func makeStats() -> [Int: PlaytestUnitStats] {
        statsPart1().merging(statsPart2(), uniquingKeysWith: { _, new in new })
            .merging(statsPart3(), uniquingKeysWith: { _, new in new })
    }

    private static func statsPart1() -> [Int: PlaytestUnitStats] {
        [
        Element.unitInfantry.simplified.value: .init(cost: 1_000, move: 3, minRange: 1, maxRange: 1, domain: .land, canCapture: true, attackPower: 55, movementType: .foot, maxFuel: 99, vision: 2),
        Element.unitMech.simplified.value: .init(cost: 3_000, move: 2, minRange: 1, maxRange: 1, domain: .land, canCapture: true, attackPower: 75, movementType: .mech, maxFuel: 70, vision: 2, primaryAmmo: 3),
        Element.unitMDTank.simplified.value: .init(cost: 18_000, move: 4, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 110, movementType: .tread, maxFuel: 50, primaryAmmo: 6),
        Element.unitTank.simplified.value: .init(cost: 7_000, move: 6, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 78, movementType: .tread, maxFuel: 70, primaryAmmo: 6),
        Element.unitAPC.simplified.value: .init(cost: 5_000, move: 6, minRange: 0, maxRange: 0, domain: .land, canCapture: false, attackPower: 0, movementType: .tread, maxFuel: 70, canCounterattack: false),
        Element.unitRecon.simplified.value: .init(cost: 3_000, move: 6, minRange: 0, maxRange: 0, domain: .land, canCapture: false, attackPower: 0, movementType: .tire, maxFuel: 80, vision: 5, canCounterattack: false)
        ]
    }

    private static func statsPart2() -> [Int: PlaytestUnitStats] {
        [
        Element.unitArtillery.simplified.value: .init(cost: 6_000, move: 5, minRange: 2, maxRange: 3, domain: .land, canCapture: false, attackPower: 88, movementType: .tread, maxFuel: 50, primaryAmmo: 6, canMoveAndFire: false, canCounterattack: false),
        Element.unitRocket.simplified.value: .init(cost: 15_000, move: 5, minRange: 3, maxRange: 5, domain: .land, canCapture: false, attackPower: 95, movementType: .tire, maxFuel: 50, primaryAmmo: 6, canMoveAndFire: false, canCounterattack: false),
        Element.unitAntiAir.simplified.value: .init(cost: 7_000, move: 6, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 100, movementType: .tread, maxFuel: 60, vision: 2, primaryAmmo: 6),
        Element.unitMissile.simplified.value: .init(cost: 12_000, move: 4, minRange: 3, maxRange: 5, domain: .land, canCapture: false, attackPower: 100, movementType: .tire, maxFuel: 50, vision: 5, primaryAmmo: 6, canMoveAndFire: false, canCounterattack: false),
        Element.unitFighter.simplified.value: .init(cost: 20_000, move: 9, minRange: 1, maxRange: 1, domain: .air, canCapture: false, attackPower: 100, movementType: .air, maxFuel: 99, dailyFuelUse: 5, vision: 2, primaryAmmo: 9),
        Element.unitBomber.simplified.value: .init(cost: 22_000, move: 7, minRange: 1, maxRange: 1, domain: .air, canCapture: false, attackPower: 110, movementType: .air, maxFuel: 99, dailyFuelUse: 5, vision: 2, primaryAmmo: 9),
        Element.unitBCopter.simplified.value: .init(cost: 9_000, move: 6, minRange: 1, maxRange: 1, domain: .air, canCapture: false, attackPower: 75, movementType: .air, maxFuel: 99, dailyFuelUse: 2, vision: 3, primaryAmmo: 6),
        Element.unitTCopter.simplified.value: .init(cost: 5_000, move: 6, minRange: 0, maxRange: 0, domain: .air, canCapture: false, attackPower: 0, movementType: .air, maxFuel: 99, dailyFuelUse: 2, vision: 2, canCounterattack: false)
        ]
    }

    private static func statsPart3() -> [Int: PlaytestUnitStats] {
        [
        Element.unitBattleship.simplified.value: .init(cost: 28_000, move: 5, minRange: 3, maxRange: 5, domain: .sea, canCapture: false, attackPower: 95, movementType: .ship, maxFuel: 99, dailyFuelUse: 1, vision: 2, primaryAmmo: 9, canMoveAndFire: false, canCounterattack: false),
        Element.unitLander.simplified.value: .init(cost: 12_000, move: 6, minRange: 0, maxRange: 0, domain: .sea, canCapture: false, attackPower: 0, movementType: .lander, maxFuel: 99, dailyFuelUse: 1, vision: 1, canCounterattack: false)
        ]
    }

    static func stats(for element: Element) -> PlaytestUnitStats? {
        statsByValue[element.simplified.value]
    }

    static func movementCost(for unit: Element, terrain: Element) -> Int? {
        guard let stats = stats(for: unit) else { return nil }
        if terrain.simplified == .terrainPipe {
            switch stats.movementType {
            case .foot, .mech, .air: return 1
            case .tread: return 2
            case .tire: return 4
            case .ship, .lander: return nil
            }
        }
        return PlaytestAdvanceWarsRules.movementCost(for: unit, terrain: terrain, weather: .clear)
    }

    static func canTransport(_ transport: Element, cargo: Element) -> Bool {
        PlaytestFamicomWarsRules.canTransport(transport, cargo: cargo)
    }
}
