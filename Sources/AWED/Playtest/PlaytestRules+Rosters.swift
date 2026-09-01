import AWEDCore

extension PlaytestRulebook {
    static func isSupported(_ element: Element, ruleset: PlaytestRuleset) -> Bool {
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

    static func landUnits(for ruleset: PlaytestRuleset) -> [Element] {
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

    static func airUnits(for ruleset: PlaytestRuleset) -> [Element] {
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

    static func seaUnits(for ruleset: PlaytestRuleset) -> [Element] {
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
