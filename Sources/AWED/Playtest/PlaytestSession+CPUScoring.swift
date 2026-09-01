import AppKit
import Observation
import SwiftUI
import AWEDCore

extension PlaytestSession {
    func cpuTransportPlans() -> [CPUPlan] {
        var plans: [CPUPlan] = []
        for point in cpuUnitPoints() where !movedCells.contains(point) {
            let unitElement = map.foregroundElement(atX: point.x, y: point.y)
            let capacity = PlaytestRulebook.transportCapacity(for: unitElement, ruleset: ruleset)
            plans.append(contentsOf: cpuTransportLoadPlans(at: point, unit: unitElement, capacity: capacity))
            plans.append(contentsOf: cpuTransportUnloadPlans(at: point, unit: unitElement))
            if let resupply = cpuTransportResupplyPlan(at: point, unit: unitElement) {
                plans.append(resupply)
            }
            plans.append(contentsOf: cpuTransportJoinPlans(at: point, unit: unitElement))
        }
        return plans
    }

    private func cpuTransportLoadPlans(at point: GridPoint, unit transport: Element, capacity: Int) -> [CPUPlan] {
        guard capacity > 0, cargo[point, default: []].count < capacity else { return [] }
        return neighbors(of: point).filter { isValid($0) }.compactMap { neighbor in
            guard let candidate = unit(at: neighbor), canLoad(candidate, into: transport, at: point) else { return nil }
            let cargoCost = PlaytestRulebook.stats(for: candidate, ruleset: ruleset)?.cost ?? 0
            return CPUPlan(
                score: 120 * cpuPolicy.transportActionMultiplier + Double(cargoCost) / 100,
                action: .load(transport: point, cargo: neighbor)
            )
        }
    }

    private func cpuTransportUnloadPlans(at point: GridPoint, unit transport: Element) -> [CPUPlan] {
        guard let loaded = cargo[point]?.first else { return [] }
        return neighbors(of: point).filter { isValid($0) }.compactMap { neighbor in
            guard canUnload(loaded.unit, from: transport, at: neighbor) else { return nil }
            return CPUPlan(
                score: 115 * cpuPolicy.transportActionMultiplier + cpuDestinationScore(for: loaded.unit, at: neighbor),
                action: .unload(transport: point, destination: neighbor)
            )
        }
    }

    private func cpuTransportResupplyPlan(at point: GridPoint, unit transport: Element) -> CPUPlan? {
        guard PlaytestRulebook.resuppliesAdjacentUnits(transport, ruleset: ruleset) || transport.simplified == .unitBlackBoat,
              resupplyNeighbors(of: point, transport: transport).contains(where: { cpuNeedsResupply($0, transport: transport) }) else {
            return nil
        }
        return CPUPlan(score: 108 * cpuPolicy.supplyActionMultiplier, action: .resupply(point: point))
    }

    private func cpuNeedsResupply(_ neighbor: GridPoint, transport: Element) -> Bool {
        guard isValid(neighbor), let adjacent = unit(at: neighbor), adjacent.army == activeArmy else { return false }
        let needsHealth = transport.simplified == .unitBlackBoat && unitHealth[neighbor, default: 100] < 100
        let fuel = maxFuel(for: neighbor)
        let needsFuel = unitFuel[neighbor, default: fuel] < fuel
        let needsAmmo = PlaytestRulebook.primaryAmmo(for: adjacent, ruleset: ruleset).map {
            unitAmmo[neighbor, default: $0] < $0
        } ?? false
        return needsHealth || needsFuel || needsAmmo
    }

    private func cpuTransportJoinPlans(at point: GridPoint, unit transport: Element) -> [CPUPlan] {
        guard let stats = PlaytestRulebook.stats(for: transport, ruleset: ruleset) else { return [] }
        return neighbors(of: point).filter { isValid($0) }.compactMap { neighbor in
            guard let candidate = unit(at: neighbor),
                  candidate.army == activeArmy,
                  candidate.simplified == transport.simplified,
                  unitHealth[point, default: 100] < 100 || unitHealth[neighbor, default: 100] < 100,
                  let path = cpuMovementPaths(from: point, unit: transport, stats: stats)[neighbor],
                  path.movement <= stats.move else { return nil }
            return CPUPlan(score: 96, action: .join(origin: point, destination: neighbor))
        }
    }

    func cpuBuildPlans() -> [CPUPlan] {
        var plans: [CPUPlan] = []
        guard !cpuPropertyPoints().isEmpty else { return plans }

        for point in cpuPropertyPoints() where !movedCells.contains(point) {
            guard cpuCanProduce(at: point) else { continue }
            let building = map.backgroundElement(atX: point.x, y: point.y)
            guard map.foregroundElement(atX: point.x, y: point.y) == .unitEmpty else { continue }
            guard unitCount(for: activeArmy) < PlaytestRulebook.unitCap(for: ruleset),
                  productionIsWithinHQArea(point) else { continue }

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

    /// Famicom-era production is tied to the HQ's local operating area. Keep
    /// this CPU-only gate separate from the shared editor command so maps can
    /// still be authored freely, while Famicom/Super Famicom playtests do not
    /// manufacture units from a remote captured facility.
    func cpuCanProduce(at point: GridPoint) -> Bool {
        let radius = cpuPolicy.hqProductionRadius
        guard let radius else { return true }

        let hqPoints = cpuPropertyPoints().filter {
            map.backgroundElement(atX: $0.x, y: $0.y).simplified == .buildingHQ
        }
        guard !hqPoints.isEmpty else { return true }
        return hqPoints.contains { hq in
            max(abs(hq.x - point.x), abs(hq.y - point.y)) <= radius
        }
    }

    func cpuBuildScore(_ option: PlaytestProductionOption, at point: GridPoint, building: Element) -> Double {
        guard let stats = PlaytestRulebook.stats(for: option.element, ruleset: ruleset) else { return -.greatestFiniteMagnitude }
        return cpuBuildScoreValue(option, at: point, building: building, stats: stats)
    }

    private func cpuBuildScoreValue(
        _ option: PlaytestProductionOption,
        at point: GridPoint,
        building: Element,
        stats: PlaytestUnitStats
    ) -> Double {
        let policy = cpuPolicy
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
        let repeatPenalty = option.element.simplified == .unitInfantry
            ? policy.infantryRepeatPenalty
            : policy.buildDiversityPenalty
        score -= Double(existingCount) * repeatPenalty

        // Keep a little cash in reserve for a counterattack or capture follow-
        // up, but permit expensive units when the treasury can support them.
        if Double(option.cost) > Double(activeFunds) * 0.75 { score -= 12 }
        return score
    }

    func cpuProductionPropertyScore(
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

    func cpuBuildRoleScore(
        for element: Element,
        stats: PlaytestUnitStats,
        ownCounts: [Int: Int],
        enemyDomains: (land: Int, air: Int, sea: Int),
        enemyPropertyCount: Int
    ) -> Double {
        let policy = cpuPolicy
        let type = element.simplified
        let captureUnits = ownCounts[Element.unitInfantry.value, default: 0]
            + ownCounts[Element.unitMech.value, default: 0]
        let desiredCaptureUnits = min(4, max(1, enemyPropertyCount))
        let captureNeed = max(0, desiredCaptureUnits - captureUnits)
        let landThreat = Double(enemyDomains.land)
        let airThreat = Double(enemyDomains.air)
        let seaThreat = Double(enemyDomains.sea)

        if PlaytestRulebook.resuppliesAdjacentUnits(element, ruleset: ruleset) {
            return policy.supplyActionMultiplier * (18 + min(36, landThreat * 5))
        }

        if ruleset == .famicomWars {
            return famicomBuildRoleScore(
                type: type,
                captureNeed: captureNeed,
                captureUnits: captureUnits,
                infantryCount: ownCounts[Element.unitInfantry.value, default: 0],
                enemyPropertyCount: enemyPropertyCount,
                landThreat: landThreat,
                airThreat: airThreat
            )
        }

        return genericBuildRoleScore(
            type: type,
            captureNeed: captureNeed,
            captureUnits: captureUnits,
            landThreat: landThreat,
            airThreat: airThreat,
            seaThreat: seaThreat,
            policy: policy,
            stats: stats
        )
    }

    func cpuUnitCounts() -> [Int: Int] {
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

    func cpuDomainCounts(for points: [GridPoint]) -> (land: Int, air: Int, sea: Int) {
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

    func cpuMovePlans() -> [CPUPlan] {
        var plans: [CPUPlan] = []
        for origin in cpuUnitPoints() where !movedCells.contains(origin) {
            let unit = map.foregroundElement(atX: origin.x, y: origin.y)
            guard let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset) else { continue }
            let paths = cpuMovementPaths(from: origin, unit: unit, stats: stats)
            for destination in paths.keys.sorted(by: gridPointOrder) {
                guard let path = paths[destination] else { continue }
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

    var usesFamicomTacticalPlanning: Bool {
        ruleset == .famicomWars
    }

    /// Keep a Famicom CPU's direct-objective horizon deliberately short. The
    /// original NES maps are compact, so a unit that can make contact in two
    /// turns should commit; a unit that is many turns away should not receive
    /// a giant score merely because its HQ is on the other side of a large
    /// editor map.
    func famicomTacticalHorizon(for stats: PlaytestUnitStats) -> Int {
        max(6, (stats.move * 2) + max(1, stats.maxRange))
    }

    /// Returns movement-point distance to one of the current Famicom
    /// objectives. This is a reverse flood fill over terrain, not a search for
    /// a legal turn: foreground units are ignored as blockers, while each
    /// unit's movement table and terrain placement rules remain authoritative.
    /// Caching one map per unit kind and objective keeps the per-action planner
    /// cheap even on a large custom map.
    func cpuTacticalDistance(
        for unit: Element,
        target: CPUTacticalTarget,
        from point: GridPoint
    ) -> Int {
        guard usesFamicomTacticalPlanning else { return .max }
        let key = CPUTacticalDistanceKey(unitValue: unit.simplified.value, target: target)
        if let cached = cpuTacticalDistanceCache[key] {
            return cached[point] ?? .max
        }

        let distances = cpuTacticalDistanceMap(for: unit, target: target)
        cpuTacticalDistanceCache[key] = distances
        return distances[point] ?? .max
    }

    func cpuTacticalDistanceMap(
        for unit: Element,
        target: CPUTacticalTarget
    ) -> [GridPoint: Int] {
        guard PlaytestRulebook.stats(for: unit, ruleset: ruleset) != nil else { return [:] }

        var distances: [GridPoint: Int] = [:]
        var frontier: [GridPoint] = []
        for point in cpuTacticalTargetPoints(for: target) where isValid(point) {
            guard distances[point] == nil else { continue }
            distances[point] = 0
            frontier.append(point)
        }

        var index = 0
        while index < frontier.count {
            let current = frontier[index]
            index += 1
            guard let currentDistance = distances[current] else { continue }
            expandTacticalDistance(from: current, distance: currentDistance, unit: unit, distances: &distances, frontier: &frontier)
        }
        return distances
    }

    private func expandTacticalDistance(
        from current: GridPoint,
        distance currentDistance: Int,
        unit: Element,
        distances: inout [GridPoint: Int],
        frontier: inout [GridPoint]
    ) {
        // Distances are expanded backwards from the objective. The first edge
        // may leave a hostile target's terrain, so use the neighbour's cost
        // when the current tile has no legal traversal cost.
        let currentCost = cpuTacticalTraversalCost(for: unit, at: current)
        for next in cardinalNeighbors(of: current) {
            guard isValid(next), let neighbourCost = cpuTacticalTraversalCost(for: unit, at: next) else { continue }
            let candidateDistance = currentDistance + (currentCost ?? neighbourCost)
            if candidateDistance < distances[next, default: .max] {
                distances[next] = candidateDistance
                frontier.append(next)
            }
        }
    }

}
