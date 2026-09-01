import AppKit
import Observation
import SwiftUI
import AWEDCore

extension PlaytestSession {
    func beginSiloLaunch() {
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

    func launchSilo(at target: GridPoint) {
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

    func canBuild(_ option: PlaytestProductionOption) -> Bool {
        guard let point = selectedPoint,
              selectedBuildingName != nil,
              let building = Optional(map.backgroundElement(atX: point.x, y: point.y)),
              building.army == activeArmy,
              map.foregroundElement(atX: point.x, y: point.y) == .unitEmpty,
              !movedCells.contains(point),
              activeFunds >= option.cost,
              unitCount(for: activeArmy) < PlaytestRulebook.unitCap(for: ruleset),
              PlaytestRulebook.productionOptions(for: building, ruleset: ruleset, tileset: map.tileset).contains(where: { $0.id == option.id }) else { return false }
        // Famicom/Super Famicom's local HQ-radius rule belongs to the CPU
        // planner. Human production remains available at any owned,
        // production-capable property, matching the visible cartridge menu.
        return map.allowPlacement(option.element.changedArmy(activeArmy), atX: point.x, y: point.y)
    }

    func productionIsWithinHQArea(_ point: GridPoint) -> Bool {
        guard let radius = cpuPolicy.hqProductionRadius else { return true }
        let hqPoints = allMapPoints().filter {
            let building = map.backgroundElement(atX: $0.x, y: $0.y)
            return building.simplified == .buildingHQ && building.army == activeArmy
        }
        guard !hqPoints.isEmpty else { return true }
        return hqPoints.contains { hq in
            max(abs(hq.x - point.x), abs(hq.y - point.y)) <= radius
        }
    }

    func buildUnit(_ option: PlaytestProductionOption) {
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

    func selectUnit(at point: GridPoint) {
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
            let movementHint = ruleset.showsMovementAvailabilityBadge ? "an M marker" : "a blue tile"
            statusMessage = "Move to \(movementHint), attack a red target, load or unload cargo, or capture the highlighted property."
        }
    }

    func refreshSelection() {
        guard let selectedPoint,
              let unit = unit(at: selectedPoint) else { return }
        selectUnit(at: selectedPoint)
        if PlaytestRulebook.resuppliesAdjacentUnits(unit, ruleset: ruleset) ||
            unit.simplified == .unitBlackBoat {
            updateTransportActions(for: unit, at: selectedPoint)
        }
    }

    func effectiveVision(for observer: Element, at point: GridPoint) -> Int? {
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
    func visibleCells() -> Set<GridPoint> {
        if cachedVisibilityRevision == visibilityRevision {
            return cachedVisibleCells
        }

        let allPoints = allMapPoints()
        let fogActive = isFogOfWarActive
        var visible = baseVisibility(allPoints: allPoints, fogActive: fogActive)

        for observerX in 0..<map.width {
            for observerY in 0..<map.height {
                let observerPoint = GridPoint(x: observerX, y: observerY)
                let observer = map.foregroundElement(atX: observerX, y: observerY)
                revealCells(for: observer, at: observerPoint, into: &visible)
            }
        }

        visible.formUnion(flareRevealCells)

        // Owned units and properties remain visible even when they do not
        // provide vision themselves. This also preserves the old behavior for
        // an army with no active observers.
        insertOwnedCells(allPoints: allPoints, into: &visible)

        cachedVisibleCells = visible
        cachedVisibilityRevision = visibilityRevision
        return visible
    }

    private func baseVisibility(allPoints: [GridPoint], fogActive: Bool) -> Set<GridPoint> {
        guard fogActive else {
            var visible = Set(allPoints)
            removeHiddenEnemies(from: &visible, points: allPoints)
            return visible
        }
        return []
    }

    private func removeHiddenEnemies(from visible: inout Set<GridPoint>, points: [GridPoint]) {
        for point in points {
            let unit = map.foregroundElement(atX: point.x, y: point.y)
            let hidden = unit.isUnitNonEmpty && isHostile(unit.army, activeArmy) &&
                ((unit.simplified == .unitSub && submergedUnits.contains(point)) ||
                 (unit.simplified == .unitStealth && stealthedUnits.contains(point)))
            if hidden { visible.remove(point) }
        }
    }

    private func revealCells(for observer: Element, at point: GridPoint, into visible: inout Set<GridPoint>) {
        guard observer.isUnitNonEmpty,
              (observer.army == activeArmy || isAllied(observer.army, activeArmy)),
              let observerStats = PlaytestRulebook.stats(for: observer, ruleset: ruleset),
              let vision = effectiveVision(for: observer, at: point) else { return }

        let xRange = max(0, point.x - vision)...min(map.width - 1, point.x + vision)
        let yRange = max(0, point.y - vision)...min(map.height - 1, point.y + vision)
        for targetX in xRange {
            for targetY in yRange {
                let target = GridPoint(x: targetX, y: targetY)
                let tileDistance = distance(from: point, to: target)
                if tileDistance <= vision && canReveal(target, from: observer, stats: observerStats, distance: tileDistance) {
                    visible.insert(target)
                }
            }
        }
    }

    private func canReveal(_ target: GridPoint, from observer: Element, stats: PlaytestUnitStats, distance: Int) -> Bool {
        let targetUnit = map.foregroundElement(atX: target.x, y: target.y)
        let targetTerrain = map.backgroundElement(atX: target.x, y: target.y)
        if isConcealed(targetUnit, at: target), distance > 1,
           observer.simplified != .unitCruiser,
           !(targetUnit.simplified == .unitSub && observer.simplified == .unitSub) {
            return false
        }
        guard distance > 1, stats.domain != .air,
              let targetStats = PlaytestRulebook.stats(for: targetUnit, ruleset: ruleset) else { return true }
        if targetTerrain.simplified == .terrainWood { return targetStats.domain != .land }
        if targetTerrain.simplified == .terrainReef { return targetStats.domain != .sea }
        return true
    }

    private func isConcealed(_ unit: Element, at point: GridPoint) -> Bool {
        unit.isUnitNonEmpty &&
            ((unit.simplified == .unitSub && submergedUnits.contains(point)) ||
             (unit.simplified == .unitStealth && stealthedUnits.contains(point)))
    }

    private func insertOwnedCells(allPoints: [GridPoint], into visible: inout Set<GridPoint>) {
        for point in allPoints {
            let unit = map.foregroundElement(atX: point.x, y: point.y)
            let building = map.backgroundElement(atX: point.x, y: point.y)
            let ownedUnit = unit.isUnitNonEmpty && isFriendly(unit.army)
            let ownedBuilding = building.isBuilding && isFriendly(building.army)
            if ownedUnit || ownedBuilding { visible.insert(point) }
        }
    }

    private func isFriendly(_ army: Int) -> Bool {
        army == activeArmy || isAllied(army, activeArmy)
    }

    func invalidateVisibilityCache() {
        visibilityRevision &+= 1
        cachedVisibilityRevision = -1
        cachedVisibleCells.removeAll(keepingCapacity: true)
    }

    func invalidatePlaytestMusic() {
        guard ruleset == .gameBoyWars3 else { return }
        musicRevision &+= 1
    }

    /// Map dimensions are stable while units move. Reuse the coordinate list
    /// needed by visibility calculations instead of allocating a new nested
    /// array every time the render-only map snapshot is requested.
    func allMapPoints() -> [GridPoint] {
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

    func isHiddenEnemy(_ occupant: Element, at point: GridPoint, relativeTo unit: Element) -> Bool {
        guard occupant.isUnitNonEmpty, isHostile(occupant.army, unit.army) else { return false }
        guard isFogOfWarActive || submergedUnits.contains(point) || stealthedUnits.contains(point) else { return false }
        return !isVisible(point)
    }

    var usesTileMovementAnimation: Bool {
        switch ruleset {
        case .famicomWars, .gameBoyWars, .gameBoyWars2, .gameBoyWars3:
            true
        case .superFamicomWars, .advanceWars, .advanceWars2, .dualStrike, .daysOfRuin:
            false
        }
    }

    func revealAmbush(
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
            if stealthedUnits.remove(origin) != nil {
                stealthedUnits.insert(stop)
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

    func selectBuilding(at point: GridPoint) {
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

    func moveSelectedUnit(to destination: GridPoint) {
        if usesTileMovementAnimation,
           !activeArmyIsCPU,
           !isAnimatingCPUMovement,
           !isAnimatingPlayerMovement {
            beginTileMovement(to: destination)
            return
        }

        moveSelectedUnitSynchronously(to: destination)
    }

    /// Starts the cartridge-style walk used by Famicom Wars and GB Wars 1–3.
    /// The route is committed one tile at a time so both the unit sprite and
    /// the camera can advance in lockstep instead of jumping to the endpoint.
}
