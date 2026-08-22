import AppKit
import Observation
import SwiftUI
import AWEDCore

struct PlaytestLaunch: Identifiable {
    let id = UUID()
    let map: MapState
    let visualVariant: MapVisualVariant
}

@MainActor
@Observable
final class PlaytestSession {
    private static let pipeSeamStartingHealth = 99

    private struct PlaytestCargo {
        let unit: Element
        let health: Int
        let fuel: Int
        let ammo: Int?
    }

    private struct MovementPath {
        let movement: Int
        let steps: Int
        let previous: GridPoint?
    }

    /// The CPU deliberately keeps its action vocabulary small. It evaluates
    /// the same legal actions exposed to the player, then chooses the highest
    /// immediate utility score rather than searching for a perfect line.
    private enum CPUAction {
        case attack(origin: GridPoint, target: GridPoint)
        case capture(point: GridPoint)
        case build(point: GridPoint, option: PlaytestProductionOption)
        case move(origin: GridPoint, destination: GridPoint)
        case load(transport: GridPoint, cargo: GridPoint)
        case unload(transport: GridPoint, destination: GridPoint)
        case join(origin: GridPoint, destination: GridPoint)
        case resupply(point: GridPoint)
        case wait(point: GridPoint)
    }

    private struct CPUPlan {
        let score: Double
        let action: CPUAction
    }

    private struct CPUThreatKey: Hashable {
        let unitValue: Int
        let point: GridPoint
        let health: Int
    }

    private struct CPUPathKey: Hashable {
        let origin: GridPoint
        let unitValue: Int
        let fuel: Int
    }

    private struct CPUAttackKey: Hashable {
        let origin: GridPoint
        let unitValue: Int
        let primaryAmmo: Int
        let hasMoved: Bool
    }

    private struct CPUEnemyInfo {
        let point: GridPoint
        let unit: Element
        let stats: PlaytestUnitStats
    }

    private struct CPUTransportKey: Hashable {
        let transportValue: Int
        let cargoValue: Int
    }

    /// A single planning pass should inspect the board once. The previous
    /// planner rediscovered the same units, properties, and opponents for
    /// every action family and for every candidate score.
    private struct CPUPlanningSnapshot {
        let ownUnitPoints: [GridPoint]
        let enemyUnitPoints: [GridPoint]
        let enemyUnits: [CPUEnemyInfo]
        let ownPropertyPoints: [GridPoint]
        let enemyPropertyPoints: [GridPoint]
        let pipeSeamPoints: [GridPoint]
        let ownCounts: [Int: Int]
        let ownDomains: (land: Int, air: Int, sea: Int)
        let enemyDomains: (land: Int, air: Int, sea: Int)
    }

    let sourceMap: MapState
    let ruleset: PlaytestRuleset
    /// The art variant selected in the editor when this playtest was opened.
    /// It is intentionally not persisted in `MapState`; the map file format
    /// still stores only its base tileset.
    let visualVariant: MapVisualVariant
    private let initialWeather: PlaytestWeather

    var map: MapState {
        didSet {
            invalidateVisibilityCache()
            mapRevision &+= 1
        }
    }
    /// A scalar render revision avoids making SwiftUI compare every terrain,
    /// draw-layer, and foreground array on each CPU move just to refresh the
    /// read-only map backdrop.
    private(set) var mapRevision = 0
    var activeArmy: Int {
        didSet { invalidateVisibilityCache() }
    }
    var turn = 1
    /// The value shown in the weather picker. When this is `.random`, the
    /// concrete `weather` value is rolled once per new day and is used by all
    /// movement, vision, range, and rendering decisions.
    var weatherMode: PlaytestWeather = .clear
    var weather: PlaytestWeather = .clear {
        didSet { invalidateVisibilityCache() }
    }
    var fogOfWarEnabled = false {
        didSet { invalidateVisibilityCache() }
    }
    var selectedPoint: GridPoint?
    var reachableCells: Set<GridPoint> = []
    var attackableCells: Set<GridPoint> = []
    var attackPreviewOrigin: GridPoint?
    var attackPreviewCells: Set<GridPoint> = []
    /// The route currently being committed by the CPU. It grows one
    /// cardinal tile at a time so the orange arrow always follows the legal
    /// path selected by the planner.
    var cpuMovementPath: [GridPoint] = []
    /// The route currently previewed by the player while dragging a selected
    /// unit. This is render-only state; the map changes only when the drag is
    /// released on the route's final tile.
    var playerMovementPath: [GridPoint] = []
    var captureableCells: Set<GridPoint> = []
    fileprivate var productionOptions: [PlaytestProductionOption] = []
    var movedCells: Set<GridPoint> = []
    var funds: [Int: Int]
    var unitHealth: [GridPoint: Int] = [:]
    /// Infantry and Mech display this resource as rations. AW2 supplies
    /// cartridge-accurate per-unit fuel capacities through the rules layer.
    var unitFuel: [GridPoint: Int] = [:]
    var unitAmmo: [GridPoint: Int] = [:]
    var submergedUnits: Set<GridPoint> = [] {
        didSet {
            invalidateVisibilityCache()
            submergedRevision &+= 1
        }
    }
    private(set) var submergedRevision = 0
    var captureProgress: [GridPoint: Int] = [:]
    var loadableCells: Set<GridPoint> = []
    var joinableCells: Set<GridPoint> = []
    var unloadableCells: Set<GridPoint> = []
    var refuelableCells: Set<GridPoint> = []
    var siloTargetCells: Set<GridPoint> = []
    var winnerArmy: Int?
    var statusMessage: String

    private let armies: [Int]
    private var defeatedArmies: Set<Int> = []
    private var cargo: [GridPoint: [PlaytestCargo]] = [:]
    /// Pipe seams are map objectives rather than units. The cartridges treat
    /// them as 99-HP structures, so keep their damage separate from unit HP
    /// while the playtest mutates the in-memory map.
    private var pipeSeamHealth: [GridPoint: Int] = [:]
    private var usedMissileSilos: Set<GridPoint> = []
    private var isSelectingSiloTarget = false
    @ObservationIgnored private var isAnimatingCPUMovement = false
    private var isExecutingCPU = false
    @ObservationIgnored private var cpuTask: Task<Void, Never>?
    @ObservationIgnored private var cpuRunID = UUID()
    @ObservationIgnored private var cpuPlanningSnapshot: CPUPlanningSnapshot?
    @ObservationIgnored private var cpuThreatCache: [CPUThreatKey: Int] = [:]
    @ObservationIgnored private var cpuMovementPathCache: [CPUPathKey: [GridPoint: MovementPath]] = [:]
    @ObservationIgnored private var cpuAttackableCache: [CPUAttackKey: Set<GridPoint>] = [:]
    @ObservationIgnored private var cpuNearestEnemyDistanceCache: [GridPoint: Int] = [:]
    @ObservationIgnored private var cpuTransportDropOffCache: [CPUTransportKey: [GridPoint]] = [:]
    @ObservationIgnored private var visibilityRevision = 0
    @ObservationIgnored private var cachedVisibilityRevision = -1
    @ObservationIgnored private var cachedVisibleCells: Set<GridPoint> = []
    @ObservationIgnored private var cachedMapPoints: [GridPoint] = []
    @ObservationIgnored private var cachedMapPointWidth = -1
    @ObservationIgnored private var cachedMapPointHeight = -1

    /// The moving CPU unit remains visually bright until its route has been
    /// committed. The render layer reads this alongside the growing route so
    /// already-finished CPU actions can still use the normal spent-unit tint.
    var isCPUMovementAnimating: Bool { isAnimatingCPUMovement }

    init(map: MapState, visualVariant: MapVisualVariant? = nil) {
        let resolvedRuleset = map.tileset.playtestRuleset
        let resolvedVariant: MapVisualVariant
        if let visualVariant, visualVariant.baseTileset == map.tileset {
            resolvedVariant = visualVariant
        } else {
            resolvedVariant = .defaultVariant(for: map.tileset)
        }

        sourceMap = map
        self.map = map
        ruleset = resolvedRuleset
        self.visualVariant = resolvedVariant
        initialWeather = PlaytestRulebook.initialWeather(for: resolvedVariant, ruleset: resolvedRuleset)
        armies = Self.armies(in: map)
        let initialArmy = armies.first ?? AWConstants.armyOrangeStar
        activeArmy = initialArmy
        weatherMode = initialWeather
        weather = initialWeather
        funds = Dictionary(uniqueKeysWithValues: armies.map { ($0, 10_000) })
        statusMessage = armies.isEmpty
            ? "No playable armies are placed on this map yet."
            : "Select a \(PaletteCatalog.armyName(initialArmy, tileset: map.tileset)) unit to begin."
        initializeUnitResources()
        initializePipeSeams()
        _ = processTurnStart(for: initialArmy)
        _ = resolveRouting()
        runCPUIfNeeded()
    }

    func setWeatherMode(_ mode: PlaytestWeather) {
        weatherMode = mode
        weather = mode == .random
            ? PlaytestRulebook.randomWeather(for: ruleset)
            : mode
        refreshSelection()
    }

    private func advanceRandomWeatherIfNeeded() {
        guard weatherMode == .random else { return }
        weather = PlaytestRulebook.randomWeather(for: ruleset)
    }

    var activeArmyName: String { armyName(activeArmy) }
    var activeArmyIsCPU: Bool { isCPUArmy(activeArmy) }
    var activeFunds: Int { funds[activeArmy, default: 0] }
    /// GB Wars uses ordinary four-sided cells with an alternating horizontal
    /// offset between rows in both the editor and playtest canvas.
    var isStaggeredGrid: Bool {
        MapCanvasMetrics.isStaggeredGB(map: map, palette: displayPalette)
    }

    private func armyName(_ army: Int) -> String {
        PaletteCatalog.armyName(army, tileset: map.tileset)
    }
    var isGameOver: Bool { winnerArmy != nil || survivingArmies.isEmpty }
    var isFogOfWarActive: Bool {
        PlaytestRulebook.fogOfWarIsActive(
            ruleset: ruleset,
            manualFogEnabled: fogOfWarEnabled,
            weather: weather
        )
    }
    var isFogForcedByWeather: Bool {
        ruleset == .dualStrike && weather == .rain
    }

    private var survivingArmies: [Int] {
        armies.filter { !defeatedArmies.contains($0) }
    }

    var selectedUnitName: String? {
        guard let selectedPoint, let unit = unit(at: selectedPoint) else { return nil }
        return PaletteCatalog.label(for: unit, tileset: map.tileset)
    }

    var selectedUnitHealth: Int? {
        guard let selectedPoint, unit(at: selectedPoint) != nil else { return nil }
        return unitHealth[selectedPoint, default: 100]
    }

    var selectedUnitFuel: Int? {
        guard let selectedPoint, unit(at: selectedPoint) != nil else { return nil }
        return unitFuel[selectedPoint, default: maxFuel(for: selectedPoint)]
    }

    var selectedUnitMaxFuel: Int? {
        guard let selectedPoint, let unit = unit(at: selectedPoint) else { return nil }
        return PlaytestRulebook.maxFuel(for: unit, ruleset: ruleset)
    }

    var selectedUnitAmmo: Int? {
        guard let selectedPoint, let unit = unit(at: selectedPoint),
              PlaytestRulebook.primaryAmmo(for: unit, ruleset: ruleset) != nil else { return nil }
        return unitAmmo[selectedPoint, default: PlaytestRulebook.primaryAmmo(for: unit, ruleset: ruleset) ?? 0]
    }

    var selectedSubmarineIsSubmerged: Bool {
        guard let selectedPoint, unit(at: selectedPoint)?.simplified == .unitSub else { return false }
        return submergedUnits.contains(selectedPoint)
    }

    var selectedUnitIsSubmarine: Bool {
        guard let selectedPoint else { return false }
        return unit(at: selectedPoint)?.simplified == .unitSub
    }

    var selectedUnitCanLaunchSilo: Bool {
        guard ruleset == .advanceWars2 || ruleset == .dualStrike,
              let selectedPoint,
              let unit = unit(at: selectedPoint),
              !movedCells.contains(selectedPoint),
              unit.simplified == .unitInfantry || unit.simplified == .unitMech,
              map.backgroundElement(atX: selectedPoint.x, y: selectedPoint.y).simplified == .buildingSilo else { return false }
        return !usedMissileSilos.contains(selectedPoint)
    }

    /// A render-only map snapshot. Terrain remains known under Fog of War;
    /// unseen enemy units disappear and unseen property ownership is shown as
    /// neutral until a friendly unit's vision reaches the square.
    var displayMap: MapState {
        var result = map
        // Weather affects the art palette in the editor's playtest without
        // mutating the source map or its persisted tileset/ruleset.
        result.tileset = displayTileset

        guard isFogOfWarActive || !submergedUnits.isEmpty else { return result }
        let visibleCells = visibleCells()
        for x in 0..<map.width {
            for y in 0..<map.height {
                let point = GridPoint(x: x, y: y)
                let unit = map.foregroundElement(atX: x, y: y)
                if unit.isUnitNonEmpty, unit.army != activeArmy,
                   (isFogOfWarActive || submergedUnits.contains(point)), !visibleCells.contains(point) {
                    _ = result.setForeground(.unitEmpty, atX: x, y: y)
                }

                let building = map.backgroundElement(atX: x, y: y)
                if isFogOfWarActive, building.isBuilding, building.army != activeArmy, !visibleCells.contains(point) {
                    _ = result.setBackground(building.changedArmy(AWConstants.armyNeutral), atX: x, y: y, check: false)
                }
            }
        }
        return result
    }

    var displayPalette: SpritePalette {
        switch visualVariant {
        case .famicomWars:
            return .famicomWars
        case .gbWars:
            return .gbWars
        case .dualStrikeWasteland where weather == .clear:
            return .tileset(.wasteland)
        default:
            return PlaytestRulebook.visualPalette(for: ruleset, weather: weather)
        }
    }

    private var displayTileset: Tileset {
        switch visualVariant {
        case .famicomWars:
            return .famicomWars
        case .gbWars:
            return .gbWars
        case .dualStrikeWasteland where weather == .clear:
            return .wasteland
        default:
            return PlaytestRulebook.visualTileset(for: ruleset, weather: weather)
        }
    }

    var selectedUnitResourceLabel: String? {
        guard let selectedPoint, let unit = unit(at: selectedPoint) else { return nil }
        return PlaytestRulebook.resourceLabel(for: unit)
    }

    var selectedTransportCapacity: Int? {
        guard let selectedPoint, let unit = unit(at: selectedPoint) else { return nil }
        let capacity = PlaytestRulebook.transportCapacity(for: unit)
        return capacity > 0 ? capacity : nil
    }

    var selectedCargoCount: Int {
        guard let selectedPoint else { return 0 }
        return cargo[selectedPoint, default: []].count
    }

    var selectedCargoSummary: String? {
        guard let selectedPoint, let loaded = cargo[selectedPoint], !loaded.isEmpty else { return nil }
        return loaded.map { PaletteCatalog.label(for: $0.unit, tileset: map.tileset) }.joined(separator: ", ")
    }

    var selectedTransportCanResupply: Bool {
        guard let selectedPoint,
              let unit = unit(at: selectedPoint),
              unit.simplified == .unitAPC || unit.simplified == .unitBlackBoat else { return false }
        return !refuelableCells.isEmpty
    }

    var selectedTransportIsBlackBoat: Bool {
        guard let selectedPoint else { return false }
        return unit(at: selectedPoint)?.simplified == .unitBlackBoat
    }

    func unitName(at point: GridPoint) -> String? {
        guard let unit = unit(at: point) else { return nil }
        return PaletteCatalog.label(for: unit, tileset: map.tileset)
    }

    var selectedBuildingName: String? {
        guard let selectedPoint,
              map.foregroundElement(atX: selectedPoint.x, y: selectedPoint.y) == .unitEmpty else { return nil }
        let building = map.backgroundElement(atX: selectedPoint.x, y: selectedPoint.y)
        return building.isBuilding ? PaletteCatalog.label(for: building, tileset: map.tileset) : nil
    }

    var selectedBuildingOwnerName: String? {
        guard let selectedPoint else { return nil }
        let building = map.backgroundElement(atX: selectedPoint.x, y: selectedPoint.y)
        guard building.isBuilding else { return nil }
        return armyName(building.army)
    }

    var selectedCaptureProgress: String? {
        guard let selectedPoint, captureProgress[selectedPoint] != nil else { return nil }
        return "Capture progress: \(captureProgress[selectedPoint, default: 0])/20"
    }

    func restart() {
        stopCPU()
        map = sourceMap
        activeArmy = armies.first ?? AWConstants.armyOrangeStar
        turn = 1
        weatherMode = initialWeather
        weather = initialWeather
        fogOfWarEnabled = false
        funds = Dictionary(uniqueKeysWithValues: armies.map { ($0, 10_000) })
        initializeUnitResources()
        initializePipeSeams()
        captureProgress.removeAll()
        cargo.removeAll()
        submergedUnits.removeAll()
        usedMissileSilos.removeAll()
        isSelectingSiloTarget = false
        siloTargetCells.removeAll()
        winnerArmy = nil
        defeatedArmies.removeAll()
        movedCells.removeAll()
        clearCPUMovementPreview()
        clearSelection()
        statusMessage = armies.isEmpty
            ? "No playable armies are placed on this map yet."
            : "Select a \(armyName(activeArmy)) unit to begin."
        _ = processTurnStart(for: activeArmy)
        _ = resolveRouting()
        runCPUIfNeeded()
    }

    func stopCPU() {
        cpuRunID = UUID()
        cpuTask?.cancel()
        cpuTask = nil
        isExecutingCPU = false
        clearCPUMovementPreview()
    }

    func handleTap(_ point: GridPoint) {
        guard isValid(point), !isGameOver else { return }
        guard !isCPUArmy(activeArmy) else {
            statusMessage = "\(activeArmyName) is controlled by the CPU."
            return
        }

        clearAttackPreview()
        clearPlayerMovementPreview()

        if isSelectingSiloTarget {
            launchSilo(at: point)
            return
        }

        if loadableCells.contains(point) {
            if let selectedPoint,
               let selectedUnit = unit(at: selectedPoint),
               PlaytestRulebook.transportCapacity(for: selectedUnit) > 0 {
                loadUnit(from: point)
            } else {
                moveSelectedUnit(to: point)
            }
            return
        }

        if joinableCells.contains(point) {
            joinUnit(to: point)
            return
        }

        if unloadableCells.contains(point) {
            unloadUnit(to: point)
            return
        }

        if attackableCells.contains(point) {
            attack(to: point)
            return
        }

        if reachableCells.contains(point) {
            moveSelectedUnit(to: point)
            return
        }

        if selectedPoint == point {
            clearSelection()
            statusMessage = "Selection cleared."
            return
        }

        let unit = map.foregroundElement(atX: point.x, y: point.y)
        if unit.isUnitNonEmpty {
            guard unit.army == activeArmy else {
                clearSelection()
                statusMessage = (isFogOfWarActive || submergedUnits.contains(point)) && !isVisible(point)
                    ? "No enemy unit is visible at that space."
                    : "That unit belongs to \(armyName(unit.army))."
                return
            }
            guard PlaytestRulebook.stats(for: unit, ruleset: ruleset) != nil else {
                clearSelection()
                statusMessage = "\(PaletteCatalog.label(for: unit, tileset: map.tileset)) is not available in \(ruleset.displayName)."
                return
            }
            guard !movedCells.contains(point) else {
                clearSelection()
                statusMessage = "That unit has already acted this turn."
                return
            }
            selectUnit(at: point)
            return
        }

        let building = map.backgroundElement(atX: point.x, y: point.y)
        if building.isBuilding {
            guard building.army == activeArmy else {
                clearSelection()
                statusMessage = (isFogOfWarActive || submergedUnits.contains(point)) && !isVisible(point)
                    ? "That property is outside friendly vision."
                    : "That property belongs to \(armyName(building.army))."
                return
            }
            selectBuilding(at: point)
            return
        }

        clearSelection()
        statusMessage = "Select one of your units or properties."
    }

    /// Secondary-clicking a unit previews the targets that unit could attack
    /// without changing the player's current selection or action state.
    func handleSecondaryTap(_ point: GridPoint) {
        guard isValid(point), !isGameOver, !isCPUArmy(activeArmy) else { return }

        let unit = map.foregroundElement(atX: point.x, y: point.y)
        guard unit.isUnitNonEmpty,
              PlaytestRulebook.stats(for: unit, ruleset: ruleset) != nil,
              (!isFogOfWarActive || unit.army == activeArmy || isVisible(point)) else {
            clearAttackPreview()
            return
        }

        attackPreviewOrigin = point
        attackPreviewCells = attackRangeCells(from: point, unit: unit)
    }

    func endTurn() {
        guard !isGameOver else { return }
        guard !armies.isEmpty else {
            statusMessage = "No playable armies are placed on this map yet."
            return
        }

        let endingArmy = activeArmy
        let routedArmies = resolveRouting()
        guard winnerArmy == nil else { return }
        guard let nextArmy = nextSurvivingArmy(after: endingArmy) else {
            statusMessage = "No playable armies remain."
            return
        }
        let currentIndex = armies.firstIndex(of: endingArmy) ?? 0
        let nextIndex = armies.firstIndex(of: nextArmy) ?? currentIndex
        let dayAdvanced = nextIndex <= currentIndex
        if dayAdvanced {
            turn += 1
            advanceRandomWeatherIfNeeded()
        }
        activeArmy = nextArmy
        movedCells.removeAll()
        clearSelection()
        let fuelLossCount = processTurnStart(for: activeArmy)
        let startRoutedArmies = resolveRouting()
        guard winnerArmy == nil else { return }
        let routedDuringTransition = Array(Set(routedArmies + startRoutedArmies)).sorted()
        let weatherMessage = weatherMode == .random
            ? " Weather: \(weather.displayName)."
            : ""
        let startMessage = "\(armyName(activeArmy))'s turn. Select a unit or property to begin." + weatherMessage
        let supplyMessage = fuelLossCount > 0
            ? " \(fuelLossCount) air/naval unit(s) were lost to fuel exhaustion."
            : ""
        if routedDuringTransition.isEmpty {
            statusMessage = startMessage + supplyMessage
        } else {
            statusMessage = startMessage + supplyMessage + " " + routedDuringTransition.map { armyName($0) }.joined(separator: ", ") + " was routed and its properties became neutral."
        }
        runCPUIfNeeded()
    }

    func capture() {
        guard let point = selectedPoint,
              let unit = unit(at: point),
              let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset) else {
            statusMessage = "Only Infantry and Mech units can capture properties."
            return
        }
        guard stats.canCapture else {
            statusMessage = "Only Infantry and Mech units can capture properties."
            return
        }

        let building = map.backgroundElement(atX: point.x, y: point.y)
        guard PlaytestRulebook.isCapturableBuilding(building, ruleset: ruleset), building.army != activeArmy else {
            statusMessage = "There is no enemy or neutral property to capture here."
            return
        }

        let progress = captureProgress[point, default: 0] + max(1, unitHealth[point, default: 100] / 10)
        // Capturing is a legal follow-up after movement. Keep the unit marked
        // as acted so it cannot move or capture again this turn.
        movedCells.insert(point)
        if progress < 20 {
            captureProgress[point] = progress
            clearSelection()
            statusMessage = "Capturing \(PaletteCatalog.label(for: building, tileset: map.tileset)): \(progress)/20. Continue next turn."
            return
        }

        let wasHQ = building.simplified == .buildingHQ
        if wasHQ {
            // HQ capture is an immediate defeat, but it still applies the
            // same surrender cleanup as routing. The captured HQ becomes a
            // neutral city and every other property owned by the defeated
            // army is released as well.
            let defeatedArmy = building.army
            neutralizeProperties(of: defeatedArmy)
            defeatedArmies.insert(defeatedArmy)
            captureProgress.removeValue(forKey: point)
            clearSelection()
            if survivingArmies.count == 1 {
                winnerArmy = activeArmy
                statusMessage = "\(activeArmyName) captured the HQ and wins the playtest."
            } else {
                statusMessage = "\(armyName(defeatedArmy))'s HQ was captured; its properties became neutral."
                _ = resolveRouting()
            }
            return
        }

        var candidate = map
        let captured = building.changedArmy(activeArmy)
        guard candidate.setBackground(captured, atX: point.x, y: point.y, check: false) else {
            statusMessage = "That property could not be captured."
            return
        }
        map = candidate
        captureProgress.removeValue(forKey: point)
        clearSelection()
        statusMessage = "\(activeArmyName) captured \(PaletteCatalog.label(for: captured, tileset: map.tileset))."
        _ = resolveRouting()
    }

    func wait() {
        guard let point = selectedPoint, unit(at: point) != nil else {
            statusMessage = "Select a unit before ending its action."
            return
        }
        movedCells.insert(point)
        clearSelection()
        statusMessage = "Unit action ended."
    }

    fileprivate func toggleSubmerge() {
        guard let point = selectedPoint,
              let unit = unit(at: point),
              unit.simplified == .unitSub,
              !movedCells.contains(point) else {
            statusMessage = "Select an unused Submarine before changing its depth."
            return
        }

        if submergedUnits.contains(point) {
            submergedUnits.remove(point)
            statusMessage = "Submarine surfaced."
        } else {
            submergedUnits.insert(point)
            statusMessage = "Submarine submerged."
        }
        movedCells.insert(point)
        clearSelection()
    }

    fileprivate func beginSiloLaunch() {
        guard selectedUnitCanLaunchSilo, selectedPoint != nil else {
            statusMessage = "An unused Missile Silo must have an Infantry or Mech standing on it."
            return
        }
        isSelectingSiloTarget = true
        siloTargetCells = Set((0..<map.width).flatMap { x in
            (0..<map.height).map { y in GridPoint(x: x, y: y) }
        })
        statusMessage = "Select any map space for the Missile Silo target."
    }

    private func launchSilo(at target: GridPoint) {
        guard selectedUnitCanLaunchSilo, let source = selectedPoint else {
            isSelectingSiloTarget = false
            siloTargetCells.removeAll()
            return
        }

        for x in 0..<map.width {
            for y in 0..<map.height {
                let point = GridPoint(x: x, y: y)
                guard abs(point.x - target.x) + abs(point.y - target.y) <= 2 else { continue }
                let unit = map.foregroundElement(atX: x, y: y)
                guard unit.isUnitNonEmpty else { continue }
                unitHealth[point] = max(10, unitHealth[point, default: 100] - 30)
            }
        }
        usedMissileSilos.insert(source)
        movedCells.insert(source)
        isSelectingSiloTarget = false
        siloTargetCells.removeAll()
        clearSelection()
        statusMessage = "Missile Silo launched. Every unit in the blast took 3 HP."
    }

    fileprivate func canBuild(_ option: PlaytestProductionOption) -> Bool {
        guard let point = selectedPoint,
              selectedBuildingName != nil,
              let building = Optional(map.backgroundElement(atX: point.x, y: point.y)),
              building.army == activeArmy,
              map.foregroundElement(atX: point.x, y: point.y) == .unitEmpty,
              !movedCells.contains(point),
              activeFunds >= option.cost,
              (ruleset != .advanceWars || unitCount(for: activeArmy) < 50),
              PlaytestRulebook.productionOptions(for: building, ruleset: ruleset, tileset: map.tileset).contains(where: { $0.id == option.id }) else { return false }
        return map.allowPlacement(option.element.changedArmy(activeArmy), atX: point.x, y: point.y)
    }

    fileprivate func buildUnit(_ option: PlaytestProductionOption) {
        guard canBuild(option), let point = selectedPoint else {
            statusMessage = "That unit cannot be built here right now."
            return
        }

        var candidate = map
        let unit = option.element.changedArmy(activeArmy)
        guard candidate.setForeground(unit, atX: point.x, y: point.y) else {
            statusMessage = "That unit cannot be built on this property."
            return
        }
        map = candidate
        funds[activeArmy, default: 0] -= option.cost
        unitHealth[point] = 100
        unitFuel[point] = PlaytestRulebook.maxFuel(for: unit, ruleset: ruleset)
        if let ammo = PlaytestRulebook.primaryAmmo(for: unit, ruleset: ruleset) {
            unitAmmo[point] = ammo
        }
        movedCells.insert(point)
        clearSelection()
        statusMessage = "Built \(option.label) for \(PlaytestRulebook.formatFunds(option.cost)). It cannot move this turn."
    }

    private func selectUnit(at point: GridPoint) {
        guard let unit = unit(at: point), let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset) else { return }
        clearPlayerMovementPreview()
        selectedPoint = point
        productionOptions.removeAll()
        let hasMoved = movedCells.contains(point)
        captureableCells = canCapture(unit: unit, stats: stats, at: point) ? [point] : []
        reachableCells = hasMoved || activeArmyIsCPU || isAnimatingCPUMovement
            ? []
            : movementCells(from: point, unit: unit, stats: stats)
        attackableCells = hasMoved && !stats.canMoveAndFire ? [] : attackableCells(from: point, unit: unit)
        updateTransportActions(for: unit, at: point)
        if hasMoved {
            if !attackableCells.isEmpty && !captureableCells.isEmpty {
                statusMessage = "Choose an enemy in red, capture the highlighted property, or end the action."
            } else if !captureableCells.isEmpty {
                statusMessage = "Capture the highlighted property or end the action."
            } else if stats.canMoveAndFire {
                statusMessage = "Choose an enemy in red, or end the action."
            } else {
                statusMessage = "\(PaletteCatalog.label(for: unit, tileset: map.tileset)) moved and is spent."
            }
        } else if activeArmyIsCPU {
            statusMessage = "\(PaletteCatalog.label(for: unit, tileset: map.tileset)) is moving."
        } else {
            statusMessage = "Move to a blue tile, attack a red target, load or unload cargo, or capture the highlighted property."
        }
    }

    func refreshSelection() {
        guard let selectedPoint,
              let unit = unit(at: selectedPoint) else { return }
        selectUnit(at: selectedPoint)
        if unit.simplified == .unitAPC || unit.simplified == .unitBlackBoat {
            updateTransportActions(for: unit, at: selectedPoint)
        }
    }

    private func effectiveVision(for observer: Element, at point: GridPoint) -> Int? {
        guard let observerStats = PlaytestRulebook.stats(for: observer, ruleset: ruleset) else { return nil }
        var vision = observerStats.vision
        let observerTerrain = map.backgroundElement(atX: point.x, y: point.y)
        if (observer.simplified == .unitInfantry || observer.simplified == .unitMech),
           observerTerrain.simplified == .terrainMountain {
            vision += 3
        }
        // Rain reduces vision in every ruleset where Fog of War is active.
        // Dual Strike also forces Fog of War on while it is raining.
        if isFogOfWarActive, weather == .rain {
            vision = max(1, vision - 1)
        }
        return vision
    }

    func isVisible(_ point: GridPoint) -> Bool {
        guard isValid(point) else { return false }
        return visibleCells().contains(point)
    }

    /// Computes Fog-of-War visibility once per board/turn state. The old
    /// implementation scanned every observer for every queried tile, which
    /// made a full-map render quadratic and repeated that work for each CPU
    /// action. Marking the observer radii directly keeps the same rules while
    /// making both rendering and attack generation proportional to vision.
    private func visibleCells() -> Set<GridPoint> {
        if cachedVisibilityRevision == visibilityRevision {
            return cachedVisibleCells
        }

        let allPoints = allMapPoints()
        let fogActive = isFogOfWarActive
        var visible = fogActive ? Set<GridPoint>() : Set(allPoints)
        if !fogActive {
            for point in allPoints {
                let unit = map.foregroundElement(atX: point.x, y: point.y)
                if unit.isUnitNonEmpty,
                   unit.army != activeArmy,
                   unit.simplified == .unitSub,
                   submergedUnits.contains(point) {
                    visible.remove(point)
                }
            }
        }

        for observerX in 0..<map.width {
            for observerY in 0..<map.height {
                let observerPoint = GridPoint(x: observerX, y: observerY)
                let observer = map.foregroundElement(atX: observerX, y: observerY)
                guard observer.isUnitNonEmpty, observer.army == activeArmy,
                      let observerStats = PlaytestRulebook.stats(for: observer, ruleset: ruleset),
                      let vision = effectiveVision(for: observer, at: observerPoint) else { continue }

                let minX = max(0, observerX - vision)
                let maxX = min(map.width - 1, observerX + vision)
                let minY = max(0, observerY - vision)
                let maxY = min(map.height - 1, observerY + vision)
                for targetX in minX...maxX {
                    for targetY in minY...maxY {
                        let targetPoint = GridPoint(x: targetX, y: targetY)
                        let tileDistance = distance(from: observerPoint, to: targetPoint)
                        guard tileDistance <= vision else { continue }

                        let targetUnit = map.foregroundElement(atX: targetX, y: targetY)
                        let targetTerrain = map.backgroundElement(atX: targetX, y: targetY)
                        let concealedSubmarine = targetUnit.isUnitNonEmpty &&
                            targetUnit.simplified == .unitSub &&
                            submergedUnits.contains(targetPoint)

                        if concealedSubmarine,
                           observer.simplified != .unitCruiser,
                           observer.simplified != .unitSub,
                           tileDistance > 1 {
                            continue
                        }
                        if targetTerrain.simplified == .terrainWood,
                           let targetStats = PlaytestRulebook.stats(for: targetUnit, ruleset: ruleset),
                           targetStats.domain == .land,
                           observerStats.domain != .air,
                           tileDistance > 1 {
                            continue
                        }
                        if targetTerrain.simplified == .terrainReef,
                           let targetStats = PlaytestRulebook.stats(for: targetUnit, ruleset: ruleset),
                           targetStats.domain == .sea,
                           observerStats.domain != .air,
                           tileDistance > 1 {
                            continue
                        }
                        visible.insert(targetPoint)
                    }
                }
            }
        }

        // Owned units and properties remain visible even when they do not
        // provide vision themselves. This also preserves the old behavior for
        // an army with no active observers.
        for point in allPoints {
            let unit = map.foregroundElement(atX: point.x, y: point.y)
            let building = map.backgroundElement(atX: point.x, y: point.y)
            if (unit.isUnitNonEmpty && unit.army == activeArmy) ||
                (building.isBuilding && building.army == activeArmy) {
                visible.insert(point)
            }
        }

        cachedVisibleCells = visible
        cachedVisibilityRevision = visibilityRevision
        return visible
    }

    private func invalidateVisibilityCache() {
        visibilityRevision &+= 1
        cachedVisibilityRevision = -1
        cachedVisibleCells.removeAll(keepingCapacity: true)
    }

    /// Map dimensions are stable while units move. Reuse the coordinate list
    /// needed by visibility calculations instead of allocating a new nested
    /// array every time the render-only map snapshot is requested.
    private func allMapPoints() -> [GridPoint] {
        guard cachedMapPointWidth == map.width,
              cachedMapPointHeight == map.height else {
            cachedMapPoints = (0..<map.width).flatMap { x in
                (0..<map.height).map { y in GridPoint(x: x, y: y) }
            }
            cachedMapPointWidth = map.width
            cachedMapPointHeight = map.height
            return cachedMapPoints
        }
        return cachedMapPoints
    }

    private func isHiddenEnemy(_ occupant: Element, at point: GridPoint, relativeTo unit: Element) -> Bool {
        guard occupant.isUnitNonEmpty, occupant.army != unit.army else { return false }
        guard isFogOfWarActive || submergedUnits.contains(point) else { return false }
        return !isVisible(point)
    }

    private func revealAmbush(
        from origin: GridPoint,
        destination: GridPoint,
        path: MovementPath,
        paths: [GridPoint: MovementPath],
        unit: Element,
        stats: PlaytestUnitStats
    ) {
        var stop = path.previous ?? origin
        while stop != origin,
              map.foregroundElement(atX: stop.x, y: stop.y).isUnitNonEmpty,
              let previous = paths[stop]?.previous {
            stop = previous
        }

        if stop != origin {
            var candidate = map
            guard candidate.setForeground(.unitEmpty, atX: origin.x, y: origin.y),
                  candidate.setForeground(unit, atX: stop.x, y: stop.y) else {
                statusMessage = "The hidden enemy blocked the move."
                return
            }
            map = candidate
            captureProgress.removeValue(forKey: origin)
            unitHealth[stop] = unitHealth.removeValue(forKey: origin) ?? 100
            let fuel = unitFuel.removeValue(forKey: origin) ?? stats.maxFuel
            let movement = paths[stop]?.movement ?? 0
            let fuelCost = PlaytestRulebook.movementFuelCost(
                for: unit,
                movement: movement,
                ruleset: ruleset,
                weather: weather
            )
            unitFuel[stop] = max(0, fuel - fuelCost)
            unitAmmo[stop] = unitAmmo.removeValue(forKey: origin)
            cargo[stop] = cargo.removeValue(forKey: origin)
            if submergedUnits.remove(origin) != nil {
                submergedUnits.insert(stop)
            }
            movedCells.remove(origin)
            movedCells.insert(stop)
        } else {
            movedCells.insert(origin)
        }

        clearSelection()
        let enemy = map.foregroundElement(atX: destination.x, y: destination.y)
        statusMessage = "Ambush! \(PaletteCatalog.label(for: enemy, tileset: map.tileset)) was revealed. The move ends here."
    }

    private func selectBuilding(at point: GridPoint) {
        let building = map.backgroundElement(atX: point.x, y: point.y)
        selectedPoint = point
        reachableCells.removeAll()
        attackableCells.removeAll()
        captureableCells.removeAll()
        loadableCells.removeAll()
        joinableCells.removeAll()
        unloadableCells.removeAll()
        refuelableCells.removeAll()
        productionOptions = PlaytestRulebook.productionOptions(for: building, ruleset: ruleset, tileset: map.tileset)
        if productionOptions.isEmpty {
            statusMessage = "This property cannot produce units in \(ruleset.displayName)."
        } else if map.foregroundElement(atX: point.x, y: point.y) != .unitEmpty {
            statusMessage = "Clear the property before building a unit."
        } else {
            statusMessage = "Choose a unit to build. New units wait until next turn."
        }
    }

    private func moveSelectedUnit(to destination: GridPoint) {
        guard let origin = selectedPoint,
              let unit = unit(at: origin),
              let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset) else {
            clearSelection()
            return
        }

        let paths = movementPaths(from: origin, unit: unit, stats: stats)
        guard let path = paths[destination] else {
            statusMessage = "That unit cannot move there."
            return
        }

        let destinationUnit = map.foregroundElement(atX: destination.x, y: destination.y)
        if isHiddenEnemy(destinationUnit, at: destination, relativeTo: unit) {
            revealAmbush(
                from: origin,
                destination: destination,
                path: path,
                paths: paths,
                unit: unit,
                stats: stats
            )
            return
        }
        if destinationUnit.isUnitNonEmpty, canJoin(unit, with: destinationUnit, at: destination) {
            joinUnit(to: destination)
            return
        }
        if destinationUnit.isUnitNonEmpty {
            guard canLoad(unit, into: destinationUnit, at: destination) else {
                statusMessage = "That unit cannot load into the selected transport."
                return
            }

            var candidate = map
            guard candidate.setForeground(.unitEmpty, atX: origin.x, y: origin.y) else {
                statusMessage = "That unit cannot load here."
                return
            }
            map = candidate
            captureProgress.removeValue(forKey: origin)
            let payload = PlaytestCargo(
                unit: unit,
                health: unitHealth.removeValue(forKey: origin) ?? 100,
                fuel: max(
                    0,
                    (unitFuel.removeValue(forKey: origin) ?? maxFuel(for: origin)) -
                        PlaytestRulebook.movementFuelCost(
                            for: unit,
                            movement: path.movement,
                            ruleset: ruleset,
                            weather: weather
                        )
                ),
                ammo: unitAmmo.removeValue(forKey: origin)
            )
            cargo[destination, default: []].append(payload)
            movedCells.remove(origin)
            selectedPoint = destination
            productionOptions.removeAll()

            if let transportStats = PlaytestRulebook.stats(for: destinationUnit, ruleset: ruleset) {
                reachableCells = movedCells.contains(destination)
                    ? []
                    : movementCells(from: destination, unit: destinationUnit, stats: transportStats)
                captureableCells.removeAll()
                attackableCells = attackableCells(from: destination, unit: destinationUnit)
                updateTransportActions(for: destinationUnit, at: destination)
            } else {
                clearSelection()
            }
            statusMessage = "Loaded \(PaletteCatalog.label(for: unit, tileset: map.tileset)) into \(PaletteCatalog.label(for: destinationUnit, tileset: map.tileset))."
            return
        }

        var candidate = map
        guard candidate.setForeground(.unitEmpty, atX: origin.x, y: origin.y),
              candidate.setForeground(unit, atX: destination.x, y: destination.y) else {
            statusMessage = "That unit cannot move there."
            return
        }

        map = candidate
        captureProgress.removeValue(forKey: origin)
        unitHealth[destination] = unitHealth.removeValue(forKey: origin) ?? 100
        let fuel = unitFuel.removeValue(forKey: origin) ?? stats.maxFuel
        let fuelCost = PlaytestRulebook.movementFuelCost(
            for: unit,
            movement: path.movement,
            ruleset: ruleset,
            weather: weather
        )
        unitFuel[destination] = max(0, fuel - fuelCost)
        unitAmmo[destination] = unitAmmo.removeValue(forKey: origin)
        cargo[destination] = cargo.removeValue(forKey: origin)
        if submergedUnits.remove(origin) != nil {
            submergedUnits.insert(destination)
        }
        movedCells.remove(origin)
        movedCells.insert(destination)
        if isAnimatingCPUMovement {
            // Keep the unit selected while the CPU walks it through the
            // route. Post-move actions are resolved only after the final
            // tile, so the intermediate sprite updates remain visible.
            selectedPoint = destination
            reachableCells.removeAll()
            attackableCells.removeAll()
            captureableCells.removeAll()
            loadableCells.removeAll()
            joinableCells.removeAll()
            unloadableCells.removeAll()
            refuelableCells.removeAll()
            productionOptions.removeAll()
            return
        }
        configurePostMoveActions(for: unit, stats: stats, at: destination)
    }

    /// Movement consumes the unit's movement, but Infantry and Mech units may
    /// still capture a property they moved onto. Units that can move and fire
    /// also retain their legal attack targets as a follow-up action.
    private func configurePostMoveActions(for unit: Element, stats: PlaytestUnitStats, at destination: GridPoint) {
        selectedPoint = destination
        reachableCells.removeAll()
        captureableCells = canCapture(unit: unit, stats: stats, at: destination) ? [destination] : []
        loadableCells.removeAll()
        joinableCells.removeAll()
        unloadableCells.removeAll()
        refuelableCells.removeAll()
        productionOptions.removeAll()
        attackableCells = stats.canMoveAndFire ? attackableCells(from: destination, unit: unit) : []

        guard !attackableCells.isEmpty || !captureableCells.isEmpty else {
            clearSelection()
            statusMessage = "\(PaletteCatalog.label(for: unit, tileset: map.tileset)) moved and is spent."
            return
        }

        if !attackableCells.isEmpty && !captureableCells.isEmpty {
            statusMessage = "Choose an enemy in red, capture the highlighted property, or end the action."
        } else if !captureableCells.isEmpty {
            statusMessage = "Capture the highlighted property or end the action."
        } else {
            statusMessage = "Choose an enemy in red, or end the action."
        }
    }

    private func attack(to destination: GridPoint) {
        guard let origin = selectedPoint,
              let attacker = unit(at: origin),
              let attackerStats = PlaytestRulebook.stats(for: attacker, ruleset: ruleset) else {
            statusMessage = "That target cannot be attacked by this unit."
            return
        }

        // Pipe seams are terrain objectives, not units. They share the same
        // attack range/action rules as unit combat but do not counterattack.
        if unit(at: destination) == nil, isPipeSeam(at: destination) {
            guard canAttackPipeSeam(from: origin, to: destination, attacker: attacker) else {
                statusMessage = "That target cannot be attacked by this unit."
                return
            }
            attackPipeSeam(from: origin, to: destination, attacker: attacker)
            return
        }

        guard let defender = unit(at: destination),
              let defenderStats = PlaytestRulebook.stats(for: defender, ruleset: ruleset),
              (!movedCells.contains(origin) || attackerStats.canMoveAndFire),
              (!submergedUnits.contains(destination) || attacker.simplified == .unitCruiser || attacker.simplified == .unitSub),
              PlaytestRulebook.canAttack(attacker, defender, ruleset: ruleset, primaryAmmo: unitAmmo[origin]),
              let damage = PlaytestRulebook.damage(
                attacker: attacker,
                defender: defender,
                ruleset: ruleset,
                attackerHealth: unitHealth[origin, default: 100],
                defenderHealth: unitHealth[destination, default: 100],
                terrain: map.backgroundElement(atX: destination.x, y: destination.y),
                primaryAmmo: unitAmmo[origin]
              ) else {
            statusMessage = "That target cannot be attacked by this unit."
            return
        }

        let attackerUsedPrimary = PlaytestRulebook.usesPrimaryWeapon(
            attacker,
            defender,
            ruleset: ruleset,
            primaryAmmo: unitAmmo[origin]
        )
        if attackerUsedPrimary, let currentAmmo = unitAmmo[origin] {
            unitAmmo[origin] = max(0, currentAmmo - 1)
        }

        let defenderHealth = unitHealth[destination, default: 100]
        var candidate = map
        var defenderDestroyed = false
        let remainingDefenderHealth = defenderHealth - damage
        if remainingDefenderHealth <= 0 {
            _ = candidate.setForeground(.unitEmpty, atX: destination.x, y: destination.y)
            unitHealth.removeValue(forKey: destination)
            unitFuel.removeValue(forKey: destination)
            unitAmmo.removeValue(forKey: destination)
            cargo.removeValue(forKey: destination)
            submergedUnits.remove(destination)
            captureProgress.removeValue(forKey: destination)
            defenderDestroyed = true
        } else {
            unitHealth[destination] = remainingDefenderHealth
        }

        var counterattackText = ""
        var attackerDestroyed = false
        if !defenderDestroyed,
           defenderStats.canCounterattack,
           (!submergedUnits.contains(origin) || defender.simplified == .unitCruiser || defender.simplified == .unitSub),
           let counterDamage = PlaytestRulebook.damage(
                attacker: defender,
                defender: attacker,
                ruleset: ruleset,
                attackerHealth: unitHealth[destination, default: 100],
                defenderHealth: unitHealth[origin, default: 100],
                terrain: map.backgroundElement(atX: origin.x, y: origin.y),
                primaryAmmo: unitAmmo[destination]
           ),
           isWithinRange(from: destination, to: origin, stats: defenderStats) {
            let defenderUsedPrimary = PlaytestRulebook.usesPrimaryWeapon(
                defender,
                attacker,
                ruleset: ruleset,
                primaryAmmo: unitAmmo[destination]
            )
            if defenderUsedPrimary, let currentAmmo = unitAmmo[destination] {
                unitAmmo[destination] = max(0, currentAmmo - 1)
            }
            let remainingAttackerHealth = unitHealth[origin, default: 100] - counterDamage
            if remainingAttackerHealth <= 0 {
                _ = candidate.setForeground(.unitEmpty, atX: origin.x, y: origin.y)
                unitHealth.removeValue(forKey: origin)
                unitFuel.removeValue(forKey: origin)
                unitAmmo.removeValue(forKey: origin)
                cargo.removeValue(forKey: origin)
                submergedUnits.remove(origin)
                captureProgress.removeValue(forKey: origin)
                attackerDestroyed = true
                counterattackText = " The defender destroyed the attacker in the counterattack."
            } else {
                unitHealth[origin] = remainingAttackerHealth
                counterattackText = " Counterattack dealt \(counterDamage) damage."
            }
        }

        map = candidate
        if !attackerDestroyed { movedCells.insert(origin) }
        clearSelection()
        statusMessage = "\(PaletteCatalog.label(for: attacker, tileset: map.tileset)) dealt \(damage) damage to \(PaletteCatalog.label(for: defender, tileset: map.tileset))." + counterattackText
        _ = resolveRouting()
    }

    private func attackPipeSeam(from origin: GridPoint, to destination: GridPoint, attacker: Element) {
        guard let damage = pipeSeamDamage(from: origin, to: destination, attacker: attacker) else {
            statusMessage = "That target cannot be attacked by this unit."
            return
        }

        let attackerUsedPrimary = PlaytestRulebook.usesPrimaryWeapon(
            attacker,
            Element.unitInfantry,
            ruleset: ruleset,
            primaryAmmo: unitAmmo[origin]
        )
        if attackerUsedPrimary, let currentAmmo = unitAmmo[origin] {
            unitAmmo[origin] = max(0, currentAmmo - 1)
        }

        let currentHealth = pipeSeamHealth[destination, default: Self.pipeSeamStartingHealth]
        let remainingHealth = currentHealth - damage
        movedCells.insert(origin)

        if remainingHealth <= 0 {
            var candidate = map
            guard candidate.setBackground(.terrainPlain, atX: destination.x, y: destination.y, check: false) else {
                statusMessage = "That pipe seam could not be destroyed."
                return
            }
            map = candidate
            pipeSeamHealth.removeValue(forKey: destination)
            clearSelection()
            statusMessage = "\(PaletteCatalog.label(for: attacker, tileset: map.tileset)) destroyed the pipe seam."
        } else {
            pipeSeamHealth[destination] = remainingHealth
            clearSelection()
            statusMessage = "\(PaletteCatalog.label(for: attacker, tileset: map.tileset)) damaged the pipe seam (\(remainingHealth) HP remaining)."
        }
        _ = resolveRouting()
    }

    private func movementCells(from origin: GridPoint, unit: Element, stats: PlaytestUnitStats) -> Set<GridPoint> {
        let paths = movementPaths(from: origin, unit: unit, stats: stats)
        return Set(paths.compactMap { point, _ in
            let occupant = map.foregroundElement(atX: point.x, y: point.y)
            return occupant == .unitEmpty || canLoad(unit, into: occupant, at: point) ||
                canJoin(unit, with: occupant, at: point, firstPoint: origin) ||
                isHiddenEnemy(occupant, at: point, relativeTo: unit) ? point : nil
        })
    }

    private func movementRoute(
        from origin: GridPoint,
        to destination: GridPoint,
        paths: [GridPoint: MovementPath]
    ) -> [GridPoint]? {
        guard paths[destination] != nil else { return nil }

        var route: [GridPoint] = []
        var current = destination
        while current != origin {
            route.append(current)
            guard let previous = paths[current]?.previous else { return nil }
            current = previous
        }
        route.append(origin)
        return Array(route.reversed())
    }

    private func movementPaths(from origin: GridPoint, unit: Element, stats: PlaytestUnitStats) -> [GridPoint: MovementPath] {
        let fuel = unitFuel[origin, default: stats.maxFuel]
        var paths: [GridPoint: MovementPath] = [origin: MovementPath(movement: 0, steps: 0, previous: nil)]
        var frontier: [GridPoint] = [origin]
        var index = 0

        while index < frontier.count {
            let current = frontier[index]
            index += 1
            guard let currentPath = paths[current] else { continue }

            for next in neighbors(of: current) {
                let occupant = map.foregroundElement(atX: next.x, y: next.y)
                let terrain = map.backgroundElement(atX: next.x, y: next.y)
                let isLoadDestination = canLoad(unit, into: occupant, at: next)
                let isJoinDestination = canJoin(unit, with: occupant, at: next, firstPoint: origin)
                let canPassThrough = occupant == .unitEmpty || (occupant.isUnitNonEmpty && occupant.army == unit.army)
                let isAmbushDestination = isHiddenEnemy(occupant, at: next, relativeTo: unit)
                let canStandOnTile = map.allowPlacement(unit, atX: next.x, y: next.y)
                let isRiver = terrain.simplified == .terrainRiver
                let cost = PlaytestRulebook.movementCost(for: unit, stats: stats, terrain: terrain, ruleset: ruleset, weather: weather)
                guard isValid(next),
                      (canPassThrough || isAmbushDestination),
                      (!isRiver || stats.domain == .air || PlaytestRulebook.canCrossRiver(unit)),
                      (isLoadDestination || isJoinDestination || canStandOnTile ||
                       (occupant.isUnitNonEmpty && occupant.army == unit.army) || isAmbushDestination),
                      let cost else { continue }

                let nextPath = MovementPath(
                    movement: currentPath.movement + cost,
                    steps: currentPath.steps + 1,
                    previous: current
                )
                let fuelCost = PlaytestRulebook.movementFuelCost(
                    for: unit,
                    movement: nextPath.movement,
                    ruleset: ruleset,
                    weather: weather
                )
                guard nextPath.movement <= stats.move, fuelCost <= fuel else { continue }
                if let existing = paths[next],
                   existing.movement < nextPath.movement ||
                    (existing.movement == nextPath.movement && existing.steps <= nextPath.steps) {
                    continue
                }
                paths[next] = nextPath
                // A hidden enemy is an ambush endpoint, not a square the
                // mover may pass through.
                if !isAmbushDestination {
                    frontier.append(next)
                }
            }
        }

        paths.removeValue(forKey: origin)
        return paths
    }

    private func canLoad(_ cargoUnit: Element, into transport: Element, at point: GridPoint) -> Bool {
        guard transport.isUnitNonEmpty,
              transport.army == cargoUnit.army,
              !movedCells.contains(point),
              PlaytestRulebook.canTransport(transport, cargo: cargoUnit, ruleset: ruleset),
              cargo[point, default: []].count < PlaytestRulebook.transportCapacity(for: transport) else { return false }
        return true
    }

    private func canJoin(_ first: Element, with second: Element, at point: GridPoint, firstPoint: GridPoint? = nil) -> Bool {
        guard isValid(point),
              second.isUnitNonEmpty,
              first.army == second.army,
              first.simplified == second.simplified,
              PlaytestRulebook.stats(for: first, ruleset: ruleset) != nil else { return false }
        let firstHealth = firstPoint.map { unitHealth[$0, default: 100] }
            ?? selectedPoint.map { unitHealth[$0, default: 100] }
            ?? 100
        let secondHealth = unitHealth[point, default: 100]
        return firstHealth < 100 || secondHealth < 100
    }

    private func updateTransportActions(for transport: Element, at point: GridPoint) {
        loadableCells.removeAll()
        joinableCells.removeAll()
        unloadableCells.removeAll()
        refuelableCells.removeAll()

        guard !movedCells.contains(point) else { return }

        let capacity = PlaytestRulebook.transportCapacity(for: transport)
        if capacity > 0, capacity > cargo[point, default: []].count {
            for neighbor in neighbors(of: point) {
                guard isValid(neighbor),
                      let candidate = self.unit(at: neighbor),
                      candidate.army == transport.army,
                      PlaytestRulebook.canTransport(transport, cargo: candidate, ruleset: ruleset) else { continue }
                loadableCells.insert(neighbor)
            }
        } else if capacity == 0 {
            for neighbor in neighbors(of: point) {
                guard isValid(neighbor),
                      let potentialTransport = self.unit(at: neighbor),
                      canLoad(transport, into: potentialTransport, at: neighbor) else { continue }
                loadableCells.insert(neighbor)
            }
        }

        if capacity == 0 {
            for neighbor in neighbors(of: point) {
                guard isValid(neighbor),
                      let candidate = self.unit(at: neighbor),
                      canJoin(transport, with: candidate, at: neighbor) else { continue }
                joinableCells.insert(neighbor)
            }
        }

        if let loaded = cargo[point]?.first {
            for neighbor in neighbors(of: point) where isValid(neighbor) {
                guard canUnload(loaded.unit, from: transport, at: neighbor) else { continue }
                unloadableCells.insert(neighbor)
            }
        }

        if transport.simplified == .unitAPC || transport.simplified == .unitBlackBoat {
            for neighbor in resupplyNeighbors(of: point, transport: transport) {
                guard isValid(neighbor),
                      let adjacent = self.unit(at: neighbor),
                      adjacent.army == transport.army else { continue }
                let needsHealth = transport.simplified == .unitBlackBoat &&
                    unitHealth[neighbor, default: 100] < 100
                let needsFuel = unitFuel[neighbor, default: maxFuel(for: neighbor)] < maxFuel(for: neighbor)
                let needsAmmo = PlaytestRulebook.primaryAmmo(for: adjacent, ruleset: ruleset).map { unitAmmo[neighbor, default: $0] < $0 } ?? false
                guard needsHealth || needsFuel || needsAmmo else { continue }
                refuelableCells.insert(neighbor)
            }
        }
    }

    private func canUnload(_ cargoUnit: Element, from transport: Element, at destination: GridPoint) -> Bool {
        guard isValid(destination),
              map.foregroundElement(atX: destination.x, y: destination.y) == .unitEmpty,
              map.allowPlacement(cargoUnit, atX: destination.x, y: destination.y) else { return false }

        let terrain = map.backgroundElement(atX: destination.x, y: destination.y)
        guard terrain.simplified != .terrainBlank else { return false }
        switch transport.simplified {
        case .unitLander:
            return terrain.simplified == .terrainShoal ||
                terrain.simplified == .buildingPort
        case .unitBlackBoat:
            return (cargoUnit.simplified == .unitInfantry || cargoUnit.simplified == .unitMech) &&
                (terrain.simplified == .terrainShoal || terrain.simplified == .buildingPort)
        case .unitTCopter:
            // Bridges are represented as sea edges in Element so their sprite
            // can join rivers, but they are land crossings for unloading.
            let isBridge = terrain.simplified == .terrainBridgeH || terrain.simplified == .terrainBridgeV
            return terrain.simplified != .terrainBlank && (terrain.isLand || isBridge)
        case .unitAPC:
            return true
        case .unitCruiser:
            return (cargoUnit.simplified == .unitBCopter || cargoUnit.simplified == .unitTCopter)
                && terrain.simplified != .terrainPipe
                && terrain.simplified != .terrainSeam
        case .unitCarrier:
            return PlaytestRulebook.stats(for: cargoUnit, ruleset: ruleset)?.domain == .air
        default:
            return false
        }
    }

    private func loadUnit(from source: GridPoint) {
        guard let transportPoint = selectedPoint,
              let transport = unit(at: transportPoint),
              let loadedUnit = unit(at: source),
              !movedCells.contains(transportPoint),
              loadableCells.contains(source),
              PlaytestRulebook.stats(for: loadedUnit, ruleset: ruleset) != nil else {
            statusMessage = "That unit cannot be loaded here."
            return
        }

        var candidate = map
        guard candidate.setForeground(.unitEmpty, atX: source.x, y: source.y) else {
            statusMessage = "That unit cannot be loaded here."
            return
        }
        map = candidate
        captureProgress.removeValue(forKey: source)
        let payload = PlaytestCargo(
            unit: loadedUnit,
            health: unitHealth.removeValue(forKey: source) ?? 100,
            fuel: unitFuel.removeValue(forKey: source) ?? PlaytestRulebook.maxFuel(for: loadedUnit, ruleset: ruleset),
            ammo: unitAmmo.removeValue(forKey: source)
        )
        cargo[transportPoint, default: []].append(payload)
        movedCells.remove(source)
        if movedCells.contains(transportPoint) {
            reachableCells.removeAll()
        } else if let transportStats = PlaytestRulebook.stats(for: transport, ruleset: ruleset) {
            reachableCells = movementCells(from: transportPoint, unit: transport, stats: transportStats)
        }
        updateTransportActions(for: transport, at: transportPoint)
        statusMessage = "Loaded \(PaletteCatalog.label(for: loadedUnit, tileset: map.tileset)) into \(PaletteCatalog.label(for: transport, tileset: map.tileset)). The transport may still move."
    }

    private func joinUnit(to destination: GridPoint) {
        guard let origin = selectedPoint,
              let first = unit(at: origin),
              let second = unit(at: destination),
              let firstStats = PlaytestRulebook.stats(for: first, ruleset: ruleset),
              !movedCells.contains(origin),
              canJoin(first, with: second, at: destination),
              let path = movementPaths(from: origin, unit: first, stats: firstStats)[destination] else {
            statusMessage = "Those units cannot join."
            return
        }

        let firstHealth = unitHealth[origin, default: 100]
        let secondHealth = unitHealth[destination, default: 100]
        let combinedHealth = firstHealth + secondHealth
        let excessHP = max(0, combinedHealth - 100) / 10
        if excessHP > 0,
           let stats = PlaytestRulebook.stats(for: first, ruleset: ruleset) {
            funds[activeArmy, default: 0] += excessHP * max(1, stats.cost / 10)
        }

        var candidate = map
        guard candidate.setForeground(.unitEmpty, atX: origin.x, y: origin.y) else {
            statusMessage = "Those units cannot join."
            return
        }
        map = candidate
        unitHealth[destination] = min(100, combinedHealth)
        let maxFuel = PlaytestRulebook.maxFuel(for: second, ruleset: ruleset)
        let fuelCost = PlaytestRulebook.movementFuelCost(
            for: first,
            movement: path.movement,
            ruleset: ruleset,
            weather: weather
        )
        let firstFuelAfterMove = max(0, unitFuel[origin, default: maxFuel] - fuelCost)
        unitFuel[destination] = min(maxFuel, firstFuelAfterMove + unitFuel[destination, default: maxFuel])
        if let ammo = PlaytestRulebook.primaryAmmo(for: second, ruleset: ruleset) {
            unitAmmo[destination] = min(ammo, unitAmmo[origin, default: ammo] + unitAmmo[destination, default: ammo])
        }
        unitHealth.removeValue(forKey: origin)
        unitFuel.removeValue(forKey: origin)
        unitAmmo.removeValue(forKey: origin)
        captureProgress.removeValue(forKey: origin)
        captureProgress.removeValue(forKey: destination)
        submergedUnits.remove(origin)
        movedCells.remove(origin)
        movedCells.insert(destination)
        clearSelection()
        statusMessage = "Joined the two \(PaletteCatalog.label(for: second, tileset: map.tileset)) units."
    }

    private func unloadUnit(to destination: GridPoint) {
        guard let transportPoint = selectedPoint,
              let transport = unit(at: transportPoint),
              var loaded = cargo[transportPoint],
              let payload = loaded.first,
              !movedCells.contains(transportPoint),
              unloadableCells.contains(destination) else {
            statusMessage = "That cargo cannot be unloaded there."
            return
        }

        var candidate = map
        guard candidate.setForeground(payload.unit, atX: destination.x, y: destination.y) else {
            statusMessage = "That cargo cannot be unloaded there."
            return
        }
        map = candidate
        loaded.removeFirst()
        if loaded.isEmpty {
            cargo.removeValue(forKey: transportPoint)
        } else {
            cargo[transportPoint] = loaded
        }
        unitHealth[destination] = payload.health
        unitFuel[destination] = payload.fuel
        if let ammo = payload.ammo {
            unitAmmo[destination] = ammo
        }
        movedCells.insert(transportPoint)
        movedCells.insert(destination)
        reachableCells.removeAll()
        updateTransportActions(for: transport, at: transportPoint)
        statusMessage = "Unloaded \(PaletteCatalog.label(for: payload.unit, tileset: map.tileset)) from \(PaletteCatalog.label(for: transport, tileset: map.tileset))."
    }

    fileprivate func resupplySelectedTransport(target: GridPoint? = nil) {
        guard let point = selectedPoint,
              let transport = unit(at: point),
              transport.simplified == .unitAPC || transport.simplified == .unitBlackBoat,
              !movedCells.contains(point),
              !refuelableCells.isEmpty else {
            statusMessage = "No adjacent friendly units need supplies."
            return
        }

        let targets: [GridPoint]
        if transport.simplified == .unitBlackBoat {
            guard let target, refuelableCells.contains(target) else {
                statusMessage = "Choose one adjacent unit for the Black Boat to repair."
                return
            }
            targets = [target]
        } else {
            targets = Array(refuelableCells)
        }

        var repairedCount = 0
        for neighbor in targets {
            unitFuel[neighbor] = maxFuel(for: neighbor)
            if let adjacent = unit(at: neighbor),
               let ammo = PlaytestRulebook.primaryAmmo(for: adjacent, ruleset: ruleset) {
                unitAmmo[neighbor] = ammo
            }
            if transport.simplified == .unitBlackBoat,
               let adjacent = unit(at: neighbor),
               let stats = PlaytestRulebook.stats(for: adjacent, ruleset: ruleset),
               unitHealth[neighbor, default: 100] < 100 {
                let repairCost = max(1, stats.cost / 10)
                if funds[transport.army, default: 0] >= repairCost {
                    funds[transport.army, default: 0] -= repairCost
                    unitHealth[neighbor] = min(100, unitHealth[neighbor, default: 100] + 10)
                    repairedCount += 1
                }
            }
        }
        movedCells.insert(point)
        reachableCells.removeAll()
        updateTransportActions(for: transport, at: point)
        if transport.simplified == .unitBlackBoat {
            statusMessage = repairedCount == 1
                ? "Black Boat repaired and resupplied the selected unit."
                : "Black Boat resupplied the selected unit."
        } else {
            statusMessage = "APC resupplied \(targets.count) adjacent unit(s)."
        }
    }

    private func refuelAdjacentUnits(for army: Int) {
        for x in 0..<map.width {
            for y in 0..<map.height {
                let point = GridPoint(x: x, y: y)
                let transport = map.foregroundElement(atX: x, y: y)
                guard transport.isUnitNonEmpty,
                      transport.army == army,
                      transport.simplified == .unitAPC else { continue }
                for neighbor in cardinalNeighbors(of: point) {
                    guard isValid(neighbor),
                          let adjacent = unit(at: neighbor),
                          adjacent.army == army else { continue }
                    unitFuel[neighbor] = maxFuel(for: neighbor)
                    if let ammo = PlaytestRulebook.primaryAmmo(for: adjacent, ruleset: ruleset) {
                        unitAmmo[neighbor] = ammo
                    }
                }
            }
        }
    }

    /// Carriers replenish the aircraft they are sheltering at the start of
    /// their army's day. Cargo keeps its own fuel and ammo while loaded, so
    /// the refresh has to update the payload rather than a map coordinate.
    private func resupplyCarriedAircraft(for army: Int) {
        for point in cargo.keys {
            guard let transport = unit(at: point),
                  transport.army == army,
                  transport.simplified == .unitCarrier,
                  let loaded = cargo[point] else { continue }
            cargo[point] = loaded.map { payload in
                return PlaytestCargo(
                    unit: payload.unit,
                    health: payload.health,
                    fuel: PlaytestRulebook.maxFuel(for: payload.unit, ruleset: ruleset),
                    ammo: PlaytestRulebook.primaryAmmo(for: payload.unit, ruleset: ruleset)
                )
            }
        }
    }

    private func isPipeSeam(at point: GridPoint) -> Bool {
        guard isValid(point) else { return false }
        let background = map.backgroundElement(atX: point.x, y: point.y)
        if background.simplified == .terrainSeam { return true }
        // Imported maps can retain the seam in the derived draw layer while
        // storing the underlying tile as Plain D. Treat that visual seam as
        // the same attackable objective during playtest.
        return background.simplified == .terrainPlainD &&
            map.backgroundDrawElement(atX: point.x, y: point.y).simplified == .terrainSeam
    }

    private func canAttackPipeSeam(from origin: GridPoint, to destination: GridPoint, attacker: Element) -> Bool {
        guard isPipeSeam(at: destination),
              map.foregroundElement(atX: destination.x, y: destination.y) == .unitEmpty,
              let stats = PlaytestRulebook.stats(for: attacker, ruleset: ruleset),
              stats.maxRange > 0,
              (!movedCells.contains(origin) || stats.canMoveAndFire),
              isWithinRange(from: origin, to: destination, stats: stats) else { return false }

        // Use Infantry as a land-target sentinel so every cartridge-specific
        // damage table decides whether this attacker can fire at ground.
        return PlaytestRulebook.canAttack(
            attacker,
            Element.unitInfantry,
            ruleset: ruleset,
            primaryAmmo: unitAmmo[origin]
        )
    }

    private func pipeSeamDamage(from origin: GridPoint, to destination: GridPoint, attacker: Element) -> Int? {
        guard canAttackPipeSeam(from: origin, to: destination, attacker: attacker) else { return nil }
        return PlaytestRulebook.damage(
            attacker: attacker,
            defender: Element.unitInfantry,
            ruleset: ruleset,
            attackerHealth: unitHealth[origin, default: 100],
            defenderHealth: pipeSeamHealth[destination, default: Self.pipeSeamStartingHealth],
            terrain: .terrainSeam,
            primaryAmmo: unitAmmo[origin]
        )
    }

    private func attackableCells(from origin: GridPoint, unit: Element) -> Set<GridPoint> {
        guard let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset),
              stats.maxRange > 0,
              (!movedCells.contains(origin) || stats.canMoveAndFire) else { return [] }
        let requiresVisibility = isFogOfWarActive || !submergedUnits.isEmpty
        var result: Set<GridPoint> = []
        for x in 0..<map.width {
            for y in 0..<map.height {
                let point = GridPoint(x: x, y: y)
                let target = map.foregroundElement(atX: x, y: y)
                guard isWithinRange(from: origin, to: point, stats: stats) else { continue }

                if target.isUnitNonEmpty {
                    guard target.army != unit.army,
                          (!requiresVisibility || isVisible(point)),
                          (!submergedUnits.contains(point) || unit.simplified == .unitCruiser || unit.simplified == .unitSub),
                          PlaytestRulebook.canAttack(unit, target, ruleset: ruleset, primaryAmmo: unitAmmo[origin]) else { continue }
                    result.insert(point)
                } else if canAttackPipeSeam(from: origin, to: point, attacker: unit) {
                    // Pipe seams are known terrain objectives in Fog of War;
                    // unlike hidden units they do not require enemy vision.
                    result.insert(point)
                }
            }
        }
        return result
    }

    private func attackRangeCells(from origin: GridPoint, unit: Element) -> Set<GridPoint> {
        guard let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset),
              stats.maxRange > 0,
              (!movedCells.contains(origin) || stats.canMoveAndFire) else { return [] }
        var result: Set<GridPoint> = []
        for x in 0..<map.width {
            for y in 0..<map.height {
                let point = GridPoint(x: x, y: y)
                guard isWithinRange(from: origin, to: point, stats: stats) else { continue }
                result.insert(point)
            }
        }
        return result
    }

    private func isWithinRange(from origin: GridPoint, to destination: GridPoint, stats: PlaytestUnitStats?) -> Bool {
        guard let stats else { return false }
        let distance = distance(from: origin, to: destination)
        let weatherMaxRange = ruleset == .dualStrike
            ? PlaytestDualStrikeRules.maximumAttackRange(for: stats, weather: weather)
            : stats.maxRange
        return distance >= stats.minRange && distance <= weatherMaxRange
    }

    private func canCapture(unit: Element, stats: PlaytestUnitStats, at point: GridPoint) -> Bool {
        guard stats.canCapture else { return false }
        let building = map.backgroundElement(atX: point.x, y: point.y)
        return PlaytestRulebook.isCapturableBuilding(building, ruleset: ruleset) && building.army != activeArmy
    }

    private func collectIncome(for army: Int) {
        var income = 0
        for x in 0..<map.width {
            for y in 0..<map.height {
                let building = map.backgroundElement(atX: x, y: y)
                if building.isBuilding, building.army == army { income += PlaytestRulebook.income(for: building) }
            }
        }
        funds[army, default: 0] += income
    }

    private func repairUnits(for army: Int) {
        for x in 0..<map.width {
            for y in 0..<map.height {
                let point = GridPoint(x: x, y: y)
                let unit = map.foregroundElement(atX: x, y: y)
                let building = map.backgroundElement(atX: x, y: y)
                guard unit.isUnitNonEmpty,
                      unit.army == army,
                      building.isBuilding,
                      building.army == army,
                      canRepair(unit, on: building) else { continue }
                let currentHealth = unitHealth[point, default: 100]
                let missingHealth = max(0, 100 - currentHealth)
                let requestedHP = min(2, missingHealth / 10)
                let costPerHP = max(1, (PlaytestRulebook.stats(for: unit, ruleset: ruleset)?.cost ?? 0) / 10)
                let affordableHP = min(requestedHP, funds[army, default: 0] / costPerHP)
                unitHealth[point] = min(100, currentHealth + affordableHP * 10)
                funds[army, default: 0] -= affordableHP * costPerHP
                unitFuel[point] = PlaytestRulebook.maxFuel(for: unit, ruleset: ruleset)
                if let ammo = PlaytestRulebook.primaryAmmo(for: unit, ruleset: ruleset) {
                    unitAmmo[point] = ammo
                }
            }
        }
    }

    private func canRepair(_ unit: Element, on building: Element) -> Bool {
        switch PlaytestRulebook.stats(for: unit, ruleset: ruleset)?.domain {
        case .land:
            return [.buildingCity, .buildingBase, .buildingHQ].contains(building.simplified)
        case .air:
            return building.simplified == .buildingAirport
        case .sea:
            return building.simplified == .buildingPort
        case nil:
            return false
        }
    }

    @discardableResult
    private func consumeDailyFuel(for army: Int) -> Int {
        var destroyed: [GridPoint] = []
        for x in 0..<map.width {
            for y in 0..<map.height {
                let point = GridPoint(x: x, y: y)
                let unit = map.foregroundElement(atX: x, y: y)
                guard unit.isUnitNonEmpty, unit.army == army,
                      let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset) else { continue }

                let dailyFuelUse: Int
                if unit.simplified == .unitSub, submergedUnits.contains(point) {
                    dailyFuelUse = 5
                } else {
                    dailyFuelUse = stats.dailyFuelUse
                }
                guard dailyFuelUse > 0 else { continue }

                let remaining = unitFuel[point, default: stats.maxFuel] - dailyFuelUse
                if remaining <= 0, stats.domain == .air || stats.domain == .sea {
                    destroyed.append(point)
                } else {
                    unitFuel[point] = max(0, remaining)
                }
            }
        }

        guard !destroyed.isEmpty else { return 0 }
        var candidate = map
        for point in destroyed {
            _ = candidate.setForeground(.unitEmpty, atX: point.x, y: point.y)
            unitHealth.removeValue(forKey: point)
            unitFuel.removeValue(forKey: point)
            unitAmmo.removeValue(forKey: point)
            cargo.removeValue(forKey: point)
            submergedUnits.remove(point)
        }
        map = candidate
        return destroyed.count
    }

    @discardableResult
    private func processTurnStart(for army: Int) -> Int {
        collectIncome(for: army)
        repairUnits(for: army)
        refuelAdjacentUnits(for: army)
        resupplyCarriedAircraft(for: army)
        return consumeDailyFuel(for: army)
    }

    /// An army is routed only when it has neither units nor a property that
    /// can produce units. This keeps property-only starting positions playable
    /// while still making a completely eliminated army surrender every
    /// remaining property; HQs become neutral cities so the map keeps a useful
    /// property tile instead of retaining a defeated HQ sprite.
    @discardableResult
    private func resolveRouting() -> [Int] {
        guard winnerArmy == nil else { return [] }

        let candidates = survivingArmies
        guard !candidates.isEmpty else { return [] }
        var routed: [Int] = []

        for army in candidates {
            let hasRouted = !hasUnits(for: army) && !hasProductionProperty(for: army)
            guard hasRouted else { continue }
            neutralizeProperties(of: army)
            defeatedArmies.insert(army)
            routed.append(army)
        }

        guard !routed.isEmpty else { return [] }

        if defeatedArmies.contains(activeArmy) {
            activeArmy = nextSurvivingArmy(after: activeArmy) ?? activeArmy
            movedCells.removeAll()
            clearSelection()
        }

        let survivors = survivingArmies
        if candidates.count > 1, survivors.count == 1, let winner = survivors.first {
            winnerArmy = winner
            statusMessage = "\(armyName(winner)) routed all opponents and wins the playtest."
        } else if survivors.isEmpty {
            statusMessage = "No playable armies remain."
        } else {
            let names = routed.map { armyName($0) }.joined(separator: ", ")
            statusMessage = "\(names) was routed and its properties became neutral."
        }

        return routed
    }

    private func hasUnits(for army: Int) -> Bool {
        for x in 0..<map.width {
            for y in 0..<map.height {
                let unit = map.foregroundElement(atX: x, y: y)
                if unit.isUnitNonEmpty, unit.army == army,
                   PlaytestRulebook.stats(for: unit, ruleset: ruleset) != nil { return true }
            }
        }
        if cargo.values.flatMap({ $0 }).contains(where: {
            $0.unit.army == army && PlaytestRulebook.stats(for: $0.unit, ruleset: ruleset) != nil
        }) { return true }
        return false
    }

    private func unitCount(for army: Int) -> Int {
        var count = 0
        for x in 0..<map.width {
            for y in 0..<map.height {
                let unit = map.foregroundElement(atX: x, y: y)
                if unit.isUnitNonEmpty, unit.army == army,
                   PlaytestRulebook.stats(for: unit, ruleset: ruleset) != nil {
                    count += 1
                }
            }
        }
        count += cargo.values.flatMap { $0 }.reduce(into: 0) { result, payload in
            if payload.unit.army == army,
               PlaytestRulebook.stats(for: payload.unit, ruleset: ruleset) != nil {
                result += 1
            }
        }
        return count
    }

    private func hasProductionProperty(for army: Int) -> Bool {
        for x in 0..<map.width {
            for y in 0..<map.height {
                let building = map.backgroundElement(atX: x, y: y)
                guard building.isBuilding, building.army == army else { continue }
                if !PlaytestRulebook.productionOptions(for: building, ruleset: ruleset, tileset: map.tileset).isEmpty { return true }
            }
        }
        return false
    }

    private func neutralizeProperties(of army: Int) {
        var candidate = map
        for x in 0..<map.width {
            for y in 0..<map.height {
                let building = map.backgroundElement(atX: x, y: y)
                guard building.isBuilding, building.army == army else { continue }

                let replacement: Element
                if building.simplified == .buildingHQ {
                    replacement = Element.buildingCity.changedArmy(AWConstants.armyNeutral)
                } else {
                    replacement = building.changedArmy(AWConstants.armyNeutral)
                }
                _ = candidate.setBackground(replacement, atX: x, y: y, check: false)
            }
        }
        map = candidate
    }

    // MARK: - CPU playtest

    /// Runs CPU actions one at a time so the playtest can show the current
    /// enemy unit's movement range before it acts. The limit is a safety valve
    /// for malformed maps or a future rules change that accidentally leaves an
    /// action legal without consuming the unit's turn.
    private func runCPUIfNeeded() {
        guard !isExecutingCPU, isCPUArmy(activeArmy), !isGameOver else { return }

        isExecutingCPU = true
        let runID = UUID()
        cpuRunID = runID
        cpuTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.cpuRunID == runID {
                    self.isExecutingCPU = false
                    self.cpuTask = nil
                    self.clearCPUMovementPreview()
                    self.cpuMovementPathCache.removeAll(keepingCapacity: true)
                }
            }

            var actionCount = 0
            while self.isCPUArmy(self.activeArmy), !self.isGameOver {
                // Keep the malformed-map safety valve, but scope it to the
                // current army's turn. A CPU-vs-CPU game must be allowed to
                // continue across turns until routing or HQ capture produces
                // an actual winner.
                if actionCount >= 400 {
                    self.clearCPUMovementPreview()
                    self.endTurn()
                    actionCount = 0
                    try? await Task.sleep(nanoseconds: 1_000_000)
                    continue
                }

                // Planning runs on the main actor because it reads the live
                // session. Give SwiftUI a scheduling point before each
                // action so a large map cannot monopolize the actor while
                // the CPU is thinking.
                await Task.yield()
                guard !Task.isCancelled, self.cpuRunID == runID else { return }
                actionCount += 1
                guard let plan = self.bestCPUPlan() else {
                    self.clearCPUMovementPreview()
                    self.endTurn()
                    actionCount = 0
                    // A malformed or empty CPU turn should still yield before
                    // evaluating the next army rather than becoming a tight
                    // synchronous loop.
                    try? await Task.sleep(nanoseconds: 1_000_000)
                    continue
                }

                let previousArmy = self.activeArmy
                let previousMoved = self.movedCells
                let previousSelection = self.selectedPoint
                self.prepareCPUMovementPreview(for: plan.action)

                // Yield to SwiftUI so the current enemy unit's marker is
                // visible before the CPU commits its action.
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled, self.cpuRunID == runID else { return }

                await self.executeCPU(plan.action)
                self.clearCPUMovementPreview()

                // A legal plan should always consume an action or advance the
                // turn. Clear a stale selection if a malformed map rejects it
                // so the CPU cannot spin on the same plan forever.
                if self.activeArmy == previousArmy,
                   self.movedCells == previousMoved,
                   self.selectedPoint == previousSelection {
                    self.clearSelection()
                    self.statusMessage = "The CPU ended an unavailable action."
                }

                try? await Task.sleep(nanoseconds: 40_000_000)
                guard !Task.isCancelled, self.cpuRunID == runID else { return }
            }

            if self.isCPUArmy(self.activeArmy), !self.isGameOver {
                self.endTurn()
            }
        }
    }

    private func prepareCPUMovementPreview(for action: CPUAction) {
        clearCPUMovementPreview()

        guard case let .move(origin, _) = action,
              let unit = unit(at: origin),
              unit.army == activeArmy,
              PlaytestRulebook.stats(for: unit, ruleset: ruleset) != nil,
              !movedCells.contains(origin) else { return }

        cpuMovementPath = [origin]
    }

    private func clearCPUMovementPreview() {
        cpuMovementPath.removeAll(keepingCapacity: true)
    }

    private func makeCPUPlanningSnapshot() -> CPUPlanningSnapshot {
        var ownUnitPoints: [GridPoint] = []
        var enemyUnitPoints: [GridPoint] = []
        var enemyUnits: [CPUEnemyInfo] = []
        var ownPropertyPoints: [GridPoint] = []
        var enemyPropertyPoints: [GridPoint] = []
        var pipeSeamPoints: [GridPoint] = []
        var ownCounts: [Int: Int] = [:]
        var ownDomains = (land: 0, air: 0, sea: 0)
        var enemyDomains = (land: 0, air: 0, sea: 0)

        for point in allMapPoints() {
            let unit = map.foregroundElement(atX: point.x, y: point.y)
            if unit.isUnitNonEmpty,
               let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset) {
                if unit.army == activeArmy {
                    ownUnitPoints.append(point)
                    ownCounts[unit.simplified.value, default: 0] += 1
                    switch stats.domain {
                    case .land: ownDomains.land += 1
                    case .air: ownDomains.air += 1
                    case .sea: ownDomains.sea += 1
                    }
                } else {
                    enemyUnitPoints.append(point)
                    enemyUnits.append(CPUEnemyInfo(point: point, unit: unit, stats: stats))
                    switch stats.domain {
                    case .land: enemyDomains.land += 1
                    case .air: enemyDomains.air += 1
                    case .sea: enemyDomains.sea += 1
                    }
                }
            }

            let building = map.backgroundElement(atX: point.x, y: point.y)
            if building.isBuilding, building.army == activeArmy {
                ownPropertyPoints.append(point)
            } else if PlaytestRulebook.isCapturableBuilding(building, ruleset: ruleset),
                      building.army != activeArmy {
                enemyPropertyPoints.append(point)
            }
            if isPipeSeam(at: point) {
                pipeSeamPoints.append(point)
            }
        }

        return CPUPlanningSnapshot(
            ownUnitPoints: ownUnitPoints,
            enemyUnitPoints: enemyUnitPoints,
            enemyUnits: enemyUnits,
            ownPropertyPoints: ownPropertyPoints,
            enemyPropertyPoints: enemyPropertyPoints,
            pipeSeamPoints: pipeSeamPoints,
            ownCounts: ownCounts,
            ownDomains: ownDomains,
            enemyDomains: enemyDomains
        )
    }

    private func bestCPUPlan() -> CPUPlan? {
        cpuPlanningSnapshot = makeCPUPlanningSnapshot()
        cpuThreatCache.removeAll(keepingCapacity: true)
        cpuMovementPathCache.removeAll(keepingCapacity: true)
        cpuAttackableCache.removeAll(keepingCapacity: true)
        cpuNearestEnemyDistanceCache.removeAll(keepingCapacity: true)
        cpuTransportDropOffCache.removeAll(keepingCapacity: true)
        defer {
            cpuPlanningSnapshot = nil
            cpuThreatCache.removeAll(keepingCapacity: true)
            cpuAttackableCache.removeAll(keepingCapacity: true)
            cpuNearestEnemyDistanceCache.removeAll(keepingCapacity: true)
            cpuTransportDropOffCache.removeAll(keepingCapacity: true)
        }

        if let followUp = cpuFollowUpPlan() { return followUp }

        var plans: [CPUPlan] = []
        plans.append(contentsOf: cpuAttackPlans())
        plans.append(contentsOf: cpuCapturePlans())
        plans.append(contentsOf: cpuTransportPlans())
        plans.append(contentsOf: cpuBuildPlans())
        plans.append(contentsOf: cpuMovePlans())
        plans.append(contentsOf: cpuWaitPlans())
        return plans.max { lhs, rhs in
            if lhs.score == rhs.score {
                return cpuActionOrder(lhs.action) < cpuActionOrder(rhs.action)
            }
            return lhs.score < rhs.score
        }
    }

    /// A moved unit stays selected long enough to resolve an available attack
    /// or capture a property it entered. Other actions remain pre-movement
    /// actions.
    private func cpuFollowUpPlan() -> CPUPlan? {
        guard let point = selectedPoint,
              let unit = unit(at: point),
              unit.army == activeArmy else { return nil }

        if movedCells.contains(point) {
            if let capturePoint = captureableCells.first {
                return CPUPlan(score: captureScore(at: capturePoint), action: .capture(point: capturePoint))
            }
            if !attackableCells.isEmpty,
               let target = attackableCells.max(by: { attackScore(from: point, to: $0) < attackScore(from: point, to: $1) }) {
                return CPUPlan(score: attackScore(from: point, to: target), action: .attack(origin: point, target: target))
            }
            return CPUPlan(score: -10, action: .wait(point: point))
        }

        if !attackableCells.isEmpty,
           let target = attackableCells.max(by: { attackScore(from: point, to: $0) < attackScore(from: point, to: $1) }) {
            return CPUPlan(score: attackScore(from: point, to: target), action: .attack(origin: point, target: target))
        }

        if let capturePoint = captureableCells.first {
            return CPUPlan(score: captureScore(at: capturePoint), action: .capture(point: capturePoint))
        }

        let capacity = PlaytestRulebook.transportCapacity(for: unit)
        if capacity > 0, let cargoPoint = loadableCells.first {
            return CPUPlan(score: 150, action: .load(transport: point, cargo: cargoPoint))
        }
        if capacity == 0, !movedCells.contains(point), let transportPoint = loadableCells.first {
            return CPUPlan(score: 145, action: .move(origin: point, destination: transportPoint))
        }
        if let destination = unloadableCells.first {
            return CPUPlan(score: 140, action: .unload(transport: point, destination: destination))
        }
        if let destination = joinableCells.first {
            return CPUPlan(score: 95, action: .join(origin: point, destination: destination))
        }
        if !refuelableCells.isEmpty {
            return CPUPlan(score: 90, action: .resupply(point: point))
        }

        return nil
    }

    private func executeCPU(_ action: CPUAction) async {
        switch action {
        case let .attack(origin, target):
            selectedPoint = origin
            attack(to: target)
        case let .capture(point):
            selectedPoint = point
            capture()
        case let .build(point, option):
            selectedPoint = point
            buildUnit(option)
        case let .move(origin, destination):
            await executeCPUMove(from: origin, to: destination)
        case let .load(transport, cargoPoint):
            selectedPoint = transport
            if let transportUnit = unit(at: transport) {
                updateTransportActions(for: transportUnit, at: transport)
            }
            loadUnit(from: cargoPoint)
        case let .unload(transport, destination):
            selectedPoint = transport
            if let transportUnit = unit(at: transport) {
                updateTransportActions(for: transportUnit, at: transport)
            }
            unloadUnit(to: destination)
        case let .join(origin, destination):
            selectedPoint = origin
            joinUnit(to: destination)
        case let .resupply(point):
            selectedPoint = point
            if let transport = unit(at: point) {
                updateTransportActions(for: transport, at: point)
            }
            resupplySelectedTransport(target: refuelableCells.first)
        case let .wait(point):
            selectedPoint = point
            wait()
        }
    }

    private func cpuActionOrder(_ action: CPUAction) -> Int {
        switch action {
        case .attack: 0
        case .capture: 1
        case .load, .unload, .join, .resupply: 2
        case .build: 3
        case .move: 4
        case .wait: 5
        }
    }

    /// Commits a CPU move one tile at a time so the unit appears to walk,
    /// tread, sail, or fly across the board instead of teleporting to the
    /// planned destination. The existing movement routine still owns all
    /// legality, fuel, cargo, and post-move-action rules.
    private func executeCPUMove(from origin: GridPoint, to destination: GridPoint) async {
        guard let unit = unit(at: origin),
              let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset) else {
            selectUnit(at: origin)
            moveSelectedUnit(to: destination)
            return
        }

        let paths = movementPaths(from: origin, unit: unit, stats: stats)
        guard paths[destination] != nil else {
            selectUnit(at: origin)
            moveSelectedUnit(to: destination)
            return
        }

        var route: [GridPoint] = []
        var current = destination
        while current != origin {
            guard let path = paths[current], let previous = path.previous else {
                selectUnit(at: origin)
                moveSelectedUnit(to: destination)
                return
            }
            route.append(current)
            current = previous
        }
        route.reverse()

        cpuMovementPath = [origin]
        isAnimatingCPUMovement = true
        defer { isAnimatingCPUMovement = false }
        selectUnit(at: origin)
        let finalTileIsOccupied = map.foregroundElement(atX: destination.x, y: destination.y).isUnitNonEmpty
        let animatedRoute = finalTileIsOccupied ? Array(route.dropLast()) : route
        var stoppedAtOccupiedIntermediate = false

        for point in animatedRoute {
            guard !Task.isCancelled else { return }
            guard map.foregroundElement(atX: point.x, y: point.y) == .unitEmpty else {
                // Same-army units can be passed through for pathfinding, but
                // they cannot be occupied during the visual walk. Let the
                // normal final move resolve that route without corrupting a
                // friendly unit's tile.
                stoppedAtOccupiedIntermediate = true
                break
            }

            moveSelectedUnit(to: point)
            cpuMovementPath.append(point)
            try? await Task.sleep(nanoseconds: 90_000_000)
        }

        guard !Task.isCancelled else { return }
        isAnimatingCPUMovement = false

        if finalTileIsOccupied || stoppedAtOccupiedIntermediate {
            // A load/join/ambush endpoint, or a friendly unit passed through
            // by the planner, may not be occupied during the visual walk.
            // Still show the complete planned route before resolving that
            // endpoint, keeping every segment tile-bound.
            cpuMovementPath = [origin] + route
            try? await Task.sleep(nanoseconds: 60_000_000)
            moveSelectedUnit(to: destination)
        } else if let finalPoint = animatedRoute.last {
            configurePostMoveActions(for: unit, stats: stats, at: finalPoint)
        }
    }

    private func cpuUnitPoints() -> [GridPoint] {
        if let snapshot = cpuPlanningSnapshot {
            return snapshot.ownUnitPoints
        }
        var points: [GridPoint] = []
        for x in 0..<map.width {
            for y in 0..<map.height {
                let point = GridPoint(x: x, y: y)
                let unit = map.foregroundElement(atX: x, y: y)
                guard unit.isUnitNonEmpty,
                      unit.army == activeArmy,
                      PlaytestRulebook.stats(for: unit, ruleset: ruleset) != nil else { continue }
                points.append(point)
            }
        }
        return points
    }

    private func cpuPropertyPoints() -> [GridPoint] {
        if let snapshot = cpuPlanningSnapshot {
            return snapshot.ownPropertyPoints
        }
        var points: [GridPoint] = []
        for x in 0..<map.width {
            for y in 0..<map.height {
                let point = GridPoint(x: x, y: y)
                let building = map.backgroundElement(atX: x, y: y)
                guard building.isBuilding, building.army == activeArmy else { continue }
                points.append(point)
            }
        }
        return points
    }

    private func cpuAttackPlans() -> [CPUPlan] {
        var plans: [CPUPlan] = []
        for origin in cpuUnitPoints() where !movedCells.contains(origin) {
            let unit = map.foregroundElement(atX: origin.x, y: origin.y)
            for target in cpuAttackableCells(from: origin, unit: unit) {
                plans.append(CPUPlan(score: attackScore(from: origin, to: target), action: .attack(origin: origin, target: target)))
            }
        }
        return plans
    }

    private func cpuAttackableCells(from origin: GridPoint, unit attacker: Element) -> Set<GridPoint> {
        guard let stats = PlaytestRulebook.stats(for: attacker, ruleset: ruleset),
              stats.maxRange > 0,
              (!movedCells.contains(origin) || stats.canMoveAndFire) else { return [] }

        let key = CPUAttackKey(
            origin: origin,
            unitValue: attacker.simplified.value,
            primaryAmmo: unitAmmo[origin, default: -1],
            hasMoved: movedCells.contains(origin)
        )
        if let cached = cpuAttackableCache[key] {
            return cached
        }

        let requiresVisibility = isFogOfWarActive || !submergedUnits.isEmpty
        var result: Set<GridPoint> = []
        for enemy in cpuEnemyUnits() {
            let point = enemy.point
            guard isWithinRange(from: origin, to: point, stats: stats),
                  (!requiresVisibility || isVisible(point)),
                  (!submergedUnits.contains(point) || attacker.simplified == .unitCruiser || attacker.simplified == .unitSub),
                  PlaytestRulebook.canAttack(attacker, enemy.unit, ruleset: ruleset, primaryAmmo: unitAmmo[origin]) else { continue }
            result.insert(point)
        }
        for point in cpuPipeSeamPoints() {
            guard isWithinRange(from: origin, to: point, stats: stats),
                  canAttackPipeSeam(from: origin, to: point, attacker: attacker) else { continue }
            result.insert(point)
        }
        cpuAttackableCache[key] = result
        return result
    }

    /// Movement paths are stable for the duration of one planning pass. The
    /// planner previously rebuilt this BFS once for transport joins and again
    /// for every movement candidate, which multiplied the cost on larger maps.
    private func cpuMovementPaths(
        from origin: GridPoint,
        unit: Element,
        stats: PlaytestUnitStats
    ) -> [GridPoint: MovementPath] {
        let key = CPUPathKey(
            origin: origin,
            unitValue: unit.simplified.value,
            fuel: unitFuel[origin, default: stats.maxFuel]
        )
        if let cached = cpuMovementPathCache[key] {
            return cached
        }

        let paths = movementPaths(from: origin, unit: unit, stats: stats)
        cpuMovementPathCache[key] = paths
        return paths
    }

    private func cpuPipeSeamPoints() -> [GridPoint] {
        if let snapshot = cpuPlanningSnapshot {
            return snapshot.pipeSeamPoints
        }
        var points: [GridPoint] = []
        for point in allMapPoints() {
            if isPipeSeam(at: point) {
                points.append(point)
            }
        }
        return points
    }

    private func attackScore(from origin: GridPoint, to target: GridPoint) -> Double {
        let attacker = map.foregroundElement(atX: origin.x, y: origin.y)
        let defender = map.foregroundElement(atX: target.x, y: target.y)

        if defender == .unitEmpty, isPipeSeam(at: target),
           let damage = pipeSeamDamage(from: origin, to: target, attacker: attacker) {
            let currentHealth = pipeSeamHealth[target, default: Self.pipeSeamStartingHealth]
            let destructionBonus = currentHealth <= damage ? 900.0 : 420.0
            let nearbyEnemyCount = allEnemyUnitPoints().filter {
                distance(from: target, to: $0) <= 4
            }.count
            let threatPenalty = Double(cpuThreat(for: attacker, at: origin)) * 1.5
            // Opening a seam is a strategic objective, not a low-value empty
            // tile. Prefer a finishing shot, then a hit that creates access
            // for the rest of the army.
            return 500 + destructionBonus + Double(damage) * 5
                + Double(nearbyEnemyCount) * 12 - threatPenalty
        }

        let targetTerrain = map.backgroundElement(atX: target.x, y: target.y)
        guard let attackerStats = PlaytestRulebook.stats(for: attacker, ruleset: ruleset),
              let defenderStats = PlaytestRulebook.stats(for: defender, ruleset: ruleset),
              let damage = PlaytestRulebook.damage(
                attacker: attacker,
                defender: defender,
                ruleset: ruleset,
                attackerHealth: unitHealth[origin, default: 100],
                defenderHealth: unitHealth[target, default: 100],
                terrain: targetTerrain,
                primaryAmmo: unitAmmo[origin]
              ) else { return -.greatestFiniteMagnitude }

        let defenderHealth = unitHealth[target, default: 100]
        let distance = abs(origin.x - target.x) + abs(origin.y - target.y)
        let terrainStars = PlaytestRulebook.terrainStars(
            for: targetTerrain,
            ruleset: ruleset
        )
        let counterDamage: Int
        if defenderStats.canCounterattack,
           isWithinRange(from: target, to: origin, stats: defenderStats),
           let value = PlaytestRulebook.damage(
            attacker: defender,
            defender: attacker,
            ruleset: ruleset,
            attackerHealth: defenderHealth,
            defenderHealth: unitHealth[origin, default: 100],
            terrain: map.backgroundElement(atX: origin.x, y: origin.y),
            primaryAmmo: unitAmmo[target]
           ) {
            counterDamage = value
        } else {
            counterDamage = 0
        }

        let lethalBonus = damage >= defenderHealth ? 650.0 : 0
        let targetValue = Double(defenderStats.cost) / 20
        let damageValue = Double(damage) * 7
        let healthValue = Double(defenderHealth) / 8
        let terrainPenalty = Double(terrainStars) * 3
        let distancePenalty = Double(distance)
        let retaliationPenalty = Double(counterDamage) * (Double(attackerStats.cost) / 700)
        let threatPenalty = Double(cpuThreat(for: attacker, at: origin)) * 1.5
        // A legal shot against another army is itself a useful result. Keep
        // that floor high enough that the CPU does not pass on every attack
        // just because a safer build or move scored similarly.
        let attackPriority = 160.0
        return attackPriority + lethalBonus + targetValue + damageValue + healthValue
            - terrainPenalty - distancePenalty - retaliationPenalty - threatPenalty
    }

    private func cpuCapturePlans() -> [CPUPlan] {
        var plans: [CPUPlan] = []
        for point in cpuUnitPoints() where !movedCells.contains(point) {
            let unit = map.foregroundElement(atX: point.x, y: point.y)
            guard let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset),
                  canCapture(unit: unit, stats: stats, at: point) else { continue }
            plans.append(CPUPlan(score: captureScore(at: point), action: .capture(point: point)))
        }
        return plans
    }

    private func captureScore(at point: GridPoint) -> Double {
        let building = map.backgroundElement(atX: point.x, y: point.y)
        let progress = captureProgress[point, default: 0]
        let value = Double(PlaytestRulebook.income(for: building)) / 8
        let completionBonus = progress + 10 >= 20 ? 450.0 : 0
        let hqBonus = building.simplified == .buildingHQ ? 900.0 : 0
        let enemyBonus = building.army == AWConstants.armyNeutral ? 0 : 80.0
        let productionBonus: Double
        switch building.simplified {
        case .buildingAirport, .buildingPort:
            // These properties unlock an entire production domain and should
            // be treated as strategic objectives, not merely 1,000 G cities.
            productionBonus = 130
        case .buildingBase:
            productionBonus = 55
        default:
            productionBonus = 0
        }
        let healthValue = Double(unitHealth[point, default: 100]) / 5
        return 140 + value + completionBonus + hqBonus + enemyBonus + productionBonus + healthValue
    }

    private func cpuTransportPlans() -> [CPUPlan] {
        var plans: [CPUPlan] = []
        for point in cpuUnitPoints() where !movedCells.contains(point) {
            let unitElement = map.foregroundElement(atX: point.x, y: point.y)
            let capacity = PlaytestRulebook.transportCapacity(for: unitElement)

            if capacity > 0, cargo[point, default: []].count < capacity {
                for neighbor in neighbors(of: point) where isValid(neighbor) {
                    guard let candidate = unit(at: neighbor),
                          canLoad(candidate, into: unitElement, at: point) else { continue }
                    let cargoCost = PlaytestRulebook.stats(for: candidate, ruleset: ruleset)?.cost ?? 0
                    plans.append(CPUPlan(score: 120 + Double(cargoCost) / 100, action: .load(transport: point, cargo: neighbor)))
                }
            }

            if let loaded = cargo[point]?.first {
                for neighbor in neighbors(of: point) where isValid(neighbor) {
                    guard canUnload(loaded.unit, from: unitElement, at: neighbor) else { continue }
                    let destinationScore = cpuDestinationScore(for: loaded.unit, at: neighbor)
                    plans.append(CPUPlan(score: 115 + destinationScore, action: .unload(transport: point, destination: neighbor)))
                }
            }

            if unitElement.simplified == .unitAPC || unitElement.simplified == .unitBlackBoat {
                let needsResupply = resupplyNeighbors(of: point, transport: unitElement).contains { neighbor in
                    guard isValid(neighbor), let adjacent = self.unit(at: neighbor), adjacent.army == activeArmy else { return false }
                    let needsHealth = unitElement.simplified == .unitBlackBoat &&
                        unitHealth[neighbor, default: 100] < 100
                    let needsFuel = unitFuel[neighbor, default: maxFuel(for: neighbor)] < maxFuel(for: neighbor)
                    let needsAmmo = PlaytestRulebook.primaryAmmo(for: adjacent, ruleset: ruleset).map {
                        unitAmmo[neighbor, default: $0] < $0
                    } ?? false
                    return needsHealth || needsFuel || needsAmmo
                }
                if needsResupply {
                    plans.append(CPUPlan(score: 108, action: .resupply(point: point)))
                }
            }

            // Joining is useful when two damaged units meet. The action still
            // goes through the normal path and canJoin checks when executed.
            for neighbor in neighbors(of: point) where isValid(neighbor) {
                guard let candidate = unit(at: neighbor),
                      candidate.army == activeArmy,
                      candidate.simplified == unitElement.simplified,
                      unitHealth[point, default: 100] < 100 || unitHealth[neighbor, default: 100] < 100,
                      let stats = PlaytestRulebook.stats(for: unitElement, ruleset: ruleset),
                      let path = cpuMovementPaths(from: point, unit: unitElement, stats: stats)[neighbor],
                      path.movement <= stats.move else { continue }
                plans.append(CPUPlan(score: 96, action: .join(origin: point, destination: neighbor)))
            }
        }
        return plans
    }

    private func cpuBuildPlans() -> [CPUPlan] {
        var plans: [CPUPlan] = []
        guard !cpuPropertyPoints().isEmpty else { return plans }

        for point in cpuPropertyPoints() where !movedCells.contains(point) {
            let building = map.backgroundElement(atX: point.x, y: point.y)
            guard map.foregroundElement(atX: point.x, y: point.y) == .unitEmpty else { continue }
            guard (ruleset != .advanceWars || unitCount(for: activeArmy) < 50) else { continue }

            for option in PlaytestRulebook.productionOptions(for: building, ruleset: ruleset, tileset: map.tileset) {
                guard activeFunds >= option.cost,
                      map.allowPlacement(option.element.changedArmy(activeArmy), atX: point.x, y: point.y) else { continue }
                plans.append(CPUPlan(
                    score: cpuBuildScore(option, at: point, building: building),
                    action: .build(point: point, option: option)
                ))
            }
        }
        return plans
    }

    private func cpuBuildScore(_ option: PlaytestProductionOption, at point: GridPoint, building: Element) -> Double {
        guard let stats = PlaytestRulebook.stats(for: option.element, ruleset: ruleset) else { return -.greatestFiniteMagnitude }
        let enemyPoints = allEnemyUnitPoints()
        let ownCounts = cpuPlanningSnapshot?.ownCounts ?? cpuUnitCounts()
        let ownDomains = cpuPlanningSnapshot?.ownDomains ?? cpuDomainCounts(for: cpuUnitPoints())
        let enemyDomains = cpuPlanningSnapshot?.enemyDomains ?? cpuDomainCounts(for: enemyPoints)
        let enemyPropertyCount = enemyPropertyPoints().count
        let existingCount = ownCounts[option.element.simplified.value, default: 0]

        // The base term rewards useful stats, but affordability is deliberately
        // gentle: a CPU should save for the right counter instead of always
        // selecting the cheapest legal unit.
        var score = 30 + Double(stats.attackPower) / 8 + Double(stats.move) * 1.5
        score -= Double(option.cost) / 2_500
        score += cpuBuildRoleScore(
            for: option.element,
            stats: stats,
            ownCounts: ownCounts,
            enemyDomains: enemyDomains,
            enemyPropertyCount: enemyPropertyCount
        )
        score += cpuProductionPropertyScore(
            for: building,
            option: option.element,
            ownDomains: ownDomains,
            enemyDomains: enemyDomains,
            enemyPropertyCount: enemyPropertyCount,
            at: point
        )

        // Diminishing returns keep any single unit type from filling every
        // production property, with infantry receiving the strongest repeat
        // penalty because it is the default capture unit.
        score -= Double(existingCount) * (option.element.simplified == .unitInfantry ? 16 : 10)

        // Keep a little cash in reserve for a counterattack or capture follow-
        // up, but permit expensive units when the treasury can support them.
        if Double(option.cost) > Double(activeFunds) * 0.75 { score -= 12 }
        return score
    }

    private func cpuProductionPropertyScore(
        for building: Element,
        option: Element,
        ownDomains: (land: Int, air: Int, sea: Int),
        enemyDomains: (land: Int, air: Int, sea: Int),
        enemyPropertyCount: Int,
        at point: GridPoint
    ) -> Double {
        switch building.simplified {
        case .buildingAirport:
            // An airport is not another land factory. Once the CPU has paid
            // to own one, give it a strong reason to put an aircraft on it.
            var score = ownDomains.air == 0 ? 82.0 : 58.0
            if option.simplified == .unitFighter, enemyDomains.air > 0 { score += 32 }
            if option.simplified == .unitBomber, enemyDomains.land > 0 { score += 28 }
            if option.simplified == .unitTCopter, enemyPropertyCount > 0 { score += 18 }
            return score
        case .buildingPort:
            // Ports need a visible strategic payoff or the general land-unit
            // score will otherwise make naval production look wasteful.
            var score = ownDomains.sea == 0 ? 88.0 : 62.0
            if option.simplified == .unitCruiser, enemyDomains.air > 0 || enemyDomains.sea > 0 { score += 30 }
            if option.simplified == .unitBattleship, enemyDomains.land > 0 { score += 34 }
            if option.simplified == .unitLander, enemyPropertyCount > 0 { score += 24 }
            return score
        case .buildingBase:
            return 0
        default:
            // Keep the point argument meaningful for future property-aware
            // heuristics without changing production behavior for cities/HQs.
            _ = point
            return 0
        }
    }

    private func cpuBuildRoleScore(
        for element: Element,
        stats: PlaytestUnitStats,
        ownCounts: [Int: Int],
        enemyDomains: (land: Int, air: Int, sea: Int),
        enemyPropertyCount: Int
    ) -> Double {
        let type = element.simplified
        let captureUnits = ownCounts[Element.unitInfantry.value, default: 0]
            + ownCounts[Element.unitMech.value, default: 0]
        let desiredCaptureUnits = min(4, max(1, enemyPropertyCount))
        let captureNeed = max(0, desiredCaptureUnits - captureUnits)
        let landThreat = Double(enemyDomains.land)
        let airThreat = Double(enemyDomains.air)
        let seaThreat = Double(enemyDomains.sea)

        switch type {
        case .unitInfantry:
            // One or two infantry are useful for a capture plan. Once that
            // need is covered, this role becomes intentionally unattractive.
            return captureNeed > 0
                ? min(60, 24 + Double(captureNeed) * 10)
                : -55
        case .unitMech:
            return (captureNeed > 0 ? 30 + min(18, Double(captureNeed) * 5) : -8)
                + min(24, landThreat * 4)
        case .unitAPC:
            return captureUnits > 0 ? 28 : 12
        case .unitRecon:
            return 18 + min(24, landThreat * 4)
        case .unitTank:
            return 28 + min(32, landThreat * 5)
        case .unitMDTank, .unitNeoTank, .unitMegaTank:
            return 24 + min(38, landThreat * 5)
        case .unitArtillery:
            return 24 + min(42, landThreat * 7)
        case .unitRocket:
            return 18 + min(42, landThreat * 7)
        case .unitMissile:
            return 10 + min(56, airThreat * 22)
        case .unitAntiAir:
            return 10 + min(72, airThreat * 28)
        case .unitTCopter:
            return 12 + (captureNeed > 0 ? 22 : 0)
        case .unitBCopter:
            return 18 + min(42, landThreat * 6) + min(24, airThreat * 8)
        case .unitFighter:
            return 12 + min(78, airThreat * 30)
        case .unitBomber:
            return 22 + min(62, landThreat * 12)
        case .unitStealth, .unitBlackBomb:
            return 18 + min(42, landThreat * 8) + min(20, airThreat * 6)
        case .unitLander:
            return 8 + (captureNeed > 0 ? 24 : 0)
        case .unitBlackBoat:
            return 12 + min(42, landThreat * 7)
        case .unitCruiser:
            return 16 + min(54, airThreat * 16 + seaThreat * 8)
        case .unitSub:
            return 18 + min(64, seaThreat * 20)
        case .unitBattleship:
            return 22 + min(72, landThreat * 12 + seaThreat * 5)
        case .unitCarrier:
            return 15 + min(36, airThreat * 10 + seaThreat * 4)
        default:
            return Double(stats.attackPower) / 6
        }
    }

    private func cpuUnitCounts() -> [Int: Int] {
        if let snapshot = cpuPlanningSnapshot {
            return snapshot.ownCounts
        }
        var counts: [Int: Int] = [:]
        for point in cpuUnitPoints() {
            let type = map.foregroundElement(atX: point.x, y: point.y).simplified.value
            counts[type, default: 0] += 1
        }
        return counts
    }

    private func cpuDomainCounts(for points: [GridPoint]) -> (land: Int, air: Int, sea: Int) {
        var counts = (land: 0, air: 0, sea: 0)
        for point in points {
            let unit = map.foregroundElement(atX: point.x, y: point.y)
            switch PlaytestRulebook.stats(for: unit, ruleset: ruleset)?.domain {
            case .land: counts.land += 1
            case .air: counts.air += 1
            case .sea: counts.sea += 1
            case nil: break
            }
        }
        return counts
    }

    private func cpuMovePlans() -> [CPUPlan] {
        var plans: [CPUPlan] = []
        for origin in cpuUnitPoints() where !movedCells.contains(origin) {
            let unit = map.foregroundElement(atX: origin.x, y: origin.y)
            guard let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset) else { continue }
            let paths = cpuMovementPaths(from: origin, unit: unit, stats: stats)
            for (destination, path) in paths {
                let occupant = map.foregroundElement(atX: destination.x, y: destination.y)
                guard occupant == .unitEmpty ||
                        canLoad(unit, into: occupant, at: destination) ||
                        canJoin(unit, with: occupant, at: destination, firstPoint: origin) else { continue }
                // A CPU can see an ambush endpoint in the editor's model, but
                // it should not knowingly throw a unit into the hidden enemy.
                guard !isHiddenEnemy(occupant, at: destination, relativeTo: unit) else { continue }

                let score = cpuMoveScore(
                    unit: unit,
                    origin: origin,
                    destination: destination,
                    movement: path.movement
                )
                plans.append(CPUPlan(score: score, action: .move(origin: origin, destination: destination)))
            }
        }
        return plans
    }

    private func cpuMoveScore(unit: Element, origin: GridPoint, destination: GridPoint, movement: Int) -> Double {
        guard let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset) else { return -.greatestFiniteMagnitude }
        let before = nearestEnemyDistance(from: origin)
        let after = nearestEnemyDistance(from: destination)
        let distanceGain = before == .max || after == .max ? 0 : before - after
        let terrain = map.backgroundElement(atX: destination.x, y: destination.y)
        let terrainStars = PlaytestRulebook.terrainStars(for: terrain, ruleset: ruleset)
        let threat = cpuThreat(for: unit, at: destination)
        let propertyValue: Double
        let building = terrain
        if stats.canCapture,
           PlaytestRulebook.isCapturableBuilding(building, ruleset: ruleset),
           building.army != activeArmy {
            propertyValue = captureScore(at: destination) / 2
        } else {
            propertyValue = 0
        }

        let attackOpportunity = cpuAdjacentAttackValue(for: unit, at: destination)
        let defensiveValue = Double(terrainStars) * 5
        let movementCost = Double(movement) * 2
        let supplyObjective = cpuSupplyPropertyScore(for: unit, origin: origin, at: destination)
        let transportObjective = cpuTransportObjectiveScore(
            for: unit,
            origin: origin,
            destination: destination
        )
        let turnsToEngagement = cpuTurnsToEngagement(at: destination, stats: stats)
        let isTwoTurnApproach = stats.attackPower > 0 && turnsToEngagement <= 2
        // A combat unit that can reach an enemy's attack range in about two
        // turns should accept some exposure. Keep the threat penalty for
        // longer approaches, but avoid making the CPU wait forever outside
        // every contested tile.
        let threatWeight = isTwoTurnApproach ? 2.0 : 12.0
        let approachBonus = isTwoTurnApproach
            ? 40.0 + (Double(stats.attackPower) * 2)
            : 0
        let threatPenalty = Double(threat) * threatWeight
        return 8 + Double(distanceGain) * 12 + propertyValue + attackOpportunity + defensiveValue
            + supplyObjective + transportObjective + approachBonus - movementCost - threatPenalty
    }

    private func cpuSupplyPropertyScore(for unit: Element, origin: GridPoint, at point: GridPoint) -> Double {
        let building = map.backgroundElement(atX: point.x, y: point.y)
        guard building.isBuilding, building.army == activeArmy,
              let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset) else { return 0 }

        let health = unitHealth[origin, default: 100]
        let fuel = unitFuel[origin, default: stats.maxFuel]
        let needsSupply = health < 100 || fuel < stats.maxFuel
        switch stats.domain {
        case .air where building.simplified == .buildingAirport:
            return needsSupply ? 170 : 24
        case .sea where building.simplified == .buildingPort:
            return needsSupply ? 170 : 24
        case .land where [.buildingCity, .buildingBase, .buildingHQ].contains(building.simplified):
            return needsSupply ? 100 : 12
        default:
            return 0
        }
    }

    private func cpuTransportObjectiveScore(for transport: Element, origin: GridPoint, destination: GridPoint) -> Double {
        guard let loaded = cargo[origin]?.first else { return 0 }

        if canUnload(loaded.unit, from: transport, at: destination) {
            // A legal drop-off is more useful than merely getting closer to an
            // enemy. This is what makes landers seek shoals/ports and
            // T-Copters seek land instead of circling the coast.
            return 210 + cpuDestinationScore(for: loaded.unit, at: destination)
        }

        let unloadDistance = cpuTransportDropOffs(for: transport, cargo: loaded.unit)
        .map { distance(from: destination, to: $0) }
        .min()

        guard let unloadDistance else { return 0 }
        return max(0, 90 - Double(unloadDistance) * 12)
    }

    private func cpuTransportDropOffs(for transport: Element, cargo: Element) -> [GridPoint] {
        let key = CPUTransportKey(
            transportValue: transport.simplified.value,
            cargoValue: cargo.simplified.value
        )
        if let cached = cpuTransportDropOffCache[key] {
            return cached
        }

        var points: [GridPoint] = []
        for point in allMapPoints() {
            if canUnload(cargo, from: transport, at: point) {
                points.append(point)
            }
        }
        cpuTransportDropOffCache[key] = points
        return points
    }

    private func cpuTurnsToEngagement(at point: GridPoint, stats: PlaytestUnitStats) -> Int {
        guard stats.attackPower > 0, stats.maxRange > 0 else { return .max }
        let nearestDistance = nearestEnemyDistance(from: point)
        let closestDistance = nearestDistance == .max
            ? Int.max
            : max(0, nearestDistance - stats.maxRange)
        guard closestDistance != .max else { return .max }
        let movementPerTurn = max(1, stats.move)
        return (closestDistance + movementPerTurn - 1) / movementPerTurn
    }

    private func cpuWaitPlans() -> [CPUPlan] {
        cpuUnitPoints()
            .filter { !movedCells.contains($0) }
            .map { CPUPlan(score: 0, action: .wait(point: $0)) }
    }

    private func cpuThreat(for unit: Element, at point: GridPoint) -> Int {
        let key = CPUThreatKey(
            unitValue: unit.simplified.value,
            point: point,
            health: unitHealth[point, default: 100]
        )
        if let cached = cpuThreatCache[key] {
            return cached
        }

        let unitCost = PlaytestRulebook.stats(for: unit, ruleset: ruleset)?.cost ?? 0
        let defenderTerrain = map.backgroundElement(atX: point.x, y: point.y)
        let terrainStars = PlaytestRulebook.terrainStars(for: defenderTerrain, ruleset: ruleset)
        let terrainScale = max(0.55, 1 - (Double(terrainStars) * 0.08))
        var threat = 0
        for enemyInfo in cpuEnemyUnits() {
            let enemyPoint = enemyInfo.point
            let enemy = enemyInfo.unit
            let enemyStats = enemyInfo.stats
            guard isWithinRange(from: enemyPoint, to: point, stats: enemyStats),
                  PlaytestRulebook.canAttack(enemy, unit, ruleset: ruleset, primaryAmmo: unitAmmo[enemyPoint]) else { continue }
            // Planning does not need a random combat roll for every
            // candidate square. Use a stable damage proxy here; the exact
            // cartridge damage table remains authoritative when an attack is
            // executed. This keeps threat evaluation cheap and repeatable.
            let healthScale = Double(unitHealth[enemyPoint, default: 100]) / 100
            let damageEstimate = Int(
                (Double(enemyStats.attackPower) * healthScale * terrainScale).rounded(.down)
            )
            threat += max(1, damageEstimate + unitCost / 500)
        }
        cpuThreatCache[key] = threat
        return threat
    }

    private func cpuAdjacentAttackValue(for unit: Element, at point: GridPoint) -> Double {
        // Movement scoring only needs to know whether a destination reaches a
        // likely engagement window. The full target/domain/damage model is
        // still evaluated for actual attack plans; scanning every opponent for
        // every reachable destination made one CPU turn disproportionately
        // costly. A nearest-enemy range check is a conservative signal here,
        // while the legal attack list remains authoritative when the unit acts.
        guard let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset),
              stats.maxRange > 0 else { return 0 }
        let nearest = nearestEnemyDistance(from: point)
        guard nearest >= stats.minRange,
              nearest <= (ruleset == .dualStrike
                ? PlaytestDualStrikeRules.maximumAttackRange(for: stats, weather: weather)
                : stats.maxRange) else { return 0 }
        return 80 + (Double(stats.attackPower) / 4)
    }

    private func cpuDestinationScore(for unit: Element, at point: GridPoint) -> Double {
        let enemyDistance = nearestEnemyDistance(from: point)
        let proximity = enemyDistance == Int.max ? 0 : max(0, 8 - enemyDistance)
        return 20 + Double(proximity) * 3 - Double(cpuThreat(for: unit, at: point)) * 2
    }

    private func allEnemyUnitPoints() -> [GridPoint] {
        if let snapshot = cpuPlanningSnapshot {
            return snapshot.enemyUnitPoints
        }
        var points: [GridPoint] = []
        for x in 0..<map.width {
            for y in 0..<map.height {
                let point = GridPoint(x: x, y: y)
                let unit = map.foregroundElement(atX: x, y: y)
                if unit.isUnitNonEmpty, unit.army != activeArmy,
                   PlaytestRulebook.stats(for: unit, ruleset: ruleset) != nil {
                    points.append(point)
                }
            }
        }
        return points
    }

    private func cpuEnemyUnits() -> [CPUEnemyInfo] {
        if let snapshot = cpuPlanningSnapshot {
            return snapshot.enemyUnits
        }

        var enemies: [CPUEnemyInfo] = []
        for point in allEnemyUnitPoints() {
            let enemy = map.foregroundElement(atX: point.x, y: point.y)
            guard let stats = PlaytestRulebook.stats(for: enemy, ruleset: ruleset) else { continue }
            enemies.append(CPUEnemyInfo(point: point, unit: enemy, stats: stats))
        }
        return enemies
    }

    private func enemyPropertyPoints() -> [GridPoint] {
        if let snapshot = cpuPlanningSnapshot {
            return snapshot.enemyPropertyPoints
        }
        var points: [GridPoint] = []
        for x in 0..<map.width {
            for y in 0..<map.height {
                let point = GridPoint(x: x, y: y)
                let building = map.backgroundElement(atX: x, y: y)
                if PlaytestRulebook.isCapturableBuilding(building, ruleset: ruleset), building.army != activeArmy {
                    points.append(point)
                }
            }
        }
        return points
    }

    private func nearestEnemyDistance(from point: GridPoint) -> Int {
        if let cached = cpuNearestEnemyDistanceCache[point] {
            return cached
        }
        let nearest = allEnemyUnitPoints().map { distance(from: point, to: $0) }.min() ?? .max
        if cpuPlanningSnapshot != nil {
            cpuNearestEnemyDistanceCache[point] = nearest
        }
        return nearest
    }

    private func nearestFriendlyPropertyPoint() -> GridPoint {
        cpuPropertyPoints().first ?? GridPoint(x: 0, y: 0)
    }

    private func distance(from first: GridPoint, to second: GridPoint) -> Int {
        guard isStaggeredGrid else {
            return abs(first.x - second.x) + abs(first.y - second.y)
        }

        // Odd-row horizontal offset coordinates map cleanly to cube
        // coordinates. This keeps GB Wars' staggered movement, attack range,
        // vision, and CPU distance scoring consistent with its cell layout.
        let firstQ = first.x - (first.y - (first.y & 1)) / 2
        let secondQ = second.x - (second.y - (second.y & 1)) / 2
        let firstR = first.y
        let secondR = second.y
        let firstS = -firstQ - firstR
        let secondS = -secondQ - secondR
        return max(
            abs(firstQ - secondQ),
            max(abs(firstR - secondR), abs(firstS - secondS))
        )
    }

    private func isCPUArmy(_ army: Int) -> Bool {
        army != AWConstants.armyOrangeStar && armies.contains(army)
    }

    private func nextSurvivingArmy(after army: Int) -> Int? {
        guard !armies.isEmpty else { return nil }
        let startIndex = armies.firstIndex(of: army) ?? -1
        for offset in 1...armies.count {
            let index = (startIndex + offset) % armies.count
            let candidate = armies[index]
            if !defeatedArmies.contains(candidate) { return candidate }
        }
        return nil
    }

    private func unit(at point: GridPoint) -> Element? {
        let unit = map.foregroundElement(atX: point.x, y: point.y)
        return unit.isUnitNonEmpty ? unit : nil
    }

    private func neighbors(of point: GridPoint) -> [GridPoint] {
        guard isStaggeredGrid else {
            return cardinalNeighbors(of: point)
        }

        let upperLowerLeft = point.y.isMultiple(of: 2) ? point.x - 1 : point.x
        let upperLowerRight = point.y.isMultiple(of: 2) ? point.x : point.x + 1
        return [
            GridPoint(x: point.x - 1, y: point.y), GridPoint(x: point.x + 1, y: point.y),
            GridPoint(x: upperLowerLeft, y: point.y - 1),
            GridPoint(x: upperLowerRight, y: point.y - 1),
            GridPoint(x: upperLowerLeft, y: point.y + 1),
            GridPoint(x: upperLowerRight, y: point.y + 1)
        ]
    }

    private func cardinalNeighbors(of point: GridPoint) -> [GridPoint] {
        [
            GridPoint(x: point.x - 1, y: point.y), GridPoint(x: point.x + 1, y: point.y),
            GridPoint(x: point.x, y: point.y - 1), GridPoint(x: point.x, y: point.y + 1)
        ]
    }

    private func resupplyNeighbors(of point: GridPoint, transport: Element) -> [GridPoint] {
        transport.simplified == .unitAPC
            ? cardinalNeighbors(of: point)
            : neighbors(of: point)
    }

    private func clearSelection() {
        selectedPoint = nil
        clearPlayerMovementPreview()
        reachableCells.removeAll()
        attackableCells.removeAll()
        captureableCells.removeAll()
        loadableCells.removeAll()
        joinableCells.removeAll()
        unloadableCells.removeAll()
        refuelableCells.removeAll()
        siloTargetCells.removeAll()
        isSelectingSiloTarget = false
        productionOptions.removeAll()
        clearAttackPreview()
    }

    /// Updates the orange route preview for a player drag. The destination
    /// must be one of the same legal movement cells used by a normal tap;
    /// invalid tiles leave the last valid preview in place until release.
    @discardableResult
    func updatePlayerMovementPreview(to destination: GridPoint) -> Bool {
        guard !isGameOver,
              !isCPUArmy(activeArmy),
              !isAnimatingCPUMovement,
              let origin = selectedPoint,
              let unit = unit(at: origin),
              unit.army == activeArmy,
              !movedCells.contains(origin),
              reachableCells.contains(destination),
              let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset) else {
            return false
        }

        let paths = movementPaths(from: origin, unit: unit, stats: stats)
        guard paths[destination] != nil,
              let route = movementRoute(from: origin, to: destination, paths: paths) else {
            return false
        }
        playerMovementPath = route
        return route.count > 1
    }

    /// Commits a player route only when the pointer is still over the route's
    /// final legal tile. Releasing outside the movement range cancels the
    /// preview without moving the unit.
    @discardableResult
    func commitPlayerMovementPreview(at destination: GridPoint) -> Bool {
        guard playerMovementPath.count > 1,
              playerMovementPath.last == destination else {
            clearPlayerMovementPreview()
            return false
        }

        clearPlayerMovementPreview()
        moveSelectedUnit(to: destination)
        return true
    }

    func clearPlayerMovementPreview() {
        playerMovementPath.removeAll(keepingCapacity: true)
    }

    private func clearAttackPreview() {
        attackPreviewOrigin = nil
        attackPreviewCells.removeAll()
    }

    private func isValid(_ point: GridPoint) -> Bool {
        point.x >= 0 && point.x < map.width && point.y >= 0 && point.y < map.height
    }

    private func initializeUnitResources() {
        unitHealth.removeAll()
        unitFuel.removeAll()
        unitAmmo.removeAll()
        for x in 0..<map.width {
            for y in 0..<map.height {
                let point = GridPoint(x: x, y: y)
                let unit = map.foregroundElement(atX: x, y: y)
                guard unit.isUnitNonEmpty else { continue }
                unitHealth[point] = 100
                unitFuel[point] = PlaytestRulebook.maxFuel(for: unit, ruleset: ruleset)
                if let ammo = PlaytestRulebook.primaryAmmo(for: unit, ruleset: ruleset) {
                    unitAmmo[point] = ammo
                }
            }
        }
    }

    private func initializePipeSeams() {
        pipeSeamHealth.removeAll()
        for x in 0..<map.width {
            for y in 0..<map.height {
                let point = GridPoint(x: x, y: y)
                if isPipeSeam(at: point) {
                    pipeSeamHealth[point] = Self.pipeSeamStartingHealth
                }
            }
        }
    }

    private func maxFuel(for point: GridPoint) -> Int {
        guard let unit = unit(at: point) else { return 100 }
        return PlaytestRulebook.maxFuel(for: unit, ruleset: ruleset)
    }

    private static func armies(in map: MapState) -> [Int] {
        var found = Set<Int>()
        let playableArmies = Set(PaletteCatalog.playtestArmies(for: map.tileset))
        for x in 0..<map.width {
            for y in 0..<map.height {
                let unit = map.foregroundElement(atX: x, y: y)
                let building = map.backgroundElement(atX: x, y: y)
                if unit.isUnitNonEmpty, playableArmies.contains(unit.army) { found.insert(unit.army) }
                if building.isBuilding, playableArmies.contains(building.army) { found.insert(building.army) }
            }
        }
        return found.sorted()
    }

}

struct PlaytestView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var session: PlaytestSession
    @State private var previewModel: EditorModel
    @State private var dayBannerSequence = 0
    @State private var isDayBannerVisible = false

    let atlas: SpriteAtlas
    let mapSize: CGSize

    init(map: MapState, visualVariant: MapVisualVariant? = nil, atlas: SpriteAtlas) {
        let session = PlaytestSession(map: map, visualVariant: visualVariant)
        _session = State(initialValue: session)
        let previewModel = EditorModel(map: session.displayMap)
        previewModel.spritePalette = session.displayPalette
        _previewModel = State(initialValue: previewModel)
        self.atlas = atlas
        self.mapSize = MapCanvasMetrics.mapPixelSize(
            width: map.width,
            height: map.height,
            tileSize: MapCanvasMetrics.tileSize,
            staggered: session.isStaggeredGrid
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            PlaytestHeader(
                session: session,
                restartAction: session.restart,
                endTurnAction: session.endTurn,
                exitAction: {
                    session.stopCPU()
                    dismiss()
                }
            )
            Divider()
            HStack(spacing: 0) {
                PlaytestMapColumn(
                    session: session,
                    previewModel: previewModel,
                    atlas: atlas,
                    mapSize: mapSize,
                    showDayBanner: isDayBannerVisible,
                    dayBannerSequence: dayBannerSequence
                )
                Divider()
                PlaytestInspector(session: session)
                    .frame(width: 270)
                    // A playtest is presented as a sheet. Use the same
                    // sidebar material, but blend within that sheet so menu
                    // flyouts do not try to sample through the parent window.
                    .background(GLWNSidebarSurface(blendingMode: .withinWindow))
            }
        }
        .frame(minWidth: 1_080, minHeight: 680)
        .onAppear {
            syncPreviewModel()
            presentDayBanner()
        }
        .task(id: dayBannerSequence) {
            guard dayBannerSequence > 0 else { return }
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                isDayBannerVisible = false
            }
        }
        .onChange(of: session.mapRevision) { _, _ in syncPreviewModel() }
        .onChange(of: session.activeArmy) { _, _ in
            // The backdrop only changes with the active army when Fog of War
            // (or submerged enemy rendering) is involved. Avoid rebuilding
            // the entire sprite Canvas on every ordinary CPU turn switch.
            if session.isFogOfWarActive || !session.submergedUnits.isEmpty {
                syncPreviewModel()
            }
            presentDayBanner()
        }
        .onChange(of: session.fogOfWarEnabled) { _, _ in syncPreviewModel() }
        .onChange(of: session.weather) { _, _ in syncPreviewModel() }
        .onChange(of: session.submergedRevision) { _, _ in syncPreviewModel() }
    }

    private func syncPreviewModel() {
        previewModel.map = session.displayMap
        previewModel.spritePalette = session.displayPalette
    }

    private func presentDayBanner() {
        withAnimation(.easeOut(duration: 0.16)) {
            dayBannerSequence &+= 1
            isDayBannerVisible = true
        }
    }
}

private struct PlaytestHeader: View {
    let session: PlaytestSession
    let restartAction: () -> Void
    let endTurnAction: () -> Void
    let exitAction: () -> Void

    var body: some View {
        @Bindable var session = session
        HStack(spacing: 12) {
            Label("Playtest", systemImage: "gamecontroller.fill")
                .font(.headline)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.ruleset.displayName)
                    .font(.subheadline.weight(.semibold))
                Text("Current Ruleset")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if session.ruleset == .advanceWars || session.ruleset == .advanceWars2 || session.ruleset == .dualStrike {
                GLWNPullDownMenu(
                    "Weather",
                    selection: Binding(
                        get: { session.weatherMode },
                        set: { session.setWeatherMode($0) }
                    ),
                    options: PlaytestRulebook.weatherOptions(for: session.ruleset),
                    showsTitle: false
                ) { weather in
                    Text(weather.displayName)
                }
                .frame(minWidth: 78)
                .help(session.weatherMode == .random
                    ? "Weather changes randomly at the start of each day. Current: \(session.weather.displayName)."
                    : "Choose the weather used for movement, vision, and combat.")

                HStack (spacing: 6) {
                    Toggle("Fog", isOn: $session.fogOfWarEnabled)
                        .toggleStyle(GLWNAquaToggleStyle())
                        .disabled(session.isFogForcedByWeather)
                        .help(session.isFogForcedByWeather
                            ? "Rain forces Fog of War in Dual Strike"
                            : "Hide enemy units outside friendly vision")

                    Text("Fog")
                        .font(.caption.weight(.semibold))
                }
            }

            Spacer(minLength: 14)

            Button("Exit", systemImage: "xmark.rectangle", action: exitAction)
                .buttonStyle(GLWNInContentButtonStyle(tone: .neutral, horizontalPadding: 14, minHeight: 32))
            Button("Restart", systemImage: "arrow.counterclockwise", action: restartAction)
                .buttonStyle(GLWNInContentButtonStyle(tone: .neutral, horizontalPadding: 14, minHeight: 32))
            Button("End Turn", systemImage: "forward.fill", action: endTurnAction)
                .buttonStyle(GLWNInContentButtonStyle(tone: .accent, horizontalPadding: 14, minHeight: 32))
                .disabled(session.isGameOver || session.activeArmyIsCPU)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .backgroundStyle(.regularMaterial)
    }
}

private struct PlaytestMapColumn: View {
    let session: PlaytestSession
    let previewModel: EditorModel
    let atlas: SpriteAtlas
    let mapSize: CGSize
    let showDayBanner: Bool
    let dayBannerSequence: Int

    var body: some View {
        ZStack(alignment: .center) {
            PlaytestMapSurface(
                session: session,
                previewModel: previewModel,
                atlas: atlas,
                mapSize: mapSize
            )

            if showDayBanner {
                PlaytestDayBanner(
                    day: session.turn,
                    army: session.activeArmy,
                    tileset: session.map.tileset
                )
                .id(dayBannerSequence)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    )
                )
                .zIndex(1)
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PlaytestDayBanner: View {
    let day: Int
    let army: Int
    let tileset: Tileset

    private var armyColor: Color {
        if tileset == .gbWars {
            switch army {
            case AWConstants.armyOrangeStar:
                return Color(red: 0.78, green: 0.12, blue: 0.12)
            case AWConstants.armyBlueMoon:
                return Color(white: 0.82)
            default:
                break
            }
        }

        switch army {
        case AWConstants.armyOrangeStar:
            return Color(red: 0.94, green: 0.40, blue: 0.12)
        case AWConstants.armyBlueMoon:
            return Color(red: 0.18, green: 0.47, blue: 0.86)
        case AWConstants.armyGreenEarth:
            return Color(red: 0.22, green: 0.62, blue: 0.27)
        case AWConstants.armyYellowComet:
            return Color(red: 0.92, green: 0.70, blue: 0.08)
        case AWConstants.armyBlackHole:
            return Color(red: 0.48, green: 0.30, blue: 0.72)
        default:
            return .secondary
        }
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.thinMaterial)

            Rectangle()
                .fill(
                    RadialGradient(
                        colors: [
                            armyColor.opacity(0.25),
                            armyColor.opacity(0.08)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 420
                    )
                )

            Text("Day \(day)")
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: armyColor.opacity(0.35), radius: 8, y: 2)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.40), value: day)
        }
        .frame(maxWidth: .infinity, minHeight: 68, maxHeight: 68)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(armyColor.opacity(0.25))
                .frame(height: 4)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(armyColor.opacity(0.25))
                .frame(height: 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Day \(day)")
    }
}

private struct PlaytestMapSurface: View {
    let session: PlaytestSession
    let previewModel: EditorModel
    let atlas: SpriteAtlas
    let mapSize: CGSize

    var body: some View {
        let tileSize = MapCanvasMetrics.tileSize
        let boardSize = CGSize(
            width: mapSize.width + (MapCanvasMetrics.woodPadding * 2),
            height: mapSize.height + (MapCanvasMetrics.woodPadding * 2) + MapCanvasMetrics.bottomWallHeight
        )
        let minimumContentSize = CGSize(
            width: boardSize.width + (MapCanvasMetrics.parchmentPadding * 2),
            height: boardSize.height + (MapCanvasMetrics.parchmentPadding * 2)
        )

        GeometryReader { proxy in
            let contentSize = CGSize(
                width: max(proxy.size.width, minimumContentSize.width),
                height: max(proxy.size.height, minimumContentSize.height)
            )
            let boardOrigin = CGPoint(
                x: (contentSize.width - minimumContentSize.width) / 2,
                y: (contentSize.height - minimumContentSize.height) / 2
            )

            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    MapParchmentSurface(tileSize: tileSize, mapSize: mapSize)

                    MapCanvasBoard(
                        model: previewModel,
                        atlas: atlas,
                        interactionEnabled: false
                    )
                        .offset(
                            x: boardOrigin.x + MapCanvasMetrics.parchmentPadding,
                            y: boardOrigin.y + MapCanvasMetrics.parchmentPadding
                        )
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)

                    PlaytestWeatherOverlay(
                        weather: session.weather,
                        mapSize: mapSize
                    )
                        .frame(width: mapSize.width, height: mapSize.height)
                        .offset(
                            x: boardOrigin.x + MapCanvasMetrics.parchmentPadding + MapCanvasMetrics.woodPadding,
                            y: boardOrigin.y + MapCanvasMetrics.parchmentPadding + MapCanvasMetrics.woodPadding
                        )

                    PlaytestInteractionLayer(
                        session: session,
                        previewModel: previewModel,
                        tileSize: tileSize
                    )
                        .frame(width: mapSize.width, height: mapSize.height)
                        .offset(
                            x: boardOrigin.x + MapCanvasMetrics.parchmentPadding + MapCanvasMetrics.woodPadding,
                            y: boardOrigin.y + MapCanvasMetrics.parchmentPadding + MapCanvasMetrics.woodPadding
                        )
                }
                .frame(width: contentSize.width, height: contentSize.height)
            }
            .background {
                MapParchmentSurface(tileSize: tileSize, mapSize: mapSize)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Receives secondary clicks without replacing the SwiftUI primary-tap
/// gesture. The editor uses the same local-monitor approach for its map
/// canvas, which also lets us suppress the default context menu here.
private struct PlaytestMapInput: NSViewRepresentable {
    let session: PlaytestSession
    let previewModel: EditorModel
    let tileSize: CGFloat

    func makeNSView(context: Context) -> MonitorView {
        MonitorView(session: session, previewModel: previewModel, tileSize: tileSize)
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.session = session
        nsView.previewModel = previewModel
        nsView.tileSize = tileSize
    }

    @MainActor
    final class MonitorView: NSView {
        var session: PlaytestSession
        var previewModel: EditorModel
        var tileSize: CGFloat
        private var eventMonitor: Any?

        init(session: PlaytestSession, previewModel: EditorModel, tileSize: CGFloat) {
            self.session = session
            self.previewModel = previewModel
            self.tileSize = tileSize
            super.init(frame: .zero)
            wantsLayer = false
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeEventMonitor()
            guard window != nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.rightMouseDown, .otherMouseDown]
            ) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        isolated deinit { removeEventMonitor() }

        private func removeEventMonitor() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let window, event.window === window else { return event }
            let location = convert(event.locationInWindow, from: nil)
            guard bounds.contains(location) else { return event }
            guard event.type == .rightMouseDown || event.buttonNumber == 2 else { return event }

            let y = Int(floor((bounds.height - location.y) / tileSize))
            let rowOffset = session.isStaggeredGrid && y % 2 != 0 ? tileSize / 2 : 0
            let point = GridPoint(
                x: Int(floor((location.x - rowOffset) / tileSize)),
                y: y
            )
            previewModel.updatePointer(point)
            session.handleSecondaryTap(point)
            return nil
        }
    }
}

private struct PlaytestInteractionLayer: View {
    let session: PlaytestSession
    let previewModel: EditorModel
    let tileSize: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isDragging = false
    @State private var movedDuringDrag = false

    var body: some View {
        Canvas { context, _ in
            let movementGlass = Color(red: 0.10, green: 0.52, blue: 1.0)
            let attackGlass = Color(red: 1.0, green: 0.16, blue: 0.20)
            let captureFill = Color.yellow.opacity(reduceTransparency ? 0.12 : 0.28)
            let captureStroke = Color.yellow.opacity(reduceTransparency ? 0.50 : 0.90)
            let loadFill = Color.cyan.opacity(reduceTransparency ? 0.10 : 0.18)
            let loadStroke = Color.cyan.opacity(reduceTransparency ? 0.42 : 0.80)
            let unloadFill = Color.orange.opacity(reduceTransparency ? 0.10 : 0.18)
            let unloadStroke = Color.orange.opacity(reduceTransparency ? 0.42 : 0.80)
            let refuelFill = Color.green.opacity(reduceTransparency ? 0.10 : 0.18)
            let refuelStroke = Color.green.opacity(reduceTransparency ? 0.42 : 0.80)
            let joinFill = Color.mint.opacity(reduceTransparency ? 0.08 : 0.16)
            let joinStroke = Color.mint.opacity(reduceTransparency ? 0.40 : 0.75)
            let siloFill = Color.purple.opacity(reduceTransparency ? 0.08 : 0.16)
            let siloStroke = Color.purple.opacity(reduceTransparency ? 0.40 : 0.75)

            drawFogOverlay(context: &context)

            // Blue-glass reachable cells are a player affordance. CPU turns
            // keep only the current-unit marker below so the AI's planning
            // does not look like a set of destinations the player can tap.
            if !session.activeArmyIsCPU {
                for point in session.reachableCells {
                    drawGlassTile(point, base: movementGlass, context: &context)
                }
            }
            for point in session.attackableCells {
                drawGlassTile(point, base: attackGlass, context: &context)
            }
            for point in session.attackPreviewCells {
                drawGlassTile(point, base: attackGlass, context: &context)
            }
            for point in session.captureableCells {
                drawTile(point, fill: captureFill, stroke: captureStroke, context: &context)
            }
            for point in session.loadableCells {
                drawTile(point, fill: loadFill, stroke: loadStroke, context: &context)
            }
            for point in session.joinableCells {
                drawTile(point, fill: joinFill, stroke: joinStroke, context: &context)
            }
            for point in session.unloadableCells {
                drawTile(point, fill: unloadFill, stroke: unloadStroke, context: &context)
            }
            for point in session.refuelableCells {
                drawTile(point, fill: refuelFill, stroke: refuelStroke, context: &context)
            }
            for point in session.siloTargetCells {
                drawTile(point, fill: siloFill, stroke: siloStroke, context: &context)
            }

            drawUnitState(context: &context)
            drawMovementPath(session.cpuMovementPath, context: &context)
            drawMovementPath(session.playerMovementPath, context: &context)
            drawTransportMarkers(context: &context)

            if let attackPreviewOrigin = session.attackPreviewOrigin {
                context.stroke(
                    tilePath(for: attackPreviewOrigin, inset: 0.5),
                    with: .color(Color.white.opacity(0.85)),
                    style: StrokeStyle(lineWidth: 2)
                )
                context.stroke(
                    tilePath(for: attackPreviewOrigin, inset: 2.5),
                    with: .color(attackGlass.opacity(0.9)),
                    style: StrokeStyle(lineWidth: 1)
                )
            }

            if let selectedPoint = session.selectedPoint, !session.activeArmyIsCPU {
                context.stroke(tilePath(for: selectedPoint, inset: 0.5), with: .color(.white.opacity(0.95)), style: StrokeStyle(lineWidth: 2))
                context.stroke(tilePath(for: selectedPoint, inset: 2.5), with: .color(Color.accentColor), style: StrokeStyle(lineWidth: 1))
            }
        }
        .contentShape(Rectangle())
        .gesture(pointerGesture)
        .background {
            PlaytestMapInput(session: session, previewModel: previewModel, tileSize: tileSize)
                .allowsHitTesting(false)
        }
        .accessibilityElement()
        .accessibilityLabel("Playtest map")
        .accessibilityValue(session.statusMessage)
        .accessibilityHint("Select a unit, drag across blue movement tiles to plan a route, release to move, choose a highlighted destination or target, or right-click a unit to preview its attacks. Use the inspector for capture, refueling, depth, missile silos, and production actions.")
        .accessibilityAddTraits(.isButton)
    }

    private var pointerGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let point = cell(for: value.location)
                if !isDragging {
                    isDragging = true
                    movedDuringDrag = false
                }

                previewModel.updatePointer(point)
                if session.updatePlayerMovementPreview(to: point) {
                    movedDuringDrag = true
                }
            }
            .onEnded { value in
                let point = cell(for: value.location)
                previewModel.updatePointer(point)

                if movedDuringDrag {
                    _ = session.commitPlayerMovementPreview(at: point)
                } else {
                    session.clearPlayerMovementPreview()
                    session.handleTap(point)
                }

                isDragging = false
                movedDuringDrag = false
            }
    }

    private func cell(for location: CGPoint) -> GridPoint {
        let y = Int(floor(location.y / tileSize))
        let rowOffset = session.isStaggeredGrid && y % 2 != 0 ? tileSize / 2 : 0
        return GridPoint(
            x: Int(floor((location.x - rowOffset) / tileSize)),
            y: y
        )
    }

    private func tileRect(for point: GridPoint, inset: CGFloat) -> CGRect {
        MapCanvasMetrics.tileRect(
            x: point.x,
            y: point.y,
            tileSize: tileSize,
            staggered: session.isStaggeredGrid,
            inset: inset
        )
    }

    private func tilePath(for point: GridPoint, inset: CGFloat) -> Path {
        MapCanvasMetrics.tilePath(
            in: tileRect(for: point, inset: inset),
            staggered: session.isStaggeredGrid
        )
    }

    private func drawTile(_ point: GridPoint, fill: Color, stroke: Color, context: inout GraphicsContext) {
        let rect = tileRect(for: point, inset: 1)
        let path = MapCanvasMetrics.tilePath(in: rect, staggered: session.isStaggeredGrid)
        context.fill(path, with: .color(fill))
        context.stroke(path, with: .color(stroke), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
    }

    private func drawGlassTile(_ point: GridPoint, base: Color, context: inout GraphicsContext) {
        let rect = tileRect(for: point, inset: 1)
        let fillOpacity = reduceTransparency ? 0.56 : 0.30
        let edgeOpacity = reduceTransparency ? 0.72 : 0.48
        let innerOpacity = reduceTransparency ? 0.86 : 0.66
        let path = tilePath(for: point, inset: 1)
        let innerPath = tilePath(for: point, inset: 2.5)

        context.fill(
            path,
            with: .linearGradient(
                Gradient(colors: [
                    Color.white.opacity(reduceTransparency ? 0.24 : 0.16),
                    base.opacity(fillOpacity),
                    base.opacity(fillOpacity * 0.58)
                ]),
                startPoint: CGPoint(x: rect.midX, y: rect.minY),
                endPoint: CGPoint(x: rect.midX, y: rect.maxY)
            )
        )
        context.stroke(
            path,
            with: .color(base.opacity(edgeOpacity)),
            style: StrokeStyle(lineWidth: 1)
        )
        context.stroke(
            innerPath,
            with: .color(base.opacity(innerOpacity)),
            style: StrokeStyle(lineWidth: 1)
        )
    }

    private func drawFogOverlay(context: inout GraphicsContext) {
        guard session.isFogOfWarActive else { return }

        // Keep the map's terrain texture just perceptible through the veil,
        // while making hidden units and properties unreadable. A stronger,
        // nearly opaque treatment is used when transparency is reduced so
        // the hidden-state distinction remains clear without relying on
        // translucency.
        let fogColor = Color(red: 0.11, green: 0.05, blue: 0.17)
            .opacity(reduceTransparency ? 0.94 : 0.86)

        for x in 0..<session.map.width {
            for y in 0..<session.map.height {
                let point = GridPoint(x: x, y: y)
                guard !session.isVisible(point) else { continue }
                context.fill(tilePath(for: point, inset: 0), with: .color(fogColor))
            }
        }
    }

    private func drawUnitState(context: inout GraphicsContext) {
        for x in 0..<session.map.width {
            for y in 0..<session.map.height {
                let point = GridPoint(x: x, y: y)
                let unit = session.map.foregroundElement(atX: x, y: y)
                guard unit.isUnitNonEmpty, session.isVisible(point) else { continue }

                let rect = tileRect(for: point, inset: 0)
                let isCurrentCPUMovement = session.activeArmyIsCPU
                    && session.isCPUMovementAnimating
                    && session.cpuMovementPath.last == point
                if session.movedCells.contains(point), unit.army == session.activeArmy, !isCurrentCPUMovement {
                    context.fill(
                        tilePath(for: point, inset: 0),
                        with: .color(Color.black.opacity(reduceTransparency ? 0.18 : 0.30))
                    )
                }

                let health = session.unitHealth[point, default: 100]
                // Advance Wars renders the unit's health as whole tens. Keep
                // damaged units at a visible 1 rather than letting a nearly
                // destroyed unit disappear from the badge entirely.
                let displayHealth = max(1, min(10, health / 10))
                guard displayHealth < 10 else { continue }
                let badgeRect = CGRect(
                    x: rect.minX + 2,
                    y: rect.maxY - 13,
                    width: 14,
                    height: 11
                )
                context.fill(
                    Path(roundedRect: badgeRect, cornerRadius: 2),
                    with: .color(Color.black.opacity(reduceTransparency ? 0.62 : 0.78))
                )

                let text = context.resolve(
                    Text("\(displayHealth)")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                )
                context.draw(text, at: CGPoint(x: badgeRect.midX, y: badgeRect.midY), anchor: .center)
            }
        }
    }

    /// Draws a planned route as a strict cardinal path through tile centres.
    /// The final segment receives an arrowhead, keeping both CPU routes and
    /// player drag previews tile-bound instead of turning into a free-form
    /// cursor marker.
    private func drawMovementPath(_ points: [GridPoint], context: inout GraphicsContext) {
        guard points.count > 1 else { return }

        let centers = points.map { point in
            let rect = tileRect(for: point, inset: 0)
            return CGPoint(x: rect.midX, y: rect.midY)
        }

        var shaft = Path()
        shaft.move(to: centers[0])
        for center in centers.dropFirst() {
            shaft.addLine(to: center)
        }

        let orange = Color.orange.opacity(0.88)
        context.stroke(
            shaft,
            with: .color(Color.black.opacity(0.20)),
            style: StrokeStyle(
                lineWidth: max(7, tileSize * 0.28),
                lineCap: .round,
                lineJoin: .round
            )
        )
        context.stroke(
            shaft,
            with: .color(orange),
            style: StrokeStyle(
                lineWidth: max(4, tileSize * 0.17),
                lineCap: .round,
                lineJoin: .round
            )
        )

        guard let previous = centers.dropLast().last,
              let tip = centers.last else { return }
        let direction = CGPoint(x: tip.x - previous.x, y: tip.y - previous.y)
        let length = hypot(direction.x, direction.y)
        guard length > 0 else { return }

        let unit = CGPoint(x: direction.x / length, y: direction.y / length)
        let perpendicular = CGPoint(x: -unit.y, y: unit.x)
        let headLength = min(tileSize * 0.46, length * 0.65)
        let headWidth = min(tileSize * 0.34, headLength * 0.82)
        let base = CGPoint(
            x: tip.x - unit.x * headLength,
            y: tip.y - unit.y * headLength
        )
        let left = CGPoint(
            x: base.x + perpendicular.x * headWidth,
            y: base.y + perpendicular.y * headWidth
        )
        let right = CGPoint(
            x: base.x - perpendicular.x * headWidth,
            y: base.y - perpendicular.y * headWidth
        )

        var head = Path()
        head.move(to: tip)
        head.addLine(to: left)
        head.addLine(to: right)
        head.closeSubpath()
        context.fill(head, with: .color(orange))
    }

    private func drawTransportMarkers(context: inout GraphicsContext) {
        for point in session.loadableCells {
            drawMarker("↓", at: point, color: .cyan, context: &context)
        }
        for point in session.joinableCells {
            drawMarker("+", at: point, color: .mint, context: &context)
        }
        for point in session.unloadableCells {
            drawMarker("↑", at: point, color: .orange, context: &context)
        }
        for point in session.refuelableCells {
            drawMarker("+", at: point, color: .green, context: &context)
        }
        if let selectedPoint = session.selectedPoint, session.selectedCargoCount > 0 {
            drawMarker("↑", at: selectedPoint, color: .orange, context: &context, corner: .topTrailing)
        }
    }

    private func drawMarker(
        _ symbol: String,
        at point: GridPoint,
        color: Color,
        context: inout GraphicsContext,
        corner: UnitPoint = .center
    ) {
        let rect = tileRect(for: point, inset: 0)
        let position: CGPoint
        switch corner {
        case .topTrailing:
            position = CGPoint(x: rect.maxX - 8, y: rect.minY + 8)
        default:
            position = CGPoint(x: rect.midX, y: rect.midY)
        }
        let text = context.resolve(
            Text(symbol)
                .font(.system(size: corner == .center ? 14 : 11, weight: .black, design: .rounded))
                .foregroundStyle(color)
        )
        context.draw(text, at: position, anchor: .center)
    }
}

private struct PlaytestInspector: View {
    let session: PlaytestSession

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let selectedUnitName = session.selectedUnitName {
                        VStack(alignment: .leading, spacing: 7) {
                        Text("Selected unit")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(selectedUnitName)
                            .font(.headline)
                        if let health = session.selectedUnitHealth {
                            GLWNProgressBar(
                                value: Double(health),
                                total: 100,
                                tint: health > 50 ? .green : .orange
                            )
                            Text("Health \(health)%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if let fuel = session.selectedUnitFuel {
                            GLWNProgressBar(
                                value: Double(fuel),
                                total: Double(session.selectedUnitMaxFuel ?? 100),
                                tint: fuel > 25 ? .blue : .orange
                            )
                            Text("\(session.selectedUnitResourceLabel ?? "Fuel") \(fuel)/\(session.selectedUnitMaxFuel ?? 100)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if let ammo = session.selectedUnitAmmo {
                            Text("Primary ammo \(ammo)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if session.selectedUnitIsSubmarine,
                           session.ruleset == .advanceWars || session.ruleset == .advanceWars2 || session.ruleset == .dualStrike {
                            Label(
                                session.selectedSubmarineIsSubmerged ? "Submerged" : "Surfaced",
                                systemImage: session.selectedSubmarineIsSubmerged ? "arrow.down.circle.fill" : "water.waves"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        }
                        if let capacity = session.selectedTransportCapacity {
                            Label("Cargo \(session.selectedCargoCount)/\(capacity)", systemImage: "shippingbox.fill")
                                .font(.caption)
                            if let cargo = session.selectedCargoSummary {
                                Text(cargo)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            HStack(spacing: 10) {
                                if !session.loadableCells.isEmpty {
                                    Label("Load", systemImage: "arrow.down.circle.fill")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.cyan)
                                }
                                if !session.unloadableCells.isEmpty {
                                    Label("Unload", systemImage: "arrow.up.circle.fill")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        if session.selectedTransportCanResupply {
                            if session.selectedTransportIsBlackBoat {
                                ForEach(
                                    Array(session.refuelableCells).sorted {
                                        $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y
                                    },
                                    id: \.self
                                ) { point in
                                    Button(
                                        "Repair \(session.unitName(at: point) ?? "unit")",
                                        systemImage: "cross.case.fill"
                                    ) {
                                        session.resupplySelectedTransport(target: point)
                                    }
                                    .buttonStyle(GLWNInContentButtonStyle(tone: .accent, horizontalPadding: 10, minHeight: 32))
                                }
                            } else {
                                Button("Resupply adjacent units", systemImage: "fuelpump.fill") {
                                    session.resupplySelectedTransport()
                                }
                                .buttonStyle(GLWNInContentButtonStyle(tone: .accent, horizontalPadding: 10, minHeight: 32))
                            }
                        }
                        if session.selectedUnitCanLaunchSilo {
                            Button("Launch Missile Silo", systemImage: "scope", action: session.beginSiloLaunch)
                                .buttonStyle(GLWNInContentButtonStyle(tone: .accent, horizontalPadding: 10, minHeight: 32))
                        }
                        if let progress = session.selectedCaptureProgress {
                            Text(progress)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            if session.selectedUnitIsSubmarine,
                               session.ruleset == .advanceWars || session.ruleset == .advanceWars2 || session.ruleset == .dualStrike {
                                Button(
                                    session.selectedSubmarineIsSubmerged ? "Surface" : "Dive",
                                    systemImage: session.selectedSubmarineIsSubmerged ? "arrow.up.circle.fill" : "arrow.down.circle.fill",
                                    action: session.toggleSubmerge
                                )
                                .buttonStyle(GLWNInContentButtonStyle(tone: .neutral, horizontalPadding: 10, minHeight: 32))
                            }
                            if session.captureableCells.contains(where: { $0 == session.selectedPoint }) {
                                Button("Capture", systemImage: "flag.fill", action: session.capture)
                                    .buttonStyle(GLWNInContentButtonStyle(tone: .accent, horizontalPadding: 10, minHeight: 32))
                            }
                            Button("Wait", systemImage: "pause.fill", action: session.wait)
                                .buttonStyle(GLWNInContentButtonStyle(tone: .neutral, horizontalPadding: 10, minHeight: 32))
                        }
                        }
                    } else if let selectedBuildingName = session.selectedBuildingName {
                        VStack(alignment: .leading, spacing: 8) {
                        Text("Selected property")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(selectedBuildingName)
                            .font(.headline)
                        if let owner = session.selectedBuildingOwnerName {
                            Text("Owner: \(owner)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !session.productionOptions.isEmpty {
                            Text("Build unit")
                                .font(.subheadline.weight(.semibold))
                            ForEach(session.productionOptions) { option in
                                Button {
                                    session.buildUnit(option)
                                } label: {
                                    HStack(spacing: 8) {
                                        Text(option.label)
                                        Spacer(minLength: 8)
                                        Text(PlaytestRulebook.formatFunds(option.cost))
                                            .font(.caption.monospacedDigit())
                                    }
                                }
                                .buttonStyle(GLWNInContentButtonStyle(tone: .neutral, horizontalPadding: 10, minHeight: 32))
                                .disabled(!session.canBuild(option))
                            }
                        }
                        }
                    }
                }
                .padding(18)
            }

            Divider()

            PlaytestSidebarStatus(session: session)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PlaytestSidebarStatus: View {
    let session: PlaytestSession

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Active side")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Label("Day \(session.turn)", systemImage: "calendar.day")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("\(session.activeArmyName)'s turn", systemImage: "flag.fill")
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Label(
                    session.activeArmyIsCPU ? "CPU" : "Player",
                    systemImage: session.activeArmyIsCPU ? "cpu" : "person.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(session.activeArmyIsCPU ? .orange : .secondary)
                .help(session.activeArmyIsCPU ? "This army is controlled by the CPU." : "\(session.activeArmyName) is controlled by you.")
            }

            Label(PlaytestRulebook.formatFunds(session.activeFunds), systemImage: "banknote")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Available funds \(PlaytestRulebook.formatFunds(session.activeFunds))")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Playtest status")
    }
}
