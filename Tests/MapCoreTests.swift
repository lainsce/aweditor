import Foundation
import Testing
@testable import AWEDCore

@Test("element tables preserve the legacy numeric layout")
func elementTables() {
    #expect(Element.terrainPlain.value == 0)
    #expect(Element.buildingCity.value == 301)
    #expect(Element.unitInfantry.value == 500)
    #expect(Element.extraVolcano.value == 946)
    #expect(Element.extraSeaArc.simplified == .extraSeaArc)
    #expect(Element(AWConstants.makeExtra(7, 4)).simplified == .extraFortress)
    #expect(Element(AWConstants.makeExtra(11, 4)).simplified == .extraBlackArc)
    #expect(Element(AWConstants.makeExtra(15, 4)).simplified == .extraSeaArc)
    #expect(Element.buildingCity.changedArmy(AWConstants.armyBlackHole).army == AWConstants.armyBlackHole)
    #expect(Element.unitTank.changedArmy(AWConstants.armyGreenEarth).army == AWConstants.armyGreenEarth)
    #expect(Element.buildingCity.drawY == 0)
    #expect(Element.buildingCity.changedArmy(AWConstants.armyBlueMoon).drawY == 2)
}

@Test("tilesets select their matching playtest rules")
func playtestRulesetMapping() {
    #expect(Tileset.normal.playtestRuleset == .dualStrike)
    #expect(Tileset.snow.playtestRuleset == .dualStrike)
    #expect(Tileset.desert.playtestRuleset == .dualStrike)
    #expect(Tileset.wasteland.playtestRuleset == .dualStrike)
    #expect(Tileset.aw1.playtestRuleset == .advanceWars)
    #expect(Tileset.aw2.playtestRuleset == .advanceWars2)
}

@Test("map defaults, placement rules, and drawing variants")
func mapEditingRules() {
    var map = MapState(width: 4, height: 3, defaultTerrain: .terrainSea)
    #expect(map.backgroundElement(atX: 0, y: 0) == .terrainSea)
    let placedPlain = map.setBackground(.terrainPlain, atX: 0, y: 0)
    #expect(placedPlain)
    let placedBattleship = map.setForeground(.unitBattleship, atX: 0, y: 0)
    #expect(!placedBattleship)
    let placedInfantry = map.setForeground(.unitInfantry, atX: 0, y: 0)
    #expect(placedInfantry)
    #expect(map.foregroundElement(atX: 0, y: 0) == .unitInfantry)
    let placedRoad = map.setBackground(.terrainRoad, atX: 1, y: 0)
    #expect(placedRoad)
    #expect(map.backgroundDrawElement(atX: 1, y: 0).isTerrain)

    let fragment = MapFragment(map: map, x: 0, y: 0, width: 4, height: 3)
    let clipped = fragment.clipped(toWidth: 2, height: 2)
    #expect(clipped.width == 2)
    #expect(clipped.height == 2)
    #expect(clipped.backgroundElement(atX: 0, y: 0) == .terrainPlain)
}

@Test("bridge, shoal, and port placement keeps land and naval units separate")
func movementSurfacePlacement() {
    var map = MapState(width: 4, height: 1, defaultTerrain: .terrainPlain)
    _ = map.setBackground(.terrainShoal, atX: 0, y: 0, check: false)
    _ = map.setBackground(.terrainBridgeH, atX: 1, y: 0, check: false)
    _ = map.setBackground(.buildingPort, atX: 2, y: 0, check: false)
    _ = map.setBackground(.terrainSea, atX: 3, y: 0, check: false)

    #expect(map.allowPlacement(.unitInfantry, atX: 0, y: 0))
    #expect(map.allowPlacement(.unitTank, atX: 0, y: 0))
    #expect(map.allowPlacement(.unitInfantry, atX: 1, y: 0))
    #expect(!map.allowPlacement(.unitLander, atX: 1, y: 0))
    #expect(map.allowPlacement(.unitLander, atX: 2, y: 0))
    #expect(!map.allowPlacement(.unitTank, atX: 3, y: 0))

    var river = MapState(width: 3, height: 1, defaultTerrain: .terrainPlain)
    _ = river.setBackground(.terrainRiver, atX: 1, y: 0, check: false)
    #expect(river.allowPlacement(.unitInfantry, atX: 1, y: 0))
    #expect(river.allowPlacement(.unitMech, atX: 1, y: 0))
    #expect(!river.allowPlacement(.unitTank, atX: 1, y: 0))
    #expect(!river.allowPlacement(.unitOozium, atX: 1, y: 0))
}

@Test("enclosed sea cells use the legacy draw variant")
func enclosedSeaDrawing() {
    var map = MapState(width: 3, height: 3, defaultTerrain: .terrainPlain)
    _ = map.setBackground(.terrainSea, atX: 1, y: 1, check: false)
    map.updateDraw()

    #expect(map.backgroundElement(atX: 1, y: 1) == .terrainSea)
    #expect(map.backgroundDrawElement(atX: 1, y: 1) == Element(AWConstants.makeTerrain(7, 0)))

    var channel = MapState(width: 3, height: 4, defaultTerrain: .terrainPlain)
    _ = channel.setBackground(.terrainSea, atX: 1, y: 1, check: false)
    _ = channel.setBackground(.terrainSea, atX: 1, y: 2, check: false)
    channel.updateDraw()
    #expect(channel.backgroundDrawElement(atX: 1, y: 1) == Element(AWConstants.makeTerrain(7, 3)))
    #expect(channel.backgroundDrawElement(atX: 1, y: 2) == Element(AWConstants.makeTerrain(7, 4)))

    var mouth = MapState(width: 4, height: 3, defaultTerrain: .terrainSea)
    _ = mouth.setBackground(.terrainRiver, atX: 2, y: 1, check: false)
    mouth.updateDraw()
    #expect(mouth.backgroundDrawElement(atX: 1, y: 1) == Element(AWConstants.makeTerrain(4, 0)))
}

@Test("sea arc placement checks the complete legacy footprint")
func seaArcPlacement() {
    var map = MapState(width: 10, height: 10, defaultTerrain: .terrainSea)
    // The selectable Sea Arc is placed at its centre; the original editor
    // checks a one-tile margin around the resulting four-by-four sprite.
    _ = map.setBackground(.terrainPlain, atX: 8, y: 4, check: false)
    #expect(map.allowPlacement(.extraSeaArc, atX: 4, y: 4))

    _ = map.setBackground(.terrainPlain, atX: 7, y: 4, check: false)
    #expect(map.allowPlacement(.extraSeaArc, atX: 4, y: 4) == false)
}

@Test("AWS and legacy map files round-trip metadata and tiles")
func fileRoundTrip() throws {
    var map = MapState(width: 3, height: 2, tileset: .desert, defaultTerrain: .terrainSea, defaultAuthor: "Tester")
    map.setName("Round trip")
    map.setAuthor("Map author")
    map.setDescription("A small map")
    let placedPlain = map.setBackground(.terrainPlain, atX: 1, y: 0)
    #expect(placedPlain)
    let placedUnit = map.setForeground(.unitInfantry.changedArmy(AWConstants.armyBlueMoon), atX: 1, y: 0)
    #expect(placedUnit)

    let directory = FileManager.default.temporaryDirectory
    let awsURL = directory.appending(path: "awed-roundtrip-\(UUID().uuidString).aws")
    defer { try? FileManager.default.removeItem(at: awsURL) }
    _ = try MapFileCodec.write(map, to: awsURL)
    let loaded = try MapFileCodec.read(from: awsURL)
    #expect(loaded.width == 3)
    #expect(loaded.height == 2)
    #expect(loaded.tileset == .desert)
    #expect(loaded.name == "Round trip")
    #expect(loaded.author == "Map author")
    #expect(loaded.backgroundElement(atX: 1, y: 0) == .terrainPlain)
    #expect(loaded.foregroundElement(atX: 1, y: 0).army == AWConstants.armyBlueMoon)

    let oldURL = directory.appending(path: "awed-roundtrip-\(UUID().uuidString).awm")
    defer { try? FileManager.default.removeItem(at: oldURL) }
    var legacy = MapState(width: 30, height: 20, defaultTerrain: .terrainPlain)
    _ = legacy.setForeground(.unitInfantry, atX: 2, y: 2)
    let report = try MapFileCodec.write(legacy, to: oldURL)
    #expect(report.format == .awm)
    let oldLoaded = try MapFileCodec.read(from: oldURL)
    #expect(oldLoaded.width == 30)
    #expect(oldLoaded.height == 20)
    #expect(oldLoaded.tileset == .aw1)
    #expect(oldLoaded.foregroundElement(atX: 2, y: 2) == .unitInfantry)
}

@Test("legacy output reports lossy conversions before writing")
func compatibilityWarnings() {
    let map = MapState(width: 40, height: 20, defaultTerrain: .terrainSea)
    let warnings = MapFileCodec.warnings(for: map, format: .aw2)
    #expect(warnings.count == 1)
    #expect(warnings[0].contains("cropped"))
}
