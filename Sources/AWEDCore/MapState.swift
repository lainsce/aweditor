import Foundation

public struct MapState: Codable, Equatable, Sendable {
    public private(set) var background: [Element]
    public private(set) var backgroundDraw: [Element]
    public private(set) var foreground: [Element]

    public private(set) var width: Int
    public private(set) var height: Int
    public var tileset: Tileset
    public var name: String
    public var author: String
    public var description: String
    public private(set) var isDirty: Bool

    public init(
        width: Int = AWConstants.mapDefaultWidth,
        height: Int = AWConstants.mapDefaultHeight,
        tileset: Tileset = .normal,
        defaultTerrain: Element = .terrainSea,
        defaultAuthor: String = "[unknown]"
    ) {
        let safeWidth = min(max(width, AWConstants.mapMinimumWidth), AWConstants.mapMaximumWidth)
        let safeHeight = min(max(height, AWConstants.mapMinimumHeight), AWConstants.mapMaximumHeight)
        self.width = safeWidth
        self.height = safeHeight
        self.tileset = tileset
        self.name = "[untitled]"
        self.author = String(defaultAuthor.prefix(AWConstants.authorMaximumLength))
        self.description = ""
        let count = safeWidth * safeHeight
        self.background = Array(repeating: defaultTerrain, count: count)
        self.backgroundDraw = Array(repeating: defaultTerrain, count: count)
        self.foreground = Array(repeating: .unitEmpty, count: count)
        self.isDirty = false
        updateDraw()
    }

    public func backgroundElement(atX x: Int, y: Int) -> Element {
        guard isValid(x: x, y: y) else { return .terrainSea }
        return background[index(x: x, y: y)]
    }

    public func backgroundDrawElement(atX x: Int, y: Int) -> Element {
        guard isValid(x: x, y: y) else { return .terrainSea }
        return backgroundDraw[index(x: x, y: y)]
    }

    /// The bridge atlas cells are transparent overlays. Reconstruct the water
    /// plate beneath them from neighbouring river tiles, falling back to sea
    /// for coastal bridges and isolated legacy/imported bridge cells.
    public func bridgeUnderlayDrawElement(atX x: Int, y: Int) -> Element? {
        let bridge = backgroundElement(atX: x, y: y)
        guard bridge == .terrainBridgeH || bridge == .terrainBridgeV else { return nil }
        let neighbours = [
            backgroundElement(atX: x, y: y - 1),
            backgroundElement(atX: x, y: y + 1),
            backgroundElement(atX: x - 1, y: y),
            backgroundElement(atX: x + 1, y: y),
        ]
        guard neighbours.contains(where: { $0.simplified == .terrainRiver }) else {
            return .terrainSea
        }
        // A horizontal bridge crosses the vertical river sprite and vice
        // versa. GB-family flat river sheets safely map either slot to their
        // one maintained river cell.
        return bridge == .terrainBridgeH
            ? Element(AWConstants.makeTerrain(3, 1))
            : .terrainRiver
    }

    /// Building artwork is composited over terrain rather than carrying an
    /// opaque plate. Ports sit in shoal water; every other property stands on
    /// the artstyle's plains tile.
    public func buildingUnderlayDrawElement(atX x: Int, y: Int) -> Element? {
        let building = backgroundElement(atX: x, y: y)
        guard building.isBuilding else { return nil }
        return building.simplified == .buildingPort ? .terrainShoal : .terrainPlain
    }

    public func foregroundElement(atX x: Int, y: Int) -> Element {
        guard isValid(x: x, y: y) else { return .unitEmpty }
        return foreground[index(x: x, y: y)]
    }

    public mutating func setName(_ value: String) {
        name = String(value.prefix(AWConstants.nameMaximumLength))
        isDirty = true
    }

    public mutating func setAuthor(_ value: String) {
        author = String(value.prefix(AWConstants.authorMaximumLength))
        isDirty = true
    }

    public mutating func setDescription(_ value: String) {
        description = String(value.prefix(AWConstants.descriptionMaximumLength))
        isDirty = true
    }

    public mutating func setDirty(_ dirty: Bool = true) {
        isDirty = dirty
    }

    @discardableResult
    public mutating func setBackground(_ element: Element, atX x: Int, y: Int, check: Bool = true) -> Bool {
        guard isValid(x: x, y: y), !check || allowPlacement(element, atX: x, y: y) else { return false }
        background[index(x: x, y: y)] = element
        updateDraw(x: x - 2, y: y - 2, width: 5, height: 5)
        isDirty = true
        return true
    }

    @discardableResult
    public mutating func setForeground(_ element: Element, atX x: Int, y: Int) -> Bool {
        guard isValid(x: x, y: y), allowPlacement(element, atX: x, y: y) else { return false }
        foreground[index(x: x, y: y)] = element
        isDirty = true
        return true
    }

    public func allowPlacement(_ element: Element, atX x: Int, y: Int, recheck: Bool = false) -> Bool {
        if element.isForeground {
            if (!recheck && element == foregroundElement(atX: x, y: y)) || element == .unitEmpty { return true }
        }
        if element.isBackground, !recheck, element == backgroundElement(atX: x, y: y) { return true }

        if element.isTerrain {
            switch element.simplified.value {
            case Element.terrainPlain.value, Element.terrainPlainD.value, Element.terrainWood.value,
                 Element.terrainMountain.value, Element.terrainRoad.value, Element.terrainPipe.value,
                 Element.terrainSea.value:
                return true
            case AWConstants.terrainBlank:
                return false
            case Element.terrainRiver.value:
                let up = backgroundElement(atX: x, y: y - 1)
                let down = backgroundElement(atX: x, y: y + 1)
                let left = backgroundElement(atX: x - 1, y: y)
                let right = backgroundElement(atX: x + 1, y: y)
                if left.isRiver && backgroundElement(atX: x - 1, y: y - 1).isRiver && up.isRiver { return false }
                if up.isRiver && backgroundElement(atX: x + 1, y: y - 1).isRiver && right.isRiver { return false }
                if right.isRiver && backgroundElement(atX: x + 1, y: y + 1).isRiver && down.isRiver { return false }
                if down.isRiver && backgroundElement(atX: x - 1, y: y + 1).isRiver && left.isRiver { return false }
                return true
            case Element.terrainBridgeH.value:
                let current = backgroundElement(atX: x, y: y)
                if current.simplified == .terrainRiver { return true }
                if current.isSea {
                    let up = backgroundElement(atX: x, y: y - 1)
                    let down = backgroundElement(atX: x, y: y + 1)
                    let left = backgroundElement(atX: x - 1, y: y)
                    let right = backgroundElement(atX: x + 1, y: y)
                    if (left.isLand && up.isLand) || (up.isLand && right.isLand) || (right.isLand && down.isLand) || (down.isLand && left.isLand) { return false }
                    return left.isLand || up.isLand || right.isLand || down.isLand ||
                        left == .terrainBridgeH || right == .terrainBridgeH || up == .terrainBridgeV || down == .terrainBridgeV
                }
                return false
            case Element.terrainReef.value:
                return backgroundElement(atX: x, y: y).isSea
            case Element.terrainShoal.value:
                let up = backgroundElement(atX: x, y: y - 1)
                let down = backgroundElement(atX: x, y: y + 1)
                let left = backgroundElement(atX: x - 1, y: y)
                let right = backgroundElement(atX: x + 1, y: y)
                if up.isSea && down.isSea && left.isSea && right.isSea { return false }
                if up.isLand && down.isLand && left.isLand && right.isLand { return false }
                if left.isLand && right.isLand && up.isSea && down.isSea { return false }
                if left.isSea && right.isSea && up.isLand && down.isLand { return false }
                if backgroundElement(atX: x - 1, y: y - 1).isLand && left.isSea && up.isSea { return false }
                if backgroundElement(atX: x + 1, y: y - 1).isLand && right.isSea && up.isSea { return false }
                if backgroundElement(atX: x + 1, y: y + 1).isLand && right.isSea && down.isSea { return false }
                if backgroundElement(atX: x - 1, y: y + 1).isLand && left.isSea && down.isSea { return false }
                return true
            case Element.terrainSeam.value:
                let current = backgroundElement(atX: x, y: y)
                guard current.isPipe || current.simplified == .terrainPlainD else { return false }
                let neighbours = [backgroundElement(atX: x - 1, y: y), backgroundElement(atX: x + 1, y: y), backgroundElement(atX: x, y: y - 1), backgroundElement(atX: x, y: y + 1)]
                if neighbours.allSatisfy({ !$0.isPipe }) { return true }
                let horizontal = neighbours[0].simplified == .terrainPipe && neighbours[1].simplified == .terrainPipe
                let vertical = neighbours[2].simplified == .terrainPipe && neighbours[3].simplified == .terrainPipe
                return horizontal || vertical
            default:
                return false
            }
        }

        if element.isBuilding { return true }

        if element.isUnit {
            let underlying = backgroundElement(atX: x, y: y)
            if underlying.isExtra { return false }
            if underlying == .terrainBlank { return true }
            let base = underlying.simplified
            let isSuperFamicomRailroad = tileset == .superFamicomWars && base == .terrainPipe
            switch element.simplified.value {
            case Element.unitInfantry.value, Element.unitMech.value:
                return isSuperFamicomRailroad || base.isBuilding || [.terrainPlain, .terrainPlainD, .terrainWood, .terrainMountain, .terrainRoad, .terrainBridgeH, .terrainRiver, .terrainShoal].contains(base)
            case Element.unitTank.value, Element.unitMDTank.value, Element.unitNeoTank.value, Element.unitMegaTank.value,
                 Element.unitRecon.value, Element.unitAntiAir.value, Element.unitMissile.value, Element.unitArtillery.value,
                 Element.unitRocket.value, Element.unitAPC.value, Element.unitOozium.value:
                return isSuperFamicomRailroad || base.isBuilding || [.terrainPlain, .terrainPlainD, .terrainWood, .terrainRoad, .terrainBridgeH, .terrainShoal].contains(base)
            case Element.unitPipeRunner.value:
                return [.terrainPipe, .terrainSeam, .buildingBase].contains(base)
            case Element.unitBlackBoat.value, Element.unitLander.value:
                return [.terrainShoal, .terrainSea, .terrainReef, .buildingPort].contains(base)
            case Element.unitCruiser.value, Element.unitSub.value, Element.unitBattleship.value, Element.unitCarrier.value:
                return [.terrainSea, .terrainReef, .buildingPort].contains(base)
            case Element.unitTCopter.value, Element.unitBCopter.value, Element.unitFighter.value, Element.unitBomber.value,
                 Element.unitStealth.value, Element.unitBlackBomb.value:
                return isSuperFamicomRailroad || (base != .terrainPipe && base != .terrainSeam)
            default:
                return element == .unitEmpty
            }
        }

        if element.isExtra {
            switch element.simplified.value {
            case Element.extraMCannonN.value, Element.extraMCannonS.value, Element.extraMCannonW.value,
                 Element.extraMCannonE.value, Element.extraLCannon.value, Element.extraBCrystal.value:
                return true
            case Element.extraBCannonN.value, Element.extraBCannons.value, Element.extraDeathray.value, Element.extraBobelisk.value:
                return element != element.simplified || (x >= 1 && y >= 1 && x <= width - 2 && y <= height - 2)
            case Element.extraSeaArc.value:
                // The selectable Sea Arc represents its centre tile. The
                // legacy editor starts the four-by-four footprint one tile
                // up and left; only generated subtiles carry a real offset.
                let offset = element.largeOffset() ?? (1, 1)
                for dx in (-1 - offset.x)..<(5 - offset.x) {
                    for dy in (-1 - offset.y)..<(5 - offset.y) {
                        if backgroundElement(atX: x + dx, y: y + dy).isLand { return false }
                    }
                }
                fallthrough
            case Element.extraVolcano.value, Element.extraFortress.value, Element.extraBlackArc.value, Element.extraGSilo.value:
                return element != element.simplified || (x >= 1 && y >= 1 && x <= width - 3 && y <= height - 3)
            default:
                return false
            }
        }
        return false
    }

    public mutating func fill(with element: Element) {
        for x in 0..<width {
            for y in 0..<height {
                _ = setBackground(element, atX: x, y: y, check: false)
            }
        }
        isDirty = true
    }

    public mutating func setSize(width newWidth: Int, height newHeight: Int) -> Bool {
        guard (AWConstants.mapMinimumWidth...AWConstants.mapMaximumWidth).contains(newWidth),
              (AWConstants.mapMinimumHeight...AWConstants.mapMaximumHeight).contains(newHeight) else { return false }
        var newMap = MapState(width: newWidth, height: newHeight, tileset: tileset, defaultTerrain: .terrainSea, defaultAuthor: author)
        newMap.name = name
        newMap.description = description
        for x in 0..<min(width, newWidth) {
            for y in 0..<min(height, newHeight) {
                newMap.background[newMap.index(x: x, y: y)] = backgroundElement(atX: x, y: y)
                newMap.backgroundDraw[newMap.index(x: x, y: y)] = backgroundDrawElement(atX: x, y: y)
                newMap.foreground[newMap.index(x: x, y: y)] = foregroundElement(atX: x, y: y)
            }
        }
        newMap.width = newWidth
        newMap.height = newHeight
        newMap.updateDraw()
        newMap.isDirty = true
        self = newMap
        return true
    }

    public func compatibleSize(with format: MapFormat) -> Compatibility {
        guard !format.supportsVariableSize else { return .ok }
        if width < 30 || height < 20 { return .impossible }
        return width == 30 && height == 20 ? .ok : .truncate
    }

    public func compatibleElements(with format: MapFormat) -> Compatibility {
        for element in background where !element.isCompatible(with: format) { return .truncate }
        for element in foreground where !element.isCompatible(with: format) { return .truncate }
        return .ok
    }

    public mutating func updateDraw() {
        updateDraw(x: 0, y: 0, width: width, height: height)
    }

    public mutating func updateDraw(x: Int, y: Int, width updateWidth: Int, height updateHeight: Int) {
        let minX = max(0, x)
        let maxX = min(width, x + updateWidth)
        let minY = max(0, y)
        let maxY = min(height, y + updateHeight)
        guard minX < maxX, minY < maxY else { return }
        for tileX in minX..<maxX {
            for tileY in minY..<maxY {
                backgroundDraw[index(x: tileX, y: tileY)] = drawElement(atX: tileX, y: tileY)
            }
        }
    }

    public func countBuildingsAndSeams() -> Int {
        background.count { $0.isBuilding || $0.simplified == .terrainSeam }
    }

    private func index(x: Int, y: Int) -> Int { x * height + y }
    private func isValid(x: Int, y: Int) -> Bool { x >= 0 && x < width && y >= 0 && y < height }

    private func isPipeForDrawing(atX x: Int, y: Int) -> Bool {
        let element = backgroundElement(atX: x, y: y)
        if element.isPipe { return true }
        return element.simplified == .terrainPlainD && allowPlacement(.terrainSeam, atX: x, y: y)
    }

    /// Returns the number of mountain cells immediately surrounding a tile.
    ///
    /// The authoring map stores the ordinary one-cell mountain tile. A taller
    /// mountain is a render-only variant, so the neighbourhood is intentionally
    /// read from `background` rather than `backgroundDraw` to avoid the derived
    /// artwork feeding back into its own selection.
    private func mountainNeighbourCount(atX x: Int, y: Int) -> Int {
        var count = 0
        for dx in -1...1 {
            for dy in -1...1 where !(dx == 0 && dy == 0) {
                if backgroundElement(atX: x + dx, y: y + dy).simplified == .terrainMountain {
                    count += 1
                }
            }
        }
        return count
    }

    /// Decides whether a mountain cell gets the taller range artwork.
    ///
    /// Two neighbours is the smallest useful range (for example the centre of
    /// a three-cell ridge). Larger clusters are sparsely sprinkled using a
    /// coordinate-stable hash, so a redraw never causes the mountain tops to
    /// jump around and a dense field does not become one solid wall of peaks.
    private func shouldDrawTallMountain(atX x: Int, y: Int) -> Bool {
        guard backgroundElement(atX: x, y: y).simplified == .terrainMountain else { return false }
        let neighbours = mountainNeighbourCount(atX: x, y: y)
        guard neighbours >= 2 else { return false }
        if neighbours == 2 { return true }

        let seed = x &* 31 &+ y &* 17 &+ x &* y &* 7
        return seed % 3 == 0
    }

    private func drawElement(atX x: Int, y: Int) -> Element {
        let element = backgroundElement(atX: x, y: y)
        guard element.isTerrain else { return element }

        // GB Wars uses the compact four-tone atlas as a collection of
        // finished 16×16 cells. Preserve its two bridge orientations, but
        // do not synthesize Advance Wars road, river, sea, shoal, or mountain
        // variants. Canonicalizing those terrain types keeps imported maps
        // from mixing later-game edge artwork into the Game Boy palette.
        if tileset.isGameBoyWarsFamily {
            switch element.simplified {
            case .terrainPlain: return .terrainPlain
            case .terrainWood: return .terrainWood
            case .terrainMountain: return .terrainMountain
            case .terrainRoad: return .terrainRoad
            case .terrainBridgeH: return element
            case .terrainRiver: return .terrainRiver
            case .terrainSea: return .terrainSea
            case .terrainShoal: return .terrainShoal
            default: break
            }
        }

        let up = backgroundElement(atX: x, y: y - 1)
        let down = backgroundElement(atX: x, y: y + 1)
        let left = backgroundElement(atX: x - 1, y: y)
        let right = backgroundElement(atX: x + 1, y: y)
        switch element.value {
        case Element.terrainMountain.value, AWConstants.makeTerrain(0, 7):
            // Keep the tall mountain in the derived layer only. This makes it
            // safe to apply the same rule to freshly drawn and imported maps
            // without changing their persisted terrain values.
            return shouldDrawTallMountain(atX: x, y: y)
                ? Element(AWConstants.makeTerrain(0, 7))
                : Element.terrainMountain
        case Element.terrainRoad.value:
            if up.isRoad && down.isRoad && left.isRoad && right.isRoad { return Element(AWConstants.makeTerrain(1, 2)) }
            if up.isRoad && down.isRoad && right.isRoad { return Element(AWConstants.makeTerrain(1, 5)) }
            if up.isRoad && down.isRoad && left.isRoad { return Element(AWConstants.makeTerrain(2, 5)) }
            if down.isRoad && left.isRoad && right.isRoad { return Element(AWConstants.makeTerrain(1, 6)) }
            if up.isRoad && left.isRoad && right.isRoad { return Element(AWConstants.makeTerrain(2, 6)) }
            if down.isRoad && right.isRoad { return Element(AWConstants.makeTerrain(1, 4)) }
            if down.isRoad && left.isRoad { return Element(AWConstants.makeTerrain(2, 4)) }
            if up.isRoad && right.isRoad { return Element(AWConstants.makeTerrain(1, 7)) }
            if up.isRoad && left.isRoad { return Element(AWConstants.makeTerrain(2, 7)) }
            if up.isRoad || down.isRoad { return Element(AWConstants.makeTerrain(1, 1)) }
            return Element(AWConstants.makeTerrain(1, 0))
        case Element.terrainRiver.value:
            if up.isRiver && down.isRiver && left.isRiver && right.isRiver { return Element(AWConstants.makeTerrain(3, 2)) }
            if up.isRiver && down.isRiver && right.isRiver { return Element(AWConstants.makeTerrain(3, 5)) }
            if up.isRiver && down.isRiver && left.isRiver { return Element(AWConstants.makeTerrain(4, 5)) }
            if down.isRiver && left.isRiver && right.isRiver { return Element(AWConstants.makeTerrain(3, 6)) }
            if up.isRiver && left.isRiver && right.isRiver { return Element(AWConstants.makeTerrain(4, 6)) }
            if down.isRiver && right.isRiver { return Element(AWConstants.makeTerrain(3, 4)) }
            if down.isRiver && left.isRiver { return Element(AWConstants.makeTerrain(4, 4)) }
            if up.isRiver && right.isRiver { return Element(AWConstants.makeTerrain(3, 7)) }
            if up.isRiver && left.isRiver { return Element(AWConstants.makeTerrain(4, 7)) }
            if up.isRiver || down.isRiver { return Element(AWConstants.makeTerrain(3, 1)) }
            return Element(AWConstants.makeTerrain(3, 0))
        case Element.terrainSea.value:
            // The legacy editor stores dedicated draw variants for sea cells
            // enclosed by land. Only the ordinary base-sea variant receives
            // the layered coast overlays in the renderer; using the variants
            // here prevents inner holes from being composited as open shores.
            if up.isLand && down.isLand && left.isLand && right.isLand { return Element(AWConstants.makeTerrain(7, 0)) }
            if down.isLand && left.isLand && right.isLand { return Element(AWConstants.makeTerrain(7, 4)) }
            if up.isLand && left.isLand && right.isLand { return Element(AWConstants.makeTerrain(7, 3)) }
            if up.isLand && down.isLand && right.isLand { return Element(AWConstants.makeTerrain(7, 2)) }
            if up.isLand && down.isLand && left.isLand { return Element(AWConstants.makeTerrain(7, 1)) }
            if up.isSea && down.isSea && left.isSea && right.isRiver,
               backgroundElement(atX: x - 1, y: y - 1).isSea,
               backgroundElement(atX: x - 1, y: y + 1).isSea,
               drawElement(atX: x + 1, y: y) == Element(AWConstants.makeTerrain(3, 0)) {
                return Element(AWConstants.makeTerrain(4, 0))
            }
            if up.isSea && down.isSea && left.isRiver && right.isSea,
               backgroundElement(atX: x + 1, y: y - 1).isSea,
               backgroundElement(atX: x + 1, y: y + 1).isSea,
               drawElement(atX: x - 1, y: y) == Element(AWConstants.makeTerrain(3, 0)) {
                return Element(AWConstants.makeTerrain(4, 1))
            }
            if up.isSea && down.isRiver && left.isSea && right.isSea,
               backgroundElement(atX: x - 1, y: y - 1).isSea,
               backgroundElement(atX: x + 1, y: y - 1).isSea,
               drawElement(atX: x, y: y + 1) == Element(AWConstants.makeTerrain(3, 1)) {
                return Element(AWConstants.makeTerrain(4, 2))
            }
            if up.isRiver && down.isSea && left.isSea && right.isSea,
               backgroundElement(atX: x - 1, y: y + 1).isSea,
               backgroundElement(atX: x + 1, y: y + 1).isSea,
               drawElement(atX: x, y: y - 1) == Element(AWConstants.makeTerrain(3, 1)) {
                return Element(AWConstants.makeTerrain(4, 3))
            }
            return element
        case Element.terrainShoal.value:
            // Famicom Wars uses one flat cyan shoal sprite. Its source sheet
            // does not contain the later Advance Wars shoreline variants, so
            // keep the authoring tile unchanged regardless of neighbours.
            if tileset.isFamicomWarsFamily { return element }
            // Match the original editor's shoal shoreline table. The tile
            // values encode the local land/shoal arrangement in the sheet.
            if down.isLand && left.isLand && right.isLand { return Element(AWConstants.makeTerrain(9, 7)) }
            if up.isLand && left.isLand && right.isLand { return Element(AWConstants.makeTerrain(9, 6)) }
            if up.isLand && down.isLand && right.isLand { return Element(AWConstants.makeTerrain(9, 5)) }
            if up.isLand && down.isLand && left.isLand { return Element(AWConstants.makeTerrain(9, 4)) }
            if up.isLand && left.isLand {
                if down.simplified == .terrainShoal && right.simplified == .terrainShoal { return Element(AWConstants.makeTerrain(13, 2)) }
                if down.simplified == .terrainShoal { return Element(AWConstants.makeTerrain(11, 2)) }
                if right.simplified == .terrainShoal { return Element(AWConstants.makeTerrain(13, 0)) }
                return Element(AWConstants.makeTerrain(11, 0))
            }
            if up.isLand && right.isLand {
                if down.simplified == .terrainShoal && left.simplified == .terrainShoal { return Element(AWConstants.makeTerrain(12, 2)) }
                if down.simplified == .terrainShoal { return Element(AWConstants.makeTerrain(14, 0)) }
                if left.simplified == .terrainShoal { return Element(AWConstants.makeTerrain(14, 2)) }
                return Element(AWConstants.makeTerrain(12, 0))
            }
            if down.isLand && left.isLand {
                if up.simplified == .terrainShoal && right.simplified == .terrainShoal { return Element(AWConstants.makeTerrain(11, 3)) }
                if up.simplified == .terrainShoal { return Element(AWConstants.makeTerrain(13, 3)) }
                if right.simplified == .terrainShoal { return Element(AWConstants.makeTerrain(13, 1)) }
                return Element(AWConstants.makeTerrain(11, 1))
            }
            if down.isLand && right.isLand {
                if up.simplified == .terrainShoal && left.simplified == .terrainShoal { return Element(AWConstants.makeTerrain(12, 3)) }
                if up.simplified == .terrainShoal { return Element(AWConstants.makeTerrain(14, 3)) }
                if left.simplified == .terrainShoal { return Element(AWConstants.makeTerrain(14, 1)) }
                return Element(AWConstants.makeTerrain(12, 1))
            }
            if up.isLand {
                if left.simplified == .terrainShoal && right.simplified == .terrainShoal { return Element(AWConstants.makeTerrain(9, 1)) }
                if left.simplified == .terrainShoal { return Element(AWConstants.makeTerrain(11, 4)) }
                if right.simplified == .terrainShoal { return Element(AWConstants.makeTerrain(12, 4)) }
                return Element(AWConstants.makeTerrain(9, 3))
            }
            if down.isLand {
                if left.simplified == .terrainShoal && right.simplified == .terrainShoal { return Element(AWConstants.makeTerrain(10, 1)) }
                if left.simplified == .terrainShoal { return Element(AWConstants.makeTerrain(11, 5)) }
                if right.simplified == .terrainShoal { return Element(AWConstants.makeTerrain(12, 5)) }
                return Element(AWConstants.makeTerrain(10, 3))
            }
            if left.isLand {
                if up.simplified == .terrainShoal && down.simplified == .terrainShoal { return Element(AWConstants.makeTerrain(9, 0)) }
                if up.simplified == .terrainShoal { return Element(AWConstants.makeTerrain(11, 6)) }
                if down.simplified == .terrainShoal { return Element(AWConstants.makeTerrain(11, 7)) }
                return Element(AWConstants.makeTerrain(9, 2))
            }
            if right.isLand {
                if up.simplified == .terrainShoal && down.simplified == .terrainShoal { return Element(AWConstants.makeTerrain(10, 0)) }
                if up.simplified == .terrainShoal { return Element(AWConstants.makeTerrain(12, 6)) }
                if down.simplified == .terrainShoal { return Element(AWConstants.makeTerrain(12, 7)) }
                return Element(AWConstants.makeTerrain(10, 2))
            }
            return element
        case Element.terrainBridgeH.value, Element.terrainBridgeV.value:
            return element
        case Element.terrainPipe.value:
            if isPipeForDrawing(atX: x - 1, y: y) && isPipeForDrawing(atX: x + 1, y: y) { return Element(AWConstants.makeTerrain(16, 0)) }
            if isPipeForDrawing(atX: x, y: y - 1) && isPipeForDrawing(atX: x, y: y + 1) { return Element(AWConstants.makeTerrain(16, 1)) }
            if isPipeForDrawing(atX: x, y: y - 1) && isPipeForDrawing(atX: x + 1, y: y) { return Element(AWConstants.makeTerrain(17, 2)) }
            if isPipeForDrawing(atX: x, y: y - 1) && isPipeForDrawing(atX: x - 1, y: y) { return Element(AWConstants.makeTerrain(17, 3)) }
            if isPipeForDrawing(atX: x, y: y + 1) && isPipeForDrawing(atX: x + 1, y: y) { return Element(AWConstants.makeTerrain(17, 0)) }
            if isPipeForDrawing(atX: x, y: y + 1) && isPipeForDrawing(atX: x - 1, y: y) { return Element(AWConstants.makeTerrain(17, 1)) }
            if isPipeForDrawing(atX: x - 1, y: y) { return Element(AWConstants.makeTerrain(16, 3)) }
            if isPipeForDrawing(atX: x + 1, y: y) { return Element(AWConstants.makeTerrain(16, 2)) }
            if isPipeForDrawing(atX: x, y: y - 1) { return Element(AWConstants.makeTerrain(16, 5)) }
            if isPipeForDrawing(atX: x, y: y + 1) { return Element(AWConstants.makeTerrain(16, 4)) }
            return Element(AWConstants.makeTerrain(16, 0))
        case Element.terrainSeam.value:
            return up.simplified == .terrainPipe && down.simplified == .terrainPipe ? Element(AWConstants.makeTerrain(16, 6)) : Element(AWConstants.makeTerrain(16, 7))
        case Element.terrainPlainD.value:
            if isPipeForDrawing(atX: x, y: y) && up.simplified == .terrainPipe && down.simplified == .terrainPipe { return Element(AWConstants.makeTerrain(17, 6)) }
            if isPipeForDrawing(atX: x, y: y) && left.simplified == .terrainPipe && right.simplified == .terrainPipe { return Element(AWConstants.makeTerrain(17, 7)) }
            return Element(AWConstants.makeTerrain(17, 5))
        default:
            return element
        }
    }
}

public enum Compatibility: Int, Codable, Sendable {
    case impossible = 0
    case ok = 1
    case truncate = 2
}
