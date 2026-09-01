import AWEDCore

/// Famicom Wars' sixteen-unit, clear-weather ruleset.
///
/// Shared `Element` slots stand in for the cartridge names used by the atlas:
/// Rocket is Howitzer, Recon is Supply Truck, B-Copter is Scout, and T-Copter
/// is Helicopter. Values below follow the original unit cost/move/fuel table.
enum PlaytestFamicomWarsRules {
    static let weatherOptions: [PlaytestWeather] = [.clear]
    static let supportsFogOfWar = false

    static let landUnits: [Element] = [
        .unitInfantry, .unitMech, .unitMDTank, .unitTank, .unitAPC,
        .unitRocket, .unitArtillery, .unitMissile, .unitAntiAir, .unitRecon
    ]
    static let airUnits: [Element] = [.unitFighter, .unitBCopter, .unitBomber, .unitTCopter]
    static let seaUnits: [Element] = [.unitBattleship, .unitLander]

    private static let statsByValue: [Int: PlaytestUnitStats] = makeStats()

    private static func makeStats() -> [Int: PlaytestUnitStats] {
        statsPart1().merging(statsPart2(), uniquingKeysWith: { _, new in new })
            .merging(statsPart3(), uniquingKeysWith: { _, new in new })
    }

    private static func statsPart1() -> [Int: PlaytestUnitStats] {
        [
        Element.unitInfantry.simplified.value: .init(cost: 1_000, move: 3, minRange: 1, maxRange: 1, domain: .land, canCapture: true, attackPower: 55, movementType: .foot, maxFuel: 99, vision: 2),
        Element.unitMech.simplified.value: .init(cost: 2_000, move: 2, minRange: 1, maxRange: 1, domain: .land, canCapture: true, attackPower: 70, movementType: .mech, maxFuel: 70, vision: 2, primaryAmmo: 3),
        Element.unitMDTank.simplified.value: .init(cost: 16_000, move: 6, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 105, movementType: .tread, maxFuel: 70, primaryAmmo: 6),
        Element.unitTank.simplified.value: .init(cost: 6_000, move: 5, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 75, movementType: .tread, maxFuel: 50, primaryAmmo: 4),
        Element.unitAPC.simplified.value: .init(cost: 4_200, move: 6, minRange: 0, maxRange: 0, domain: .land, canCapture: false, attackPower: 0, movementType: .tread, maxFuel: 70, canCounterattack: false)
        ]
    }

    private static func statsPart2() -> [Int: PlaytestUnitStats] {
        [
        Element.unitRocket.simplified.value: .init(cost: 13_000, move: 4, minRange: 3, maxRange: 5, domain: .land, canCapture: false, attackPower: 95, movementType: .tire, maxFuel: 50, primaryAmmo: 5, canMoveAndFire: false, canCounterattack: false),
        Element.unitArtillery.simplified.value: .init(cost: 5_500, move: 5, minRange: 2, maxRange: 3, domain: .land, canCapture: false, attackPower: 88, movementType: .tread, maxFuel: 30, primaryAmmo: 3, canMoveAndFire: false, canCounterattack: false),
        Element.unitMissile.simplified.value: .init(cost: 11_000, move: 4, minRange: 3, maxRange: 5, domain: .land, canCapture: false, attackPower: 100, movementType: .tire, maxFuel: 40, vision: 5, primaryAmmo: 2, canMoveAndFire: false, canCounterattack: false),
        Element.unitAntiAir.simplified.value: .init(cost: 5_500, move: 5, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 100, movementType: .tread, maxFuel: 50, vision: 2, primaryAmmo: 4),
        Element.unitRecon.simplified.value: .init(cost: 3_000, move: 5, minRange: 0, maxRange: 0, domain: .land, canCapture: false, attackPower: 0, movementType: .tire, maxFuel: 60, vision: 3, canCounterattack: false)
        ]
    }

    private static func statsPart3() -> [Int: PlaytestUnitStats] {
        [
        Element.unitFighter.simplified.value: .init(cost: 22_000, move: 10, minRange: 1, maxRange: 1, domain: .air, canCapture: false, attackPower: 100, movementType: .air, maxFuel: 99, dailyFuelUse: 5, vision: 2, primaryAmmo: 5),
        Element.unitBCopter.simplified.value: .init(cost: 15_000, move: 10, minRange: 1, maxRange: 1, domain: .air, canCapture: false, attackPower: 75, movementType: .air, maxFuel: 99, dailyFuelUse: 4, vision: 3, primaryAmmo: 4),
        Element.unitBomber.simplified.value: .init(cost: 20_000, move: 8, minRange: 1, maxRange: 1, domain: .air, canCapture: false, attackPower: 110, movementType: .air, maxFuel: 99, dailyFuelUse: 5, vision: 2, primaryAmmo: 6),
        Element.unitTCopter.simplified.value: .init(cost: 4_000, move: 6, minRange: 0, maxRange: 0, domain: .air, canCapture: false, attackPower: 0, movementType: .air, maxFuel: 60, dailyFuelUse: 2, vision: 2, canCounterattack: false),
        Element.unitBattleship.simplified.value: .init(cost: 28_800, move: 6, minRange: 3, maxRange: 5, domain: .sea, canCapture: false, attackPower: 95, movementType: .ship, maxFuel: 99, dailyFuelUse: 1, vision: 2, primaryAmmo: 6, canMoveAndFire: false, canCounterattack: false),
        Element.unitLander.simplified.value: .init(cost: 18_500, move: 5, minRange: 0, maxRange: 0, domain: .sea, canCapture: false, attackPower: 0, movementType: .lander, maxFuel: 99, dailyFuelUse: 1, vision: 1, canCounterattack: false)
        ]
    }

    static func stats(for element: Element) -> PlaytestUnitStats? {
        statsByValue[element.simplified.value]
    }

    static func movementCost(for unit: Element, terrain: Element) -> Int? {
        guard let stats = stats(for: unit), !terrain.isExtra else { return nil }
        let tile = terrain.simplified
        if stats.domain == .air { return 1 }
        if stats.domain == .sea { return seaMovementCost(tile) }
        if terrain.isBuilding || isRoadOrBridge(tile) { return 1 }
        return landMovementCost(stats.movementType, tile)
    }

    private static func seaMovementCost(_ tile: Element) -> Int? {
        switch tile {
        case .terrainSea, .terrainShoal, .buildingPort: return 1
        default: return nil
        }
    }

    private static func isRoadOrBridge(_ tile: Element) -> Bool {
        tile == .terrainRoad || tile == .terrainBridgeH || tile == .terrainBridgeV
    }

    private static func landMovementCost(_ movementType: PlaytestMovementType, _ tile: Element) -> Int? {
        switch movementType {
        case .foot, .mech:
            switch tile {
            case .terrainMountain, .terrainRiver: return 2
            case .terrainSea, .terrainReef: return nil
            default: return 1
            }
        case .tread:
            switch tile {
            case .terrainWood: return 2
            case .terrainRiver: return 6
            case .terrainMountain, .terrainSea, .terrainReef: return nil
            default: return 1
            }
        case .tire:
            switch tile {
            case .terrainWood: return 2
            case .terrainRiver: return 6
            case .terrainMountain, .terrainSea, .terrainReef: return nil
            default: return 1
            }
        case .air, .ship, .lander:
            return nil
        }
    }

    static func canTransport(_ transport: Element, cargo: Element) -> Bool {
        guard transport.army == cargo.army, stats(for: cargo) != nil else { return false }
        switch transport.simplified {
        case .unitAPC, .unitTCopter:
            return cargo.simplified == .unitInfantry || cargo.simplified == .unitMech
        case .unitLander:
            return stats(for: cargo)?.domain == .land
        default:
            return false
        }
    }
}
