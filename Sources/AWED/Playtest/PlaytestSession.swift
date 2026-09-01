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
    static let pipeSeamStartingHealth = 99

    // CPU actions are intentionally paced separately from the rules engine.
    // The planner should stay quick, while the visible turn should still read
    // like a game rather than a batch simulation.
    static let cpuActionPreviewDelay: UInt64 = 220_000_000
    static let cpuActionPause: UInt64 = 90_000_000
    static let cpuTurnPause: UInt64 = 520_000_000
    static let cpuMoveStepPause: UInt64 = 125_000_000
    static let legacyMoveStepPause: UInt64 = 180_000_000
    static let cpuRoutePause: UInt64 = 100_000_000

    struct CPUTimingProfile {
        let minimumTurnDuration: UInt64
        let delayScale: Double
    }

    /// Keep the visible pacing in step with the source game's era: compact
    /// 8-bit rulesets turn over quickly, 16-bit/Game Boy Color rulesets get a
    /// little more room to read, and the larger GBA/DS rulesets retain the
    /// five-second floor used for modern playtests.
    var cpuTimingProfile: CPUTimingProfile {
        switch ruleset {
        case .famicomWars, .gameBoyWars:
            return CPUTimingProfile(minimumTurnDuration: 3_000_000_000, delayScale: 0.6)
        case .superFamicomWars, .gameBoyWars2, .gameBoyWars3:
            return CPUTimingProfile(minimumTurnDuration: 4_000_000_000, delayScale: 0.8)
        case .advanceWars, .advanceWars2, .dualStrike, .daysOfRuin:
            return CPUTimingProfile(minimumTurnDuration: 5_000_000_000, delayScale: 1.0)
        }
    }

    var cpuMinimumTurnDuration: UInt64 {
        cpuTimingProfile.minimumTurnDuration
    }

    func scaledCPUDelay(_ base: UInt64) -> UInt64 {
        max(1, UInt64((Double(base) * cpuTimingProfile.delayScale).rounded()))
    }

    var movementStepDelay: UInt64 {
        scaledCPUDelay(usesTileMovementAnimation ? Self.legacyMoveStepPause : Self.cpuMoveStepPause)
    }

    struct PlaytestCargo {
        let unit: Element
        let health: Int
        let fuel: Int
        let ammo: Int?
    }

    struct MovementPath {
        let movement: Int
        let steps: Int
        let previous: GridPoint?
    }

    /// The CPU deliberately keeps its action vocabulary small. It evaluates
    /// the same legal actions exposed to the player, then chooses the highest
    /// immediate utility score rather than searching for a perfect line.
    enum CPUAction {
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

    struct CPUPlan {
        let score: Double
        let action: CPUAction
    }

    struct CPUThreatKey: Hashable {
        let unitValue: Int
        let point: GridPoint
        let health: Int
    }

    struct CPUPathKey: Hashable {
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
    enum CPUTacticalTarget: Hashable {
        case enemyUnit
        case enemyProperty
        case enemyHQ
    }

    struct CPUTacticalDistanceKey: Hashable {
        let unitValue: Int
        let target: CPUTacticalTarget
    }

    struct CPUAttackKey: Hashable {
        let origin: GridPoint
        let unitValue: Int
        let primaryAmmo: Int
        let hasMoved: Bool
    }

    struct CPUEnemyInfo {
        let point: GridPoint
        let unit: Element
        let stats: PlaytestUnitStats
    }

    struct CPUTransportKey: Hashable {
        let transportValue: Int
        let cargoValue: Int
    }

    /// A single planning pass should inspect the board once. The previous
    /// planner rediscovered the same units, properties, and opponents for
    /// every action family and for every candidate score.
    struct CPUPlanningSnapshot {
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
    let cpuPolicy: PlaytestRulebook.CPUPolicy
    /// The art variant selected in the editor when this playtest was opened.
    /// It is intentionally not persisted in `MapState`; the map file format
    /// still stores only its base tileset.
    let visualVariant: MapVisualVariant
    let initialWeather: PlaytestWeather

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
    var musicRevision = 0
    var activeArmy: Int {
        didSet {
            invalidateVisibilityCache()
            cpuTacticalDistanceCache.removeAll(keepingCapacity: true)
        }
    }
    var playerArmy: Int?
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
    var playerMovementAnimation: PlaytestMovementAnimation?
    var cpuMovementAnimation: PlaytestMovementAnimation?
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

    let armies: [Int]
    var cpuArmies: Set<Int>
    var teamAssignments: [Int: PlaytestTeam]
    var hasStarted = false
    var defeatedArmies: Set<Int> = []
    /// Famicom-era routing can use unit elimination even when an army still
    /// has a production property. An army that starts a map with no units has
    /// not been eliminated yet, though; remember which armies have actually
    /// fielded a supported unit so startup cannot neutralize a perfectly valid
    /// empty opening army.
    @ObservationIgnored var armiesThatHaveHadUnits: Set<Int> = []
    /// GB Wars 3's losing cue is based on cumulative unit losses, not on a
    /// generic material score. Keep this transient match state separate from
    /// the map so loading/restarting a playtest never changes persisted data.
    @ObservationIgnored var destroyedUnitCounts: [Int: Int] = [:]
    var cargo: [GridPoint: [PlaytestCargo]] = [:]
    var selectedCargoIndex = 0
    /// Pipe seams are map objectives rather than units. The cartridges treat
    /// them as 99-HP structures, so keep their damage separate from unit HP
    /// while the playtest mutates the in-memory map.
    var pipeSeamHealth: [GridPoint: Int] = [:]
    var usedMissileSilos: Set<GridPoint> = []
    var isSelectingSiloTarget = false
    @ObservationIgnored var isAnimatingCPUMovement = false
    var isAnimatingPlayerMovement = false
    @ObservationIgnored var playerMovementTask: Task<Void, Never>?
    var isExecutingCPU = false
    @ObservationIgnored var cpuTask: Task<Void, Never>?
    @ObservationIgnored var cpuRunID = UUID()
    @ObservationIgnored var cpuPlanningSnapshot: CPUPlanningSnapshot?
    @ObservationIgnored var cpuThreatCache: [CPUThreatKey: Int] = [:]
    @ObservationIgnored var cpuMovementPathCache: [CPUPathKey: [GridPoint: MovementPath]] = [:]
    @ObservationIgnored var cpuAttackableCache: [CPUAttackKey: Set<GridPoint>] = [:]
    @ObservationIgnored var cpuNearestEnemyDistanceCache: [GridPoint: Int] = [:]
    @ObservationIgnored var cpuNearestEnemyPropertyDistanceCache: [GridPoint: Int] = [:]
    @ObservationIgnored var cpuTacticalDistanceCache: [CPUTacticalDistanceKey: [GridPoint: Int]] = [:]
    @ObservationIgnored var cpuTransportDropOffCache: [CPUTransportKey: [GridPoint]] = [:]
    @ObservationIgnored var visibilityRevision = 0
    @ObservationIgnored var cachedVisibilityRevision = -1
    @ObservationIgnored var cachedVisibleCells: Set<GridPoint> = []
    @ObservationIgnored var cachedMapPoints: [GridPoint] = []
    @ObservationIgnored var cachedMapPointWidth = -1
    @ObservationIgnored var cachedMapPointHeight = -1

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

}
