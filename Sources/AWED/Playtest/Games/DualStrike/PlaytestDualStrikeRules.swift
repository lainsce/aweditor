import AWEDCore

/// Dual Strike's unit roster and production availability.
///
/// Keeping this table separate from PlaytestSession makes the DS-specific
/// costs, movement values, fuel, vision, and unit availability easy to audit
/// against the rules reference without mixing them into turn-state mechanics.
enum PlaytestDualStrikeRules {
    static let weatherOptions: [PlaytestWeather] = [.random, .clear, .rain, .snow, .sandstorm]

    static func fogOfWarIsActive(manualFogEnabled: Bool, weather: PlaytestWeather) -> Bool {
        manualFogEnabled || weather == .rain
    }

    static func movementFuelCost(for unit: Element, movement: Int, weather: PlaytestWeather) -> Int {
        guard weather == .snow, stats(for: unit) != nil else { return movement }
        return movement * 2
    }

    static func maximumAttackRange(for stats: PlaytestUnitStats, weather: PlaytestWeather) -> Int {
        guard weather == .sandstorm, stats.maxRange > stats.minRange else { return stats.maxRange }
        return max(stats.minRange, stats.maxRange - 1)
    }

    private static let statsByValue: [Int: PlaytestUnitStats] = makeStats()

    private static func makeStats() -> [Int: PlaytestUnitStats] {
        statsPart1().merging(statsPart2(), uniquingKeysWith: { _, new in new })
            .merging(statsPart3(), uniquingKeysWith: { _, new in new })
    }

    private static func statsPart1() -> [Int: PlaytestUnitStats] {
        [
        Element.unitInfantry.simplified.value: .init(cost: 1_000, move: 3, minRange: 1, maxRange: 1, domain: .land, canCapture: true, attackPower: 55, movementType: .foot, maxFuel: 99, vision: 2),
        Element.unitMech.simplified.value: .init(cost: 3_000, move: 2, minRange: 1, maxRange: 1, domain: .land, canCapture: true, attackPower: 85, movementType: .mech, maxFuel: 70, vision: 2, primaryAmmo: 3),
        Element.unitAPC.simplified.value: .init(cost: 5_000, move: 6, minRange: 0, maxRange: 0, domain: .land, canCapture: false, attackPower: 0, movementType: .tread, maxFuel: 70, vision: 1),
        Element.unitRecon.simplified.value: .init(cost: 4_000, move: 8, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 60, movementType: .tire, maxFuel: 80, vision: 5),
        Element.unitTank.simplified.value: .init(cost: 7_000, move: 6, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 72, movementType: .tread, maxFuel: 70, vision: 3, primaryAmmo: 9),
        Element.unitMDTank.simplified.value: .init(cost: 16_000, move: 5, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 96, movementType: .tread, maxFuel: 50, vision: 1, primaryAmmo: 8),
        Element.unitNeoTank.simplified.value: .init(cost: 22_000, move: 6, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 105, movementType: .tread, maxFuel: 99, vision: 1, primaryAmmo: 9),
        Element.unitMegaTank.simplified.value: .init(cost: 28_000, move: 4, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 115, movementType: .tread, maxFuel: 50, vision: 1, primaryAmmo: 9),
        Element.unitOozium.simplified.value: .init(cost: 0, move: 1, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 100)
        ]
    }

    private static func statsPart2() -> [Int: PlaytestUnitStats] {
        [
        Element.unitArtillery.simplified.value: .init(cost: 6_000, move: 5, minRange: 2, maxRange: 3, domain: .land, canCapture: false, attackPower: 68, movementType: .tread, maxFuel: 50, vision: 1, primaryAmmo: 9, canMoveAndFire: false, canCounterattack: false),
        Element.unitRocket.simplified.value: .init(cost: 15_000, move: 5, minRange: 3, maxRange: 5, domain: .land, canCapture: false, attackPower: 78, movementType: .tire, maxFuel: 50, vision: 1, primaryAmmo: 6, canMoveAndFire: false, canCounterattack: false),
        Element.unitPipeRunner.simplified.value: .init(cost: 20_000, move: 9, minRange: 2, maxRange: 5, domain: .land, canCapture: false, attackPower: 84, movementType: .tread, maxFuel: 99, vision: 4, primaryAmmo: 9, canMoveAndFire: false, canCounterattack: false),
        Element.unitMissile.simplified.value: .init(cost: 12_000, move: 4, minRange: 3, maxRange: 5, domain: .land, canCapture: false, attackPower: 86, movementType: .tire, maxFuel: 50, vision: 5, primaryAmmo: 5, canMoveAndFire: false, canCounterattack: false),
        Element.unitAntiAir.simplified.value: .init(cost: 8_000, move: 6, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 92, movementType: .tread, maxFuel: 60, vision: 2, primaryAmmo: 9),
        Element.unitTCopter.simplified.value: .init(cost: 5_000, move: 6, minRange: 0, maxRange: 0, domain: .air, canCapture: false, attackPower: 0, movementType: .air, maxFuel: 99, dailyFuelUse: 2, vision: 2, canCounterattack: false),
        Element.unitBCopter.simplified.value: .init(cost: 9_000, move: 6, minRange: 1, maxRange: 1, domain: .air, canCapture: false, attackPower: 72, movementType: .air, maxFuel: 99, dailyFuelUse: 2, vision: 3, primaryAmmo: 6, secondaryAttackPower: 6)
        ]
    }

    private static func statsPart3() -> [Int: PlaytestUnitStats] {
        [
        Element.unitFighter.simplified.value: .init(cost: 20_000, move: 9, minRange: 1, maxRange: 1, domain: .air, canCapture: false, attackPower: 100, movementType: .air, maxFuel: 99, dailyFuelUse: 5, vision: 2, primaryAmmo: 9),
        Element.unitBomber.simplified.value: .init(cost: 22_000, move: 7, minRange: 1, maxRange: 1, domain: .air, canCapture: false, attackPower: 100, movementType: .air, maxFuel: 99, dailyFuelUse: 5, vision: 2, primaryAmmo: 9),
        Element.unitStealth.simplified.value: .init(cost: 24_000, move: 6, minRange: 1, maxRange: 1, domain: .air, canCapture: false, attackPower: 98, movementType: .air, maxFuel: 60, dailyFuelUse: 5, vision: 4, primaryAmmo: 6),
        Element.unitBlackBomb.simplified.value: .init(cost: 25_000, move: 9, minRange: 1, maxRange: 1, domain: .air, canCapture: false, attackPower: 100, movementType: .air, maxFuel: 45, dailyFuelUse: 5, vision: 1, canCounterattack: false),
        Element.unitBlackBoat.simplified.value: .init(cost: 7_500, move: 6, minRange: 0, maxRange: 0, domain: .sea, canCapture: false, attackPower: 0, movementType: .ship, maxFuel: 60, dailyFuelUse: 1, vision: 1, canCounterattack: false),
        Element.unitLander.simplified.value: .init(cost: 12_000, move: 6, minRange: 0, maxRange: 0, domain: .sea, canCapture: false, attackPower: 0, movementType: .lander, maxFuel: 99, dailyFuelUse: 1, vision: 1, canCounterattack: false),
        Element.unitCruiser.simplified.value: .init(cost: 18_000, move: 6, minRange: 1, maxRange: 1, domain: .sea, canCapture: false, attackPower: 82, movementType: .ship, maxFuel: 99, dailyFuelUse: 1, vision: 3, primaryAmmo: 9),
        Element.unitSub.simplified.value: .init(cost: 20_000, move: 5, minRange: 1, maxRange: 1, domain: .sea, canCapture: false, attackPower: 80, movementType: .ship, maxFuel: 60, dailyFuelUse: 1, vision: 5, primaryAmmo: 6),
        Element.unitBattleship.simplified.value: .init(cost: 28_000, move: 5, minRange: 2, maxRange: 6, domain: .sea, canCapture: false, attackPower: 90, movementType: .ship, maxFuel: 99, dailyFuelUse: 1, vision: 2, primaryAmmo: 9, canMoveAndFire: false, canCounterattack: false),
        Element.unitCarrier.simplified.value: .init(cost: 30_000, move: 5, minRange: 3, maxRange: 8, domain: .sea, canCapture: false, attackPower: 100, movementType: .ship, maxFuel: 99, dailyFuelUse: 1, vision: 4, primaryAmmo: 9, canMoveAndFire: false, canCounterattack: false)
        ]
    }

    static func stats(for element: Element) -> PlaytestUnitStats? {
        statsByValue[element.simplified.value]
    }

    /// Dual Strike keeps clear-weather movement costs from the GBA games, but
    /// rain does not add movement points and snow only changes fuel use.
    static func movementCost(for unit: Element, terrain: Element) -> Int? {
        let tile = terrain.simplified
        guard !terrain.isExtra, tile != .terrainPipe, tile != .terrainSeam else {
            return unit.simplified == .unitPipeRunner &&
                (tile == .terrainPipe || tile == .terrainSeam || tile == .buildingBase) ? 1 : nil
        }

        guard let stats = stats(for: unit) else { return nil }
        let isBridge = tile == .terrainBridgeH || tile == .terrainBridgeV
        if stats.domain == .sea {
            return seaMovementCost(for: unit, tile: tile, isBridge: isBridge)
        }
        guard stats.domain != .air else { return 1 }
        guard unit.simplified != .unitPipeRunner else { return tile == .buildingBase ? 1 : nil }
        guard !isBridge && !terrain.isBuilding else { return 1 }
        guard !terrain.isSea else { return tile == .terrainShoal ? 1 : nil }
        return landMovementCost(for: stats.movementType, tile: tile)
    }

    private static func seaMovementCost(for unit: Element, tile: Element, isBridge: Bool) -> Int? {
        guard !isBridge else { return nil }
        switch tile {
        case .terrainSea, .buildingPort: return 1
        case .terrainReef: return 2
        case .terrainShoal:
            return unit.simplified == .unitLander || unit.simplified == .unitBlackBoat ? 1 : nil
        default: return nil
        }
    }

    private static func landMovementCost(for movementType: PlaytestMovementType, tile: Element) -> Int? {
        switch movementType {
        case .foot:
            return tile == .terrainMountain || tile == .terrainRiver ? 2 : 1
        case .mech:
            return 1
        case .tread:
            switch tile {
            case .terrainWood: return 2
            case .terrainMountain, .terrainRiver: return nil
            default: return 1
            }
        case .tire:
            switch tile {
            case .terrainPlain, .terrainPlainD: return 2
            case .terrainWood: return 3
            case .terrainMountain, .terrainRiver: return nil
            default: return 1
            }
        case .air, .ship, .lander:
            return 1
        }
    }

    static let landUnits: [Element] = [
        .unitInfantry, .unitMech, .unitAPC, .unitRecon, .unitTank, .unitMDTank,
        .unitNeoTank, .unitMegaTank, .unitArtillery, .unitRocket, .unitMissile,
        .unitAntiAir, .unitPipeRunner
    ]

    static let airUnits: [Element] = [
        .unitTCopter, .unitBCopter, .unitFighter, .unitBomber, .unitStealth, .unitBlackBomb
    ]

    static let seaUnits: [Element] = [
        .unitLander, .unitCruiser, .unitSub, .unitBattleship, .unitBlackBoat, .unitCarrier
    ]
}
