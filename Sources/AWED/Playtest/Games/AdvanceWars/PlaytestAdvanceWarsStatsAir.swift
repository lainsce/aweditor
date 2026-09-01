import AWEDCore

extension PlaytestAdvanceWarsRules {
    static let statsByValuePart2: [Int: PlaytestUnitStats] = [
        Element.unitArtillery.simplified.value: .init(cost: 6_000, move: 5, minRange: 2, maxRange: 3, domain: .land, canCapture: false, attackPower: 90, movementType: .tread, maxFuel: 50, vision: 1, primaryAmmo: 9, canMoveAndFire: false, canCounterattack: false),
        Element.unitRocket.simplified.value: .init(cost: 15_000, move: 5, minRange: 3, maxRange: 5, domain: .land, canCapture: false, attackPower: 95, movementType: .tire, maxFuel: 50, vision: 1, primaryAmmo: 6, canMoveAndFire: false, canCounterattack: false),
        Element.unitAntiAir.simplified.value: .init(cost: 8_000, move: 6, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 105, movementType: .tread, maxFuel: 60, vision: 2, primaryAmmo: 9),
        Element.unitMissile.simplified.value: .init(cost: 12_000, move: 4, minRange: 3, maxRange: 5, domain: .land, canCapture: false, attackPower: 100, movementType: .tire, maxFuel: 50, vision: 5, primaryAmmo: 6, canMoveAndFire: false, canCounterattack: false),
        Element.unitTCopter.simplified.value: .init(cost: 5_000, move: 6, minRange: 0, maxRange: 0, domain: .air, canCapture: false, attackPower: 0, movementType: .air, maxFuel: 99, dailyFuelUse: 2, vision: 2, canCounterattack: false),
        Element.unitBCopter.simplified.value: .init(cost: 9_000, move: 6, minRange: 1, maxRange: 1, domain: .air, canCapture: false, attackPower: 75, movementType: .air, maxFuel: 99, dailyFuelUse: 2, vision: 3, primaryAmmo: 6),
        Element.unitFighter.simplified.value: .init(cost: 20_000, move: 9, minRange: 1, maxRange: 1, domain: .air, canCapture: false, attackPower: 55, movementType: .air, maxFuel: 99, dailyFuelUse: 5, vision: 2, primaryAmmo: 9),
        Element.unitBomber.simplified.value: .init(cost: 22_000, move: 7, minRange: 1, maxRange: 1, domain: .air, canCapture: false, attackPower: 110, movementType: .air, maxFuel: 99, dailyFuelUse: 5, vision: 2, primaryAmmo: 9)
    ]
}
