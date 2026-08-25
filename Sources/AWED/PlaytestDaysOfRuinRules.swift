import AWEDCore

/// CO-less Days of Ruin / Dark Conflict mechanics. DoR's compact map-unit
/// atlas maps its unique roster into the stable editor slots documented below.
enum PlaytestDaysOfRuinRules {
    static let weatherOptions: [PlaytestWeather] = [.random, .clear, .rain, .snow, .sandstorm]

    static let landUnits: [Element] = [
        .unitInfantry, .unitMech, .unitPipeRunner, .unitRecon, .unitOozium,
        .unitAntiAir, .unitTank, .unitMDTank, .unitMegaTank, .unitArtillery,
        .unitNeoTank, .unitRocket, .unitMissile, .unitAPC
    ]
    static let airUnits: [Element] = [
        .unitFighter, .unitBomber, .unitStealth, .unitBCopter, .unitTCopter
    ]
    static let seaUnits: [Element] = [
        .unitBlackBoat, .unitCruiser, .unitSub, .unitCarrier, .unitBattleship, .unitLander
    ]

    static func fogOfWarIsActive(manualFogEnabled: Bool, weather: PlaytestWeather) -> Bool {
        manualFogEnabled || weather == .rain
    }

    static func maximumAttackRange(for stats: PlaytestUnitStats, weather: PlaytestWeather) -> Int {
        guard weather == .sandstorm, stats.maxRange > stats.minRange else { return stats.maxRange }
        return max(stats.minRange, stats.maxRange - 1)
    }

    static func stats(for element: Element) -> PlaytestUnitStats? {
        switch element.simplified {
        case .unitInfantry:
            .init(cost: 1_500, move: 3, minRange: 1, maxRange: 1, domain: .land, canCapture: true, attackPower: 55, movementType: .foot, maxFuel: 99, vision: 2)
        case .unitMech:
            .init(cost: 2_500, move: 2, minRange: 1, maxRange: 1, domain: .land, canCapture: true, attackPower: 80, movementType: .mech, maxFuel: 70, vision: 2, primaryAmmo: 3)
        case .unitPipeRunner: // Bike
            .init(cost: 2_500, move: 5, minRange: 1, maxRange: 1, domain: .land, canCapture: true, attackPower: 60, movementType: .tire, maxFuel: 70, vision: 2)
        case .unitRecon:
            .init(cost: 4_000, move: 8, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 65, movementType: .tire, maxFuel: 80, vision: 5)
        case .unitOozium: // Flare
            .init(cost: 5_000, move: 5, minRange: 0, maxRange: 0, domain: .land, canCapture: false, attackPower: 0, movementType: .tread, maxFuel: 60, vision: 2, primaryAmmo: 3, canCounterattack: false)
        case .unitAntiAir:
            .init(cost: 7_000, move: 6, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 95, movementType: .tread, maxFuel: 60, vision: 3, primaryAmmo: 9)
        case .unitTank:
            .init(cost: 7_000, move: 6, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 75, movementType: .tread, maxFuel: 70, vision: 3, primaryAmmo: 6)
        case .unitMDTank:
            .init(cost: 12_000, move: 5, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 100, movementType: .tread, maxFuel: 50, vision: 2, primaryAmmo: 5)
        case .unitMegaTank: // War Tank
            .init(cost: 16_000, move: 4, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 120, movementType: .tread, maxFuel: 50, vision: 2, primaryAmmo: 5)
        case .unitArtillery:
            .init(cost: 6_000, move: 5, minRange: 2, maxRange: 3, domain: .land, canCapture: false, attackPower: 85, movementType: .tread, maxFuel: 50, vision: 3, primaryAmmo: 6, canMoveAndFire: false, canCounterattack: false)
        case .unitNeoTank: // Anti-Tank: indirect, but can counter adjacent attacks.
            .init(cost: 11_000, move: 4, minRange: 1, maxRange: 3, domain: .land, canCapture: false, attackPower: 105, movementType: .tread, maxFuel: 50, vision: 2, primaryAmmo: 6, canMoveAndFire: false)
        case .unitRocket:
            .init(cost: 15_000, move: 5, minRange: 3, maxRange: 5, domain: .land, canCapture: false, attackPower: 95, movementType: .tire, maxFuel: 50, vision: 3, primaryAmmo: 6, canMoveAndFire: false, canCounterattack: false)
        case .unitMissile:
            .init(cost: 12_000, move: 4, minRange: 3, maxRange: 6, domain: .land, canCapture: false, attackPower: 100, movementType: .tire, maxFuel: 50, vision: 5, primaryAmmo: 6, canMoveAndFire: false, canCounterattack: false)
        case .unitAPC: // Rig
            .init(cost: 5_000, move: 6, minRange: 0, maxRange: 0, domain: .land, canCapture: false, attackPower: 0, movementType: .tread, maxFuel: 99, vision: 2, canCounterattack: false)
        case .unitFighter:
            .init(cost: 20_000, move: 9, minRange: 1, maxRange: 1, domain: .air, canCapture: false, attackPower: 100, movementType: .air, maxFuel: 99, dailyFuelUse: 5, vision: 5, primaryAmmo: 6)
        case .unitBomber:
            .init(cost: 20_000, move: 7, minRange: 1, maxRange: 1, domain: .air, canCapture: false, attackPower: 110, movementType: .air, maxFuel: 99, dailyFuelUse: 5, vision: 3, primaryAmmo: 6)
        case .unitStealth: // Duster
            .init(cost: 13_000, move: 8, minRange: 1, maxRange: 1, domain: .air, canCapture: false, attackPower: 80, movementType: .air, maxFuel: 99, dailyFuelUse: 5, vision: 4, primaryAmmo: 6)
        case .unitBCopter:
            .init(cost: 9_000, move: 6, minRange: 1, maxRange: 1, domain: .air, canCapture: false, attackPower: 75, movementType: .air, maxFuel: 99, dailyFuelUse: 2, vision: 3, primaryAmmo: 6)
        case .unitTCopter:
            .init(cost: 5_000, move: 6, minRange: 0, maxRange: 0, domain: .air, canCapture: false, attackPower: 0, movementType: .air, maxFuel: 99, dailyFuelUse: 2, vision: 2, canCounterattack: false)
        case .unitBlackBoat: // Gunboat
            .init(cost: 6_000, move: 7, minRange: 1, maxRange: 1, domain: .sea, canCapture: false, attackPower: 75, movementType: .ship, maxFuel: 99, dailyFuelUse: 1, vision: 2, primaryAmmo: 1)
        case .unitCruiser:
            .init(cost: 16_000, move: 6, minRange: 1, maxRange: 1, domain: .sea, canCapture: false, attackPower: 100, movementType: .ship, maxFuel: 99, dailyFuelUse: 1, vision: 5, primaryAmmo: 6)
        case .unitSub:
            .init(cost: 18_000, move: 5, minRange: 1, maxRange: 1, domain: .sea, canCapture: false, attackPower: 100, movementType: .ship, maxFuel: 70, dailyFuelUse: 1, vision: 5, primaryAmmo: 6)
        case .unitCarrier:
            .init(cost: 28_000, move: 5, minRange: 0, maxRange: 0, domain: .sea, canCapture: false, attackPower: 0, movementType: .ship, maxFuel: 99, dailyFuelUse: 1, vision: 4, canCounterattack: false)
        case .unitBattleship:
            .init(cost: 25_000, move: 5, minRange: 3, maxRange: 5, domain: .sea, canCapture: false, attackPower: 95, movementType: .ship, maxFuel: 99, dailyFuelUse: 1, vision: 3, primaryAmmo: 6, canMoveAndFire: true, canCounterattack: false)
        case .unitLander:
            .init(cost: 10_000, move: 6, minRange: 0, maxRange: 0, domain: .sea, canCapture: false, attackPower: 0, movementType: .lander, maxFuel: 99, dailyFuelUse: 1, vision: 2, canCounterattack: false)
        default:
            nil
        }
    }

    static func movementCost(for unit: Element, terrain: Element, weather: PlaytestWeather) -> Int? {
        guard stats(for: unit) != nil else { return nil }
        return PlaytestAdvanceWars2Rules.movementCost(for: unit, terrain: terrain, weather: weather)
    }

    static func canTransport(_ transport: Element, cargo: Element) -> Bool {
        guard transport.army == cargo.army, let cargoStats = stats(for: cargo) else { return false }
        switch transport.simplified {
        case .unitAPC:
            return [.unitInfantry, .unitMech, .unitPipeRunner].contains(cargo.simplified)
        case .unitTCopter:
            return cargo.simplified == .unitInfantry || cargo.simplified == .unitMech
        case .unitBlackBoat:
            return cargo.simplified == .unitInfantry || cargo.simplified == .unitMech
        case .unitLander:
            return cargoStats.domain == .land
        case .unitCruiser:
            return cargo.simplified == .unitBCopter || cargo.simplified == .unitTCopter
        case .unitCarrier:
            return cargoStats.domain == .air
        default:
            return false
        }
    }
}
