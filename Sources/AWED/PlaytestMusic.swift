import AWEDCore

/// The optional result cues used by cartridges that provide separate
/// winning/neutral/losing play tracks. A missing result-specific file falls
/// back to the ordinary army track, so adding these files is incremental.
enum PlaytestMusicCue: String, Sendable {
    case neutral
    case winning
    case losing
}

/// Converts the editor's stable tileset/army values into the filename
/// vocabulary used by the Play BGM folder. The resolver deliberately emits
/// several spelling variants: existing files use compact names such as
/// `play_famicomwars_redstar.mp3`, while readable names such as
/// `play_famicom_wars_red_star.mp3` are easier to maintain going forward.
enum PlaytestMusicRouter {
    static func resourceNameCandidates(
        tileset: Tileset,
        army: Int,
        cue: PlaytestMusicCue = .neutral
    ) -> [String] {
        let games = gameTokens(for: tileset)
        let factions = factionTokens(for: tileset, army: army)
        // GB Wars 3 appends a single cartridge-style letter directly to the
        // faction token: `redstarn`, `redstarl`, and `redstarw`. Keep the
        // readable underscore spellings as fallbacks for future additions.
        let cueSuffixes: [String]
        if tileset == .gbWars3 {
            cueSuffixes = switch cue {
            case .neutral: ["n", "_n", "_neutral", ""]
            case .losing: ["l", "_l", "_losing", "_lose", ""]
            case .winning: ["w", "_w", "_winning", "_win", ""]
            }
        } else {
            cueSuffixes = switch cue {
            case .neutral: ["_neutral", ""]
            case .losing: ["_losing", "_lose", ""]
            case .winning: ["_winning", "_win", ""]
            }
        }

        var names: [String] = []
        for game in games {
            for faction in factions {
                for suffix in cueSuffixes {
                    names.append("play_\(game)_\(faction)\(suffix)")
                }
            }
            // Days of Ruin uses one no-CO track for every army. This also
            // makes a game-wide fallback useful for future one-track sets.
            for suffix in cueSuffixes {
                names.append("play_\(game)\(suffix)")
            }
            // Days of Ruin's no-CO soundtrack is commonly named explicitly
            // rather than after a faction. Keep those spellings as a final
            // fallback without affecting faction-specific sets.
            if tileset == .daysOfRuin {
                names.append("play_\(game)_no_co")
                names.append("play_\(game)_noco")
            }
        }
        return unique(names)
    }

    private static func gameTokens(for tileset: Tileset) -> [String] {
        switch tileset {
        case .normal, .snow, .desert, .wasteland:
            ["dualstrike", "dual_strike", "awds", "advancewarsds", "advance_wars_dual_strike"]
        case .aw1:
            ["aw1", "advancewars1", "advance_wars_1", "advancewars", "advance_wars"]
        case .aw2:
            ["aw2", "advancewars2", "advance_wars_2"]
        case .famicomWars:
            ["famicomwars", "famicom_wars"]
        case .gbWars:
            ["gbwars", "gb_wars", "gameboywars", "game_boy_wars"]
        case .superFamicomWars:
            ["superfamicomwars", "super_famicom_wars"]
        case .gbWars2:
            ["gbwars2", "gb_wars_2", "gameboywars2", "game_boy_wars_2"]
        case .gbWars3:
            ["gbwars3", "gb_wars_3", "gameboywars3", "game_boy_wars_3"]
        case .daysOfRuin:
            ["daysofruin", "days_of_ruin", "dor", "awdr", "awdor", "advancewarsdaysofruin", "advance_wars_days_of_ruin"]
        }
    }

    private static func factionTokens(for tileset: Tileset, army: Int) -> [String] {
        switch tileset {
        case .gbWars, .gbWars2, .gbWars3:
            switch army {
            case AWConstants.armyOrangeStar: ["redstar", "red_star", "red"]
            case AWConstants.armyBlueMoon: ["whitemoon", "white_moon", "white"]
            default: ["army\(army)"]
            }
        case .daysOfRuin:
            switch army {
            case AWConstants.armyOrangeStar: ["12thbattalion", "12th_battalion", "orangestar", "orange_star", "orange"]
            case AWConstants.armyBlueMoon: ["lazuria", "bluemoon", "blue_moon", "blue"]
            case AWConstants.armyYellowComet: ["newrubinellearmy", "new_rubinelle_army", "goldcomet", "gold_comet"]
            case AWConstants.armyBlackHole: ["intelligencedefensesystems", "intelligence_defense_systems", "ids", "blackhole", "black_hole"]
            default: ["army\(army)"]
            }
        case .famicomWars:
            switch army {
            case AWConstants.armyOrangeStar: ["redstar", "red_star", "red"]
            case AWConstants.armyBlueMoon: ["whitemoon", "white_moon", "white"]
            case AWConstants.armyGreenEarth: ["greensoil", "green_soil", "green"]
            case AWConstants.armyYellowComet: ["yellowcomet", "yellow_comet", "yellow"]
            default: ["army\(army)"]
            }
        default:
            switch army {
            case AWConstants.armyOrangeStar: ["orangestar", "orange_star", "orange"]
            case AWConstants.armyBlueMoon: ["bluemoon", "blue_moon", "blue"]
            case AWConstants.armyGreenEarth: ["greenearth", "green_earth", "green"]
            case AWConstants.armyYellowComet: ["goldcomet", "gold_comet", "yellowcomet", "yellow_comet", "yellow"]
            case AWConstants.armyBlackHole: ["blackhole", "black_hole", "black"]
            default: ["army\(army)"]
            }
        }
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
