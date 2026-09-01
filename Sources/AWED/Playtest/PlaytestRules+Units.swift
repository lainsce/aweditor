import AWEDCore

extension PlaytestRulebook {
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
        case .buildingHQ where ruleset == .famicomWars:
            // Famicom Wars treats the HQ as a local land-unit production
            // point.  The 5x5 operating-area restriction is enforced by the
            // session, so this remains a legal option only for an HQ that is
            // actually connected to the army's production area.
            elements = PlaytestFamicomWarsRules.landUnits
        case .buildingCity where ruleset == .famicomWars:
            // On Bean Island the nearby city is the fifth opening production
            // point, but it is an infantry point rather than a second factory.
            elements = [.unitInfantry]
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

}
