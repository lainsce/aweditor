import AppKit
import Observation
import SwiftUI
import AWEDCore

private struct CPUMoveScoreMetrics {
    let distanceGain: Int
    let propertyDistanceGain: Int
    let hqDistanceGain: Int
    let afterEnemy: Int
    let afterProperty: Int
    let afterHQ: Int
    let terrain: Element
    let terrainStars: Int
    let threat: Int
    let propertyValue: Double
    let attackOpportunity: Double
    let propertyApproachBonus: Double
    let supplyObjective: Double
    let transportObjective: Double
    let contact: (approachBonus: Double, attackWindowBonus: Double, threatWeight: Double)
}

extension PlaytestSession {
    func cpuTacticalTargetPoints(for target: CPUTacticalTarget) -> [GridPoint] {
        switch target {
        case .enemyUnit:
            return allEnemyUnitPoints()
        case .enemyProperty:
            return enemyPropertyPoints()
        case .enemyHQ:
            return cpuPlanningSnapshot?.enemyHQPoints ?? allMapPoints().filter { point in
                let building = map.backgroundElement(atX: point.x, y: point.y)
                return building.simplified == .buildingHQ && isHostile(building.army, activeArmy)
            }
        }
    }

    func cpuTacticalTraversalCost(for unit: Element, at point: GridPoint) -> Int? {
        let terrain = map.backgroundElement(atX: point.x, y: point.y)
        guard !terrain.isExtra,
              let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset),
              let cost = PlaytestRulebook.movementCost(
                  for: unit,
                  stats: stats,
                  terrain: terrain,
                  ruleset: ruleset,
                  weather: weather,
                  tileset: map.tileset
              ),
              map.allowPlacement(unit, atX: point.x, y: point.y) else { return nil }
        return cost
    }

    func cpuMoveScore(unit: Element, origin: GridPoint, destination: GridPoint, movement: Int) -> Double {
        guard let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset) else { return -.greatestFiniteMagnitude }
        let policy = cpuPolicy
        let metrics = cpuMoveScoreMetrics(for: unit, stats: stats, origin: origin, destination: destination, policy: policy)
        if cpuShouldWait(
            unit: unit,
            origin: origin,
            propertyValue: metrics.propertyValue,
            supplyObjective: metrics.supplyObjective,
            transportObjective: metrics.transportObjective,
            attackOpportunity: metrics.attackOpportunity
        ) {
            return -Double(movement) - Double(metrics.threat) * metrics.contact.threatWeight
        }
        return cpuMoveScoreValue(metrics, stats: stats, movement: movement, horizon: famicomTacticalHorizon(for: stats))
    }

    private func cpuMoveScoreMetrics(
        for unit: Element,
        stats: PlaytestUnitStats,
        origin: GridPoint,
        destination: GridPoint,
        policy: PlaytestRulebook.CPUPolicy
    ) -> CPUMoveScoreMetrics {
        let distanceGain = cpuDistanceGain(for: unit, target: .enemyUnit, from: origin, to: destination)
        let propertyDistanceGain = cpuDistanceGain(for: unit, target: .enemyProperty, from: origin, to: destination)
        let hqDistanceGain = cpuDistanceGain(for: unit, target: .enemyHQ, from: origin, to: destination)
        let after = cpuDistance(for: unit, target: .enemyUnit, from: destination)
        let afterProperty = cpuDistance(for: unit, target: .enemyProperty, from: destination)
        let afterHQ = cpuDistance(for: unit, target: .enemyHQ, from: destination)
        let terrain = map.backgroundElement(atX: destination.x, y: destination.y)
        let terrainStars = PlaytestRulebook.terrainStars(for: terrain, ruleset: ruleset)
        let threat = cpuThreat(for: unit, at: destination)
        let propertyValue = cpuCaptureValue(stats: stats, terrain: terrain, at: destination)

        let attackOpportunity = cpuAdjacentAttackValue(for: unit, at: destination)
        let supplyObjective = cpuSupplyPropertyScore(for: unit, origin: origin, at: destination)
        let transportObjective = cpuTransportObjectiveScore(
            for: unit,
            origin: origin,
            destination: destination
        )
        let contact = cpuContactBonuses(for: unit, stats: stats, distance: after, at: destination, policy: policy)
        return CPUMoveScoreMetrics(
            distanceGain: distanceGain,
            propertyDistanceGain: propertyDistanceGain,
            hqDistanceGain: hqDistanceGain,
            afterEnemy: after,
            afterProperty: afterProperty,
            afterHQ: afterHQ,
            terrain: terrain,
            terrainStars: terrainStars,
            threat: threat,
            propertyValue: propertyValue,
            attackOpportunity: attackOpportunity,
            propertyApproachBonus: cpuPropertyApproachBonus(
                stats: stats,
                distanceGain: propertyDistanceGain,
                distance: afterProperty,
                horizon: famicomTacticalHorizon(for: stats),
                policy: policy
            ),
            supplyObjective: supplyObjective,
            transportObjective: transportObjective,
            contact: contact
        )
    }

    private func cpuMoveScoreValue(
        _ metrics: CPUMoveScoreMetrics,
        stats: PlaytestUnitStats,
        movement: Int,
        horizon: Int
    ) -> Double {
        // Bean Island is a direct HQ race. Capture units are the decisive
        // resource, so favour the opposing HQ corridor only once it is a
        // near-term route. A distant HQ should not pull a unit across the
        // whole editor canvas simply because Manhattan distance decreases.
        let hqApproachBonus = ruleset == .famicomWars && metrics.afterHQ <= horizon
            ? Double(metrics.hqDistanceGain) * (stats.canCapture ? 400 : 200) : 0
        let threatPenalty = Double(metrics.threat) * metrics.contact.threatWeight
        let defensiveValue = Double(metrics.terrainStars) * 5
        let movementCost = Double(movement) * 2
        return 8 + Double(metrics.distanceGain) * 22 + metrics.propertyValue + metrics.propertyApproachBonus
            + metrics.attackOpportunity + defensiveValue + metrics.supplyObjective + metrics.transportObjective
            + metrics.contact.approachBonus + metrics.contact.attackWindowBonus + hqApproachBonus - movementCost - threatPenalty
    }

    private func cpuDistance(for unit: Element, target: CPUTacticalTarget, from point: GridPoint) -> Int {
        guard usesFamicomTacticalPlanning else {
            switch target {
            case .enemyUnit: return nearestEnemyDistance(from: point)
            case .enemyProperty: return nearestEnemyPropertyDistance(from: point)
            case .enemyHQ: return nearestEnemyHQDistance(from: point)
            }
        }
        return cpuTacticalDistance(for: unit, target: target, from: point)
    }

    private func cpuDistanceGain(for unit: Element, target: CPUTacticalTarget, from origin: GridPoint, to destination: GridPoint) -> Int {
        let before = cpuDistance(for: unit, target: target, from: origin)
        let after = cpuDistance(for: unit, target: target, from: destination)
        return before == .max || after == .max ? 0 : before - after
    }

    private func cpuCaptureValue(stats: PlaytestUnitStats, terrain: Element, at point: GridPoint) -> Double {
        guard stats.canCapture,
              PlaytestRulebook.isCapturableBuilding(terrain, ruleset: ruleset),
              terrain.army == AWConstants.armyNeutral || isHostile(terrain.army, activeArmy) else { return 0 }
        return captureScore(at: point) * 0.85
    }

    private func cpuPropertyApproachBonus(
        stats: PlaytestUnitStats,
        distanceGain: Int,
        distance: Int,
        horizon: Int,
        policy: PlaytestRulebook.CPUPolicy
    ) -> Double {
        guard stats.canCapture, distance != .max,
              !usesFamicomTacticalPlanning || distance <= horizon else { return 0 }
        let urgency = Double(max(0, 7 - distance)) * 6
        return (Double(distanceGain) * 24 + urgency) * policy.propertyApproachMultiplier
    }

    private func cpuContactBonuses(
        for unit: Element,
        stats: PlaytestUnitStats,
        distance: Int,
        at destination: GridPoint,
        policy: PlaytestRulebook.CPUPolicy
    ) -> (approachBonus: Double, attackWindowBonus: Double, threatWeight: Double) {
        let turns = cpuTurnsToEngagement(for: unit, at: destination, stats: stats)
        let isTwoTurnApproach = stats.attackPower > 0 && turns <= 2
        let threatWeight = (isTwoTurnApproach ? 0.45 : 1.25) * policy.threatMultiplier
        let approachBonus = isTwoTurnApproach ? (55.0 + Double(stats.attackPower) * 2.2) * policy.contactMultiplier : 0
        let attackWindowBonus = stats.attackPower > 0 && distance <= stats.maxRange + stats.move
            ? (35.0 + Double(stats.attackPower) * 0.6) * policy.contactMultiplier : 0
        return (approachBonus, attackWindowBonus, threatWeight)
    }

    private func cpuShouldWait(
        unit: Element,
        origin: GridPoint,
        propertyValue: Double,
        supplyObjective: Double,
        transportObjective: Double,
        attackOpportunity: Double
    ) -> Bool {
        guard usesFamicomTacticalPlanning else { return false }
        let hasReachableObjective = cpuDistance(for: unit, target: .enemyUnit, from: origin) != .max ||
            cpuDistance(for: unit, target: .enemyProperty, from: origin) != .max ||
            cpuDistance(for: unit, target: .enemyHQ, from: origin) != .max
        return !hasReachableObjective && propertyValue == 0 && supplyObjective == 0 &&
            transportObjective == 0 && attackOpportunity == 0
    }

    func cpuSupplyPropertyScore(for unit: Element, origin: GridPoint, at point: GridPoint) -> Double {
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

    func cpuTransportObjectiveScore(for transport: Element, origin: GridPoint, destination: GridPoint) -> Double {
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

}
