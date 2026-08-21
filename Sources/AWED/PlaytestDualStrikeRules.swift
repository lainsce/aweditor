import AWEDCore

/// Dual Strike's unit roster and production availability.
///
/// Keeping this table separate from PlaytestSession makes the DS-specific
/// costs, movement values, and unit availability easy to audit against the
/// rules reference without mixing them into turn-state mechanics.
enum PlaytestDualStrikeRules {
    static func stats(for element: Element) -> PlaytestUnitStats? {
        switch element.simplified.value {
        case Element.unitInfantry.value:
            .init(cost: 1_000, move: 3, minRange: 1, maxRange: 1, domain: .land, canCapture: true, attackPower: 55)
        case Element.unitMech.value:
            .init(cost: 3_000, move: 2, minRange: 1, maxRange: 1, domain: .land, canCapture: true, attackPower: 85)
        case Element.unitAPC.value:
            .init(cost: 5_000, move: 6, minRange: 0, maxRange: 0, domain: .land, canCapture: false, attackPower: 0)
        case Element.unitRecon.value:
            .init(cost: 4_000, move: 8, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 60)
        case Element.unitTank.value:
            .init(cost: 7_000, move: 6, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 72)
        case Element.unitMDTank.value:
            .init(cost: 16_000, move: 5, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 96)
        case Element.unitNeoTank.value:
            .init(cost: 22_000, move: 6, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 105)
        case Element.unitMegaTank.value:
            .init(cost: 28_000, move: 4, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 115)
        case Element.unitOozium.value:
            .init(cost: 0, move: 1, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 100)
        case Element.unitArtillery.value:
            .init(cost: 6_000, move: 5, minRange: 2, maxRange: 3, domain: .land, canCapture: false, attackPower: 68)
        case Element.unitRocket.value:
            .init(cost: 15_000, move: 5, minRange: 3, maxRange: 5, domain: .land, canCapture: false, attackPower: 78)
        case Element.unitPipeRunner.value:
            .init(cost: 20_000, move: 9, minRange: 2, maxRange: 5, domain: .land, canCapture: false, attackPower: 84)
        case Element.unitMissile.value:
            .init(cost: 12_000, move: 4, minRange: 3, maxRange: 5, domain: .land, canCapture: false, attackPower: 86)
        case Element.unitAntiAir.value:
            .init(cost: 8_000, move: 6, minRange: 1, maxRange: 1, domain: .land, canCapture: false, attackPower: 92)
        case Element.unitTCopter.value:
            .init(cost: 5_000, move: 6, minRange: 0, maxRange: 0, domain: .air, canCapture: false, attackPower: 0)
        case Element.unitBCopter.value:
            .init(cost: 9_000, move: 6, minRange: 1, maxRange: 1, domain: .air, canCapture: false, attackPower: 72)
        case Element.unitFighter.value:
            .init(cost: 20_000, move: 9, minRange: 1, maxRange: 1, domain: .air, canCapture: false, attackPower: 100)
        case Element.unitBomber.value:
            .init(cost: 22_000, move: 7, minRange: 1, maxRange: 1, domain: .air, canCapture: false, attackPower: 100)
        case Element.unitStealth.value:
            .init(cost: 24_000, move: 6, minRange: 1, maxRange: 1, domain: .air, canCapture: false, attackPower: 98)
        case Element.unitBlackBomb.value:
            .init(cost: 25_000, move: 9, minRange: 1, maxRange: 1, domain: .air, canCapture: false, attackPower: 100)
        case Element.unitBlackBoat.value:
            .init(cost: 7_500, move: 7, minRange: 1, maxRange: 1, domain: .sea, canCapture: false, attackPower: 58)
        case Element.unitLander.value:
            .init(cost: 12_000, move: 6, minRange: 0, maxRange: 0, domain: .sea, canCapture: false, attackPower: 0)
        case Element.unitCruiser.value:
            .init(cost: 18_000, move: 6, minRange: 1, maxRange: 1, domain: .sea, canCapture: false, attackPower: 82)
        case Element.unitSub.value:
            .init(cost: 20_000, move: 5, minRange: 1, maxRange: 1, domain: .sea, canCapture: false, attackPower: 80)
        case Element.unitBattleship.value:
            .init(cost: 28_000, move: 5, minRange: 2, maxRange: 6, domain: .sea, canCapture: false, attackPower: 90)
        case Element.unitCarrier.value:
            .init(cost: 30_000, move: 5, minRange: 0, maxRange: 0, domain: .sea, canCapture: false, attackPower: 0)
        default:
            nil
        }
    }

    static let landUnits: [Element] = [
        .unitInfantry, .unitMech, .unitAPC, .unitRecon, .unitTank, .unitMDTank,
        .unitNeoTank, .unitMegaTank, .unitArtillery, .unitRocket, .unitMissile,
        .unitAntiAir, .unitPipeRunner
    ]

    static let airUnits: [Element] = [
        .unitTCopter, .unitBCopter, .unitFighter, .unitBomber, .unitStealth, .unitBlackBomb
    ]

    static let seaUnits: [Element] = [
        .unitLander, .unitCruiser, .unitSub, .unitBattleship, .unitBlackBoat, .unitCarrier
    ]
}
