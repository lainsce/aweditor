import AppKit
import Observation
import SwiftUI
import AWEDCore

extension PlaytestSession {
    func movementPaths(from origin: GridPoint, unit: Element, stats: PlaytestUnitStats) -> [GridPoint: MovementPath] {
        let fuel = unitFuel[origin, default: stats.maxFuel]
        var paths: [GridPoint: MovementPath] = [origin: MovementPath(movement: 0, steps: 0, previous: nil)]
        var frontier: [GridPoint] = [origin]
        var index = 0

        while index < frontier.count {
            let current = frontier[index]
            index += 1
            guard let currentPath = paths[current] else { continue }
            expandMovementFrontier(
                from: current,
                origin: origin,
                unit: unit,
                stats: stats,
                currentPath: currentPath,
                fuel: fuel,
                paths: &paths,
                frontier: &frontier
            )
        }

        paths.removeValue(forKey: origin)
        return paths
    }

    private func expandMovementFrontier(
        from current: GridPoint,
        origin: GridPoint,
        unit: Element,
        stats: PlaytestUnitStats,
        currentPath: MovementPath,
        fuel: Int,
        paths: inout [GridPoint: MovementPath],
        frontier: inout [GridPoint]
    ) {
        for next in neighbors(of: current) {
            let isAmbushDestination = isHiddenEnemy(map.foregroundElement(atX: next.x, y: next.y), at: next, relativeTo: unit)
            guard let nextPath = movementCandidate(
                from: current,
                to: next,
                origin: origin,
                unit: unit,
                stats: stats,
                currentPath: currentPath,
                fuel: fuel
            ), shouldReplaceMovementPath(paths[next], with: nextPath) else { continue }
            paths[next] = nextPath
            // A hidden enemy is an ambush endpoint, not a square the mover may pass through.
            if !isAmbushDestination { frontier.append(next) }
        }
    }

    private func shouldReplaceMovementPath(_ existing: MovementPath?, with candidate: MovementPath) -> Bool {
        guard let existing else { return true }
        return existing.movement > candidate.movement ||
            (existing.movement == candidate.movement && existing.steps > candidate.steps)
    }

    private func movementCandidate(
        from current: GridPoint,
        to next: GridPoint,
        origin: GridPoint,
        unit: Element,
        stats: PlaytestUnitStats,
        currentPath: MovementPath,
        fuel: Int
    ) -> MovementPath? {
        guard isValid(next) else { return nil }
        let occupant = map.foregroundElement(atX: next.x, y: next.y)
        let terrain = map.backgroundElement(atX: next.x, y: next.y)
        let isAmbushDestination = isHiddenEnemy(occupant, at: next, relativeTo: unit)
        guard canPassThrough(occupant, unit: unit) || isAmbushDestination else { return nil }
        let cost = PlaytestRulebook.movementCost(for: unit, stats: stats, terrain: terrain, ruleset: ruleset, weather: weather, tileset: map.tileset)
        guard canEnterMovementCell(unit: unit, stats: stats, terrain: terrain, occupant: occupant, point: next, origin: origin, cost: cost, isAmbush: isAmbushDestination), let cost else { return nil }

        let nextPath = MovementPath(movement: currentPath.movement + cost, steps: currentPath.steps + 1, previous: current)
        let fuelCost = PlaytestRulebook.movementFuelCost(for: unit, movement: nextPath.movement, ruleset: ruleset, weather: weather)
        return nextPath.movement <= stats.move && fuelCost <= fuel ? nextPath : nil
    }

    private func canPassThrough(_ occupant: Element, unit: Element) -> Bool {
        occupant == .unitEmpty || (occupant.isUnitNonEmpty && !isHostile(occupant.army, unit.army))
    }

    private func canEnterMovementCell(
        unit: Element,
        stats: PlaytestUnitStats,
        terrain: Element,
        occupant: Element,
        point: GridPoint,
        origin: GridPoint,
        cost: Int?,
        isAmbush: Bool
    ) -> Bool {
        let isRiver = terrain.simplified == .terrainRiver
        let load = canLoad(unit, into: occupant, at: point)
        let join = canJoin(unit, with: occupant, at: point, firstPoint: origin)
        let stand = map.allowPlacement(unit, atX: point.x, y: point.y)
        let friendlyOccupant = occupant.isUnitNonEmpty && !isHostile(occupant.army, unit.army)
        return (!isRiver || stats.domain == .air || cost != nil) &&
            (load || join || stand || (isRiver && cost != nil) || friendlyOccupant || isAmbush)
    }

    func canLoad(_ cargoUnit: Element, into transport: Element, at point: GridPoint) -> Bool {
        guard transport.isUnitNonEmpty,
                      transport.army == cargoUnit.army,
              PlaytestRulebook.canTransport(transport, cargo: cargoUnit, ruleset: ruleset),
              cargo[point, default: []].count < PlaytestRulebook.transportCapacity(for: transport, ruleset: ruleset) else { return false }
        return true
    }

    func canJoin(_ first: Element, with second: Element, at point: GridPoint, firstPoint: GridPoint? = nil) -> Bool {
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

    func updateTransportActions(for transport: Element, at point: GridPoint) {
        loadableCells.removeAll()
        joinableCells.removeAll()
        unloadableCells.removeAll()
        refuelableCells.removeAll()

        let capacity = PlaytestRulebook.transportCapacity(for: transport, ruleset: ruleset)
        updateLoadActions(for: transport, at: point, capacity: capacity)
        updateJoinActions(for: transport, at: point, capacity: capacity)
        updateUnloadActions(for: transport, at: point)
        updateRefuelActions(for: transport, at: point)
    }

    private func updateLoadActions(for transport: Element, at point: GridPoint, capacity: Int) {
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
    }

    private func updateJoinActions(for transport: Element, at point: GridPoint, capacity: Int) {
        if capacity == 0 {
            for neighbor in neighbors(of: point) {
                guard isValid(neighbor),
                      let candidate = self.unit(at: neighbor),
                      canJoin(transport, with: candidate, at: neighbor) else { continue }
                joinableCells.insert(neighbor)
            }
        }
    }

    private func updateUnloadActions(for transport: Element, at point: GridPoint) {
        if let loaded = cargo[point], !loaded.isEmpty {
            let index = min(selectedCargoIndex, loaded.count - 1)
            let selected = loaded[index]
            for neighbor in neighbors(of: point) where isValid(neighbor) {
                guard canUnload(selected.unit, from: transport, at: neighbor) else { continue }
                unloadableCells.insert(neighbor)
            }
        }
    }

    private func updateRefuelActions(for transport: Element, at point: GridPoint) {
        if PlaytestRulebook.resuppliesAdjacentUnits(transport, ruleset: ruleset) ||
            transport.simplified == .unitBlackBoat {
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

    func canUnload(_ cargoUnit: Element, from transport: Element, at destination: GridPoint) -> Bool {
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

    func loadUnit(from source: GridPoint) {
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
        statusMessage = "Loaded \(PaletteCatalog.label(for: loadedUnit, tileset: map.tileset)) into \(PaletteCatalog.label(for: transport, tileset: map.tileset)). The transport may still move."
    }

    func joinUnit(to destination: GridPoint) {
        guard let context = joinContext(to: destination) else {
            statusMessage = "Those units cannot join."
            return
        }
        var candidate = map
        guard candidate.setForeground(.unitEmpty, atX: context.origin.x, y: context.origin.y) else {
            statusMessage = "Those units cannot join."
            return
        }
        map = candidate
        applyJoinResources(context)
        unitHealth[destination] = min(100, context.combinedHealth)
        let maxFuel = PlaytestRulebook.maxFuel(for: context.second, ruleset: ruleset)
        let fuelCost = PlaytestRulebook.movementFuelCost(
            for: context.first,
            movement: context.path.movement,
            ruleset: ruleset,
            weather: weather
        )
        let firstFuelAfterMove = max(0, unitFuel[context.origin, default: maxFuel] - fuelCost)
        unitFuel[destination] = min(maxFuel, firstFuelAfterMove + unitFuel[destination, default: maxFuel])
        if let ammo = PlaytestRulebook.primaryAmmo(for: context.second, ruleset: ruleset) {
            unitAmmo[destination] = min(ammo, unitAmmo[context.origin, default: ammo] + unitAmmo[destination, default: ammo])
        }
        unitHealth.removeValue(forKey: context.origin)
        unitFuel.removeValue(forKey: context.origin)
        unitAmmo.removeValue(forKey: context.origin)
        captureProgress.removeValue(forKey: context.origin)
        captureProgress.removeValue(forKey: destination)
        submergedUnits.remove(context.origin)
        stealthedUnits.remove(context.origin)
        movedCells.remove(context.origin)
        movedCells.insert(destination)
        clearSelection()
        statusMessage = "Joined the two \(PaletteCatalog.label(for: context.second, tileset: map.tileset)) units."
    }

    private func joinContext(to destination: GridPoint) -> (origin: GridPoint, first: Element, second: Element, path: MovementPath, combinedHealth: Int, excessHP: Int)? {
        guard let origin = selectedPoint,
              let first = unit(at: origin),
              let second = unit(at: destination),
              let firstStats = PlaytestRulebook.stats(for: first, ruleset: ruleset),
              !movedCells.contains(origin),
              canJoin(first, with: second, at: destination),
              let path = movementPaths(from: origin, unit: first, stats: firstStats)[destination] else { return nil }
        let combinedHealth = unitHealth[origin, default: 100] + unitHealth[destination, default: 100]
        return (origin, first, second, path, combinedHealth, max(0, combinedHealth - 100) / 10)
    }

    private func applyJoinResources(_ context: (origin: GridPoint, first: Element, second: Element, path: MovementPath, combinedHealth: Int, excessHP: Int)) {
        guard context.excessHP > 0,
              let stats = PlaytestRulebook.stats(for: context.first, ruleset: ruleset) else { return }
        funds[activeArmy, default: 0] += context.excessHP * max(1, stats.cost / 10)
    }

    func unloadUnit(to destination: GridPoint) {
        guard let transportPoint = selectedPoint,
              let transport = unit(at: transportPoint),
              var loaded = cargo[transportPoint],
              !loaded.isEmpty,
              unloadableCells.contains(destination) else {
            statusMessage = "That cargo cannot be unloaded there."
            return
        }

        var candidate = map
        let index = min(selectedCargoIndex, loaded.count - 1)
        let payload = loaded[index]
        guard candidate.setForeground(payload.unit, atX: destination.x, y: destination.y) else {
            statusMessage = "That cargo cannot be unloaded there."
            return
        }
        map = candidate
        loaded.remove(at: index)
        selectedCargoIndex = min(selectedCargoIndex, max(0, loaded.count - 1))
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

    func resupplySelectedTransport(target: GridPoint? = nil) {
        guard let point = selectedPoint,
              let transport = unit(at: point),
              PlaytestRulebook.resuppliesAdjacentUnits(transport, ruleset: ruleset) ||
                transport.simplified == .unitBlackBoat,
              !refuelableCells.isEmpty else {
            statusMessage = "No adjacent friendly units need supplies."
            return
        }

        guard let targets = resupplyTargets(for: transport, requested: target) else { return }
        let repairedCount = resupplyUnits(targets, from: transport)
        movedCells.insert(point)
        reachableCells.removeAll()
        updateTransportActions(for: transport, at: point)
        if transport.simplified == .unitBlackBoat {
            statusMessage = repairedCount == 1
                ? "Black Boat repaired and resupplied the selected unit."
                : "Black Boat resupplied the selected unit."
        } else {
            let supplierName = PaletteCatalog.label(for: transport, tileset: map.tileset)
            statusMessage = "\(supplierName) resupplied \(targets.count) adjacent unit(s)."
        }
    }

    private func resupplyTargets(for transport: Element, requested target: GridPoint?) -> [GridPoint]? {
        guard transport.simplified == .unitBlackBoat else { return Array(refuelableCells) }
        guard let target, refuelableCells.contains(target) else {
            statusMessage = "Choose one adjacent unit for the Black Boat to repair."
            return nil
        }
        return [target]
    }

    private func resupplyUnits(_ targets: [GridPoint], from transport: Element) -> Int {
        var repairedCount = 0
        for neighbor in targets {
            unitFuel[neighbor] = maxFuel(for: neighbor)
            if let adjacent = unit(at: neighbor), let ammo = PlaytestRulebook.primaryAmmo(for: adjacent, ruleset: ruleset) {
                unitAmmo[neighbor] = ammo
            }
            if transport.simplified == .unitBlackBoat, repairTransportTarget(neighbor, army: transport.army) {
                repairedCount += 1
            }
        }
        return repairedCount
    }

    private func repairTransportTarget(_ point: GridPoint, army: Int) -> Bool {
        guard let adjacent = unit(at: point),
              let stats = PlaytestRulebook.stats(for: adjacent, ruleset: ruleset),
              unitHealth[point, default: 100] < 100 else { return false }
        let repairCost = max(1, stats.cost / 10)
        guard funds[army, default: 0] >= repairCost else { return false }
        funds[army, default: 0] -= repairCost
        unitHealth[point] = min(100, unitHealth[point, default: 100] + 10)
        return true
    }

    func refuelAdjacentUnits(for army: Int) {
        for x in 0..<map.width {
            for y in 0..<map.height {
                let point = GridPoint(x: x, y: y)
                let transport = map.foregroundElement(atX: x, y: y)
                guard transport.isUnitNonEmpty,
                      transport.army == army,
                      PlaytestRulebook.resuppliesAdjacentUnits(transport, ruleset: ruleset) else { continue }
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
    func resupplyCarriedAircraft(for army: Int) {
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

    func isPipeSeam(at point: GridPoint) -> Bool {
        guard isValid(point) else { return false }
        let background = map.backgroundElement(atX: point.x, y: point.y)
        if background.simplified == .terrainSeam { return true }
        // Imported maps can retain the seam in the derived draw layer while
        // storing the underlying tile as Plain D. Treat that visual seam as
        // the same attackable objective during playtest.
        return background.simplified == .terrainPlainD &&
            map.backgroundDrawElement(atX: point.x, y: point.y).simplified == .terrainSeam
    }

    func canAttackPipeSeam(from origin: GridPoint, to destination: GridPoint, attacker: Element) -> Bool {
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

}
