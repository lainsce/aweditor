import AWEDCore

/// The cartridge rules that differ from Dual Strike live here so the shared
/// playtest session does not quietly apply DS-only units or weather behavior to
/// an AW2 map.
enum PlaytestAdvanceWars2Rules {
    static let weatherOptions: [PlaytestWeather] = [.random, .clear, .rain, .snow]

    static let landUnits: [Element] = [
        .unitInfantry, .unitMech, .unitRecon, .unitTank, .unitMDTank,
        .unitNeoTank, .unitAPC, .unitArtillery, .unitRocket, .unitAntiAir,
        .unitMissile
    ]

    static let airUnits: [Element] = [
        .unitTCopter, .unitBCopter, .unitFighter, .unitBomber
    ]

    static let seaUnits: [Element] = [
        .unitBattleship, .unitCruiser, .unitLander, .unitSub
    ]

    private static let landDamageAttackers: [Element] = [
        .unitInfantry, .unitMech, .unitRecon, .unitTank, .unitMDTank,
        .unitNeoTank, .unitAPC, .unitArtillery, .unitRocket, .unitAntiAir,
        .unitMissile, .unitFighter, .unitBomber, .unitBCopter, .unitBattleship
    ]

    private static let landDamageDefenders: [Element] = [
        .unitInfantry, .unitMech, .unitRecon, .unitTank, .unitMDTank,
        .unitNeoTank, .unitAPC, .unitArtillery, .unitRocket, .unitAntiAir,
        .unitMissile
    ]

    private static let airSeaDamageAttackers: [Element] = [
        .unitInfantry, .unitMech, .unitRecon, .unitTank, .unitMDTank,
        .unitNeoTank, .unitArtillery, .unitRocket, .unitAntiAir, .unitMissile,
        .unitFighter, .unitBomber, .unitBCopter, .unitBattleship, .unitCruiser,
        .unitSub
    ]

    private static let airSeaDamageDefenders: [Element] = [
        .unitFighter, .unitBomber, .unitBCopter, .unitTCopter,
        .unitBattleship, .unitCruiser, .unitLander, .unitSub
    ]

    // AW2 base-damage values at 10 HP, before luck and terrain defense.
    // A nil cell is an illegal matchup.
    private static let landDamage: [[Int?]] = [
        [55, 45, 12, 5, 1, 1, 14, 15, 25, 5, 25],
        [65, 55, 85, 55, 15, 15, 75, 70, 85, 65, 85],
        [70, 65, 35, 6, 1, 1, 45, 45, 55, 4, 28],
        [75, 70, 85, 55, 15, 15, 75, 70, 85, 65, 85],
        [105, 95, 105, 85, 55, 45, 105, 105, 105, 105, 105],
        [125, 115, 125, 105, 75, 55, 125, 115, 125, 115, 125],
        [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil],
        [90, 85, 80, 70, 45, 40, 70, 75, 80, 75, 80],
        [95, 90, 90, 80, 55, 50, 80, 80, 85, 85, 90],
        [105, 105, 60, 25, 10, 5, 50, 50, 55, 45, 55],
        [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil],
        [110, 110, 105, 105, 95, 90, 105, 105, 105, 95, 105],
        [75, 75, 55, 55, 25, 20, 60, 65, 65, 25, 65],
        [95, 90, 90, 80, 55, 50, 80, 80, 85, 85, 90]
    ]

    private static let airSeaDamage: [[Int?]] = [
        [nil, nil, 7, 30, nil, nil, nil, nil],
        [nil, nil, 9, 35, nil, nil, nil, nil],
        [nil, nil, 10, 35, nil, nil, nil, nil],
        [nil, nil, 10, 40, 1, 5, 10, 1],
        [nil, nil, 12, 45, 10, 45, 35, 10],
        [nil, nil, 22, 55, 15, 50, 40, 15],
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
        switch element.simplified.value {
        case Element.unitInfantry.value:
            return .init(cost: 1_000, move: 3, minRange: 1, maxRange: 1, domain: .land, canCapture: true, attackPower: 55, movementType: .foot, maxFuel: 99, vision: 2, primaryAmmo: nil)
        case Element.unitMech.value:
            return .init(cost: 3_000, move: 2, minRange: 1, maxRange: 1, domain: .land, canCapture: true, attackPower: 65, movementType: .mech, maxFuel: 70, vision: 2, primaryAmmo: 3, secondaryAttackPower: 12)
        case Element.unitRecon.value:
            return .init(cost: 4_000, move: 8, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 70, movementType: .tire, maxFuel: 80, vision: 5)
        case Element.unitTank.value:
            return .init(cost: 7_000, move: 6, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 75, movementType: .tread, maxFuel: 70, primaryAmmo: 9, secondaryAttackPower: 6)
        case Element.unitMDTank.value:
            return .init(cost: 16_000, move: 5, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 105, movementType: .tread, maxFuel: 50, primaryAmmo: 8, secondaryAttackPower: 8)
        case Element.unitNeoTank.value:
            return .init(cost: 22_000, move: 6, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 125, movementType: .tread, maxFuel: 99, primaryAmmo: 9, secondaryAttackPower: 10)
        case Element.unitAPC.value:
            return .init(cost: 5_000, move: 6, minRange: 0, maxRange: 0, domain: .land, canCapture: false, attackPower: 0, movementType: .tread, maxFuel: 70)
        case Element.unitArtillery.value:
            return .init(cost: 6_000, move: 5, minRange: 2, maxRange: 3, domain: .land, canCapture: false, attackPower: 90, movementType: .tire, maxFuel: 50, primaryAmmo: 9, canMoveAndFire: false, canCounterattack: false)
        case Element.unitRocket.value:
            return .init(cost: 15_000, move: 5, minRange: 3, maxRange: 5, domain: .land, canCapture: false, attackPower: 95, movementType: .tire, maxFuel: 50, primaryAmmo: 6, canMoveAndFire: false, canCounterattack: false)
        case Element.unitAntiAir.value:
            return .init(cost: 8_000, move: 6, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 105, movementType: .tread, maxFuel: 60, vision: 2, primaryAmmo: 9)
        case Element.unitMissile.value:
            return .init(cost: 12_000, move: 4, minRange: 3, maxRange: 5, domain: .land, canCapture: false, attackPower: 100, movementType: .tire, maxFuel: 50, vision: 5, primaryAmmo: 6, canMoveAndFire: false, canCounterattack: false)
        case Element.unitTCopter.value:
            return .init(cost: 5_000, move: 6, minRange: 0, maxRange: 0, domain: .air, canCapture: false, attackPower: 0, movementType: .air, maxFuel: 99, dailyFuelUse: 2, vision: 2, canCounterattack: false)
        case Element.unitBCopter.value:
            return .init(cost: 9_000, move: 6, minRange: 1, maxRange: 1, domain: .air, canCapture: false, attackPower: 75, movementType: .air, maxFuel: 99, dailyFuelUse: 2, vision: 3, primaryAmmo: 6, secondaryAttackPower: 6)
        case Element.unitFighter.value:
            return .init(cost: 20_000, move: 9, minRange: 1, maxRange: 1, domain: .air, canCapture: false, attackPower: 55, movementType: .air, maxFuel: 99, dailyFuelUse: 5, vision: 2, primaryAmmo: 9)
        case Element.unitBomber.value:
            return .init(cost: 22_000, move: 7, minRange: 1, maxRange: 1, domain: .air, canCapture: false, attackPower: 110, movementType: .air, maxFuel: 99, dailyFuelUse: 5, vision: 2, primaryAmmo: 9)
        case Element.unitBattleship.value:
            return .init(cost: 28_000, move: 5, minRange: 2, maxRange: 6, domain: .sea, canCapture: false, attackPower: 95, movementType: .ship, maxFuel: 99, dailyFuelUse: 1, vision: 2, primaryAmmo: 9, canMoveAndFire: false, canCounterattack: false)
        case Element.unitCruiser.value:
            return .init(cost: 18_000, move: 6, minRange: 1, maxRange: 1, domain: .sea, canCapture: false, attackPower: 115, movementType: .ship, maxFuel: 99, dailyFuelUse: 1, vision: 3, primaryAmmo: 9)
        case Element.unitLander.value:
            return .init(cost: 12_000, move: 6, minRange: 0, maxRange: 0, domain: .sea, canCapture: false, attackPower: 0, movementType: .lander, maxFuel: 99, dailyFuelUse: 1, vision: 1, canCounterattack: false)
        case Element.unitSub.value:
            return .init(cost: 20_000, move: 5, minRange: 1, maxRange: 1, domain: .sea, canCapture: false, attackPower: 95, movementType: .ship, maxFuel: 60, dailyFuelUse: 1, vision: 5, primaryAmmo: 6)
        default:
            return nil
        }
    }

    static func canAttack(_ attacker: Element, _ defender: Element, primaryAmmo: Int? = nil) -> Bool {
        guard let attackerStats = stats(for: attacker), attackerStats.attackPower > 0,
              stats(for: defender) != nil else { return false }
        guard baseDamage(attacker: attacker, defender: defender) != nil else { return false }

        guard let ammoCapacity = attackerStats.primaryAmmo else { return true }
        if (primaryAmmo ?? ammoCapacity) > 0, usesPrimaryWeapon(attacker, defender, primaryAmmo: primaryAmmo) {
            return true
        }

        // Cruisers retain their unlimited anti-air secondary weapon after
        // their anti-submarine ammunition is depleted. Other limited weapons
        // use the unit's lower-power secondary value when available.
        if attacker.simplified == .unitCruiser {
            return stats(for: defender)?.domain == .air
        }
        return attackerStats.secondaryAttackPower != nil
    }

    static func usesPrimaryWeapon(_ attacker: Element, _ defender: Element, primaryAmmo: Int? = nil) -> Bool {
        guard let attackerStats = stats(for: attacker),
              let ammoCapacity = attackerStats.primaryAmmo,
              (primaryAmmo ?? ammoCapacity) > 0,
              baseDamage(attacker: attacker, defender: defender) != nil else { return false }

        // A Cruiser's limited weapon is anti-submarine only. Its anti-air
        // gun is the unlimited secondary weapon, even while torpedo ammo
        // remains.
        if attacker.simplified == .unitCruiser {
            return defender.simplified == .unitSub
        }
        return true
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
        guard canAttack(attacker, defender, primaryAmmo: primaryAmmo) else { return nil }
        guard let attackerStats = stats(for: attacker) else { return nil }

        let useSecondary = attackerStats.primaryAmmo != nil && !usesPrimaryWeapon(attacker, defender, primaryAmmo: primaryAmmo)
        let cruiserAntiAir = attacker.simplified == .unitCruiser && stats(for: defender)?.domain == .air
        guard !useSecondary || attackerStats.secondaryAttackPower != nil || cruiserAntiAir else { return nil }
        let base = useSecondary
            ? (cruiserAntiAir ? (baseDamage(attacker: attacker, defender: defender) ?? 0) : (attackerStats.secondaryAttackPower ?? 0))
            : (baseDamage(attacker: attacker, defender: defender) ?? 0)
        guard base > 0 else { return nil }

        let displayedDefenderHealth = max(1, min(10, defenderHealth / 10))
        let stars = stats(for: defender)?.domain == .air
            ? 0
            : terrainStars(for: terrain)
        let terrainDefense = max(0, 100 - stars * displayedDefenderHealth)
        let luck = randomize ? Int.random(in: 0...9) : 4
        let raw = Double(base + luck)
            * (Double(max(1, min(100, attackerHealth))) / 100)
            * (Double(terrainDefense) / 100)
        return max(1, min(100, Int(raw.rounded(.down))))
    }

    static func movementCost(for unit: Element, terrain: Element, weather: PlaytestWeather) -> Int? {
        let tile = terrain.simplified
        guard !terrain.isExtra, tile != .terrainPipe, tile != .terrainSeam else { return nil }

        let row: [Int?]
        switch tile {
        case .terrainRoad, .terrainBridgeH, .terrainBridgeV:
            row = movementRow(inf: 1, mech: 1, tread: 1, tire: 1, air: weather == .snow ? 2 : 1, ship: nil, lander: nil)
        case .terrainPlain, .terrainPlainD:
            row = movementRow(inf: weather == .snow ? 2 : 1, mech: 1, tread: weather == .rain || weather == .snow ? 2 : 1, tire: weather == .rain || weather == .snow ? 3 : 2, air: weather == .snow ? 2 : 1, ship: nil, lander: nil)
        case .terrainWood:
            row = movementRow(inf: weather == .snow ? 2 : 1, mech: 1, tread: weather == .rain || weather == .snow ? 3 : 2, tire: weather == .rain || weather == .snow ? 4 : 3, air: weather == .snow ? 2 : 1, ship: nil, lander: nil)
        case .terrainMountain:
            row = movementRow(inf: weather == .snow ? 4 : 2, mech: weather == .snow ? 2 : 1, tread: nil, tire: nil, air: weather == .snow ? 2 : 1, ship: nil, lander: nil)
        case .terrainRiver:
            row = movementRow(inf: 2, mech: 1, tread: nil, tire: nil, air: weather == .snow ? 2 : 1, ship: nil, lander: nil)
        case .terrainShoal:
            row = movementRow(inf: 1, mech: 1, tread: 1, tire: 1, air: weather == .snow ? 2 : 1, ship: nil, lander: 1)
        case .terrainSea:
            row = movementRow(inf: nil, mech: nil, tread: nil, tire: nil, air: weather == .snow ? 2 : 1, ship: weather == .snow ? 2 : 1, lander: weather == .snow ? 2 : 1)
        case .terrainReef:
            row = movementRow(inf: nil, mech: nil, tread: nil, tire: nil, air: weather == .snow ? 2 : 1, ship: weather == .snow ? 2 : 2, lander: weather == .snow ? 2 : 2)
        case .buildingPort:
            row = movementRow(inf: 1, mech: 1, tread: 1, tire: 1, air: weather == .snow ? 2 : 1, ship: weather == .snow ? 2 : 1, lander: weather == .snow ? 2 : 1)
        default:
            guard terrain.isBuilding else { return nil }
            // Snow increases the cost of entering normal terrain, but AW1/AW2
            // properties remain a one-point air landing square. Ports are
            // handled above because naval and transport movement there is
            // also weather-sensitive.
            row = movementRow(inf: 1, mech: 1, tread: 1, tire: 1, air: 1, ship: nil, lander: nil)
        }

        let movementType = stats(for: unit)?.movementType ?? .tread
        switch movementType {
        case .foot: return row[0]
        case .mech: return row[1]
        case .tread: return row[2]
        case .tire: return row[3]
        case .air: return row[4]
        case .ship: return row[5]
        case .lander: return row[6]
        }
    }

    static func terrainStars(for terrain: Element) -> Int {
        switch terrain.simplified {
        case .terrainPlain, .terrainPlainD: return 1
        case .terrainReef: return 1
        case .terrainWood: return 2
        case .buildingCity, .buildingBase, .buildingAirport, .buildingPort, .buildingLab, .buildingSilo: return 3
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

    private static func movementRow(inf: Int?, mech: Int?, tread: Int?, tire: Int?, air: Int?, ship: Int?, lander: Int?) -> [Int?] {
        [inf, mech, tread, tire, air, ship, lander]
    }
}
