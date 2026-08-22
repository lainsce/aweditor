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

    static func stats(for element: Element) -> PlaytestUnitStats? {
        switch element.simplified.value {
        case Element.unitInfantry.value:
            .init(cost: 1_000, move: 3, minRange: 1, maxRange: 1, domain: .land, canCapture: true, attackPower: 55, movementType: .foot, maxFuel: 99, vision: 2)
        case Element.unitMech.value:
            .init(cost: 3_000, move: 2, minRange: 1, maxRange: 1, domain: .land, canCapture: true, attackPower: 85, movementType: .mech, maxFuel: 70, vision: 2, primaryAmmo: 3)
        case Element.unitAPC.value:
            .init(cost: 5_000, move: 6, minRange: 0, maxRange: 0, domain: .land, canCapture: false, attackPower: 0, movementType: .tread, maxFuel: 70, vision: 1)
        case Element.unitRecon.value:
            .init(cost: 4_000, move: 8, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 60, movementType: .tire, maxFuel: 80, vision: 5)
        case Element.unitTank.value:
            .init(cost: 7_000, move: 6, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 72, movementType: .tread, maxFuel: 70, vision: 3, primaryAmmo: 9)
        case Element.unitMDTank.value:
            .init(cost: 16_000, move: 5, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 96, movementType: .tread, maxFuel: 50, vision: 1, primaryAmmo: 8)
        case Element.unitNeoTank.value:
            .init(cost: 22_000, move: 6, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 105, movementType: .tread, maxFuel: 99, vision: 1, primaryAmmo: 9)
        case Element.unitMegaTank.value:
            .init(cost: 28_000, move: 4, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 115, movementType: .tread, maxFuel: 50, vision: 1, primaryAmmo: 9)
        case Element.unitOozium.value:
            .init(cost: 0, move: 1, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 100)
        case Element.unitArtillery.value:
            .init(cost: 6_000, move: 5, minRange: 2, maxRange: 3, domain: .land, canCapture: false, attackPower: 68, movementType: .tread, maxFuel: 50, vision: 1, primaryAmmo: 9, canMoveAndFire: false, canCounterattack: false)
        case Element.unitRocket.value:
            .init(cost: 15_000, move: 5, minRange: 3, maxRange: 5, domain: .land, canCapture: false, attackPower: 78, movementType: .tire, maxFuel: 50, vision: 1, primaryAmmo: 6, canMoveAndFire: false, canCounterattack: false)
        case Element.unitPipeRunner.value:
            .init(cost: 20_000, move: 9, minRange: 2, maxRange: 5, domain: .land, canCapture: false, attackPower: 84, movementType: .tread, maxFuel: 99, vision: 4, primaryAmmo: 9, canMoveAndFire: false, canCounterattack: false)
        case Element.unitMissile.value:
            .init(cost: 12_000, move: 4, minRange: 3, maxRange: 5, domain: .land, canCapture: false, attackPower: 86, movementType: .tire, maxFuel: 50, vision: 5, primaryAmmo: 5, canMoveAndFire: false, canCounterattack: false)
        case Element.unitAntiAir.value:
            .init(cost: 8_000, move: 6, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 92, movementType: .tread, maxFuel: 60, vision: 2, primaryAmmo: 9)
        case Element.unitTCopter.value:
            .init(cost: 5_000, move: 6, minRange: 0, maxRange: 0, domain: .air, canCapture: false, attackPower: 0, movementType: .air, maxFuel: 99, dailyFuelUse: 2, vision: 2, canCounterattack: false)
        case Element.unitBCopter.value:
            .init(cost: 9_000, move: 6, minRange: 1, maxRange: 1, domain: .air, canCapture: false, attackPower: 72, movementType: .air, maxFuel: 99, dailyFuelUse: 2, vision: 3, primaryAmmo: 6, secondaryAttackPower: 6)
        case Element.unitFighter.value:
            .init(cost: 20_000, move: 9, minRange: 1, maxRange: 1, domain: .air, canCapture: false, attackPower: 100, movementType: .air, maxFuel: 99, dailyFuelUse: 5, vision: 2, primaryAmmo: 9)
        case Element.unitBomber.value:
            .init(cost: 22_000, move: 7, minRange: 1, maxRange: 1, domain: .air, canCapture: false, attackPower: 100, movementType: .air, maxFuel: 99, dailyFuelUse: 5, vision: 2, primaryAmmo: 9)
        case Element.unitStealth.value:
            .init(cost: 24_000, move: 6, minRange: 1, maxRange: 1, domain: .air, canCapture: false, attackPower: 98, movementType: .air, maxFuel: 60, dailyFuelUse: 5, vision: 4, primaryAmmo: 6)
        case Element.unitBlackBomb.value:
            .init(cost: 25_000, move: 9, minRange: 1, maxRange: 1, domain: .air, canCapture: false, attackPower: 100, movementType: .air, maxFuel: 45, dailyFuelUse: 5, vision: 1, canCounterattack: false)
        case Element.unitBlackBoat.value:
            .init(cost: 7_500, move: 6, minRange: 0, maxRange: 0, domain: .sea, canCapture: false, attackPower: 0, movementType: .ship, maxFuel: 60, dailyFuelUse: 1, vision: 1, canCounterattack: false)
        case Element.unitLander.value:
            .init(cost: 12_000, move: 6, minRange: 0, maxRange: 0, domain: .sea, canCapture: false, attackPower: 0, movementType: .lander, maxFuel: 99, dailyFuelUse: 1, vision: 1, canCounterattack: false)
        case Element.unitCruiser.value:
            .init(cost: 18_000, move: 6, minRange: 1, maxRange: 1, domain: .sea, canCapture: false, attackPower: 82, movementType: .ship, maxFuel: 99, dailyFuelUse: 1, vision: 3, primaryAmmo: 9)
        case Element.unitSub.value:
            .init(cost: 20_000, move: 5, minRange: 1, maxRange: 1, domain: .sea, canCapture: false, attackPower: 80, movementType: .ship, maxFuel: 60, dailyFuelUse: 1, vision: 5, primaryAmmo: 6)
        case Element.unitBattleship.value:
            .init(cost: 28_000, move: 5, minRange: 2, maxRange: 6, domain: .sea, canCapture: false, attackPower: 90, movementType: .ship, maxFuel: 99, dailyFuelUse: 1, vision: 2, primaryAmmo: 9, canMoveAndFire: false, canCounterattack: false)
        case Element.unitCarrier.value:
            .init(cost: 30_000, move: 5, minRange: 3, maxRange: 8, domain: .sea, canCapture: false, attackPower: 100, movementType: .ship, maxFuel: 99, dailyFuelUse: 1, vision: 4, primaryAmmo: 9, canMoveAndFire: false, canCounterattack: false)
        default:
            nil
        }
    }

    /// Dual Strike keeps clear-weather movement costs from the GBA games, but
    /// rain does not add movement points and snow only changes fuel use.
    static func movementCost(for unit: Element, terrain: Element) -> Int? {
        let tile = terrain.simplified
        guard !terrain.isExtra, tile != .terrainPipe, tile != .terrainSeam else {
            if unit.simplified == .unitPipeRunner {
                return tile == .terrainPipe || tile == .terrainSeam || tile == .buildingBase ? 1 : nil
            }
            return nil
        }

        guard let stats = stats(for: unit) else { return nil }
        if stats.domain == .air {
            return 1
        }

        if unit.simplified == .unitPipeRunner {
            return tile == .buildingBase ? 1 : nil
        }

        let isBridge = tile == .terrainBridgeH || tile == .terrainBridgeV
        if stats.domain == .sea {
            guard !isBridge else { return nil }
            switch tile {
            case .terrainSea, .buildingPort:
                return 1
            case .terrainReef:
                return 2
            case .terrainShoal:
                return unit.simplified == .unitLander || unit.simplified == .unitBlackBoat ? 1 : nil
            default:
                return nil
            }
        }

        if isBridge || terrain.isBuilding {
            return 1
        }

        guard !terrain.isSea else {
            return tile == .terrainShoal ? 1 : nil
        }

        switch stats.movementType {
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
