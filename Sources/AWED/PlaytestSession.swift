import AppKit
import Observation
import SwiftUI
import AWEDCore

/// The render layer uses this transient value to show the unit at the current
/// committed grid cell. The simulation advances one cell at a time; hiding the
/// committed sprite while this value is active keeps the step visible without
/// turning the movement into a continuous tween.
struct PlaytestMovementAnimation: Equatable {
    let unit: Element
    let from: GridPoint
    let to: GridPoint
}

struct PlaytestLaunch: Identifiable {
    let id = UUID()
    let map: MapState
    let visualVariant: MapVisualVariant
}

@MainActor
@Observable
final class PlaytestSession {
    private static let pipeSeamStartingHealth = 99

    // CPU actions are intentionally paced separately from the rules engine.
    // The planner should stay quick, while the visible turn should still read
    // like a game rather than a batch simulation.
    private static let cpuActionPreviewDelay: UInt64 = 220_000_000
    private static let cpuActionPause: UInt64 = 90_000_000
    private static let cpuTurnPause: UInt64 = 520_000_000
    private static let cpuMoveStepPause: UInt64 = 125_000_000
    private static let legacyMoveStepPause: UInt64 = 180_000_000
    private static let cpuRoutePause: UInt64 = 100_000_000

    private struct CPUTimingProfile {
        let minimumTurnDuration: UInt64
        let delayScale: Double
    }

    /// Keep the visible pacing in step with the source game's era: compact
    /// 8-bit rulesets turn over quickly, 16-bit/Game Boy Color rulesets get a
    /// little more room to read, and the larger GBA/DS rulesets retain the
    /// five-second floor used for modern playtests.
    private var cpuTimingProfile: CPUTimingProfile {
        switch ruleset {
        case .famicomWars, .gameBoyWars:
            return CPUTimingProfile(minimumTurnDuration: 3_000_000_000, delayScale: 0.6)
        case .superFamicomWars, .gameBoyWars2, .gameBoyWars3:
            return CPUTimingProfile(minimumTurnDuration: 4_000_000_000, delayScale: 0.8)
        case .advanceWars, .advanceWars2, .dualStrike, .daysOfRuin:
            return CPUTimingProfile(minimumTurnDuration: 5_000_000_000, delayScale: 1.0)
        }
    }

    private var cpuMinimumTurnDuration: UInt64 {
        cpuTimingProfile.minimumTurnDuration
    }

    private func scaledCPUDelay(_ base: UInt64) -> UInt64 {
        max(1, UInt64((Double(base) * cpuTimingProfile.delayScale).rounded()))
    }

    private var movementStepDelay: UInt64 {
        scaledCPUDelay(usesTileMovementAnimation ? Self.legacyMoveStepPause : Self.cpuMoveStepPause)
    }

    private struct PlaytestCargo {
        let unit: Element
        let health: Int
        let fuel: Int
        let ammo: Int?
    }

    private struct MovementPath {
        let movement: Int
        let steps: Int
        let previous: GridPoint?
    }

    /// The CPU deliberately keeps its action vocabulary small. It evaluates
    /// the same legal actions exposed to the player, then chooses the highest
    /// immediate utility score rather than searching for a perfect line.
    private enum CPUAction {
        case attack(origin: GridPoint, target: GridPoint)
        case capture(point: GridPoint)
        case build(point: GridPoint, option: PlaytestProductionOption)
        case move(origin: GridPoint, destination: GridPoint)
        case load(transport: GridPoint, cargo: GridPoint)
        case unload(transport: GridPoint, destination: GridPoint)
        case join(origin: GridPoint, destination: GridPoint)
        case resupply(point: GridPoint)
        case detonate(point: GridPoint)
        case flare(point: GridPoint)
        case stealth(point: GridPoint)
        case wait(point: GridPoint)
    }

    private struct CPUPlan {
        let score: Double
        let action: CPUAction
    }

    private struct CPUThreatKey: Hashable {
        let unitValue: Int
        let point: GridPoint
        let health: Int
    }

    private struct CPUPathKey: Hashable {
        let origin: GridPoint
        let unitValue: Int
        let fuel: Int
    }

    /// Famicom Wars' small CPU should only advance toward objectives that its
    /// unit can actually reach over the terrain.  Manhattan distance is still
    /// useful for the newer games' broad heuristics, but it makes an NES land
    /// unit look as though it can march through a sea gap or around an
    /// unreachable island.  Keep the target type in the cache key because a
    /// unit may have a different route to an enemy, a property, and an HQ.
    private enum CPUTacticalTarget: Hashable {
        case enemyUnit
        case enemyProperty
        case enemyHQ
    }

    private struct CPUTacticalDistanceKey: Hashable {
        let unitValue: Int
        let target: CPUTacticalTarget
    }

    private struct CPUAttackKey: Hashable {
        let origin: GridPoint
        let unitValue: Int
        let primaryAmmo: Int
        let hasMoved: Bool
    }

    private struct CPUEnemyInfo {
        let point: GridPoint
        let unit: Element
        let stats: PlaytestUnitStats
    }

    private struct CPUTransportKey: Hashable {
        let transportValue: Int
        let cargoValue: Int
    }

    /// A single planning pass should inspect the board once. The previous
    /// planner rediscovered the same units, properties, and opponents for
    /// every action family and for every candidate score.
    private struct CPUPlanningSnapshot {
        let ownUnitPoints: [GridPoint]
        let enemyUnitPoints: [GridPoint]
        let enemyUnits: [CPUEnemyInfo]
        let ownPropertyPoints: [GridPoint]
        let enemyPropertyPoints: [GridPoint]
        let enemyHQPoints: [GridPoint]
        let pipeSeamPoints: [GridPoint]
        let ownCounts: [Int: Int]
        let ownDomains: (land: Int, air: Int, sea: Int)
        let enemyDomains: (land: Int, air: Int, sea: Int)
    }

    let sourceMap: MapState
    let ruleset: PlaytestRuleset
    /// The planner is selected once from the map's tileset, so every CPU
    /// decision in this session follows that game's profile without repeated
    /// rulebook dispatch during candidate scoring.
    private let cpuPolicy: PlaytestRulebook.CPUPolicy
    /// The art variant selected in the editor when this playtest was opened.
    /// It is intentionally not persisted in `MapState`; the map file format
    /// still stores only its base tileset.
    let visualVariant: MapVisualVariant
    private let initialWeather: PlaytestWeather

    var map: MapState {
        didSet {
            invalidateVisibilityCache()
            // Terrain, units, and property ownership all change through the
            // live map value. Keep the Famicom strategic distance fields tied
            // to that snapshot instead of rebuilding them for every action.
            cpuTacticalDistanceCache.removeAll(keepingCapacity: true)
            mapRevision &+= 1
            // Cartridge-style movement commits one tile at a time. Defer
            // cue evaluation until that walk finishes instead of asking the
            // GB Wars 3 objective scan to run for every intermediate tile.
            if !isAnimatingCPUMovement && !isAnimatingPlayerMovement {
                invalidatePlaytestMusic()
            }
        }
    }
    /// A scalar render revision avoids making SwiftUI compare every terrain,
    /// draw-layer, and foreground array on each CPU move just to refresh the
    /// read-only map backdrop.
    private(set) var mapRevision = 0
    /// A lightweight state signal for playtest music. Map changes cover unit
    /// movement, combat, captures, production, and routing; the few
    /// render-independent objective changes (such as partial HQ capture)
    /// bump this separately so GB Wars 3 can change cues at the right moment.
    private(set) var musicRevision = 0
    var activeArmy: Int {
        didSet {
            invalidateVisibilityCache()
            cpuTacticalDistanceCache.removeAll(keepingCapacity: true)
        }
    }
    private(set) var playerArmy: Int?
    var turn = 1
    /// The value shown in the weather picker. When this is `.random`, the
    /// concrete `weather` value is rolled once per new day and is used by all
    /// movement, vision, range, and rendering decisions.
    var weatherMode: PlaytestWeather = .clear
    var weather: PlaytestWeather = .clear {
        didSet {
            invalidateVisibilityCache()
            cpuTacticalDistanceCache.removeAll(keepingCapacity: true)
        }
    }
    var fogOfWarEnabled = false {
        didSet { invalidateVisibilityCache() }
    }
    /// The directional cursor used by the pre-DS playtest controls. This is
    /// deliberately separate from `selectedPoint`: the cartridges let the
    /// player browse the map before committing an action with A.
    var cursorPoint: GridPoint?
    var selectedPoint: GridPoint?
    var reachableCells: Set<GridPoint> = []
    var attackableCells: Set<GridPoint> = []
    var attackPreviewOrigin: GridPoint?
    var attackPreviewCells: Set<GridPoint> = []
    /// The route currently being committed by the CPU. It grows one
    /// cardinal tile at a time so the orange arrow always follows the legal
    /// path selected by the planner.
    var cpuMovementPath: [GridPoint] = []
    /// The route currently previewed by the player while dragging a selected
    /// unit. This is render-only state; the map changes only when the drag is
    /// released on the route's final tile.
    var playerMovementPath: [GridPoint] = []
    /// A frame-level visual transition for the tile currently being crossed.
    /// It is deliberately separate from the path so the Canvas can interpolate
    /// the sprite between cells while the simulation remains tile-accurate.
    private(set) var playerMovementAnimation: PlaytestMovementAnimation?
    private(set) var cpuMovementAnimation: PlaytestMovementAnimation?
    var movementAnimation: PlaytestMovementAnimation? {
        playerMovementAnimation ?? cpuMovementAnimation
    }
    var isMovementAnimating: Bool {
        movementAnimation != nil
    }
    /// The point at which the CPU's current non-movement action is taking
    /// place. Movement uses `cpuMovementPath` for a tile-by-tile camera
    /// target; this fallback keeps attacks, captures, production, and cargo
    /// actions visible even when they complete in one state update.
    var cpuActionPoint: GridPoint?
    var captureableCells: Set<GridPoint> = []
    var productionOptions: [PlaytestProductionOption] = []
    var movedCells: Set<GridPoint> = []
    var funds: [Int: Int]
    var unitHealth: [GridPoint: Int] = [:]
    /// Infantry and Mech display this resource as rations. AW2 supplies
    /// cartridge-accurate per-unit fuel capacities through the rules layer.
    var unitFuel: [GridPoint: Int] = [:]
    var unitAmmo: [GridPoint: Int] = [:]
    var submergedUnits: Set<GridPoint> = [] {
        didSet {
            invalidateVisibilityCache()
            submergedRevision &+= 1
        }
    }
    var stealthedUnits: Set<GridPoint> = [] {
        didSet { invalidateVisibilityCache() }
    }
    var flareRevealCells: Set<GridPoint> = [] {
        didSet { invalidateVisibilityCache() }
    }
    private(set) var submergedRevision = 0
    var captureProgress: [GridPoint: Int] = [:]
    var loadableCells: Set<GridPoint> = []
    var joinableCells: Set<GridPoint> = []
    var unloadableCells: Set<GridPoint> = []
    var refuelableCells: Set<GridPoint> = []
    var siloTargetCells: Set<GridPoint> = []
    var winnerArmy: Int?
    var statusMessage: String

    private let armies: [Int]
    private var cpuArmies: Set<Int>
    private var teamAssignments: [Int: PlaytestTeam]
    private var hasStarted = false
    private var defeatedArmies: Set<Int> = []
    /// Famicom-era routing can use unit elimination even when an army still
    /// has a production property. An army that starts a map with no units has
    /// not been eliminated yet, though; remember which armies have actually
    /// fielded a supported unit so startup cannot neutralize a perfectly valid
    /// empty opening army.
    @ObservationIgnored private var armiesThatHaveHadUnits: Set<Int> = []
    /// GB Wars 3's losing cue is based on cumulative unit losses, not on a
    /// generic material score. Keep this transient match state separate from
    /// the map so loading/restarting a playtest never changes persisted data.
    @ObservationIgnored private var destroyedUnitCounts: [Int: Int] = [:]
    private var cargo: [GridPoint: [PlaytestCargo]] = [:]
    /// Pipe seams are map objectives rather than units. The cartridges treat
    /// them as 99-HP structures, so keep their damage separate from unit HP
    /// while the playtest mutates the in-memory map.
    private var pipeSeamHealth: [GridPoint: Int] = [:]
    private var usedMissileSilos: Set<GridPoint> = []
    private var isSelectingSiloTarget = false
    @ObservationIgnored private var isAnimatingCPUMovement = false
    private var isAnimatingPlayerMovement = false
    @ObservationIgnored private var playerMovementTask: Task<Void, Never>?
    private var isExecutingCPU = false
    @ObservationIgnored private var cpuTask: Task<Void, Never>?
    @ObservationIgnored private var cpuRunID = UUID()
    @ObservationIgnored private var cpuPlanningSnapshot: CPUPlanningSnapshot?
    @ObservationIgnored private var cpuThreatCache: [CPUThreatKey: Int] = [:]
    @ObservationIgnored private var cpuMovementPathCache: [CPUPathKey: [GridPoint: MovementPath]] = [:]
    @ObservationIgnored private var cpuAttackableCache: [CPUAttackKey: Set<GridPoint>] = [:]
    @ObservationIgnored private var cpuNearestEnemyDistanceCache: [GridPoint: Int] = [:]
    @ObservationIgnored private var cpuNearestEnemyPropertyDistanceCache: [GridPoint: Int] = [:]
    @ObservationIgnored private var cpuTacticalDistanceCache: [CPUTacticalDistanceKey: [GridPoint: Int]] = [:]
    @ObservationIgnored private var cpuTransportDropOffCache: [CPUTransportKey: [GridPoint]] = [:]
    @ObservationIgnored private var visibilityRevision = 0
    @ObservationIgnored private var cachedVisibilityRevision = -1
    @ObservationIgnored private var cachedVisibleCells: Set<GridPoint> = []
    @ObservationIgnored private var cachedMapPoints: [GridPoint] = []
    @ObservationIgnored private var cachedMapPointWidth = -1
    @ObservationIgnored private var cachedMapPointHeight = -1

    /// The moving CPU unit remains visually bright until its route has been
    /// committed. The render layer reads this alongside the growing route so
    /// already-finished CPU actions can still use the normal spent-unit tint.
    var isCPUMovementAnimating: Bool { isAnimatingCPUMovement }
    /// Legacy cartridges commit movement from the command rail. Expose the
    /// transient animation state so keyboard input cannot queue another action
    /// while the unit is still walking tile by tile.
    var isPlayerMovementAnimating: Bool { isAnimatingPlayerMovement }

    init(
        map: MapState,
        visualVariant: MapVisualVariant? = nil,
        configuration: PlaytestConfiguration? = nil,
        startCPU: Bool = true
    ) {
        let resolvedRuleset = map.tileset.playtestRuleset
        let resolvedVariant: MapVisualVariant
        if let visualVariant, visualVariant.baseTileset == map.tileset {
            resolvedVariant = visualVariant
        } else {
            resolvedVariant = .defaultVariant(for: map.tileset)
        }

        let availableArmies = Self.armies(in: map)
        let automaticConfiguration = PlaytestConfiguration.automatic(for: availableArmies)
        let resolvedConfiguration = configuration ?? automaticConfiguration
        let allowsCPUOnlyMatch = availableArmies.count >= 2
        let resolvedPlayerArmy: Int?
        if let configuredPlayerArmy = resolvedConfiguration.playerArmy,
           availableArmies.contains(configuredPlayerArmy) {
            resolvedPlayerArmy = configuredPlayerArmy
        } else if configuration != nil, allowsCPUOnlyMatch {
            resolvedPlayerArmy = nil
        } else {
            resolvedPlayerArmy = automaticConfiguration.playerArmy
        }
        var resolvedCPUArmies = Set(resolvedConfiguration.cpuArmies.filter { availableArmies.contains($0) && $0 != resolvedPlayerArmy })
        resolvedCPUArmies.formUnion(availableArmies.filter { $0 != resolvedPlayerArmy && !resolvedCPUArmies.contains($0) })
        let resolvedTeamAssignments = Dictionary(uniqueKeysWithValues: availableArmies.map { army in
            (army, resolvedConfiguration.teams[army] ?? automaticConfiguration.team(for: army))
        })
        let initialArmy = resolvedPlayerArmy ?? availableArmies.first ?? AWConstants.armyOrangeStar

        sourceMap = map
        self.map = map
        ruleset = resolvedRuleset
        cpuPolicy = PlaytestRulebook.cpuPolicy(for: map.tileset)
        self.visualVariant = resolvedVariant
        initialWeather = PlaytestRulebook.initialWeather(for: resolvedVariant, ruleset: resolvedRuleset)
        armies = availableArmies
        playerArmy = resolvedPlayerArmy
        cpuArmies = resolvedCPUArmies
        teamAssignments = resolvedTeamAssignments
        activeArmy = initialArmy
        cursorPoint = Self.initialCursor(in: map, army: initialArmy)
        weatherMode = initialWeather
        weather = initialWeather
        funds = Dictionary(uniqueKeysWithValues: availableArmies.map { ($0, 10_000) })
        statusMessage = availableArmies.isEmpty
            ? "No playable armies are placed on this map yet."
            : resolvedPlayerArmy == nil
                ? "CPU vs CPU: \(PaletteCatalog.armyName(initialArmy, tileset: map.tileset)) begins."
                : "Select a \(PaletteCatalog.armyName(initialArmy, tileset: map.tileset)) unit to begin."
        initializeUnitResources()
        initializePipeSeams()
        recordUnitPresence()
        if startCPU {
            startPlaytest()
        }
    }

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

    private func advanceRandomWeatherIfNeeded() {
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
    private func isCloseToWinningObjective(for army: Int) -> Bool {
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

    private func captureUnitCanReach(hq: GridPoint, for army: Int) -> Bool {
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

    private func productionPropertyCount(for army: Int) -> Int {
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

    private func armyName(_ army: Int) -> String {
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

    private var survivingArmies: [Int] {
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

    private var displayTileset: Tileset {
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

    private var selectedCargoIndex = 0

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

        if loadableCells.contains(point) {
            if let selectedPoint,
               let selectedUnit = unit(at: selectedPoint),
               PlaytestRulebook.transportCapacity(for: selectedUnit, ruleset: ruleset) > 0 {
                loadUnit(from: point)
            } else {
                moveSelectedUnit(to: point)
            }
            return
        }

        if joinableCells.contains(point) {
            joinUnit(to: point)
            return
        }

        if unloadableCells.contains(point) {
            unloadUnit(to: point)
            return
        }

        if attackableCells.contains(point) {
            attack(to: point)
            return
        }

        if reachableCells.contains(point) {
            moveSelectedUnit(to: point)
            return
        }

        if selectedPoint == point {
            clearSelection()
            statusMessage = "Selection cleared."
            return
        }

        let unit = map.foregroundElement(atX: point.x, y: point.y)
        if unit.isUnitNonEmpty {
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
            return
        }

        let building = map.backgroundElement(atX: point.x, y: point.y)
        if building.isBuilding {
            guard building.army == activeArmy else {
                clearSelection()
                statusMessage = (isFogOfWarActive || submergedUnits.contains(point)) && !isVisible(point)
                    ? "That property is outside friendly vision."
                    : "That property belongs to \(armyName(building.army))."
                return
            }
            selectBuilding(at: point)
            return
        }

        clearSelection()
        statusMessage = "Select one of your units or properties."
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
        recordDestroyedUnit(unit(at: source) ?? .unitEmpty)
        recordDestroyedCargo(at: source)
        _ = candidate.setForeground(.unitEmpty, atX: source.x, y: source.y)
        map = candidate
        unitHealth.removeValue(forKey: source)
        unitFuel.removeValue(forKey: source)
        unitAmmo.removeValue(forKey: source)
        cargo.removeValue(forKey: source)
        movedCells.insert(source)
        clearSelection()
        _ = resolveRouting()
        let result = destroyed == 0 ? "" : "; \(destroyed) hostile unit(s) destroyed"
        statusMessage = "Black Bomb detonated\(result)."
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

    func beginSiloLaunch() {
        guard selectedUnitCanLaunchSilo, selectedPoint != nil else {
            statusMessage = "An unused Missile Silo must have an Infantry or Mech standing on it."
            return
        }
        isSelectingSiloTarget = true
        siloTargetCells = Set((0..<map.width).flatMap { x in
            (0..<map.height).map { y in GridPoint(x: x, y: y) }
        })
        statusMessage = "Select any map space for the Missile Silo target."
    }

    private func launchSilo(at target: GridPoint) {
        guard selectedUnitCanLaunchSilo, let source = selectedPoint else {
            isSelectingSiloTarget = false
            siloTargetCells.removeAll()
            return
        }

        for x in 0..<map.width {
            for y in 0..<map.height {
                let point = GridPoint(x: x, y: y)
                guard abs(point.x - target.x) + abs(point.y - target.y) <= 2 else { continue }
                let unit = map.foregroundElement(atX: x, y: y)
                guard unit.isUnitNonEmpty else { continue }
                unitHealth[point] = max(10, unitHealth[point, default: 100] - 30)
            }
        }
        usedMissileSilos.insert(source)
        movedCells.insert(source)
        isSelectingSiloTarget = false
        siloTargetCells.removeAll()
        clearSelection()
        statusMessage = "Missile Silo launched. Every unit in the blast took 3 HP."
    }

    func canBuild(_ option: PlaytestProductionOption) -> Bool {
        guard let point = selectedPoint,
              selectedBuildingName != nil,
              let building = Optional(map.backgroundElement(atX: point.x, y: point.y)),
              building.army == activeArmy,
              map.foregroundElement(atX: point.x, y: point.y) == .unitEmpty,
              !movedCells.contains(point),
              activeFunds >= option.cost,
              unitCount(for: activeArmy) < PlaytestRulebook.unitCap(for: ruleset),
              PlaytestRulebook.productionOptions(for: building, ruleset: ruleset, tileset: map.tileset).contains(where: { $0.id == option.id }) else { return false }
        // Famicom/Super Famicom's local HQ-radius rule belongs to the CPU
        // planner. Human production remains available at any owned,
        // production-capable property, matching the visible cartridge menu.
        return map.allowPlacement(option.element.changedArmy(activeArmy), atX: point.x, y: point.y)
    }

    private func productionIsWithinHQArea(_ point: GridPoint) -> Bool {
        guard let radius = cpuPolicy.hqProductionRadius else { return true }
        let hqPoints = allMapPoints().filter {
            let building = map.backgroundElement(atX: $0.x, y: $0.y)
            return building.simplified == .buildingHQ && building.army == activeArmy
        }
        guard !hqPoints.isEmpty else { return true }
        return hqPoints.contains { hq in
            max(abs(hq.x - point.x), abs(hq.y - point.y)) <= radius
        }
    }

    func buildUnit(_ option: PlaytestProductionOption) {
        guard canBuild(option), let point = selectedPoint else {
            statusMessage = "That unit cannot be built here right now."
            return
        }

        var candidate = map
        let unit = option.element.changedArmy(activeArmy)
        guard candidate.setForeground(unit, atX: point.x, y: point.y) else {
            statusMessage = "That unit cannot be built on this property."
            return
        }
        map = candidate
        funds[activeArmy, default: 0] -= option.cost
        unitHealth[point] = 100
        unitFuel[point] = PlaytestRulebook.maxFuel(for: unit, ruleset: ruleset)
        if let ammo = PlaytestRulebook.primaryAmmo(for: unit, ruleset: ruleset) {
            unitAmmo[point] = ammo
        }
        movedCells.insert(point)
        clearSelection()
        statusMessage = "Built \(option.label) for \(PlaytestRulebook.formatFunds(option.cost)). It cannot move this turn."
    }

    private func selectUnit(at point: GridPoint) {
        guard let unit = unit(at: point), let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset) else { return }
        clearPlayerMovementPreview()
        selectedPoint = point
        productionOptions.removeAll()
        let hasMoved = movedCells.contains(point)
        captureableCells = canCapture(unit: unit, stats: stats, at: point) ? [point] : []
        reachableCells = hasMoved || activeArmyIsCPU || isAnimatingCPUMovement
            ? []
            : movementCells(from: point, unit: unit, stats: stats)
        attackableCells = hasMoved && !stats.canMoveAndFire ? [] : attackableCells(from: point, unit: unit)
        updateTransportActions(for: unit, at: point)
        if hasMoved {
            if !attackableCells.isEmpty && !captureableCells.isEmpty {
                statusMessage = "Choose an enemy in red, capture the highlighted property, or end the action."
            } else if !captureableCells.isEmpty {
                statusMessage = "Capture the highlighted property or end the action."
            } else if stats.canMoveAndFire {
                statusMessage = "Choose an enemy in red, or end the action."
            } else {
                statusMessage = "\(PaletteCatalog.label(for: unit, tileset: map.tileset)) moved and is spent."
            }
        } else if activeArmyIsCPU {
            statusMessage = "\(PaletteCatalog.label(for: unit, tileset: map.tileset)) is moving."
        } else {
            let movementHint = ruleset.showsMovementAvailabilityBadge ? "an M marker" : "a blue tile"
            statusMessage = "Move to \(movementHint), attack a red target, load or unload cargo, or capture the highlighted property."
        }
    }

    func refreshSelection() {
        guard let selectedPoint,
              let unit = unit(at: selectedPoint) else { return }
        selectUnit(at: selectedPoint)
        if PlaytestRulebook.resuppliesAdjacentUnits(unit, ruleset: ruleset) ||
            unit.simplified == .unitBlackBoat {
            updateTransportActions(for: unit, at: selectedPoint)
        }
    }

    private func effectiveVision(for observer: Element, at point: GridPoint) -> Int? {
        guard let observerStats = PlaytestRulebook.stats(for: observer, ruleset: ruleset) else { return nil }
        var vision = observerStats.vision
        let observerTerrain = map.backgroundElement(atX: point.x, y: point.y)
        if (observer.simplified == .unitInfantry || observer.simplified == .unitMech),
           observerTerrain.simplified == .terrainMountain {
            vision += 3
        }
        // Rain reduces vision in every ruleset where Fog of War is active.
        // Dual Strike also forces Fog of War on while it is raining.
        if isFogOfWarActive, weather == .rain {
            vision = max(1, vision - 1)
        }
        return vision
    }

    func isVisible(_ point: GridPoint) -> Bool {
        guard isValid(point) else { return false }
        return visibleCells().contains(point)
    }

    /// Computes Fog-of-War visibility once per board/turn state. The old
    /// implementation scanned every observer for every queried tile, which
    /// made a full-map render quadratic and repeated that work for each CPU
    /// action. Marking the observer radii directly keeps the same rules while
    /// making both rendering and attack generation proportional to vision.
    private func visibleCells() -> Set<GridPoint> {
        if cachedVisibilityRevision == visibilityRevision {
            return cachedVisibleCells
        }

        let allPoints = allMapPoints()
        let fogActive = isFogOfWarActive
        var visible = fogActive ? Set<GridPoint>() : Set(allPoints)
        if !fogActive {
            for point in allPoints {
                let unit = map.foregroundElement(atX: point.x, y: point.y)
                if unit.isUnitNonEmpty,
                   isHostile(unit.army, activeArmy),
                   ((unit.simplified == .unitSub && submergedUnits.contains(point)) ||
                    (unit.simplified == .unitStealth && stealthedUnits.contains(point))) {
                    visible.remove(point)
                }
            }
        }

        for observerX in 0..<map.width {
            for observerY in 0..<map.height {
                let observerPoint = GridPoint(x: observerX, y: observerY)
                let observer = map.foregroundElement(atX: observerX, y: observerY)
                guard observer.isUnitNonEmpty,
                      (observer.army == activeArmy || isAllied(observer.army, activeArmy)),
                      let observerStats = PlaytestRulebook.stats(for: observer, ruleset: ruleset),
                      let vision = effectiveVision(for: observer, at: observerPoint) else { continue }

                let minX = max(0, observerX - vision)
                let maxX = min(map.width - 1, observerX + vision)
                let minY = max(0, observerY - vision)
                let maxY = min(map.height - 1, observerY + vision)
                for targetX in minX...maxX {
                    for targetY in minY...maxY {
                        let targetPoint = GridPoint(x: targetX, y: targetY)
                        let tileDistance = distance(from: observerPoint, to: targetPoint)
                        guard tileDistance <= vision else { continue }

                        let targetUnit = map.foregroundElement(atX: targetX, y: targetY)
                        let targetTerrain = map.backgroundElement(atX: targetX, y: targetY)
                        let concealedSubmarine = targetUnit.isUnitNonEmpty &&
                            targetUnit.simplified == .unitSub &&
                            submergedUnits.contains(targetPoint)
                        let concealedStealth = targetUnit.isUnitNonEmpty &&
                            targetUnit.simplified == .unitStealth &&
                            stealthedUnits.contains(targetPoint)

                        if concealedSubmarine,
                           observer.simplified != .unitCruiser,
                           observer.simplified != .unitSub,
                           tileDistance > 1 {
                            continue
                        }
                        if concealedStealth,
                           observer.simplified != .unitCruiser,
                           tileDistance > 1 {
                            continue
                        }
                        if targetTerrain.simplified == .terrainWood,
                           let targetStats = PlaytestRulebook.stats(for: targetUnit, ruleset: ruleset),
                           targetStats.domain == .land,
                           observerStats.domain != .air,
                           tileDistance > 1 {
                            continue
                        }
                        if targetTerrain.simplified == .terrainReef,
                           let targetStats = PlaytestRulebook.stats(for: targetUnit, ruleset: ruleset),
                           targetStats.domain == .sea,
                           observerStats.domain != .air,
                           tileDistance > 1 {
                            continue
                        }
                        visible.insert(targetPoint)
                    }
                }
            }
        }

        visible.formUnion(flareRevealCells)

        // Owned units and properties remain visible even when they do not
        // provide vision themselves. This also preserves the old behavior for
        // an army with no active observers.
        for point in allPoints {
            let unit = map.foregroundElement(atX: point.x, y: point.y)
            let building = map.backgroundElement(atX: point.x, y: point.y)
            if (unit.isUnitNonEmpty && (unit.army == activeArmy || isAllied(unit.army, activeArmy))) ||
                (building.isBuilding && (building.army == activeArmy || isAllied(building.army, activeArmy))) {
                visible.insert(point)
            }
        }

        cachedVisibleCells = visible
        cachedVisibilityRevision = visibilityRevision
        return visible
    }

    private func invalidateVisibilityCache() {
        visibilityRevision &+= 1
        cachedVisibilityRevision = -1
        cachedVisibleCells.removeAll(keepingCapacity: true)
    }

    private func invalidatePlaytestMusic() {
        guard ruleset == .gameBoyWars3 else { return }
        musicRevision &+= 1
    }

    /// Map dimensions are stable while units move. Reuse the coordinate list
    /// needed by visibility calculations instead of allocating a new nested
    /// array every time the render-only map snapshot is requested.
    private func allMapPoints() -> [GridPoint] {
        guard cachedMapPointWidth == map.width,
              cachedMapPointHeight == map.height else {
            cachedMapPoints = (0..<map.width).flatMap { x in
                (0..<map.height).map { y in GridPoint(x: x, y: y) }
            }
            cachedMapPointWidth = map.width
            cachedMapPointHeight = map.height
            return cachedMapPoints
        }
        return cachedMapPoints
    }

    private func isHiddenEnemy(_ occupant: Element, at point: GridPoint, relativeTo unit: Element) -> Bool {
        guard occupant.isUnitNonEmpty, isHostile(occupant.army, unit.army) else { return false }
        guard isFogOfWarActive || submergedUnits.contains(point) || stealthedUnits.contains(point) else { return false }
        return !isVisible(point)
    }

    private var usesTileMovementAnimation: Bool {
        switch ruleset {
        case .famicomWars, .gameBoyWars, .gameBoyWars2, .gameBoyWars3:
            true
        case .superFamicomWars, .advanceWars, .advanceWars2, .dualStrike, .daysOfRuin:
            false
        }
    }

    private func revealAmbush(
        from origin: GridPoint,
        destination: GridPoint,
        path: MovementPath,
        paths: [GridPoint: MovementPath],
        unit: Element,
        stats: PlaytestUnitStats
    ) {
        var stop = path.previous ?? origin
        while stop != origin,
              map.foregroundElement(atX: stop.x, y: stop.y).isUnitNonEmpty,
              let previous = paths[stop]?.previous {
            stop = previous
        }

        if stop != origin {
            var candidate = map
            guard candidate.setForeground(.unitEmpty, atX: origin.x, y: origin.y),
                  candidate.setForeground(unit, atX: stop.x, y: stop.y) else {
                statusMessage = "The hidden enemy blocked the move."
                return
            }
            map = candidate
            captureProgress.removeValue(forKey: origin)
            unitHealth[stop] = unitHealth.removeValue(forKey: origin) ?? 100
            let fuel = unitFuel.removeValue(forKey: origin) ?? stats.maxFuel
            let movement = paths[stop]?.movement ?? 0
            let fuelCost = PlaytestRulebook.movementFuelCost(
                for: unit,
                movement: movement,
                ruleset: ruleset,
                weather: weather
            )
            unitFuel[stop] = max(0, fuel - fuelCost)
            unitAmmo[stop] = unitAmmo.removeValue(forKey: origin)
            cargo[stop] = cargo.removeValue(forKey: origin)
            if submergedUnits.remove(origin) != nil {
                submergedUnits.insert(stop)
            }
            if stealthedUnits.remove(origin) != nil {
                stealthedUnits.insert(stop)
            }
            movedCells.remove(origin)
            movedCells.insert(stop)
        } else {
            movedCells.insert(origin)
        }

        clearSelection()
        let enemy = map.foregroundElement(atX: destination.x, y: destination.y)
        statusMessage = "Ambush! \(PaletteCatalog.label(for: enemy, tileset: map.tileset)) was revealed. The move ends here."
    }

    private func selectBuilding(at point: GridPoint) {
        let building = map.backgroundElement(atX: point.x, y: point.y)
        selectedPoint = point
        reachableCells.removeAll()
        attackableCells.removeAll()
        captureableCells.removeAll()
        loadableCells.removeAll()
        joinableCells.removeAll()
        unloadableCells.removeAll()
        refuelableCells.removeAll()
        productionOptions = PlaytestRulebook.productionOptions(for: building, ruleset: ruleset, tileset: map.tileset)
        if productionOptions.isEmpty {
            statusMessage = "This property cannot produce units in \(ruleset.displayName)."
        } else if map.foregroundElement(atX: point.x, y: point.y) != .unitEmpty {
            statusMessage = "Clear the property before building a unit."
        } else {
            statusMessage = "Choose a unit to build. New units wait until next turn."
        }
    }

    private func moveSelectedUnit(to destination: GridPoint) {
        if usesTileMovementAnimation,
           !activeArmyIsCPU,
           !isAnimatingCPUMovement,
           !isAnimatingPlayerMovement {
            beginTileMovement(to: destination)
            return
        }

        moveSelectedUnitSynchronously(to: destination)
    }

    /// Starts the cartridge-style walk used by Famicom Wars and GB Wars 1–3.
    /// The route is committed one tile at a time so both the unit sprite and
    /// the camera can advance in lockstep instead of jumping to the endpoint.
    private func beginTileMovement(to destination: GridPoint) {
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

            for point in animatedRoute.dropFirst() {
                guard !Task.isCancelled else { return }
                guard self.map.foregroundElement(atX: point.x, y: point.y) == .unitEmpty else { return }
                let from = self.selectedPoint ?? origin
                let stepDelay = self.movementStepDelay
                self.playerMovementAnimation = PlaytestMovementAnimation(
                    unit: unit,
                    from: from,
                    to: point
                )
                self.moveSelectedUnit(to: point)
                guard self.selectedPoint == point else { return }
                self.playerMovementPath.append(point)
                await Task.yield()
                try? await Task.sleep(nanoseconds: stepDelay)
            }

            guard !Task.isCancelled else { return }
            self.playerMovementAnimation = nil
            self.isAnimatingPlayerMovement = false

            if finalTileIsOccupied {
                // Show the final destination as the camera's next tile before
                // resolving a load, join, or hidden-enemy ambush there.
                self.playerMovementPath.append(destination)
                self.moveSelectedUnit(to: destination)
            } else if let finalUnit = self.unit(at: destination),
                      let finalStats = PlaytestRulebook.stats(for: finalUnit, ruleset: self.ruleset) {
                self.configurePostMoveActions(for: finalUnit, stats: finalStats, at: destination)
            }
        }
    }

    private func moveSelectedUnitSynchronously(to destination: GridPoint) {
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
            revealAmbush(
                from: origin,
                destination: destination,
                path: path,
                paths: paths,
                unit: unit,
                stats: stats
            )
            return
        }
        if destinationUnit.isUnitNonEmpty, canJoin(unit, with: destinationUnit, at: destination) {
            joinUnit(to: destination)
            return
        }
        if destinationUnit.isUnitNonEmpty {
            guard canLoad(unit, into: destinationUnit, at: destination) else {
                statusMessage = "That unit cannot load into the selected transport."
                return
            }

            var candidate = map
            guard candidate.setForeground(.unitEmpty, atX: origin.x, y: origin.y) else {
                statusMessage = "That unit cannot load here."
                return
            }
            map = candidate
            captureProgress.removeValue(forKey: origin)
            let payload = PlaytestCargo(
                unit: unit,
                health: unitHealth.removeValue(forKey: origin) ?? 100,
                fuel: max(
                    0,
                    (unitFuel.removeValue(forKey: origin) ?? maxFuel(for: origin)) -
                        PlaytestRulebook.movementFuelCost(
                            for: unit,
                            movement: path.movement,
                            ruleset: ruleset,
                            weather: weather
                        )
                ),
                ammo: unitAmmo.removeValue(forKey: origin)
            )
            cargo[destination, default: []].append(payload)
            movedCells.remove(origin)
            selectedPoint = destination
            productionOptions.removeAll()

            if let transportStats = PlaytestRulebook.stats(for: destinationUnit, ruleset: ruleset) {
                reachableCells = movedCells.contains(destination)
                    ? []
                    : movementCells(from: destination, unit: destinationUnit, stats: transportStats)
                captureableCells.removeAll()
                attackableCells = attackableCells(from: destination, unit: destinationUnit)
                updateTransportActions(for: destinationUnit, at: destination)
            } else {
                clearSelection()
            }
            statusMessage = "Loaded \(PaletteCatalog.label(for: unit, tileset: map.tileset)) into \(PaletteCatalog.label(for: destinationUnit, tileset: map.tileset))."
            return
        }

        var candidate = map
        guard candidate.setForeground(.unitEmpty, atX: origin.x, y: origin.y),
              candidate.setForeground(unit, atX: destination.x, y: destination.y) else {
            statusMessage = "That unit cannot move there."
            return
        }

        map = candidate
        captureProgress.removeValue(forKey: origin)
        unitHealth[destination] = unitHealth.removeValue(forKey: origin) ?? 100
        let fuel = unitFuel.removeValue(forKey: origin) ?? stats.maxFuel
        let fuelCost = PlaytestRulebook.movementFuelCost(
            for: unit,
            movement: path.movement,
            ruleset: ruleset,
            weather: weather
        )
        unitFuel[destination] = max(0, fuel - fuelCost)
        unitAmmo[destination] = unitAmmo.removeValue(forKey: origin)
        cargo[destination] = cargo.removeValue(forKey: origin)
        if submergedUnits.remove(origin) != nil {
            submergedUnits.insert(destination)
        }
        if stealthedUnits.remove(origin) != nil {
            stealthedUnits.insert(destination)
        }
        movedCells.remove(origin)
        movedCells.insert(destination)
        if isAnimatingCPUMovement || isAnimatingPlayerMovement {
            // Keep the unit selected while a tile-by-tile walk is in progress.
            // Post-move actions are resolved only after the final tile, so the
            // intermediate sprite updates remain visible.
            selectedPoint = destination
            reachableCells.removeAll()
            attackableCells.removeAll()
            captureableCells.removeAll()
            loadableCells.removeAll()
            joinableCells.removeAll()
            unloadableCells.removeAll()
            refuelableCells.removeAll()
            productionOptions.removeAll()
            return
        }
        configurePostMoveActions(for: unit, stats: stats, at: destination)
    }

    /// Movement consumes the unit's movement, but Infantry and Mech units may
    /// still capture a property they moved onto. Units that can move and fire
    /// also retain their legal attack targets as a follow-up action.
    private func configurePostMoveActions(for unit: Element, stats: PlaytestUnitStats, at destination: GridPoint) {
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

    private func attack(to destination: GridPoint) {
        guard let origin = selectedPoint,
              let attacker = unit(at: origin),
              let attackerStats = PlaytestRulebook.stats(for: attacker, ruleset: ruleset) else {
            statusMessage = "That target cannot be attacked by this unit."
            return
        }

        // Pipe seams are terrain objectives, not units. They share the same
        // attack range/action rules as unit combat but do not counterattack.
        if unit(at: destination) == nil, isPipeSeam(at: destination) {
            guard canAttackPipeSeam(from: origin, to: destination, attacker: attacker) else {
                statusMessage = "That target cannot be attacked by this unit."
                return
            }
            attackPipeSeam(from: origin, to: destination, attacker: attacker)
            return
        }

        guard let defender = unit(at: destination),
              let defenderStats = PlaytestRulebook.stats(for: defender, ruleset: ruleset),
              (!movedCells.contains(origin) || attackerStats.canMoveAndFire),
              ((!submergedUnits.contains(destination) && !stealthedUnits.contains(destination)) ||
                attacker.simplified == .unitCruiser || attacker.simplified == .unitSub),
              PlaytestRulebook.canAttack(attacker, defender, ruleset: ruleset, primaryAmmo: unitAmmo[origin]),
              var damage = PlaytestRulebook.damage(
                attacker: attacker,
                defender: defender,
                ruleset: ruleset,
                attackerHealth: unitHealth[origin, default: 100],
                defenderHealth: unitHealth[destination, default: 100],
                terrain: map.backgroundElement(atX: destination.x, y: destination.y),
                primaryAmmo: unitAmmo[origin]
              ) else {
            statusMessage = "That target cannot be attacked by this unit."
            return
        }

        if hasComTower(for: attacker.army) {
            damage = min(100, Int((Double(damage) * 1.10).rounded(.down)))
        }

        let attackerUsedPrimary = PlaytestRulebook.usesPrimaryWeapon(
            attacker,
            defender,
            ruleset: ruleset,
            primaryAmmo: unitAmmo[origin]
        )
        if attackerUsedPrimary, let currentAmmo = unitAmmo[origin] {
            unitAmmo[origin] = max(0, currentAmmo - 1)
        }

        let defenderHealth = unitHealth[destination, default: 100]
        let defenderAmmo = unitAmmo[destination]
        let simultaneousCounter = PlaytestRulebook.counterattackUsesStartingStrength(ruleset)
        var candidate = map
        var defenderDestroyed = false
        let remainingDefenderHealth = defenderHealth - damage
        if remainingDefenderHealth <= 0 {
            recordDestroyedUnit(defender)
            recordDestroyedCargo(at: destination)
            _ = candidate.setForeground(.unitEmpty, atX: destination.x, y: destination.y)
            unitHealth.removeValue(forKey: destination)
            unitFuel.removeValue(forKey: destination)
            unitAmmo.removeValue(forKey: destination)
            cargo.removeValue(forKey: destination)
            submergedUnits.remove(destination)
            stealthedUnits.remove(destination)
            captureProgress.removeValue(forKey: destination)
            defenderDestroyed = true
        } else {
            unitHealth[destination] = remainingDefenderHealth
        }

        var counterattackText = ""
        var attackerDestroyed = false
        if (!defenderDestroyed || simultaneousCounter),
           defenderStats.canCounterattack,
           ((!submergedUnits.contains(origin) && !stealthedUnits.contains(origin)) ||
                defender.simplified == .unitCruiser || defender.simplified == .unitSub),
           let counterDamage = PlaytestRulebook.damage(
                attacker: defender,
                defender: attacker,
                ruleset: ruleset,
                attackerHealth: simultaneousCounter ? defenderHealth : unitHealth[destination, default: 100],
                defenderHealth: unitHealth[origin, default: 100],
                terrain: map.backgroundElement(atX: origin.x, y: origin.y),
                primaryAmmo: defenderAmmo
           ),
           isWithinRange(from: destination, to: origin, stats: defenderStats) {
            let defenderUsedPrimary = PlaytestRulebook.usesPrimaryWeapon(
                defender,
                attacker,
                ruleset: ruleset,
                primaryAmmo: defenderAmmo
            )
            if !defenderDestroyed, defenderUsedPrimary, let currentAmmo = defenderAmmo {
                unitAmmo[destination] = max(0, currentAmmo - 1)
            }
            let remainingAttackerHealth = unitHealth[origin, default: 100] - counterDamage
            if remainingAttackerHealth <= 0 {
                recordDestroyedUnit(attacker)
                recordDestroyedCargo(at: origin)
                _ = candidate.setForeground(.unitEmpty, atX: origin.x, y: origin.y)
                unitHealth.removeValue(forKey: origin)
                unitFuel.removeValue(forKey: origin)
                unitAmmo.removeValue(forKey: origin)
                cargo.removeValue(forKey: origin)
                submergedUnits.remove(origin)
                stealthedUnits.remove(origin)
                captureProgress.removeValue(forKey: origin)
                attackerDestroyed = true
                counterattackText = " The defender destroyed the attacker in the counterattack."
            } else {
                unitHealth[origin] = remainingAttackerHealth
                counterattackText = " Counterattack dealt \(counterDamage) damage."
            }
        }

        map = candidate
        if !attackerDestroyed { movedCells.insert(origin) }
        clearSelection()
        statusMessage = "\(PaletteCatalog.label(for: attacker, tileset: map.tileset)) dealt \(damage) damage to \(PaletteCatalog.label(for: defender, tileset: map.tileset))." + counterattackText
        _ = resolveRouting()
    }

    private func attackPipeSeam(from origin: GridPoint, to destination: GridPoint, attacker: Element) {
        guard let damage = pipeSeamDamage(from: origin, to: destination, attacker: attacker) else {
            statusMessage = "That target cannot be attacked by this unit."
            return
        }

        let attackerUsedPrimary = PlaytestRulebook.usesPrimaryWeapon(
            attacker,
            Element.unitInfantry,
            ruleset: ruleset,
            primaryAmmo: unitAmmo[origin]
        )
        if attackerUsedPrimary, let currentAmmo = unitAmmo[origin] {
            unitAmmo[origin] = max(0, currentAmmo - 1)
        }

        let currentHealth = pipeSeamHealth[destination, default: Self.pipeSeamStartingHealth]
        let remainingHealth = currentHealth - damage
        movedCells.insert(origin)

        if remainingHealth <= 0 {
            var candidate = map
            guard candidate.setBackground(.terrainPlain, atX: destination.x, y: destination.y, check: false) else {
                statusMessage = "That pipe seam could not be destroyed."
                return
            }
            map = candidate
            pipeSeamHealth.removeValue(forKey: destination)
            clearSelection()
            statusMessage = "\(PaletteCatalog.label(for: attacker, tileset: map.tileset)) destroyed the pipe seam."
        } else {
            pipeSeamHealth[destination] = remainingHealth
            clearSelection()
            statusMessage = "\(PaletteCatalog.label(for: attacker, tileset: map.tileset)) damaged the pipe seam (\(remainingHealth) HP remaining)."
        }
        _ = resolveRouting()
    }

    private func movementCells(from origin: GridPoint, unit: Element, stats: PlaytestUnitStats) -> Set<GridPoint> {
        let paths = movementPaths(from: origin, unit: unit, stats: stats)
        return Set(paths.compactMap { point, _ in
            let occupant = map.foregroundElement(atX: point.x, y: point.y)
            return occupant == .unitEmpty || canLoad(unit, into: occupant, at: point) ||
                canJoin(unit, with: occupant, at: point, firstPoint: origin) ||
                isHiddenEnemy(occupant, at: point, relativeTo: unit) ? point : nil
        })
    }

    private func movementRoute(
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

    private func movementPaths(from origin: GridPoint, unit: Element, stats: PlaytestUnitStats) -> [GridPoint: MovementPath] {
        let fuel = unitFuel[origin, default: stats.maxFuel]
        var paths: [GridPoint: MovementPath] = [origin: MovementPath(movement: 0, steps: 0, previous: nil)]
        var frontier: [GridPoint] = [origin]
        var index = 0

        while index < frontier.count {
            let current = frontier[index]
            index += 1
            guard let currentPath = paths[current] else { continue }

            for next in neighbors(of: current) {
                let occupant = map.foregroundElement(atX: next.x, y: next.y)
                let terrain = map.backgroundElement(atX: next.x, y: next.y)
                let isLoadDestination = canLoad(unit, into: occupant, at: next)
                let isJoinDestination = canJoin(unit, with: occupant, at: next, firstPoint: origin)
                let canPassThrough = occupant == .unitEmpty || (occupant.isUnitNonEmpty && !isHostile(occupant.army, unit.army))
                let isAmbushDestination = isHiddenEnemy(occupant, at: next, relativeTo: unit)
                let canStandOnTile = map.allowPlacement(unit, atX: next.x, y: next.y)
                let isRiver = terrain.simplified == .terrainRiver
                let cost = PlaytestRulebook.movementCost(
                    for: unit,
                    stats: stats,
                    terrain: terrain,
                    ruleset: ruleset,
                    weather: weather,
                    tileset: map.tileset
                )
                guard isValid(next),
                      (canPassThrough || isAmbushDestination),
                      (!isRiver || stats.domain == .air || cost != nil),
                      (isLoadDestination || isJoinDestination || canStandOnTile ||
                       (isRiver && cost != nil) ||
                       (occupant.isUnitNonEmpty && !isHostile(occupant.army, unit.army)) || isAmbushDestination),
                      let cost else { continue }

                let nextPath = MovementPath(
                    movement: currentPath.movement + cost,
                    steps: currentPath.steps + 1,
                    previous: current
                )
                let fuelCost = PlaytestRulebook.movementFuelCost(
                    for: unit,
                    movement: nextPath.movement,
                    ruleset: ruleset,
                    weather: weather
                )
                guard nextPath.movement <= stats.move, fuelCost <= fuel else { continue }
                if let existing = paths[next],
                   existing.movement < nextPath.movement ||
                    (existing.movement == nextPath.movement && existing.steps <= nextPath.steps) {
                    continue
                }
                paths[next] = nextPath
                // A hidden enemy is an ambush endpoint, not a square the
                // mover may pass through.
                if !isAmbushDestination {
                    frontier.append(next)
                }
            }
        }

        paths.removeValue(forKey: origin)
        return paths
    }

    private func canLoad(_ cargoUnit: Element, into transport: Element, at point: GridPoint) -> Bool {
        guard transport.isUnitNonEmpty,
                      transport.army == cargoUnit.army,
              PlaytestRulebook.canTransport(transport, cargo: cargoUnit, ruleset: ruleset),
              cargo[point, default: []].count < PlaytestRulebook.transportCapacity(for: transport, ruleset: ruleset) else { return false }
        return true
    }

    private func canJoin(_ first: Element, with second: Element, at point: GridPoint, firstPoint: GridPoint? = nil) -> Bool {
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

    private func updateTransportActions(for transport: Element, at point: GridPoint) {
        loadableCells.removeAll()
        joinableCells.removeAll()
        unloadableCells.removeAll()
        refuelableCells.removeAll()

        let capacity = PlaytestRulebook.transportCapacity(for: transport, ruleset: ruleset)
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

        if capacity == 0 {
            for neighbor in neighbors(of: point) {
                guard isValid(neighbor),
                      let candidate = self.unit(at: neighbor),
                      canJoin(transport, with: candidate, at: neighbor) else { continue }
                joinableCells.insert(neighbor)
            }
        }

        if let loaded = cargo[point], !loaded.isEmpty {
            let index = min(selectedCargoIndex, loaded.count - 1)
            let selected = loaded[index]
            for neighbor in neighbors(of: point) where isValid(neighbor) {
                guard canUnload(selected.unit, from: transport, at: neighbor) else { continue }
                unloadableCells.insert(neighbor)
            }
        }

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

    private func canUnload(_ cargoUnit: Element, from transport: Element, at destination: GridPoint) -> Bool {
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

    private func loadUnit(from source: GridPoint) {
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

    private func joinUnit(to destination: GridPoint) {
        guard let origin = selectedPoint,
              let first = unit(at: origin),
              let second = unit(at: destination),
              let firstStats = PlaytestRulebook.stats(for: first, ruleset: ruleset),
              !movedCells.contains(origin),
              canJoin(first, with: second, at: destination),
              let path = movementPaths(from: origin, unit: first, stats: firstStats)[destination] else {
            statusMessage = "Those units cannot join."
            return
        }

        let firstHealth = unitHealth[origin, default: 100]
        let secondHealth = unitHealth[destination, default: 100]
        let combinedHealth = firstHealth + secondHealth
        let excessHP = max(0, combinedHealth - 100) / 10
        if excessHP > 0,
           let stats = PlaytestRulebook.stats(for: first, ruleset: ruleset) {
            funds[activeArmy, default: 0] += excessHP * max(1, stats.cost / 10)
        }

        var candidate = map
        guard candidate.setForeground(.unitEmpty, atX: origin.x, y: origin.y) else {
            statusMessage = "Those units cannot join."
            return
        }
        map = candidate
        unitHealth[destination] = min(100, combinedHealth)
        let maxFuel = PlaytestRulebook.maxFuel(for: second, ruleset: ruleset)
        let fuelCost = PlaytestRulebook.movementFuelCost(
            for: first,
            movement: path.movement,
            ruleset: ruleset,
            weather: weather
        )
        let firstFuelAfterMove = max(0, unitFuel[origin, default: maxFuel] - fuelCost)
        unitFuel[destination] = min(maxFuel, firstFuelAfterMove + unitFuel[destination, default: maxFuel])
        if let ammo = PlaytestRulebook.primaryAmmo(for: second, ruleset: ruleset) {
            unitAmmo[destination] = min(ammo, unitAmmo[origin, default: ammo] + unitAmmo[destination, default: ammo])
        }
        unitHealth.removeValue(forKey: origin)
        unitFuel.removeValue(forKey: origin)
        unitAmmo.removeValue(forKey: origin)
        captureProgress.removeValue(forKey: origin)
        captureProgress.removeValue(forKey: destination)
        submergedUnits.remove(origin)
        stealthedUnits.remove(origin)
        movedCells.remove(origin)
        movedCells.insert(destination)
        clearSelection()
        statusMessage = "Joined the two \(PaletteCatalog.label(for: second, tileset: map.tileset)) units."
    }

    private func unloadUnit(to destination: GridPoint) {
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

        let targets: [GridPoint]
        if transport.simplified == .unitBlackBoat {
            guard let target, refuelableCells.contains(target) else {
                statusMessage = "Choose one adjacent unit for the Black Boat to repair."
                return
            }
            targets = [target]
        } else {
            targets = Array(refuelableCells)
        }

        var repairedCount = 0
        for neighbor in targets {
            unitFuel[neighbor] = maxFuel(for: neighbor)
            if let adjacent = unit(at: neighbor),
               let ammo = PlaytestRulebook.primaryAmmo(for: adjacent, ruleset: ruleset) {
                unitAmmo[neighbor] = ammo
            }
            if transport.simplified == .unitBlackBoat,
               let adjacent = unit(at: neighbor),
               let stats = PlaytestRulebook.stats(for: adjacent, ruleset: ruleset),
               unitHealth[neighbor, default: 100] < 100 {
                let repairCost = max(1, stats.cost / 10)
                if funds[transport.army, default: 0] >= repairCost {
                    funds[transport.army, default: 0] -= repairCost
                    unitHealth[neighbor] = min(100, unitHealth[neighbor, default: 100] + 10)
                    repairedCount += 1
                }
            }
        }
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

    private func refuelAdjacentUnits(for army: Int) {
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
    private func resupplyCarriedAircraft(for army: Int) {
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

    private func isPipeSeam(at point: GridPoint) -> Bool {
        guard isValid(point) else { return false }
        let background = map.backgroundElement(atX: point.x, y: point.y)
        if background.simplified == .terrainSeam { return true }
        // Imported maps can retain the seam in the derived draw layer while
        // storing the underlying tile as Plain D. Treat that visual seam as
        // the same attackable objective during playtest.
        return background.simplified == .terrainPlainD &&
            map.backgroundDrawElement(atX: point.x, y: point.y).simplified == .terrainSeam
    }

    private func canAttackPipeSeam(from origin: GridPoint, to destination: GridPoint, attacker: Element) -> Bool {
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

    private func pipeSeamDamage(from origin: GridPoint, to destination: GridPoint, attacker: Element) -> Int? {
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

    private func attackableCells(from origin: GridPoint, unit: Element) -> Set<GridPoint> {
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

    private func attackRangeCells(from origin: GridPoint, unit: Element) -> Set<GridPoint> {
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

    private func isWithinRange(from origin: GridPoint, to destination: GridPoint, stats: PlaytestUnitStats?) -> Bool {
        guard let stats else { return false }
        let distance = distance(from: origin, to: destination)
        let weatherMaxRange = PlaytestRulebook.maximumAttackRange(
            for: stats,
            ruleset: ruleset,
            weather: weather
        )
        return distance >= stats.minRange && distance <= weatherMaxRange
    }

    private func canCapture(unit: Element, stats: PlaytestUnitStats, at point: GridPoint) -> Bool {
        guard stats.canCapture else { return false }
        let building = map.backgroundElement(atX: point.x, y: point.y)
        return PlaytestRulebook.isCapturableBuilding(building, ruleset: ruleset) &&
            (building.army == AWConstants.armyNeutral || isHostile(building.army, activeArmy))
    }

    private func collectIncome(for army: Int) {
        var income = 0
        for x in 0..<map.width {
            for y in 0..<map.height {
                let building = map.backgroundElement(atX: x, y: y)
                if building.isBuilding, building.army == army { income += PlaytestRulebook.income(for: building) }
            }
        }
        funds[army, default: 0] += income
    }

    private func repairUnits(for army: Int) {
        for x in 0..<map.width {
            for y in 0..<map.height {
                let point = GridPoint(x: x, y: y)
                let unit = map.foregroundElement(atX: x, y: y)
                let building = map.backgroundElement(atX: x, y: y)
                guard unit.isUnitNonEmpty,
                      unit.army == army,
                      building.isBuilding,
                      building.army == army,
                      canRepair(unit, on: building) else { continue }
                let currentHealth = unitHealth[point, default: 100]
                let missingHealth = max(0, 100 - currentHealth)
                let requestedHP = min(2, missingHealth / 10)
                let costPerHP = max(1, (PlaytestRulebook.stats(for: unit, ruleset: ruleset)?.cost ?? 0) / 10)
                let affordableHP = min(requestedHP, funds[army, default: 0] / costPerHP)
                unitHealth[point] = min(100, currentHealth + affordableHP * 10)
                funds[army, default: 0] -= affordableHP * costPerHP
                unitFuel[point] = PlaytestRulebook.maxFuel(for: unit, ruleset: ruleset)
                if let ammo = PlaytestRulebook.primaryAmmo(for: unit, ruleset: ruleset) {
                    unitAmmo[point] = ammo
                }
            }
        }
    }

    private func canRepair(_ unit: Element, on building: Element) -> Bool {
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

    private func hasComTower(for army: Int) -> Bool {
        guard ruleset == .dualStrike || ruleset == .advanceWars2 else { return false }
        return allMapPoints().contains { point in
            let building = map.backgroundElement(atX: point.x, y: point.y)
            return building.simplified == .buildingTower && building.army == army
        }
    }

    @discardableResult
    private func consumeDailyFuel(for army: Int) -> Int {
        var destroyed: [GridPoint] = []
        for x in 0..<map.width {
            for y in 0..<map.height {
                let point = GridPoint(x: x, y: y)
                let unit = map.foregroundElement(atX: x, y: y)
                guard unit.isUnitNonEmpty, unit.army == army,
                      let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset) else { continue }

                let dailyFuelUse: Int
                if unit.simplified == .unitSub, submergedUnits.contains(point) {
                    dailyFuelUse = 5
                } else {
                    dailyFuelUse = stats.dailyFuelUse
                }
                guard dailyFuelUse > 0 else { continue }

                let remaining = unitFuel[point, default: stats.maxFuel] - dailyFuelUse
                if remaining <= 0, stats.domain == .air || stats.domain == .sea {
                    destroyed.append(point)
                } else {
                    unitFuel[point] = max(0, remaining)
                }
            }
        }

        guard !destroyed.isEmpty else { return 0 }
        var candidate = map
        for point in destroyed {
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
        return destroyed.count
    }

    @discardableResult
    private func processTurnStart(for army: Int) -> Int {
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
    private func resolveRouting() -> [Int] {
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
    private func resolveDominationVictory(for candidates: [Int]) -> Bool {
        guard ruleset == .superFamicomWars else { return false }

        let candidateTeams = Set(candidates.map { team(for: $0) })
        guard candidates.count > 1, candidateTeams.count > 1 else { return false }

        let properties = allMapPoints().compactMap { point -> Element? in
            let building = map.backgroundElement(atX: point.x, y: point.y)
            return PlaytestRulebook.isCapturableBuilding(building, ruleset: ruleset)
                ? building
                : nil
        }
        guard !properties.isEmpty else { return false }

        let totalProperties = properties.count
        let activeTeam = team(for: activeArmy)
        var evaluatedTeams: Set<PlaytestTeam> = []
        var winningTeam: PlaytestTeam?
        var winningCount = 0

        for army in candidates {
            let candidateTeam = team(for: army)
            guard evaluatedTeams.insert(candidateTeam).inserted else { continue }

            let ownedProperties = properties.reduce(into: 0) { count, building in
                guard building.army != AWConstants.armyNeutral,
                      candidates.contains(building.army),
                      team(for: building.army) == candidateTeam else { return }
                count += 1
            }
            guard ownedProperties * 100 >= totalProperties * 75 else { continue }

            // Prefer the active team when two sides somehow qualify on the
            // same map state; otherwise keep the first qualifying side in the
            // stable army order used by the playtest session.
            if ownedProperties > winningCount ||
                (ownedProperties == winningCount && candidateTeam == activeTeam && winningTeam != activeTeam) {
                winningTeam = candidateTeam
                winningCount = ownedProperties
            }
        }

        guard let winningTeam,
              let winner = candidates.first(where: { team(for: $0) == winningTeam }) else {
            return false
        }

        winnerArmy = winner
        statusMessage = "\(armyName(winner)) wins by Domination (\(winningCount)/\(totalProperties) properties)."
        return true
    }

    private var usesUnitEliminationVictory: Bool {
        switch ruleset {
        case .famicomWars, .superFamicomWars:
            return true
        default:
            return false
        }
    }

    private func hasUnits(for army: Int) -> Bool {
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

    private func recordUnitPresence() {
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

    private func recordDestroyedUnit(_ unit: Element) {
        guard unit.isUnitNonEmpty else { return }
        destroyedUnitCounts[unit.army, default: 0] += 1
    }

    private func recordDestroyedCargo(at point: GridPoint) {
        for payload in cargo[point, default: []] {
            recordDestroyedUnit(payload.unit)
        }
    }

    private func unitCount(for army: Int) -> Int {
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

    private func hasProductionProperty(for army: Int) -> Bool {
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

    private func neutralizeProperties(of army: Int) {
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
    private func runCPUIfNeeded() {
        guard !isExecutingCPU, isCPUArmy(activeArmy), !isGameOver else { return }

        isExecutingCPU = true
        let runID = UUID()
        cpuRunID = runID
        cpuTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.cpuRunID == runID {
                    self.isExecutingCPU = false
                    self.cpuTask = nil
                    self.clearCPUMovementPreview()
                    self.cpuMovementPathCache.removeAll(keepingCapacity: true)
                }
            }

            var actionCount = 0
            var cpuTurnStart = DispatchTime.now().uptimeNanoseconds
            while self.isCPUArmy(self.activeArmy), !self.isGameOver {
                // Keep the malformed-map safety valve, but scope it to the
                // current army's turn. A CPU-vs-CPU game must be allowed to
                // continue across turns until routing or HQ capture produces
                // an actual winner.
                if actionCount >= 400 {
                    self.clearCPUMovementPreview()
                    guard await self.waitForMinimumCPUTurn(start: cpuTurnStart, runID: runID) else { return }
                    self.endTurn()
                    cpuTurnStart = DispatchTime.now().uptimeNanoseconds
                    actionCount = 0
                    try? await Task.sleep(nanoseconds: self.scaledCPUDelay(Self.cpuTurnPause))
                    continue
                }

                // Planning runs on the main actor because it reads the live
                // session. Give SwiftUI a scheduling point before each
                // action so a large map cannot monopolize the actor while
                // the CPU is thinking.
                await Task.yield()
                guard !Task.isCancelled, self.cpuRunID == runID else { return }
                actionCount += 1
                guard let plan = self.bestCPUPlan() else {
                    self.clearCPUMovementPreview()
                    guard await self.waitForMinimumCPUTurn(start: cpuTurnStart, runID: runID) else { return }
                    self.endTurn()
                    cpuTurnStart = DispatchTime.now().uptimeNanoseconds
                    actionCount = 0
                    // A malformed or empty CPU turn should still yield before
                    // evaluating the next army rather than becoming a tight
                    // synchronous loop.
                    try? await Task.sleep(nanoseconds: self.scaledCPUDelay(Self.cpuTurnPause))
                    continue
                }

                let previousArmy = self.activeArmy
                let previousMoved = self.movedCells
                let previousSelection = self.selectedPoint
                self.prepareCPUMovementPreview(for: plan.action)

                // Yield to SwiftUI so the current enemy unit's marker is
                // visible before the CPU commits its action.
                try? await Task.sleep(nanoseconds: self.scaledCPUDelay(Self.cpuActionPreviewDelay))
                guard !Task.isCancelled, self.cpuRunID == runID else { return }

                await self.executeCPU(plan.action)
                self.clearCPUMovementPreview()

                // A legal plan should always consume an action or advance the
                // turn. Clear a stale selection if a malformed map rejects it
                // so the CPU cannot spin on the same plan forever.
                if self.activeArmy == previousArmy,
                   self.movedCells == previousMoved,
                   self.selectedPoint == previousSelection {
                    self.clearSelection()
                    self.statusMessage = "The CPU ended an unavailable action."
                }

                let pause = self.activeArmy == previousArmy
                    ? Self.cpuActionPause
                    : Self.cpuTurnPause
                try? await Task.sleep(nanoseconds: self.scaledCPUDelay(pause))
                guard !Task.isCancelled, self.cpuRunID == runID else { return }
            }

            if self.isCPUArmy(self.activeArmy), !self.isGameOver {
                guard await self.waitForMinimumCPUTurn(start: cpuTurnStart, runID: runID) else { return }
                self.endTurn()
            }
        }
    }

    /// Keeps short CPU turns readable without blocking the main actor. The
    /// task's cancellation is checked both while sleeping and by the caller,
    /// so closing/restarting playtest never waits out the pacing interval.
    private func waitForMinimumCPUTurn(start: UInt64, runID: UUID) async -> Bool {
        let elapsed = DispatchTime.now().uptimeNanoseconds &- start
        if elapsed < cpuMinimumTurnDuration {
            try? await Task.sleep(nanoseconds: cpuMinimumTurnDuration - elapsed)
        }
        return !Task.isCancelled && cpuRunID == runID
    }

    private func prepareCPUMovementPreview(for action: CPUAction) {
        clearCPUMovementPreview()
        cpuActionPoint = actionFocusPoint(for: action)
        // The cartridge cursor is the CPU's visible hand. Put it on the
        // action's focus before the preview pause so captures, attacks,
        // production, and movement all read as deliberate cursor actions.
        cursorPoint = cpuActionPoint

        guard case let .move(origin, _) = action,
              let unit = unit(at: origin),
              unit.army == activeArmy,
              PlaytestRulebook.stats(for: unit, ruleset: ruleset) != nil,
              !movedCells.contains(origin) else { return }

        cpuMovementPath = [origin]
    }

    private func actionFocusPoint(for action: CPUAction) -> GridPoint {
        switch action {
        case let .attack(_, target), let .capture(target), let .build(target, _),
             let .resupply(target), let .detonate(target), let .flare(target),
             let .stealth(target), let .wait(target):
            return target
        case let .move(origin, _), let .join(origin, _), let .load(origin, _),
             let .unload(origin, _):
            return origin
        }
    }

    private func clearCPUMovementPreview() {
        cpuMovementPath.removeAll(keepingCapacity: true)
        cpuMovementAnimation = nil
    }

    private func makeCPUPlanningSnapshot() -> CPUPlanningSnapshot {
        var ownUnitPoints: [GridPoint] = []
        var enemyUnitPoints: [GridPoint] = []
        var enemyUnits: [CPUEnemyInfo] = []
        var ownPropertyPoints: [GridPoint] = []
        var enemyPropertyPoints: [GridPoint] = []
        var enemyHQPoints: [GridPoint] = []
        var pipeSeamPoints: [GridPoint] = []
        var ownCounts: [Int: Int] = [:]
        var ownDomains = (land: 0, air: 0, sea: 0)
        var enemyDomains = (land: 0, air: 0, sea: 0)

        for point in allMapPoints() {
            let unit = map.foregroundElement(atX: point.x, y: point.y)
            if unit.isUnitNonEmpty,
               let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset) {
                if unit.army == activeArmy {
                    ownUnitPoints.append(point)
                    ownCounts[unit.simplified.value, default: 0] += 1
                    switch stats.domain {
                    case .land: ownDomains.land += 1
                    case .air: ownDomains.air += 1
                    case .sea: ownDomains.sea += 1
                    }
                } else if isHostile(unit.army, activeArmy),
                          (!isFogOfWarActive || isVisible(point)) {
                    enemyUnitPoints.append(point)
                    enemyUnits.append(CPUEnemyInfo(point: point, unit: unit, stats: stats))
                    switch stats.domain {
                    case .land: enemyDomains.land += 1
                    case .air: enemyDomains.air += 1
                    case .sea: enemyDomains.sea += 1
                    }
                }
            }

            let building = map.backgroundElement(atX: point.x, y: point.y)
            if building.simplified == .buildingHQ, isHostile(building.army, activeArmy) {
                enemyHQPoints.append(point)
            }
            if building.isBuilding, building.army == activeArmy {
                ownPropertyPoints.append(point)
            } else if PlaytestRulebook.isCapturableBuilding(building, ruleset: ruleset),
                      (building.army == AWConstants.armyNeutral || isHostile(building.army, activeArmy)),
                      (!isFogOfWarActive || building.army == AWConstants.armyNeutral || isVisible(point)) {
                enemyPropertyPoints.append(point)
            }
            if isPipeSeam(at: point) {
                pipeSeamPoints.append(point)
            }
        }

        return CPUPlanningSnapshot(
            ownUnitPoints: ownUnitPoints,
            enemyUnitPoints: enemyUnitPoints,
            enemyUnits: enemyUnits,
            ownPropertyPoints: ownPropertyPoints,
            enemyPropertyPoints: enemyPropertyPoints,
            enemyHQPoints: enemyHQPoints,
            pipeSeamPoints: pipeSeamPoints,
            ownCounts: ownCounts,
            ownDomains: ownDomains,
            enemyDomains: enemyDomains
        )
    }

    private func bestCPUPlan() -> CPUPlan? {
        cpuPlanningSnapshot = makeCPUPlanningSnapshot()
        cpuThreatCache.removeAll(keepingCapacity: true)
        cpuMovementPathCache.removeAll(keepingCapacity: true)
        cpuAttackableCache.removeAll(keepingCapacity: true)
        cpuNearestEnemyDistanceCache.removeAll(keepingCapacity: true)
        cpuNearestEnemyPropertyDistanceCache.removeAll(keepingCapacity: true)
        cpuTransportDropOffCache.removeAll(keepingCapacity: true)
        defer {
            cpuPlanningSnapshot = nil
            cpuThreatCache.removeAll(keepingCapacity: true)
            cpuAttackableCache.removeAll(keepingCapacity: true)
            cpuNearestEnemyDistanceCache.removeAll(keepingCapacity: true)
            cpuNearestEnemyPropertyDistanceCache.removeAll(keepingCapacity: true)
            cpuTransportDropOffCache.removeAll(keepingCapacity: true)
        }

        if let followUp = cpuFollowUpPlan() { return followUp }

        var plans: [CPUPlan] = []
        plans.append(contentsOf: cpuAttackPlans())
        plans.append(contentsOf: cpuCapturePlans())
        plans.append(contentsOf: cpuTransportPlans())
        plans.append(contentsOf: cpuSpecialPlans())
        plans.append(contentsOf: cpuBuildPlans())
        plans.append(contentsOf: cpuMovePlans())
        plans.append(contentsOf: cpuWaitPlans())
        return plans.max { lhs, rhs in
            if lhs.score == rhs.score {
                return cpuActionOrder(lhs.action) < cpuActionOrder(rhs.action)
            }
            return lhs.score < rhs.score
        }
    }

    /// A moved unit stays selected long enough to resolve an available attack
    /// or capture a property it entered. Other actions remain pre-movement
    /// actions.
    private func cpuFollowUpPlan() -> CPUPlan? {
        guard let point = selectedPoint,
              let unit = unit(at: point),
              unit.army == activeArmy else { return nil }
        let policy = cpuPolicy

        if movedCells.contains(point) {
            if unit.simplified == .unitBlackBomb {
                return CPUPlan(score: 620, action: .detonate(point: point))
            }
            if ruleset == .daysOfRuin, unit.simplified == .unitOozium {
                return CPUPlan(score: 120, action: .flare(point: point))
            }
            let capturePlan = sortedGridPoints(captureableCells).first.map {
                CPUPlan(score: captureScore(at: $0), action: .capture(point: $0))
            }
            let attackPlan: CPUPlan? = sortedGridPoints(attackableCells).max(
                by: { attackScore(from: point, to: $0) < attackScore(from: point, to: $1) }
            ).map {
                CPUPlan(score: attackScore(from: point, to: $0), action: .attack(origin: point, target: $0))
            }
            return [capturePlan, attackPlan].compactMap { $0 }.max { lhs, rhs in
                lhs.score < rhs.score
            } ?? CPUPlan(score: -10, action: .wait(point: point))
        }

        let capturePlan = sortedGridPoints(captureableCells).first.map {
            CPUPlan(score: captureScore(at: $0), action: .capture(point: $0))
        }
        let attackPlan: CPUPlan? = sortedGridPoints(attackableCells).max(
            by: { attackScore(from: point, to: $0) < attackScore(from: point, to: $1) }
        ).map {
            CPUPlan(score: attackScore(from: point, to: $0), action: .attack(origin: point, target: $0))
        }
        if let immediatePlan = [capturePlan, attackPlan].compactMap({ $0 }).max(by: { $0.score < $1.score }) {
            return immediatePlan
        }

        let capacity = PlaytestRulebook.transportCapacity(for: unit, ruleset: ruleset)
        if capacity > 0, let cargoPoint = sortedGridPoints(loadableCells).first {
            return CPUPlan(
                score: 150 * policy.transportActionMultiplier,
                action: .load(transport: point, cargo: cargoPoint)
            )
        }
        if capacity == 0, !movedCells.contains(point), let transportPoint = sortedGridPoints(loadableCells).first {
            return CPUPlan(
                score: 145 * policy.transportActionMultiplier,
                action: .move(origin: point, destination: transportPoint)
            )
        }
        if let destination = sortedGridPoints(unloadableCells).first {
            return CPUPlan(
                score: 140 * policy.transportActionMultiplier,
                action: .unload(transport: point, destination: destination)
            )
        }
        if let destination = sortedGridPoints(joinableCells).first {
            return CPUPlan(score: 95, action: .join(origin: point, destination: destination))
        }
        if !refuelableCells.isEmpty {
            return CPUPlan(
                score: 90 * policy.supplyActionMultiplier,
                action: .resupply(point: point)
            )
        }

        return nil
    }

    private func executeCPU(_ action: CPUAction) async {
        switch action {
        case let .attack(origin, target):
            selectedPoint = origin
            attack(to: target)
        case let .capture(point):
            selectedPoint = point
            capture()
        case let .build(point, option):
            selectedPoint = point
            buildUnit(option)
        case let .move(origin, destination):
            await executeCPUMove(from: origin, to: destination)
        case let .load(transport, cargoPoint):
            selectedPoint = transport
            if let transportUnit = unit(at: transport) {
                updateTransportActions(for: transportUnit, at: transport)
            }
            loadUnit(from: cargoPoint)
        case let .unload(transport, destination):
            selectedPoint = transport
            if let transportUnit = unit(at: transport) {
                updateTransportActions(for: transportUnit, at: transport)
            }
            unloadUnit(to: destination)
        case let .join(origin, destination):
            selectedPoint = origin
            joinUnit(to: destination)
        case let .resupply(point):
            selectedPoint = point
            if let transport = unit(at: point) {
                updateTransportActions(for: transport, at: point)
            }
            resupplySelectedTransport(target: sortedGridPoints(refuelableCells).first)
        case let .detonate(point):
            selectedPoint = point
            detonateBlackBomb()
        case let .flare(point):
            selectedPoint = point
            useFlare()
        case let .stealth(point):
            selectedPoint = point
            toggleStealth()
        case let .wait(point):
            selectedPoint = point
            wait()
        }
    }

    private func cpuActionOrder(_ action: CPUAction) -> Int {
        switch action {
        case .attack: 0
        case .capture: 1
        case .load, .unload, .join, .resupply, .detonate, .flare, .stealth: 2
        case .build: 3
        case .move: 4
        case .wait: 5
        }
    }

    /// Commits a CPU move one tile at a time so the unit appears to walk,
    /// tread, sail, or fly across the board instead of teleporting to the
    /// planned destination. The existing movement routine still owns all
    /// legality, fuel, cargo, and post-move-action rules.
    private func executeCPUMove(from origin: GridPoint, to destination: GridPoint) async {
        cursorPoint = origin
        guard let unit = unit(at: origin),
              let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset) else {
            selectUnit(at: origin)
            cursorPoint = destination
            moveSelectedUnit(to: destination)
            return
        }

        let paths = movementPaths(from: origin, unit: unit, stats: stats)
        guard paths[destination] != nil else {
            selectUnit(at: origin)
            cursorPoint = destination
            moveSelectedUnit(to: destination)
            return
        }

        var route: [GridPoint] = []
        var current = destination
        while current != origin {
            guard let path = paths[current], let previous = path.previous else {
                selectUnit(at: origin)
                cursorPoint = destination
                moveSelectedUnit(to: destination)
                return
            }
            route.append(current)
            current = previous
        }
        route.reverse()

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
        var stoppedAtOccupiedIntermediate = false

        for point in animatedRoute {
            guard !Task.isCancelled else { return }
            guard map.foregroundElement(atX: point.x, y: point.y) == .unitEmpty else {
                // Same-army units can be passed through for pathfinding, but
                // they cannot be occupied during the visual walk. Let the
                // normal final move resolve that route without corrupting a
                // friendly unit's tile.
                stoppedAtOccupiedIntermediate = true
                break
            }

            let from = selectedPoint ?? origin
            let stepDelay = movementStepDelay
            cpuMovementAnimation = PlaytestMovementAnimation(
                unit: unit,
                from: from,
                to: point
            )
            cursorPoint = point
            moveSelectedUnit(to: point)
            guard selectedPoint == point else { return }
            // Keep the cursor assignment after the map mutation as well. The
            // map setter can trigger a render before the movement state has
            // been observed, so this guarantees the frame follows the tile
            // that was just committed.
            cursorPoint = point
            cpuMovementPath.append(point)
            await Task.yield()
            try? await Task.sleep(nanoseconds: stepDelay)
        }

        guard !Task.isCancelled else { return }
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

    private func cpuUnitPoints() -> [GridPoint] {
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

    private func cpuPropertyPoints() -> [GridPoint] {
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

    private func cpuAttackPlans() -> [CPUPlan] {
        var plans: [CPUPlan] = []
        for origin in cpuUnitPoints() where !movedCells.contains(origin) {
            let unit = map.foregroundElement(atX: origin.x, y: origin.y)
            for target in sortedGridPoints(cpuAttackableCells(from: origin, unit: unit)) {
                plans.append(CPUPlan(score: attackScore(from: origin, to: target), action: .attack(origin: origin, target: target)))
            }
        }
        return plans
    }

    private func cpuAttackableCells(from origin: GridPoint, unit attacker: Element) -> Set<GridPoint> {
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
        var result: Set<GridPoint> = []
        for enemy in cpuEnemyUnits() {
            let point = enemy.point
            guard isWithinRange(from: origin, to: point, stats: stats),
                  (!requiresVisibility || isVisible(point)),
                  ((!submergedUnits.contains(point) && !stealthedUnits.contains(point)) ||
                    attacker.simplified == .unitCruiser || attacker.simplified == .unitSub),
                  PlaytestRulebook.canAttack(attacker, enemy.unit, ruleset: ruleset, primaryAmmo: unitAmmo[origin]) else { continue }
            result.insert(point)
        }
        for point in cpuPipeSeamPoints() {
            guard isWithinRange(from: origin, to: point, stats: stats),
                  canAttackPipeSeam(from: origin, to: point, attacker: attacker) else { continue }
            result.insert(point)
        }
        cpuAttackableCache[key] = result
        return result
    }

    /// Movement paths are stable for the duration of one planning pass. The
    /// planner previously rebuilt this BFS once for transport joins and again
    /// for every movement candidate, which multiplied the cost on larger maps.
    private func cpuMovementPaths(
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

    private func cpuPipeSeamPoints() -> [GridPoint] {
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

    private func attackScore(from origin: GridPoint, to target: GridPoint) -> Double {
        let attacker = map.foregroundElement(atX: origin.x, y: origin.y)
        let defender = map.foregroundElement(atX: target.x, y: target.y)
        let policy = cpuPolicy

        if defender == .unitEmpty, isPipeSeam(at: target),
           let damage = pipeSeamDamage(from: origin, to: target, attacker: attacker) {
            let currentHealth = pipeSeamHealth[target, default: Self.pipeSeamStartingHealth]
            let destructionBonus = currentHealth <= damage ? 900.0 : 420.0
            let nearbyEnemyCount = allEnemyUnitPoints().filter {
                distance(from: target, to: $0) <= 4
            }.count
            let threatPenalty = min(
                Double(cpuThreat(for: attacker, at: origin)) * 0.35,
                75
            )
            // Opening a seam is a strategic objective, not a low-value empty
            // tile. Prefer a finishing shot, then a hit that creates access
            // for the rest of the army.
            return 500 + destructionBonus + Double(damage) * 5
                + Double(nearbyEnemyCount) * 12 - threatPenalty
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
        let distance = distance(from: origin, to: target)
        let terrainStars = PlaytestRulebook.terrainStars(
            for: targetTerrain,
            ruleset: ruleset
        )
        let counterDamage: Int
        if defenderStats.canCounterattack,
           isWithinRange(from: target, to: origin, stats: defenderStats),
           let value = PlaytestRulebook.damage(
            attacker: defender,
            defender: attacker,
            ruleset: ruleset,
            attackerHealth: defenderHealth,
            defenderHealth: unitHealth[origin, default: 100],
            terrain: map.backgroundElement(atX: origin.x, y: origin.y),
            primaryAmmo: unitAmmo[target],
            randomize: false
           ) {
            counterDamage = value
        } else {
            counterDamage = 0
        }

        let lethalBonus = damage >= defenderHealth ? 700.0 : 0
        let targetValue = Double(defenderStats.cost) / 20 * policy.targetCostMultiplier
        let damageValue = Double(damage) * 7
        let healthValue = Double(defenderHealth) / 8
        let terrainPenalty = Double(terrainStars) * 3
        let distancePenalty = Double(distance)
        let transportCapacity = PlaytestRulebook.transportCapacity(
            for: defender,
            ruleset: ruleset
        )
        let transportTargetBonus: Double
        if transportCapacity > 0 {
            let isLoaded = !cargo[target, default: []].isEmpty
            transportTargetBonus = 42 * policy.transportTargetMultiplier
                + (isLoaded ? policy.loadedTransportBonus : 0)
        } else {
            transportTargetBonus = 0
        }
        // Counter-fire matters, but multiplying it by the whole unit cost made
        // expensive units refuse perfectly reasonable trades. Keep the risk
        // proportional to the attacker's cost and cap it so a legal shot is
        // not silently turned into a wait action.
        let retaliationMultiplier = (0.75 + (Double(attackerStats.cost) / 5_000))
            * policy.counterRiskMultiplier
        let retaliationPenalty = min(
            360,
            Double(counterDamage) * retaliationMultiplier
        )
        let threatPenalty = min(
            Double(cpuThreat(for: attacker, at: origin)) * 0.35 * policy.threatMultiplier,
            70
        )
        let indirectMultiplier = attackerStats.canMoveAndFire
            ? 1.0
            : policy.indirectAttackMultiplier
        // A legal shot against another army is itself a useful result. Keep
        // that floor high enough that the CPU does not pass on every attack
        // just because a safer build or move scored similarly.
        let attackPriority = policy.attackBias
        let hqTargetBonus = ruleset == .famicomWars && targetTerrain.simplified == .buildingHQ
            ? 500.0
            : 0
        return attackPriority + lethalBonus + targetValue + damageValue * indirectMultiplier + healthValue
            + transportTargetBonus + hqTargetBonus
            - terrainPenalty - distancePenalty - retaliationPenalty - threatPenalty
    }

    private func cpuCapturePlans() -> [CPUPlan] {
        var plans: [CPUPlan] = []
        for point in cpuUnitPoints() where !movedCells.contains(point) {
            let unit = map.foregroundElement(atX: point.x, y: point.y)
            guard let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset),
                  canCapture(unit: unit, stats: stats, at: point) else { continue }
            plans.append(CPUPlan(score: captureScore(at: point), action: .capture(point: point)))
        }
        return plans
    }

    private func captureScore(at point: GridPoint) -> Double {
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

    private func cpuTransportPlans() -> [CPUPlan] {
        var plans: [CPUPlan] = []
        let policy = cpuPolicy
        for point in cpuUnitPoints() where !movedCells.contains(point) {
            let unitElement = map.foregroundElement(atX: point.x, y: point.y)
            let capacity = PlaytestRulebook.transportCapacity(for: unitElement, ruleset: ruleset)

            if capacity > 0, cargo[point, default: []].count < capacity {
                for neighbor in neighbors(of: point) where isValid(neighbor) {
                    guard let candidate = unit(at: neighbor),
                          canLoad(candidate, into: unitElement, at: point) else { continue }
                    let cargoCost = PlaytestRulebook.stats(for: candidate, ruleset: ruleset)?.cost ?? 0
                    plans.append(CPUPlan(
                        score: 120 * policy.transportActionMultiplier + Double(cargoCost) / 100,
                        action: .load(transport: point, cargo: neighbor)
                    ))
                }
            }

            if let loaded = cargo[point]?.first {
                for neighbor in neighbors(of: point) where isValid(neighbor) {
                    guard canUnload(loaded.unit, from: unitElement, at: neighbor) else { continue }
                    let destinationScore = cpuDestinationScore(for: loaded.unit, at: neighbor)
                    plans.append(CPUPlan(
                        score: 115 * policy.transportActionMultiplier + destinationScore,
                        action: .unload(transport: point, destination: neighbor)
                    ))
                }
            }

            if PlaytestRulebook.resuppliesAdjacentUnits(unitElement, ruleset: ruleset) ||
                unitElement.simplified == .unitBlackBoat {
                let needsResupply = resupplyNeighbors(of: point, transport: unitElement).contains { neighbor in
                    guard isValid(neighbor), let adjacent = self.unit(at: neighbor), adjacent.army == activeArmy else { return false }
                    let needsHealth = unitElement.simplified == .unitBlackBoat &&
                        unitHealth[neighbor, default: 100] < 100
                    let needsFuel = unitFuel[neighbor, default: maxFuel(for: neighbor)] < maxFuel(for: neighbor)
                    let needsAmmo = PlaytestRulebook.primaryAmmo(for: adjacent, ruleset: ruleset).map {
                        unitAmmo[neighbor, default: $0] < $0
                    } ?? false
                    return needsHealth || needsFuel || needsAmmo
                }
                if needsResupply {
                    plans.append(CPUPlan(
                        score: 108 * policy.supplyActionMultiplier,
                        action: .resupply(point: point)
                    ))
                }
            }

            // Joining is useful when two damaged units meet. The action still
            // goes through the normal path and canJoin checks when executed.
            for neighbor in neighbors(of: point) where isValid(neighbor) {
                guard let candidate = unit(at: neighbor),
                      candidate.army == activeArmy,
                      candidate.simplified == unitElement.simplified,
                      unitHealth[point, default: 100] < 100 || unitHealth[neighbor, default: 100] < 100,
                      let stats = PlaytestRulebook.stats(for: unitElement, ruleset: ruleset),
                      let path = cpuMovementPaths(from: point, unit: unitElement, stats: stats)[neighbor],
                      path.movement <= stats.move else { continue }
                plans.append(CPUPlan(score: 96, action: .join(origin: point, destination: neighbor)))
            }
        }
        return plans
    }

    private func cpuBuildPlans() -> [CPUPlan] {
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
    private func cpuCanProduce(at point: GridPoint) -> Bool {
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

    private func cpuBuildScore(_ option: PlaytestProductionOption, at point: GridPoint, building: Element) -> Double {
        guard let stats = PlaytestRulebook.stats(for: option.element, ruleset: ruleset) else { return -.greatestFiniteMagnitude }
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

    private func cpuProductionPropertyScore(
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

    private func cpuBuildRoleScore(
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
            // Bean Island's compact opening is a capture race: fill the local
            // HQ/city production ring with Infantry first, then spend the
            // growing income on Tanks. Heavy indirects are a response to an
            // established front, not an opening build.
            let openingCaptureTarget = min(5, max(3, enemyPropertyCount / 3))
            switch type {
            case .unitInfantry:
                guard captureNeed > 0 else { return -65 }
                return 95 + min(60, Double(captureNeed) * 13)
                    - Double(ownCounts[Element.unitInfantry.value, default: 0]) * 4
            case .unitTank:
                guard captureUnits >= openingCaptureTarget else { return -35 }
                return 76 + min(30, landThreat * 4)
            case .unitMech:
                return captureNeed > 0 && captureUnits < openingCaptureTarget ? 25 : -30
            case .unitAPC:
                return captureUnits >= openingCaptureTarget ? 18 : -15
            case .unitArtillery:
                return captureUnits >= openingCaptureTarget + 1 ? 18 + min(24, landThreat * 3) : -28
            case .unitRocket, .unitMissile, .unitMDTank:
                return captureUnits >= openingCaptureTarget + 2 ? 12 + min(24, landThreat * 3) : -45
            case .unitAntiAir:
                return airThreat > 0 ? 30 + min(30, airThreat * 8) : -20
            case .unitRecon:
                return 12
            default:
                break
            }
        }

        switch type {
        case .unitInfantry:
            // One or two infantry are useful for a capture plan. Once that
            // need is covered, this role becomes intentionally unattractive.
            return captureNeed > 0
                ? min(60, 24 + Double(captureNeed) * 10) * policy.captureUnitBuildMultiplier
                : -55 - policy.infantryRepeatPenalty * 0.5
        case .unitMech:
            return (captureNeed > 0
                ? 30 + min(18, Double(captureNeed) * 5)
                : -8) * policy.captureUnitBuildMultiplier
                + min(24, landThreat * 4)
        case .unitAPC:
            return captureUnits > 0 ? 28 : 12
        case .unitRecon:
            return 18 + min(24, landThreat * 4)
        case .unitTank:
            return 28 + min(32, landThreat * 5)
        case .unitMDTank, .unitNeoTank, .unitMegaTank:
            return 24 + min(38, landThreat * 5)
        case .unitArtillery:
            return 24 + min(42, landThreat * 7)
        case .unitRocket:
            return 18 + min(42, landThreat * 7)
        case .unitMissile:
            return 10 + min(56, airThreat * 22)
        case .unitAntiAir:
            return 10 + min(72, airThreat * 28)
        case .unitTCopter:
            return 12 + (captureNeed > 0 ? 22 : 0)
        case .unitBCopter:
            return 18 + min(42, landThreat * 6) + min(24, airThreat * 8)
        case .unitFighter:
            return 12 + min(78, airThreat * 30)
        case .unitBomber:
            return 22 + min(62, landThreat * 12)
        case .unitStealth, .unitBlackBomb:
            return 18 + min(42, landThreat * 8) + min(20, airThreat * 6)
        case .unitLander:
            return 8 + (captureNeed > 0 ? 24 : 0)
        case .unitBlackBoat:
            return 12 + min(42, landThreat * 7)
        case .unitCruiser:
            return 16 + min(54, airThreat * 16 + seaThreat * 8)
        case .unitSub:
            return 18 + min(64, seaThreat * 20)
        case .unitBattleship:
            return 22 + min(72, landThreat * 12 + seaThreat * 5)
        case .unitCarrier:
            return 15 + min(36, airThreat * 10 + seaThreat * 4)
        default:
            return Double(stats.attackPower) / 6
        }
    }

    private func cpuUnitCounts() -> [Int: Int] {
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

    private func cpuDomainCounts(for points: [GridPoint]) -> (land: Int, air: Int, sea: Int) {
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

    private func cpuMovePlans() -> [CPUPlan] {
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

    private var usesFamicomTacticalPlanning: Bool {
        ruleset == .famicomWars
    }

    /// Keep a Famicom CPU's direct-objective horizon deliberately short. The
    /// original NES maps are compact, so a unit that can make contact in two
    /// turns should commit; a unit that is many turns away should not receive
    /// a giant score merely because its HQ is on the other side of a large
    /// editor map.
    private func famicomTacticalHorizon(for stats: PlaytestUnitStats) -> Int {
        max(6, (stats.move * 2) + max(1, stats.maxRange))
    }

    /// Returns movement-point distance to one of the current Famicom
    /// objectives. This is a reverse flood fill over terrain, not a search for
    /// a legal turn: foreground units are ignored as blockers, while each
    /// unit's movement table and terrain placement rules remain authoritative.
    /// Caching one map per unit kind and objective keeps the per-action planner
    /// cheap even on a large custom map.
    private func cpuTacticalDistance(
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

    private func cpuTacticalDistanceMap(
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
            // Distances are expanded backwards from the objective. Since a
            // movement cost is charged when entering a tile, the reverse edge
            // pays the cost of the tile being left (the tile that is entered
            // in the forward route). A target can itself be a hostile unit on
            // terrain this unit cannot occupy, so fall back to the neighbour's
            // cost for that first edge.
            let currentCost = cpuTacticalTraversalCost(for: unit, at: current)

            for next in cardinalNeighbors(of: current) {
                guard isValid(next),
                      let neighbourCost = cpuTacticalTraversalCost(for: unit, at: next) else { continue }
                let cost = currentCost ?? neighbourCost
                let candidateDistance = currentDistance + cost
                if candidateDistance < distances[next, default: .max] {
                    distances[next] = candidateDistance
                    frontier.append(next)
                }
            }
        }
        return distances
    }

    private func cpuTacticalTargetPoints(for target: CPUTacticalTarget) -> [GridPoint] {
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

    private func cpuTacticalTraversalCost(for unit: Element, at point: GridPoint) -> Int? {
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

    private func cpuMoveScore(unit: Element, origin: GridPoint, destination: GridPoint, movement: Int) -> Double {
        guard let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset) else { return -.greatestFiniteMagnitude }
        let policy = cpuPolicy
        let before = usesFamicomTacticalPlanning
            ? cpuTacticalDistance(for: unit, target: .enemyUnit, from: origin)
            : nearestEnemyDistance(from: origin)
        let after = usesFamicomTacticalPlanning
            ? cpuTacticalDistance(for: unit, target: .enemyUnit, from: destination)
            : nearestEnemyDistance(from: destination)
        let distanceGain = before == .max || after == .max ? 0 : before - after
        let beforeProperty = usesFamicomTacticalPlanning
            ? cpuTacticalDistance(for: unit, target: .enemyProperty, from: origin)
            : nearestEnemyPropertyDistance(from: origin)
        let afterProperty = usesFamicomTacticalPlanning
            ? cpuTacticalDistance(for: unit, target: .enemyProperty, from: destination)
            : nearestEnemyPropertyDistance(from: destination)
        let propertyDistanceGain = beforeProperty == .max || afterProperty == .max
            ? 0
            : beforeProperty - afterProperty
        let beforeHQ = usesFamicomTacticalPlanning
            ? cpuTacticalDistance(for: unit, target: .enemyHQ, from: origin)
            : nearestEnemyHQDistance(from: origin)
        let afterHQ = usesFamicomTacticalPlanning
            ? cpuTacticalDistance(for: unit, target: .enemyHQ, from: destination)
            : nearestEnemyHQDistance(from: destination)
        let hqDistanceGain = beforeHQ == .max || afterHQ == .max ? 0 : beforeHQ - afterHQ
        let terrain = map.backgroundElement(atX: destination.x, y: destination.y)
        let terrainStars = PlaytestRulebook.terrainStars(for: terrain, ruleset: ruleset)
        let threat = cpuThreat(for: unit, at: destination)
        let propertyValue: Double
        let building = terrain
        if stats.canCapture,
           PlaytestRulebook.isCapturableBuilding(building, ruleset: ruleset),
           (building.army == AWConstants.armyNeutral || isHostile(building.army, activeArmy)) {
            propertyValue = captureScore(at: destination) * 0.85
        } else {
            propertyValue = 0
        }

        let attackOpportunity = cpuAdjacentAttackValue(for: unit, at: destination)
        let defensiveValue = Double(terrainStars) * 5
        let movementCost = Double(movement) * 2
        let famicomHorizon = famicomTacticalHorizon(for: stats)
        let propertyIsNear = !usesFamicomTacticalPlanning || afterProperty <= famicomHorizon
        let propertyApproachBonus: Double
        if stats.canCapture, afterProperty != .max, propertyIsNear {
            // Infantry and Mech need a reason to walk toward the next income
            // source even when the nearest enemy unit is being screened. A
            // near property receives a small urgency bonus; landing on it is
            // still handled by captureScore above.
            let urgency = Double(max(0, 7 - afterProperty)) * 6
            propertyApproachBonus = Double(propertyDistanceGain) * 24 * policy.propertyApproachMultiplier
                + urgency * policy.propertyApproachMultiplier
        } else {
            propertyApproachBonus = 0
        }
        let supplyObjective = cpuSupplyPropertyScore(for: unit, origin: origin, at: destination)
        let transportObjective = cpuTransportObjectiveScore(
            for: unit,
            origin: origin,
            destination: destination
        )
        let turnsToEngagement = cpuTurnsToEngagement(for: unit, at: destination, stats: stats)
        let isTwoTurnApproach = stats.attackPower > 0 && turnsToEngagement <= 2
        // A useful Advance Wars CPU accepts a reasonable exchange to make
        // contact. Threat is a risk adjustment, not a hard exclusion zone;
        // otherwise a single long-range unit can keep the CPU parked forever.
        let threatWeight = (isTwoTurnApproach ? 0.45 : 1.25) * policy.threatMultiplier
        let approachBonus = isTwoTurnApproach
            ? (55.0 + (Double(stats.attackPower) * 2.2)) * policy.contactMultiplier
            : 0
        let attackWindowBonus = stats.attackPower > 0 && after <= stats.maxRange + stats.move
            ? (35.0 + (Double(stats.attackPower) * 0.6)) * policy.contactMultiplier
            : 0
        // Bean Island is a direct HQ race. Capture units are the decisive
        // resource, so favour the opposing HQ corridor only once it is a
        // near-term route. A distant HQ should not pull a unit across the
        // whole editor canvas simply because Manhattan distance decreases.
        let hqApproachBonus = ruleset == .famicomWars && afterHQ <= famicomHorizon
            ? Double(hqDistanceGain) * (stats.canCapture ? 400 : 200)
            : 0
        let threatPenalty = Double(threat) * threatWeight
        let hasReachableObjective = before != .max || beforeProperty != .max || beforeHQ != .max
        if usesFamicomTacticalPlanning,
           !hasReachableObjective,
           propertyValue == 0,
           supplyObjective == 0,
           transportObjective == 0,
           attackOpportunity == 0 {
            // Do not spend turns wandering on an isolated island or across a
            // sea gap that this unit cannot traverse. Waiting still lets the
            // CPU build an appropriate transport or defend its position.
            return -Double(movement) - threatPenalty
        }

        return 8 + Double(distanceGain) * 22 + propertyValue + propertyApproachBonus
            + attackOpportunity + defensiveValue + supplyObjective + transportObjective
            + approachBonus + attackWindowBonus + hqApproachBonus - movementCost - threatPenalty
    }

    private func cpuSupplyPropertyScore(for unit: Element, origin: GridPoint, at point: GridPoint) -> Double {
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

    private func cpuTransportObjectiveScore(for transport: Element, origin: GridPoint, destination: GridPoint) -> Double {
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

    private func cpuSpecialPlans() -> [CPUPlan] {
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
                    plans.append(CPUPlan(
                        score: 620 + Double(hostileCount * 160),
                        action: .detonate(point: point)
                    ))
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

    private func cpuTransportDropOffs(for transport: Element, cargo: Element) -> [GridPoint] {
        let key = CPUTransportKey(
            transportValue: transport.simplified.value,
            cargoValue: cargo.simplified.value
        )
        if let cached = cpuTransportDropOffCache[key] {
            return cached
        }

        var points: [GridPoint] = []
        for point in allMapPoints() {
            if canUnload(cargo, from: transport, at: point) {
                points.append(point)
            }
        }
        cpuTransportDropOffCache[key] = points
        return points
    }

    private func cpuTurnsToEngagement(for unit: Element, at point: GridPoint, stats: PlaytestUnitStats) -> Int {
        guard stats.attackPower > 0, stats.maxRange > 0 else { return .max }
        let nearestDistance = usesFamicomTacticalPlanning
            ? cpuTacticalDistance(for: unit, target: .enemyUnit, from: point)
            : nearestEnemyDistance(from: point)
        let closestDistance = nearestDistance == .max
            ? Int.max
            : max(0, nearestDistance - stats.maxRange)
        guard closestDistance != .max else { return .max }
        let movementPerTurn = max(1, stats.move)
        return (closestDistance + movementPerTurn - 1) / movementPerTurn
    }

    private func cpuWaitPlans() -> [CPUPlan] {
        cpuUnitPoints()
            .filter { !movedCells.contains($0) }
            .map { CPUPlan(score: 0, action: .wait(point: $0)) }
    }

    private func cpuThreat(for unit: Element, at point: GridPoint) -> Int {
        let key = CPUThreatKey(
            unitValue: unit.simplified.value,
            point: point,
            health: unitHealth[point, default: 100]
        )
        if let cached = cpuThreatCache[key] {
            return cached
        }

        let defenderTerrain = map.backgroundElement(atX: point.x, y: point.y)
        var threat = 0
        for enemyInfo in cpuEnemyUnits() {
            let enemyPoint = enemyInfo.point
            let enemy = enemyInfo.unit
            let enemyStats = enemyInfo.stats
            guard isWithinRange(from: enemyPoint, to: point, stats: enemyStats),
                  PlaytestRulebook.canAttack(enemy, unit, ruleset: ruleset, primaryAmmo: unitAmmo[enemyPoint]) else { continue }
            // Use the same damage table as execution, without simulating a
            // second combat animation. The old
            // attack-power-plus-cost proxy made expensive units look much more
            // dangerous than they really were and produced a giant keep-away
            // zone around every CPU unit.
            guard let damage = PlaytestRulebook.damage(
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

    private func cpuAdjacentAttackValue(for unit: Element, at point: GridPoint) -> Double {
        // Movement scoring only needs to know whether a destination reaches a
        // likely engagement window. The full target/domain/damage model is
        // still evaluated for actual attack plans; scanning every opponent for
        // every reachable destination made one CPU turn disproportionately
        // costly. A nearest-enemy range check is a conservative signal here,
        // while the legal attack list remains authoritative when the unit acts.
        guard let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset),
              stats.maxRange > 0 else { return 0 }
        let policy = cpuPolicy
        let nearest = usesFamicomTacticalPlanning
            ? cpuTacticalDistance(for: unit, target: .enemyUnit, from: point)
            : nearestEnemyDistance(from: point)
        guard nearest >= stats.minRange,
              nearest <= PlaytestRulebook.maximumAttackRange(
                for: stats,
                ruleset: ruleset,
                weather: weather
              ) else { return 0 }
        let proximityBonus = Double(max(0, 8 - nearest)) * 10
        return (125 + (Double(stats.attackPower) * 0.65) + proximityBonus) * policy.contactMultiplier
    }

    private func cpuDestinationScore(for unit: Element, at point: GridPoint) -> Double {
        let policy = cpuPolicy
        let enemyDistance = usesFamicomTacticalPlanning
            ? cpuTacticalDistance(for: unit, target: .enemyUnit, from: point)
            : nearestEnemyDistance(from: point)
        let proximity = enemyDistance == Int.max ? 0 : max(0, 8 - enemyDistance)
        let threatPenalty = min(
            Double(cpuThreat(for: unit, at: point)) * 0.6 * policy.threatMultiplier,
            90
        )
        return 20 + Double(proximity) * 3 * policy.contactMultiplier - threatPenalty
    }

    private func allEnemyUnitPoints() -> [GridPoint] {
        if let snapshot = cpuPlanningSnapshot {
            return snapshot.enemyUnitPoints
        }
        var points: [GridPoint] = []
        for x in 0..<map.width {
            for y in 0..<map.height {
                let point = GridPoint(x: x, y: y)
                let unit = map.foregroundElement(atX: x, y: y)
                if unit.isUnitNonEmpty, isHostile(unit.army, activeArmy),
                   PlaytestRulebook.stats(for: unit, ruleset: ruleset) != nil {
                    points.append(point)
                }
            }
        }
        return points
    }

    private func cpuEnemyUnits() -> [CPUEnemyInfo] {
        if let snapshot = cpuPlanningSnapshot {
            return snapshot.enemyUnits
        }

        var enemies: [CPUEnemyInfo] = []
        for point in allEnemyUnitPoints() {
            let enemy = map.foregroundElement(atX: point.x, y: point.y)
            guard let stats = PlaytestRulebook.stats(for: enemy, ruleset: ruleset) else { continue }
            enemies.append(CPUEnemyInfo(point: point, unit: enemy, stats: stats))
        }
        return enemies
    }

    private func enemyPropertyPoints() -> [GridPoint] {
        if let snapshot = cpuPlanningSnapshot {
            return snapshot.enemyPropertyPoints
        }
        var points: [GridPoint] = []
        for x in 0..<map.width {
            for y in 0..<map.height {
                let point = GridPoint(x: x, y: y)
                let building = map.backgroundElement(atX: x, y: y)
                if PlaytestRulebook.isCapturableBuilding(building, ruleset: ruleset),
                   (building.army == AWConstants.armyNeutral || isHostile(building.army, activeArmy)) {
                    points.append(point)
                }
            }
        }
        return points
    }

    private func nearestEnemyDistance(from point: GridPoint) -> Int {
        if let cached = cpuNearestEnemyDistanceCache[point] {
            return cached
        }
        let nearest = allEnemyUnitPoints().map { distance(from: point, to: $0) }.min() ?? .max
        if cpuPlanningSnapshot != nil {
            cpuNearestEnemyDistanceCache[point] = nearest
        }
        return nearest
    }

    private func nearestEnemyPropertyDistance(from point: GridPoint) -> Int {
        if let cached = cpuNearestEnemyPropertyDistanceCache[point] {
            return cached
        }
        let nearest = enemyPropertyPoints()
            .map { distance(from: point, to: $0) }
            .min() ?? .max
        if cpuPlanningSnapshot != nil {
            cpuNearestEnemyPropertyDistanceCache[point] = nearest
        }
        return nearest
    }

    private func nearestEnemyHQDistance(from point: GridPoint) -> Int {
        let points = cpuPlanningSnapshot?.enemyHQPoints ?? allMapPoints().filter {
            let building = map.backgroundElement(atX: $0.x, y: $0.y)
            return building.simplified == .buildingHQ && isHostile(building.army, activeArmy)
        }
        return points.map { distance(from: point, to: $0) }.min() ?? .max
    }

    private func nearestFriendlyPropertyPoint() -> GridPoint {
        cpuPropertyPoints().first ?? GridPoint(x: 0, y: 0)
    }

    private func distance(from first: GridPoint, to second: GridPoint) -> Int {
        // GB Wars offsets alternating rows for presentation, but each map
        // cell remains a four-sided square. Keep logical movement and attack
        // distance Manhattan-based; the stagger belongs only to rendering
        // and hit testing, not to the board's topology.
        abs(first.x - second.x) + abs(first.y - second.y)
    }

    private func isCPUArmy(_ army: Int) -> Bool {
        cpuArmies.contains(army)
    }

    private func nextSurvivingArmy(after army: Int) -> Int? {
        guard !armies.isEmpty else { return nil }
        let startIndex = armies.firstIndex(of: army) ?? -1
        for offset in 1...armies.count {
            let index = (startIndex + offset) % armies.count
            let candidate = armies[index]
            if !defeatedArmies.contains(candidate) { return candidate }
        }
        return nil
    }

    private func unit(at point: GridPoint) -> Element? {
        let unit = map.foregroundElement(atX: point.x, y: point.y)
        return unit.isUnitNonEmpty ? unit : nil
    }

    private func neighbors(of point: GridPoint) -> [GridPoint] {
        // The GB presentation is staggered, not hexagonal. Every tile still
        // has the same four cardinal neighbours as the other rulesets.
        cardinalNeighbors(of: point)
    }

    /// Set and dictionary iteration is intentionally randomized by Swift. CPU
    /// tie scores should not turn the same map into a different opening every
    /// run, so keep grid-point fallbacks stable (left-to-right, then top-to-
    /// bottom) whenever the tactical score is equal.
    private func sortedGridPoints(_ points: Set<GridPoint>) -> [GridPoint] {
        points.sorted(by: gridPointOrder)
    }

    private func gridPointOrder(_ lhs: GridPoint, _ rhs: GridPoint) -> Bool {
        lhs.x == rhs.x ? lhs.y < rhs.y : lhs.x < rhs.x
    }

    private func cardinalNeighbors(of point: GridPoint) -> [GridPoint] {
        [
            GridPoint(x: point.x - 1, y: point.y), GridPoint(x: point.x + 1, y: point.y),
            GridPoint(x: point.x, y: point.y - 1), GridPoint(x: point.x, y: point.y + 1)
        ]
    }

    private func resupplyNeighbors(of point: GridPoint, transport: Element) -> [GridPoint] {
        PlaytestRulebook.resuppliesAdjacentUnits(transport, ruleset: ruleset)
            ? cardinalNeighbors(of: point)
            : neighbors(of: point)
    }

    private func clearSelection() {
        selectedPoint = nil
        clearPlayerMovementPreview()
        reachableCells.removeAll()
        attackableCells.removeAll()
        captureableCells.removeAll()
        loadableCells.removeAll()
        joinableCells.removeAll()
        unloadableCells.removeAll()
        refuelableCells.removeAll()
        siloTargetCells.removeAll()
        isSelectingSiloTarget = false
        productionOptions.removeAll()
        clearAttackPreview()
    }

    /// Cancels the currently highlighted action without moving the cartridge
    /// cursor. This is the B-button path for the legacy menu.
    func cancelLegacySelection() {
        clearSelection()
        statusMessage = "Selection cancelled."
    }

    /// Selects whatever is under the cartridge cursor, matching an A press on
    /// the map. The view decides whether a second A opens the command menu.
    func selectLegacyCursor() {
        guard let cursorPoint else { return }
        handleTap(cursorPoint)
    }

    /// The Stat command first selects the cursor's unit/property, then leaves
    /// the details visible in the existing inspector panel.
    func inspectLegacyCursor() {
        guard let cursorPoint else {
            statusMessage = "Move the cursor onto a unit or property first."
            return
        }
        if selectedPoint != cursorPoint {
            handleTap(cursorPoint)
        } else if let selectedUnitName {
            statusMessage = "Stats shown for \(selectedUnitName)."
        } else if let selectedBuildingName {
            statusMessage = "Stats shown for \(selectedBuildingName)."
        }
    }

    func moveCursor(dx: Int, dy: Int) {
        guard map.width > 0, map.height > 0 else { return }
        let current = cursorPoint ?? GridPoint(x: 0, y: 0)
        let next = GridPoint(
            x: min(max(current.x + dx, 0), map.width - 1),
            y: min(max(current.y + dy, 0), map.height - 1)
        )
        cursorPoint = next
    }

    func setCursor(_ point: GridPoint) {
        guard isValid(point) else { return }
        cursorPoint = point
    }

    func firstLegacyTarget(in points: Set<GridPoint>) -> GridPoint? {
        points.sorted { lhs, rhs in
            lhs.x == rhs.x ? lhs.y < rhs.y : lhs.x < rhs.x
        }.first
    }

    /// Updates the orange route preview for a player drag. The destination
    /// must be one of the same legal movement cells used by a normal tap;
    /// invalid tiles leave the last valid preview in place until release.
    @discardableResult
    func updatePlayerMovementPreview(to destination: GridPoint) -> Bool {
        guard !isGameOver,
              !isCPUArmy(activeArmy),
              !isAnimatingCPUMovement,
              let origin = selectedPoint,
              let unit = unit(at: origin),
              unit.army == activeArmy,
              !movedCells.contains(origin),
              reachableCells.contains(destination),
              let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset) else {
            return false
        }

        let paths = movementPaths(from: origin, unit: unit, stats: stats)
        guard paths[destination] != nil,
              let route = movementRoute(from: origin, to: destination, paths: paths) else {
            return false
        }
        playerMovementPath = route
        return route.count > 1
    }

    /// Commits a player route only when the pointer is still over the route's
    /// final legal tile. Releasing outside the movement range cancels the
    /// preview without moving the unit.
    @discardableResult
    func commitPlayerMovementPreview(at destination: GridPoint) -> Bool {
        guard playerMovementPath.count > 1,
              playerMovementPath.last == destination else {
            clearPlayerMovementPreview()
            return false
        }

        clearPlayerMovementPreview()
        moveSelectedUnit(to: destination)
        return true
    }

    func clearPlayerMovementPreview() {
        playerMovementPath.removeAll(keepingCapacity: true)
    }

    private func clearAttackPreview() {
        attackPreviewOrigin = nil
        attackPreviewCells.removeAll()
    }

    private func isValid(_ point: GridPoint) -> Bool {
        point.x >= 0 && point.x < map.width && point.y >= 0 && point.y < map.height
    }

    private func initializeUnitResources() {
        unitHealth.removeAll()
        unitFuel.removeAll()
        unitAmmo.removeAll()
        for x in 0..<map.width {
            for y in 0..<map.height {
                let point = GridPoint(x: x, y: y)
                let unit = map.foregroundElement(atX: x, y: y)
                guard unit.isUnitNonEmpty else { continue }
                unitHealth[point] = 100
                unitFuel[point] = PlaytestRulebook.maxFuel(for: unit, ruleset: ruleset)
                if let ammo = PlaytestRulebook.primaryAmmo(for: unit, ruleset: ruleset) {
                    unitAmmo[point] = ammo
                }
            }
        }
    }

    private func initializePipeSeams() {
        pipeSeamHealth.removeAll()
        for x in 0..<map.width {
            for y in 0..<map.height {
                let point = GridPoint(x: x, y: y)
                if isPipeSeam(at: point) {
                    pipeSeamHealth[point] = Self.pipeSeamStartingHealth
                }
            }
        }
    }

    private func maxFuel(for point: GridPoint) -> Int {
        guard let unit = unit(at: point) else { return 100 }
        return PlaytestRulebook.maxFuel(for: unit, ruleset: ruleset)
    }

    private static func initialCursor(in map: MapState, army: Int) -> GridPoint? {
        guard map.width > 0, map.height > 0 else { return nil }

        // Start on the first controllable unit, then fall back to an owned
        // property. This makes the first A press useful on both battle maps
        // and production-only test maps.
        for x in 0..<map.width {
            for y in 0..<map.height {
                let unit = map.foregroundElement(atX: x, y: y)
                if unit.isUnitNonEmpty, unit.army == army {
                    return GridPoint(x: x, y: y)
                }
            }
        }
        for x in 0..<map.width {
            for y in 0..<map.height {
                let building = map.backgroundElement(atX: x, y: y)
                if building.isBuilding, building.army == army {
                    return GridPoint(x: x, y: y)
                }
            }
        }
        return GridPoint(x: 0, y: 0)
    }

    private static func armies(in map: MapState) -> [Int] {
        var found = Set<Int>()
        let playableArmies = Set(PaletteCatalog.playtestArmies(for: map.tileset))
        for x in 0..<map.width {
            for y in 0..<map.height {
                let unit = map.foregroundElement(atX: x, y: y)
                let building = map.backgroundElement(atX: x, y: y)
                if unit.isUnitNonEmpty, playableArmies.contains(unit.army) { found.insert(unit.army) }
                if building.isBuilding, playableArmies.contains(building.army) { found.insert(building.army) }
            }
        }
        return found.sorted()
    }

}
