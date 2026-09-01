import AWEDCore

extension PlaytestAdvanceWarsRules {
    static let statsByValuePart1: [Int: PlaytestUnitStats] = [
        Element.unitInfantry.simplified.value: .init(cost: 1_000, move: 3, minRange: 1, maxRange: 1, domain: .land, canCapture: true, attackPower: 55, movementType: .foot, maxFuel: 99, vision: 2),
        Element.unitMech.simplified.value: .init(cost: 3_000, move: 2, minRange: 1, maxRange: 1, domain: .land, canCapture: true, attackPower: 65, movementType: .mech, maxFuel: 70, vision: 2, primaryAmmo: 3),
        Element.unitRecon.simplified.value: .init(cost: 4_000, move: 8, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 70, movementType: .tire, maxFuel: 80, vision: 5),
        Element.unitTank.simplified.value: .init(cost: 7_000, move: 6, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 75, movementType: .tread, maxFuel: 70, vision: 3, primaryAmmo: 9),
        Element.unitMDTank.simplified.value: .init(cost: 16_000, move: 5, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 105, movementType: .tread, maxFuel: 50, vision: 1, primaryAmmo: 8),
        Element.unitAPC.simplified.value: .init(cost: 5_000, move: 6, minRange: 0, maxRange: 0, domain: .land, canCapture: false, attackPower: 0, movementType: .tread, maxFuel: 70, vision: 1)
    ]
}
