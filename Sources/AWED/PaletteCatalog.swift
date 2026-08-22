import Foundation
import AWEDCore

struct PaletteItem: Identifiable, Hashable {
    let id: String
    let element: Element
    let label: String
    let tab: PaletteTab

    init(_ element: Element, label: String, tab: PaletteTab, position: String) {
        self.id = "\(tab.rawValue)-\(position)-\(element.value)"
        self.element = element
        self.label = label
        self.tab = tab
    }

    private init(id: String, element: Element, label: String, tab: PaletteTab) {
        self.id = id
        self.element = element
        self.label = label
        self.tab = tab
    }

    func withLabel(_ label: String) -> PaletteItem {
        PaletteItem(id: id, element: element, label: label, tab: tab)
    }
}

enum PaletteCatalog {
    static func tabs(for tileset: Tileset) -> [PaletteTab] {
        PaletteTab.allCases.filter { tab in
            if tileset == .famicomWars || tileset == .gbWars {
                return tab != .extra
            }
            return true
        }
    }

    static func visibleArmies(for tileset: Tileset) -> [Int] {
        if tileset == .famicomWars {
            return [
                AWConstants.armyOrangeStar,
                AWConstants.armyBlueMoon,
                AWConstants.armyGreenEarth,
                AWConstants.armyYellowComet
            ]
        }
        if tileset == .gbWars {
            return [AWConstants.armyOrangeStar, AWConstants.armyBlueMoon]
        }
        return Array(0..<AWConstants.playableArmies)
    }

    /// Factions that can participate in the local playtest for a tileset.
    /// AW1 and Famicom Wars do not have a Black Hole player; GB Wars is the
    /// two-player Red Star/White Moon variant.
    static func playtestArmies(for tileset: Tileset) -> [Int] {
        switch tileset {
        case .aw1:
            return Array(0..<4)
        case .famicomWars, .gbWars:
            return visibleArmies(for: tileset)
        default:
            return Array(0..<AWConstants.playableArmies)
        }
    }

    static func items(for tab: PaletteTab, tileset: Tileset? = nil) -> [PaletteItem] {
        let items: [PaletteItem]
        switch tab {
        case .terrain: items = terrainItems
        case .unit: items = unitItems
        case .extra: items = extraItems
        case .mapArt: items = []
        }

        if tileset == .gbWars {
            if tab == .unit {
                let deleteItem = items.first(where: { $0.element == .unitDelete })
                let rosterItems = gbWarsUnitRoster.compactMap { rosterElement in
                    items.first(where: { $0.element.simplified == rosterElement })
                }
                return ([deleteItem].compactMap { $0 } + rosterItems).map { item in
                    guard let label = gbWarsUnitLabel(for: item.element) else { return item }
                    return item.withLabel(label)
                }
            }
            return items
                .filter { item in
                    if item.tab == .terrain {
                        if item.element.isBuilding {
                            let hiddenBuildings: Set<Element> = [
                                .buildingSilo,
                                .buildingAirport,
                                .buildingPort,
                                .buildingTower,
                                .buildingLab
                            ]
                            guard !hiddenBuildings.contains(item.element.simplified) else { return false }
                            return visibleArmies(for: .gbWars).contains(item.element.army)
                                || item.element.army == AWConstants.armyNeutral
                        }

                        let hiddenTerrain: Set<Element> = [
                            .terrainPlainD,
                            .terrainReef,
                            .terrainShoal,
                            .terrainRiver,
                            .terrainPipe,
                            .terrainSeam
                        ]
                        return !hiddenTerrain.contains(item.element.simplified)
                    }
                    return true
                }
                .map { item in
                    guard item.element.isBuilding else { return item }
                    return item.withLabel(buildingLabel(for: item.element, tileset: .gbWars))
                }
        }

        // Famicom Wars predates the Dual Strike map objectives and the
        // additional AW property set. Keep those entries out of the authoring
        // palette instead of showing a guessed fallback sprite from the
        // source-derived atlas.
        guard tileset == .famicomWars else { return items }
        return items
            .filter { item in
                if item.element.isBuilding {
                    guard visibleArmies(for: .famicomWars).contains(item.element.army)
                            || item.element.army == AWConstants.armyNeutral else { return false }
                }
                switch item.element.simplified {
                case .terrainPlainD, .terrainPipe, .terrainSeam,
                     .buildingTower, .buildingLab, .buildingSilo:
                    return false
                default:
                    return true
                }
            }
            .map { item in
                guard item.element.isBuilding else { return item }
                return item.withLabel(buildingLabel(for: item.element, tileset: .famicomWars))
            }
    }

    static func label(for element: Element, tileset: Tileset? = nil) -> String {
        if element == .unitEmpty { return "Empty Unit" }

        if tileset == .gbWars, let label = gbWarsUnitLabel(for: element) {
            return label
        }

        if element.isBuilding {
            return buildingLabel(for: element, tileset: tileset)
        }

        let items: [PaletteItem]
        if element.isUnit {
            items = unitItems
        } else if element.isTerrain || element.isBuilding {
            items = terrainItems
        } else if element.isExtra {
            items = extraItems
        } else {
            return "Tile"
        }

        if let exact = items.first(where: { $0.element == element }) {
            return exact.label
        }
        if let simplified = items.first(where: { $0.element.simplified == element.simplified }) {
            return simplified.label
        }

        if element.isUnit { return "Unit" }
        if element.isBuilding { return "Building" }
        if element.isExtra { return "Extra" }
        if element.isTerrain { return "Terrain" }
        return "Tile"
    }

    /// The GB Wars cartridge uses a smaller roster and its own names for a
    /// few of the shared sprite slots. Keep the source element identities so
    /// the playtest rules can reuse the existing movement and damage tables.
    private static let gbWarsUnitRoster: [Element] = [
        .unitInfantry,
        .unitMech,
        .unitAPC,
        .unitRecon,
        .unitRocket,
        .unitAntiAir,
        .unitArtillery,
        .unitTank,
        .unitTCopter,
        .unitBCopter,
        .unitBomber,
        .unitLander,
        .unitSub,
        .unitCruiser,
        .unitBattleship
    ]

    private static func gbWarsUnitLabel(for element: Element) -> String? {
        switch element.simplified {
        case .unitRecon: return "Combat Buggy"
        case .unitRocket: return "Rocket Launcher"
        case .unitAntiAir: return "Anti-Air"
        case .unitTCopter: return "Transport Plane"
        case .unitBCopter: return "Copter"
        case .unitBattleship: return "Aegis Warship"
        default: return nil
        }
    }

    private static func buildingLabel(for element: Element, tileset: Tileset?) -> String {
        let buildingName: String
        switch element.simplified {
        case .buildingHQ: buildingName = "HQ"
        case .buildingCity: buildingName = "City"
        case .buildingBase: buildingName = "Base"
        case .buildingAirport: buildingName = "Airport"
        case .buildingPort: buildingName = "Port"
        case .buildingTower: buildingName = "Tower"
        case .buildingLab: buildingName = "Lab"
        case .buildingSilo: buildingName = "Missile silo"
        default: buildingName = "Building"
        }
        return "\(armyName(element.army, tileset: tileset)) \(buildingName)"
    }

    static let terrainItems: [PaletteItem] = {
        var items: [PaletteItem] = []
        func add(_ element: Element, _ label: String, _ position: String) {
            items.append(PaletteItem(element, label: label, tab: .terrain, position: position))
        }
        add(.terrainPlain, "Plains", "0-0")
        add(.terrainPlainD, "Ruins", "1-0")
        add(.terrainWood, "Woods", "2-0")
        add(.terrainMountain, "Mountains", "3-0")
        add(.terrainRoad, "Roads", "4-0")
        add(.terrainBridgeH, "Bridge", "5-0")
        add(.terrainSea, "Sea", "0-1")
        add(.terrainReef, "Reef", "1-1")
        add(.terrainShoal, "Shoal", "2-1")
        add(.terrainRiver, "River", "3-1")
        add(.terrainPipe, "Pipe", "4-1")
        add(.terrainSeam, "Pipe Seam", "5-1")
        let buildings: [(Element, String)] = [
            (.buildingHQ, "HQ"),
            (.buildingCity, "City"),
            (.buildingBase, "Base"),
            (.buildingAirport, "Airport"),
            (.buildingPort, "Port"),
            (.buildingTower, "Tower"),
            (.buildingLab, "Lab")
        ]
        for army in 0...4 {
            for (column, building) in buildings.enumerated() {
                add(building.0.changedArmy(army), "\(armyName(army)) \(building.1)", "\(column)-\(army + 3)")
            }
        }
        add(.buildingSilo, "Missile silo", "0-8")
        for (column, building) in buildings.dropFirst().enumerated() {
            add(building.0.changedArmy(AWConstants.armyNeutral), "Neutral \(building.1)", "\(column + 1)-8")
        }
        return items
    }()

    static let unitItems: [PaletteItem] = {
        var items: [PaletteItem] = []
        func add(_ element: Element, _ label: String, _ position: String) {
            items.append(PaletteItem(element, label: label, tab: .unit, position: position))
        }
        add(.unitDelete, "Delete unit", "4-2")
        let units: [(Element, String)] = [
            (.unitInfantry, "Infantry"),
            (.unitMech, "Mech"),
            (.unitAPC, "APC"),
            (.unitOozium, "Oozium"),
            (.unitRecon, "Recon"),
            (.unitTank, "Tank"),
            (.unitMDTank, "Medium Tank"),
            (.unitNeoTank, "Neotank"),
            (.unitMegaTank, "Megatank"),
            (.unitArtillery, "Artillery"),
            (.unitRocket, "Rocket"),
            (.unitPipeRunner, "Piperunner"),
            (.unitMissile, "Missile"),
            (.unitAntiAir, "Anti-air"),
            (.unitTCopter, "T-copter"),
            (.unitBCopter, "B-copter"),
            (.unitFighter, "Fighter"),
            (.unitBomber, "Bomber"),
            (.unitStealth, "Stealth"),
            (.unitBlackBomb, "Black Bomb"),
            (.unitBlackBoat, "Black Boat"),
            (.unitLander, "Lander"),
            (.unitCruiser, "Cruiser"),
            (.unitSub, "Submarine"),
            (.unitBattleship, "Battleship"),
            (.unitCarrier, "Carrier")
        ]
        for (index, unit) in units.enumerated() {
            let row = index < 4 ? 2 : index < 9 ? 3 : index < 14 ? 4 : index < 20 ? 5 : 6
            let column = index < 4 ? index : index < 9 ? index - 4 : index < 14 ? index - 9 : index < 20 ? index - 14 : index - 20
            add(unit.0, unit.1, "\(column)-\(row)")
        }
        return items
    }()

    static let extraItems: [PaletteItem] = {
        let entries: [(Element, String, String)] = [
            (.extraMCannonW, "Mini Cannon W", "0-0"),
            (.extraMCannonN, "Mini Cannon N", "1-0"),
            (.extraMCannonE, "Mini Cannon E", "2-0"),
            (.extraMCannonS, "Mini Cannon S", "3-0"),
            (.extraLCannon, "Large Cannon", "4-0"),
            (.extraBCannonN, "Black Cannon N", "0-1"),
            (.extraBCannons, "Black Cannon S", "1-1"),
            (.extraBobelisk, "Black Obelisk", "4-1"),
            (.extraVolcano, "Volcano", "0-3"),
            (.extraBlackArc, "Black Ark", "1-3"),
            (.extraSeaArc, "Sea Black Ark", "2-3"),
            (.extraFortress, "Fortress", "3-3"),
            (.extraBCrystal, "Black Crystal", "3-1"),
            (.extraDeathray, "Deathray", "2-1"),
            (.extraGSilo, "Grand Silo", "4-3")
        ]
        return entries.map { PaletteItem($0.0, label: $0.1, tab: .extra, position: $0.2) }
    }()

    static func armyName(_ army: Int, tileset: Tileset? = nil) -> String {
        if tileset == .famicomWars {
            switch army {
            case AWConstants.armyOrangeStar: return "Red Star"
            case AWConstants.armyBlueMoon: return "White Moon"
            case AWConstants.armyGreenEarth: return "Green Soil"
            case AWConstants.armyYellowComet: return "Yellow Star"
            case AWConstants.armyNeutral: return "Neutral"
            default: return "Unavailable"
            }
        }
        if tileset == .gbWars {
            switch army {
            case AWConstants.armyOrangeStar: return "Red Star"
            case AWConstants.armyBlueMoon: return "White Moon"
            default: break
            }
        }
        switch army {
        case AWConstants.armyOrangeStar: return "Orange Star"
        case AWConstants.armyBlueMoon: return "Blue Moon"
        case AWConstants.armyGreenEarth: return "Green Earth"
        case AWConstants.armyYellowComet: return "Gold Comet"
        case AWConstants.armyBlackHole: return "Black Hole"
        default: return "Neutral"
        }
    }

    static func armyAbbreviation(_ army: Int, tileset: Tileset? = nil) -> String {
        armyName(army, tileset: tileset)
    }
}
