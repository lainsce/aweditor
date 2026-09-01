import Foundation
import Testing
@testable import AWEDCore

@Test("element tables preserve the legacy numeric layout")
func elementTables() {
    #expect(Element.terrainPlain.value == 0)
    #expect(Element.terrainSea.value == 60)
    #expect(Element.terrainWood.value == 90)
    #expect(Element.terrainMountain.value == 150)
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

@Test("AWS terrain IDs load with the stable stride and the compact regression stride")
func terrainIDCompatibility() throws {
    let stableURL = try makeTerrainFixture(values: [60, 90, 150])
    defer { try? FileManager.default.removeItem(at: stableURL) }
    let stable = try MapFileCodec.read(from: stableURL)
    #expect(stable.width == 3)
    #expect(stable.height == 1)
    #expect(stable.backgroundElement(atX: 0, y: 0) == .terrainSea)
    #expect(stable.backgroundElement(atX: 1, y: 0) == .terrainWood)
    #expect(stable.backgroundElement(atX: 2, y: 0) == .terrainMountain)

    let compactURL = try makeTerrainFixture(values: [40, 60, 100, 299])
    defer { try? FileManager.default.removeItem(at: compactURL) }
    let compact = try MapFileCodec.read(from: compactURL)
    #expect(compact.backgroundElement(atX: 0, y: 0) == .terrainSea)
    #expect(compact.backgroundElement(atX: 1, y: 0) == .terrainWood)
    #expect(compact.backgroundElement(atX: 2, y: 0) == .terrainMountain)
}

private func makeTerrainFixture(values: [UInt16]) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "awed-terrain-ids-\(UUID().uuidString).aws")
    var data = Data("AWSMap001".utf8)
    data.append(0)
    data.append(UInt8(values.count))
    data.append(1)
    data.append(UInt8(Tileset.normal.rawValue))
    for value in values {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8(value >> 8))
    }
    for _ in values {
        data.append(0xFF)
        data.append(0xFF)
    }
    try data.write(to: url, options: .atomic)
    return url
}

@Test("tilesets select their matching playtest rules")
func playtestRulesetMapping() {
    #expect(Tileset.normal.playtestRuleset == .dualStrike)
    #expect(Tileset.snow.playtestRuleset == .dualStrike)
    #expect(Tileset.desert.playtestRuleset == .dualStrike)
    #expect(Tileset.wasteland.playtestRuleset == .dualStrike)
    #expect(Tileset.aw1.playtestRuleset == .advanceWars)
    #expect(Tileset.aw2.playtestRuleset == .advanceWars2)
    #expect(Tileset.famicomWars.playtestRuleset == .famicomWars)
    #expect(Tileset.gbWars.playtestRuleset == .gameBoyWars)
    #expect(Tileset.superFamicomWars.playtestRuleset == .superFamicomWars)
    #expect(Tileset.gbWars2.playtestRuleset == .gameBoyWars2)
    #expect(Tileset.gbWars3.playtestRuleset == .gameBoyWars3)
    #expect(Tileset.daysOfRuin.playtestRuleset == .daysOfRuin)
    #expect(Tileset.famicomWars.isFamicomWarsFamily)
    #expect(Tileset.superFamicomWars.isFamicomWarsFamily)
    #expect(Tileset.gbWars2.isGameBoyWarsFamily)
    #expect(Tileset.gbWars3.isGameBoyWarsFamily)
    #expect(Tileset.launchOrdered == [
        .famicomWars,
        .gbWars,
        .superFamicomWars,
        .gbWars2,
        .aw1,
        .gbWars3,
        .aw2,
        .normal,
        .snow,
        .desert,
        .wasteland,
        .daysOfRuin
    ])
}

@Test("tilesets select their matching background music")
func backgroundMusicMapping() {
    #expect(Tileset.normal.backgroundMusicResourceName == "design_dual_strike")
    #expect(Tileset.snow.backgroundMusicResourceName == "design_dual_strike")
    #expect(Tileset.desert.backgroundMusicResourceName == "design_dual_strike")
    #expect(Tileset.wasteland.backgroundMusicResourceName == "design_dual_strike")
    #expect(Tileset.aw1.backgroundMusicResourceName == "design_advance_wars_1_2")
    #expect(Tileset.aw2.backgroundMusicResourceName == "design_advance_wars_1_2")
    #expect(Tileset.famicomWars.backgroundMusicResourceName == "design_famicom_wars")
    #expect(Tileset.gbWars.backgroundMusicResourceName == "design_game_boy_wars_1_2")
    #expect(Tileset.superFamicomWars.backgroundMusicResourceName == "design_super_famicom_wars")
    #expect(Tileset.gbWars2.backgroundMusicResourceName == "design_game_boy_wars_1_2")
    #expect(Tileset.daysOfRuin.backgroundMusicResourceName == "design_days_of_ruin")
    #expect(Tileset.gbWars3.backgroundMusicResourceName == "design_game_boy_wars_3")
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

@Test("Super Famicom railroad accepts land and air units but not naval units")
func superFamicomRailroadPlacement() {
    var map = MapState(
        width: 1,
        height: 1,
        tileset: .superFamicomWars,
        defaultTerrain: .terrainPipe
    )

    #expect(map.allowPlacement(.unitInfantry, atX: 0, y: 0))
    #expect(map.allowPlacement(.unitTank, atX: 0, y: 0))
    #expect(map.allowPlacement(.unitFighter, atX: 0, y: 0))
    #expect(!map.allowPlacement(.unitBattleship, atX: 0, y: 0))

    map.tileset = .famicomWars
    #expect(!map.allowPlacement(.unitInfantry, atX: 0, y: 0))
    #expect(!map.allowPlacement(.unitTank, atX: 0, y: 0))
    #expect(!map.allowPlacement(.unitFighter, atX: 0, y: 0))
}

@Test("enclosed sea cells use the legacy draw variant")
func enclosedSeaDrawing() {
    enclosedSeaCellDrawing()
    enclosedSeaChannelDrawing()
    enclosedSeaMouthDrawing()
    enclosedSeaUpperRiverEdgeDrawing()
}

private func enclosedSeaCellDrawing() {
    var map = MapState(width: 3, height: 3, defaultTerrain: .terrainPlain)
    _ = map.setBackground(.terrainSea, atX: 1, y: 1, check: false)
    map.updateDraw()

    #expect(map.backgroundElement(atX: 1, y: 1) == .terrainSea)
    #expect(map.backgroundDrawElement(atX: 1, y: 1) == Element(AWConstants.makeTerrain(7, 0)))
}
private func enclosedSeaChannelDrawing() {
    var channel = MapState(width: 3, height: 4, defaultTerrain: .terrainPlain)
    _ = channel.setBackground(.terrainSea, atX: 1, y: 1, check: false)
    _ = channel.setBackground(.terrainSea, atX: 1, y: 2, check: false)
    channel.updateDraw()
    #expect(channel.backgroundDrawElement(atX: 1, y: 1) == Element(AWConstants.makeTerrain(7, 3)))
    #expect(channel.backgroundDrawElement(atX: 1, y: 2) == Element(AWConstants.makeTerrain(7, 4)))
}
private func enclosedSeaMouthDrawing() {
    var mouth = MapState(width: 4, height: 3, defaultTerrain: .terrainSea)
    _ = mouth.setBackground(.terrainRiver, atX: 2, y: 1, check: false)
    mouth.updateDraw()
    #expect(mouth.backgroundDrawElement(atX: 1, y: 1) == Element(AWConstants.makeTerrain(4, 0)))
}
private func enclosedSeaUpperRiverEdgeDrawing() {
    var upperRiverEdge = MapState(width: 3, height: 4, defaultTerrain: .terrainSea)
    _ = upperRiverEdge.setBackground(.terrainRiver, atX: 1, y: 0, check: false)
    _ = upperRiverEdge.setBackground(.terrainRiver, atX: 1, y: 1, check: false)
    upperRiverEdge.updateDraw()
    #expect(upperRiverEdge.backgroundDrawElement(atX: 1, y: 2) == Element(AWConstants.makeTerrain(4, 3)))
}
@Test("Famicom Wars keeps shoal as its flat cyan tile")
func famicomShoalDrawing() {
    var map = MapState(width: 3, height: 3, tileset: .famicomWars, defaultTerrain: .terrainSea)
    _ = map.setBackground(.terrainPlain, atX: 1, y: 0, check: false)
    _ = map.setBackground(.terrainShoal, atX: 1, y: 1, check: false)
    map.updateDraw()

    #expect(map.backgroundDrawElement(atX: 1, y: 1) == .terrainShoal)
}

@Test("GB Wars keeps flat terrain cells and bridge orientation")
func gbWarsFlatTerrainDrawing() {
    var map = MapState(width: 5, height: 3, tileset: .gbWars, defaultTerrain: .terrainSea)
    _ = map.setBackground(.terrainPlain, atX: 1, y: 1, check: false)
    _ = map.setBackground(.terrainRoad, atX: 2, y: 1, check: false)
    _ = map.setBackground(.terrainBridgeH, atX: 3, y: 1, check: false)
    _ = map.setBackground(.terrainBridgeV, atX: 4, y: 1, check: false)
    _ = map.setBackground(.terrainShoal, atX: 1, y: 2, check: false)
    _ = map.setBackground(.terrainPlainD, atX: 2, y: 2, check: false)
    map.updateDraw()

    #expect(map.backgroundDrawElement(atX: 1, y: 1) == .terrainPlain)
    #expect(map.backgroundDrawElement(atX: 2, y: 1) == .terrainRoad)
    #expect(map.backgroundDrawElement(atX: 3, y: 1) == .terrainBridgeH)
    #expect(map.backgroundDrawElement(atX: 4, y: 1) == .terrainBridgeV)
    #expect(map.backgroundDrawElement(atX: 1, y: 2) == .terrainShoal)
    #expect(map.backgroundDrawElement(atX: 2, y: 2).simplified == .terrainPlainD)
}

@Test("bridges reconstruct a matching water underlay")
func bridgeWaterUnderlay() {
    var riverCrossing = MapState(width: 3, height: 3, defaultTerrain: .terrainPlain)
    _ = riverCrossing.setBackground(.terrainRiver, atX: 1, y: 0, check: false)
    _ = riverCrossing.setBackground(.terrainBridgeH, atX: 1, y: 1, check: false)
    _ = riverCrossing.setBackground(.terrainRiver, atX: 1, y: 2, check: false)
    #expect(
        riverCrossing.bridgeUnderlayDrawElement(atX: 1, y: 1) ==
            Element(AWConstants.makeTerrain(3, 1))
    )

    let coastalCrossing = MapState(width: 1, height: 1, defaultTerrain: .terrainBridgeV)
    #expect(coastalCrossing.bridgeUnderlayDrawElement(atX: 0, y: 0) == .terrainSea)
    #expect(coastalCrossing.bridgeUnderlayDrawElement(atX: -1, y: 0) == nil)
}

@Test("buildings reconstruct their terrain underlay")
func buildingTerrainUnderlay() {
    var map = MapState(width: 3, height: 1, defaultTerrain: .terrainSea)
    _ = map.setBackground(.buildingCity, atX: 0, y: 0, check: false)
    _ = map.setBackground(.buildingPort, atX: 1, y: 0, check: false)

    #expect(map.buildingUnderlayDrawElement(atX: 0, y: 0) == .terrainPlain)
    #expect(map.buildingUnderlayDrawElement(atX: 1, y: 0) == .terrainShoal)
    #expect(map.buildingUnderlayDrawElement(atX: 2, y: 0) == nil)
    #expect(map.buildingUnderlayDrawElement(atX: -1, y: 0) == nil)
}

@Test("neutral HQs normalize to neutral cities")
func neutralHQNormalization() {
    var map = MapState(width: 1, height: 1, defaultTerrain: .terrainSea)
    let neutralHQ = Element.buildingHQ.changedArmy(AWConstants.armyNeutral)

    #expect(neutralHQ == Element.buildingCity.changedArmy(AWConstants.armyNeutral))
    #expect(neutralHQ.simplified == .buildingCity)
    let placed = map.setBackground(neutralHQ, atX: 0, y: 0, check: false)
    #expect(placed)

    let stored = map.backgroundElement(atX: 0, y: 0)
    #expect(stored.simplified == .buildingCity)
    #expect(stored.army == AWConstants.armyNeutral)
}

@Test("mountain ranges sprinkle taller draw-only variants")
func mountainRangeDrawing() {
    isolatedMountainDrawing()
    clusteredMountainDrawing()
    ridgeMountainDrawing()
}

private func isolatedMountainDrawing() {
    var isolated = MapState(width: 1, height: 1, defaultTerrain: .terrainSea)
    _ = isolated.setBackground(.terrainMountain, atX: 0, y: 0, check: false)
    #expect(isolated.backgroundElement(atX: 0, y: 0) == .terrainMountain)
    #expect(isolated.backgroundDrawElement(atX: 0, y: 0) == .terrainMountain)
}
private func clusteredMountainDrawing() {
    var rangeWithMountains = MapState(width: 7, height: 7, defaultTerrain: .terrainSea)
    for x in 1..<6 {
        for y in 1..<6 {
            _ = rangeWithMountains.setBackground(.terrainMountain, atX: x, y: y, check: false)
        }
    }

    let tallMountain = Element(AWConstants.makeTerrain(0, 7))
    var tallCount = 0
    for x in 0..<rangeWithMountains.width {
        for y in 0..<rangeWithMountains.height {
            if rangeWithMountains.backgroundDrawElement(atX: x, y: y) == tallMountain {
                tallCount += 1
            }
        }
    }

    #expect(tallCount > 0)
    #expect(rangeWithMountains.backgroundElement(atX: 3, y: 3) == .terrainMountain)
    #expect(rangeWithMountains.backgroundDrawElement(atX: 3, y: 3).simplified == .terrainMountain)
}
private func ridgeMountainDrawing() {
    let tallMountain = Element(AWConstants.makeTerrain(0, 7))
    var ridge = MapState(width: 3, height: 1, defaultTerrain: .terrainSea)
    _ = ridge.setBackground(.terrainMountain, atX: 0, y: 0, check: false)
    _ = ridge.setBackground(.terrainMountain, atX: 1, y: 0, check: false)
    _ = ridge.setBackground(.terrainMountain, atX: 2, y: 0, check: false)
    #expect(ridge.backgroundDrawElement(atX: 1, y: 0) == tallMountain)
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
    try awsFileRoundTrip()
    try legacyFileRoundTrip()
    try awdFileRoundTrip()
}

private func awsFileRoundTrip() throws {
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
}

private func legacyFileRoundTrip() throws {
    let directory = FileManager.default.temporaryDirectory
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

private func awdFileRoundTrip() throws {
    let directory = FileManager.default.temporaryDirectory
    let awdURL = directory.appending(path: "awed-roundtrip-\(UUID().uuidString).awd")
    defer { try? FileManager.default.removeItem(at: awdURL) }
    var awdMap = MapState(width: 30, height: 20, tileset: .aw2, defaultTerrain: .terrainSea)
    _ = awdMap.setBackground(.terrainPlain, atX: 4, y: 4)
    let awdReport = try MapFileCodec.write(awdMap, to: awdURL)
    #expect(awdReport.format == .awd)
    let awdLoaded = try MapFileCodec.read(from: awdURL)
    #expect(awdLoaded.width == 30)
    #expect(awdLoaded.height == 20)
    #expect(awdLoaded.tileset == .aw2)
    #expect(awdLoaded.backgroundElement(atX: 4, y: 4) == .terrainPlain)
}

@Test("legacy output reports lossy conversions before writing")
func compatibilityWarnings() {
    let map = MapState(width: 40, height: 20, defaultTerrain: .terrainSea)
    let warnings = MapFileCodec.warnings(for: map, format: .aw2)
    #expect(warnings.count == 1)
    #expect(warnings[0].contains("cropped"))

    var unsupported = MapState(width: 30, height: 20, defaultTerrain: .terrainSea)
    _ = unsupported.setBackground(.terrainPipe, atX: 1, y: 1, check: false)
    let unsupportedWarnings = MapFileCodec.warnings(for: unsupported, format: .awm)
    #expect(unsupportedWarnings.count == 1)
    #expect(unsupportedWarnings[0].contains("not available"))
}

@Test("map placement and drawing dispatch cover connected terrain families")
func mapPlacementAndDrawingFamilies() {
    roadMaskFamilies()
    riverMaskFamilies()
    var surfaces = surfaceDrawingFixture()
    surfacePlacementCoverage(surfaces)
    surfaceResizeCoverage(&surfaces)
}

private func roadMaskFamilies() {
    var map = MapState(width: 5, height: 5, defaultTerrain: .terrainSea)
    for mask in 0..<16 {
        let center = (x: 2, y: 2)
        _ = map.setBackground(.terrainRoad, atX: center.x, y: center.y, check: false)
        let neighbours = [
            (x: 2, y: 1), (x: 2, y: 3),
            (x: 1, y: 2), (x: 3, y: 2)
        ]
        for (offset, point) in neighbours.enumerated() where mask & (1 << offset) != 0 {
            _ = map.setBackground(.terrainRoad, atX: point.x, y: point.y, check: false)
        }
        map.updateDraw()
        _ = map.backgroundDrawElement(atX: center.x, y: center.y)
    }
}

private func riverMaskFamilies() {
    for mask in 0..<16 {
        var river = MapState(width: 5, height: 5, defaultTerrain: .terrainPlain)
        _ = river.setBackground(.terrainRiver, atX: 2, y: 2, check: false)
        let neighbours = [
            (x: 2, y: 1), (x: 2, y: 3),
            (x: 1, y: 2), (x: 3, y: 2)
        ]
        for (offset, point) in neighbours.enumerated() where mask & (1 << offset) != 0 {
            _ = river.setBackground(.terrainRiver, atX: point.x, y: point.y, check: false)
        }
        river.updateDraw()
        _ = river.backgroundDrawElement(atX: 2, y: 2)
    }
}

private func surfaceDrawingFixture() -> MapState {
    var surfaces = MapState(width: 7, height: 7, defaultTerrain: .terrainSea)
    for x in 1...5 {
        for y in 1...5 {
            _ = surfaces.setBackground(.terrainPlain, atX: x, y: y, check: false)
        }
    }
    _ = surfaces.setBackground(.terrainShoal, atX: 1, y: 1, check: false)
    _ = surfaces.setBackground(.terrainPipe, atX: 3, y: 3, check: false)
    _ = surfaces.setBackground(.terrainSeam, atX: 3, y: 4, check: false)
    _ = surfaces.setBackground(.terrainPlainD, atX: 4, y: 3, check: false)
    _ = surfaces.setBackground(.terrainBridgeH, atX: 1, y: 3, check: false)
    _ = surfaces.setBackground(.terrainBridgeV, atX: 5, y: 3, check: false)
    _ = surfaces.setBackground(.terrainReef, atX: 0, y: 0, check: false)
    surfaces.updateDraw()
    return surfaces
}

private func surfacePlacementCoverage(_ surfaces: MapState) {
    for element in [Element.unitInfantry, .unitMech, .unitTank, .unitAPC, .unitLander, .unitBattleship, .unitTCopter, .unitPipeRunner, .unitEmpty] {
        _ = surfaces.allowPlacement(element, atX: 3, y: 3, recheck: true)
    }
    for element in [Element.extraMCannonN, .extraBCannons, .extraBCannonN, .extraDeathray, .extraBobelisk, .extraVolcano, .extraFortress, .extraGSilo, .extraBlackArc, .extraSeaArc] {
        _ = surfaces.allowPlacement(element, atX: 2, y: 2)
    }
    _ = surfaces.allowPlacement(.terrainRiver, atX: 2, y: 2)
    _ = surfaces.allowPlacement(.terrainBridgeH, atX: 2, y: 2)
    _ = surfaces.allowPlacement(.terrainShoal, atX: 2, y: 2)
    _ = surfaces.allowPlacement(.terrainSeam, atX: 3, y: 3)
    _ = surfaces.allowPlacement(.buildingHQ.changedArmy(AWConstants.armyNeutral), atX: 2, y: 2)
}

private func surfaceResizeCoverage(_ surfaces: inout MapState) {
    _ = surfaces.setSize(width: 6, height: 6)
    let invalidResize = surfaces.setSize(width: 0, height: 0)
    #expect(!invalidResize)
    surfaces.fill(with: .terrainSea)
    #expect(surfaces.countBuildingsAndSeams() == 0)
    _ = surfaces.compatibleSize(with: .awm)
    _ = surfaces.compatibleElements(with: .awm)
}
