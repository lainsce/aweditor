import AppKit
import Observation
import SwiftUI
import AWEDCore

extension PlaytestSession {
    func executeCPUMove(from origin: GridPoint, to destination: GridPoint) async {
        cursorPoint = origin
        guard let unit = unit(at: origin),
              let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset) else {
            completeFallbackCPUMove(from: origin, to: destination)
            return
        }

        guard let route = cpuRoute(from: origin, to: destination, unit: unit, stats: stats) else {
            completeFallbackCPUMove(from: origin, to: destination)
            return
        }

        cpuMovementPath = [origin]
        isAnimatingCPUMovement = true
        cpuMovementAnimation = PlaytestMovementAnimation(
            unit: unit,
            from: origin,
            to: origin
        )
        defer {
            isAnimatingCPUMovement = false
            cpuMovementAnimation = nil
            invalidatePlaytestMusic()
        }
        selectUnit(at: origin)
        let finalTileIsOccupied = map.foregroundElement(atX: destination.x, y: destination.y).isUnitNonEmpty
        let animatedRoute = finalTileIsOccupied ? Array(route.dropLast()) : route
        guard let stoppedAtOccupiedIntermediate = await animateCPURoute(animatedRoute, unit: unit, origin: origin) else { return }
        cpuMovementAnimation = nil
        isAnimatingCPUMovement = false

        if finalTileIsOccupied || stoppedAtOccupiedIntermediate {
            // A load/join/ambush endpoint, or a friendly unit passed through
            // by the planner, may not be occupied during the visual walk.
            // Still show the complete planned route before resolving that
            // endpoint, keeping every segment tile-bound.
            cpuMovementPath = [origin] + route
            cursorPoint = destination
            try? await Task.sleep(nanoseconds: scaledCPUDelay(Self.cpuRoutePause))
            moveSelectedUnit(to: destination)
        } else if let finalPoint = animatedRoute.last {
            cursorPoint = finalPoint
            configurePostMoveActions(for: unit, stats: stats, at: finalPoint)
        }
    }

    private func completeFallbackCPUMove(from origin: GridPoint, to destination: GridPoint) {
        selectUnit(at: origin)
        cursorPoint = destination
        moveSelectedUnit(to: destination)
    }

    private func cpuRoute(from origin: GridPoint, to destination: GridPoint, unit: Element, stats: PlaytestUnitStats) -> [GridPoint]? {
        let paths = movementPaths(from: origin, unit: unit, stats: stats)
        guard paths[destination] != nil else { return nil }
        var route: [GridPoint] = []
        var current = destination
        while current != origin {
            guard let path = paths[current], let previous = path.previous else { return nil }
            route.append(current)
            current = previous
        }
        route.reverse()
        return route
    }

    private func animateCPURoute(_ route: [GridPoint], unit: Element, origin: GridPoint) async -> Bool? {
        var stoppedAtOccupiedIntermediate = false
        for point in route {
            guard !Task.isCancelled else { return nil }
            guard map.foregroundElement(atX: point.x, y: point.y) == .unitEmpty else {
                // Same-army units can be passed through for pathfinding, but
                // they cannot be occupied during the visual walk. Let the
                // normal final move resolve that route without corrupting a
                // friendly unit's tile.
                stoppedAtOccupiedIntermediate = true
                break
            }
            let from = selectedPoint ?? origin
            cpuMovementAnimation = PlaytestMovementAnimation(unit: unit, from: from, to: point)
            cursorPoint = point
            moveSelectedUnit(to: point)
            guard selectedPoint == point else { return nil }
            // Keep the cursor assignment after the map mutation as well. The
            // map setter can trigger a render before the movement state has
            // been observed, so this guarantees the frame follows the tile
            // that was just committed.
            cursorPoint = point
            cpuMovementPath.append(point)
            await Task.yield()
            try? await Task.sleep(nanoseconds: movementStepDelay)
        }
        return stoppedAtOccupiedIntermediate
    }

    func cpuUnitPoints() -> [GridPoint] {
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

    func cpuPropertyPoints() -> [GridPoint] {
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

    func cpuAttackPlans() -> [CPUPlan] {
        var plans: [CPUPlan] = []
        for origin in cpuUnitPoints() where !movedCells.contains(origin) {
            let unit = map.foregroundElement(atX: origin.x, y: origin.y)
            for target in sortedGridPoints(cpuAttackableCells(from: origin, unit: unit)) {
                plans.append(CPUPlan(score: attackScore(from: origin, to: target), action: .attack(origin: origin, target: target)))
            }
        }
        return plans
    }

    func cpuAttackableCells(from origin: GridPoint, unit attacker: Element) -> Set<GridPoint> {
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

        let requiresVisibility = isFogOfWarActive || !submergedUnits.isEmpty || !stealthedUnits.isEmpty
        var result = cpuAttackableEnemyCells(from: origin, attacker: attacker, stats: stats, requiresVisibility: requiresVisibility)
        result.formUnion(cpuAttackablePipeSeams(from: origin, attacker: attacker, stats: stats))
        cpuAttackableCache[key] = result
        return result
    }

    private func cpuAttackableEnemyCells(
        from origin: GridPoint,
        attacker: Element,
        stats: PlaytestUnitStats,
        requiresVisibility: Bool
    ) -> Set<GridPoint> {
        Set(cpuEnemyUnits().compactMap { enemy in
            let point = enemy.point
            guard isWithinRange(from: origin, to: point, stats: stats),
                  (!requiresVisibility || isVisible(point)),
                  ((!submergedUnits.contains(point) && !stealthedUnits.contains(point)) || attacker.simplified == .unitCruiser || attacker.simplified == .unitSub),
                  PlaytestRulebook.canAttack(attacker, enemy.unit, ruleset: ruleset, primaryAmmo: unitAmmo[origin]) else { return nil }
            return point
        })
    }

    private func cpuAttackablePipeSeams(from origin: GridPoint, attacker: Element, stats: PlaytestUnitStats) -> Set<GridPoint> {
        Set(cpuPipeSeamPoints().filter {
            isWithinRange(from: origin, to: $0, stats: stats) && canAttackPipeSeam(from: origin, to: $0, attacker: attacker)
        })
    }

    /// Movement paths are stable for the duration of one planning pass. The
    /// planner previously rebuilt this BFS once for transport joins and again
    /// for every movement candidate, which multiplied the cost on larger maps.
    func cpuMovementPaths(
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

    func cpuPipeSeamPoints() -> [GridPoint] {
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

    func attackScore(from origin: GridPoint, to target: GridPoint) -> Double {
        let attacker = map.foregroundElement(atX: origin.x, y: origin.y)
        let defender = map.foregroundElement(atX: target.x, y: target.y)
        if let pipeScore = cpuPipeSeamAttackScore(from: origin, to: target, attacker: attacker, defender: defender) {
            return pipeScore
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
                primaryAmmo: unitAmmo[origin],
                randomize: false
              ) else { return -.greatestFiniteMagnitude }

        let defenderHealth = unitHealth[target, default: 100]
        let counterDamage = cpuCounterDamage(
            attacker: attacker,
            defender: defender,
            defenderStats: defenderStats,
            origin: origin,
            target: target,
            defenderHealth: defenderHealth
        )
        let transportTargetBonus = cpuTransportTargetBonus(for: defender, at: target)
        return cpuCombatAttackScore(
            attacker: attacker,
            attackerStats: attackerStats,
            defenderStats: defenderStats,
            targetTerrain: targetTerrain,
            origin: origin,
            target: target,
            damage: damage,
            defenderHealth: defenderHealth,
            counterDamage: counterDamage,
            transportTargetBonus: transportTargetBonus
        )
    }

    private func cpuPipeSeamAttackScore(from origin: GridPoint, to target: GridPoint, attacker: Element, defender: Element) -> Double? {
        guard defender == .unitEmpty, isPipeSeam(at: target),
              let damage = pipeSeamDamage(from: origin, to: target, attacker: attacker) else { return nil }
        let currentHealth = pipeSeamHealth[target, default: Self.pipeSeamStartingHealth]
        let destructionBonus = currentHealth <= damage ? 900.0 : 420.0
        let nearbyEnemyCount = allEnemyUnitPoints().filter { distance(from: target, to: $0) <= 4 }.count
        let threatPenalty = min(Double(cpuThreat(for: attacker, at: origin)) * 0.35, 75)
        return 500 + destructionBonus + Double(damage) * 5 + Double(nearbyEnemyCount) * 12 - threatPenalty
    }

    private func cpuCounterDamage(
        attacker: Element,
        defender: Element,
        defenderStats: PlaytestUnitStats,
        origin: GridPoint,
        target: GridPoint,
        defenderHealth: Int
    ) -> Int {
        guard defenderStats.canCounterattack,
              isWithinRange(from: target, to: origin, stats: defenderStats) else { return 0 }
        return PlaytestRulebook.damage(
            attacker: defender,
            defender: attacker,
            ruleset: ruleset,
            attackerHealth: defenderHealth,
            defenderHealth: unitHealth[origin, default: 100],
            terrain: map.backgroundElement(atX: origin.x, y: origin.y),
            primaryAmmo: unitAmmo[target],
            randomize: false
        ) ?? 0
    }

    private func cpuTransportTargetBonus(for defender: Element, at target: GridPoint) -> Double {
        guard PlaytestRulebook.transportCapacity(for: defender, ruleset: ruleset) > 0 else { return 0 }
        let loadedBonus = cargo[target, default: []].isEmpty ? 0 : cpuPolicy.loadedTransportBonus
        return 42 * cpuPolicy.transportTargetMultiplier + loadedBonus
    }

    private func cpuCombatAttackScore(
        attacker: Element,
        attackerStats: PlaytestUnitStats,
        defenderStats: PlaytestUnitStats,
        targetTerrain: Element,
        origin: GridPoint,
        target: GridPoint,
        damage: Int,
        defenderHealth: Int,
        counterDamage: Int,
        transportTargetBonus: Double
    ) -> Double {
        let policy = cpuPolicy
        let lethalBonus = damage >= defenderHealth ? 700.0 : 0
        let targetValue = Double(defenderStats.cost) / 20 * policy.targetCostMultiplier
        let damageValue = Double(damage) * 7
        let healthValue = Double(defenderHealth) / 8
        let terrainPenalty = Double(PlaytestRulebook.terrainStars(for: targetTerrain, ruleset: ruleset)) * 3
        let distancePenalty = Double(distance(from: origin, to: target))
        let retaliationMultiplier = (0.75 + (Double(attackerStats.cost) / 5_000)) * policy.counterRiskMultiplier
        let retaliationPenalty = min(360, Double(counterDamage) * retaliationMultiplier)
        let threatPenalty = min(Double(cpuThreat(for: attacker, at: origin)) * 0.35 * policy.threatMultiplier, 70)
        let indirectMultiplier = attackerStats.canMoveAndFire ? 1.0 : policy.indirectAttackMultiplier
        let hqTargetBonus = ruleset == .famicomWars && targetTerrain.simplified == .buildingHQ ? 500.0 : 0
        return policy.attackBias + lethalBonus + targetValue + damageValue * indirectMultiplier + healthValue
            + transportTargetBonus + hqTargetBonus - terrainPenalty - distancePenalty - retaliationPenalty - threatPenalty
    }

    func cpuCapturePlans() -> [CPUPlan] {
        var plans: [CPUPlan] = []
        for point in cpuUnitPoints() where !movedCells.contains(point) {
            let unit = map.foregroundElement(atX: point.x, y: point.y)
            guard let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset),
                  canCapture(unit: unit, stats: stats, at: point) else { continue }
            plans.append(CPUPlan(score: captureScore(at: point), action: .capture(point: point)))
        }
        return plans
    }

    func captureScore(at point: GridPoint) -> Double {
        let building = map.backgroundElement(atX: point.x, y: point.y)
        let policy = cpuPolicy
        let progress = captureProgress[point, default: 0]
        let value = Double(PlaytestRulebook.income(for: building)) / 8
        let completionBonus = progress + 10 >= 20 ? 520.0 : 0
        let hqBonus = building.simplified == .buildingHQ
            ? 1_100.0 * policy.hqCaptureMultiplier
            : 0
        // Taking an opponent's income or production tile also denies it to
        // that army. Treat it as materially more urgent than an empty neutral
        // property, while still leaving neutral cities useful objectives.
        let enemyBonus = building.army == AWConstants.armyNeutral
            ? 0
            : 180.0 * policy.enemyPropertyMultiplier
        let productionBonus: Double
        switch building.simplified {
        case .buildingAirport, .buildingPort:
            // These properties unlock an entire production domain and should
            // be treated as strategic objectives, not merely 1,000 G cities.
            productionBonus = 170 * policy.productionCaptureMultiplier
        case .buildingBase:
            productionBonus = 80 * policy.productionCaptureMultiplier
        default:
            productionBonus = 0
        }
        let healthValue = Double(unitHealth[point, default: 100]) / 5
        let progressValue = Double(progress) * policy.captureProgressWeight
        return (175 + value + completionBonus + hqBonus + enemyBonus + productionBonus + healthValue
            + progressValue) * policy.captureMultiplier
    }

}
