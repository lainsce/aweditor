import AppKit
import Observation
import SwiftUI
import AWEDCore

extension PlaytestSession {
    func neighbors(of point: GridPoint) -> [GridPoint] {
        // The GB presentation is staggered, not hexagonal. Every tile still
        // has the same four cardinal neighbours as the other rulesets.
        cardinalNeighbors(of: point)
    }

    /// Set and dictionary iteration is intentionally randomized by Swift. CPU
    /// tie scores should not turn the same map into a different opening every
    /// run, so keep grid-point fallbacks stable (left-to-right, then top-to-
    /// bottom) whenever the tactical score is equal.
    func sortedGridPoints(_ points: Set<GridPoint>) -> [GridPoint] {
        points.sorted(by: gridPointOrder)
    }

    func gridPointOrder(_ lhs: GridPoint, _ rhs: GridPoint) -> Bool {
        lhs.x == rhs.x ? lhs.y < rhs.y : lhs.x < rhs.x
    }

    func cardinalNeighbors(of point: GridPoint) -> [GridPoint] {
        [(-1, 0), (1, 0), (0, -1), (0, 1)].map {
            GridPoint(x: point.x + $0.0, y: point.y + $0.1)
        }
    }

    func resupplyNeighbors(of point: GridPoint, transport: Element) -> [GridPoint] {
        PlaytestRulebook.resuppliesAdjacentUnits(transport, ruleset: ruleset)
            ? cardinalNeighbors(of: point)
            : neighbors(of: point)
    }

    func clearSelection() {
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

    /// Cancels the currently highlighted action without moving the cartridge
    /// cursor. This is the B-button path for the legacy menu.
    func cancelLegacySelection() {
        clearSelection()
        statusMessage = "Selection cancelled."
    }

    /// Selects whatever is under the cartridge cursor, matching an A press on
    /// the map. The view decides whether a second A opens the command menu.
    func selectLegacyCursor() {
        guard let cursorPoint else { return }
        handleTap(cursorPoint)
    }

    /// The Stat command first selects the cursor's unit/property, then leaves
    /// the details visible in the existing inspector panel.
    func inspectLegacyCursor() {
        guard let cursorPoint else {
            statusMessage = "Move the cursor onto a unit or property first."
            return
        }
        if selectedPoint != cursorPoint {
            handleTap(cursorPoint)
        } else if let selectedUnitName {
            statusMessage = "Stats shown for \(selectedUnitName)."
        } else if let selectedBuildingName {
            statusMessage = "Stats shown for \(selectedBuildingName)."
        }
    }

    func moveCursor(dx: Int, dy: Int) {
        guard map.width > 0, map.height > 0 else { return }
        let current = cursorPoint ?? GridPoint(x: 0, y: 0)
        let next = GridPoint(
            x: min(max(current.x + dx, 0), map.width - 1),
            y: min(max(current.y + dy, 0), map.height - 1)
        )
        cursorPoint = next
    }

    func setCursor(_ point: GridPoint) {
        guard isValid(point) else { return }
        cursorPoint = point
    }

    func firstLegacyTarget(in points: Set<GridPoint>) -> GridPoint? {
        points.sorted { lhs, rhs in
            lhs.x == rhs.x ? lhs.y < rhs.y : lhs.x < rhs.x
        }.first
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

    func clearAttackPreview() {
        attackPreviewOrigin = nil
        attackPreviewCells.removeAll()
    }

    func isValid(_ point: GridPoint) -> Bool {
        point.x >= 0 && point.x < map.width && point.y >= 0 && point.y < map.height
    }

    func initializeUnitResources() {
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

    func initializePipeSeams() {
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

    func maxFuel(for point: GridPoint) -> Int {
        guard let unit = unit(at: point) else { return 100 }
        return PlaytestRulebook.maxFuel(for: unit, ruleset: ruleset)
    }

    static func initialCursor(in map: MapState, army: Int) -> GridPoint? {
        guard map.width > 0, map.height > 0 else { return nil }

        // Start on the first controllable unit, then fall back to an owned
        // property. This makes the first A press useful on both battle maps
        // and production-only test maps.
        for x in 0..<map.width {
            for y in 0..<map.height {
                let unit = map.foregroundElement(atX: x, y: y)
                if unit.isUnitNonEmpty, unit.army == army {
                    return GridPoint(x: x, y: y)
                }
            }
        }
        for x in 0..<map.width {
            for y in 0..<map.height {
                let building = map.backgroundElement(atX: x, y: y)
                if building.isBuilding, building.army == army {
                    return GridPoint(x: x, y: y)
                }
            }
        }
        return GridPoint(x: 0, y: 0)
    }

    static func armies(in map: MapState) -> [Int] {
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
