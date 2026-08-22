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
    case sandstorm
    case random

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .clear: "Clear"
        case .rain: "Rain"
        case .snow: "Snow"
        case .sandstorm: "Sandstorm"
        case .random: "Random"
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
    static func formatFunds(_ amount: Int) -> String {
        "\(amount.formatted()) G"
    }

    static func weatherOptions(for ruleset: PlaytestRuleset) -> [PlaytestWeather] {
        switch ruleset {
        case .dualStrike:
            return PlaytestDualStrikeRules.weatherOptions
        case .advanceWars:
            return PlaytestAdvanceWarsRules.weatherOptions
        case .advanceWars2:
            return PlaytestAdvanceWars2Rules.weatherOptions
        }
    }

    static func concreteWeatherOptions(for ruleset: PlaytestRuleset) -> [PlaytestWeather] {
        weatherOptions(for: ruleset).filter { $0 != .random }
    }

    static func randomWeather(for ruleset: PlaytestRuleset) -> PlaytestWeather {
        concreteWeatherOptions(for: ruleset).randomElement() ?? .clear
    }

    /// The map-art choice is also the starting weather for playtest. This
    /// keeps an AW1 snow map, AW2 rain map, or DS desert map visually and
    /// mechanically aligned as soon as the playtest opens. Wasteland is a
    /// Dual Strike art-only palette, so it starts in clear weather.
    static func initialWeather(for variant: MapVisualVariant, ruleset: PlaytestRuleset) -> PlaytestWeather {
        let requested: PlaytestWeather
        switch variant {
        case .famicomWars, .gbWars, .dualStrikeNormal, .dualStrikeWasteland, .aw1Clear, .aw2Clear:
            requested = .clear
        case .dualStrikeSnow, .aw1Snow, .aw2Snow:
            requested = .snow
        case .dualStrikeDesert:
            requested = .sandstorm
        case .aw2Rain:
            requested = .rain
        }

        return weatherOptions(for: ruleset).contains(requested) ? requested : .clear
    }

    /// Returns the persisted/base art tileset used by the playtest map
    /// snapshot. Weather-specific GBA art is selected separately through
    /// `visualPalette` so it never leaks into map serialization.
    static func visualTileset(for ruleset: PlaytestRuleset, weather: PlaytestWeather) -> Tileset {
        switch ruleset {
        case .dualStrike:
            switch weather {
            case .snow:
                return .snow
            case .sandstorm:
                return .desert
            case .clear, .rain, .random:
                return .normal
            }
        case .advanceWars:
            return .aw1
        case .advanceWars2:
            return .aw2
        }
    }

    /// Render-only palette for weather art. The AW1 and AW2 terrain geometry
    /// is shared by the GBA cartridges, while their building/unit sheets stay
    /// game-specific through the base tileset.
    static func visualPalette(for ruleset: PlaytestRuleset, weather: PlaytestWeather) -> SpritePalette {
        switch ruleset {
        case .dualStrike:
            return .tileset(visualTileset(for: ruleset, weather: weather))
        case .advanceWars:
            switch weather {
            case .snow: return .gbaSnow(base: .aw1)
            case .clear, .rain, .sandstorm, .random: return .tileset(.aw1)
            }
        case .advanceWars2:
            switch weather {
            case .rain: return .gbaRain(base: .aw2)
            case .snow: return .gbaSnow(base: .aw2)
            case .clear, .sandstorm, .random: return .tileset(.aw2)
            }
        }
    }

    static func fogOfWarIsActive(
        ruleset: PlaytestRuleset,
        manualFogEnabled: Bool,
        weather: PlaytestWeather
    ) -> Bool {
        if ruleset == .dualStrike {
            return PlaytestDualStrikeRules.fogOfWarIsActive(
                manualFogEnabled: manualFogEnabled,
                weather: weather
            )
        }
        return manualFogEnabled
    }

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
        case .unitCruiser, .unitBlackBoat, .unitCarrier: return 2
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
              cargo.army == transport.army else { return false }

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
        case .unitCruiser:
            return cargo.simplified == .unitBCopter || cargo.simplified == .unitTCopter
        case .unitBlackBoat:
            return cargo.simplified == .unitInfantry || cargo.simplified == .unitMech
        case .unitCarrier:
            return cargoStats.domain == .air
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

    static func productionOptions(
        for building: Element,
        ruleset: PlaytestRuleset,
        tileset: Tileset? = nil
    ) -> [PlaytestProductionOption] {
        let elements: [Element]
        let famicomRoster = tileset == .famicomWars && ruleset == .advanceWars
        let gbWarsRoster = tileset == .gbWars && ruleset == .advanceWars
        if famicomRoster {
            switch building.simplified {
            case .buildingBase:
                elements = PlaytestAdvanceWarsRules.famicomWarsLandUnits
            case .buildingAirport:
                elements = PlaytestAdvanceWarsRules.famicomWarsAirUnits
            case .buildingPort:
                elements = PlaytestAdvanceWarsRules.famicomWarsSeaUnits
            default:
                return []
            }
        } else if gbWarsRoster {
            switch building.simplified {
            case .buildingBase:
                elements = PlaytestAdvanceWarsRules.gbWarsLandUnits
            case .buildingAirport:
                elements = PlaytestAdvanceWarsRules.gbWarsAirUnits
            case .buildingPort:
                elements = PlaytestAdvanceWarsRules.gbWarsSeaUnits
            default:
                return []
            }
        } else {
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
        }
        return elements.compactMap { element in
            guard let stats = stats(for: element, ruleset: ruleset) else { return nil }
            let label: String
            if famicomRoster {
                label = PlaytestAdvanceWarsRules.famicomWarsProductionLabel(for: element)
            } else {
                label = PaletteCatalog.label(for: element, tileset: gbWarsRoster ? .gbWars : nil)
            }
            return PlaytestProductionOption(element: element, label: label, cost: stats.cost)
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
        case .unitTCopter, .unitLander:
            return false
        case .unitBCopter, .unitBomber:
            return targetDomain != .air
        case .unitFighter, .unitStealth:
            return true
        case .unitBlackBomb:
            return targetDomain != .air
        case .unitBlackBoat:
            return false
        case .unitBattleship:
            return targetDomain != .air
        case .unitCarrier:
            return targetDomain == .air
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
        if ruleset == .dualStrike {
            return PlaytestDualStrikeRules.movementCost(for: unit, terrain: terrain)
        }
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

    /// Snow in Dual Strike leaves movement points unchanged but doubles the
    /// fuel/rations charged for every movement point. The GBA rules keep the
    /// normal one-fuel-per-point cost in every weather condition.
    static func movementFuelCost(
        for unit: Element,
        movement: Int,
        ruleset: PlaytestRuleset,
        weather: PlaytestWeather
    ) -> Int {
        if ruleset == .dualStrike {
            return PlaytestDualStrikeRules.movementFuelCost(
                for: unit,
                movement: movement,
                weather: weather
            )
        }
        return movement
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
        case .unitCarrier:
            multiplier = defenderStats.domain == .air ? 100 : 0
        default:
            multiplier = defenderStats.domain == .land ? 78 : 42
        }
        // Dual Strike stores health as a percentage internally. A unit at
        // 10 HP (100) deals full damage, while 9 HP (90) deals 90%, and so
        // on down to 1 HP (10).
        let healthScale = Double(max(1, min(100, attackerHealth))) / 100
        let rawDamage = Double(attackerStats.attackPower * multiplier) / 100 * healthScale
        return max(1, min(100, Int(rawDamage.rounded(.down))))
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
        if (ruleset == .advanceWars2 || ruleset == .dualStrike), building.simplified == .buildingSilo {
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
