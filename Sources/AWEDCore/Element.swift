import Foundation

/// A tile value from the original editor's terrain/building/unit/extra tables.
/// The numeric layout is part of the on-disk format and is intentionally kept
/// stable in this Swift port.
public struct Element: Hashable, Codable, Sendable {
    public var value: Int

    public init(_ value: Int = 0, mapType: MapFormat? = nil) {
        self.value = mapType.map { Self.convertFrom(value, mapType: $0) } ?? value
    }

    public static let unitEmpty = Element(AWConstants.unitEmpty)
    public static let unitDelete = Element(AWConstants.unitDelete)
    public static let terrainBlank = Element(AWConstants.terrainBlank)

    public static let terrainPlain = Element(AWConstants.makeTerrain(0, 0))
    public static let terrainPlainD = Element(AWConstants.makeTerrain(17, 5))
    public static let terrainWood = Element(AWConstants.makeTerrain(0, 3))
    public static let terrainMountain = Element(AWConstants.makeTerrain(0, 5))
    public static let terrainRoad = Element(AWConstants.makeTerrain(1, 0))
    public static let terrainBridgeH = Element(AWConstants.makeTerrain(2, 0))
    public static let terrainBridgeV = Element(AWConstants.makeTerrain(2, 1))
    public static let terrainRiver = Element(AWConstants.makeTerrain(3, 0))
    public static let terrainPipe = Element(AWConstants.makeTerrain(16, 0))
    public static let terrainSeam = Element(AWConstants.makeTerrain(16, 7))
    public static let terrainShoal = Element(AWConstants.makeTerrain(9, 1))
    public static let terrainSea = Element(AWConstants.makeTerrain(0, 2))
    public static let terrainReef = Element(AWConstants.makeTerrain(0, 1))

    public static let buildingHQ = Element(AWConstants.makeBuilding(0, 0))
    public static let buildingCity = Element(AWConstants.makeBuilding(1, 0))
    public static let buildingBase = Element(AWConstants.makeBuilding(2, 0))
    public static let buildingAirport = Element(AWConstants.makeBuilding(3, 0))
    public static let buildingPort = Element(AWConstants.makeBuilding(4, 0))
    public static let buildingTower = Element(AWConstants.makeBuilding(5, 0))
    public static let buildingLab = Element(AWConstants.makeBuilding(6, 0))
    public static let buildingSilo = Element(AWConstants.makeBuilding(0, 5))

    public static let unitInfantry = Element(AWConstants.makeUnit(0, 0))
    public static let unitMech = Element(AWConstants.makeUnit(0, 1))
    public static let unitTank = Element(AWConstants.makeUnit(1, 1))
    public static let unitMDTank = Element(AWConstants.makeUnit(1, 0))
    public static let unitNeoTank = Element(AWConstants.makeUnit(9, 0))
    public static let unitMegaTank = Element(AWConstants.makeUnit(10, 0))
    public static let unitRecon = Element(AWConstants.makeUnit(2, 0))
    public static let unitAntiAir = Element(AWConstants.makeUnit(4, 0))
    public static let unitMissile = Element(AWConstants.makeUnit(4, 1))
    public static let unitArtillery = Element(AWConstants.makeUnit(3, 0))
    public static let unitRocket = Element(AWConstants.makeUnit(3, 1))
    public static let unitAPC = Element(AWConstants.makeUnit(2, 1))
    public static let unitPipeRunner = Element(AWConstants.makeUnit(11, 0))
    public static let unitOozium = Element(AWConstants.makeUnit(12, 0))
    public static let unitBlackBoat = Element(AWConstants.makeUnit(9, 1))
    public static let unitLander = Element(AWConstants.makeUnit(8, 0))
    public static let unitCruiser = Element(AWConstants.makeUnit(7, 1))
    public static let unitSub = Element(AWConstants.makeUnit(8, 1))
    public static let unitBattleship = Element(AWConstants.makeUnit(7, 0))
    public static let unitCarrier = Element(AWConstants.makeUnit(10, 1))
    public static let unitTCopter = Element(AWConstants.makeUnit(6, 1))
    public static let unitBCopter = Element(AWConstants.makeUnit(6, 0))
    public static let unitFighter = Element(AWConstants.makeUnit(5, 0))
    public static let unitBomber = Element(AWConstants.makeUnit(5, 1))
    public static let unitStealth = Element(AWConstants.makeUnit(11, 1))
    public static let unitBlackBomb = Element(AWConstants.makeUnit(12, 1))

    public static let extraMCannonN = Element(AWConstants.makeExtra(0, 0))
    public static let extraMCannonS = Element(AWConstants.makeExtra(1, 1))
    public static let extraMCannonW = Element(AWConstants.makeExtra(1, 0))
    public static let extraMCannonE = Element(AWConstants.makeExtra(0, 1))
    public static let extraLCannon = Element(AWConstants.makeExtra(2, 0))
    public static let extraBCannons = Element(AWConstants.makeExtra(4, 0))
    public static let extraBCannonN = Element(AWConstants.makeExtra(4, 1))
    public static let extraDeathray = Element(AWConstants.makeExtra(5, 1))
    public static let extraBCrystal = Element(AWConstants.makeExtra(3, 1))
    public static let extraBobelisk = Element(AWConstants.makeExtra(6, 1))
    public static let extraVolcano = Element(AWConstants.makeExtra(6, 2))
    public static let extraFortress = Element(AWConstants.makeExtra(6, 3))
    public static let extraBlackArc = Element(AWConstants.makeExtra(6, 4))
    public static let extraGSilo = Element(AWConstants.makeExtra(6, 6))
    public static let extraSeaArc = Element(AWConstants.makeExtra(6, 7))

    public var x: Int {
        if value == AWConstants.unitDelete { return 0 }
        if isTerrain { return (value - AWConstants.terrainStart) % AWConstants.terrainColumns }
        if isBuilding { return (value - AWConstants.buildingStart) % AWConstants.buildingColumns }
        if isUnit { return (value - AWConstants.unitStart) % AWConstants.unitColumns }
        if isExtra { return (value - AWConstants.extraStart) % AWConstants.extraColumns }
        return 0
    }

    public var y: Int {
        if value == AWConstants.unitDelete { return 4 }
        if isTerrain { return (value - AWConstants.terrainStart) / AWConstants.terrainColumns }
        if isBuilding { return (value - AWConstants.buildingStart) / AWConstants.buildingColumns }
        if isUnit { return (value - AWConstants.unitStart) / AWConstants.unitColumns }
        if isExtra { return (value - AWConstants.extraStart) / AWConstants.extraColumns }
        return 0
    }

    public var isTerrain: Bool {
        (AWConstants.terrainStart...AWConstants.terrainEnd).contains(value) || value == AWConstants.terrainBlank
    }

    public var isBuilding: Bool {
        (AWConstants.buildingStart...AWConstants.buildingEnd).contains(value)
    }

    public var isUnit: Bool {
        (AWConstants.unitStart...AWConstants.unitEnd).contains(value) || value == AWConstants.unitEmpty || value == AWConstants.unitDelete
    }

    public var isExtra: Bool {
        (AWConstants.extraStart...AWConstants.extraEnd).contains(value)
    }

    public var isBackground: Bool { isTerrain || isBuilding || isExtra }
    public var isForeground: Bool { isUnit }
    public var isUnitNonEmpty: Bool { (AWConstants.unitStart...AWConstants.unitEnd).contains(value) }

    public var doubleHeight: Bool {
        isBuilding || value == AWConstants.makeTerrain(0, 7) || value == Self.extraBCrystal.value ||
            value == Self.extraDeathray.value || value == Self.extraGSilo.value
    }

    public var spritesheet: SpriteSheetKind {
        if isTerrain || value == AWConstants.unitDelete { return .terrain }
        if isBuilding { return .building }
        if isUnit { return .unit }
        if isExtra { return .extra }
        return .terrain
    }

    public var drawX: Int { x }
    /// Y coordinate in a sprite sheet. The legacy editor stores buildings as
    /// two-row sprites, so their sheet rows advance by two rather than using
    /// the terrain/unit one-row offset.
    public var drawY: Int {
        guard doubleHeight else { return y }
        if isBuilding { return y * 2 }
        return y - 1
    }
    public var drawable: Bool { value != AWConstants.terrainBlank && (isTerrain || isBuilding || isExtra || isUnitNonEmpty || value == AWConstants.unitDelete) }

    public var size: Int {
        guard isExtra else { return 1 }
        switch simplified.value {
        case Self.extraBCannonN.value, Self.extraBCannons.value, Self.extraDeathray.value, Self.extraBobelisk.value: return 3
        case Self.extraVolcano.value, Self.extraFortress.value, Self.extraGSilo.value, Self.extraBlackArc.value, Self.extraSeaArc.value: return 4
        default: return 1
        }
    }

    public var topLeft: Int {
        guard size > 1 else { return value }
        switch simplified.value {
        case Self.extraBCannons.value: return AWConstants.makeExtra(0, 2)
        case Self.extraBCannonN.value: return AWConstants.makeExtra(3, 2)
        case Self.extraDeathray.value: return AWConstants.makeExtra(0, 5)
        case Self.extraBobelisk.value: return AWConstants.makeExtra(3, 5)
        case Self.extraVolcano.value: return AWConstants.makeExtra(7, 0)
        case Self.extraGSilo.value: return AWConstants.makeExtra(11, 0)
        case Self.extraFortress.value: return AWConstants.makeExtra(7, 4)
        case Self.extraBlackArc.value: return AWConstants.makeExtra(11, 4)
        case Self.extraSeaArc.value: return AWConstants.makeExtra(15, 4)
        default: return value
        }
    }

    public func largeOffset() -> (x: Int, y: Int)? {
        guard size > 1, self != simplified else { return nil }
        let difference = value - topLeft
        return (difference % AWConstants.extraColumns, difference / AWConstants.extraColumns)
    }

    public func makeFromLargeOffset(x: Int, y: Int) -> Element {
        guard size > 1, self != simplified else { return self }
        let base = Element(topLeft).value - AWConstants.extraStart
        let newX = x + base % AWConstants.extraColumns
        let newY = y + base / AWConstants.extraColumns
        return Element(AWConstants.makeExtra(newX, newY))
    }

    public var army: Int {
        if isUnitNonEmpty { return ((value - AWConstants.unitStart) / AWConstants.unitColumns) / 2 }
        if isBuilding { return (value - AWConstants.buildingStart) / AWConstants.buildingColumns }
        return 0
    }

    public func changedArmy(_ newArmy: Int) -> Element {
        var copy = self
        guard (isUnitNonEmpty && (0..<AWConstants.playableArmies).contains(newArmy)) ||
                (isBuilding && (0...AWConstants.armyNeutral).contains(newArmy)) else { return copy }
        if isUnitNonEmpty { copy.value = simplified.value + newArmy * AWConstants.unitColumns * 2 }
        if isBuilding { copy.value = simplified.value + newArmy * AWConstants.buildingColumns }
        return copy
    }

    public var simplified: Element {
        if isTerrain || isExtra {
            switch value {
            case AWConstants.makeTerrain(0, 0): return .terrainPlain
            case AWConstants.makeTerrain(17, 5), AWConstants.makeTerrain(17, 6), AWConstants.makeTerrain(17, 7): return .terrainPlainD
            case AWConstants.makeTerrain(0, 3), AWConstants.makeTerrain(15, 6): return .terrainWood
            case AWConstants.makeTerrain(0, 5), AWConstants.makeTerrain(0, 7): return .terrainMountain
            case AWConstants.makeTerrain(1, 0), AWConstants.makeTerrain(1, 1), AWConstants.makeTerrain(1, 2), AWConstants.makeTerrain(1, 4), AWConstants.makeTerrain(1, 5), AWConstants.makeTerrain(1, 6), AWConstants.makeTerrain(1, 7), AWConstants.makeTerrain(2, 4), AWConstants.makeTerrain(2, 5), AWConstants.makeTerrain(2, 6), AWConstants.makeTerrain(2, 7), AWConstants.makeTerrain(15, 2), AWConstants.makeTerrain(15, 3): return .terrainRoad
            case AWConstants.makeTerrain(2, 0), AWConstants.makeTerrain(2, 1): return .terrainBridgeH
            case AWConstants.makeTerrain(3, 0), AWConstants.makeTerrain(3, 1), AWConstants.makeTerrain(3, 2), AWConstants.makeTerrain(3, 4), AWConstants.makeTerrain(3, 5), AWConstants.makeTerrain(3, 6), AWConstants.makeTerrain(3, 7), AWConstants.makeTerrain(4, 0), AWConstants.makeTerrain(4, 1), AWConstants.makeTerrain(4, 2), AWConstants.makeTerrain(4, 3), AWConstants.makeTerrain(4, 4), AWConstants.makeTerrain(4, 5), AWConstants.makeTerrain(4, 6), AWConstants.makeTerrain(4, 7): return .terrainRiver
            case AWConstants.makeTerrain(16, 0), AWConstants.makeTerrain(16, 1), AWConstants.makeTerrain(16, 2), AWConstants.makeTerrain(16, 3), AWConstants.makeTerrain(16, 4), AWConstants.makeTerrain(16, 5), AWConstants.makeTerrain(17, 0), AWConstants.makeTerrain(17, 1), AWConstants.makeTerrain(17, 2), AWConstants.makeTerrain(17, 3): return .terrainPipe
            case AWConstants.makeTerrain(16, 6), AWConstants.makeTerrain(16, 7): return .terrainSeam
            case AWConstants.makeTerrain(9, 0)...AWConstants.makeTerrain(14, 7):
                // Shoal graphics occupy columns 9–12 for all rows and columns 13–14
                // only for the first four rows of the source sheet.
                if ((9...12).contains(x) && (0...7).contains(y)) || ((13...14).contains(x) && (0...3).contains(y)) {
                    return .terrainShoal
                }
            case AWConstants.makeTerrain(0, 2), AWConstants.makeTerrain(7, 0), AWConstants.makeTerrain(7, 1), AWConstants.makeTerrain(7, 2), AWConstants.makeTerrain(7, 3), AWConstants.makeTerrain(7, 4): return .terrainSea
            case AWConstants.makeTerrain(0, 1): return .terrainReef
            default: break
            }

            // Extra sprites occupy rectangular regions in a 20-column sheet.
            // Comparing their flattened integer ranges is incorrect because
            // adjacent rows overlap (for example, Sea Arc and Fortress).
            // Match the original editor's x/y rectangles instead.
            if isExtra {
                if (0...2).contains(x) && (2...4).contains(y) { return .extraBCannons }
                if (3...5).contains(x) && (2...4).contains(y) { return .extraBCannonN }
                if (0...2).contains(x) && (5...7).contains(y) { return .extraDeathray }
                if (3...5).contains(x) && (5...7).contains(y) { return .extraBobelisk }
                if (7...10).contains(x) && (0...3).contains(y) { return .extraVolcano }
                if (7...10).contains(x) && (4...7).contains(y) { return .extraFortress }
                if (11...14).contains(x) && (0...3).contains(y) { return .extraGSilo }
                if (11...14).contains(x) && (4...7).contains(y) { return .extraBlackArc }
                if (15...18).contains(x) && (4...7).contains(y) { return .extraSeaArc }
            }
        }

        if isBuilding, value != Self.buildingSilo.value {
            return Element(AWConstants.makeBuilding(x, 0))
        }
        if isUnitNonEmpty {
            return Element(AWConstants.makeUnit((value - AWConstants.unitStart) % AWConstants.unitColumns, (value - AWConstants.unitStart) / AWConstants.unitColumns % 2))
        }
        return self
    }

    public var base: Element { isSea ? .terrainSea : .terrainPlain }

    public func nextSprite() -> Element {
        guard isTerrain else { return self }
        let simple = simplified
        var next = self
        repeat {
            next.value += 1
            if next.value > AWConstants.terrainEnd { next.value = AWConstants.terrainStart }
        } while next.simplified != simple && next != self
        return next
    }

    public var isLand: Bool {
        guard isBackground else { return false }
        switch simplified.value {
        case Self.terrainBridgeH.value, Self.terrainSea.value, Self.terrainShoal.value, Self.terrainReef.value, Self.extraSeaArc.value: return false
        default: return true
        }
    }

    public var isSea: Bool {
        guard isBackground else { return false }
        switch simplified.value {
        case Self.terrainBridgeH.value, Self.terrainSea.value, Self.terrainShoal.value, Self.terrainReef.value, Self.extraSeaArc.value: return true
        default: return false
        }
    }

    public var isPipe: Bool { isTerrain && (simplified == .terrainPipe || simplified == .terrainSeam) }
    public var isRoad: Bool {
        isTerrain && (simplified == .terrainRoad || simplified == .terrainBridgeH || simplified == .terrainBridgeV)
    }
    public var isRiver: Bool {
        isTerrain && (simplified == .terrainRiver || simplified == .terrainBridgeH || simplified == .terrainBridgeV)
    }

    public func isCompatible(with format: MapFormat) -> Bool {
        guard format != .aws else { return true }
        if isTerrain {
            if simplified == .terrainPlain || simplified == .terrainWood || simplified == .terrainMountain || simplified == .terrainRoad || simplified == .terrainBridgeH || simplified == .terrainRiver || simplified == .terrainSea || simplified == .terrainShoal || simplified == .terrainReef { return true }
            if simplified == .terrainPlainD && format == .awd { return true }
            if simplified == .terrainPipe || simplified == .terrainSeam { return format != .awm }
            return false
        }
        if isBuilding {
            guard (0...AWConstants.armyNeutral).contains(army), !(army == AWConstants.armyBlackHole && format == .awm) else { return false }
            if [.buildingHQ, .buildingCity, .buildingBase, .buildingAirport, .buildingPort].contains(simplified) { return true }
            if simplified == .buildingTower || simplified == .buildingLab { return format == .awd }
            if simplified == .buildingSilo { return format != .awm }
            return false
        }
        if isExtra {
            return format == .awd
        }
        if isUnit {
            guard isUnitNonEmpty else { return true }
            guard (0..<AWConstants.playableArmies).contains(army), !(army == AWConstants.armyBlackHole && format == .awm) else { return false }
            switch simplified.value {
            case Self.unitNeoTank.value: return format != .awm
            case Self.unitMegaTank.value, Self.unitPipeRunner.value, Self.unitOozium.value, Self.unitBlackBoat.value, Self.unitCarrier.value, Self.unitStealth.value, Self.unitBlackBomb.value: return format == .awd
            default: return true
            }
        }
        return false
    }

    public func converted(to format: MapFormat) -> Int {
        guard format != .aws else { return value }
        let oldTerrainStart = 0
        let oldBuildingStart = 300
        let oldUnitStart = 500
        let oldExtraStart = 900
        if isTerrain {
            let simple = simplified
            if simple.isCompatible(with: format) { return oldTerrainStart + simple.x + simple.y * AWConstants.terrainColumns }
            if simple.isSea { return oldTerrainStart + Element.terrainSea.x + Element.terrainSea.y * AWConstants.terrainColumns }
            if simple.isPipe && format != .awm { return oldTerrainStart + Element.terrainPipe.x + Element.terrainPipe.y * AWConstants.terrainColumns }
            if simple.isRiver { return oldTerrainStart + Element.terrainRiver.x + Element.terrainRiver.y * AWConstants.terrainColumns }
            if simple.isRoad { return oldTerrainStart + Element.terrainRoad.x + Element.terrainRoad.y * AWConstants.terrainColumns }
            return oldTerrainStart + Element.terrainPlain.x + Element.terrainPlain.y * AWConstants.terrainColumns
        }
        if isBuilding {
            var armyValue = army
            if armyValue < 0 || armyValue > AWConstants.armyNeutral || (armyValue == AWConstants.armyBlackHole && format == .awm) { armyValue = AWConstants.armyNeutral }
            let simple = simplified
            if isCompatible(with: format) {
                let neutralRow = format == .awm ? 4 : 5
                let row = armyValue == AWConstants.armyNeutral ? neutralRow : armyValue
                return oldBuildingStart + x + row * AWConstants.buildingColumns
            }
            // An otherwise-supported building with an unsupported army keeps
            // its type where possible. HQs cannot be represented for that
            // army in old formats, so the legacy editor saved plain terrain.
            if simple.isCompatible(with: format) {
                if simple == .buildingHQ {
                    return oldTerrainStart + Element.terrainPlain.x + Element.terrainPlain.y * AWConstants.terrainColumns
                }
                let neutralRow = format == .awm ? 4 : 5
                let row = armyValue == AWConstants.armyNeutral ? neutralRow : simple.y
                return oldBuildingStart + simple.x + row * AWConstants.buildingColumns
            }
            let fallback = Element.buildingCity.changedArmy(armyValue)
            let neutralRow = format == .awm ? 4 : 5
            let row = armyValue == AWConstants.armyNeutral ? neutralRow : fallback.y
            return oldBuildingStart + fallback.x + row * AWConstants.buildingColumns
        }
        if isExtra {
            if isCompatible(with: format) { return oldExtraStart + x + y * AWConstants.extraColumns }
            let fallback = format == .awm ? Element.terrainPlain : Element.terrainPipe
            return fallback.x + fallback.y * AWConstants.terrainColumns
        }
        if isUnit {
            if value == AWConstants.unitEmpty { return AWConstants.unitEmpty }
            return isCompatible(with: format) ? oldUnitStart + x + y * AWConstants.unitColumns : AWConstants.unitEmpty
        }
        return value
    }

    public static func convertFrom(_ value: Int, mapType: MapFormat) -> Int {
        guard mapType != .aws else { return value }
        if (0...299).contains(value) { return AWConstants.makeTerrain(value % 30, value / 30) }
        if (300...499).contains(value) {
            let offset = value - 300
            var row = offset / 10
            let neutralRow = mapType == .awm ? 4 : 5
            if row == neutralRow { row = AWConstants.armyNeutral }
            return AWConstants.makeBuilding(offset % 10, row)
        }
        if (900...1299).contains(value) { return AWConstants.makeExtra((value - 900) % 20, (value - 900) / 20) }
        if (500...899).contains(value) { return AWConstants.makeUnit((value - 500) % 20, (value - 500) / 20) }
        if value == AWConstants.unitEmpty { return AWConstants.unitEmpty }
        return 0
    }

    public static func mapType(for header: String) -> MapFormat? {
        MapFormat.allCases.first { $0.header == header }
    }
}

public enum SpriteSheetKind: String, Codable, Sendable {
    case terrain
    case building
    case unit
    case extra
}
