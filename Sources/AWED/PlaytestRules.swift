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

    /// The source games share the same action vocabulary, but their CPUs do
    /// not value the same action equally. In particular, AW1's transport
    /// targeting and AW2's loaded-transport targeting are documented by
    /// reverse-engineered priority tables, while Super Famicom Wars uses
    /// simultaneous combat and rewards a more forward attack posture.
    static func cpuPolicy(for ruleset: PlaytestRuleset) -> CPUPolicy {
        switch ruleset {
        case .dualStrike:
            CPUPolicy(
                attackBias: 220, counterRiskMultiplier: 0.95, targetCostMultiplier: 1.0,
                captureMultiplier: 1.0, captureProgressWeight: 12, hqCaptureMultiplier: 1.25,
                productionCaptureMultiplier: 1.10, enemyPropertyMultiplier: 1.0,
                propertyApproachMultiplier: 1.0, contactMultiplier: 1.0, threatMultiplier: 0.90,
                transportTargetMultiplier: 1.0, loadedTransportBonus: 60,
                transportActionMultiplier: 1.0, supplyActionMultiplier: 1.0,
                infantryRepeatPenalty: 16, captureUnitBuildMultiplier: 1.0,
                buildDiversityPenalty: 10, indirectAttackMultiplier: 1.0,
                hqProductionRadius: nil
            )
        case .advanceWars:
            // AW1's old CPU is notably transport-focused, especially toward
            // APCs and T-Copters, while still keeping capture soldiers urgent.
            CPUPolicy(
                attackBias: 235, counterRiskMultiplier: 0.78, targetCostMultiplier: 1.0,
                captureMultiplier: 1.05, captureProgressWeight: 14, hqCaptureMultiplier: 1.35,
                productionCaptureMultiplier: 1.20, enemyPropertyMultiplier: 1.05,
                propertyApproachMultiplier: 1.10, contactMultiplier: 1.10, threatMultiplier: 0.75,
                transportTargetMultiplier: 1.70, loadedTransportBonus: 80,
                transportActionMultiplier: 1.0, supplyActionMultiplier: 1.0,
                infantryRepeatPenalty: 20, captureUnitBuildMultiplier: 1.05,
                buildDiversityPenalty: 11, indirectAttackMultiplier: 0.95,
                hqProductionRadius: nil
            )
        case .advanceWars2:
            // AW2 gives loaded APCs/T-Copters a special target priority. The
            // higher capture weights also stop a CPU from screening the HQ
            // forever instead of committing to a property attack.
            CPUPolicy(
                attackBias: 228, counterRiskMultiplier: 0.90, targetCostMultiplier: 1.0,
                captureMultiplier: 1.10, captureProgressWeight: 15, hqCaptureMultiplier: 1.45,
                productionCaptureMultiplier: 1.25, enemyPropertyMultiplier: 1.10,
                propertyApproachMultiplier: 1.08, contactMultiplier: 1.05, threatMultiplier: 0.80,
                transportTargetMultiplier: 1.10, loadedTransportBonus: 170,
                transportActionMultiplier: 1.10, supplyActionMultiplier: 1.0,
                infantryRepeatPenalty: 20, captureUnitBuildMultiplier: 1.05,
                buildDiversityPenalty: 11, indirectAttackMultiplier: 1.0,
                hqProductionRadius: nil
            )
        case .famicomWars:
            // The NES game is compact and objective-driven: income, capture,
            // and a direct march toward the opposing HQ matter more than a
            // modern two-front threat map.
            CPUPolicy(
                attackBias: 245, counterRiskMultiplier: 0.70, targetCostMultiplier: 1.0,
                captureMultiplier: 1.15, captureProgressWeight: 16, hqCaptureMultiplier: 1.40,
                productionCaptureMultiplier: 1.30, enemyPropertyMultiplier: 1.10,
                propertyApproachMultiplier: 1.22, contactMultiplier: 1.15, threatMultiplier: 0.60,
                transportTargetMultiplier: 1.0, loadedTransportBonus: 40,
                transportActionMultiplier: 1.15, supplyActionMultiplier: 1.10,
                infantryRepeatPenalty: 22, captureUnitBuildMultiplier: 1.05,
                buildDiversityPenalty: 10, indirectAttackMultiplier: 1.0,
                hqProductionRadius: 2
            )
        case .superFamicomWars:
            // Simultaneous combat means the CPU can accept forward trades
            // that would be too risky under attacker-first combat.
            CPUPolicy(
                attackBias: 255, counterRiskMultiplier: 0.60, targetCostMultiplier: 1.0,
                captureMultiplier: 1.12, captureProgressWeight: 16, hqCaptureMultiplier: 1.45,
                productionCaptureMultiplier: 1.30, enemyPropertyMultiplier: 1.10,
                propertyApproachMultiplier: 1.25, contactMultiplier: 1.20, threatMultiplier: 0.45,
                transportTargetMultiplier: 1.0, loadedTransportBonus: 40,
                transportActionMultiplier: 1.20, supplyActionMultiplier: 1.10,
                infantryRepeatPenalty: 22, captureUnitBuildMultiplier: 1.0,
                buildDiversityPenalty: 11, indirectAttackMultiplier: 1.15,
                hqProductionRadius: 2
            )
        case .gameBoyWars:
            // GB Wars 1 has a smaller, simpler decision space. Keep the CPU
            // economical and objective-aware without importing GBA quirks.
            CPUPolicy(
                attackBias: 215, counterRiskMultiplier: 0.90, targetCostMultiplier: 1.0,
                captureMultiplier: 1.0, captureProgressWeight: 12, hqCaptureMultiplier: 1.20,
                productionCaptureMultiplier: 1.10, enemyPropertyMultiplier: 1.0,
                propertyApproachMultiplier: 0.95, contactMultiplier: 0.95, threatMultiplier: 0.95,
                transportTargetMultiplier: 0.90, loadedTransportBonus: 30,
                transportActionMultiplier: 0.90, supplyActionMultiplier: 0.90,
                infantryRepeatPenalty: 24, captureUnitBuildMultiplier: 0.95,
                buildDiversityPenalty: 9, indirectAttackMultiplier: 0.90,
                hqProductionRadius: nil
            )
        case .gameBoyWars2:
            CPUPolicy(
                attackBias: 220, counterRiskMultiplier: 0.82, targetCostMultiplier: 1.0,
                captureMultiplier: 1.05, captureProgressWeight: 13, hqCaptureMultiplier: 1.30,
                productionCaptureMultiplier: 1.15, enemyPropertyMultiplier: 1.0,
                propertyApproachMultiplier: 1.0, contactMultiplier: 1.0, threatMultiplier: 0.85,
                transportTargetMultiplier: 1.0, loadedTransportBonus: 55,
                transportActionMultiplier: 1.0, supplyActionMultiplier: 0.95,
                infantryRepeatPenalty: 22, captureUnitBuildMultiplier: 1.0,
                buildDiversityPenalty: 10, indirectAttackMultiplier: 0.95,
                hqProductionRadius: nil
            )
        case .gameBoyWars3:
            // GB Wars 3 has the richest of the three GB unit tables, so its
            // CPU gets slightly more willingness to contest air/sea lanes.
            CPUPolicy(
                attackBias: 230, counterRiskMultiplier: 0.78, targetCostMultiplier: 1.0,
                captureMultiplier: 1.10, captureProgressWeight: 14, hqCaptureMultiplier: 1.35,
                productionCaptureMultiplier: 1.20, enemyPropertyMultiplier: 1.05,
                propertyApproachMultiplier: 1.08, contactMultiplier: 1.05, threatMultiplier: 0.75,
                transportTargetMultiplier: 1.0, loadedTransportBonus: 70,
                transportActionMultiplier: 1.05, supplyActionMultiplier: 1.0,
                infantryRepeatPenalty: 24, captureUnitBuildMultiplier: 1.0,
                buildDiversityPenalty: 12, indirectAttackMultiplier: 1.0,
                hqProductionRadius: nil
            )
        case .daysOfRuin:
            // DoR's Flare, Anti-Tank, Rig, Radar, and move-and-fire
            // Battleship exceptions make a pure GBA-era score too passive.
            CPUPolicy(
                attackBias: 240, counterRiskMultiplier: 0.75, targetCostMultiplier: 1.0,
                captureMultiplier: 1.15, captureProgressWeight: 16, hqCaptureMultiplier: 1.45,
                productionCaptureMultiplier: 1.25, enemyPropertyMultiplier: 1.10,
                propertyApproachMultiplier: 1.12, contactMultiplier: 1.10, threatMultiplier: 0.70,
                transportTargetMultiplier: 1.15, loadedTransportBonus: 90,
                transportActionMultiplier: 1.10, supplyActionMultiplier: 1.05,
                infantryRepeatPenalty: 20, captureUnitBuildMultiplier: 1.05,
                buildDiversityPenalty: 12, indirectAttackMultiplier: 1.10,
                hqProductionRadius: nil
            )
        }
    }

    /// Resolve the CPU profile from the map's art family. Keeping this
    /// overload next to the ruleset dispatcher makes it hard for a playtest
    /// to accidentally use the Dual Strike planner after a historical
    /// tileset is selected.
    static func cpuPolicy(for tileset: Tileset) -> CPUPolicy {
        cpuPolicy(for: tileset.playtestRuleset)
    }

    static func formatFunds(_ amount: Int) -> String {
        "\(amount.formatted()) G"
    }

    static func weatherOptions(for ruleset: PlaytestRuleset) -> [PlaytestWeather] {
        switch ruleset {
        case .dualStrike:
            return PlaytestDualStrikeRules.weatherOptions
        case .advanceWars:
            return PlaytestAdvanceWarsRules.weatherOptions
        case .advanceWars2:
            return PlaytestAdvanceWars2Rules.weatherOptions
        case .famicomWars:
            return PlaytestFamicomWarsRules.weatherOptions
        case .superFamicomWars:
            return PlaytestSuperFamicomWarsRules.weatherOptions
        case .gameBoyWars, .gameBoyWars2, .gameBoyWars3:
            return PlaytestGameBoyWarsRules.weatherOptions
        case .daysOfRuin:
            return PlaytestDaysOfRuinRules.weatherOptions
        }
    }

    static func supportsWeatherControl(_ ruleset: PlaytestRuleset) -> Bool {
        weatherOptions(for: ruleset).count > 1
    }

    static func supportsFogOfWar(_ ruleset: PlaytestRuleset) -> Bool {
        switch ruleset {
        case .famicomWars, .gameBoyWars:
            return false
        case .superFamicomWars:
            return PlaytestSuperFamicomWarsRules.supportsFogOfWar
        case .gameBoyWars2, .gameBoyWars3:
            return PlaytestGameBoyWarsRules.supportsFogOfWar(for: ruleset)
        case .dualStrike, .advanceWars, .advanceWars2, .daysOfRuin:
            return true
        }
    }

    static func weatherForcesFog(_ ruleset: PlaytestRuleset, weather: PlaytestWeather) -> Bool {
        weather == .rain && (ruleset == .dualStrike || ruleset == .daysOfRuin)
    }

    static func concreteWeatherOptions(for ruleset: PlaytestRuleset) -> [PlaytestWeather] {
        weatherOptions(for: ruleset).filter { $0 != .random }
    }

    static func randomWeather(for ruleset: PlaytestRuleset) -> PlaytestWeather {
        concreteWeatherOptions(for: ruleset).randomElement() ?? .clear
    }

    /// The map-art choice is also the starting weather for playtest. This
    /// keeps an AW1 snow map, AW2 rain map, or DS desert map visually and
    /// mechanically aligned as soon as the playtest opens. Wasteland is a
    /// Dual Strike art-only palette, so it starts in clear weather.
    static func initialWeather(for variant: MapVisualVariant, ruleset: PlaytestRuleset) -> PlaytestWeather {
        let requested: PlaytestWeather
        switch variant {
        case .famicomWars, .gbWars, .superFamicomWars, .gbWars2, .gbWars3,
             .daysOfRuin, .dualStrikeNormal, .dualStrikeWasteland, .aw1Clear, .aw2Clear:
            requested = .clear
        case .dualStrikeSnow, .aw1Snow, .aw2Snow:
            requested = .snow
        case .dualStrikeDesert:
            requested = .sandstorm
        case .aw2Rain:
            requested = .rain
        }

        return weatherOptions(for: ruleset).contains(requested) ? requested : .clear
    }

    /// Returns the persisted/base art tileset used by the playtest map
    /// snapshot. Weather-specific GBA art is selected separately through
    /// `visualPalette` so it never leaks into map serialization.
    static func visualTileset(for ruleset: PlaytestRuleset, weather: PlaytestWeather) -> Tileset {
        switch ruleset {
        case .dualStrike:
            switch weather {
            case .snow:
                return .snow
            case .sandstorm:
                return .desert
            case .clear, .rain, .random:
                return .normal
            }
        case .advanceWars:
            return .aw1
        case .advanceWars2:
            return .aw2
        case .famicomWars:
            return .famicomWars
        case .gameBoyWars:
            return .gbWars
        case .superFamicomWars:
            return .superFamicomWars
        case .gameBoyWars2:
            return .gbWars2
        case .gameBoyWars3:
            return .gbWars3
        case .daysOfRuin:
            return .daysOfRuin
        }
    }

    /// Render-only palette for weather art. The AW1 and AW2 terrain geometry
    /// is shared by the GBA cartridges, while their building/unit sheets stay
    /// game-specific through the base tileset.
    static func visualPalette(for ruleset: PlaytestRuleset, weather: PlaytestWeather) -> SpritePalette {
        switch ruleset {
        case .dualStrike:
            return .tileset(visualTileset(for: ruleset, weather: weather))
        case .advanceWars:
            switch weather {
            case .snow: return .gbaSnow(base: .aw1)
            case .clear, .rain, .sandstorm, .random: return .tileset(.aw1)
            }
        case .advanceWars2:
            switch weather {
            case .rain: return .gbaRain(base: .aw2)
            case .snow: return .gbaSnow(base: .aw2)
                case .clear, .sandstorm, .random: return .tileset(.aw2)
            }
        case .famicomWars, .gameBoyWars, .superFamicomWars,
             .gameBoyWars2, .gameBoyWars3, .daysOfRuin:
            return .tileset(visualTileset(for: ruleset, weather: weather))
        }
    }

    static func fogOfWarIsActive(
        ruleset: PlaytestRuleset,
        manualFogEnabled: Bool,
        weather: PlaytestWeather
    ) -> Bool {
        if ruleset == .dualStrike {
            return PlaytestDualStrikeRules.fogOfWarIsActive(
                manualFogEnabled: manualFogEnabled,
                weather: weather
            )
        }
        if ruleset == .daysOfRuin {
            return PlaytestDaysOfRuinRules.fogOfWarIsActive(
                manualFogEnabled: manualFogEnabled,
                weather: weather
            )
        }
        return supportsFogOfWar(ruleset) && manualFogEnabled
    }

    static func resourceLabel(for element: Element) -> String {
        switch element.simplified {
        case .unitInfantry, .unitMech:
            return "Rations"
        default:
            return "Fuel"
        }
    }

    /// The 8/16-bit games use a dedicated Supply Truck in the shared Recon
    /// slot. Later games fold the same adjacent resupply role into APC/Rig.
    static func resuppliesAdjacentUnits(_ element: Element, ruleset: PlaytestRuleset) -> Bool {
        switch ruleset {
        case .famicomWars, .superFamicomWars:
            return element.simplified == .unitRecon
        case .dualStrike, .advanceWars, .advanceWars2,
             .gameBoyWars, .gameBoyWars2, .gameBoyWars3, .daysOfRuin:
            return element.simplified == .unitAPC
        }
    }

    /// Direct combat in Super Famicom Wars is resolved simultaneously, so a
    /// defender that is destroyed still returns fire at its starting strength.
    static func counterattackUsesStartingStrength(_ ruleset: PlaytestRuleset) -> Bool {
        ruleset == .superFamicomWars
    }

    static func canCrossRiver(_ element: Element) -> Bool {
        element.simplified == .unitInfantry || element.simplified == .unitMech
    }

    static func transportCapacity(for element: Element, ruleset: PlaytestRuleset) -> Int {
        if ruleset == .daysOfRuin {
            switch element.simplified {
            case .unitAPC, .unitTCopter, .unitBlackBoat: return 1
            case .unitLander, .unitCruiser: return 2
            case .unitCarrier: return 4
            default: return 0
            }
        }
        switch element.simplified {
        case .unitAPC: return 1
        case .unitLander: return 2
        case .unitTCopter: return 1
        case .unitCruiser, .unitBlackBoat, .unitCarrier: return 2
        default: return 0
        }
    }

    static func canTransport(_ transport: Element, cargo: Element, ruleset: PlaytestRuleset) -> Bool {
        if ruleset == .advanceWars2 {
            return PlaytestAdvanceWars2Rules.canTransport(transport, cargo: cargo)
        }
        if ruleset == .advanceWars {
            return PlaytestAdvanceWarsRules.canTransport(transport, cargo: cargo)
        }
        if ruleset == .famicomWars {
            return PlaytestFamicomWarsRules.canTransport(transport, cargo: cargo)
        }
        if ruleset == .superFamicomWars {
            return PlaytestSuperFamicomWarsRules.canTransport(transport, cargo: cargo)
        }
        if ruleset == .gameBoyWars || ruleset == .gameBoyWars2 || ruleset == .gameBoyWars3 {
            return PlaytestGameBoyWarsRules.canTransport(transport, cargo: cargo, ruleset: ruleset)
        }
        if ruleset == .daysOfRuin {
            return PlaytestDaysOfRuinRules.canTransport(transport, cargo: cargo)
        }

        guard transportCapacity(for: transport, ruleset: ruleset) > 0,
              let cargoStats = stats(for: cargo, ruleset: ruleset),
              cargo.army == transport.army else { return false }

        switch transport.simplified {
        case .unitAPC:
            // Dual Strike's APC is an Infantry/Mech carrier. It can supply
            // every unit class, but only foot units occupy its single cargo
            // space.
            return cargo.simplified == .unitInfantry || cargo.simplified == .unitMech
        case .unitLander:
            return cargoStats.domain == .land
        case .unitTCopter:
            return cargo.simplified == .unitInfantry || cargo.simplified == .unitMech
        case .unitCruiser:
            return cargo.simplified == .unitBCopter || cargo.simplified == .unitTCopter
        case .unitBlackBoat:
            return cargo.simplified == .unitInfantry || cargo.simplified == .unitMech
        case .unitCarrier:
            return cargoStats.domain == .air
        default:
            return false
        }
    }

    static func stats(for element: Element, ruleset: PlaytestRuleset) -> PlaytestUnitStats? {
        if ruleset == .advanceWars2 {
            return PlaytestAdvanceWars2Rules.stats(for: element)
        }
        if ruleset == .advanceWars {
            return PlaytestAdvanceWarsRules.stats(for: element)
        }
        switch ruleset {
        case .dualStrike:
            return PlaytestDualStrikeRules.stats(for: element)
        case .famicomWars:
            return PlaytestFamicomWarsRules.stats(for: element)
        case .superFamicomWars:
            return PlaytestSuperFamicomWarsRules.stats(for: element)
        case .gameBoyWars, .gameBoyWars2, .gameBoyWars3:
            return PlaytestGameBoyWarsRules.stats(for: element, ruleset: ruleset)
        case .daysOfRuin:
            return PlaytestDaysOfRuinRules.stats(for: element)
        case .advanceWars, .advanceWars2:
            return nil
        }
    }

    static func productionOptions(
        for building: Element,
        ruleset: PlaytestRuleset,
        tileset: Tileset? = nil
    ) -> [PlaytestProductionOption] {
        let elements: [Element]
        switch building.simplified {
        case .buildingBase:
            elements = landUnits(for: ruleset)
        case .buildingAirport:
            elements = airUnits(for: ruleset)
        case .buildingPort:
            elements = seaUnits(for: ruleset)
        default:
            return []
        }
        return elements.compactMap { element in
            guard let stats = stats(for: element, ruleset: ruleset) else { return nil }
            let label = PaletteCatalog.label(for: element, tileset: tileset)
            return PlaytestProductionOption(element: element, label: label, cost: stats.cost)
        }
    }

    static func income(for building: Element) -> Int {
        switch building.simplified {
        case .buildingCity, .buildingBase, .buildingAirport, .buildingPort, .buildingHQ:
            return 1_000
        default:
            return 0
        }
    }

    /// The classic cartridges cap the active army at roughly fifty units;
    /// keeping the cap in the rulebook prevents a CPU turn from creating an
    /// unbounded army on an authored map.
    static func unitCap(for ruleset: PlaytestRuleset) -> Int {
        switch ruleset {
        case .famicomWars, .superFamicomWars: return 50
        default: return 50
        }
    }

    static func canAttack(_ attacker: Element, _ defender: Element, ruleset: PlaytestRuleset, primaryAmmo: Int? = nil) -> Bool {
        if ruleset == .advanceWars2 {
            guard let stats = PlaytestAdvanceWars2Rules.stats(for: attacker),
                  stats.attackPower > 0,
                  PlaytestAdvanceWars2Rules.canAttack(attacker, defender, primaryAmmo: primaryAmmo) else { return false }
            return true
        }
        if ruleset == .advanceWars {
            guard let stats = PlaytestAdvanceWarsRules.stats(for: attacker),
                  stats.attackPower > 0,
                  PlaytestAdvanceWarsRules.canAttack(attacker, defender, primaryAmmo: primaryAmmo) else { return false }
            return true
        }

        guard let attackerStats = stats(for: attacker, ruleset: ruleset),
              let defenderStats = stats(for: defender, ruleset: ruleset),
              attackerStats.attackPower > 0 else { return false }

        // Once a limited primary magazine is empty, only a unit with an
        // explicitly modelled secondary weapon may still attack.  The old
        // generic path ignored this check, which let artillery, rockets, and
        // every Game Boy Wars limited-ammo unit fire forever.
        if let primaryAmmo,
           attackerStats.primaryAmmo != nil,
           primaryAmmo <= 0,
           attackerStats.secondaryAttackPower == nil {
            return false
        }

        let targetDomain = defenderStats.domain
        if ruleset == .daysOfRuin {
            switch attacker.simplified {
            case .unitInfantry, .unitMech, .unitPipeRunner, .unitRecon,
                 .unitTank, .unitMDTank, .unitMegaTank, .unitArtillery,
                 .unitNeoTank, .unitRocket:
                return targetDomain == .land || targetDomain == .sea
            case .unitAntiAir:
                return targetDomain == .air || targetDomain == .land
            case .unitMissile:
                return targetDomain == .air
            case .unitFighter:
                return targetDomain == .air
            case .unitBomber:
                return targetDomain != .air
            case .unitStealth, .unitBCopter:
                return targetDomain == .air || targetDomain == .land
            case .unitBlackBoat:
                return targetDomain == .sea || targetDomain == .land
            case .unitCruiser:
                return targetDomain == .air || targetDomain == .sea
            case .unitSub:
                return targetDomain == .sea
            case .unitBattleship:
                return targetDomain != .air
            default:
                return false
            }
        }

        switch attacker.simplified {
        case .unitInfantry, .unitMech, .unitRecon, .unitTank, .unitMDTank, .unitNeoTank,
             .unitMegaTank, .unitOozium, .unitAPC, .unitPipeRunner:
            return targetDomain == .land
        case .unitArtillery, .unitRocket, .unitMissile:
            return targetDomain != .air
        case .unitAntiAir:
            return targetDomain == .air || targetDomain == .land
        case .unitTCopter, .unitLander:
            return false
        case .unitBCopter, .unitBomber:
            return targetDomain != .air
        case .unitFighter, .unitStealth:
            return true
        case .unitBlackBomb:
            return targetDomain != .air
        case .unitBlackBoat:
            return false
        case .unitBattleship:
            return targetDomain != .air
        case .unitCarrier:
            return targetDomain == .air
        case .unitCruiser:
            return targetDomain == .air || targetDomain == .sea
        case .unitSub:
            return targetDomain == .sea
        default:
            return false
        }
    }

    static func usesPrimaryWeapon(_ attacker: Element, _ defender: Element, ruleset: PlaytestRuleset, primaryAmmo: Int? = nil) -> Bool {
        if ruleset == .advanceWars2 {
            return PlaytestAdvanceWars2Rules.usesPrimaryWeapon(attacker, defender, primaryAmmo: primaryAmmo)
        }
        if ruleset == .advanceWars {
            return PlaytestAdvanceWarsRules.usesPrimaryWeapon(attacker, defender, primaryAmmo: primaryAmmo)
        }
        guard let capacity = stats(for: attacker, ruleset: ruleset)?.primaryAmmo else { return false }
        return (primaryAmmo ?? capacity) > 0
    }

    /// Returns the movement points consumed by a unit entering a tile. The
    /// terrain table is deliberately expressed in terms of unit movement
    /// types instead of broad land/air/sea domains: Dual Strike distinguishes
    /// foot, tires, treads, Piperunners, and naval ships on Woods, Mountains,
    /// Rivers, and Reefs.
    static func movementCost(
        for unit: Element,
        stats: PlaytestUnitStats,
        terrain: Element,
        ruleset: PlaytestRuleset = .dualStrike,
        weather: PlaytestWeather = .clear,
        tileset: Tileset? = nil
    ) -> Int? {
        switch ruleset {
        case .dualStrike:
            return PlaytestDualStrikeRules.movementCost(for: unit, terrain: terrain)
        case .advanceWars2:
            return PlaytestAdvanceWars2Rules.movementCost(for: unit, terrain: terrain, weather: weather)
        case .advanceWars:
            return PlaytestAdvanceWarsRules.movementCost(for: unit, terrain: terrain, weather: weather)
        case .famicomWars:
            return PlaytestFamicomWarsRules.movementCost(for: unit, terrain: terrain)
        case .superFamicomWars:
            return PlaytestSuperFamicomWarsRules.movementCost(for: unit, terrain: terrain)
        case .gameBoyWars, .gameBoyWars2, .gameBoyWars3:
            return PlaytestGameBoyWarsRules.movementCost(for: unit, terrain: terrain, ruleset: ruleset)
        case .daysOfRuin:
            return PlaytestDaysOfRuinRules.movementCost(for: unit, terrain: terrain, weather: weather)
        }
    }

    /// Snow in Dual Strike leaves movement points unchanged but doubles the
    /// fuel/rations charged for every movement point. The GBA rules keep the
    /// normal one-fuel-per-point cost in every weather condition.
    static func movementFuelCost(
        for unit: Element,
        movement: Int,
        ruleset: PlaytestRuleset,
        weather: PlaytestWeather
    ) -> Int {
        if ruleset == .dualStrike {
            return PlaytestDualStrikeRules.movementFuelCost(
                for: unit,
                movement: movement,
                weather: weather
            )
        }
        return movement
    }

    static func maximumAttackRange(for stats: PlaytestUnitStats, ruleset: PlaytestRuleset, weather: PlaytestWeather) -> Int {
        switch ruleset {
        case .dualStrike:
            return PlaytestDualStrikeRules.maximumAttackRange(for: stats, weather: weather)
        case .daysOfRuin:
            return PlaytestDaysOfRuinRules.maximumAttackRange(for: stats, weather: weather)
        default:
            return stats.maxRange
        }
    }

    static func damage(
        attacker: Element,
        defender: Element,
        ruleset: PlaytestRuleset,
        attackerHealth: Int = 100,
        defenderHealth: Int = 100,
        terrain: Element = .terrainPlain,
        primaryAmmo: Int? = nil,
        randomize: Bool = true
    ) -> Int? {
        if ruleset == .advanceWars2 {
            return PlaytestAdvanceWars2Rules.damage(
                attacker: attacker,
                defender: defender,
                attackerHealth: attackerHealth,
                defenderHealth: defenderHealth,
                terrain: terrain,
                primaryAmmo: primaryAmmo,
                randomize: randomize
            )
        }
        if ruleset == .advanceWars {
            return PlaytestAdvanceWarsRules.damage(
                attacker: attacker,
                defender: defender,
                attackerHealth: attackerHealth,
                defenderHealth: defenderHealth,
                terrain: terrain,
                primaryAmmo: primaryAmmo,
                randomize: randomize
            )
        }

        guard canAttack(attacker, defender, ruleset: ruleset, primaryAmmo: primaryAmmo),
              let attackerStats = stats(for: attacker, ruleset: ruleset),
              let defenderStats = stats(for: defender, ruleset: ruleset) else { return nil }

        let attackerType = attacker.simplified
        let defenderType = defender.simplified
        let useSecondary = attackerStats.primaryAmmo != nil &&
            !usesPrimaryWeapon(attacker, defender, ruleset: ruleset, primaryAmmo: primaryAmmo)
        let baseAttackPower = useSecondary
            ? (attackerStats.secondaryAttackPower ?? 0)
            : attackerStats.attackPower
        guard baseAttackPower > 0 else { return nil }

        let multiplier: Int
        switch attackerType {
        case .unitAntiAir:
            multiplier = defenderStats.domain == .air ? 100 : 45
        case .unitMissile:
            multiplier = defenderStats.domain == .air ? 100 : 35
        case .unitFighter:
            multiplier = defenderStats.domain == .air ? 100 : 45
        case .unitBomber:
            multiplier = defenderStats.domain == .land ? 100 : 60
        case .unitCruiser:
            multiplier = defenderStats.domain == .air ? 80 : 70
        case .unitSub:
            multiplier = defenderType == .unitBattleship || defenderType == .unitCarrier ? 95 : 70
        case .unitBattleship:
            multiplier = defenderStats.domain == .land ? 85 : 65
        case .unitArtillery, .unitRocket, .unitPipeRunner:
            multiplier = defenderStats.domain == .land ? 78 : 55
        case .unitBlackBoat:
            multiplier = defenderStats.domain == .land ? 70 : 50
        case .unitCarrier:
            multiplier = defenderStats.domain == .air ? 100 : 0
        default:
            multiplier = defenderStats.domain == .land ? 78 : 42
        }
        // Dual Strike stores health as a percentage internally. A unit at
        // 10 HP (100) deals full damage, while 9 HP (90) deals 90%, and so
        // on down to 1 HP (10).
        let healthScale = Double(max(1, min(100, attackerHealth))) / 100
        let rawDamage = Double(baseAttackPower * multiplier) / 100 * healthScale
        return max(1, min(100, Int(rawDamage.rounded(.down))))
    }

    static func terrainStars(for terrain: Element, ruleset: PlaytestRuleset) -> Int {
        if ruleset == .advanceWars2 {
            return PlaytestAdvanceWars2Rules.terrainStars(for: terrain)
        }
        if ruleset == .advanceWars {
            return PlaytestAdvanceWarsRules.terrainStars(for: terrain)
        }
        if ruleset == .famicomWars || ruleset == .superFamicomWars ||
            ruleset == .gameBoyWars || ruleset == .gameBoyWars2 || ruleset == .gameBoyWars3 {
            switch terrain.simplified {
            case .terrainPlain, .terrainPlainD, .terrainReef: return 1
            case .terrainWood: return 2
            case .buildingCity, .buildingBase, .buildingAirport, .buildingPort,
                 .buildingTower, .buildingLab: return 3
            case .terrainMountain, .buildingHQ: return 4
            default: return 0
            }
        }
        if ruleset == .daysOfRuin {
            switch terrain.simplified {
            case .terrainPlain, .terrainPlainD, .terrainReef: return 1
            case .terrainWood: return 3
            case .buildingCity, .buildingBase, .buildingAirport, .buildingPort: return 3
            case .terrainMountain, .buildingHQ: return 4
            default: return 0
            }
        }
        switch terrain.simplified {
        case .terrainPlain, .terrainPlainD, .terrainReef: return 1
        case .terrainWood: return 2
        case .buildingCity, .buildingBase, .buildingAirport, .buildingPort, .buildingTower, .buildingLab, .buildingSilo: return 3
        case .terrainMountain, .buildingHQ: return 4
        default: return 0
        }
    }

    static func maxFuel(for element: Element, ruleset: PlaytestRuleset) -> Int {
        stats(for: element, ruleset: ruleset)?.maxFuel ?? 100
    }

    static func dailyFuelUse(for element: Element, ruleset: PlaytestRuleset) -> Int {
        stats(for: element, ruleset: ruleset)?.dailyFuelUse ?? 0
    }

    static func primaryAmmo(for element: Element, ruleset: PlaytestRuleset) -> Int? {
        stats(for: element, ruleset: ruleset)?.primaryAmmo
    }

    static func isCapturableBuilding(_ building: Element, ruleset: PlaytestRuleset) -> Bool {
        guard building.isBuilding else { return false }
        if (ruleset == .advanceWars2 || ruleset == .dualStrike), building.simplified == .buildingSilo {
            return false
        }
        if ruleset == .advanceWars,
           [.buildingSilo, .buildingLab, .buildingTower].contains(building.simplified) {
            return false
        }
        if ruleset == .famicomWars,
           [.buildingSilo, .buildingLab, .buildingTower].contains(building.simplified) {
            return false
        }
        if ruleset == .gameBoyWars || ruleset == .gameBoyWars2 || ruleset == .gameBoyWars3,
           [.buildingSilo, .buildingLab, .buildingTower].contains(building.simplified) {
            return false
        }
        if ruleset == .daysOfRuin,
           [.buildingSilo, .buildingLab, .buildingTower].contains(building.simplified) {
            return false
        }
        return true
    }

    private static func isSupported(_ element: Element, ruleset: PlaytestRuleset) -> Bool {
        switch ruleset {
        case .dualStrike:
            return PlaytestDualStrikeRules.stats(for: element) != nil
        case .advanceWars:
            return PlaytestAdvanceWarsRules.stats(for: element) != nil
        case .advanceWars2:
            return PlaytestAdvanceWars2Rules.stats(for: element) != nil
        case .famicomWars:
            return PlaytestFamicomWarsRules.stats(for: element) != nil
        case .superFamicomWars:
            return PlaytestSuperFamicomWarsRules.stats(for: element) != nil
        case .gameBoyWars, .gameBoyWars2, .gameBoyWars3:
            return PlaytestGameBoyWarsRules.stats(for: element, ruleset: ruleset) != nil
        case .daysOfRuin:
            return PlaytestDaysOfRuinRules.stats(for: element) != nil
        }
    }

    private static func landUnits(for ruleset: PlaytestRuleset) -> [Element] {
        if ruleset == .dualStrike {
            return PlaytestDualStrikeRules.landUnits
        }

        if ruleset == .advanceWars2 {
            return PlaytestAdvanceWars2Rules.landUnits
        }
        if ruleset == .advanceWars {
            return PlaytestAdvanceWarsRules.landUnits
        }
        switch ruleset {
        case .famicomWars: return PlaytestFamicomWarsRules.landUnits
        case .superFamicomWars: return PlaytestSuperFamicomWarsRules.landUnits
        case .gameBoyWars, .gameBoyWars2, .gameBoyWars3: return PlaytestGameBoyWarsRules.landUnits
        case .daysOfRuin: return PlaytestDaysOfRuinRules.landUnits
        default: return []
        }
    }

    private static func airUnits(for ruleset: PlaytestRuleset) -> [Element] {
        if ruleset == .dualStrike {
            return PlaytestDualStrikeRules.airUnits
        }
        if ruleset == .advanceWars2 {
            return PlaytestAdvanceWars2Rules.airUnits
        }
        if ruleset == .advanceWars {
            return PlaytestAdvanceWarsRules.airUnits
        }
        switch ruleset {
        case .famicomWars: return PlaytestFamicomWarsRules.airUnits
        case .superFamicomWars: return PlaytestSuperFamicomWarsRules.airUnits
        case .gameBoyWars, .gameBoyWars2, .gameBoyWars3: return PlaytestGameBoyWarsRules.airUnits
        case .daysOfRuin: return PlaytestDaysOfRuinRules.airUnits
        default: return []
        }
    }

    private static func seaUnits(for ruleset: PlaytestRuleset) -> [Element] {
        if ruleset == .dualStrike {
            return PlaytestDualStrikeRules.seaUnits
        }
        if ruleset == .advanceWars2 {
            return PlaytestAdvanceWars2Rules.seaUnits
        }
        if ruleset == .advanceWars {
            return PlaytestAdvanceWarsRules.seaUnits
        }
        switch ruleset {
        case .famicomWars: return PlaytestFamicomWarsRules.seaUnits
        case .superFamicomWars: return PlaytestSuperFamicomWarsRules.seaUnits
        case .gameBoyWars, .gameBoyWars2, .gameBoyWars3: return PlaytestGameBoyWarsRules.seaUnits
        case .daysOfRuin: return PlaytestDaysOfRuinRules.seaUnits
        default: return []
        }
    }
}
