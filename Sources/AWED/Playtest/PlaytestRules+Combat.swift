import AWEDCore

extension PlaytestRulebook {
    static func canAttack(_ attacker: Element, _ defender: Element, ruleset: PlaytestRuleset, primaryAmmo: Int? = nil) -> Bool {
        if ruleset == .advanceWars2 {
            return PlaytestAdvanceWars2Rules.canAttack(attacker, defender, primaryAmmo: primaryAmmo)
        }
        if ruleset == .advanceWars {
            return PlaytestAdvanceWarsRules.canAttack(attacker, defender, primaryAmmo: primaryAmmo)
        }

        guard let attackerStats = stats(for: attacker, ruleset: ruleset),
              let defenderStats = stats(for: defender, ruleset: ruleset),
              attackerStats.attackPower > 0,
              genericAmmoIsAvailable(attackerStats, primaryAmmo: primaryAmmo) else { return false }
        return ruleset == .daysOfRuin
            ? daysOfRuinCanAttack(attacker, targetDomain: defenderStats.domain)
            : classicCanAttack(attacker, targetDomain: defenderStats.domain)
    }

    private static func genericAmmoIsAvailable(_ stats: PlaytestUnitStats, primaryAmmo: Int?) -> Bool {
        guard let primaryAmmo, stats.primaryAmmo != nil, primaryAmmo <= 0 else { return true }
        return stats.secondaryAttackPower != nil
    }

    private static func daysOfRuinCanAttack(_ attacker: Element, targetDomain: PlaytestUnitDomain) -> Bool {
        switch attacker.simplified {
        case .unitInfantry, .unitMech, .unitPipeRunner, .unitRecon, .unitTank, .unitMDTank,
             .unitMegaTank, .unitArtillery, .unitNeoTank, .unitRocket:
            return targetDomain == .land || targetDomain == .sea
        case .unitAntiAir: return targetDomain == .air || targetDomain == .land
        case .unitMissile, .unitFighter: return targetDomain == .air
        case .unitBomber: return targetDomain != .air
        case .unitStealth, .unitBCopter: return targetDomain == .air || targetDomain == .land
        case .unitBlackBoat: return targetDomain == .sea || targetDomain == .land
        case .unitCruiser: return targetDomain == .air || targetDomain == .sea
        case .unitSub: return targetDomain == .sea
        case .unitBattleship: return targetDomain != .air
        default: return false
        }
    }

    private static func classicCanAttack(_ attacker: Element, targetDomain: PlaytestUnitDomain) -> Bool {
        switch attacker.simplified {
        case .unitInfantry, .unitMech, .unitRecon, .unitTank, .unitMDTank, .unitNeoTank,
             .unitMegaTank, .unitOozium, .unitAPC, .unitPipeRunner:
            return targetDomain == .land
        case .unitArtillery, .unitRocket, .unitMissile, .unitBCopter, .unitBomber:
            return targetDomain != .air
        case .unitAntiAir: return targetDomain == .air || targetDomain == .land
        case .unitTCopter, .unitLander, .unitBlackBoat: return false
        case .unitFighter, .unitStealth: return true
        case .unitBlackBomb, .unitBattleship: return targetDomain != .air
        case .unitCarrier: return targetDomain == .air
        case .unitCruiser: return targetDomain == .air || targetDomain == .sea
        case .unitSub: return targetDomain == .sea
        default: return false
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
    static func movementCost(
        for unit: Element,
        stats: PlaytestUnitStats,
        terrain: Element,
        ruleset: PlaytestRuleset = .dualStrike,
        weather: PlaytestWeather = .clear,
        tileset: Tileset? = nil
    ) -> Int? {
        switch ruleset {
        case .dualStrike:
            return PlaytestDualStrikeRules.movementCost(for: unit, terrain: terrain)
        case .advanceWars2:
            return PlaytestAdvanceWars2Rules.movementCost(for: unit, terrain: terrain, weather: weather)
        case .advanceWars:
            return PlaytestAdvanceWarsRules.movementCost(for: unit, terrain: terrain, weather: weather)
        case .famicomWars:
            return PlaytestFamicomWarsRules.movementCost(for: unit, terrain: terrain)
        case .superFamicomWars:
            return PlaytestSuperFamicomWarsRules.movementCost(for: unit, terrain: terrain)
        case .gameBoyWars, .gameBoyWars2, .gameBoyWars3:
            return PlaytestGameBoyWarsRules.movementCost(for: unit, terrain: terrain, ruleset: ruleset)
        case .daysOfRuin:
            return PlaytestDaysOfRuinRules.movementCost(for: unit, terrain: terrain, weather: weather)
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

    static func maximumAttackRange(for stats: PlaytestUnitStats, ruleset: PlaytestRuleset, weather: PlaytestWeather) -> Int {
        switch ruleset {
        case .dualStrike:
            return PlaytestDualStrikeRules.maximumAttackRange(for: stats, weather: weather)
        case .daysOfRuin:
            return PlaytestDaysOfRuinRules.maximumAttackRange(for: stats, weather: weather)
        default:
            return stats.maxRange
        }
    }

    static func damage(
        attacker: Element,
        defender: Element,
        ruleset: PlaytestRuleset,
        attackerHealth: Int = 100,
        defenderHealth: Int = 100,
        terrain: Element = .terrainPlain,
        primaryAmmo: Int? = nil,
        randomize: Bool = true
    ) -> Int? {
        if ruleset == .advanceWars2 {
            return PlaytestAdvanceWars2Rules.damage(
                attacker: attacker,
                defender: defender,
                attackerHealth: attackerHealth,
                defenderHealth: defenderHealth,
                terrain: terrain,
                primaryAmmo: primaryAmmo,
                randomize: randomize
            )
        }
        if ruleset == .advanceWars {
            return PlaytestAdvanceWarsRules.damage(
                attacker: attacker,
                defender: defender,
                attackerHealth: attackerHealth,
                defenderHealth: defenderHealth,
                terrain: terrain,
                primaryAmmo: primaryAmmo,
                randomize: randomize
            )
        }

        guard canAttack(attacker, defender, ruleset: ruleset, primaryAmmo: primaryAmmo),
              let attackerStats = stats(for: attacker, ruleset: ruleset),
              let defenderStats = stats(for: defender, ruleset: ruleset) else { return nil }
        guard let baseAttackPower = baseAttackPower(
            attacker: attacker,
            defender: defender,
            ruleset: ruleset,
            stats: attackerStats,
            primaryAmmo: primaryAmmo
        ) else { return nil }
        let multiplier = damageMultiplier(
            for: attacker.simplified,
            defender: defender.simplified,
            defenderDomain: defenderStats.domain
        )
        // Dual Strike stores health as a percentage internally. A unit at
        // 10 HP (100) deals full damage, while 9 HP (90) deals 90%, and so
        // on down to 1 HP (10).
        return scaledDamage(baseAttackPower, multiplier: multiplier, attackerHealth: attackerHealth)
    }

    private static func baseAttackPower(
        attacker: Element,
        defender: Element,
        ruleset: PlaytestRuleset,
        stats: PlaytestUnitStats,
        primaryAmmo: Int?
    ) -> Int? {
        let useSecondary = stats.primaryAmmo != nil &&
            !usesPrimaryWeapon(attacker, defender, ruleset: ruleset, primaryAmmo: primaryAmmo)
        let power = useSecondary ? (stats.secondaryAttackPower ?? 0) : stats.attackPower
        return power > 0 ? power : nil
    }

    private static func scaledDamage(_ power: Int, multiplier: Int, attackerHealth: Int) -> Int {
        let healthScale = Double(max(1, min(100, attackerHealth))) / 100
        let rawDamage = Double(power * multiplier) / 100 * healthScale
        return max(1, min(100, Int(rawDamage.rounded(.down))))
    }

    private static func damageMultiplier(
        for attacker: Element,
        defender: Element,
        defenderDomain: PlaytestUnitDomain
    ) -> Int {
        switch attacker {
        case .unitAntiAir, .unitMissile, .unitFighter: return airDefenseMultiplier(attacker, domain: defenderDomain)
        case .unitBomber, .unitCruiser, .unitBattleship: return heavyUnitMultiplier(attacker, domain: defenderDomain)
        case .unitSub: return submarineMultiplier(defender)
        case .unitArtillery, .unitRocket, .unitPipeRunner: return defenderDomain == .land ? 78 : 55
        case .unitBlackBoat: return defenderDomain == .land ? 70 : 50
        case .unitCarrier: return defenderDomain == .air ? 100 : 0
        default: return defenderDomain == .land ? 78 : 42
        }
    }

    private static func airDefenseMultiplier(_ attacker: Element, domain: PlaytestUnitDomain) -> Int {
        switch attacker {
        case .unitMissile: return domain == .air ? 100 : 35
        case .unitFighter: return domain == .air ? 100 : 45
        default: return domain == .air ? 100 : 45
        }
    }

    private static func heavyUnitMultiplier(_ attacker: Element, domain: PlaytestUnitDomain) -> Int {
        switch attacker {
        case .unitBomber: return domain == .land ? 100 : 60
        case .unitCruiser: return domain == .air ? 80 : 70
        default: return domain == .land ? 85 : 65
        }
    }

    private static func submarineMultiplier(_ defender: Element) -> Int {
        defender == .unitBattleship || defender == .unitCarrier ? 95 : 70
    }

    static func terrainStars(for terrain: Element, ruleset: PlaytestRuleset) -> Int {
        switch ruleset {
        case .advanceWars2: return PlaytestAdvanceWars2Rules.terrainStars(for: terrain)
        case .advanceWars: return PlaytestAdvanceWarsRules.terrainStars(for: terrain)
        case .daysOfRuin: return daysOfRuinTerrainStars(terrain)
        case .famicomWars, .superFamicomWars, .gameBoyWars, .gameBoyWars2, .gameBoyWars3:
            return classicTerrainStars(terrain)
        case .dualStrike: return dualStrikeTerrainStars(terrain)
        }
    }

    private static func classicTerrainStars(_ terrain: Element) -> Int {
        switch terrain.simplified {
        case .terrainPlain, .terrainPlainD, .terrainReef: return 1
        case .terrainWood: return 2
        case .buildingCity, .buildingBase, .buildingAirport, .buildingPort, .buildingTower, .buildingLab: return 3
        case .terrainMountain, .buildingHQ: return 4
        default: return 0
        }
    }

    private static func daysOfRuinTerrainStars(_ terrain: Element) -> Int {
        switch terrain.simplified {
        case .terrainPlain, .terrainPlainD, .terrainReef: return 1
        case .terrainWood: return 3
        case .buildingCity, .buildingBase, .buildingAirport, .buildingPort: return 3
        case .terrainMountain, .buildingHQ: return 4
        default: return 0
        }
    }

    private static func dualStrikeTerrainStars(_ terrain: Element) -> Int {
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
        if ruleset == .famicomWars,
           [.buildingSilo, .buildingLab, .buildingTower].contains(building.simplified) {
            return false
        }
        if ruleset == .gameBoyWars || ruleset == .gameBoyWars2 || ruleset == .gameBoyWars3,
           [.buildingSilo, .buildingLab, .buildingTower].contains(building.simplified) {
            return false
        }
        if ruleset == .daysOfRuin,
           [.buildingSilo, .buildingLab, .buildingTower].contains(building.simplified) {
            return false
        }
        return true
    }

}
