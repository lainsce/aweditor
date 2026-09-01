import Foundation
import AWEDCore

extension EditorModel {
    func pointerBegan(at point: GridPoint, modifiers: PointerModifiers) {
        lastDragCell = point
        switch selectedTool {
        case .pencil:
            addUndoPoint()
            place(selectedElement, at: point, nextSprite: modifiers.option, allowMultipleHQ: modifiers.shift)
        case .line, .rectangle, .filledRectangle:
            guard selectedElement.size == 1 else { return }
            dragStart = point
            previewCells = shapeCells(from: point, to: point, tool: selectedTool)
        case .bucket:
            guard selectedElement.isBackground else { return }
            addUndoPoint()
            floodFill(from: point, with: selectedElement)
        case .selector:
            if let selection, selection.contains(point), selectionFragment != nil {
                movingSelection = true
                movingSelectionOrigin = selection
                dragStart = point
                // The legacy editor treats Control-drag as a quick copy. On
                // macOS both Command-drag and Control-drag are accepted so
                // the shortcut feels native while retaining the old behavior.
                if modifiers.command { selectionIsOverlay = true }
            } else {
                clearSelection()
                dragStart = point
                previewCells = []
            }
        }
    }

    func pointerChanged(to point: GridPoint, modifiers: PointerModifiers) {
        guard lastDragCell != point || selectedTool == .selector else { return }
        lastDragCell = point
        switch selectedTool {
        case .pencil:
            place(selectedElement, at: point, nextSprite: modifiers.option, allowMultipleHQ: modifiers.shift)
        case .line, .rectangle, .filledRectangle:
            if let dragStart { previewCells = shapeCells(from: dragStart, to: point, tool: selectedTool) }
        case .bucket:
            break
        case .selector:
            guard let dragStart else { return }
            if movingSelection, let origin = movingSelectionOrigin, let fragment = selectionFragment {
                let dx = point.x - dragStart.x
                let dy = point.y - dragStart.y
                let x = min(max(0, origin.x + dx), max(0, map.width - fragment.width))
                let y = min(max(0, origin.y + dy), max(0, map.height - fragment.height))
                selection = SelectionRect(x: x, y: y, width: fragment.width, height: fragment.height)
            } else {
                previewCells = outlineCells(from: dragStart, to: point)
            }
        }
    }

    func pointerEnded(at point: GridPoint, modifiers: PointerModifiers) {
        switch selectedTool {
        case .line, .rectangle, .filledRectangle:
            guard !previewCells.isEmpty else { break }
            addUndoPoint()
            for cell in previewCells { place(selectedElement, at: cell, nextSprite: modifiers.option, allowMultipleHQ: modifiers.shift) }
        case .selector:
            if movingSelection {
                if let origin = movingSelectionOrigin, let selection, selection != origin {
                    selectionNeedsCommit = true
                    commitSelection(allowMultipleHQ: modifiers.shift)
                }
            } else if let dragStart {
                let rect = normalizedRect(from: dragStart, to: point)
                if !rect.isEmpty {
                    selection = rect
                    selectionFragment = MapFragment(map: map, x: rect.x, y: rect.y, width: rect.width, height: rect.height)
                    selectionNeedsCommit = false
                    selectionUndoRecorded = false
                    selectionEraseRect = nil
                    selectionIsOverlay = false
                }
            }
        default:
            break
        }
        previewCells.removeAll()
        dragStart = nil
        lastDragCell = nil
        movingSelectionOrigin = nil
        movingSelection = false
    }

    private func shapeCells(from start: GridPoint, to end: GridPoint, tool: EditorTool) -> Set<GridPoint> {
        switch tool {
        case .line: return bresenham(from: start, to: end)
        case .rectangle: return rectangleCells(from: start, to: end, filled: false)
        case .filledRectangle: return rectangleCells(from: start, to: end, filled: true)
        default: return []
        }
    }

    private func rectangleCells(from start: GridPoint, to end: GridPoint, filled: Bool) -> Set<GridPoint> {
        let rect = normalizedRect(from: start, to: end)
        var cells = Set<GridPoint>()
        for x in rect.x..<(rect.x + rect.width) {
            for y in rect.y..<(rect.y + rect.height) where filled || isRectangleEdge(x: x, y: y, in: rect) {
                cells.insert(GridPoint(x: x, y: y))
            }
        }
        return cells
    }

    private func isRectangleEdge(x: Int, y: Int, in rect: SelectionRect) -> Bool {
        x == rect.x || y == rect.y || x == rect.x + rect.width - 1 || y == rect.y + rect.height - 1
    }

    private func outlineCells(from start: GridPoint, to end: GridPoint) -> Set<GridPoint> {
        let rect = normalizedRect(from: start, to: end)
        return boundaryCells(rect)
    }

    private func boundaryCells(_ rect: SelectionRect) -> Set<GridPoint> {
        horizontalBoundaryCells(in: rect).union(verticalBoundaryCells(in: rect))
    }

    private func horizontalBoundaryCells(in rect: SelectionRect) -> Set<GridPoint> {
        var cells = Set<GridPoint>()
        for x in rect.x..<(rect.x + rect.width) {
            cells.insert(GridPoint(x: x, y: rect.y))
            cells.insert(GridPoint(x: x, y: rect.y + rect.height - 1))
        }
        return cells
    }

    private func verticalBoundaryCells(in rect: SelectionRect) -> Set<GridPoint> {
        var cells = Set<GridPoint>()
        for y in rect.y..<(rect.y + rect.height) {
            cells.insert(GridPoint(x: rect.x, y: y))
            cells.insert(GridPoint(x: rect.x + rect.width - 1, y: y))
        }
        return cells
    }

    private func normalizedRect(from start: GridPoint, to end: GridPoint) -> SelectionRect {
        let x = min(start.x, end.x)
        let y = min(start.y, end.y)
        let maxX = min(map.width - 1, max(start.x, end.x))
        let maxY = min(map.height - 1, max(start.y, end.y))
        return SelectionRect(x: max(0, x), y: max(0, y), width: maxX - max(0, x) + 1, height: maxY - max(0, y) + 1)
    }

    private func bresenham(from start: GridPoint, to end: GridPoint) -> Set<GridPoint> {
        bresenhamPoints(from: start, to: end).filter { point in
            point.x >= 0 && point.x < map.width && point.y >= 0 && point.y < map.height
        }
    }

    private func bresenhamPoints(from start: GridPoint, to end: GridPoint) -> Set<GridPoint> {
        var state = BresenhamState(start: start, end: end)
        var points = Set<GridPoint>()
        while true {
            points.insert(state.point)
            if state.isDone { return points }
            state.advance()
        }
    }

    private func floodFill(from start: GridPoint, with element: Element) {
        let original = map.backgroundElement(atX: start.x, y: start.y)
        guard original != element else { return }
        var queue = [start]
        var visited = Set<GridPoint>()
        while let point = queue.popLast() {
            guard !visited.contains(point), point.x >= 0, point.x < map.width, point.y >= 0, point.y < map.height else { continue }
            guard map.backgroundElement(atX: point.x, y: point.y) == original else { continue }
            visited.insert(point)
            place(element, at: point, allowMultipleHQ: true)
            queue.append(contentsOf: floodNeighbours(of: point))
        }
    }

    private func floodNeighbours(of point: GridPoint) -> [GridPoint] {
        let horizontal = [-1, 1].map { GridPoint(x: point.x + $0, y: point.y) }
        let vertical = [-1, 1].map { GridPoint(x: point.x, y: point.y + $0) }
        return horizontal + vertical
    }

    private func place(_ requestedElement: Element, at point: GridPoint, nextSprite: Bool = false, allowMultipleHQ: Bool = false) {
        guard point.x >= 0, point.x < map.width, point.y >= 0, point.y < map.height else { return }
        let previousBackground = map.backgroundElement(atX: point.x, y: point.y)
        guard let element = resolvedElement(requestedElement, previous: previousBackground, at: point, nextSprite: nextSprite) else { return }
        guard element.isBackground else {
            if element.isForeground {
                _ = map.setForeground(element == .unitDelete ? .unitEmpty : element, atX: point.x, y: point.y)
            }
            return
        }
        guard map.allowPlacement(element, atX: point.x, y: point.y) else { return }
        eraseLargeBackground(previousBackground, at: point)
        _ = map.setBackground(element, atX: point.x, y: point.y)
        clearInvalidForeground(at: point)
        writeLargeBackground(element, at: point)
        repairTerrainAround(point, previousBackground: previousBackground, placed: element)
        if !allowMultipleHQ { removeDuplicateHQs(around: point, for: element) }
        map.updateDraw(x: point.x - 2, y: point.y - 2, width: 5, height: 5)
    }

    private func resolvedElement(_ requested: Element, previous: Element, at point: GridPoint, nextSprite: Bool) -> Element? {
        var element = requested
        if nextSprite, element.isTerrain, element.simplified == previous.simplified { element = previous.nextSprite() }
        if element == previous, !nextSprite { return nil }
        if element.simplified == .terrainRoad && (previous.simplified == .terrainRiver || previous.simplified == .terrainBridgeH) {
            element = .terrainBridgeH
        }
        guard element == .terrainBridgeH else { return element }
        return bridgeOrientation(at: point, previous: previous)
    }

    private func bridgeOrientation(at point: GridPoint, previous: Element) -> Element {
        let neighbours = bridgeNeighbours(at: point)
        if previous.simplified == .terrainRiver { return neighbours[0].isRiver || neighbours[1].isRiver ? .terrainBridgeH : .terrainBridgeV }
        return verticalBridgeNeeded(neighbours) ? .terrainBridgeV : .terrainBridgeH
    }

    private func bridgeNeighbours(at point: GridPoint) -> [Element] {
        [
            map.backgroundElement(atX: point.x, y: point.y - 1), map.backgroundElement(atX: point.x, y: point.y + 1),
            map.backgroundElement(atX: point.x - 1, y: point.y), map.backgroundElement(atX: point.x + 1, y: point.y)
        ]
    }

    private func verticalBridgeNeeded(_ neighbours: [Element]) -> Bool {
        neighbours[0].isLand || neighbours[1].isLand || neighbours[0] == .terrainBridgeV || neighbours[1] == .terrainBridgeV
    }

    private func eraseLargeBackground(_ previous: Element, at point: GridPoint) {
        guard previous.isExtra, previous.size > 1, previous != previous.simplified, let offset = previous.largeOffset() else { return }
        for dx in -offset.x..<(previous.size - offset.x) {
            for dy in -offset.y..<(previous.size - offset.y) {
                _ = map.setBackground(previous.base, atX: point.x + dx, y: point.y + dy, check: false)
            }
        }
    }

    private func clearInvalidForeground(at point: GridPoint) {
        let foreground = map.foregroundElement(atX: point.x, y: point.y)
        if !map.allowPlacement(foreground, atX: point.x, y: point.y, recheck: true) {
            _ = map.setForeground(.unitEmpty, atX: point.x, y: point.y)
        }
    }

    private func writeLargeBackground(_ element: Element, at point: GridPoint) {
        guard element.isExtra, element.size > 1, element == element.simplified else { return }
        for dx in 0..<element.size {
            for dy in 0..<element.size {
                _ = map.setBackground(Element(element.topLeft + AWConstants.extraColumns * dy + dx), atX: point.x + dx - 1, y: point.y + dy - 1, check: false)
            }
        }
    }

    private func removeDuplicateHQs(around point: GridPoint, for element: Element) {
        guard element.simplified == .buildingHQ || element.simplified == .buildingLab else { return }
        for x in 0..<map.width {
            for y in 0..<map.height where !(x == point.x && y == point.y) {
                let existing = map.backgroundElement(atX: x, y: y)
                if (existing.simplified == .buildingHQ || existing.simplified == .buildingLab), existing.army == element.army {
                    _ = map.setBackground(.terrainPlain, atX: x, y: y)
                }
            }
        }
    }

    private func repairTerrainAround(_ point: GridPoint, previousBackground: Element, placed: Element) {
        repairPipes(around: point, previousBackground: previousBackground)
        repairShoals(around: point)
        repairReefs(around: point, placed: placed)
        repairSeaArcs(around: point)
    }

    private func repairPipes(around point: GridPoint, previousBackground: Element) {
        // Removing a pipe/pipe-seam can invalidate the seams that touch it.
        if previousBackground.isPipe {
            let neighbours = [
                GridPoint(x: point.x - 1, y: point.y), GridPoint(x: point.x + 1, y: point.y),
                GridPoint(x: point.x, y: point.y - 1), GridPoint(x: point.x, y: point.y + 1)
            ]
            for neighbour in neighbours {
                let current = map.backgroundElement(atX: neighbour.x, y: neighbour.y)
                if current.simplified == .terrainSeam,
                   !map.allowPlacement(current, atX: neighbour.x, y: neighbour.y, recheck: true) {
                    _ = map.setBackground(.terrainPipe, atX: neighbour.x, y: neighbour.y, check: false)
                }
            }
        }
    }

    private func repairShoals(around point: GridPoint) {
        // Keep shoal islands valid after a neighbouring tile changes.
        for dx in -1...1 {
            for dy in -1...1 {
                let x = point.x + dx
                let y = point.y + dy
                let current = map.backgroundElement(atX: x, y: y)
                if current.simplified == .terrainShoal,
                   !map.allowPlacement(current, atX: x, y: y, recheck: true) {
                    _ = map.setBackground(.terrainSea, atX: x, y: y, check: false)
                }
            }
        }
    }

    private func repairReefs(around point: GridPoint, placed: Element) {
        // Reefs cannot overlap land, and placing land removes nearby reefs.
        if placed.simplified == .terrainReef {
            clearReefLandCollisions(around: point)
        } else if placed.isLand {
            clearNearbyReefs(around: point)
        }
    }

    private func clearReefLandCollisions(around point: GridPoint) {
        for dx in -1...1 {
            for dy in -1...1 {
                let x = point.x + dx
                let y = point.y + dy
                guard map.backgroundElement(atX: x, y: y).isLand else { continue }
                _ = map.setBackground(.terrainSea, atX: x, y: y, check: false)
                let foreground = map.foregroundElement(atX: x, y: y)
                if !map.allowPlacement(foreground, atX: x, y: y, recheck: true) {
                    _ = map.setForeground(.unitEmpty, atX: x, y: y)
                }
            }
        }
    }

    private func clearNearbyReefs(around point: GridPoint) {
        for dx in -1...1 {
            for dy in -1...1 {
                let x = point.x + dx
                let y = point.y + dy
                guard map.backgroundElement(atX: x, y: y).simplified == .terrainReef else { continue }
                _ = map.setBackground(.terrainSea, atX: x, y: y, check: false)
            }
        }
    }

    private func repairSeaArcs(around point: GridPoint) {
        // A land change can make an existing sea arc illegal. Convert it to
        // the land-safe black arc, matching the legacy editor's repair step.
        for dx in -1...1 {
            for dy in -1...1 {
                let x = point.x + dx
                let y = point.y + dy
                let current = map.backgroundElement(atX: x, y: y)
                guard current.simplified == .extraSeaArc,
                      !map.allowPlacement(current, atX: x, y: y, recheck: true),
                      let offset = current.largeOffset() else { continue }
                let origin = GridPoint(x: x - offset.x, y: y - offset.y)
                place(.extraBlackArc, at: origin, allowMultipleHQ: true)
            }
        }
    }

}

private struct BresenhamState {
    var x: Int
    var y: Int
    let target: GridPoint
    let dx: Int
    let sx: Int
    let dy: Int
    let sy: Int
    var error: Int

    init(start: GridPoint, end: GridPoint) {
        x = start.x
        y = start.y
        target = end
        dx = abs(end.x - start.x)
        sx = start.x < end.x ? 1 : -1
        dy = -abs(end.y - start.y)
        sy = start.y < end.y ? 1 : -1
        error = dx + dy
    }

    var point: GridPoint { GridPoint(x: x, y: y) }
    var isDone: Bool { x == target.x && y == target.y }

    mutating func advance() {
        let e2 = 2 * error
        if e2 >= dy { error += dy; x += sx }
        if e2 <= dx { error += dx; y += sy }
    }
}
