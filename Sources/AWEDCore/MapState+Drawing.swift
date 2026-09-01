import Foundation

extension MapState {
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
        if tileset.isGameBoyWarsFamily, let canonical = gameBoyTerrain(element) { return canonical }

        switch element.value {
        case Element.terrainMountain.value, AWConstants.makeTerrain(0, 7):
            return shouldDrawTallMountain(atX: x, y: y) ? Element(AWConstants.makeTerrain(0, 7)) : .terrainMountain
        case Element.terrainRoad.value:
            return drawRoad(atX: x, y: y)
        case Element.terrainRiver.value:
            return drawRiver(atX: x, y: y)
        case Element.terrainSea.value:
            return drawSea(atX: x, y: y, original: element)
        case Element.terrainShoal.value:
            return drawShoal(atX: x, y: y, original: element)
        case Element.terrainBridgeH.value, Element.terrainBridgeV.value:
            return element
        case Element.terrainPipe.value:
            return drawPipe(atX: x, y: y)
        case Element.terrainSeam.value:
            return drawSeam(atX: x, y: y)
        case Element.terrainPlainD.value:
            return drawPlainD(atX: x, y: y)
        default:
            return element
        }
    }

    private func gameBoyTerrain(_ element: Element) -> Element? {
        switch element.simplified {
        case .terrainPlain, .terrainWood, .terrainMountain, .terrainRoad,
             .terrainRiver, .terrainSea, .terrainShoal:
            return element.simplified
        case .terrainBridgeH:
            return element
        default:
            return nil
        }
    }

    private func connectionMask(atX x: Int, y: Int, matches: (Element) -> Bool) -> Int {
        let neighbours = [
            backgroundElement(atX: x, y: y - 1), backgroundElement(atX: x, y: y + 1),
            backgroundElement(atX: x - 1, y: y), backgroundElement(atX: x + 1, y: y)
        ]
        return neighbours.enumerated().reduce(0) { mask, item in
            matches(item.element) ? mask | (1 << item.offset) : mask
        }
    }

    private func terrainTile(_ row: Int, _ column: Int) -> Element {
        Element(AWConstants.makeTerrain(row, column))
    }

    private func drawRoad(atX x: Int, y: Int) -> Element {
        switch connectionMask(atX: x, y: y, matches: { $0.isRoad }) {
        case 15: return terrainTile(1, 2)
        case 11: return terrainTile(1, 5)
        case 7: return terrainTile(2, 5)
        case 14: return terrainTile(1, 6)
        case 13: return terrainTile(2, 6)
        case 10: return terrainTile(1, 4)
        case 6: return terrainTile(2, 4)
        case 9: return terrainTile(1, 7)
        case 5: return terrainTile(2, 7)
        case 3, 1, 2, 4: return terrainTile(1, 1)
        default: return terrainTile(1, 0)
        }
    }

    private func drawRiver(atX x: Int, y: Int) -> Element {
        switch connectionMask(atX: x, y: y, matches: { $0.isRiver }) {
        case 15: return terrainTile(3, 2)
        case 11: return terrainTile(3, 5)
        case 7: return terrainTile(4, 5)
        case 14: return terrainTile(3, 6)
        case 13: return terrainTile(4, 6)
        case 10: return terrainTile(3, 4)
        case 6: return terrainTile(4, 4)
        case 9: return terrainTile(3, 7)
        case 5: return terrainTile(4, 7)
        case 3, 1, 2, 4: return terrainTile(3, 1)
        default: return terrainTile(3, 0)
        }
    }

    private func drawSea(atX x: Int, y: Int, original: Element) -> Element {
        let up = backgroundElement(atX: x, y: y - 1)
        let down = backgroundElement(atX: x, y: y + 1)
        let left = backgroundElement(atX: x - 1, y: y)
        let right = backgroundElement(atX: x + 1, y: y)
        if let corner = drawSeaCorner(up: up, down: down, left: left, right: right) {
            return corner
        }
        return drawSeaRiverEdge(atX: x, y: y, up: up, down: down, left: left, right: right) ?? original
    }

    private func drawSeaCorner(up: Element, down: Element, left: Element, right: Element) -> Element? {
        if up.isLand && down.isLand && left.isLand && right.isLand { return terrainTile(7, 0) }
        if down.isLand && left.isLand && right.isLand { return terrainTile(7, 4) }
        if up.isLand && left.isLand && right.isLand { return terrainTile(7, 3) }
        if up.isLand && down.isLand && right.isLand { return terrainTile(7, 2) }
        if up.isLand && down.isLand && left.isLand { return terrainTile(7, 1) }
        return nil
    }

    private func drawSeaRiverEdge(
        atX x: Int,
        y: Int,
        up: Element,
        down: Element,
        left: Element,
        right: Element
    ) -> Element? {
        if let result = drawSeaRiverLeft(atX: x, y: y, up: up, down: down, left: left, right: right) {
            return result
        }
        if let result = drawSeaRiverRight(atX: x, y: y, up: up, down: down, left: left, right: right) {
            return result
        }
        if let result = drawSeaRiverDown(atX: x, y: y, up: up, down: down, left: left, right: right) {
            return result
        }
        return drawSeaRiverUp(atX: x, y: y, up: up, down: down, left: left, right: right)
    }

    private func drawSeaRiverLeft(atX x: Int, y: Int, up: Element, down: Element, left: Element, right: Element) -> Element? {
        guard up.isSea && down.isSea && left.isSea && right.isRiver else { return nil }
        let diagonal = backgroundElement(atX: x - 1, y: y - 1).isSea && backgroundElement(atX: x - 1, y: y + 1).isSea
        guard diagonal, drawElement(atX: x + 1, y: y) == terrainTile(3, 0) else { return nil }
        return terrainTile(4, 0)
    }

    private func drawSeaRiverRight(atX x: Int, y: Int, up: Element, down: Element, left: Element, right: Element) -> Element? {
        guard up.isSea && down.isSea && left.isRiver && right.isSea else { return nil }
        let diagonal = backgroundElement(atX: x + 1, y: y - 1).isSea && backgroundElement(atX: x + 1, y: y + 1).isSea
        guard diagonal, drawElement(atX: x - 1, y: y) == terrainTile(3, 0) else { return nil }
        return terrainTile(4, 1)
    }

    private func drawSeaRiverDown(atX x: Int, y: Int, up: Element, down: Element, left: Element, right: Element) -> Element? {
        guard up.isSea && down.isRiver && left.isSea && right.isSea else { return nil }
        let diagonal = seaDiagonals(atX: x, y: y)
        guard diagonal, drawElement(atX: x, y: y + 1) == terrainTile(3, 1) else { return nil }
        return terrainTile(4, 2)
    }

    private func drawSeaRiverUp(atX x: Int, y: Int, up: Element, down: Element, left: Element, right: Element) -> Element? {
        guard up.isRiver && down.isSea && left.isSea && right.isSea else { return nil }
        let diagonal = seaDiagonals(atX: x, y: y)
        guard diagonal, drawElement(atX: x, y: y - 1) == terrainTile(3, 1) else { return nil }
        return terrainTile(4, 3)
    }

    private func seaDiagonals(atX x: Int, y: Int) -> Bool {
        backgroundElement(atX: x - 1, y: y - 1).isSea &&
            backgroundElement(atX: x + 1, y: y - 1).isSea &&
            backgroundElement(atX: x - 1, y: y + 1).isSea &&
            backgroundElement(atX: x + 1, y: y + 1).isSea
    }

    private func drawShoal(atX x: Int, y: Int, original: Element) -> Element {
        guard !tileset.isFamicomWarsFamily else { return original }
        let up = backgroundElement(atX: x, y: y - 1)
        let down = backgroundElement(atX: x, y: y + 1)
        let left = backgroundElement(atX: x - 1, y: y)
        let right = backgroundElement(atX: x + 1, y: y)
        switch landMask(up: up, down: down, left: left, right: right) {
        case 14: return terrainTile(9, 7)
        case 13: return terrainTile(9, 6)
        case 11: return terrainTile(9, 5)
        case 7: return terrainTile(9, 4)
        case 5: return drawShoalNorthWest(down: down, right: right)
        case 9: return drawShoalNorthEast(down: down, left: left)
        case 6: return drawShoalSouthWest(up: up, right: right)
        case 10: return drawShoalSouthEast(up: up, left: left)
        case 1: return drawShoalNorth(left: left, right: right)
        case 2: return drawShoalSouth(left: left, right: right)
        case 4: return drawShoalWest(up: up, down: down)
        case 8: return drawShoalEast(up: up, down: down)
        default: return original
        }
    }

    private func landMask(up: Element, down: Element, left: Element, right: Element) -> Int {
        let neighbours = [up, down, left, right]
        return neighbours.enumerated().reduce(0) { mask, item in
            item.element.isLand ? mask | (1 << item.offset) : mask
        }
    }

    private func drawShoalNorthWest(down: Element, right: Element) -> Element {
        if down.simplified == .terrainShoal && right.simplified == .terrainShoal { return terrainTile(13, 2) }
        if down.simplified == .terrainShoal { return terrainTile(11, 2) }
        if right.simplified == .terrainShoal { return terrainTile(13, 0) }
        return terrainTile(11, 0)
    }

    private func drawShoalNorthEast(down: Element, left: Element) -> Element {
        if down.simplified == .terrainShoal && left.simplified == .terrainShoal { return terrainTile(12, 2) }
        if down.simplified == .terrainShoal { return terrainTile(14, 0) }
        if left.simplified == .terrainShoal { return terrainTile(14, 2) }
        return terrainTile(12, 0)
    }

    private func drawShoalSouthWest(up: Element, right: Element) -> Element {
        if up.simplified == .terrainShoal && right.simplified == .terrainShoal { return terrainTile(11, 3) }
        if up.simplified == .terrainShoal { return terrainTile(13, 3) }
        if right.simplified == .terrainShoal { return terrainTile(13, 1) }
        return terrainTile(11, 1)
    }

    private func drawShoalSouthEast(up: Element, left: Element) -> Element {
        if up.simplified == .terrainShoal && left.simplified == .terrainShoal { return terrainTile(12, 3) }
        if up.simplified == .terrainShoal { return terrainTile(14, 3) }
        if left.simplified == .terrainShoal { return terrainTile(14, 1) }
        return terrainTile(12, 1)
    }

    private func drawShoalNorth(left: Element, right: Element) -> Element {
        if left.simplified == .terrainShoal && right.simplified == .terrainShoal { return terrainTile(9, 1) }
        if left.simplified == .terrainShoal { return terrainTile(11, 4) }
        if right.simplified == .terrainShoal { return terrainTile(12, 4) }
        return terrainTile(9, 3)
    }

    private func drawShoalSouth(left: Element, right: Element) -> Element {
        if left.simplified == .terrainShoal && right.simplified == .terrainShoal { return terrainTile(10, 1) }
        if left.simplified == .terrainShoal { return terrainTile(11, 5) }
        if right.simplified == .terrainShoal { return terrainTile(12, 5) }
        return terrainTile(10, 3)
    }

    private func drawShoalWest(up: Element, down: Element) -> Element {
        if up.simplified == .terrainShoal && down.simplified == .terrainShoal { return terrainTile(9, 0) }
        if up.simplified == .terrainShoal { return terrainTile(11, 6) }
        if down.simplified == .terrainShoal { return terrainTile(11, 7) }
        return terrainTile(9, 2)
    }

    private func drawShoalEast(up: Element, down: Element) -> Element {
        if up.simplified == .terrainShoal && down.simplified == .terrainShoal { return terrainTile(10, 0) }
        if up.simplified == .terrainShoal { return terrainTile(12, 6) }
        if down.simplified == .terrainShoal { return terrainTile(12, 7) }
        return terrainTile(10, 2)
    }

    private func drawPipe(atX x: Int, y: Int) -> Element {
        let horizontal = isPipeForDrawing(atX: x - 1, y: y) && isPipeForDrawing(atX: x + 1, y: y)
        let vertical = isPipeForDrawing(atX: x, y: y - 1) && isPipeForDrawing(atX: x, y: y + 1)
        if horizontal { return terrainTile(16, 0) }
        if vertical { return terrainTile(16, 1) }
        return drawPipeCornerOrEnd(atX: x, y: y)
    }

    private func drawPipeCornerOrEnd(atX x: Int, y: Int) -> Element {
        let up = isPipeForDrawing(atX: x, y: y - 1)
        let down = isPipeForDrawing(atX: x, y: y + 1)
        let left = isPipeForDrawing(atX: x - 1, y: y)
        let right = isPipeForDrawing(atX: x + 1, y: y)
        if up && right { return terrainTile(17, 2) }
        if up && left { return terrainTile(17, 3) }
        if down && right { return terrainTile(17, 0) }
        if down && left { return terrainTile(17, 1) }
        if left { return terrainTile(16, 3) }
        if right { return terrainTile(16, 2) }
        if up { return terrainTile(16, 5) }
        if down { return terrainTile(16, 4) }
        return terrainTile(16, 0)
    }

    private func drawSeam(atX x: Int, y: Int) -> Element {
        let up = backgroundElement(atX: x, y: y - 1).simplified == .terrainPipe
        let down = backgroundElement(atX: x, y: y + 1).simplified == .terrainPipe
        return terrainTile(16, up && down ? 6 : 7)
    }

    private func drawPlainD(atX x: Int, y: Int) -> Element {
        let center = isPipeForDrawing(atX: x, y: y)
        let up = backgroundElement(atX: x, y: y - 1).simplified == .terrainPipe
        let down = backgroundElement(atX: x, y: y + 1).simplified == .terrainPipe
        let left = backgroundElement(atX: x - 1, y: y).simplified == .terrainPipe
        let right = backgroundElement(atX: x + 1, y: y).simplified == .terrainPipe
        if center && up && down { return terrainTile(17, 6) }
        if center && left && right { return terrainTile(17, 7) }
        return terrainTile(17, 5)
    }
}
