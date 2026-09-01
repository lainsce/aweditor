import AppKit
import Observation
import SwiftUI
import AWEDCore

extension PlaytestSession {
    func cpuSpecialPlans() -> [CPUPlan] {
        var plans: [CPUPlan] = []
        for point in cpuUnitPoints() where !movedCells.contains(point) {
            let unit = map.foregroundElement(atX: point.x, y: point.y)
            switch unit.simplified {
            case .unitBlackBomb:
                let hostileCount = neighbors(of: point).filter { neighbor in
                    guard let target = self.unit(at: neighbor) else { return false }
                    return isHostile(target.army, activeArmy)
                }.count
                if hostileCount > 0 {
                    plans.append(CPUPlan(score: 620 + Double(hostileCount * 160), action: .detonate(point: point)))
                }
            case .unitOozium where ruleset == .daysOfRuin && isFogOfWarActive:
                plans.append(CPUPlan(score: 120, action: .flare(point: point)))
            case .unitStealth where !stealthedUnits.contains(point):
                let threat = cpuThreat(for: unit, at: point)
                if threat > 0 {
                    plans.append(CPUPlan(score: 80 + Double(threat) * 0.25, action: .stealth(point: point)))
                }
            default:
                break
            }
        }
        return plans
    }

    func cpuTransportDropOffs(for transport: Element, cargo: Element) -> [GridPoint] {
        let key = CPUTransportKey(transportValue: transport.simplified.value, cargoValue: cargo.simplified.value)
        if let cached = cpuTransportDropOffCache[key] { return cached }

        let points = allMapPoints().filter { canUnload(cargo, from: transport, at: $0) }
        cpuTransportDropOffCache[key] = points
        return points
    }

    func cpuTurnsToEngagement(for unit: Element, at point: GridPoint, stats: PlaytestUnitStats) -> Int {
        guard stats.attackPower > 0, stats.maxRange > 0 else { return .max }
        let nearestDistance = usesFamicomTacticalPlanning
            ? cpuTacticalDistance(for: unit, target: .enemyUnit, from: point)
            : nearestEnemyDistance(from: point)
        let closestDistance = nearestDistance == .max ? Int.max : max(0, nearestDistance - stats.maxRange)
        guard closestDistance != .max else { return .max }
        let movementPerTurn = max(1, stats.move)
        return (closestDistance + movementPerTurn - 1) / movementPerTurn
    }

    func cpuWaitPlans() -> [CPUPlan] {
        cpuUnitPoints()
            .filter { !movedCells.contains($0) }
            .map { CPUPlan(score: 0, action: .wait(point: $0)) }
    }

    func cpuThreat(for unit: Element, at point: GridPoint) -> Int {
        let key = CPUThreatKey(unitValue: unit.simplified.value, point: point, health: unitHealth[point, default: 100])
        if let cached = cpuThreatCache[key] { return cached }

        let defenderTerrain = map.backgroundElement(atX: point.x, y: point.y)
        var threat = 0
        for enemyInfo in cpuEnemyUnits() {
            let enemyPoint = enemyInfo.point
            let enemy = enemyInfo.unit
            let enemyStats = enemyInfo.stats
            guard isWithinRange(from: enemyPoint, to: point, stats: enemyStats),
                  PlaytestRulebook.canAttack(enemy, unit, ruleset: ruleset, primaryAmmo: unitAmmo[enemyPoint]),
                  let damage = PlaytestRulebook.damage(
                      attacker: enemy,
                      defender: unit,
                      ruleset: ruleset,
                      attackerHealth: unitHealth[enemyPoint, default: 100],
                      defenderHealth: unitHealth[point, default: 100],
                      terrain: defenderTerrain,
                      primaryAmmo: unitAmmo[enemyPoint],
                      randomize: false
                  ) else { continue }
            threat = min(180, threat + max(1, damage))
        }
        cpuThreatCache[key] = threat
        return threat
    }

    func cpuAdjacentAttackValue(for unit: Element, at point: GridPoint) -> Double {
        guard let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset), stats.maxRange > 0 else { return 0 }
        let nearest = usesFamicomTacticalPlanning
            ? cpuTacticalDistance(for: unit, target: .enemyUnit, from: point)
            : nearestEnemyDistance(from: point)
        guard nearest >= stats.minRange,
              nearest <= PlaytestRulebook.maximumAttackRange(for: stats, ruleset: ruleset, weather: weather) else { return 0 }
        let proximityBonus = Double(max(0, 8 - nearest)) * 10
        return (125 + (Double(stats.attackPower) * 0.65) + proximityBonus) * cpuPolicy.contactMultiplier
    }

    func cpuDestinationScore(for unit: Element, at point: GridPoint) -> Double {
        let policy = cpuPolicy
        let enemyDistance = usesFamicomTacticalPlanning
            ? cpuTacticalDistance(for: unit, target: .enemyUnit, from: point)
            : nearestEnemyDistance(from: point)
        let proximity = enemyDistance == Int.max ? 0 : max(0, 8 - enemyDistance)
        let threatPenalty = min(Double(cpuThreat(for: unit, at: point)) * 0.6 * policy.threatMultiplier, 90)
        return 20 + Double(proximity) * 3 * policy.contactMultiplier - threatPenalty
    }

    func allEnemyUnitPoints() -> [GridPoint] {
        if let snapshot = cpuPlanningSnapshot { return snapshot.enemyUnitPoints }
        return allMapPoints().filter { point in
            let unit = map.foregroundElement(atX: point.x, y: point.y)
            return unit.isUnitNonEmpty && isHostile(unit.army, activeArmy) &&
                PlaytestRulebook.stats(for: unit, ruleset: ruleset) != nil
        }
    }

    func cpuEnemyUnits() -> [CPUEnemyInfo] {
        if let snapshot = cpuPlanningSnapshot { return snapshot.enemyUnits }
        return allEnemyUnitPoints().compactMap { point in
            let enemy = map.foregroundElement(atX: point.x, y: point.y)
            guard let stats = PlaytestRulebook.stats(for: enemy, ruleset: ruleset) else { return nil }
            return CPUEnemyInfo(point: point, unit: enemy, stats: stats)
        }
    }

    func enemyPropertyPoints() -> [GridPoint] {
        if let snapshot = cpuPlanningSnapshot { return snapshot.enemyPropertyPoints }
        return allMapPoints().filter { point in
            let building = map.backgroundElement(atX: point.x, y: point.y)
            return PlaytestRulebook.isCapturableBuilding(building, ruleset: ruleset) &&
                (building.army == AWConstants.armyNeutral || isHostile(building.army, activeArmy))
        }
    }

    func nearestEnemyDistance(from point: GridPoint) -> Int {
        if let cached = cpuNearestEnemyDistanceCache[point] { return cached }
        let nearest = allEnemyUnitPoints().map { distance(from: point, to: $0) }.min() ?? .max
        if cpuPlanningSnapshot != nil { cpuNearestEnemyDistanceCache[point] = nearest }
        return nearest
    }

    func nearestEnemyPropertyDistance(from point: GridPoint) -> Int {
        if let cached = cpuNearestEnemyPropertyDistanceCache[point] { return cached }
        let nearest = enemyPropertyPoints().map { distance(from: point, to: $0) }.min() ?? .max
        if cpuPlanningSnapshot != nil { cpuNearestEnemyPropertyDistanceCache[point] = nearest }
        return nearest
    }

    func nearestEnemyHQDistance(from point: GridPoint) -> Int {
        let points = cpuPlanningSnapshot?.enemyHQPoints ?? allMapPoints().filter {
            let building = map.backgroundElement(atX: $0.x, y: $0.y)
            return building.simplified == .buildingHQ && isHostile(building.army, activeArmy)
        }
        return points.map { distance(from: point, to: $0) }.min() ?? .max
    }

    func nearestFriendlyPropertyPoint() -> GridPoint {
        cpuPropertyPoints().first ?? GridPoint(x: 0, y: 0)
    }

    func distance(from first: GridPoint, to second: GridPoint) -> Int {
        abs(first.x - second.x) + abs(first.y - second.y)
    }

    func isCPUArmy(_ army: Int) -> Bool {
        cpuArmies.contains(army)
    }

    func nextSurvivingArmy(after army: Int) -> Int? {
        guard !armies.isEmpty else { return nil }
        let startIndex = armies.firstIndex(of: army) ?? -1
        for offset in 1...armies.count {
            let index = (startIndex + offset) % armies.count
            let candidate = armies[index]
            if !defeatedArmies.contains(candidate) { return candidate }
        }
        return nil
    }

    func unit(at point: GridPoint) -> Element? {
        let unit = map.foregroundElement(atX: point.x, y: point.y)
        return unit.isUnitNonEmpty ? unit : nil
    }
}
