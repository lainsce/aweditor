import AppKit
import Observation
import SwiftUI
import AWEDCore

extension PlaytestSession {
    func beginTileMovement(to destination: GridPoint) {
        guard let origin = selectedPoint,
              let unit = unit(at: origin),
              let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset) else {
            clearSelection()
            return
        }

        let paths = movementPaths(from: origin, unit: unit, stats: stats)
        guard paths[destination] != nil,
              let route = movementRoute(from: origin, to: destination, paths: paths),
              route.count > 1 else {
            statusMessage = "That unit cannot move there."
            return
        }

        let destinationUnit = map.foregroundElement(atX: destination.x, y: destination.y)
        let finalTileIsOccupied = destinationUnit.isUnitNonEmpty
        let animatedRoute = finalTileIsOccupied ? Array(route.dropLast()) : route
        playerMovementPath = [origin]
        isAnimatingPlayerMovement = true

        playerMovementTask?.cancel()
        playerMovementTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isAnimatingPlayerMovement = false
                self.playerMovementTask = nil
                self.playerMovementPath.removeAll(keepingCapacity: true)
                self.playerMovementAnimation = nil
                self.invalidatePlaytestMusic()
            }
            await self.animatePlayerRoute(
                animatedRoute,
                unit: unit,
                origin: origin,
                destination: destination,
                finalTileIsOccupied: finalTileIsOccupied
            )
        }
    }

    private func animatePlayerRoute(
        _ route: [GridPoint],
        unit movingUnit: Element,
        origin: GridPoint,
        destination: GridPoint,
        finalTileIsOccupied: Bool
    ) async {
        for point in route.dropFirst() {
            guard !Task.isCancelled else { return }
            guard map.foregroundElement(atX: point.x, y: point.y) == .unitEmpty else { return }
            let from = selectedPoint ?? origin
            playerMovementAnimation = PlaytestMovementAnimation(unit: movingUnit, from: from, to: point)
            moveSelectedUnit(to: point)
            guard selectedPoint == point else { return }
            playerMovementPath.append(point)
            await Task.yield()
            try? await Task.sleep(nanoseconds: movementStepDelay)
        }

        guard !Task.isCancelled else { return }
        playerMovementAnimation = nil
        isAnimatingPlayerMovement = false
        if finalTileIsOccupied {
            // Show the final destination as the camera's next tile before resolving a load, join, or hidden-enemy ambush there.
            playerMovementPath.append(destination)
            moveSelectedUnit(to: destination)
        } else if let finalUnit = self.unit(at: destination),
                  let finalStats = PlaytestRulebook.stats(for: finalUnit, ruleset: ruleset) {
            configurePostMoveActions(for: finalUnit, stats: finalStats, at: destination)
        }
    }

    func moveSelectedUnitSynchronously(to destination: GridPoint) {
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
            revealAmbush(from: origin, destination: destination, path: path, paths: paths, unit: unit, stats: stats)
            return
        }
        if destinationUnit.isUnitNonEmpty, canJoin(unit, with: destinationUnit, at: destination) {
            joinUnit(to: destination)
            return
        }
        if destinationUnit.isUnitNonEmpty {
            moveUnitIntoTransport(
                unit: unit,
                transport: destinationUnit,
                from: origin,
                to: destination,
                path: path
            )
            return
        }
        moveUnitToEmptyDestination(unit: unit, stats: stats, from: origin, to: destination, path: path)
    }

    /// Movement consumes the unit's movement, but Infantry and Mech units may
    /// still capture a property they moved onto. Units that can move and fire
    /// also retain their legal attack targets as a follow-up action.
    func configurePostMoveActions(for unit: Element, stats: PlaytestUnitStats, at destination: GridPoint) {
        selectedPoint = destination
        reachableCells.removeAll()
        captureableCells = canCapture(unit: unit, stats: stats, at: destination) ? [destination] : []
        loadableCells.removeAll()
        joinableCells.removeAll()
        unloadableCells.removeAll()
        refuelableCells.removeAll()
        productionOptions.removeAll()
        attackableCells = stats.canMoveAndFire ? attackableCells(from: destination, unit: unit) : []
        let canUseSpecialAction = unit.simplified == .unitBlackBomb ||
            (ruleset == .daysOfRuin && unit.simplified == .unitOozium)

        guard !attackableCells.isEmpty || !captureableCells.isEmpty || canUseSpecialAction else {
            clearSelection()
            statusMessage = "\(PaletteCatalog.label(for: unit, tileset: map.tileset)) moved and is spent."
            return
        }

        if !attackableCells.isEmpty && !captureableCells.isEmpty {
            statusMessage = "Choose an enemy in red, capture the highlighted property, or end the action."
        } else if !captureableCells.isEmpty {
            statusMessage = "Capture the highlighted property or end the action."
        } else if canUseSpecialAction {
            statusMessage = "Use the special action or end the action."
        } else {
            statusMessage = "Choose an enemy in red, or end the action."
        }
    }

    func movementCells(from origin: GridPoint, unit: Element, stats: PlaytestUnitStats) -> Set<GridPoint> {
        let paths = movementPaths(from: origin, unit: unit, stats: stats)
        return Set(paths.compactMap { point, _ in
            let occupant = map.foregroundElement(atX: point.x, y: point.y)
            return occupant == .unitEmpty || canLoad(unit, into: occupant, at: point) ||
                canJoin(unit, with: occupant, at: point, firstPoint: origin) ||
                isHiddenEnemy(occupant, at: point, relativeTo: unit) ? point : nil
        })
    }

    func movementRoute(
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

}
