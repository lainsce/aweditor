import AppKit
import Observation
import SwiftUI
import AWEDCore

extension PlaytestSession {
    var playableArmies: [Int] { armies }
    /// Any map with at least two playable armies can be run as CPU versus CPU.
    /// Single-army maps still require a human side so the match has an actor.
    var supportsCPUOnlyMatch: Bool {
        armies.count >= 2
    }
    var cpuArmiesForDisplay: Set<Int> { cpuArmies }
    var teamAssignmentsForDisplay: [Int: PlaytestTeam] { teamAssignments }
    var isStarted: Bool { hasStarted }
    var needsInitialArmySetup: Bool {
        // The match setup is useful for every map: it lets the player switch
        // away from Orange Star as well as select a side on maps that do not
        // contain it.
        !hasStarted && !armies.isEmpty
    }

    func team(for army: Int) -> PlaytestTeam {
        teamAssignments[army] ?? .red
    }

    func isAllied(_ first: Int, _ second: Int) -> Bool {
        first != second && team(for: first) == team(for: second)
    }

    func isHostile(_ first: Int, _ second: Int) -> Bool {
        first != second && team(for: first) != team(for: second)
    }

    func isCPUControlled(_ army: Int) -> Bool {
        isCPUArmy(army)
    }

    func startPlaytest() {
        guard !hasStarted else { return }
        hasStarted = true
        guard !armies.isEmpty else { return }
        _ = processTurnStart(for: activeArmy)
        _ = resolveRouting()
        runCPUIfNeeded()
    }

    @discardableResult
    func applyConfiguration(_ configuration: PlaytestConfiguration) -> Bool {
        guard !hasStarted, !armies.isEmpty else { return false }
        let selectedPlayer = configuration.playerArmy.flatMap { armies.contains($0) ? $0 : nil }
        guard selectedPlayer != nil || supportsCPUOnlyMatch else { return false }
        let automaticConfiguration = PlaytestConfiguration.automatic(for: armies)
        playerArmy = selectedPlayer
        if let selectedPlayer {
            cpuArmies = Set(configuration.cpuArmies.filter { armies.contains($0) && $0 != selectedPlayer })
            cpuArmies.formUnion(armies.filter { $0 != selectedPlayer && !cpuArmies.contains($0) })
        } else {
            cpuArmies = Set(armies)
        }
        teamAssignments = Dictionary(uniqueKeysWithValues: armies.map { army in
            (army, configuration.teams[army] ?? automaticConfiguration.team(for: army))
        })
        activeArmy = selectedPlayer ?? armies[0]
        cursorPoint = Self.initialCursor(in: map, army: activeArmy)
        statusMessage = selectedPlayer.map {
            "Select a \(armyName($0)) unit to begin."
        } ?? "CPU vs CPU: \(armyName(activeArmy)) begins."
        return true
    }

    func setWeatherMode(_ mode: PlaytestWeather) {
        weatherMode = mode
        weather = mode == .random
            ? PlaytestRulebook.randomWeather(for: ruleset)
            : mode
        refreshSelection()
    }

    func advanceRandomWeatherIfNeeded() {
        guard weatherMode == .random else { return }
        weather = PlaytestRulebook.randomWeather(for: ruleset)
    }

    var activeArmyName: String { armyName(activeArmy) }
    var gameDisplayName: String {
        ruleset.displayName
    }

    var usesCompatibilityRules: Bool {
        false
    }

    var activeArmyIsCPU: Bool { isCPUArmy(activeArmy) }
    var activeFunds: Int { funds[activeArmy, default: 0] }
    /// GB Wars 3 has separate winning/neutral/losing music for each side.
    /// Neutral is the normal state. Losing is driven by the cartridge-like
    /// casualty comparison, while winning is reserved for a concrete route or
    /// HQ-capture opportunity rather than a broad material-lead heuristic.
    var playtestMusicCue: PlaytestMusicCue {
        guard ruleset == .gameBoyWars3 else { return .neutral }
        if let winnerArmy {
            return winnerArmy == activeArmy ? .winning : .losing
        }

        guard armies.contains(activeArmy) else { return .neutral }
        if isCloseToWinningObjective(for: activeArmy) { return .winning }

        let activeLosses = destroyedUnitCounts[activeArmy, default: 0]
        let opposingLosses = armies
            .filter { isHostile($0, activeArmy) }
            .reduce(0) { result, army in
                result + destroyedUnitCounts[army, default: 0]
            }
        return activeLosses > opposingLosses ? .losing : .neutral
    }

    /// GB Wars 3's winning cue should only appear when a match is visibly
    /// approaching an actual objective:
    ///
    /// * an Infantry/Mech can capture an opposing HQ now or on its next move;
    /// * an HQ capture is already at least half complete; or
    /// * an opponent is one short step from routing (no production property
    ///   and at most two remaining units).
    ///
    /// This intentionally avoids treating money or raw unit value as a win
    /// signal, keeping the neutral theme as the track heard most of the time.
    func isCloseToWinningObjective(for army: Int) -> Bool {
        let opponents = armies.filter {
            !defeatedArmies.contains($0) && isHostile(army, $0)
        }
        guard !opponents.isEmpty else { return false }

        for opponent in opponents {
            let enemyHQs = allMapPoints().filter { point in
                let building = map.backgroundElement(atX: point.x, y: point.y)
                return building.simplified == .buildingHQ && building.army == opponent
            }

            if enemyHQs.contains(where: { hq in
                if captureProgress[hq, default: 0] >= 10,
                   let unit = unit(at: hq),
                   unit.army == army,
                   PlaytestRulebook.stats(for: unit, ruleset: ruleset)?.canCapture == true {
                    return true
                }
                return captureUnitCanReach(hq: hq, for: army)
            }) {
                return true
            }

            let remainingUnits = unitCount(for: opponent)
            let productionProperties = productionPropertyCount(for: opponent)
            if productionProperties == 0 && remainingUnits <= 2 {
                return true
            }
            if productionProperties <= 1 && remainingUnits <= 1 {
                return true
            }
        }
        return false
    }

    func captureUnitCanReach(hq: GridPoint, for army: Int) -> Bool {
        for point in allMapPoints() {
            guard let unit = unit(at: point),
                  unit.army == army,
                  let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset),
                  stats.canCapture else { continue }

            if point == hq { return true }
            guard !movedCells.contains(point) else { continue }
            guard distance(from: point, to: hq) <= stats.move else { continue }
            if movementPaths(from: point, unit: unit, stats: stats)[hq] != nil {
                return true
            }
        }
        return false
    }

    func productionPropertyCount(for army: Int) -> Int {
        allMapPoints().reduce(into: 0) { count, point in
            let building = map.backgroundElement(atX: point.x, y: point.y)
            guard building.isBuilding, building.army == army else { return }
            if !PlaytestRulebook.productionOptions(
                for: building,
                ruleset: ruleset,
                tileset: map.tileset
            ).isEmpty {
                count += 1
            }
        }
    }

    /// GB Wars uses ordinary four-sided cells with an alternating horizontal
    /// offset between rows in both the editor and playtest canvas.
    var isStaggeredGrid: Bool {
        MapCanvasMetrics.isStaggeredGB(map: map, palette: displayPalette)
    }

    func armyName(_ army: Int) -> String {
        PaletteCatalog.armyName(army, tileset: map.tileset)
    }
    var isGameOver: Bool { winnerArmy != nil || survivingArmies.isEmpty }
    var isFogOfWarActive: Bool {
        PlaytestRulebook.fogOfWarIsActive(
            ruleset: ruleset,
            manualFogEnabled: fogOfWarEnabled,
            weather: weather
        )
    }
    var isFogForcedByWeather: Bool {
        PlaytestRulebook.weatherForcesFog(ruleset, weather: weather)
    }

    var survivingArmies: [Int] {
        armies.filter { !defeatedArmies.contains($0) }
    }

    var selectedUnitName: String? {
        guard let selectedPoint, let unit = unit(at: selectedPoint) else { return nil }
        return PaletteCatalog.label(for: unit, tileset: map.tileset)
    }

    var selectedUnitHealth: Int? {
        guard let selectedPoint, unit(at: selectedPoint) != nil else { return nil }
        return unitHealth[selectedPoint, default: 100]
    }

    var selectedUnitFuel: Int? {
        guard let selectedPoint, unit(at: selectedPoint) != nil else { return nil }
        return unitFuel[selectedPoint, default: maxFuel(for: selectedPoint)]
    }

    var selectedUnitMaxFuel: Int? {
        guard let selectedPoint, let unit = unit(at: selectedPoint) else { return nil }
        return PlaytestRulebook.maxFuel(for: unit, ruleset: ruleset)
    }

    var selectedUnitAmmo: Int? {
        guard let selectedPoint, let unit = unit(at: selectedPoint),
              PlaytestRulebook.primaryAmmo(for: unit, ruleset: ruleset) != nil else { return nil }
        return unitAmmo[selectedPoint, default: PlaytestRulebook.primaryAmmo(for: unit, ruleset: ruleset) ?? 0]
    }

    var selectedSubmarineIsSubmerged: Bool {
        guard let selectedPoint, unit(at: selectedPoint)?.simplified == .unitSub else { return false }
        return submergedUnits.contains(selectedPoint)
    }

    var selectedUnitIsSubmarine: Bool {
        guard let selectedPoint else { return false }
        return unit(at: selectedPoint)?.simplified == .unitSub
    }

    var selectedUnitIsStealth: Bool {
        guard let selectedPoint else { return false }
        return unit(at: selectedPoint)?.simplified == .unitStealth
    }

    var selectedStealthIsCloaked: Bool {
        guard let selectedPoint, selectedUnitIsStealth else { return false }
        return stealthedUnits.contains(selectedPoint)
    }

    var selectedUnitCanDetonateBlackBomb: Bool {
        guard let selectedPoint,
              let unit = unit(at: selectedPoint),
              unit.simplified == .unitBlackBomb else { return false }
        return true
    }

    var selectedUnitCanToggleDepth: Bool {
        guard let selectedPoint, selectedUnitIsSubmarine else { return false }
        return !movedCells.contains(selectedPoint)
    }

    var selectedUnitCanToggleStealth: Bool {
        guard let selectedPoint, selectedUnitIsStealth else { return false }
        return !movedCells.contains(selectedPoint)
    }

    var selectedUnitCanWait: Bool {
        selectedPoint != nil && selectedUnitName != nil
    }

    var selectedUnitCanUseFlare: Bool {
        guard ruleset == .daysOfRuin,
              let selectedPoint,
              let unit = unit(at: selectedPoint),
              unit.simplified == .unitOozium else { return false }
        return true
    }

    var selectedUnitCanLaunchSilo: Bool {
        guard ruleset == .advanceWars2 || ruleset == .dualStrike,
              let selectedPoint,
              let unit = unit(at: selectedPoint),
              !movedCells.contains(selectedPoint),
              unit.simplified == .unitInfantry || unit.simplified == .unitMech,
              map.backgroundElement(atX: selectedPoint.x, y: selectedPoint.y).simplified == .buildingSilo else { return false }
        return !usedMissileSilos.contains(selectedPoint)
    }

    /// A render-only map snapshot. Terrain remains known under Fog of War;
    /// unseen enemy units disappear and unseen property ownership is shown as
    /// neutral until a friendly unit's vision reaches the square.
    var displayMap: MapState {
        var result = map
        // Weather affects the art palette in the editor's playtest without
        // mutating the source map or its persisted tileset/ruleset.
        result.tileset = displayTileset

        guard isFogOfWarActive || !submergedUnits.isEmpty || !stealthedUnits.isEmpty || !flareRevealCells.isEmpty else { return result }
        let visibleCells = visibleCells()
        for x in 0..<map.width {
            for y in 0..<map.height {
                let point = GridPoint(x: x, y: y)
                let unit = map.foregroundElement(atX: x, y: y)
                if unit.isUnitNonEmpty, isHostile(unit.army, activeArmy),
                   (isFogOfWarActive || submergedUnits.contains(point) || stealthedUnits.contains(point)), !visibleCells.contains(point) {
                    _ = result.setForeground(.unitEmpty, atX: x, y: y)
                }

                let building = map.backgroundElement(atX: x, y: y)
                if isFogOfWarActive, building.isBuilding, isHostile(building.army, activeArmy), !visibleCells.contains(point) {
                    _ = result.setBackground(building.changedArmy(AWConstants.armyNeutral), atX: x, y: y, check: false)
                }
            }
        }
        return result
    }

    /// The board backdrop hides the sprite that is being animated by the
    /// interaction layer. Both endpoints are removed because the simulation
    /// commits each step before the visual transition finishes; the transient
    /// Canvas sprite is then the single visible representation of that unit.
    var displayMapForPlaytest: MapState {
        var result = displayMap
        guard let animation = movementAnimation else { return result }

        for point in Set([animation.from, animation.to]) {
            guard result.foregroundElement(atX: point.x, y: point.y) == animation.unit else { continue }
            _ = result.setForeground(.unitEmpty, atX: point.x, y: point.y)
        }
        return result
    }

    var displayPalette: SpritePalette {
        switch visualVariant {
        case .famicomWars:
            return .famicomWars
        case .gbWars:
            return .gbWars
        case .superFamicomWars:
            return .superFamicomWars
        case .gbWars2:
            return .gbWars2
        case .gbWars3:
            return .gbWars3
        case .daysOfRuin:
            return .daysOfRuin
        case .dualStrikeWasteland where weather == .clear:
            return .tileset(.wasteland)
        default:
            return PlaytestRulebook.visualPalette(for: ruleset, weather: weather)
        }
    }

    var displayTileset: Tileset {
        switch visualVariant {
        case .famicomWars:
            return .famicomWars
        case .gbWars:
            return .gbWars
        case .superFamicomWars:
            return .superFamicomWars
        case .gbWars2:
            return .gbWars2
        case .gbWars3:
            return .gbWars3
        case .daysOfRuin:
            return .daysOfRuin
        case .dualStrikeWasteland where weather == .clear:
            return .wasteland
        default:
            return PlaytestRulebook.visualTileset(for: ruleset, weather: weather)
        }
    }

    var selectedUnitResourceLabel: String? {
        guard let selectedPoint, let unit = unit(at: selectedPoint) else { return nil }
        return PlaytestRulebook.resourceLabel(for: unit)
    }

    var selectedTransportCapacity: Int? {
        guard let selectedPoint, let unit = unit(at: selectedPoint) else { return nil }
        let capacity = PlaytestRulebook.transportCapacity(for: unit, ruleset: ruleset)
        return capacity > 0 ? capacity : nil
    }

    var selectedCargoCount: Int {
        guard let selectedPoint else { return 0 }
        return cargo[selectedPoint, default: []].count
    }

    var selectedCargoNames: [String] {
        guard let selectedPoint else { return [] }
        return cargo[selectedPoint, default: []].map {
            PaletteCatalog.label(for: $0.unit, tileset: map.tileset)
        }
    }

    var selectedCargoSummary: String? {
        guard let selectedPoint, let loaded = cargo[selectedPoint], !loaded.isEmpty else { return nil }
        let index = min(selectedCargoIndex, loaded.count - 1)
        return PaletteCatalog.label(for: loaded[index].unit, tileset: map.tileset)
    }

    func selectCargo(index: Int) {
        selectedCargoIndex = max(0, index)
        guard let point = selectedPoint, let transport = unit(at: point) else { return }
        updateTransportActions(for: transport, at: point)
    }

    var selectedTransportCanResupply: Bool {
        guard let selectedPoint,
              let unit = unit(at: selectedPoint),
              PlaytestRulebook.resuppliesAdjacentUnits(unit, ruleset: ruleset) ||
                unit.simplified == .unitBlackBoat else { return false }
        return !refuelableCells.isEmpty
    }

}
