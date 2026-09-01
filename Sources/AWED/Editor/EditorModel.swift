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

    /// Optional render-only palette used by read-only surfaces such as
    /// playtest. The editor uses `visualVariant` so every supported art
    /// variant can be previewed while authoring without changing the file
    /// format's tileset contract.
    var spritePalette: SpritePalette?
    var visualVariant: MapVisualVariant

    var dragStart: GridPoint?
    var lastDragCell: GridPoint?
    var movingSelectionOrigin: SelectionRect?
    var movingSelection = false
    var selectionNeedsCommit = false
    var selectionUndoRecorded = false
    var selectionEraseRect: SelectionRect?
    var selectionIsOverlay = false

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
        self.visualVariant = .defaultVariant(for: initialMap.tileset)
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
        self.visualVariant = .defaultVariant(for: map.tileset)
        self.selectedElement = map.backgroundElement(atX: 0, y: 0).simplified
        self.statusMessage = "X: –, Y: –"
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var renderPalette: SpritePalette { spritePalette ?? visualVariant.palette }
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
        spritePalette = nil
        visualVariant = .defaultVariant(for: map.tileset)
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
        spritePalette = nil
        visualVariant = .defaultVariant(for: map.tileset)
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
        let army = PaletteCatalog.visibleArmies(for: map.tileset).contains(selectedArmy)
            ? selectedArmy
            : PaletteCatalog.visibleArmies(for: map.tileset).first ?? AWConstants.armyOrangeStar
        return item.element.changedArmy(army)
    }

    func selectArmy(_ army: Int) {
        guard PaletteCatalog.visibleArmies(for: map.tileset).contains(army) else { return }
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
                if PaletteCatalog.tabs(for: map.tileset).contains(.extra) {
                    selectedTab = .extra
                    selectedElement = background.simplified
                } else {
                    // Extra terrain is not editable from this tileset's palette.
                    selectedTab = .terrain
                    selectedElement = preferences.defaultTerrain
                }
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
        let tabs = PaletteCatalog.tabs(for: map.tileset)
        guard let currentIndex = tabs.firstIndex(of: selectedTab), !tabs.isEmpty else {
            selectedTab = tabs.first ?? .terrain
            return
        }
        selectedTab = tabs[(currentIndex + 1) % tabs.count]
    }

    @discardableResult
    func cycleArmy(for wheelDelta: Double) -> Bool {
        guard wheelDelta != 0 else { return false }
        if selectedElement.isBuilding, selectedElement != .buildingSilo {
            return cycleBuildingArmy(direction: wheelDelta > 0 ? 1 : -1)
        }
        guard selectedElement.isUnitNonEmpty else { return false }
        return cycleUnitArmy(direction: wheelDelta > 0 ? 1 : -1)
    }

    private func cycleBuildingArmy(direction: Int) -> Bool {
        let armies = PaletteCatalog.visibleArmies(for: map.tileset) + [AWConstants.armyNeutral]
        guard let army = nextArmy(in: armies, direction: direction, current: selectedElement.army) else { return false }
        let normalizedArmy = army == AWConstants.armyNeutral && selectedElement.simplified == .buildingHQ
            ? AWConstants.armyOrangeStar
            : army
        selectedElement = selectedElement.changedArmy(normalizedArmy)
        if PaletteCatalog.visibleArmies(for: map.tileset).contains(normalizedArmy) {
            selectedArmy = normalizedArmy
        }
        return true
    }

    private func cycleUnitArmy(direction: Int) -> Bool {
        let armies = PaletteCatalog.visibleArmies(for: map.tileset)
        guard let army = nextArmy(in: armies, direction: direction, current: selectedElement.army) else { return false }
        selectedElement = selectedElement.changedArmy(army)
        selectedArmy = army
        return true
    }

    private func nextArmy(in armies: [Int], direction: Int, current: Int) -> Int? {
        guard !armies.isEmpty else { return nil }
        let currentIndex = armies.firstIndex(of: current) ?? 0
        return armies[(currentIndex - direction + armies.count) % armies.count]
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
        if visualVariant.baseTileset != map.tileset {
            visualVariant = .defaultVariant(for: map.tileset)
        }
        normalizePaletteTab()
        clearSelection()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(map)
        map = next
        if visualVariant.baseTileset != map.tileset {
            visualVariant = .defaultVariant(for: map.tileset)
        }
        normalizePaletteTab()
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
        let tilesetChanged = map.tileset != tileset
        map.tileset = tileset
        map.updateDraw()
        if tilesetChanged {
            visualVariant = .defaultVariant(for: tileset)
            normalizePaletteTab()
        }
    }

    /// Selects an authoring palette. GBA weather variants affect only the
    /// rendered art; switching the game family still updates the persisted
    /// base tileset so playtest and file-format rules remain correct.
    func setVisualVariant(_ variant: MapVisualVariant) {
        if map.tileset != variant.baseTileset {
            addUndoPoint()
            map.tileset = variant.baseTileset
            map.updateDraw()
            normalizePaletteTab()
        }
        visualVariant = variant
    }

    private func normalizePaletteTab() {
        if !PaletteCatalog.tabs(for: map.tileset).contains(selectedTab) {
            selectedTab = .terrain
        }
        normalizeSelectedArmy()
    }

    private func normalizeSelectedArmy() {
        let armies = PaletteCatalog.visibleArmies(for: map.tileset)
        guard !armies.contains(selectedArmy) else { return }
        selectedArmy = armies.first ?? AWConstants.armyOrangeStar
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

    func statusCounts() -> MapStatusCounts { MapStatusCounts(map: map) }

    let clipboardType = NSPasteboard.PasteboardType("com.awsmapeditor.map-part")
}
