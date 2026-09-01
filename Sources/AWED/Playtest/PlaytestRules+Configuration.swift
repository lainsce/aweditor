import AWEDCore

extension PlaytestRulebook {
    /// The source games share the same action vocabulary, but their CPUs do
    /// not value the same action equally. In particular, AW1's transport
    /// targeting and AW2's loaded-transport targeting are documented by
    /// reverse-engineered priority tables, while Super Famicom Wars uses
    /// simultaneous combat and rewards a more forward attack posture.
    static func cpuPolicy(for ruleset: PlaytestRuleset) -> CPUPolicy {
        switch ruleset {
        case .dualStrike:
            return dualStrikeCPUPolicy()
        case .advanceWars:
            return advanceWarsCPUPolicy()
        case .advanceWars2:
            return advanceWars2CPUPolicy()
        case .famicomWars:
            return famicomWarsCPUPolicy()
        case .superFamicomWars:
            return superFamicomWarsCPUPolicy()
        case .gameBoyWars:
            return gameBoyWarsCPUPolicy()
        case .gameBoyWars2:
            return gameBoyWars2CPUPolicy()
        case .gameBoyWars3:
            return gameBoyWars3CPUPolicy()
        case .daysOfRuin:
            return daysOfRuinCPUPolicy()
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

}
