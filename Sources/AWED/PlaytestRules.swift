import AWEDCore

enum PlaytestUnitDomain {
    case land
    case air
    case sea
}

enum PlaytestMovementType: Equatable {
    case foot
    case mech
    case tire
    case tread
    case air
    case ship
    case lander
}

enum PlaytestWeather: String, CaseIterable, Identifiable, Sendable {
    case clear
    case rain
    case snow

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .clear: "Clear"
        case .rain: "Rain"
        case .snow: "Snow"
        }
    }
}

struct PlaytestUnitStats {
    let cost: Int
    let move: Int
    let minRange: Int
    let maxRange: Int
    let domain: PlaytestUnitDomain
    let canCapture: Bool
    let attackPower: Int
    let movementType: PlaytestMovementType
    let maxFuel: Int
    let dailyFuelUse: Int
    let vision: Int
    /// A nil value means the primary weapon has unlimited ammunition (or the
    /// unit has no weapon when attackPower is zero).
    let primaryAmmo: Int?
    let secondaryAttackPower: Int?
    let canMoveAndFire: Bool
    let canCounterattack: Bool

    init(
        cost: Int,
        move: Int,
        minRange: Int,
        maxRange: Int,
        domain: PlaytestUnitDomain,
        canCapture: Bool,
        attackPower: Int,
        movementType: PlaytestMovementType = .tread,
        maxFuel: Int = 100,
        dailyFuelUse: Int = 0,
        vision: Int = 1,
        primaryAmmo: Int? = nil,
        secondaryAttackPower: Int? = nil,
        canMoveAndFire: Bool = true,
        canCounterattack: Bool = true
    ) {
        self.cost = cost
        self.move = move
        self.minRange = minRange
        self.maxRange = maxRange
        self.domain = domain
        self.canCapture = canCapture
        self.attackPower = attackPower
        self.movementType = movementType
        self.maxFuel = maxFuel
        self.dailyFuelUse = dailyFuelUse
        self.vision = vision
        self.primaryAmmo = primaryAmmo
        self.secondaryAttackPower = secondaryAttackPower
        self.canMoveAndFire = canMoveAndFire
        self.canCounterattack = canCounterattack
    }
}

struct PlaytestProductionOption: Identifiable {
    let element: Element
    let label: String
    let cost: Int

    var id: Int { element.simplified.value }
}

/// Shared rules for the editor's local playtest. Cartridge-specific rosters
/// and tables live in the dedicated Dual Strike, AW1, and AW2 rule files so
/// each game can evolve without making this dispatch layer harder to maintain.
enum PlaytestRulebook {
    static func resourceLabel(for element: Element) -> String {
        switch element.simplified {
        case .unitInfantry, .unitMech:
            return "Rations"
        default:
            return "Fuel"
        }
    }

    static func canCrossRiver(_ element: Element) -> Bool {
        element.simplified == .unitInfantry || element.simplified == .unitMech
    }

    static func transportCapacity(for element: Element) -> Int {
        switch element.simplified {
        case .unitAPC: return 1
        case .unitLander: return 2
        case .unitTCopter: return 1
        case .unitCruiser: return 2
        default: return 0
        }
    }

    static func canTransport(_ transport: Element, cargo: Element, ruleset: PlaytestRuleset) -> Bool {
        if ruleset == .advanceWars2 {
            return PlaytestAdvanceWars2Rules.canTransport(transport, cargo: cargo)
        }
        if ruleset == .advanceWars {
            return PlaytestAdvanceWarsRules.canTransport(transport, cargo: cargo)
        }

        guard transportCapacity(for: transport) > 0,
              let cargoStats = stats(for: cargo, ruleset: ruleset),
              cargo.army == transport.army,
              cargo.simplified != .unitAPC,
              cargo.simplified != .unitLander,
              cargo.simplified != .unitTCopter else { return false }

        switch transport.simplified {
        case .unitAPC:
            // Dual Strike's APC is an Infantry/Mech carrier. It can supply
            // every unit class, but only foot units occupy its single cargo
            // space.
            return cargo.simplified == .unitInfantry || cargo.simplified == .unitMech
        case .unitLander:
            return cargoStats.domain == .land
        case .unitTCopter:
            return cargo.simplified == .unitInfantry || cargo.simplified == .unitMech
        default:
            return false
        }
    }

    static func stats(for element: Element, ruleset: PlaytestRuleset) -> PlaytestUnitStats? {
        if ruleset == .advanceWars2 {
            return PlaytestAdvanceWars2Rules.stats(for: element)
        }
        if ruleset == .advanceWars {
            return PlaytestAdvanceWarsRules.stats(for: element)
        }
        guard isSupported(element, ruleset: ruleset) else { return nil }

        if ruleset == .dualStrike {
            return PlaytestDualStrikeRules.stats(for: element)
        }

        return nil
    }

    static func productionOptions(for building: Element, ruleset: PlaytestRuleset) -> [PlaytestProductionOption] {
        let elements: [Element]
        switch building.simplified {
        case .buildingBase:
            elements = landUnits(for: ruleset)
        case .buildingAirport:
            elements = airUnits(for: ruleset)
        case .buildingPort:
            elements = seaUnits(for: ruleset)
        default:
            return []
        }
        return elements.compactMap { element in
            guard let stats = stats(for: element, ruleset: ruleset) else { return nil }
            return PlaytestProductionOption(element: element, label: PaletteCatalog.label(for: element), cost: stats.cost)
        }
    }

    static func income(for building: Element) -> Int {
        switch building.simplified {
        case .buildingCity, .buildingBase, .buildingAirport, .buildingPort, .buildingHQ:
            return 1_000
        default:
            return 0
        }
    }

    static func canAttack(_ attacker: Element, _ defender: Element, ruleset: PlaytestRuleset, primaryAmmo: Int? = nil) -> Bool {
        if ruleset == .advanceWars2 {
            guard let stats = PlaytestAdvanceWars2Rules.stats(for: attacker),
                  stats.attackPower > 0,
                  PlaytestAdvanceWars2Rules.canAttack(attacker, defender, primaryAmmo: primaryAmmo) else { return false }
            return true
        }
        if ruleset == .advanceWars {
            guard let stats = PlaytestAdvanceWarsRules.stats(for: attacker),
                  stats.attackPower > 0,
                  PlaytestAdvanceWarsRules.canAttack(attacker, defender, primaryAmmo: primaryAmmo) else { return false }
            return true
        }

        guard let attackerStats = stats(for: attacker, ruleset: ruleset),
              let defenderStats = stats(for: defender, ruleset: ruleset),
              attackerStats.attackPower > 0 else { return false }

        let targetDomain = defenderStats.domain
        switch attacker.simplified {
        case .unitInfantry, .unitMech, .unitRecon, .unitTank, .unitMDTank, .unitNeoTank,
             .unitMegaTank, .unitOozium, .unitAPC, .unitPipeRunner:
            return targetDomain == .land
        case .unitArtillery, .unitRocket, .unitMissile:
            return targetDomain != .air
        case .unitAntiAir:
            return targetDomain == .air || targetDomain == .land
        case .unitTCopter, .unitLander, .unitCarrier:
            return false
        case .unitBCopter, .unitBomber:
            return targetDomain != .air
        case .unitFighter, .unitStealth:
            return true
        case .unitBlackBomb:
            return targetDomain != .air
        case .unitBlackBoat, .unitBattleship:
            return targetDomain != .air
        case .unitCruiser:
            return targetDomain == .air || targetDomain == .sea
        case .unitSub:
            return targetDomain == .sea
        default:
            return false
        }
    }

    static func usesPrimaryWeapon(_ attacker: Element, _ defender: Element, ruleset: PlaytestRuleset, primaryAmmo: Int? = nil) -> Bool {
        if ruleset == .advanceWars2 {
            return PlaytestAdvanceWars2Rules.usesPrimaryWeapon(attacker, defender, primaryAmmo: primaryAmmo)
        }
        if ruleset == .advanceWars {
            return PlaytestAdvanceWarsRules.usesPrimaryWeapon(attacker, defender, primaryAmmo: primaryAmmo)
        }
        guard let capacity = stats(for: attacker, ruleset: ruleset)?.primaryAmmo else { return false }
        return (primaryAmmo ?? capacity) > 0
    }

    /// Returns the movement points consumed by a unit entering a tile. The
    /// terrain table is deliberately expressed in terms of unit movement
    /// types instead of broad land/air/sea domains: Dual Strike distinguishes
    /// foot, tires, treads, Piperunners, and naval ships on Woods, Mountains,
    /// Rivers, and Reefs.
    static func movementCost(for unit: Element, stats: PlaytestUnitStats, terrain: Element, ruleset: PlaytestRuleset = .dualStrike, weather: PlaytestWeather = .clear) -> Int? {
        if ruleset == .advanceWars2 {
            return PlaytestAdvanceWars2Rules.movementCost(for: unit, terrain: terrain, weather: weather)
        }
        if ruleset == .advanceWars {
            return PlaytestAdvanceWarsRules.movementCost(for: unit, terrain: terrain, weather: weather)
        }

        let tile = terrain.simplified

        if stats.domain == .air {
            return 1
        }

        let isBridge = tile == .terrainBridgeH
        let isPort = tile == .buildingPort

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

        if unit.simplified == .unitPipeRunner {
            return tile == .terrainPipe || tile == .terrainSeam || tile == .buildingBase ? 1 : nil
        }

        // Bridges and properties use the normal land cost. A port is also a
        // valid one-point docking tile for eligible naval units above.
        if isBridge || isPort || terrain.isBuilding {
            return 1
        }

        // Land units cannot enter open water or reefs. Shoals are the one
        // coastal terrain every legal ground movement type can cross.
        guard !terrain.isSea else {
            return tile == .terrainShoal ? 1 : nil
        }

        switch unit.simplified {
        case .unitInfantry:
            return tile == .terrainMountain || tile == .terrainRiver ? 2 : 1
        case .unitMech, .unitOozium:
            return 1
        case .unitRecon, .unitArtillery, .unitRocket, .unitAntiAir, .unitMissile:
            switch tile {
            case .terrainPlain, .terrainPlainD: return 2
            case .terrainWood: return 3
            case .terrainMountain, .terrainRiver: return nil
            default: return 1
            }
        case .unitAPC, .unitTank, .unitMDTank, .unitNeoTank, .unitMegaTank:
            switch tile {
            case .terrainWood: return 2
            case .terrainMountain, .terrainRiver: return nil
            default: return 1
            }
        default:
            return 1
        }
    }

    static func damage(
        attacker: Element,
        defender: Element,
        ruleset: PlaytestRuleset,
        attackerHealth: Int = 100,
        defenderHealth: Int = 100,
        terrain: Element = .terrainPlain,
        primaryAmmo: Int? = nil
    ) -> Int? {
        if ruleset == .advanceWars2 {
            return PlaytestAdvanceWars2Rules.damage(
                attacker: attacker,
                defender: defender,
                attackerHealth: attackerHealth,
                defenderHealth: defenderHealth,
                terrain: terrain,
                primaryAmmo: primaryAmmo
            )
        }
        if ruleset == .advanceWars {
            return PlaytestAdvanceWarsRules.damage(
                attacker: attacker,
                defender: defender,
                attackerHealth: attackerHealth,
                defenderHealth: defenderHealth,
                terrain: terrain,
                primaryAmmo: primaryAmmo
            )
        }

        guard canAttack(attacker, defender, ruleset: ruleset),
              let attackerStats = stats(for: attacker, ruleset: ruleset),
              let defenderStats = stats(for: defender, ruleset: ruleset) else { return nil }

        let attackerType = attacker.simplified
        let defenderType = defender.simplified
        let multiplier: Int
        switch attackerType {
        case .unitAntiAir:
            multiplier = defenderStats.domain == .air ? 100 : 45
        case .unitMissile:
            multiplier = defenderStats.domain == .air ? 100 : 35
        case .unitFighter:
            multiplier = defenderStats.domain == .air ? 100 : 45
        case .unitBomber:
            multiplier = defenderStats.domain == .land ? 100 : 60
        case .unitCruiser:
            multiplier = defenderStats.domain == .air ? 80 : 70
        case .unitSub:
            multiplier = defenderType == .unitBattleship || defenderType == .unitCarrier ? 95 : 70
        case .unitBattleship:
            multiplier = defenderStats.domain == .land ? 85 : 65
        case .unitArtillery, .unitRocket, .unitPipeRunner:
            multiplier = defenderStats.domain == .land ? 78 : 55
        case .unitBlackBoat:
            multiplier = defenderStats.domain == .land ? 70 : 50
        default:
            multiplier = defenderStats.domain == .land ? 78 : 42
        }
        return max(1, min(100, attackerStats.attackPower * multiplier / 100))
    }

    static func terrainStars(for terrain: Element, ruleset: PlaytestRuleset) -> Int {
        if ruleset == .advanceWars2 {
            return PlaytestAdvanceWars2Rules.terrainStars(for: terrain)
        }
        if ruleset == .advanceWars {
            return PlaytestAdvanceWarsRules.terrainStars(for: terrain)
        }
        switch terrain.simplified {
        case .terrainPlain, .terrainPlainD, .terrainReef: return 1
        case .terrainWood: return 2
        case .buildingCity, .buildingBase, .buildingAirport, .buildingPort, .buildingTower, .buildingLab, .buildingSilo: return 3
        case .terrainMountain, .buildingHQ: return 4
        default: return 0
        }
    }

    static func maxFuel(for element: Element, ruleset: PlaytestRuleset) -> Int {
        stats(for: element, ruleset: ruleset)?.maxFuel ?? 100
    }

    static func dailyFuelUse(for element: Element, ruleset: PlaytestRuleset) -> Int {
        stats(for: element, ruleset: ruleset)?.dailyFuelUse ?? 0
    }

    static func primaryAmmo(for element: Element, ruleset: PlaytestRuleset) -> Int? {
        stats(for: element, ruleset: ruleset)?.primaryAmmo
    }

    static func isCapturableBuilding(_ building: Element, ruleset: PlaytestRuleset) -> Bool {
        guard building.isBuilding else { return false }
        if ruleset == .advanceWars2, building.simplified == .buildingSilo {
            return false
        }
        if ruleset == .advanceWars,
           [.buildingSilo, .buildingLab, .buildingTower].contains(building.simplified) {
            return false
        }
        return true
    }

    private static func isSupported(_ element: Element, ruleset: PlaytestRuleset) -> Bool {
        switch ruleset {
        case .dualStrike:
            return PlaytestDualStrikeRules.stats(for: element) != nil
        case .advanceWars:
            return PlaytestAdvanceWarsRules.stats(for: element) != nil
        case .advanceWars2:
            return PlaytestAdvanceWars2Rules.stats(for: element) != nil
        }
    }

    private static func landUnits(for ruleset: PlaytestRuleset) -> [Element] {
        if ruleset == .dualStrike {
            return PlaytestDualStrikeRules.landUnits
        }

        if ruleset == .advanceWars2 {
            return PlaytestAdvanceWars2Rules.landUnits
        }
        if ruleset == .advanceWars {
            return PlaytestAdvanceWarsRules.landUnits
        }
        return []
    }

    private static func airUnits(for ruleset: PlaytestRuleset) -> [Element] {
        if ruleset == .dualStrike {
            return PlaytestDualStrikeRules.airUnits
        }
        if ruleset == .advanceWars2 {
            return PlaytestAdvanceWars2Rules.airUnits
        }
        if ruleset == .advanceWars {
            return PlaytestAdvanceWarsRules.airUnits
        }
        return []
    }

    private static func seaUnits(for ruleset: PlaytestRuleset) -> [Element] {
        if ruleset == .dualStrike {
            return PlaytestDualStrikeRules.seaUnits
        }
        if ruleset == .advanceWars2 {
            return PlaytestAdvanceWars2Rules.seaUnits
        }
        if ruleset == .advanceWars {
            return PlaytestAdvanceWarsRules.seaUnits
        }
        return []
    }
}
