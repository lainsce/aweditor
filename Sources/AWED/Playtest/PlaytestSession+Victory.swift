import AppKit
import Observation
import SwiftUI
import AWEDCore

extension PlaytestSession {
    func pipeSeamDamage(from origin: GridPoint, to destination: GridPoint, attacker: Element) -> Int? {
        guard canAttackPipeSeam(from: origin, to: destination, attacker: attacker) else { return nil }
        return PlaytestRulebook.damage(
            attacker: attacker,
            defender: Element.unitInfantry,
            ruleset: ruleset,
            attackerHealth: unitHealth[origin, default: 100],
            defenderHealth: pipeSeamHealth[destination, default: Self.pipeSeamStartingHealth],
            terrain: .terrainSeam,
            primaryAmmo: unitAmmo[origin]
        )
    }

    func attackableCells(from origin: GridPoint, unit: Element) -> Set<GridPoint> {
        guard let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset),
              stats.maxRange > 0,
              (!movedCells.contains(origin) || stats.canMoveAndFire) else { return [] }
        let requiresVisibility = isFogOfWarActive || !submergedUnits.isEmpty || !stealthedUnits.isEmpty
        var result: Set<GridPoint> = []
        for x in 0..<map.width {
            for y in 0..<map.height {
                let point = GridPoint(x: x, y: y)
                let target = map.foregroundElement(atX: x, y: y)
                guard isWithinRange(from: origin, to: point, stats: stats) else { continue }

                if target.isUnitNonEmpty {
                    guard isHostile(target.army, unit.army),
                          (!requiresVisibility || isVisible(point)),
                          ((!submergedUnits.contains(point) && !stealthedUnits.contains(point)) ||
                            unit.simplified == .unitCruiser || unit.simplified == .unitSub),
                          PlaytestRulebook.canAttack(unit, target, ruleset: ruleset, primaryAmmo: unitAmmo[origin]) else { continue }
                    result.insert(point)
                } else if canAttackPipeSeam(from: origin, to: point, attacker: unit) {
                    // Pipe seams are known terrain objectives in Fog of War;
                    // unlike hidden units they do not require enemy vision.
                    result.insert(point)
                }
            }
        }
        return result
    }

    func attackRangeCells(from origin: GridPoint, unit: Element) -> Set<GridPoint> {
        guard let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset),
              stats.maxRange > 0,
              (!movedCells.contains(origin) || stats.canMoveAndFire) else { return [] }
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

    func isWithinRange(from origin: GridPoint, to destination: GridPoint, stats: PlaytestUnitStats?) -> Bool {
        guard let stats else { return false }
        let distance = distance(from: origin, to: destination)
        let weatherMaxRange = PlaytestRulebook.maximumAttackRange(
            for: stats,
            ruleset: ruleset,
            weather: weather
        )
        return distance >= stats.minRange && distance <= weatherMaxRange
    }

    func canCapture(unit: Element, stats: PlaytestUnitStats, at point: GridPoint) -> Bool {
        guard stats.canCapture else { return false }
        let building = map.backgroundElement(atX: point.x, y: point.y)
        return PlaytestRulebook.isCapturableBuilding(building, ruleset: ruleset) &&
            (building.army == AWConstants.armyNeutral || isHostile(building.army, activeArmy))
    }

    func collectIncome(for army: Int) {
        var income = 0
        for x in 0..<map.width {
            for y in 0..<map.height {
                let building = map.backgroundElement(atX: x, y: y)
                if building.isBuilding, building.army == army { income += PlaytestRulebook.income(for: building) }
            }
        }
        funds[army, default: 0] += income
    }

    func repairUnits(for army: Int) {
        for x in 0..<map.width {
            for y in 0..<map.height {
                repairUnit(at: GridPoint(x: x, y: y), for: army)
            }
        }
    }

    private func repairUnit(at point: GridPoint, for army: Int) {
        let unit = map.foregroundElement(atX: point.x, y: point.y)
        let building = map.backgroundElement(atX: point.x, y: point.y)
        guard unit.isUnitNonEmpty, unit.army == army, building.isBuilding, building.army == army,
              canRepair(unit, on: building) else { return }
        let currentHealth = unitHealth[point, default: 100]
        let requestedHP = min(2, max(0, 100 - currentHealth) / 10)
        let costPerHP = max(1, (PlaytestRulebook.stats(for: unit, ruleset: ruleset)?.cost ?? 0) / 10)
        let affordableHP = min(requestedHP, funds[army, default: 0] / costPerHP)
        unitHealth[point] = min(100, currentHealth + affordableHP * 10)
        funds[army, default: 0] -= affordableHP * costPerHP
        unitFuel[point] = PlaytestRulebook.maxFuel(for: unit, ruleset: ruleset)
        if let ammo = PlaytestRulebook.primaryAmmo(for: unit, ruleset: ruleset) { unitAmmo[point] = ammo }
    }

    func canRepair(_ unit: Element, on building: Element) -> Bool {
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

    func hasComTower(for army: Int) -> Bool {
        guard ruleset == .dualStrike || ruleset == .advanceWars2 else { return false }
        return allMapPoints().contains { point in
            let building = map.backgroundElement(atX: point.x, y: point.y)
            return building.simplified == .buildingTower && building.army == army
        }
    }

    @discardableResult
    func consumeDailyFuel(for army: Int) -> Int {
        var destroyed: [GridPoint] = []
        for x in 0..<map.width {
            for y in 0..<map.height {
                let point = GridPoint(x: x, y: y)
                let unit = map.foregroundElement(atX: x, y: y)
                guard unit.isUnitNonEmpty, unit.army == army,
                      let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset) else { continue }
                if let destroyedPoint = applyDailyFuel(to: point, unit: unit, stats: stats) {
                    destroyed.append(destroyedPoint)
                }
            }
        }
        guard !destroyed.isEmpty else { return 0 }
        removeFuelDestroyedUnits(at: destroyed)
        return destroyed.count
    }

    private func applyDailyFuel(to point: GridPoint, unit: Element, stats: PlaytestUnitStats) -> GridPoint? {
        let dailyFuelUse = unit.simplified == .unitSub && submergedUnits.contains(point) ? 5 : stats.dailyFuelUse
        guard dailyFuelUse > 0 else { return nil }
        let remaining = unitFuel[point, default: stats.maxFuel] - dailyFuelUse
        if remaining <= 0, stats.domain == .air || stats.domain == .sea { return point }
        unitFuel[point] = max(0, remaining)
        return nil
    }

    private func removeFuelDestroyedUnits(at points: [GridPoint]) {
        var candidate = map
        for point in points {
            let destroyedUnit = unit(at: point) ?? .unitEmpty
            recordDestroyedUnit(destroyedUnit)
            recordDestroyedCargo(at: point)
            _ = candidate.setForeground(.unitEmpty, atX: point.x, y: point.y)
            unitHealth.removeValue(forKey: point)
            unitFuel.removeValue(forKey: point)
            unitAmmo.removeValue(forKey: point)
            cargo.removeValue(forKey: point)
            submergedUnits.remove(point)
        }
        map = candidate
    }

    @discardableResult
    func processTurnStart(for army: Int) -> Int {
        collectIncome(for: army)
        repairUnits(for: army)
        refuelAdjacentUnits(for: army)
        resupplyCarriedAircraft(for: army)
        return consumeDailyFuel(for: army)
    }

    /// Older Wars cartridges end the battle as soon as an army has no units
    /// left, even if one of its bases is still open. Later rulesets retain the
    /// more forgiving property-only state until that production network is
    /// gone. In either case a defeated army surrenders every property; HQs
    /// become neutral cities so the map keeps a useful property tile instead
    /// of retaining a defeated HQ sprite.
    @discardableResult
    func resolveRouting() -> [Int] {
        guard winnerArmy == nil else { return [] }

        // Record this before checking for an empty army. This catches units
        // placed by the editor, produced during the match, or carried by a
        // transport before their eventual destruction.
        recordUnitPresence()
        let candidates = survivingArmies
        guard !candidates.isEmpty else { return [] }

        // Super Famicom Wars has one additional victory condition: a side
        // controlling at least 75% of the map's capturable properties wins
        // by Domination. Check it alongside routing so a capture resolves the
        // match immediately, without changing the victory rules of the other
        // cartridges.
        if resolveDominationVictory(for: candidates) {
            return []
        }
        var routed: [Int] = []

        for army in candidates {
            let hasNoUnits = !hasUnits(for: army)
            let hasNoProduction = !hasProductionProperty(for: army)
            let hasRouted = hasNoUnits &&
                (hasNoProduction ||
                    (usesUnitEliminationVictory && armiesThatHaveHadUnits.contains(army)))
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
        if candidates.count > 1, Set(survivors.map { team(for: $0) }).count == 1, let winner = survivors.first {
            winnerArmy = winner
            statusMessage = "\(armyName(winner)) routed all opponents and wins the playtest."
        } else if survivors.isEmpty {
            statusMessage = "No playable armies remain."
        } else {
            let names = routed.map { armyName($0) }.joined(separator: ", ")
            statusMessage = "\(names) was routed and its properties became neutral."
        }

        return routed
    }

    /// Resolves the Super Famicom Wars property-control victory condition.
    /// Allied armies share their property count because the playtest setup
    /// treats an alliance as one side for all victory checks. The denominator
    /// is every capturable property currently on the map, including neutral
    /// properties and HQs; neutralizing a defeated army therefore cannot make
    /// the threshold easier by removing a property from the map.
    func resolveDominationVictory(for candidates: [Int]) -> Bool {
        guard ruleset == .superFamicomWars else { return false }

        let candidateTeams = Set(candidates.map { team(for: $0) })
        guard candidates.count > 1, candidateTeams.count > 1 else { return false }
        let properties = dominationProperties()
        guard !properties.isEmpty else { return false }

        let activeTeam = team(for: activeArmy)
        guard let result = dominationWinner(candidates: candidates, properties: properties, activeTeam: activeTeam),
              let winner = candidates.first(where: { team(for: $0) == result.team }) else {
            return false
        }

        winnerArmy = winner
        statusMessage = "\(armyName(winner)) wins by Domination (\(result.count)/\(properties.count) properties)."
        return true
    }

    private func dominationProperties() -> [Element] {
        allMapPoints().compactMap { point in
            let building = map.backgroundElement(atX: point.x, y: point.y)
            return PlaytestRulebook.isCapturableBuilding(building, ruleset: ruleset) ? building : nil
        }
    }

    private func dominationWinner(
        candidates: [Int],
        properties: [Element],
        activeTeam: PlaytestTeam
    ) -> (team: PlaytestTeam, count: Int)? {
        var evaluatedTeams: Set<PlaytestTeam> = []
        var winner: (team: PlaytestTeam, count: Int)?
        for army in candidates {
            let candidateTeam = team(for: army)
            guard evaluatedTeams.insert(candidateTeam).inserted else { continue }
            let owned = dominationPropertyCount(properties, candidates: candidates, team: candidateTeam)
            guard owned * 100 >= properties.count * 75 else { continue }
            winner = preferredDominationWinner(current: winner, candidate: (candidateTeam, owned), activeTeam: activeTeam)
        }
        return winner
    }

    private func preferredDominationWinner(
        current: (team: PlaytestTeam, count: Int)?,
        candidate: (team: PlaytestTeam, count: Int),
        activeTeam: PlaytestTeam
    ) -> (team: PlaytestTeam, count: Int) {
        guard let current else { return candidate }
        return dominationCandidateIsPreferred(candidate, over: current, activeTeam: activeTeam) ? candidate : current
    }

    private func dominationCandidateIsPreferred(
        _ candidate: (team: PlaytestTeam, count: Int),
        over current: (team: PlaytestTeam, count: Int),
        activeTeam: PlaytestTeam
    ) -> Bool {
        guard candidate.count == current.count else { return candidate.count > current.count }
        return candidate.team == activeTeam && current.team != activeTeam
    }

    private func dominationPropertyCount(_ properties: [Element], candidates: [Int], team candidateTeam: PlaytestTeam) -> Int {
        properties.reduce(into: 0) { count, building in
            if building.army != AWConstants.armyNeutral,
               candidates.contains(building.army),
               team(for: building.army) == candidateTeam {
                count += 1
            }
        }
    }

    var usesUnitEliminationVictory: Bool {
        switch ruleset {
        case .famicomWars, .superFamicomWars:
            return true
        default:
            return false
        }
    }

    func hasUnits(for army: Int) -> Bool {
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

    func recordUnitPresence() {
        for x in 0..<map.width {
            for y in 0..<map.height {
                let unit = map.foregroundElement(atX: x, y: y)
                guard unit.isUnitNonEmpty,
                      PlaytestRulebook.stats(for: unit, ruleset: ruleset) != nil else { continue }
                armiesThatHaveHadUnits.insert(unit.army)
            }
        }

        for payloads in cargo.values {
            for payload in payloads where PlaytestRulebook.stats(for: payload.unit, ruleset: ruleset) != nil {
                armiesThatHaveHadUnits.insert(payload.unit.army)
            }
        }
    }

    func recordDestroyedUnit(_ unit: Element) {
        guard unit.isUnitNonEmpty else { return }
        destroyedUnitCounts[unit.army, default: 0] += 1
    }

    func recordDestroyedCargo(at point: GridPoint) {
        for payload in cargo[point, default: []] {
            recordDestroyedUnit(payload.unit)
        }
    }

    func unitCount(for army: Int) -> Int {
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

    func hasProductionProperty(for army: Int) -> Bool {
        for x in 0..<map.width {
            for y in 0..<map.height {
                let building = map.backgroundElement(atX: x, y: y)
                guard building.isBuilding, building.army == army else { continue }
                // Routing asks whether the army still owns a property that
                // can produce units in this ruleset. It must not depend on
                // the tile being empty right now, or on the CPU's local HQ
                // build-radius heuristic: a unit can move off the property
                // and the CPU restriction is enforced separately by
                // `cpuCanProduce`/`productionIsWithinHQArea`.
                if !PlaytestRulebook.productionOptions(
                    for: building,
                    ruleset: ruleset,
                    tileset: map.tileset
                ).isEmpty { return true }
            }
        }
        return false
    }

    func neutralizeProperties(of army: Int) {
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
}
