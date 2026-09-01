import Foundation
import Testing
@testable import AWEDCore

@Test("metadata tables expose every supported variant")
func metadataTables() {
    for tileset in Tileset.allCases {
        #expect(!tileset.displayName.isEmpty)
        #expect(!tileset.backgroundMusicResourceName.isEmpty)
        #expect(!tileset.playtestRuleset.displayName.isEmpty)
        #expect(!tileset.playtestRuleset.shortName.isEmpty)
        _ = tileset.isFamicomWarsFamily
        _ = tileset.isGameBoyWarsFamily
        _ = tileset.isHistoricalWarsVariant
    }
    for ruleset in PlaytestRuleset.allCases {
        #expect(!ruleset.displayName.isEmpty)
        #expect(!ruleset.shortName.isEmpty)
    }
    for format in MapFormat.allCases {
        #expect(!format.header.isEmpty)
        #expect(format.mapType > 0)
        #expect(!format.displayName.isEmpty)
        _ = format.supportsVariableSize
        #expect(MapFormat(fileExtension: ".\(format.rawValue)") == format)
    }
    #expect(MapFormat(fileExtension: "unknown") == .aws)
    for tab in PaletteTab.allCases {
        #expect(tab.id == tab.rawValue)
        #expect(!tab.displayName.isEmpty)
    }
}

@Test("map fragments preserve underlays, clipping, and safe bounds")
func mapFragmentCoverage() {
    mapFragmentArrayCoverage()
    mapFragmentClippingCoverage()
}

private func mapFragmentArrayCoverage() {
    var map = MapState(width: 4, height: 3, defaultTerrain: .terrainPlain)
    _ = map.setBackground(.terrainBridgeH, atX: 1, y: 1, check: false)
    _ = map.setBackground(.terrainRiver, atX: 1, y: 0, check: false)
    _ = map.setBackground(.buildingPort, atX: 2, y: 1, check: false)
    _ = map.setForeground(.unitTank, atX: 0, y: 0)

    let fragment = MapFragment(map: map, x: 0, y: 0, width: 4, height: 3)
    #expect(fragment.bridgeUnderlayDrawElement(atX: 1, y: 1) == Element(AWConstants.makeTerrain(3, 1)))
    #expect(fragment.buildingUnderlayDrawElement(atX: 2, y: 1) == .terrainShoal)
    #expect(fragment.buildingUnderlayDrawElement(atX: 0, y: 0) == nil)
    #expect(fragment.backgroundElement(atX: -1, y: 0) == .terrainSea)
    #expect(fragment.foregroundElement(atX: 8, y: 8) == .unitEmpty)
    #expect(fragment.backgroundDrawElement(atX: 8, y: 8) == .terrainSea)
}

private func mapFragmentClippingCoverage() {
    var isolated = MapFragment(
        width: 1,
        height: 1,
        background: [.terrainBridgeV],
        backgroundDraw: [.terrainBridgeV],
        foreground: [.unitEmpty]
    )
    #expect(isolated.bridgeUnderlayDrawElement(atX: 0, y: 0) == .terrainSea)
    #expect(isolated.bridgeUnderlayDrawElement(atX: 1, y: 0) == nil)
    isolated.setBackground(.terrainSea, atX: 2, y: 2)
    isolated.setBackgroundDraw(.terrainSea, atX: 2, y: 2)
    isolated.setForeground(.unitTank, atX: 2, y: 2)
    let empty = isolated.clipped(toWidth: -1, height: 4)
    #expect(empty.width == 0)
    #expect(empty.height == 1)
}

@Test("map drawing dispatch covers every road, river, pipe, and shoal mask")
func drawingMaskCoverage() {
    drawingRoadAndRiverMasks()
    drawingShoalMasks()
    drawingPipeMasks()
}

private func drawingRoadAndRiverMasks() {
    for terrain in [Element.terrainRoad, .terrainRiver] {
        for mask in 0..<16 {
            var map = MapState(width: 5, height: 5, defaultTerrain: .terrainSea)
            _ = map.setBackground(terrain, atX: 2, y: 2, check: false)
            let neighbours = [(2, 1), (2, 3), (1, 2), (3, 2)]
            for (offset, point) in neighbours.enumerated() where mask & (1 << offset) != 0 {
                _ = map.setBackground(terrain, atX: point.0, y: point.1, check: false)
            }
            map.updateDraw()
            _ = map.backgroundDrawElement(atX: 2, y: 2)
        }
    }
}

private func drawingShoalMasks() {
    for mask in 0..<16 {
        var map = MapState(width: 5, height: 5, defaultTerrain: .terrainSea)
        _ = map.setBackground(.terrainShoal, atX: 2, y: 2, check: false)
        let neighbours = [(2, 1), (2, 3), (1, 2), (3, 2)]
        for (offset, point) in neighbours.enumerated() where mask & (1 << offset) != 0 {
            _ = map.setBackground(.terrainPlain, atX: point.0, y: point.1, check: false)
        }
        map.updateDraw()
        _ = map.backgroundDrawElement(atX: 2, y: 2)
    }
}

private func drawingPipeMasks() {
    for (element, point) in [
        (Element.terrainPipe, (2, 2)),
        (.terrainSeam, (2, 2)),
        (.terrainPlainD, (2, 2))
    ] {
        var map = MapState(width: 5, height: 5, defaultTerrain: .terrainPlain)
        _ = map.setBackground(element, atX: point.0, y: point.1, check: false)
        for neighbour in [(2, 1), (2, 3), (1, 2), (3, 2)] {
            _ = map.setBackground(.terrainPipe, atX: neighbour.0, y: neighbour.1, check: false)
        }
        map.updateDraw()
        _ = map.backgroundDrawElement(atX: point.0, y: point.1)
    }
}

@Test("map file errors describe malformed and incompatible maps")
func mapFileErrorCoverage() throws {
    let errors: [MapFileError] = [
        .unreadableHeader, .unsupportedHeader, .truncatedFile,
        .invalidDimensions, .incompatibleDimensions, .invalidAWSDimensions, .cannotWrite
    ]
    for error in errors { #expect(error.errorDescription?.isEmpty == false) }

    let directory = FileManager.default.temporaryDirectory
    let missing = directory.appending(path: "awed-missing-\(UUID().uuidString).aws")
    #expect(throws: MapFileError.truncatedFile) { try MapFileCodec.read(from: missing) }

    let malformed = directory.appending(path: "awed-malformed-\(UUID().uuidString).aws")
    defer { try? FileManager.default.removeItem(at: malformed) }
    try Data("not-a-map".utf8).write(to: malformed)
    #expect(throws: MapFileError.truncatedFile) { try MapFileCodec.read(from: malformed) }

    let unsupported = directory.appending(path: "awed-unsupported-\(UUID().uuidString).aws")
    defer { try? FileManager.default.removeItem(at: unsupported) }
    try Data("XXXXXXXXX\0".utf8).write(to: unsupported)
    #expect(throws: MapFileError.unsupportedHeader) { try MapFileCodec.read(from: unsupported) }

    let invalid = directory.appending(path: "awed-invalid-\(UUID().uuidString).aws")
    defer { try? FileManager.default.removeItem(at: invalid) }
    var invalidData = Data("AWSMap001\0".utf8)
    invalidData.append(contentsOf: [0, 1, 0])
    try invalidData.write(to: invalid)
    #expect(throws: MapFileError.invalidDimensions) { try MapFileCodec.read(from: invalid) }

    let map = MapState(width: 1, height: 1)
    let oldURL = directory.appending(path: "awed-incompatible-\(UUID().uuidString).awm")
    #expect(throws: MapFileError.incompatibleDimensions) { try MapFileCodec.write(map, to: oldURL, format: .awm) }
}

@Test("placement boundaries cover unsupported terrain, surfaces, and sprites")
func placementBoundaryCoverage() {
    placementUnknownElements()
    placementTerrainRules()
    placementBridgeRules()
    placementShoalRules()
    placementDiagonalRules()
    placementSeamRules()
}

private func placementUnknownElements() {
    let map = MapState(width: 5, height: 5, defaultTerrain: .terrainSea)
    let unknownTerrain = Element(AWConstants.makeTerrain(29, 9))
    let unknownBuilding = Element(AWConstants.makeBuilding(8, 0))
    let unknownExtra = Element(AWConstants.makeExtra(19, 19))
    #expect(!map.allowPlacement(Element(1_300), atX: 2, y: 2))
    #expect(!map.allowPlacement(unknownTerrain, atX: 2, y: 2))
    #expect(!map.allowPlacement(.terrainBlank, atX: 2, y: 2))
    #expect(map.allowPlacement(unknownBuilding, atX: 2, y: 2))
    #expect(!map.allowPlacement(unknownExtra, atX: 2, y: 2))
}

private func placementTerrainRules() {
    var map = MapState(width: 5, height: 5, defaultTerrain: .terrainSea)
    let unknownUnit = Element(AWConstants.makeUnit(19, 19))
    _ = map.setBackground(.terrainPlain, atX: 2, y: 2, check: false)
    #expect(!map.allowPlacement(.terrainReef, atX: 2, y: 2))
    #expect(!map.allowPlacement(.terrainBridgeH, atX: 2, y: 2))
    #expect(!map.allowPlacement(.terrainShoal, atX: 2, y: 2))
    #expect(!map.allowPlacement(.terrainSeam, atX: 2, y: 2))
    #expect(!map.allowPlacement(unknownUnit, atX: 2, y: 2, recheck: true))
    #expect(map.allowPlacement(.unitEmpty, atX: 2, y: 2, recheck: true))
}

private func placementBridgeRules() {
    var bridge = MapState(width: 3, height: 3, defaultTerrain: .terrainSea)
    _ = bridge.setBackground(.terrainBridgeH, atX: 1, y: 1, check: false)
    _ = bridge.setBackground(.terrainPlain, atX: 1, y: 0, check: false)
    #expect(bridge.allowPlacement(.terrainBridgeH, atX: 1, y: 1, recheck: true))
    _ = bridge.setBackground(.terrainPlain, atX: 1, y: 2, check: false)
    #expect(bridge.allowPlacement(.terrainBridgeH, atX: 1, y: 1, recheck: true) == false)
    _ = bridge.setBackground(.terrainRiver, atX: 1, y: 1, check: false)
    #expect(bridge.allowPlacement(.terrainBridgeH, atX: 1, y: 1, recheck: true))
}

private func placementShoalRules() {
    var shoal = MapState(width: 3, height: 3, defaultTerrain: .terrainSea)
    _ = shoal.setBackground(.terrainShoal, atX: 1, y: 1, check: false)
    #expect(shoal.allowPlacement(.terrainShoal, atX: 1, y: 1, recheck: true) == false)
    for point in [(1, 0), (1, 2), (0, 1), (2, 1)] {
        _ = shoal.setBackground(.terrainPlain, atX: point.0, y: point.1, check: false)
    }
    #expect(shoal.allowPlacement(.terrainShoal, atX: 1, y: 1, recheck: true) == false)
}

private func placementDiagonalRules() {
    var diagonal = MapState(width: 3, height: 3, defaultTerrain: .terrainSea)
    _ = diagonal.setBackground(.terrainShoal, atX: 1, y: 1, check: false)
    _ = diagonal.setBackground(.terrainSea, atX: 1, y: 0, check: false)
    _ = diagonal.setBackground(.terrainPlain, atX: 1, y: 2, check: false)
    _ = diagonal.setBackground(.terrainSea, atX: 0, y: 1, check: false)
    _ = diagonal.setBackground(.terrainSea, atX: 2, y: 1, check: false)
    _ = diagonal.setBackground(.terrainPlain, atX: 0, y: 0, check: false)
    #expect(diagonal.allowPlacement(.terrainShoal, atX: 1, y: 1, recheck: true) == false)
}

private func placementSeamRules() {
    var seam = MapState(width: 3, height: 3, defaultTerrain: .terrainPlain)
    _ = seam.setBackground(.terrainSeam, atX: 1, y: 1, check: false)
    #expect(seam.allowPlacement(.terrainSeam, atX: 1, y: 1, recheck: true))
    _ = seam.setBackground(.terrainPipe, atX: 0, y: 1, check: false)
    #expect(seam.allowPlacement(.terrainSeam, atX: 1, y: 1, recheck: true) == false)
    _ = seam.setBackground(.terrainPipe, atX: 2, y: 1, check: false)
    #expect(seam.allowPlacement(.terrainSeam, atX: 1, y: 1, recheck: true))
}
