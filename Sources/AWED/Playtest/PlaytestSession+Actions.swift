import AppKit
import Observation
import SwiftUI
import AWEDCore

extension PlaytestSession {
    var selectedTransportIsBlackBoat: Bool {
        guard let selectedPoint else { return false }
        return unit(at: selectedPoint)?.simplified == .unitBlackBoat
    }

    func unitName(at point: GridPoint) -> String? {
        guard let unit = unit(at: point) else { return nil }
        return PaletteCatalog.label(for: unit, tileset: map.tileset)
    }

    var selectedBuildingName: String? {
        guard let selectedPoint,
              map.foregroundElement(atX: selectedPoint.x, y: selectedPoint.y) == .unitEmpty else { return nil }
        let building = map.backgroundElement(atX: selectedPoint.x, y: selectedPoint.y)
        return building.isBuilding ? PaletteCatalog.label(for: building, tileset: map.tileset) : nil
    }

    var selectedBuildingOwnerName: String? {
        guard let selectedPoint else { return nil }
        let building = map.backgroundElement(atX: selectedPoint.x, y: selectedPoint.y)
        guard building.isBuilding else { return nil }
        return armyName(building.army)
    }

    var selectedCaptureProgress: String? {
        guard let selectedPoint, captureProgress[selectedPoint] != nil else { return nil }
        return "Capture progress: \(captureProgress[selectedPoint, default: 0])/20"
    }

    func restart() {
        stopCPU()
        map = sourceMap
        activeArmy = playerArmy ?? armies.first ?? AWConstants.armyOrangeStar
        cursorPoint = Self.initialCursor(in: map, army: activeArmy)
        cpuActionPoint = nil
        turn = 1
        weatherMode = initialWeather
        weather = initialWeather
        fogOfWarEnabled = false
        funds = Dictionary(uniqueKeysWithValues: armies.map { ($0, 10_000) })
        initializeUnitResources()
        initializePipeSeams()
        armiesThatHaveHadUnits.removeAll()
        destroyedUnitCounts.removeAll()
        recordUnitPresence()
        captureProgress.removeAll()
        cargo.removeAll()
        selectedCargoIndex = 0
        submergedUnits.removeAll()
        stealthedUnits.removeAll()
        flareRevealCells.removeAll()
        usedMissileSilos.removeAll()
        isSelectingSiloTarget = false
        siloTargetCells.removeAll()
        winnerArmy = nil
        defeatedArmies.removeAll()
        movedCells.removeAll()
        clearCPUMovementPreview()
        clearSelection()
        statusMessage = armies.isEmpty
            ? "No playable armies are placed on this map yet."
            : "Select a \(armyName(activeArmy)) unit to begin."
        hasStarted = true
        _ = processTurnStart(for: activeArmy)
        _ = resolveRouting()
        runCPUIfNeeded()
    }

    func stopCPU() {
        cpuRunID = UUID()
        cpuTask?.cancel()
        cpuTask = nil
        isExecutingCPU = false
        cpuActionPoint = nil
        clearCPUMovementPreview()
        playerMovementTask?.cancel()
        playerMovementTask = nil
        isAnimatingPlayerMovement = false
        playerMovementPath.removeAll(keepingCapacity: true)
        playerMovementAnimation = nil
        cpuMovementAnimation = nil
    }

    func handleTap(_ point: GridPoint) {
        guard isValid(point), !isGameOver else { return }
        cursorPoint = point
        guard !isCPUArmy(activeArmy) else {
            statusMessage = "\(activeArmyName) is controlled by the CPU."
            return
        }

        clearAttackPreview()
        clearPlayerMovementPreview()

        if isSelectingSiloTarget {
            launchSilo(at: point)
            return
        }

        if handleTapActionCell(point) { return }

        if selectedPoint == point {
            clearSelection()
            statusMessage = "Selection cleared."
            return
        }

        let unit = map.foregroundElement(atX: point.x, y: point.y)
        if unit.isUnitNonEmpty {
            handleUnitTap(unit, at: point)
            return
        }

        let building = map.backgroundElement(atX: point.x, y: point.y)
        if building.isBuilding {
            handleBuildingTap(building, at: point)
            return
        }

        clearSelection()
        statusMessage = "Select one of your units or properties."
    }

    private func handleTapActionCell(_ point: GridPoint) -> Bool {
        if loadableCells.contains(point) {
            if let selectedPoint,
               let selectedUnit = unit(at: selectedPoint),
               PlaytestRulebook.transportCapacity(for: selectedUnit, ruleset: ruleset) > 0 {
                loadUnit(from: point)
            } else {
                moveSelectedUnit(to: point)
            }
            return true
        }
        if joinableCells.contains(point) { joinUnit(to: point); return true }
        if unloadableCells.contains(point) { unloadUnit(to: point); return true }
        if attackableCells.contains(point) { attack(to: point); return true }
        if reachableCells.contains(point) { moveSelectedUnit(to: point); return true }
        return false
    }

    private func handleUnitTap(_ unit: Element, at point: GridPoint) {
        guard unit.army == activeArmy else {
            clearSelection()
            statusMessage = (isFogOfWarActive || submergedUnits.contains(point)) && !isVisible(point)
                ? "No enemy unit is visible at that space."
                : "That unit belongs to \(armyName(unit.army))."
            return
        }
        guard PlaytestRulebook.stats(for: unit, ruleset: ruleset) != nil else {
            clearSelection()
            statusMessage = "\(PaletteCatalog.label(for: unit, tileset: map.tileset)) is not available in \(ruleset.displayName)."
            return
        }
        guard !movedCells.contains(point) else {
            clearSelection()
            statusMessage = "That unit has already acted this turn."
            return
        }
        selectUnit(at: point)
    }

    private func handleBuildingTap(_ building: Element, at point: GridPoint) {
        guard building.army == activeArmy else {
            clearSelection()
            statusMessage = (isFogOfWarActive || submergedUnits.contains(point)) && !isVisible(point)
                ? "That property is outside friendly vision."
                : "That property belongs to \(armyName(building.army))."
            return
        }
        selectBuilding(at: point)
    }

    /// Secondary-clicking a unit previews the targets that unit could attack
    /// without changing the player's current selection or action state.
    func handleSecondaryTap(_ point: GridPoint) {
        guard isValid(point), !isGameOver, !isCPUArmy(activeArmy) else { return }

        let unit = map.foregroundElement(atX: point.x, y: point.y)
        guard unit.isUnitNonEmpty,
              PlaytestRulebook.stats(for: unit, ruleset: ruleset) != nil,
              (!isFogOfWarActive || unit.army == activeArmy || isVisible(point)) else {
            clearAttackPreview()
            return
        }

        guard unit.army == activeArmy else {
            clearAttackPreview()
            return
        }
        attackPreviewOrigin = point
        // A secondary-click is a range preview: show every square this unit
        // could target by distance, including currently empty squares. The
        // normal left-click selection remains stricter and only enables legal
        // enemy/property targets for the actual attack action.
        attackPreviewCells = attackRangeCells(from: point, unit: unit)
    }

    func endTurn() {
        guard !isGameOver else { return }
        guard !isAnimatingPlayerMovement else { return }
        guard !armies.isEmpty else {
            statusMessage = "No playable armies are placed on this map yet."
            return
        }

        let endingArmy = activeArmy
        cpuActionPoint = nil
        let routedArmies = resolveRouting()
        guard winnerArmy == nil else { return }
        guard let nextArmy = nextSurvivingArmy(after: endingArmy) else {
            statusMessage = "No playable armies remain."
            return
        }
        let currentIndex = armies.firstIndex(of: endingArmy) ?? 0
        let nextIndex = armies.firstIndex(of: nextArmy) ?? currentIndex
        let dayAdvanced = nextIndex <= currentIndex
        if dayAdvanced {
            turn += 1
            advanceRandomWeatherIfNeeded()
        }
        activeArmy = nextArmy
        cursorPoint = Self.initialCursor(in: map, army: activeArmy)
        movedCells.removeAll()
        clearSelection()
        let fuelLossCount = processTurnStart(for: activeArmy)
        let startRoutedArmies = resolveRouting()
        guard winnerArmy == nil else { return }
        let routedDuringTransition = Array(Set(routedArmies + startRoutedArmies)).sorted()
        let weatherMessage = weatherMode == .random
            ? " Weather: \(weather.displayName)."
            : ""
        let startMessage = "\(armyName(activeArmy))'s turn. Select a unit or property to begin." + weatherMessage
        let supplyMessage = fuelLossCount > 0
            ? " \(fuelLossCount) air/naval unit(s) were lost to fuel exhaustion."
            : ""
        if routedDuringTransition.isEmpty {
            statusMessage = startMessage + supplyMessage
        } else {
            statusMessage = startMessage + supplyMessage + " " + routedDuringTransition.map { armyName($0) }.joined(separator: ", ") + " was routed and its properties became neutral."
        }
        runCPUIfNeeded()
    }

    func capture() {
        guard let point = selectedPoint,
              let unit = unit(at: point),
              let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset) else {
            statusMessage = "Only Infantry and Mech units can capture properties."
            return
        }
        guard stats.canCapture else {
            statusMessage = "Only Infantry and Mech units can capture properties."
            return
        }

        let building = map.backgroundElement(atX: point.x, y: point.y)
        guard PlaytestRulebook.isCapturableBuilding(building, ruleset: ruleset), isHostile(building.army, activeArmy) || building.army == AWConstants.armyNeutral else {
            statusMessage = "There is no enemy or neutral property to capture here."
            return
        }

        let progress = captureProgress[point, default: 0] + max(1, unitHealth[point, default: 100] / 10)
        // Capturing is a legal follow-up after movement. Keep the unit marked
        // as acted so it cannot move or capture again this turn.
        movedCells.insert(point)
        if progress < 20 {
            captureProgress[point] = progress
            invalidatePlaytestMusic()
            clearSelection()
            statusMessage = "Capturing \(PaletteCatalog.label(for: building, tileset: map.tileset)): \(progress)/20. Continue next turn."
            return
        }

        let wasHQ = building.simplified == .buildingHQ
        if wasHQ {
            // HQ capture is an immediate defeat, but it still applies the
            // same surrender cleanup as routing. The captured HQ becomes a
            // neutral city and every other property owned by the defeated
            // army is released as well.
            let defeatedArmy = building.army
            neutralizeProperties(of: defeatedArmy)
            defeatedArmies.insert(defeatedArmy)
            captureProgress.removeValue(forKey: point)
            clearSelection()
            if Set(survivingArmies.map { team(for: $0) }).count == 1 {
                winnerArmy = activeArmy
                statusMessage = "\(activeArmyName) captured the HQ and wins the playtest."
            } else {
                statusMessage = "\(armyName(defeatedArmy))'s HQ was captured; its properties became neutral."
                _ = resolveRouting()
            }
            return
        }

        var candidate = map
        let captured = building.changedArmy(activeArmy)
        guard candidate.setBackground(captured, atX: point.x, y: point.y, check: false) else {
            statusMessage = "That property could not be captured."
            return
        }
        map = candidate
        captureProgress.removeValue(forKey: point)
        clearSelection()
        statusMessage = "\(activeArmyName) captured \(PaletteCatalog.label(for: captured, tileset: map.tileset))."
        _ = resolveRouting()
    }

    func wait() {
        guard let point = selectedPoint, unit(at: point) != nil else {
            statusMessage = "Select a unit before ending its action."
            return
        }
        movedCells.insert(point)
        clearSelection()
        statusMessage = "Unit action ended."
    }

    func toggleSubmerge() {
        guard let point = selectedPoint,
              let unit = unit(at: point),
              unit.simplified == .unitSub,
              !movedCells.contains(point) else {
            statusMessage = "Select an unused Submarine before changing its depth."
            return
        }

        if submergedUnits.contains(point) {
            submergedUnits.remove(point)
            statusMessage = "Submarine surfaced."
        } else {
            submergedUnits.insert(point)
            statusMessage = "Submarine submerged."
        }
        movedCells.insert(point)
        clearSelection()
    }

    func toggleStealth() {
        guard let point = selectedPoint,
              let unit = unit(at: point),
              unit.simplified == .unitStealth,
              !movedCells.contains(point) else {
            statusMessage = "Select an unused Stealth before changing its cloak."
            return
        }

        if stealthedUnits.contains(point) {
            stealthedUnits.remove(point)
            statusMessage = "Stealth uncloaked."
        } else {
            stealthedUnits.insert(point)
            statusMessage = "Stealth cloaked."
        }
        movedCells.insert(point)
        clearSelection()
    }

    /// Black Bombs are a special self-destruct action rather than a normal
    /// weapon.  The blast removes hostile units in the surrounding 3x3 area;
    /// allied units are left untouched.
    func detonateBlackBomb() {
        guard selectedUnitCanDetonateBlackBomb, let source = selectedPoint else {
            statusMessage = "Select an unused Black Bomb to detonate."
            return
        }

        let blast = detonateBlackBombBlast(at: source)
        recordDestroyedUnit(unit(at: source) ?? .unitEmpty)
        recordDestroyedCargo(at: source)
        var candidate = blast.map
        _ = candidate.setForeground(.unitEmpty, atX: source.x, y: source.y)
        map = candidate
        unitHealth.removeValue(forKey: source)
        unitFuel.removeValue(forKey: source)
        unitAmmo.removeValue(forKey: source)
        cargo.removeValue(forKey: source)
        movedCells.insert(source)
        clearSelection()
        _ = resolveRouting()
        let result = blast.destroyed == 0 ? "" : "; \(blast.destroyed) hostile unit(s) destroyed"
        statusMessage = "Black Bomb detonated\(result)."
    }

    private func detonateBlackBombBlast(at source: GridPoint) -> (map: MapState, destroyed: Int) {
        var candidate = map
        var destroyed = 0
        for x in max(0, source.x - 1)...min(map.width - 1, source.x + 1) {
            for y in max(0, source.y - 1)...min(map.height - 1, source.y + 1) {
                let point = GridPoint(x: x, y: y)
                guard let target = unit(at: point), isHostile(target.army, activeArmy) else { continue }
                recordDestroyedUnit(target)
                recordDestroyedCargo(at: point)
                _ = candidate.setForeground(.unitEmpty, atX: x, y: y)
                unitHealth.removeValue(forKey: point)
                unitFuel.removeValue(forKey: point)
                unitAmmo.removeValue(forKey: point)
                cargo.removeValue(forKey: point)
                submergedUnits.remove(point)
                stealthedUnits.remove(point)
                destroyed += 1
            }
        }
        return (candidate, destroyed)
    }

    /// Days of Ruin's Flare/Oozium slot reveals a small area for the current
    /// turn without changing the persisted map or permanently changing vision.
    func useFlare() {
        guard selectedUnitCanUseFlare, let source = selectedPoint else {
            statusMessage = "Select an unused Flare to reveal an area."
            return
        }
        let radius = 3
        for x in max(0, source.x - radius)...min(map.width - 1, source.x + radius) {
            for y in max(0, source.y - radius)...min(map.height - 1, source.y + radius) {
                let point = GridPoint(x: x, y: y)
                if distance(from: source, to: point) <= radius {
                    flareRevealCells.insert(point)
                }
            }
        }
        movedCells.insert(source)
        clearSelection()
        statusMessage = "Flare revealed the surrounding area for this turn."
    }

}
