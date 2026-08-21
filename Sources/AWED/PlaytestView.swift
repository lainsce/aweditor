import AppKit
import Observation
import SwiftUI
import AWEDCore

struct PlaytestLaunch: Identifiable {
    let id = UUID()
    let map: MapState
}

@MainActor
@Observable
final class PlaytestSession {
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

    let sourceMap: MapState
    let ruleset: PlaytestRuleset

    var map: MapState
    var activeArmy: Int
    var turn = 1
    var weather: PlaytestWeather = .clear
    var fogOfWarEnabled = false
    var selectedPoint: GridPoint?
    var reachableCells: Set<GridPoint> = []
    var attackableCells: Set<GridPoint> = []
    var attackPreviewOrigin: GridPoint?
    var attackPreviewCells: Set<GridPoint> = []
    var cpuMovementOrigin: GridPoint?
    var cpuMovementCells: Set<GridPoint> = []
    var captureableCells: Set<GridPoint> = []
    fileprivate var productionOptions: [PlaytestProductionOption] = []
    var movedCells: Set<GridPoint> = []
    var funds: [Int: Int]
    var unitHealth: [GridPoint: Int] = [:]
    /// Infantry and Mech display this resource as rations. AW2 supplies
    /// cartridge-accurate per-unit fuel capacities through the rules layer.
    var unitFuel: [GridPoint: Int] = [:]
    var unitAmmo: [GridPoint: Int] = [:]
    var submergedUnits: Set<GridPoint> = []
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
    private var usedMissileSilos: Set<GridPoint> = []
    private var isSelectingSiloTarget = false
    private var isExecutingCPU = false
    @ObservationIgnored private var cpuTask: Task<Void, Never>?
    @ObservationIgnored private var cpuRunID = UUID()

    init(map: MapState) {
        sourceMap = map
        self.map = map
        ruleset = map.tileset.playtestRuleset
        armies = Self.armies(in: map)
        let initialArmy = armies.first ?? AWConstants.armyOrangeStar
        activeArmy = initialArmy
        funds = Dictionary(uniqueKeysWithValues: armies.map { ($0, 10_000) })
        statusMessage = armies.isEmpty
            ? "No playable armies are placed on this map yet."
            : "Select a \(Self.armyName(initialArmy)) unit to begin."
        initializeUnitResources()
        _ = processTurnStart(for: initialArmy)
        _ = resolveRouting()
        runCPUIfNeeded()
    }

    var activeArmyName: String { Self.armyName(activeArmy) }
    var activeArmyIsCPU: Bool { isCPUArmy(activeArmy) }
    var activeFunds: Int { funds[activeArmy, default: 0] }
    var isGameOver: Bool { winnerArmy != nil || survivingArmies.isEmpty }

    private var survivingArmies: [Int] {
        armies.filter { !defeatedArmies.contains($0) }
    }

    var selectedUnitName: String? {
        guard let selectedPoint, let unit = unit(at: selectedPoint) else { return nil }
        return PaletteCatalog.label(for: unit)
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
        guard ruleset == .advanceWars2,
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
        guard fogOfWarEnabled || !submergedUnits.isEmpty else { return map }
        var result = map
        for x in 0..<map.width {
            for y in 0..<map.height {
                let point = GridPoint(x: x, y: y)
                let unit = map.foregroundElement(atX: x, y: y)
                if unit.isUnitNonEmpty, unit.army != activeArmy,
                   (fogOfWarEnabled || submergedUnits.contains(point)), !isVisible(point) {
                    _ = result.setForeground(.unitEmpty, atX: x, y: y)
                }

                let building = map.backgroundElement(atX: x, y: y)
                if fogOfWarEnabled, building.isBuilding, building.army != activeArmy, !isVisible(point) {
                    _ = result.setBackground(building.changedArmy(AWConstants.armyNeutral), atX: x, y: y, check: false)
                }
            }
        }
        return result
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
        return loaded.map { PaletteCatalog.label(for: $0.unit) }.joined(separator: ", ")
    }

    var selectedAPCCanRefuel: Bool {
        guard let selectedPoint,
              let unit = unit(at: selectedPoint),
              unit.simplified == .unitAPC else { return false }
        return !refuelableCells.isEmpty
    }

    var selectedBuildingName: String? {
        guard let selectedPoint,
              map.foregroundElement(atX: selectedPoint.x, y: selectedPoint.y) == .unitEmpty else { return nil }
        let building = map.backgroundElement(atX: selectedPoint.x, y: selectedPoint.y)
        return building.isBuilding ? PaletteCatalog.label(for: building) : nil
    }

    var selectedBuildingOwnerName: String? {
        guard let selectedPoint else { return nil }
        let building = map.backgroundElement(atX: selectedPoint.x, y: selectedPoint.y)
        guard building.isBuilding else { return nil }
        return Self.armyName(building.army)
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
        weather = .clear
        fogOfWarEnabled = false
        funds = Dictionary(uniqueKeysWithValues: armies.map { ($0, 10_000) })
        initializeUnitResources()
        captureProgress.removeAll()
        cargo.removeAll()
        submergedUnits.removeAll()
        usedMissileSilos.removeAll()
        isSelectingSiloTarget = false
        siloTargetCells.removeAll()
        winnerArmy = nil
        defeatedArmies.removeAll()
        movedCells.removeAll()
        cpuMovementOrigin = nil
        cpuMovementCells.removeAll()
        clearSelection()
        statusMessage = armies.isEmpty
            ? "No playable armies are placed on this map yet."
            : "Select a \(Self.armyName(activeArmy)) unit to begin."
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
                statusMessage = (fogOfWarEnabled || submergedUnits.contains(point)) && !isVisible(point)
                    ? "No enemy unit is visible at that space."
                    : "That unit belongs to \(Self.armyName(unit.army))."
                return
            }
            guard PlaytestRulebook.stats(for: unit, ruleset: ruleset) != nil else {
                clearSelection()
                statusMessage = "\(PaletteCatalog.label(for: unit)) is not available in \(ruleset.displayName)."
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
                statusMessage = (fogOfWarEnabled || submergedUnits.contains(point)) && !isVisible(point)
                    ? "That property is outside friendly vision."
                    : "That property belongs to \(Self.armyName(building.army))."
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
              (!fogOfWarEnabled || unit.army == activeArmy || isVisible(point)) else {
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
        if nextIndex <= currentIndex { turn += 1 }
        activeArmy = nextArmy
        movedCells.removeAll()
        clearSelection()
        let fuelLossCount = processTurnStart(for: activeArmy)
        let startRoutedArmies = resolveRouting()
        guard winnerArmy == nil else { return }
        let routedDuringTransition = Array(Set(routedArmies + startRoutedArmies)).sorted()
        let startMessage = "\(Self.armyName(activeArmy))'s turn. Select a unit or property to begin."
        let supplyMessage = fuelLossCount > 0
            ? " \(fuelLossCount) air/naval unit(s) were lost to fuel exhaustion."
            : ""
        if routedDuringTransition.isEmpty {
            statusMessage = startMessage + supplyMessage
        } else {
            statusMessage = startMessage + supplyMessage + " " + routedDuringTransition.map(Self.armyName).joined(separator: ", ") + " was routed and its properties became neutral."
        }
        runCPUIfNeeded()
    }

    func capture() {
        guard let point = selectedPoint,
              let unit = unit(at: point),
              let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset),
              stats.canCapture else {
            statusMessage = "Only Infantry and Mech units can capture properties."
            return
        }

        let building = map.backgroundElement(atX: point.x, y: point.y)
        guard PlaytestRulebook.isCapturableBuilding(building, ruleset: ruleset), building.army != activeArmy else {
            statusMessage = "There is no enemy or neutral property to capture here."
            return
        }

        let progress = captureProgress[point, default: 0] + max(1, unitHealth[point, default: 100] / 10)
        movedCells.insert(point)
        if progress < 20 {
            captureProgress[point] = progress
            clearSelection()
            statusMessage = "Capturing \(PaletteCatalog.label(for: building)): \(progress)/20. Continue next turn."
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
                statusMessage = "\(Self.armyName(defeatedArmy))'s HQ was captured; its properties became neutral."
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
        statusMessage = "\(activeArmyName) captured \(PaletteCatalog.label(for: captured))."
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
              PlaytestRulebook.productionOptions(for: building, ruleset: ruleset).contains(where: { $0.id == option.id }) else { return false }
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
        statusMessage = "Built \(option.label) for $\(option.cost.formatted()). It cannot move this turn."
    }

    private func selectUnit(at point: GridPoint) {
        guard let unit = unit(at: point), let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset) else { return }
        selectedPoint = point
        productionOptions.removeAll()
        captureableCells = canCapture(unit: unit, stats: stats, at: point) ? [point] : []
        reachableCells = movedCells.contains(point) ? [] : movementCells(from: point, unit: unit, stats: stats)
        attackableCells = attackableCells(from: point, unit: unit)
        updateTransportActions(for: unit, at: point)
        if movedCells.contains(point) {
            statusMessage = "Choose an enemy in red, load or unload cargo, or capture the property under this unit."
        } else {
            statusMessage = "Move to a blue tile, attack a red target, load or unload cargo, or capture the highlighted property."
        }
    }

    func refreshSelection() {
        guard let selectedPoint,
              let unit = unit(at: selectedPoint) else { return }
        selectUnit(at: selectedPoint)
        if unit.simplified == .unitAPC {
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
        // In AW1, Rain only cuts vision when Fog is active. Snow leaves
        // vision unchanged; AW2 has its own DS weather behavior.
        if ruleset == .advanceWars, fogOfWarEnabled, weather == .rain {
            vision = max(1, vision - 1)
        }
        return vision
    }

    func isVisible(_ point: GridPoint) -> Bool {
        let targetUnit = map.foregroundElement(atX: point.x, y: point.y)
        if targetUnit.isUnitNonEmpty, targetUnit.army == activeArmy { return true }
        // A controlled property is always known at its own coordinate in
        // Fog of War, but it does not provide any surrounding vision.
        let targetBuilding = map.backgroundElement(atX: point.x, y: point.y)
        if targetBuilding.isBuilding, targetBuilding.army == activeArmy { return true }
        let concealedSubmarine = targetUnit.isUnitNonEmpty && targetUnit.simplified == .unitSub && submergedUnits.contains(point)
        guard fogOfWarEnabled || concealedSubmarine else { return true }

        for x in 0..<map.width {
            for y in 0..<map.height {
                let observerPoint = GridPoint(x: x, y: y)
                let observer = map.foregroundElement(atX: x, y: y)
                guard observer.isUnitNonEmpty, observer.army == activeArmy,
                      let observerStats = PlaytestRulebook.stats(for: observer, ruleset: ruleset),
                      let vision = effectiveVision(for: observer, at: observerPoint) else { continue }
                let distance = abs(observerPoint.x - point.x) + abs(observerPoint.y - point.y)
                guard distance <= vision else { continue }

                let targetTerrain = map.backgroundElement(atX: point.x, y: point.y)
                if targetUnit.isUnitNonEmpty {
                    if concealedSubmarine, observer.simplified != .unitCruiser,
                       observer.simplified != .unitSub, distance > 1 {
                        continue
                    }
                    if targetTerrain.simplified == .terrainWood,
                       let targetStats = PlaytestRulebook.stats(for: targetUnit, ruleset: ruleset),
                       targetStats.domain == .land,
                       observerStats.domain != .air,
                       distance > 1 {
                        continue
                    }
                    if targetTerrain.simplified == .terrainReef,
                       let targetStats = PlaytestRulebook.stats(for: targetUnit, ruleset: ruleset),
                       targetStats.domain == .sea,
                       observerStats.domain != .air,
                       distance > 1 {
                        continue
                    }
                }
                return true
            }
        }
        return false
    }

    private func isHiddenEnemy(_ occupant: Element, at point: GridPoint, relativeTo unit: Element) -> Bool {
        guard occupant.isUnitNonEmpty, occupant.army != unit.army else { return false }
        guard fogOfWarEnabled || submergedUnits.contains(point) else { return false }
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
            unitFuel[stop] = max(0, fuel - (paths[stop]?.movement ?? 0))
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
        statusMessage = "Ambush! \(PaletteCatalog.label(for: enemy)) was revealed. The move ends here."
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
        productionOptions = PlaytestRulebook.productionOptions(for: building, ruleset: ruleset)
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
                fuel: max(0, (unitFuel.removeValue(forKey: origin) ?? maxFuel(for: origin)) - path.movement),
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
            statusMessage = "Loaded \(PaletteCatalog.label(for: unit)) into \(PaletteCatalog.label(for: destinationUnit))."
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
        unitFuel[destination] = max(0, fuel - path.movement)
        unitAmmo[destination] = unitAmmo.removeValue(forKey: origin)
        cargo[destination] = cargo.removeValue(forKey: origin)
        if submergedUnits.remove(origin) != nil {
            submergedUnits.insert(destination)
        }
        movedCells.remove(origin)
        movedCells.insert(destination)
        selectedPoint = destination
        reachableCells.removeAll()
        captureableCells = canCapture(unit: unit, stats: stats, at: destination) ? [destination] : []
        attackableCells = stats.canMoveAndFire ? attackableCells(from: destination, unit: unit) : []
        updateTransportActions(for: unit, at: destination)
        productionOptions.removeAll()
        if attackableCells.isEmpty && captureableCells.isEmpty && loadableCells.isEmpty && joinableCells.isEmpty && unloadableCells.isEmpty {
            statusMessage = "\(PaletteCatalog.label(for: unit)) moved. End its action or end the turn."
        } else {
            statusMessage = "Choose an enemy in red, load or unload cargo, capture the highlighted property, or end the action."
        }
    }

    private func attack(to destination: GridPoint) {
        guard let origin = selectedPoint,
              let attacker = unit(at: origin),
              let defender = unit(at: destination),
              let defenderStats = PlaytestRulebook.stats(for: defender, ruleset: ruleset),
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
        statusMessage = "\(PaletteCatalog.label(for: attacker)) dealt \(damage) damage to \(PaletteCatalog.label(for: defender))." + counterattackText
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
                guard nextPath.movement <= stats.move, nextPath.movement <= fuel else { continue }
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

        if transport.simplified == .unitAPC {
            for neighbor in neighbors(of: point) {
                guard isValid(neighbor),
                      let adjacent = self.unit(at: neighbor),
                      adjacent.army == transport.army else { continue }
                let needsFuel = unitFuel[neighbor, default: maxFuel(for: neighbor)] < maxFuel(for: neighbor)
                let needsAmmo = PlaytestRulebook.primaryAmmo(for: adjacent, ruleset: ruleset).map { unitAmmo[neighbor, default: $0] < $0 } ?? false
                guard needsFuel || needsAmmo else { continue }
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
        default:
            return false
        }
    }

    private func loadUnit(from source: GridPoint) {
        guard let transportPoint = selectedPoint,
              let transport = unit(at: transportPoint),
              let loadedUnit = unit(at: source),
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
        statusMessage = "Loaded \(PaletteCatalog.label(for: loadedUnit)) into \(PaletteCatalog.label(for: transport)). The transport may still move."
    }

    private func joinUnit(to destination: GridPoint) {
        guard let origin = selectedPoint,
              let first = unit(at: origin),
              let second = unit(at: destination),
              let firstStats = PlaytestRulebook.stats(for: first, ruleset: ruleset),
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
        let firstFuelAfterMove = max(0, unitFuel[origin, default: maxFuel] - path.movement)
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
        statusMessage = "Joined the two \(PaletteCatalog.label(for: second)) units."
    }

    private func unloadUnit(to destination: GridPoint) {
        guard let transportPoint = selectedPoint,
              let transport = unit(at: transportPoint),
              var loaded = cargo[transportPoint],
              let payload = loaded.first,
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
        statusMessage = "Unloaded \(PaletteCatalog.label(for: payload.unit)) from \(PaletteCatalog.label(for: transport))."
    }

    fileprivate func refuelSelectedAPC() {
        guard let point = selectedPoint,
              let apc = unit(at: point),
              apc.simplified == .unitAPC,
              !refuelableCells.isEmpty else {
            statusMessage = "No adjacent friendly units need fuel."
            return
        }

        let refueledCount = refuelableCells.count
        for neighbor in refuelableCells {
            unitFuel[neighbor] = maxFuel(for: neighbor)
            if let adjacent = unit(at: neighbor),
               let ammo = PlaytestRulebook.primaryAmmo(for: adjacent, ruleset: ruleset) {
                unitAmmo[neighbor] = ammo
            }
        }
        movedCells.insert(point)
        reachableCells.removeAll()
        updateTransportActions(for: apc, at: point)
        statusMessage = "APC resupplied \(refueledCount) adjacent unit(s)."
    }

    private func refuelAdjacentUnits(for army: Int) {
        for x in 0..<map.width {
            for y in 0..<map.height {
                let point = GridPoint(x: x, y: y)
                let transport = map.foregroundElement(atX: x, y: y)
                guard transport.isUnitNonEmpty,
                      transport.army == army,
                      transport.simplified == .unitAPC else { continue }
                for neighbor in neighbors(of: point) {
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

    private func attackableCells(from origin: GridPoint, unit: Element) -> Set<GridPoint> {
        guard let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset), stats.maxRange > 0 else { return [] }
        var result: Set<GridPoint> = []
        for x in 0..<map.width {
            for y in 0..<map.height {
                let point = GridPoint(x: x, y: y)
                let target = map.foregroundElement(atX: x, y: y)
                guard target.isUnitNonEmpty, target.army != unit.army,
                      isVisible(point),
                      (!submergedUnits.contains(point) || unit.simplified == .unitCruiser || unit.simplified == .unitSub),
                      isWithinRange(from: origin, to: point, stats: stats),
                      PlaytestRulebook.canAttack(unit, target, ruleset: ruleset, primaryAmmo: unitAmmo[origin]) else { continue }
                result.insert(point)
            }
        }
        return result
    }

    private func attackRangeCells(from origin: GridPoint, unit: Element) -> Set<GridPoint> {
        guard let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset), stats.maxRange > 0 else { return [] }
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
        let distance = abs(origin.x - destination.x) + abs(origin.y - destination.y)
        return distance >= stats.minRange && distance <= stats.maxRange
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
                if (ruleset == .advanceWars || ruleset == .advanceWars2),
                   unit.simplified == .unitSub, submergedUnits.contains(point) {
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
            statusMessage = "\(Self.armyName(winner)) routed all opponents and wins the playtest."
        } else if survivors.isEmpty {
            statusMessage = "No playable armies remain."
        } else {
            let names = routed.map(Self.armyName).joined(separator: ", ")
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
                if !PlaytestRulebook.productionOptions(for: building, ruleset: ruleset).isEmpty { return true }
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
                    self.cpuMovementOrigin = nil
                    self.cpuMovementCells.removeAll()
                }
            }

            var actionCount = 0
            while self.isCPUArmy(self.activeArmy), !self.isGameOver, actionCount < 400 {
                actionCount += 1
                guard let plan = self.bestCPUPlan() else {
                    self.clearCPUMovementPreview()
                    self.endTurn()
                    continue
                }

                let previousArmy = self.activeArmy
                let previousMoved = self.movedCells
                let previousSelection = self.selectedPoint
                self.prepareCPUMovementPreview(for: plan.action)

                // Yield to SwiftUI so the current enemy unit's movement
                // squares are visible before the CPU commits its action.
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled, self.cpuRunID == runID else { return }

                self.executeCPU(plan.action)
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

        guard let origin = cpuOrigin(for: action),
              let unit = unit(at: origin),
              unit.army == activeArmy,
              let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset),
              !movedCells.contains(origin) else { return }

        cpuMovementOrigin = origin
        cpuMovementCells = movementCells(from: origin, unit: unit, stats: stats)
    }

    private func clearCPUMovementPreview() {
        cpuMovementOrigin = nil
        cpuMovementCells.removeAll()
    }

    private func cpuOrigin(for action: CPUAction) -> GridPoint? {
        switch action {
        case let .attack(origin, _), let .move(origin, _), let .join(origin, _):
            origin
        case let .capture(point), let .resupply(point), let .wait(point):
            point
        case let .load(transport, _), let .unload(transport, _):
            transport
        case .build:
            nil
        }
    }

    private func bestCPUPlan() -> CPUPlan? {
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

    /// A moved unit stays selected so it can attack, capture, load or unload
    /// immediately. Resolve those continuations before considering another
    /// unit, matching the player's normal Advance Wars action flow.
    private func cpuFollowUpPlan() -> CPUPlan? {
        guard let point = selectedPoint,
              let unit = unit(at: point),
              unit.army == activeArmy else { return nil }

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

        if movedCells.contains(point) {
            return CPUPlan(score: -10, action: .wait(point: point))
        }
        return nil
    }

    private func executeCPU(_ action: CPUAction) {
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
            selectUnit(at: origin)
            moveSelectedUnit(to: destination)
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
            if let apc = unit(at: point) {
                updateTransportActions(for: apc, at: point)
            }
            refuelSelectedAPC()
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

    private func cpuUnitPoints() -> [GridPoint] {
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
            for target in attackableCells(from: origin, unit: unit) {
                plans.append(CPUPlan(score: attackScore(from: origin, to: target), action: .attack(origin: origin, target: target)))
            }
        }
        return plans
    }

    private func attackScore(from origin: GridPoint, to target: GridPoint) -> Double {
        let attacker = map.foregroundElement(atX: origin.x, y: origin.y)
        let defender = map.foregroundElement(atX: target.x, y: target.y)
        guard let attackerStats = PlaytestRulebook.stats(for: attacker, ruleset: ruleset),
              let defenderStats = PlaytestRulebook.stats(for: defender, ruleset: ruleset),
              let damage = PlaytestRulebook.damage(
                attacker: attacker,
                defender: defender,
                ruleset: ruleset,
                attackerHealth: unitHealth[origin, default: 100],
                defenderHealth: unitHealth[target, default: 100],
                terrain: map.backgroundElement(atX: target.x, y: target.y),
                primaryAmmo: unitAmmo[origin]
              ) else { return -.greatestFiniteMagnitude }

        let defenderHealth = unitHealth[target, default: 100]
        let distance = abs(origin.x - target.x) + abs(origin.y - target.y)
        let terrainStars = PlaytestRulebook.terrainStars(
            for: map.backgroundElement(atX: target.x, y: target.y),
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
        let threatPenalty = Double(cpuThreat(for: attacker, at: origin)) * 2
        return 100 + lethalBonus + targetValue + damageValue + healthValue - terrainPenalty - distancePenalty - retaliationPenalty - threatPenalty
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
        let healthValue = Double(unitHealth[point, default: 100]) / 5
        return 140 + value + completionBonus + hqBonus + enemyBonus + healthValue
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

            if unitElement.simplified == .unitAPC {
                let needsResupply = neighbors(of: point).contains { neighbor in
                    guard isValid(neighbor), let adjacent = self.unit(at: neighbor), adjacent.army == activeArmy else { return false }
                    let needsFuel = unitFuel[neighbor, default: maxFuel(for: neighbor)] < maxFuel(for: neighbor)
                    let needsAmmo = PlaytestRulebook.primaryAmmo(for: adjacent, ruleset: ruleset).map {
                        unitAmmo[neighbor, default: $0] < $0
                    } ?? false
                    return needsFuel || needsAmmo
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
                      let path = movementPaths(from: point, unit: unitElement, stats: stats)[neighbor],
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

            for option in PlaytestRulebook.productionOptions(for: building, ruleset: ruleset) {
                guard activeFunds >= option.cost,
                      map.allowPlacement(option.element.changedArmy(activeArmy), atX: point.x, y: point.y) else { continue }
                plans.append(CPUPlan(score: cpuBuildScore(option), action: .build(point: point, option: option)))
            }
        }
        return plans
    }

    private func cpuBuildScore(_ option: PlaytestProductionOption) -> Double {
        guard let stats = PlaytestRulebook.stats(for: option.element, ruleset: ruleset) else { return -.greatestFiniteMagnitude }
        let enemyPoints = allEnemyUnitPoints()
        let ownCounts = cpuUnitCounts()
        let enemyDomains = cpuDomainCounts(for: enemyPoints)
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

        // Diminishing returns keep any single unit type from filling every
        // production property, with infantry receiving the strongest repeat
        // penalty because it is the default capture unit.
        score -= Double(existingCount) * (option.element.simplified == .unitInfantry ? 16 : 10)

        // Keep a little cash in reserve for a counterattack or capture follow-
        // up, but permit expensive units when the treasury can support them.
        if Double(option.cost) > Double(activeFunds) * 0.75 { score -= 12 }
        return score
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
            let paths = movementPaths(from: origin, unit: unit, stats: stats)
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
        let before = nearestEnemyDistance(from: origin)
        let after = nearestEnemyDistance(from: destination)
        let distanceGain = before == .max || after == .max ? 0 : before - after
        let terrain = map.backgroundElement(atX: destination.x, y: destination.y)
        let terrainStars = PlaytestRulebook.terrainStars(for: terrain, ruleset: ruleset)
        let threat = cpuThreat(for: unit, at: destination)
        let propertyValue: Double
        let building = map.backgroundElement(atX: destination.x, y: destination.y)
        if let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset),
           stats.canCapture,
           PlaytestRulebook.isCapturableBuilding(building, ruleset: ruleset),
           building.army != activeArmy {
            propertyValue = captureScore(at: destination) / 2
        } else {
            propertyValue = 0
        }

        let attackOpportunity = cpuAdjacentAttackValue(for: unit, at: destination)
        let defensiveValue = Double(terrainStars) * 5
        let movementCost = Double(movement) * 2
        let threatPenalty = Double(threat) * 12
        return 8 + Double(distanceGain) * 12 + propertyValue + attackOpportunity + defensiveValue - movementCost - threatPenalty
    }

    private func cpuWaitPlans() -> [CPUPlan] {
        cpuUnitPoints()
            .filter { !movedCells.contains($0) }
            .map { CPUPlan(score: 0, action: .wait(point: $0)) }
    }

    private func cpuThreat(for unit: Element, at point: GridPoint) -> Int {
        var threat = 0
        for enemyPoint in allEnemyUnitPoints() {
            let enemy = map.foregroundElement(atX: enemyPoint.x, y: enemyPoint.y)
            guard let enemyStats = PlaytestRulebook.stats(for: enemy, ruleset: ruleset),
                  isWithinRange(from: enemyPoint, to: point, stats: enemyStats),
                  PlaytestRulebook.canAttack(enemy, unit, ruleset: ruleset, primaryAmmo: unitAmmo[enemyPoint]) else { continue }
            let cost = PlaytestRulebook.stats(for: unit, ruleset: ruleset)?.cost ?? 0
            let damage = PlaytestRulebook.damage(
                attacker: enemy,
                defender: unit,
                ruleset: ruleset,
                attackerHealth: unitHealth[enemyPoint, default: 100],
                defenderHealth: unitHealth[point, default: 100],
                terrain: map.backgroundElement(atX: point.x, y: point.y),
                primaryAmmo: unitAmmo[enemyPoint]
            ) ?? 0
            threat += max(1, damage + cost / 500)
        }
        return threat
    }

    private func cpuAdjacentAttackValue(for unit: Element, at point: GridPoint) -> Double {
        allEnemyUnitPoints()
            .filter { enemyPoint in
                isWithinRange(from: point, to: enemyPoint, stats: PlaytestRulebook.stats(for: unit, ruleset: ruleset)) &&
                    PlaytestRulebook.canAttack(
                        unit,
                        map.foregroundElement(atX: enemyPoint.x, y: enemyPoint.y),
                        ruleset: ruleset,
                        primaryAmmo: unitAmmo[point]
                    )
            }
            .map { attackScore(from: point, to: $0) }
            .max() ?? 0
    }

    private func cpuDestinationScore(for unit: Element, at point: GridPoint) -> Double {
        let enemyDistance = nearestEnemyDistance(from: point)
        let proximity = enemyDistance == Int.max ? 0 : max(0, 8 - enemyDistance)
        return 20 + Double(proximity) * 3 - Double(cpuThreat(for: unit, at: point)) * 2
    }

    private func allEnemyUnitPoints() -> [GridPoint] {
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

    private func enemyPropertyPoints() -> [GridPoint] {
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
        allEnemyUnitPoints().map { distance(from: point, to: $0) }.min() ?? .max
    }

    private func nearestFriendlyPropertyPoint() -> GridPoint {
        cpuPropertyPoints().first ?? GridPoint(x: 0, y: 0)
    }

    private func distance(from first: GridPoint, to second: GridPoint) -> Int {
        abs(first.x - second.x) + abs(first.y - second.y)
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
        [
            GridPoint(x: point.x - 1, y: point.y), GridPoint(x: point.x + 1, y: point.y),
            GridPoint(x: point.x, y: point.y - 1), GridPoint(x: point.x, y: point.y + 1)
        ]
    }

    private func clearSelection() {
        selectedPoint = nil
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

    private func maxFuel(for point: GridPoint) -> Int {
        guard let unit = unit(at: point) else { return 100 }
        return PlaytestRulebook.maxFuel(for: unit, ruleset: ruleset)
    }

    private static func armies(in map: MapState) -> [Int] {
        var found = Set<Int>()
        let armyLimit = map.tileset == .aw1 ? 4 : AWConstants.playableArmies
        for x in 0..<map.width {
            for y in 0..<map.height {
                let unit = map.foregroundElement(atX: x, y: y)
                let building = map.backgroundElement(atX: x, y: y)
                if unit.isUnitNonEmpty, (0..<armyLimit).contains(unit.army) { found.insert(unit.army) }
                if building.isBuilding, (0..<armyLimit).contains(building.army) { found.insert(building.army) }
            }
        }
        return found.sorted()
    }

    private static func armyName(_ army: Int) -> String {
        switch army {
        case AWConstants.armyOrangeStar: "Orange Star"
        case AWConstants.armyBlueMoon: "Blue Moon"
        case AWConstants.armyGreenEarth: "Green Earth"
        case AWConstants.armyYellowComet: "Gold Comet"
        case AWConstants.armyBlackHole: "Black Hole"
        default: "Neutral"
        }
    }
}

struct PlaytestView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var session: PlaytestSession
    @State private var previewModel: EditorModel

    let atlas: SpriteAtlas

    init(map: MapState, atlas: SpriteAtlas) {
        let session = PlaytestSession(map: map)
        _session = State(initialValue: session)
        _previewModel = State(initialValue: EditorModel(map: map))
        self.atlas = atlas
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
                PlaytestMapSurface(session: session, previewModel: previewModel, atlas: atlas)
                Divider()
                PlaytestInspector(session: session)
                    .frame(width: 270)
                    .background(GLWNSidebarSurface())
            }
        }
        .frame(minWidth: 1_080, minHeight: 680)
        .onChange(of: session.map) { _, _ in
            previewModel.map = session.displayMap
        }
        .onChange(of: session.activeArmy) { _, _ in
            previewModel.map = session.displayMap
        }
        .onChange(of: session.fogOfWarEnabled) { _, _ in
            previewModel.map = session.displayMap
        }
        .onChange(of: session.weather) { _, _ in
            previewModel.map = session.displayMap
        }
        .onChange(of: session.submergedUnits) { _, _ in
            previewModel.map = session.displayMap
        }
        .onChange(of: session.statusMessage) { _, _ in
            previewModel.map = session.displayMap
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

            if session.ruleset == .advanceWars || session.ruleset == .advanceWars2 {
                GLWNPullDownMenu(
                    "Weather",
                    selection: $session.weather,
                    options: PlaytestWeather.allCases,
                    showsTitle: false
                ) { weather in
                    Text(weather.displayName)
                }
                .frame(minWidth: 78)
                .onChange(of: session.weather) { _, _ in
                    session.refreshSelection()
                }

                HStack (spacing: 6) {
                    Toggle("Fog", isOn: $session.fogOfWarEnabled)
                        .toggleStyle(GLWNAquaToggleStyle())
                        .help("Hide enemy units outside friendly vision")

                    Text("Fog")
                        .font(.caption.weight(.semibold))
                }
            }

            Spacer(minLength: 14)

            HStack(spacing: 8) {
                Label(session.activeArmyName, systemImage: "flag.fill")
                    .font(.subheadline.weight(.semibold))

                Label(
                    session.activeArmyIsCPU ? "CPU" : "Player",
                    systemImage: session.activeArmyIsCPU ? "cpu" : "person.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(session.activeArmyIsCPU ? .orange : .secondary)
                .help(session.activeArmyIsCPU ? "This army is controlled by the CPU." : "Orange Star is controlled by you.")
            }

            HStack(spacing: 8) {
                Text("$\(session.activeFunds.formatted())")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)

                Label("Day \(session.turn)", systemImage: "calendar.day")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button("Restart", systemImage: "arrow.counterclockwise", action: restartAction)
                .buttonStyle(GLWNInContentButtonStyle(tone: .neutral, horizontalPadding: 11, minHeight: 32))
            Button("End Turn", systemImage: "forward.fill", action: endTurnAction)
                .buttonStyle(GLWNInContentButtonStyle(tone: .accent, horizontalPadding: 11, minHeight: 32))
                .disabled(session.isGameOver || session.activeArmyIsCPU)
            Button("Exit", action: exitAction)
                .buttonStyle(GLWNInContentButtonStyle(tone: .neutral, horizontalPadding: 11, minHeight: 32))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct PlaytestMapSurface: View {
    let session: PlaytestSession
    let previewModel: EditorModel
    let atlas: SpriteAtlas

    var body: some View {
        let tileSize = MapCanvasMetrics.tileSize
        let mapSize = CGSize(
            width: CGFloat(session.map.width) * tileSize,
            height: CGFloat(session.map.height) * tileSize
        )
        let boardSize = CGSize(
            width: mapSize.width + (MapCanvasMetrics.woodPadding * 2),
            height: mapSize.height + (MapCanvasMetrics.woodPadding * 2) + MapCanvasMetrics.bottomWallHeight
        )
        let contentSize = CGSize(
            width: boardSize.width + (MapCanvasMetrics.parchmentPadding * 2),
            height: boardSize.height + (MapCanvasMetrics.parchmentPadding * 2)
        )

        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                MapParchmentSurface(tileSize: tileSize, mapSize: mapSize)

                MapCanvasBoard(
                    model: previewModel,
                    atlas: atlas,
                    interactionEnabled: false
                )
                    .offset(x: MapCanvasMetrics.parchmentPadding, y: MapCanvasMetrics.parchmentPadding)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                PlaytestInteractionLayer(
                    session: session,
                    previewModel: previewModel,
                    tileSize: tileSize
                )
                    .frame(width: mapSize.width, height: mapSize.height)
                    .offset(
                        x: MapCanvasMetrics.parchmentPadding + MapCanvasMetrics.woodPadding,
                        y: MapCanvasMetrics.parchmentPadding + MapCanvasMetrics.woodPadding
                    )
            }
            .frame(width: contentSize.width, height: contentSize.height)
        }
        .background {
            MapParchmentSurface(tileSize: tileSize, mapSize: mapSize)
                .allowsHitTesting(false)
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

            let point = GridPoint(
                x: Int(floor(location.x / tileSize)),
                y: Int(floor((bounds.height - location.y) / tileSize))
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

            for point in session.cpuMovementCells {
                drawGlassTile(point, base: movementGlass, context: &context)
            }
            for point in session.reachableCells {
                drawGlassTile(point, base: movementGlass, context: &context)
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
            drawTransportMarkers(context: &context)

            if let cpuMovementOrigin = session.cpuMovementOrigin {
                let rect = tileRect(for: cpuMovementOrigin, inset: 0.5)
                context.stroke(
                    Path(rect),
                    with: .color(Color.white.opacity(0.85)),
                    style: StrokeStyle(lineWidth: 2)
                )
                context.stroke(
                    Path(rect.insetBy(dx: 2, dy: 2)),
                    with: .color(Color.blue.opacity(0.9)),
                    style: StrokeStyle(lineWidth: 1)
                )
            }

            if let attackPreviewOrigin = session.attackPreviewOrigin {
                let rect = tileRect(for: attackPreviewOrigin, inset: 0.5)
                context.stroke(
                    Path(rect),
                    with: .color(Color.white.opacity(0.85)),
                    style: StrokeStyle(lineWidth: 2)
                )
                context.stroke(
                    Path(rect.insetBy(dx: 2, dy: 2)),
                    with: .color(attackGlass.opacity(0.9)),
                    style: StrokeStyle(lineWidth: 1)
                )
            }

            if let selectedPoint = session.selectedPoint {
                let rect = tileRect(for: selectedPoint, inset: 0.5)
                context.stroke(Path(rect), with: .color(.white.opacity(0.95)), style: StrokeStyle(lineWidth: 2))
                context.stroke(Path(rect.insetBy(dx: 2, dy: 2)), with: .color(Color.accentColor), style: StrokeStyle(lineWidth: 1))
            }
        }
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture()
                .onEnded { value in
                    let point = GridPoint(
                        x: Int(value.location.x / tileSize),
                        y: Int(value.location.y / tileSize)
                    )
                    previewModel.updatePointer(point)
                    session.handleTap(point)
                }
        )
        .background {
            PlaytestMapInput(session: session, previewModel: previewModel, tileSize: tileSize)
                .allowsHitTesting(false)
        }
        .accessibilityElement()
        .accessibilityLabel("Playtest map")
        .accessibilityValue(session.statusMessage)
        .accessibilityHint("Select a unit, choose a highlighted destination or target, or right-click a unit to preview its attacks. Use the inspector for capture, refueling, depth, missile silos, and production actions.")
        .accessibilityAddTraits(.isButton)
    }

    private func tileRect(for point: GridPoint, inset: CGFloat) -> CGRect {
        CGRect(
            x: CGFloat(point.x) * tileSize + inset,
            y: CGFloat(point.y) * tileSize + inset,
            width: tileSize - (inset * 2),
            height: tileSize - (inset * 2)
        )
    }

    private func drawTile(_ point: GridPoint, fill: Color, stroke: Color, context: inout GraphicsContext) {
        let rect = tileRect(for: point, inset: 1)
        context.fill(Path(rect), with: .color(fill))
        context.stroke(Path(rect), with: .color(stroke), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
    }

    private func drawGlassTile(_ point: GridPoint, base: Color, context: inout GraphicsContext) {
        let rect = tileRect(for: point, inset: 1)
        let fillOpacity = reduceTransparency ? 0.56 : 0.30
        let edgeOpacity = reduceTransparency ? 0.72 : 0.48
        let innerOpacity = reduceTransparency ? 0.86 : 0.66

        context.fill(
            Path(rect),
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
            Path(rect),
            with: .color(base.opacity(edgeOpacity)),
            style: StrokeStyle(lineWidth: 1)
        )
        context.stroke(
            Path(rect.insetBy(dx: 1.5, dy: 1.5)),
            with: .color(base.opacity(innerOpacity)),
            style: StrokeStyle(lineWidth: 1)
        )
    }

    private func drawFogOverlay(context: inout GraphicsContext) {
        guard session.fogOfWarEnabled else { return }

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
                context.fill(Path(tileRect(for: point, inset: 0)), with: .color(fogColor))
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
                if session.movedCells.contains(point), unit.army == session.activeArmy {
                    context.fill(
                        Path(rect),
                        with: .color(Color.black.opacity(reduceTransparency ? 0.18 : 0.30))
                    )
                }

                let health = session.unitHealth[point, default: 100]
                // Advance Wars renders the unit's health as whole tens. Keep
                // damaged units at a visible 1 rather than letting a nearly
                // destroyed unit disappear from the badge entirely.
                let displayHealth = max(1, min(10, health / 10))
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
                           session.ruleset == .advanceWars || session.ruleset == .advanceWars2 {
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
                        if session.selectedAPCCanRefuel {
                            Button("Resupply adjacent units", systemImage: "fuelpump.fill", action: session.refuelSelectedAPC)
                                .buttonStyle(GLWNInContentButtonStyle(tone: .accent, horizontalPadding: 10, minHeight: 32))
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
                               session.ruleset == .advanceWars || session.ruleset == .advanceWars2 {
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
                                        Text("$\(option.cost.formatted())")
                                            .font(.caption.monospacedDigit())
                                    }
                                }
                                .buttonStyle(GLWNInContentButtonStyle(tone: .neutral, horizontalPadding: 10, minHeight: 32))
                                .disabled(!session.canBuild(option))
                            }
                        }
                    }
                }

                Spacer(minLength: 12)
            }
            .padding(18)
        }
    }
}
