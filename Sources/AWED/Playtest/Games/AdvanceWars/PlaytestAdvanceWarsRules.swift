import AWEDCore

/// Original Advance Wars rules for the CO-less playtest.
///
/// AW1 shares the movement, weather, fuel, transport, and visibility
/// systems with AW2, but its roster and damage/weapon tables are different.
/// Keeping the cartridge-specific table here prevents an AW2 Neotank or
/// AW2-era damage value from leaking into an AW1 map.
enum PlaytestAdvanceWarsRules {
    static let weatherOptions: [PlaytestWeather] = [.random, .clear, .snow]

    static let landUnits: [Element] = [
        .unitInfantry, .unitMech, .unitRecon, .unitTank, .unitMDTank,
        .unitAPC, .unitArtillery, .unitRocket, .unitAntiAir, .unitMissile
    ]

    static let airUnits: [Element] = [
        .unitTCopter, .unitBCopter, .unitFighter, .unitBomber
    ]

    static let seaUnits: [Element] = [
        .unitBattleship, .unitCruiser, .unitLander, .unitSub
    ]

    /// GB Wars has a compact 15-unit roster: eight land units, three air
    /// units, and four sea units. The shared element slots are relabeled in
    /// `PaletteCatalog` to match the GB cartridge's names.
    static let gbWarsLandUnits: [Element] = [
        .unitInfantry, .unitMech, .unitAPC, .unitRecon, .unitRocket,
        .unitAntiAir, .unitArtillery, .unitTank
    ]

    static let gbWarsAirUnits: [Element] = [
        .unitTCopter, .unitBCopter, .unitBomber
    ]

    static let gbWarsSeaUnits: [Element] = [
        .unitLander, .unitSub, .unitCruiser, .unitBattleship
    ]

    /// Famicom Wars has a smaller, fixed build roster: ten land units, four
    /// air units, and only Battleships and Landers at ports. The editor's
    /// shared element table does not have separate Supply, Scout, and Copter
    /// identifiers, so those source-game names are represented by the
    /// compatible existing sprite slots (`Recon`, `B-Copter`, and `T-Copter`)
    /// when the Famicom production menu is built.
    static let famicomWarsLandUnits: [Element] = [
        .unitInfantry, .unitMech, .unitMDTank, .unitTank, .unitAPC,
        .unitRocket, .unitArtillery, .unitMissile, .unitAntiAir, .unitRecon
    ]

    static let famicomWarsAirUnits: [Element] = [
        .unitFighter, .unitBCopter, .unitBomber, .unitTCopter
    ]

    static let famicomWarsSeaUnits: [Element] = [
        .unitBattleship, .unitLander
    ]

    static func famicomWarsProductionLabel(for element: Element) -> String {
        switch element.simplified {
        case .unitMDTank: return "Med Tank"
        case .unitRocket: return "Howitzer"
        case .unitMissile: return "AA Missile"
        case .unitAntiAir: return "AA Tank"
        case .unitRecon: return "Supply Truck"
        case .unitBCopter: return "Scout"
        case .unitTCopter: return "Helicopter"
        default: return PaletteCatalog.label(for: element)
        }
    }

    private static let landDamageAttackers: [Element] = [
        .unitInfantry, .unitMech, .unitRecon, .unitTank, .unitMDTank,
        .unitAPC, .unitArtillery, .unitRocket, .unitAntiAir, .unitMissile,
        .unitFighter, .unitBomber, .unitBCopter, .unitBattleship
    ]

    private static let landDamageDefenders: [Element] = [
        .unitInfantry, .unitMech, .unitRecon, .unitTank, .unitMDTank,
        .unitAPC, .unitArtillery, .unitRocket, .unitAntiAir, .unitMissile
    ]

    private static let airSeaDamageAttackers: [Element] = [
        .unitInfantry, .unitMech, .unitRecon, .unitTank, .unitMDTank,
        .unitArtillery, .unitRocket, .unitAntiAir, .unitMissile,
        .unitFighter, .unitBomber, .unitBCopter, .unitBattleship,
        .unitCruiser, .unitSub
    ]

    private static let airSeaDamageDefenders: [Element] = [
        .unitFighter, .unitBomber, .unitBCopter, .unitTCopter,
        .unitBattleship, .unitCruiser, .unitLander, .unitSub
    ]

    // AW1 base damage at 10 HP, before luck and terrain defense. A nil cell
    // is an illegal matchup. These values intentionally do not reuse AW2's
    // table; for example, Md Tank -> Cruiser is 55 in AW1.
    private static let landDamage: [[Int?]] = [
        [55, 45, 12, 5, 1, 14, 15, 25, 5, 25],
        [65, 55, 85, 55, 15, 75, 70, 85, 65, 85],
        [70, 65, 35, 6, 1, 45, 45, 55, 4, 28],
        [75, 70, 85, 55, 15, 75, 70, 85, 65, 85],
        [105, 95, 105, 85, 55, 105, 105, 105, 105, 105],
        [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil],
        [90, 85, 80, 70, 45, 70, 75, 80, 75, 80],
        [95, 90, 90, 80, 55, 80, 80, 85, 85, 90],
        [105, 105, 60, 25, 10, 50, 50, 55, 45, 55],
        [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil],
        [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil],
        [110, 110, 105, 105, 95, 105, 105, 105, 95, 105],
        [75, 75, 55, 55, 25, 60, 65, 65, 25, 65],
        [95, 90, 90, 80, 55, 80, 80, 85, 85, 90]
    ]

    private static let airSeaDamage: [[Int?]] = [
        [nil, nil, 7, 30, nil, nil, nil, nil],
        [nil, nil, 9, 35, nil, nil, nil, nil],
        [nil, nil, 10, 35, nil, nil, nil, nil],
        [nil, nil, 10, 40, 1, 5, 10, 1],
        [nil, nil, 12, 45, 10, 55, 35, 10],
        [nil, nil, nil, nil, 40, 65, 55, 60],
        [nil, nil, nil, nil, 55, 85, 60, 85],
        [65, 75, 120, 120, nil, nil, nil, nil],
        [100, 100, 120, 120, nil, nil, nil, nil],
        [55, 100, 100, 100, nil, nil, nil, nil],
        [nil, nil, nil, nil, 75, 85, 95, 95],
        [nil, nil, 65, 95, 25, 55, 25, 25],
        [nil, nil, nil, nil, 50, 95, 95, 95],
        [55, 65, 115, 115, nil, nil, nil, 90],
        [nil, nil, nil, nil, 55, 25, 95, 55]
    ]

    static func stats(for element: Element) -> PlaytestUnitStats? {
        let value = element.simplified.value
        return statsByValuePart1[value] ?? statsByValuePart2[value] ?? statsByValuePart3[value]
    }

    static func canAttack(_ attacker: Element, _ defender: Element, primaryAmmo: Int? = nil) -> Bool {
        guard let attackerStats = stats(for: attacker),
              attackerStats.attackPower > 0,
              stats(for: defender) != nil,
              baseDamage(attacker: attacker, defender: defender) != nil else { return false }

        guard let ammoCapacity = attackerStats.primaryAmmo else { return true }
        if (primaryAmmo ?? ammoCapacity) > 0, usesPrimaryWeapon(attacker, defender, primaryAmmo: primaryAmmo) {
            return true
        }
        return secondaryDamage(attacker: attacker, defender: defender) != nil
    }

    static func usesPrimaryWeapon(_ attacker: Element, _ defender: Element, primaryAmmo: Int? = nil) -> Bool {
        guard let attackerStats = stats(for: attacker),
              let ammoCapacity = attackerStats.primaryAmmo,
              (primaryAmmo ?? ammoCapacity) > 0,
              baseDamage(attacker: attacker, defender: defender) != nil else { return false }

        switch attacker.simplified {
        case .unitMech:
            // Bazookas are for vehicles and naval targets are not a Mech
            // matchup; Infantry, Mechs, and Copters use the MG.
            return defender.simplified != .unitInfantry && defender.simplified != .unitMech &&
                stats(for: defender)?.domain == .land
        case .unitTank, .unitMDTank:
            // Cannon fire handles vehicles and ships. Foot units and air
            // targets use the unlimited machine gun.
            return defender.simplified != .unitInfantry && defender.simplified != .unitMech &&
                stats(for: defender)?.domain != .air
        case .unitBCopter:
            // Missiles are reserved for vehicles and ships; the MG handles
            // foot units and both Copter classes.
            return defender.simplified != .unitInfantry && defender.simplified != .unitMech &&
                defender.simplified != .unitBCopter && defender.simplified != .unitTCopter
        case .unitCruiser:
            // A Cruiser's torpedoes are reserved for Submarines; its
            // unlimited anti-air guns handle every air target.
            return defender.simplified == .unitSub
        default:
            return true
        }
    }

    static func baseDamage(attacker: Element, defender: Element) -> Int? {
        let attackerValue = attacker.simplified.value
        let defenderValue = defender.simplified.value
        if let attackerIndex = landDamageAttackers.firstIndex(where: { $0.value == attackerValue }),
           let defenderIndex = landDamageDefenders.firstIndex(where: { $0.value == defenderValue }) {
            return landDamage[attackerIndex][defenderIndex]
        }
        if let attackerIndex = airSeaDamageAttackers.firstIndex(where: { $0.value == attackerValue }),
           let defenderIndex = airSeaDamageDefenders.firstIndex(where: { $0.value == defenderValue }) {
            return airSeaDamage[attackerIndex][defenderIndex]
        }
        return nil
    }

    static func damage(
        attacker: Element,
        defender: Element,
        attackerHealth: Int,
        defenderHealth: Int,
        terrain: Element,
        primaryAmmo: Int?,
        randomize: Bool = true
    ) -> Int? {
        guard canAttack(attacker, defender, primaryAmmo: primaryAmmo),
              let base = damageBase(attacker: attacker, defender: defender, primaryAmmo: primaryAmmo), base > 0 else { return nil }
        return scaledDamage(base: base, defender: defender, defenderHealth: defenderHealth,
                            attackerHealth: attackerHealth, terrain: terrain, randomize: randomize)
    }

    private static func damageBase(attacker: Element, defender: Element, primaryAmmo: Int?) -> Int? {
        guard let stats = stats(for: attacker) else { return nil }
        if stats.primaryAmmo != nil, !usesPrimaryWeapon(attacker, defender, primaryAmmo: primaryAmmo) {
            return secondaryDamage(attacker: attacker, defender: defender)
        }
        return baseDamage(attacker: attacker, defender: defender)
    }

    private static func scaledDamage(
        base: Int,
        defender: Element,
        defenderHealth: Int,
        attackerHealth: Int,
        terrain: Element,
        randomize: Bool
    ) -> Int {
        let displayedHealth = max(1, min(10, defenderHealth / 10))
        let stars = stats(for: defender)?.domain == .air ? 0 : terrainStars(for: terrain)
        let defense = max(0, 100 - stars * displayedHealth)
        let luck = randomize ? Int.random(in: 0...9) : 4
        let raw = Double(base + luck) * (Double(max(1, min(100, attackerHealth))) / 100) * (Double(defense) / 100)
        return max(1, min(100, Int(raw.rounded(.down))))
    }

    static func movementCost(for unit: Element, terrain: Element, weather: PlaytestWeather) -> Int? {
        // AW1 and AW2 use the same GBA movement/weather tables. The AW2
        // implementation is intentionally limited to these movement types
        // and contains no DS snow-fuel behavior.
        PlaytestAdvanceWars2Rules.movementCost(for: unit, terrain: terrain, weather: weather)
    }

    static func terrainStars(for terrain: Element) -> Int {
        switch terrain.simplified {
        case .terrainPlain, .terrainPlainD: return 1
        case .terrainReef: return 1
        case .terrainWood: return 2
        case .buildingCity, .buildingBase, .buildingAirport, .buildingPort: return 3
        case .terrainMountain, .buildingHQ: return 4
        default: return 0
        }
    }

    static func canTransport(_ transport: Element, cargo: Element) -> Bool {
        guard cargo.army == transport.army, stats(for: cargo) != nil else { return false }
        switch transport.simplified {
        case .unitAPC, .unitTCopter:
            return cargo.simplified == .unitInfantry || cargo.simplified == .unitMech
        case .unitLander:
            return stats(for: cargo)?.domain == .land
        case .unitCruiser:
            return cargo.simplified == .unitBCopter || cargo.simplified == .unitTCopter
        default:
            return false
        }
    }

    static func transportCapacity(for element: Element) -> Int {
        switch element.simplified {
        case .unitAPC, .unitTCopter: return 1
        case .unitLander, .unitCruiser: return 2
        default: return 0
        }
    }

    private static func secondaryDamage(attacker: Element, defender: Element) -> Int? {
        switch attacker.simplified {
        case .unitMech: return secondaryMechDamage(attacker: attacker, defender: defender)
        case .unitTank: return secondaryTankDamage(attacker: attacker, defender: defender)
        case .unitMDTank: return secondaryMDTankDamage(attacker: attacker, defender: defender)
        case .unitBCopter: return secondaryBCopterDamage(attacker: attacker, defender: defender)
        case .unitCruiser: return secondaryCruiserDamage(attacker: attacker, defender: defender)
        default:
            return nil
        }
    }

    private static func secondaryMechDamage(attacker: Element, defender: Element) -> Int? {
        switch defender.simplified {
        case .unitInfantry, .unitMech, .unitBCopter, .unitTCopter: return baseDamage(attacker: attacker, defender: defender)
        case .unitRecon: return 18
        case .unitTank: return 6
        case .unitMDTank: return 1
        case .unitAPC: return 20
        case .unitArtillery: return 32
        case .unitRocket: return 35
        case .unitAntiAir: return 6
        case .unitMissile: return 32
        default: return nil
        }
    }

    private static func secondaryTankDamage(attacker: Element, defender: Element) -> Int? {
        switch defender.simplified {
        case .unitInfantry: return 75
        case .unitMech: return 70
        case .unitRecon: return 40
        case .unitTank: return 6
        case .unitMDTank: return 1
        case .unitAPC, .unitArtillery: return 45
        case .unitRocket: return 55
        case .unitAntiAir: return 6
        case .unitMissile: return 30
        case .unitFighter, .unitBomber, .unitBCopter, .unitTCopter: return baseDamage(attacker: attacker, defender: defender)
        default: return nil
        }
    }

    private static func secondaryMDTankDamage(attacker: Element, defender: Element) -> Int? {
        switch defender.simplified {
        case .unitInfantry: return 105
        case .unitMech: return 95
        case .unitRecon: return 45
        case .unitTank: return 8
        case .unitMDTank: return 1
        case .unitAPC, .unitArtillery: return 45
        case .unitRocket: return 55
        case .unitAntiAir: return 8
        case .unitMissile: return 30
        case .unitFighter, .unitBomber, .unitBCopter, .unitTCopter: return baseDamage(attacker: attacker, defender: defender)
        default: return nil
        }
    }

    private static func secondaryBCopterDamage(attacker: Element, defender: Element) -> Int? {
        switch defender.simplified {
        case .unitInfantry, .unitMech, .unitBCopter, .unitTCopter: return baseDamage(attacker: attacker, defender: defender)
        case .unitRecon: return 30
        case .unitTank: return 6
        case .unitMDTank: return 1
        case .unitAPC: return 20
        case .unitArtillery: return 25
        case .unitRocket, .unitMissile: return 35
        case .unitAntiAir: return 6
        default: return nil
        }
    }

    private static func secondaryCruiserDamage(attacker: Element, defender: Element) -> Int? {
        stats(for: defender)?.domain == .air ? baseDamage(attacker: attacker, defender: defender) : nil
    }
}
