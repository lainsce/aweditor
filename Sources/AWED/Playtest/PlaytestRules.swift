import AWEDCore

enum PlaytestUnitDomain {
    case land
    case air
    case sea
}

enum PlaytestMovementType: Equatable {
    case foot
    case mech
    case tire
    case tread
    case air
    case ship
    case lander
}

enum PlaytestWeather: String, CaseIterable, Identifiable, Sendable {
    case clear
    case rain
    case snow
    case sandstorm
    case random

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .clear: "Clear"
        case .rain: "Rain"
        case .snow: "Snow"
        case .sandstorm: "Sandstorm"
        case .random: "Random"
        }
    }
}

/// The four alliance flags used by the playtest setup.  Team membership is
/// deliberately transient: it belongs to a match, not to the map file.
enum PlaytestTeam: String, CaseIterable, Identifiable, Sendable {
    case red
    case blue
    case yellow
    case green

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }
}

extension PlaytestRuleset {
    /// The original pre-DS cartridges use a directional map cursor and
    /// confirm/cancel/select buttons rather than pointer-first playtest input.
    /// Keep Dual Strike and Days of Ruin on the modern pointer interaction
    /// path until their richer control surfaces are added.
    var usesLegacyKeyboardControls: Bool {
        switch self {
        case .famicomWars, .superFamicomWars, .gameBoyWars, .gameBoyWars2,
             .gameBoyWars3, .advanceWars, .advanceWars2:
            true
        case .dualStrike, .daysOfRuin:
            false
        }
    }

    /// Cartridge-era games before Dual Strike draw a directional movement
    /// path without the later Advance Wars arrowhead treatment. AW1 and AW2
    /// retain the classic orange route arrow; DS and DoR use the modern
    /// pointer-first renderer and keep their existing path styling.
    var showsMovementArrow: Bool {
        switch self {
        case .famicomWars, .superFamicomWars, .gameBoyWars, .gameBoyWars2, .gameBoyWars3:
            false
        case .advanceWars, .advanceWars2, .dualStrike, .daysOfRuin:
            true
        }
    }

    /// Used-unit markers are part of the original Famicom/GB presentation.
    /// Super Famicom Wars and the later Advance Wars games use the existing
    /// moved-cell treatment instead.
    var showsMovedUnitBadge: Bool {
        switch self {
        case .famicomWars, .gameBoyWars, .gameBoyWars2, .gameBoyWars3:
            true
        case .superFamicomWars, .advanceWars, .advanceWars2, .dualStrike, .daysOfRuin:
            false
        }
    }

    /// Game Boy Wars 1–3 identify legal movement destinations with an `M`
    /// badge rather than the blue translucent movement-square overlay.
    var showsMovementAvailabilityBadge: Bool {
        switch self {
        case .gameBoyWars, .gameBoyWars2, .gameBoyWars3:
            true
        case .famicomWars, .superFamicomWars, .advanceWars, .advanceWars2, .dualStrike, .daysOfRuin:
            false
        }
    }
}

/// Match-only control settings.  The editor's persisted army values remain
/// unchanged, which keeps old map files and screenshots compatible.
struct PlaytestConfiguration: Sendable {
    var playerArmy: Int?
    var cpuArmies: Set<Int>
    var teams: [Int: PlaytestTeam]

    static func automatic(for armies: [Int]) -> Self {
        // Keep the familiar Orange Star default when it is present, while
        // still choosing the first placed army for maps from another game.
        let player = armies.contains(AWConstants.armyOrangeStar)
            ? AWConstants.armyOrangeStar
            : armies.first
        let cpu = Set(armies.filter { $0 != player })
        let teams = Dictionary(uniqueKeysWithValues: armies.enumerated().map { index, army in
            (army, PlaytestTeam.allCases[index % PlaytestTeam.allCases.count])
        })
        return Self(playerArmy: player, cpuArmies: cpu, teams: teams)
    }

    func team(for army: Int) -> PlaytestTeam {
        teams[army] ?? .red
    }
}

struct PlaytestUnitStats {
    let cost: Int
    let move: Int
    let minRange: Int
    let maxRange: Int
    let domain: PlaytestUnitDomain
    let canCapture: Bool
    let attackPower: Int
    let movementType: PlaytestMovementType
    let maxFuel: Int
    let dailyFuelUse: Int
    let vision: Int
    /// A nil value means the primary weapon has unlimited ammunition (or the
    /// unit has no weapon when attackPower is zero).
    let primaryAmmo: Int?
    let secondaryAttackPower: Int?
    let canMoveAndFire: Bool
    let canCounterattack: Bool

    init(
        cost: Int,
        move: Int,
        minRange: Int,
        maxRange: Int,
        domain: PlaytestUnitDomain,
        canCapture: Bool,
        attackPower: Int,
        movementType: PlaytestMovementType = .tread,
        maxFuel: Int = 100,
        dailyFuelUse: Int = 0,
        vision: Int = 1,
        primaryAmmo: Int? = nil,
        secondaryAttackPower: Int? = nil,
        canMoveAndFire: Bool = true,
        canCounterattack: Bool = true
    ) {
        self.cost = cost
        self.move = move
        self.minRange = minRange
        self.maxRange = maxRange
        self.domain = domain
        self.canCapture = canCapture
        self.attackPower = attackPower
        self.movementType = movementType
        self.maxFuel = maxFuel
        self.dailyFuelUse = dailyFuelUse
        self.vision = vision
        self.primaryAmmo = primaryAmmo
        self.secondaryAttackPower = secondaryAttackPower
        self.canMoveAndFire = canMoveAndFire
        self.canCounterattack = canCounterattack
    }
}

struct PlaytestProductionOption: Identifiable {
    let element: Element
    let label: String
    let cost: Int

    var id: Int { element.simplified.value }
}

/// Shared dispatch for the editor's local playtest. Cartridge-specific
/// rosters and tables live in dedicated rule files so one game's mechanics do
/// not silently leak into another game's tileset.
enum PlaytestRulebook {
    /// Decision weights used by the CPU planner. The legal-action generator
    /// stays shared, while these values preserve the broad personality of
    /// each cartridge's CPU without pretending to reproduce its hidden ROM
    /// tables exactly.
    struct CPUPolicy: Sendable {
        let attackBias: Double
        let counterRiskMultiplier: Double
        let targetCostMultiplier: Double
        let captureMultiplier: Double
        let captureProgressWeight: Double
        let hqCaptureMultiplier: Double
        let productionCaptureMultiplier: Double
        let enemyPropertyMultiplier: Double
        let propertyApproachMultiplier: Double
        let contactMultiplier: Double
        let threatMultiplier: Double
        let transportTargetMultiplier: Double
        let loadedTransportBonus: Double
        let transportActionMultiplier: Double
        let supplyActionMultiplier: Double
        let infantryRepeatPenalty: Double
        let captureUnitBuildMultiplier: Double
        let buildDiversityPenalty: Double
        let indirectAttackMultiplier: Double
        /// A square radius around an owned HQ used by the original Famicom
        /// production rule. `nil` means the ruleset has no such CPU filter.
        let hqProductionRadius: Int?
    }
}
