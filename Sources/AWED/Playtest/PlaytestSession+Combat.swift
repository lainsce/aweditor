import AppKit
import Observation
import SwiftUI
import AWEDCore

private struct PlaytestAttackContext {
    let origin: GridPoint
    let destination: GridPoint
    let attacker: Element
    let defender: Element
    let defenderStats: PlaytestUnitStats
    let damage: Int
    let defenderHealth: Int
    let defenderAmmo: Int?
}

private struct PlaytestAttackResolution {
    let damage: Int
    let attackerDestroyed: Bool
    let counterattackText: String
}

extension PlaytestSession {
    func attack(to destination: GridPoint) {
        guard let origin = selectedPoint,
              let attacker = unit(at: origin),
              let attackerStats = PlaytestRulebook.stats(for: attacker, ruleset: ruleset) else {
            statusMessage = "That target cannot be attacked by this unit."
            return
        }
        if tryAttackPipeSeam(from: origin, to: destination, attacker: attacker) { return }
        guard let context = makeAttackContext(
            from: origin,
            to: destination,
            attacker: attacker,
            attackerStats: attackerStats
        ) else {
            statusMessage = "That target cannot be attacked by this unit."
            return
        }

        let result = resolveUnitAttack(context)
        clearSelection()
        statusMessage = "\(PaletteCatalog.label(for: attacker, tileset: map.tileset)) dealt \(result.damage) damage to \(PaletteCatalog.label(for: context.defender, tileset: map.tileset))." + result.counterattackText
        _ = resolveRouting()
    }

    private func tryAttackPipeSeam(from origin: GridPoint, to destination: GridPoint, attacker: Element) -> Bool {
        guard unit(at: destination) == nil, isPipeSeam(at: destination) else { return false }
        guard canAttackPipeSeam(from: origin, to: destination, attacker: attacker) else {
            statusMessage = "That target cannot be attacked by this unit."
            return true
        }
        attackPipeSeam(from: origin, to: destination, attacker: attacker)
        return true
    }

    private func makeAttackContext(
        from origin: GridPoint,
        to destination: GridPoint,
        attacker: Element,
        attackerStats: PlaytestUnitStats
    ) -> PlaytestAttackContext? {
        guard let defender = unit(at: destination),
              let defenderStats = PlaytestRulebook.stats(for: defender, ruleset: ruleset),
              canAttackAfterMovement(attackerStats, from: origin),
              canSeeAttackTarget(attacker, at: destination),
              PlaytestRulebook.canAttack(attacker, defender, ruleset: ruleset, primaryAmmo: unitAmmo[origin]),
              var damage = PlaytestRulebook.damage(
                attacker: attacker,
                defender: defender,
                ruleset: ruleset,
                attackerHealth: unitHealth[origin, default: 100],
                defenderHealth: unitHealth[destination, default: 100],
                terrain: map.backgroundElement(atX: destination.x, y: destination.y),
                primaryAmmo: unitAmmo[origin]
              ) else { return nil }

        if hasComTower(for: attacker.army) {
            damage = min(100, Int((Double(damage) * 1.10).rounded(.down)))
        }
        return PlaytestAttackContext(
            origin: origin,
            destination: destination,
            attacker: attacker,
            defender: defender,
            defenderStats: defenderStats,
            damage: damage,
            defenderHealth: unitHealth[destination, default: 100],
            defenderAmmo: unitAmmo[destination]
        )
    }

    private func canAttackAfterMovement(_ stats: PlaytestUnitStats, from origin: GridPoint) -> Bool {
        !movedCells.contains(origin) || stats.canMoveAndFire
    }

    private func canSeeAttackTarget(_ attacker: Element, at destination: GridPoint) -> Bool {
        !submergedUnits.contains(destination) && !stealthedUnits.contains(destination) ||
            attacker.simplified == .unitCruiser || attacker.simplified == .unitSub
    }

    private func resolveUnitAttack(_ context: PlaytestAttackContext) -> PlaytestAttackResolution {
        consumePrimaryAmmo(for: context.attacker, against: context.defender, at: context.origin)
        var candidate = map
        let defenderDestroyed = applyDamage(
            context.damage,
            to: context.destination,
            unit: context.defender,
            candidate: &candidate
        )
        let counterattack = resolveCounterattack(
            for: context,
            defenderDestroyed: defenderDestroyed,
            candidate: &candidate
        )
        map = candidate
        if !counterattack.attackerDestroyed { movedCells.insert(context.origin) }
        return PlaytestAttackResolution(
            damage: context.damage,
            attackerDestroyed: counterattack.attackerDestroyed,
            counterattackText: counterattack.text
        )
    }

    private func consumePrimaryAmmo(for attacker: Element, against defender: Element, at origin: GridPoint) {
        guard PlaytestRulebook.usesPrimaryWeapon(
            attacker,
            defender,
            ruleset: ruleset,
            primaryAmmo: unitAmmo[origin]
        ), let currentAmmo = unitAmmo[origin] else { return }
        unitAmmo[origin] = max(0, currentAmmo - 1)
    }

    @discardableResult
    private func applyDamage(
        _ damage: Int,
        to point: GridPoint,
        unit: Element,
        candidate: inout MapState
    ) -> Bool {
        let remainingHealth = unitHealth[point, default: 100] - damage
        guard remainingHealth > 0 else {
            removeDefeatedUnit(unit, at: point, from: &candidate)
            return true
        }
        unitHealth[point] = remainingHealth
        return false
    }

    private func resolveCounterattack(
        for context: PlaytestAttackContext,
        defenderDestroyed: Bool,
        candidate: inout MapState
    ) -> (attackerDestroyed: Bool, text: String) {
        guard canCounterattack(context, defenderDestroyed: defenderDestroyed),
              let counterDamage = counterattackDamage(for: context),
              isWithinRange(from: context.destination, to: context.origin, stats: context.defenderStats) else {
            return (false, "")
        }

        consumeCounterattackAmmo(for: context, defenderDestroyed: defenderDestroyed)
        let attackerRemainingHealth = unitHealth[context.origin, default: 100] - counterDamage
        guard attackerRemainingHealth > 0 else {
            removeDefeatedUnit(context.attacker, at: context.origin, from: &candidate)
            return (true, " The defender destroyed the attacker in the counterattack.")
        }
        unitHealth[context.origin] = attackerRemainingHealth
        return (false, " Counterattack dealt \(counterDamage) damage.")
    }

    private func canCounterattack(_ context: PlaytestAttackContext, defenderDestroyed: Bool) -> Bool {
        let simultaneous = PlaytestRulebook.counterattackUsesStartingStrength(ruleset)
        guard !defenderDestroyed || simultaneous, context.defenderStats.canCounterattack else { return false }
        return canSeeAttackTarget(context.defender, at: context.origin)
    }

    private func counterattackDamage(for context: PlaytestAttackContext) -> Int? {
        let simultaneous = PlaytestRulebook.counterattackUsesStartingStrength(ruleset)
        return PlaytestRulebook.damage(
            attacker: context.defender,
            defender: context.attacker,
            ruleset: ruleset,
            attackerHealth: simultaneous ? context.defenderHealth : unitHealth[context.destination, default: 100],
            defenderHealth: unitHealth[context.origin, default: 100],
            terrain: map.backgroundElement(atX: context.origin.x, y: context.origin.y),
            primaryAmmo: context.defenderAmmo
        )
    }

    private func consumeCounterattackAmmo(for context: PlaytestAttackContext, defenderDestroyed: Bool) {
        guard !defenderDestroyed,
              PlaytestRulebook.usesPrimaryWeapon(
                context.defender,
                context.attacker,
                ruleset: ruleset,
                primaryAmmo: context.defenderAmmo
              ),
              let currentAmmo = context.defenderAmmo else { return }
        unitAmmo[context.destination] = max(0, currentAmmo - 1)
    }

    private func removeDefeatedUnit(_ unit: Element, at point: GridPoint, from candidate: inout MapState) {
        recordDestroyedUnit(unit)
        recordDestroyedCargo(at: point)
        _ = candidate.setForeground(.unitEmpty, atX: point.x, y: point.y)
        unitHealth.removeValue(forKey: point)
        unitFuel.removeValue(forKey: point)
        unitAmmo.removeValue(forKey: point)
        cargo.removeValue(forKey: point)
        submergedUnits.remove(point)
        stealthedUnits.remove(point)
        captureProgress.removeValue(forKey: point)
    }

    func attackPipeSeam(from origin: GridPoint, to destination: GridPoint, attacker: Element) {
        guard let damage = pipeSeamDamage(from: origin, to: destination, attacker: attacker) else {
            statusMessage = "That target cannot be attacked by this unit."
            return
        }

        consumePrimaryAmmo(for: attacker, against: Element.unitInfantry, at: origin)
        let remainingHealth = pipeSeamHealth[destination, default: Self.pipeSeamStartingHealth] - damage
        movedCells.insert(origin)
        if remainingHealth <= 0 {
            guard destroyPipeSeam(at: destination, attacker: attacker) else { return }
        } else {
            pipeSeamHealth[destination] = remainingHealth
            clearSelection()
            statusMessage = "\(PaletteCatalog.label(for: attacker, tileset: map.tileset)) damaged the pipe seam (\(remainingHealth) HP remaining)."
        }
        _ = resolveRouting()
    }

    @discardableResult
    private func destroyPipeSeam(at destination: GridPoint, attacker: Element) -> Bool {
        var candidate = map
        guard candidate.setBackground(.terrainPlain, atX: destination.x, y: destination.y, check: false) else {
            statusMessage = "That pipe seam could not be destroyed."
            return false
        }
        map = candidate
        pipeSeamHealth.removeValue(forKey: destination)
        clearSelection()
        statusMessage = "\(PaletteCatalog.label(for: attacker, tileset: map.tileset)) destroyed the pipe seam."
        return true
    }
}
