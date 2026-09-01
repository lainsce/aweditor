import AppKit
import Observation
import SwiftUI
import AWEDCore

extension PlaytestSession {
    func moveUnitIntoTransport(
        unit: Element,
        transport: Element,
        from origin: GridPoint,
        to destination: GridPoint,
        path: MovementPath
    ) {
        guard canLoad(unit, into: transport, at: destination) else {
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
            fuel: remainingFuel(for: unit, at: origin, after: path),
            ammo: unitAmmo.removeValue(forKey: origin)
        )
        cargo[destination, default: []].append(payload)
        movedCells.remove(origin)
        selectedPoint = destination
        productionOptions.removeAll()
        refreshTransportAfterLoad(transport, at: destination)
        statusMessage = "Loaded \(PaletteCatalog.label(for: unit, tileset: map.tileset)) into \(PaletteCatalog.label(for: transport, tileset: map.tileset))."
    }

    private func remainingFuel(for unit: Element, at origin: GridPoint, after path: MovementPath) -> Int {
        let startingFuel = unitFuel.removeValue(forKey: origin) ?? maxFuel(for: origin)
        let fuelCost = PlaytestRulebook.movementFuelCost(
            for: unit,
            movement: path.movement,
            ruleset: ruleset,
            weather: weather
        )
        return max(0, startingFuel - fuelCost)
    }

    private func refreshTransportAfterLoad(_ transport: Element, at destination: GridPoint) {
        guard let transportStats = PlaytestRulebook.stats(for: transport, ruleset: ruleset) else {
            clearSelection()
            return
        }
        reachableCells = movedCells.contains(destination)
            ? []
            : movementCells(from: destination, unit: transport, stats: transportStats)
        captureableCells.removeAll()
        attackableCells = attackableCells(from: destination, unit: transport)
        updateTransportActions(for: transport, at: destination)
    }

    func moveUnitToEmptyDestination(
        unit: Element,
        stats: PlaytestUnitStats,
        from origin: GridPoint,
        to destination: GridPoint,
        path: MovementPath
    ) {
        var candidate = map
        guard candidate.setForeground(.unitEmpty, atX: origin.x, y: origin.y),
              candidate.setForeground(unit, atX: destination.x, y: destination.y) else {
            statusMessage = "That unit cannot move there."
            return
        }

        map = candidate
        captureProgress.removeValue(forKey: origin)
        unitHealth[destination] = unitHealth.removeValue(forKey: origin) ?? 100
        unitFuel[destination] = remainingFuel(for: unit, at: origin, after: path, fallback: stats.maxFuel)
        unitAmmo[destination] = unitAmmo.removeValue(forKey: origin)
        cargo[destination] = cargo.removeValue(forKey: origin)
        moveUnitFlags(from: origin, to: destination)
        movedCells.remove(origin)
        movedCells.insert(destination)

        if isAnimatingCPUMovement || isAnimatingPlayerMovement {
            retainSelectionDuringMovement(at: destination)
            return
        }
        configurePostMoveActions(for: unit, stats: stats, at: destination)
    }

    private func remainingFuel(
        for unit: Element,
        at origin: GridPoint,
        after path: MovementPath,
        fallback: Int
    ) -> Int {
        let startingFuel = unitFuel.removeValue(forKey: origin) ?? fallback
        let fuelCost = PlaytestRulebook.movementFuelCost(
            for: unit,
            movement: path.movement,
            ruleset: ruleset,
            weather: weather
        )
        return max(0, startingFuel - fuelCost)
    }

    private func moveUnitFlags(from origin: GridPoint, to destination: GridPoint) {
        if submergedUnits.remove(origin) != nil {
            submergedUnits.insert(destination)
        }
        if stealthedUnits.remove(origin) != nil {
            stealthedUnits.insert(destination)
        }
    }

    private func retainSelectionDuringMovement(at destination: GridPoint) {
        // Keep the unit selected while a tile-by-tile walk is in progress.
        // Post-move actions are resolved only after the final tile, so the
        // intermediate sprite updates remain visible.
        selectedPoint = destination
        reachableCells.removeAll()
        attackableCells.removeAll()
        captureableCells.removeAll()
        loadableCells.removeAll()
        joinableCells.removeAll()
        unloadableCells.removeAll()
        refuelableCells.removeAll()
        productionOptions.removeAll()
    }
}
