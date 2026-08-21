import AppKit
import Foundation
import Observation
import AWEDCore

@MainActor
@Observable
final class EditorModel {
    var map: MapState
    var preferences: EditorPreferences
    var undoStack: [MapState] = []
    var redoStack: [MapState] = []
    var filename: URL?

    var selectedTool: EditorTool = .pencil
    var selectedTab: PaletteTab = .terrain
    var selectedElement: Element
    var selectedArmy = AWConstants.armyOrangeStar
    var selection: SelectionRect?
    var selectionFragment: MapFragment?
    var previewCells: Set<GridPoint> = []
    var pointerCell: GridPoint?
    var dialog: EditorDialog?
    var errorMessage: String?
    var isShowingError = false
    var pendingDocumentAction: PendingDocumentAction?
    var isShowingUnsavedChanges = false
    var statusMessage = ""

    private var dragStart: GridPoint?
    private var lastDragCell: GridPoint?
    private var movingSelectionOrigin: SelectionRect?
    private var movingSelection = false
    private var selectionNeedsCommit = false
    private var selectionUndoRecorded = false
    private var selectionEraseRect: SelectionRect?
    private var selectionIsOverlay = false

    init(preferences: EditorPreferences = .load()) {
        let validatedPreferences = preferences.validated()
        let initialMap = MapState(
            width: validatedPreferences.defaultWidth,
            height: validatedPreferences.defaultHeight,
            tileset: validatedPreferences.defaultTileset,
            defaultTerrain: validatedPreferences.defaultTerrain,
            defaultAuthor: validatedPreferences.defaultAuthor
        )
        self.preferences = validatedPreferences
        self.map = initialMap
        self.selectedElement = validatedPreferences.defaultTerrain
        self.statusMessage = "X: –, Y: –"
    }

    /// Creates a model around an existing map snapshot for read-only surfaces
    /// such as playtest. The editor's undo and document state remain empty so
    /// actions in that surface cannot mutate the source document accidentally.
    init(map: MapState, preferences: EditorPreferences = .load()) {
        let validatedPreferences = preferences.validated()
        self.preferences = validatedPreferences
        self.map = map
        self.selectedElement = map.backgroundElement(atX: 0, y: 0).simplified
        self.statusMessage = "X: –, Y: –"
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var hasSelection: Bool { selection != nil && selectionFragment != nil }
    var documentTitle: String { filename?.deletingPathExtension().lastPathComponent ?? map.name }

    func presentError(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        isShowingError = true
    }

    func updatePreferences(_ newPreferences: EditorPreferences) {
        preferences = newPreferences.validated()
        preferences.save()
    }

    func newMap() {
        map = MapState(
            width: preferences.defaultWidth,
            height: preferences.defaultHeight,
            tileset: preferences.defaultTileset,
            defaultTerrain: preferences.defaultTerrain,
            defaultAuthor: preferences.defaultAuthor
        )
        filename = nil
        undoStack.removeAll()
        redoStack.removeAll()
        clearSelection()
        selectedTool = .pencil
        selectedTab = .terrain
        selectedElement = preferences.defaultTerrain
        selectedArmy = AWConstants.armyOrangeStar
    }

    func requestNewDocument() {
        guard map.isDirty else { newMap(); return }
        pendingDocumentAction = .new
        isShowingUnsavedChanges = true
    }

    func requestOpenDocument(url: URL) {
        guard map.isDirty else {
            performDocumentAction(.open(url))
            return
        }
        pendingDocumentAction = .open(url)
        isShowingUnsavedChanges = true
    }

    func requestCloseDocument() { requestNewDocument() }

    func discardPendingDocumentAction() {
        guard let action = pendingDocumentAction else { return }
        pendingDocumentAction = nil
        isShowingUnsavedChanges = false
        performDocumentAction(action)
    }

    func completePendingDocumentActionAfterSave() {
        guard let action = pendingDocumentAction else { return }
        pendingDocumentAction = nil
        isShowingUnsavedChanges = false
        performDocumentAction(action)
    }

    private func performDocumentAction(_ action: PendingDocumentAction) {
        switch action {
        case .new:
            newMap()
        case .open(let url):
            do { try open(url: url) } catch { presentError(error) }
        }
    }

    func open(url: URL) throws {
        map = try MapFileCodec.read(from: url, defaultAuthor: preferences.defaultAuthor)
        filename = url
        undoStack.removeAll()
        redoStack.removeAll()
        clearSelection()
        selectedTool = .pencil
        selectedTab = .terrain
        selectedElement = preferences.defaultTerrain
        selectedArmy = AWConstants.armyOrangeStar
    }

    @discardableResult
    func save(to url: URL) throws -> MapWriteReport {
        let report = try MapFileCodec.write(map, to: url)
        filename = url
        map.setDirty(false)
        return report
    }

    func select(_ item: PaletteItem) {
        selectedTab = item.tab
        selectedElement = paletteElement(for: item)
        if selectedElement.isUnitNonEmpty { selectedArmy = selectedElement.army }
    }

    func paletteElement(for item: PaletteItem) -> Element {
        guard item.tab == .unit, item.element.isUnitNonEmpty else { return item.element }
        return item.element.changedArmy(selectedArmy)
    }

    func selectArmy(_ army: Int) {
        guard (0..<AWConstants.playableArmies).contains(army) else { return }
        selectedArmy = army
        guard selectedTab == .unit else { return }
        selectedElement = selectedElement.isUnitNonEmpty
            ? selectedElement.changedArmy(army)
            : Element.unitInfantry.changedArmy(army)
    }

    func isPaletteItemSelected(_ item: PaletteItem) -> Bool {
        if item.tab == .unit, item.element.isUnitNonEmpty {
            return selectedElement.isUnitNonEmpty && item.element.simplified == selectedElement.simplified
        }
        return item.element == selectedElement
    }

    func pick(at point: GridPoint) {
        guard point.x >= 0, point.x < map.width, point.y >= 0, point.y < map.height else { return }
        if selectedTab == .unit {
            let unit = map.foregroundElement(atX: point.x, y: point.y)
            guard unit.isUnitNonEmpty else { return }
            selectedElement = unit
            selectedArmy = unit.army
        } else {
            let background = map.backgroundElement(atX: point.x, y: point.y)
            if background.isExtra {
                selectedTab = .extra
                selectedElement = background.simplified
            } else if background.isTerrain || background.isBuilding {
                selectedTab = .terrain
                // Keep the exact army variant for properties while reducing
                // generated terrain subtile values back to their palette item.
                selectedElement = background.isBuilding ? background : background.simplified
            } else {
                selectedElement = preferences.defaultTerrain
            }
        }
    }

    func advancePaletteTab() {
        guard let currentIndex = PaletteTab.allCases.firstIndex(of: selectedTab) else { return }
        selectedTab = PaletteTab.allCases[(currentIndex + 1) % PaletteTab.allCases.count]
    }

    @discardableResult
    func cycleArmy(for wheelDelta: Double) -> Bool {
        guard wheelDelta != 0 else { return false }
        let change = wheelDelta > 0 ? 1 : -1

        if selectedElement.isBuilding, selectedElement != .buildingSilo {
            var army = selectedElement.army - change
            if army < 0 { army = AWConstants.armyNeutral }
            if army > AWConstants.armyNeutral { army = 0 }
            if army == AWConstants.armyNeutral, selectedElement.simplified == .buildingHQ {
                army = AWConstants.armyOrangeStar
            }
            selectedElement = selectedElement.changedArmy(army)
            if (0..<AWConstants.playableArmies).contains(army) { selectedArmy = army }
            return true
        }

        guard selectedElement.isUnitNonEmpty else { return false }
        var army = selectedElement.army - change
        if army < 0 { army = AWConstants.playableArmies - 1 }
        if army == AWConstants.armyNeutral { army = AWConstants.armyOrangeStar }
        selectedElement = selectedElement.changedArmy(army)
        selectedArmy = army
        return true
    }

    func setTool(_ tool: EditorTool) {
        if selectedTool == tool { return }
        if hasSelection { commitSelection() }
        selectedTool = tool
        previewCells.removeAll()
        dragStart = nil
        movingSelectionOrigin = nil
        movingSelection = false
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(map)
        map = previous
        clearSelection()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(map)
        map = next
        clearSelection()
    }

    func fill(_ element: Element) {
        addUndoPoint()
        map.fill(with: element)
    }

    func updateInformation(name: String, author: String, description: String) {
        addUndoPoint()
        map.setName(name)
        map.setAuthor(author)
        map.setDescription(description)
    }

    func updateSettings(width: Int, height: Int, tileset: Tileset) {
        addUndoPoint()
        _ = map.setSize(width: width, height: height)
        map.tileset = tileset
        map.updateDraw()
    }

    func deleteAllUnits() {
        addUndoPoint()
        for x in 0..<map.width {
            for y in 0..<map.height {
                _ = map.setForeground(.unitEmpty, atX: x, y: y)
            }
        }
    }

    func updatePointer(_ point: GridPoint?) {
        pointerCell = point
        if let point {
            statusMessage = "X: \(point.x + 1), Y: \(point.y + 1)"
        } else {
            statusMessage = "X: –, Y: –"
        }
    }

    func handlePointer(_ point: GridPoint, phase: PointerPhase, modifiers: PointerModifiers = .init()) {
        guard point.x >= 0, point.x < map.width, point.y >= 0, point.y < map.height else { return }
        updatePointer(point)
        switch phase {
        case .began:
            pointerBegan(at: point, modifiers: modifiers)
        case .changed:
            pointerChanged(to: point, modifiers: modifiers)
        case .ended:
            pointerEnded(at: point, modifiers: modifiers)
        }
    }

    func cancelPointer() {
        dragStart = nil
        lastDragCell = nil
        previewCells.removeAll()
        movingSelectionOrigin = nil
        movingSelection = false
    }

    func cancelSelection() {
        clearSelection()
    }

    func cutSelection() {
        guard let fragment = selectionFragment else { return }
        writeClipboard(fragment)
        if !selectionIsOverlay {
            addUndoPoint()
            if let movingSelectionOrigin {
                eraseSelectionContents(movingSelectionOrigin)
            } else if let selectionEraseRect {
                eraseSelectionContents(selectionEraseRect)
            } else {
                eraseSelectionContents(selection)
            }
        }
        clearSelection()
    }

    func copySelection() {
        guard let fragment = selectionFragment else { return }
        writeClipboard(fragment)
    }

    func pasteSelection(terrainOnly: Bool = false, unitsOnly: Bool = false) {
        guard var fragment = readClipboard() else { return }
        fragment = fragment.clipped(toWidth: map.width, height: map.height)
        if terrainOnly {
            fragment.foreground = Array(repeating: .unitEmpty, count: fragment.width * fragment.height)
        }
        if unitsOnly {
            fragment.background = Array(repeating: .terrainBlank, count: fragment.width * fragment.height)
            fragment.backgroundDraw = fragment.background
        }
        setTool(.selector)
        selectionFragment = fragment
        selection = SelectionRect(x: 0, y: 0, width: min(fragment.width, map.width), height: min(fragment.height, map.height))
        selectionNeedsCommit = true
        selectionUndoRecorded = false
        selectionEraseRect = nil
        selectionIsOverlay = true
    }

    func flipSelection(horizontal: Bool) {
        guard var fragment = selectionFragment else { return }
        markSelectionModified()
        var newBackground = fragment.background
        var newDraw = fragment.backgroundDraw
        var newForeground = fragment.foreground
        for x in 0..<fragment.width {
            for y in 0..<fragment.height {
                let targetX = horizontal ? fragment.width - x - 1 : x
                let targetY = horizontal ? y : fragment.height - y - 1
                let source = x * fragment.height + y
                let target = targetX * fragment.height + targetY
                newBackground[target] = fragment.background[source]
                newDraw[target] = fragment.backgroundDraw[source]
                newForeground[target] = fragment.foreground[source]
            }
        }
        fragment.background = newBackground
        fragment.backgroundDraw = newDraw
        fragment.foreground = newForeground
        selectionFragment = fragment
    }

    func rotateSelection(clockwise: Bool) {
        guard let fragment = selectionFragment else { return }
        markSelectionModified()
        var rotated = MapFragment(
            width: fragment.height,
            height: fragment.width,
            background: Array(repeating: .terrainSea, count: fragment.width * fragment.height),
            backgroundDraw: Array(repeating: .terrainSea, count: fragment.width * fragment.height),
            foreground: Array(repeating: .unitEmpty, count: fragment.width * fragment.height)
        )
        for x in 0..<fragment.width {
            for y in 0..<fragment.height {
                let targetX = clockwise ? fragment.height - y - 1 : y
                let targetY = clockwise ? x : fragment.width - x - 1
                rotated.setBackground(fragment.backgroundElement(atX: x, y: y), atX: targetX, y: targetY)
                rotated.setBackgroundDraw(fragment.backgroundDrawElement(atX: x, y: y), atX: targetX, y: targetY)
                rotated.setForeground(fragment.foregroundElement(atX: x, y: y), atX: targetX, y: targetY)
            }
        }
        selectionFragment = rotated
        if let selection {
            self.selection = SelectionRect(x: selection.x, y: selection.y, width: rotated.width, height: rotated.height)
        }
    }

    func deleteUnitsInSelection() {
        guard var fragment = selectionFragment else { return }
        markSelectionModified()
        fragment.foreground = Array(repeating: .unitEmpty, count: fragment.width * fragment.height)
        selectionFragment = fragment
    }

    func statusCounts() -> MapStatusCounts { MapStatusCounts(map: map) }

    private func addUndoPoint() {
        undoStack.append(map)
        if undoStack.count > preferences.undoLimit { undoStack.removeFirst(undoStack.count - preferences.undoLimit) }
        redoStack.removeAll()
    }

    private func markSelectionModified() {
        selectionNeedsCommit = true
        if !selectionIsOverlay, selectionEraseRect == nil {
            selectionEraseRect = selection
        }
    }

    private func ensureSelectionUndoPoint() {
        guard !selectionUndoRecorded else { return }
        addUndoPoint()
        selectionUndoRecorded = true
    }

    private func pointerBegan(at point: GridPoint, modifiers: PointerModifiers) {
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

    private func pointerChanged(to point: GridPoint, modifiers: PointerModifiers) {
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

    private func pointerEnded(at point: GridPoint, modifiers: PointerModifiers) {
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
        case .rectangle, .filledRectangle:
            let rect = normalizedRect(from: start, to: end)
            var cells = Set<GridPoint>()
            for x in rect.x..<(rect.x + rect.width) {
                for y in rect.y..<(rect.y + rect.height) {
                    if tool == .filledRectangle || x == rect.x || y == rect.y || x == rect.x + rect.width - 1 || y == rect.y + rect.height - 1 {
                        cells.insert(GridPoint(x: x, y: y))
                    }
                }
            }
            return cells
        default: return []
        }
    }

    private func outlineCells(from start: GridPoint, to end: GridPoint) -> Set<GridPoint> {
        let rect = normalizedRect(from: start, to: end)
        var cells = Set<GridPoint>()
        for x in rect.x..<(rect.x + rect.width) {
            cells.insert(GridPoint(x: x, y: rect.y))
            cells.insert(GridPoint(x: x, y: rect.y + rect.height - 1))
        }
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
        var points = Set<GridPoint>()
        var x = start.x
        var y = start.y
        let dx = abs(end.x - start.x)
        let sx = x < end.x ? 1 : -1
        let dy = -abs(end.y - start.y)
        let sy = y < end.y ? 1 : -1
        var error = dx + dy
        while true {
            if x >= 0, x < map.width, y >= 0, y < map.height { points.insert(GridPoint(x: x, y: y)) }
            if x == end.x, y == end.y { break }
            let e2 = 2 * error
            if e2 >= dy { error += dy; x += sx }
            if e2 <= dx { error += dx; y += sy }
        }
        return points
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
            queue.append(GridPoint(x: point.x - 1, y: point.y))
            queue.append(GridPoint(x: point.x + 1, y: point.y))
            queue.append(GridPoint(x: point.x, y: point.y - 1))
            queue.append(GridPoint(x: point.x, y: point.y + 1))
        }
    }

    private func place(_ requestedElement: Element, at point: GridPoint, nextSprite: Bool = false, allowMultipleHQ: Bool = false) {
        guard point.x >= 0, point.x < map.width, point.y >= 0, point.y < map.height else { return }
        var element = requestedElement
        let previousBackground = map.backgroundElement(atX: point.x, y: point.y)
        if element.isBackground {
            if nextSprite, element.isTerrain, element.simplified == previousBackground.simplified { element = previousBackground.nextSprite() }
            if element == previousBackground, !nextSprite { return }
            // Drawing a road over a river/bridge in the original editor is a
            // bridge gesture, not a request to erase the crossing.
            if element.simplified == .terrainRoad,
               previousBackground.simplified == .terrainRiver || previousBackground.simplified == .terrainBridgeH {
                element = .terrainBridgeH
            }
            if element == .terrainBridgeH {
                let up = map.backgroundElement(atX: point.x, y: point.y - 1)
                let down = map.backgroundElement(atX: point.x, y: point.y + 1)
                let left = map.backgroundElement(atX: point.x - 1, y: point.y)
                let right = map.backgroundElement(atX: point.x + 1, y: point.y)
                if previousBackground.simplified == .terrainRiver { element = (up.isRiver || down.isRiver) ? .terrainBridgeH : .terrainBridgeV }
                else if up.isLand || down.isLand || up == .terrainBridgeV || down == .terrainBridgeV { element = .terrainBridgeV }
                else { element = (left.isLand || right.isLand || left == .terrainBridgeH || right == .terrainBridgeH) ? .terrainBridgeH : .terrainBridgeH }
            }
            // The bridge tool may resolve a horizontal/vertical sprite from the
            // surrounding map, but the resolved value still has to pass the
            // same placement rules as every other terrain.
            guard map.allowPlacement(element, atX: point.x, y: point.y) else { return }
            if previousBackground.isExtra, previousBackground.size > 1, previousBackground != previousBackground.simplified, let offset = previousBackground.largeOffset() {
                for dx in -offset.x..<(previousBackground.size - offset.x) {
                    for dy in -offset.y..<(previousBackground.size - offset.y) {
                        _ = map.setBackground(previousBackground.base, atX: point.x + dx, y: point.y + dy, check: false)
                    }
                }
            }
            _ = map.setBackground(element, atX: point.x, y: point.y)
            if !map.allowPlacement(map.foregroundElement(atX: point.x, y: point.y), atX: point.x, y: point.y, recheck: true) {
                _ = map.setForeground(.unitEmpty, atX: point.x, y: point.y)
            }
            if element.isExtra, element.size > 1, element == element.simplified {
                for dx in 0..<element.size {
                    for dy in 0..<element.size {
                        _ = map.setBackground(Element(element.topLeft + AWConstants.extraColumns * dy + dx), atX: point.x + dx - 1, y: point.y + dy - 1, check: false)
                    }
                }
            }
            repairTerrainAround(point, previousBackground: previousBackground, placed: element)
            if (element.simplified == .buildingHQ || element.simplified == .buildingLab), !allowMultipleHQ {
                for x in 0..<map.width {
                    for y in 0..<map.height where !(x == point.x && y == point.y) {
                        let existing = map.backgroundElement(atX: x, y: y)
                        if (existing.simplified == .buildingHQ || existing.simplified == .buildingLab), existing.army == element.army {
                            _ = map.setBackground(.terrainPlain, atX: x, y: y)
                        }
                    }
                }
            }
            map.updateDraw(x: point.x - 2, y: point.y - 2, width: 5, height: 5)
        } else if element.isForeground {
            _ = map.setForeground(element == .unitDelete ? .unitEmpty : element, atX: point.x, y: point.y)
        }
    }

    private func repairTerrainAround(_ point: GridPoint, previousBackground: Element, placed: Element) {
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

        // Reefs cannot overlap land, and placing land removes nearby reefs.
        if placed.simplified == .terrainReef {
            for dx in -1...1 {
                for dy in -1...1 {
                    let x = point.x + dx
                    let y = point.y + dy
                    if map.backgroundElement(atX: x, y: y).isLand {
                        _ = map.setBackground(.terrainSea, atX: x, y: y, check: false)
                        if !map.allowPlacement(map.foregroundElement(atX: x, y: y), atX: x, y: y, recheck: true) {
                            _ = map.setForeground(.unitEmpty, atX: x, y: y)
                        }
                    }
                }
            }
        } else if placed.isLand {
            for dx in -1...1 {
                for dy in -1...1 {
                    let x = point.x + dx
                    let y = point.y + dy
                    if map.backgroundElement(atX: x, y: y).simplified == .terrainReef {
                        _ = map.setBackground(.terrainSea, atX: x, y: y, check: false)
                    }
                }
            }
        }

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

    private func clearSelection() {
        selection = nil
        selectionFragment = nil
        previewCells.removeAll()
        movingSelectionOrigin = nil
        movingSelection = false
        selectionNeedsCommit = false
        selectionUndoRecorded = false
        selectionEraseRect = nil
        selectionIsOverlay = false
    }

    private func commitSelection() {
        commitSelection(allowMultipleHQ: true)
    }

    private func commitSelection(allowMultipleHQ: Bool) {
        guard let selection, let fragment = selectionFragment else { clearSelection(); return }
        let moved = movingSelectionOrigin.map { $0 != selection } ?? false
        guard selectionNeedsCommit || moved else { clearSelection(); return }
        ensureSelectionUndoPoint()
        if !selectionIsOverlay {
            if let origin = movingSelectionOrigin, moved {
                eraseSelectionContents(origin)
            } else if let eraseRect = selectionEraseRect {
                eraseSelectionContents(eraseRect)
            }
        }
        apply(fragment, at: selection.x, y: selection.y, allowMultipleHQ: allowMultipleHQ)
        clearSelection()
    }

    private func eraseSelectionContents(_ rect: SelectionRect?) {
        guard let rect else { return }
        for x in rect.x..<(rect.x + rect.width) {
            for y in rect.y..<(rect.y + rect.height) {
                _ = map.setBackground(preferences.defaultTerrain, atX: x, y: y, check: false)
                _ = map.setForeground(.unitEmpty, atX: x, y: y)
            }
        }
        map.updateDraw(x: rect.x - 2, y: rect.y - 2, width: rect.width + 4, height: rect.height + 4)
    }

    private func apply(_ fragment: MapFragment?, at x: Int, y: Int, allowMultipleHQ: Bool) {
        guard let fragment else { return }
        for localX in 0..<fragment.width {
            for localY in 0..<fragment.height {
                let targetX = x + localX
                let targetY = y + localY
                let background = fragment.backgroundElement(atX: localX, y: localY)
                if background != .terrainBlank { _ = map.setBackground(background, atX: targetX, y: targetY, check: false) }
                _ = map.setForeground(fragment.foregroundElement(atX: localX, y: localY), atX: targetX, y: targetY)
            }
        }
        map.updateDraw(x: x - 2, y: y - 2, width: fragment.width + 4, height: fragment.height + 4)
        _ = allowMultipleHQ
    }

    private let clipboardType = NSPasteboard.PasteboardType("com.awsmapeditor.map-part")

    private func writeClipboard(_ fragment: MapFragment) {
        guard let data = try? JSONEncoder().encode(fragment) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: clipboardType)
    }

    private func readClipboard() -> MapFragment? {
        guard let data = NSPasteboard.general.data(forType: clipboardType) else { return nil }
        return try? JSONDecoder().decode(MapFragment.self, from: data)
    }
}

struct MapStatusCounts: Sendable {
    let values: [[Int]]
    let unitCounts: [Int]
    let pipeSeams: Int
    let silos: Int
    let totalProperties: Int

    init(map: MapState) {
        let buildingTypes: [Element] = [.buildingCity, .buildingBase, .buildingPort, .buildingAirport, .buildingTower]
        values = buildingTypes.map { building in
            (0...AWConstants.armyNeutral).map { army in
                map.background.count { $0 == building.changedArmy(army) }
            }
        }
        unitCounts = (0..<AWConstants.playableArmies).map { army in
            map.foreground.count { $0.isUnitNonEmpty && $0.army == army }
        }
        pipeSeams = map.background.count { $0.simplified == .terrainSeam }
        silos = map.background.count { $0.simplified == .buildingSilo }
        totalProperties = map.countBuildingsAndSeams()
    }
}
