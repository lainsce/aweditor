import AWEDCore

extension PlaytestAdvanceWarsRules {
    static let statsByValuePart3: [Int: PlaytestUnitStats] = [
        Element.unitBattleship.simplified.value: .init(cost: 28_000, move: 5, minRange: 2, maxRange: 6, domain: .sea, canCapture: false, attackPower: 95, movementType: .ship, maxFuel: 99, dailyFuelUse: 1, vision: 2, primaryAmmo: 9, canMoveAndFire: false, canCounterattack: false),
        Element.unitCruiser.simplified.value: .init(cost: 18_000, move: 6, minRange: 1, maxRange: 1, domain: .sea, canCapture: false, attackPower: 115, movementType: .ship, maxFuel: 99, dailyFuelUse: 1, vision: 3, primaryAmmo: 9),
        Element.unitLander.simplified.value: .init(cost: 12_000, move: 6, minRange: 0, maxRange: 0, domain: .sea, canCapture: false, attackPower: 0, movementType: .lander, maxFuel: 99, dailyFuelUse: 1, vision: 1, canCounterattack: false),
        Element.unitSub.simplified.value: .init(cost: 20_000, move: 5, minRange: 1, maxRange: 1, domain: .sea, canCapture: false, attackPower: 95, movementType: .ship, maxFuel: 60, dailyFuelUse: 1, vision: 5, primaryAmmo: 6)
    ]
}
