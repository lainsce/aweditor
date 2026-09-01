import Testing
@testable import AWEDCore

@Test("element helpers cover conversions, footprints, and legacy categories")
func elementHelpers() {
    let buildingTypes = [
        Element.buildingHQ, .buildingCity, .buildingBase, .buildingAirport,
        .buildingPort, .buildingTower, .buildingLab, .buildingSilo
    ]
    let unitTypes = [
        Element.unitInfantry, .unitMech, .unitTank, .unitMDTank, .unitNeoTank,
        .unitMegaTank, .unitRecon, .unitAntiAir, .unitMissile, .unitArtillery,
        .unitRocket, .unitAPC, .unitPipeRunner, .unitOozium, .unitBlackBoat,
        .unitLander, .unitCruiser, .unitSub, .unitBattleship, .unitCarrier,
        .unitTCopter, .unitBCopter, .unitFighter, .unitBomber, .unitStealth,
        .unitBlackBomb
    ]
    let extraTypes = [
        Element.extraMCannonN, .extraMCannonS, .extraMCannonW, .extraMCannonE,
        .extraLCannon, .extraBCannons, .extraBCannonN, .extraDeathray,
        .extraBCrystal, .extraBobelisk, .extraVolcano, .extraFortress,
        .extraBlackArc, .extraGSilo, .extraSeaArc
    ]
    let terrainTypes = [
        Element.terrainBlank, .terrainPlain, .terrainPlainD, .terrainWood,
        .terrainMountain, .terrainRoad, .terrainBridgeH, .terrainBridgeV,
        .terrainRiver, .terrainPipe, .terrainSeam, .terrainShoal, .terrainSea,
        .terrainReef, Element(AWConstants.makeTerrain(0, 7)),
        Element(AWConstants.makeTerrain(17, 6)), Element(AWConstants.makeTerrain(9, 0)),
        Element(AWConstants.makeTerrain(14, 7))
    ]

    for element in terrainTypes + buildingTypes + unitTypes + extraTypes + [.unitEmpty, .unitDelete, Element(1300)] {
        _ = element.x
        _ = element.y
        _ = element.isTerrain
        _ = element.isBuilding
        _ = element.isUnit
        _ = element.isExtra
        _ = element.isBackground
        _ = element.isForeground
        _ = element.isUnitNonEmpty
        _ = element.doubleHeight
        _ = element.spritesheet
        _ = element.drawX
        _ = element.drawY
        _ = element.drawable
        _ = element.size
        _ = element.topLeft
        _ = element.largeOffset()
        _ = element.makeFromLargeOffset(x: 1, y: 1)
        _ = element.army
        _ = element.base
        _ = element.nextSprite()
        _ = element.isLand
        _ = element.isSea
        _ = element.isPipe
        _ = element.isRoad
        _ = element.isRiver
        for army in 0...AWConstants.armyNeutral { _ = element.changedArmy(army) }
        for format in MapFormat.allCases {
            _ = element.isCompatible(with: format)
            _ = element.converted(to: format)
        }
    }

    for format in MapFormat.allCases {
        _ = Element.convertFrom(0, mapType: format)
        _ = Element.convertFrom(300, mapType: format)
        _ = Element.convertFrom(500, mapType: format)
        _ = Element.convertFrom(900, mapType: format)
        _ = Element.convertFrom(AWConstants.unitEmpty, mapType: format)
        _ = Element.convertFrom(2_000, mapType: format)
    }
    #expect(Element.mapType(for: MapFormat.awd.header) == .awd)
    #expect(Element.mapType(for: "unknown") == nil)
}

@Test("large sprites and legacy conversion fallbacks stay stable")
func largeSpriteAndConversionCoverage() {
    let volcanoPart = Element(AWConstants.makeExtra(8, 0))
    #expect(volcanoPart.simplified == .extraVolcano)
    #expect(volcanoPart.largeOffset()?.x == 1)
    #expect(volcanoPart.largeOffset()?.y == 0)
    #expect(volcanoPart.makeFromLargeOffset(x: 8, y: 0) == Element(AWConstants.makeExtra(15, 0)))
    #expect(volcanoPart.makeFromLargeOffset(x: 0, y: 0) == Element(AWConstants.makeExtra(7, 0)))

    let invalidArmyCity = Element(AWConstants.makeBuilding(1, 6))
    #expect(invalidArmyCity.converted(to: .awm) == AWConstants.makeBuilding(1, 4))

    let invalidArmyHQ = Element(AWConstants.makeBuilding(0, 6))
    #expect(invalidArmyHQ.converted(to: .awm) == AWConstants.makeTerrain(0, 0))

    let unsupportedBuilding = Element(AWConstants.makeBuilding(8, 0))
    #expect(!unsupportedBuilding.isCompatible(with: .awd))
    #expect(unsupportedBuilding.converted(to: .awd) == AWConstants.makeBuilding(1, 0))
}
