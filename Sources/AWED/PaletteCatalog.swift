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
            if tileset.isFamicomWarsFamily || tileset.isGameBoyWarsFamily {
                return tab != .extra
            }
            return true
        }
    }

    static func visibleArmies(for tileset: Tileset) -> [Int] {
        if tileset == .daysOfRuin {
            return [
                AWConstants.armyOrangeStar,
                AWConstants.armyBlueMoon,
                AWConstants.armyYellowComet,
                AWConstants.armyBlackHole
            ]
        }
        if tileset.isFamicomWarsFamily {
            return [
                AWConstants.armyOrangeStar,
                AWConstants.armyBlueMoon,
                AWConstants.armyGreenEarth,
                AWConstants.armyYellowComet
            ]
        }
        if tileset.isGameBoyWarsFamily {
            return [AWConstants.armyOrangeStar, AWConstants.armyBlueMoon]
        }
        return Array(0..<AWConstants.playableArmies)
    }

    /// Factions that can participate in the local playtest for a tileset.
    /// Famicom Wars exposes all four editor factions: Orange Star remains the
    /// human-controlled side while every other participating faction is CPU.
    /// GB Wars remains two-player. Days of Ruin has no Green Earth-equivalent
    /// faction, so its four source armies use shared rows 0, 1, 3, and 4.
    static func playtestArmies(for tileset: Tileset) -> [Int] {
        switch tileset {
        case .aw1:
            return Array(0..<4)
        case .famicomWars, .superFamicomWars:
            return visibleArmies(for: tileset)
        case .gbWars, .gbWars2, .gbWars3, .daysOfRuin:
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

        if let tileset, tileset == .daysOfRuin {
            if tab == .unit {
                let deleteItem = items.first(where: { $0.element == .unitDelete })
                let rosterItems = daysOfRuinUnitRoster.compactMap { rosterElement in
                    items.first(where: { $0.element.simplified == rosterElement.simplified })
                }
                return ([deleteItem].compactMap { $0 } + rosterItems).map { item in
                    guard let label = daysOfRuinUnitLabel(for: item.element) else { return item }
                    return item.withLabel(label)
                }
            }
            return items
                .filter { item in
                    !item.element.isBuilding
                        || visibleArmies(for: tileset).contains(item.element.army)
                        || item.element.army == AWConstants.armyNeutral
                }
                .map { item in
                    guard item.element.isBuilding,
                          item.element.simplified != .buildingSilo else { return item }
                    return item.withLabel(buildingLabel(for: item.element, tileset: tileset))
                }
        }

        if let tileset, tileset.isGameBoyWarsFamily {
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
                            // GB Wars includes faction airports and ports;
                            // keep them in the authoring palette alongside
                            // HQs, cities, and bases. The remaining entries
                            // are not part of the supplied GB property atlas.
                            let hiddenBuildings: Set<Element> = [
                                .buildingSilo,
                                .buildingTower,
                                .buildingLab
                            ]
                            guard !hiddenBuildings.contains(item.element.simplified) else { return false }
                            // GB Wars has faction HQs/factories/airports/ports;
                            // the supplied GBW2 map table only has a neutral
                            // city, so do not offer synthetic neutral slots.
                            if item.element.army == AWConstants.armyNeutral,
                               [.buildingHQ, .buildingBase, .buildingAirport, .buildingPort]
                                .contains(item.element.simplified) {
                                return false
                            }
                            return visibleArmies(for: tileset).contains(item.element.army)
                                || item.element.army == AWConstants.armyNeutral
                        }

                        let hiddenTerrain: Set<Element> = [
                            .terrainPlainD,
                            .terrainReef,
                            .terrainPipe,
                            .terrainSeam
                        ]
                        return !hiddenTerrain.contains(item.element.simplified)
                    }
                    return true
                }
                .map { item in
                    guard item.element.isBuilding else { return item }
                    return item.withLabel(buildingLabel(for: item.element, tileset: tileset))
                }
        }

        // Famicom Wars has its own sixteen-unit roster. The source-derived
        // map sheet uses the original names (Howitzer, Supply Truck, and
        // Scout), while the shared Element table supplies compatible slots
        // for those three units (Rocket, Recon, and B-Copter respectively).
        // Keep the unsupported later Advance Wars units out of this palette
        // instead of exposing a misleading fallback sprite.
        if let tileset, tileset.isFamicomWarsFamily, tab == .unit {
            let deleteItem = items.first(where: { $0.element == .unitDelete })
            let rosterItems = famicomWarsUnitRoster.compactMap { rosterElement in
                items.first(where: { $0.element.simplified == rosterElement.simplified })
            }
            return ([deleteItem].compactMap { $0 } + rosterItems).map { item in
                guard let label = famicomWarsUnitLabel(for: item.element) else { return item }
                return item.withLabel(label)
            }
        }

        // The NES game predates the later property set. Super Famicom Wars,
        // however, has genuine Railroad terrain plus Train Station and
        // Research Lab properties. The shared Pipe, Tower, and Lab element
        // slots preserve the map-file contract while the palette presents
        // the source-game names.
        guard let tileset, tileset.isFamicomWarsFamily else { return items }
        return items
            .filter { item in
                if item.element.isBuilding {
                    guard visibleArmies(for: tileset).contains(item.element.army)
                            || item.element.army == AWConstants.armyNeutral else { return false }
                }
                switch item.element.simplified {
                case .terrainPlainD, .terrainSeam, .buildingSilo:
                    return false
                case .terrainPipe:
                    return tileset == .superFamicomWars
                case .buildingTower, .buildingLab:
                    return tileset == .superFamicomWars
                default:
                    return true
                }
            }
            .map { item in
                if tileset == .superFamicomWars, item.element.simplified == .terrainPipe {
                    return item.withLabel("Railroad")
                }
                guard item.element.isBuilding else { return item }
                return item.withLabel(buildingLabel(for: item.element, tileset: tileset))
            }
    }

    static func label(for element: Element, tileset: Tileset? = nil) -> String {
        if element == .unitEmpty { return "Empty Unit" }

        if tileset?.isGameBoyWarsFamily == true, let label = gbWarsUnitLabel(for: element) {
            return label
        }

        if tileset?.isFamicomWarsFamily == true, let label = famicomWarsUnitLabel(for: element) {
            return label
        }

        if tileset == .daysOfRuin, let label = daysOfRuinUnitLabel(for: element) {
            return label
        }

        if tileset == .superFamicomWars, element.simplified == .terrainPipe {
            return "Railroad"
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

    private static let famicomWarsUnitRoster: [Element] = [
        .unitInfantry,
        .unitMech,
        .unitAPC,
        .unitTank,
        .unitMDTank,
        .unitArtillery,
        .unitRocket,
        .unitAntiAir,
        .unitMissile,
        .unitRecon,
        .unitTCopter,
        .unitBCopter,
        .unitFighter,
        .unitBomber,
        .unitLander,
        .unitBattleship
    ]

    private static let daysOfRuinUnitRoster: [Element] = [
        .unitInfantry, .unitMech, .unitPipeRunner, .unitRecon, .unitOozium,
        .unitAntiAir, .unitTank, .unitMDTank, .unitMegaTank, .unitArtillery,
        .unitNeoTank, .unitRocket, .unitMissile, .unitAPC, .unitFighter,
        .unitBomber, .unitStealth, .unitBCopter, .unitTCopter, .unitBlackBoat,
        .unitCruiser, .unitSub, .unitCarrier, .unitBattleship, .unitLander
    ]

    private static func famicomWarsUnitLabel(for element: Element) -> String? {
        switch element.simplified {
        case .unitRocket: return "Howitzer"
        case .unitRecon: return "Supply Truck"
        case .unitTCopter: return "Helicopter"
        case .unitBCopter: return "Scout"
        case .unitMDTank: return "Md. Tank"
        case .unitAntiAir: return "Anti-Air"
        case .unitMissile: return "Missiles"
        default: return nil
        }
    }

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

    private static func daysOfRuinUnitLabel(for element: Element) -> String? {
        switch element.simplified {
        case .unitPipeRunner: return "Bike"
        case .unitOozium: return "Flare"
        case .unitNeoTank: return "Anti-Tank"
        case .unitMegaTank: return "War Tank"
        case .unitAPC: return "Rig"
        case .unitStealth: return "Duster"
        case .unitBlackBoat: return "Gunboat"
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
        case .buildingTower:
            buildingName = tileset == .superFamicomWars ? "Train Station" : "Tower"
        case .buildingLab:
            buildingName = tileset == .superFamicomWars ? "Research Lab" : "Lab"
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
        if tileset == .daysOfRuin {
            switch army {
            case AWConstants.armyOrangeStar: return "12th Battalion"
            case AWConstants.armyBlueMoon: return "Lazuria"
            case AWConstants.armyYellowComet: return "New Rubinelle Army"
            case AWConstants.armyBlackHole: return "Intelligence Defense Systems"
            case AWConstants.armyNeutral: return "Neutral"
            default: return "Unavailable"
            }
        }
        if tileset?.isFamicomWarsFamily == true {
            switch army {
            case AWConstants.armyOrangeStar: return "Red Star"
            case AWConstants.armyBlueMoon: return "White Moon"
            case AWConstants.armyGreenEarth: return "Green Soil"
            case AWConstants.armyYellowComet: return "Yellow Comet"
            case AWConstants.armyNeutral: return "Neutral"
            default: return "Unavailable"
            }
        }
        if tileset?.isGameBoyWarsFamily == true {
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
        if tileset == .daysOfRuin {
            switch army {
            case AWConstants.armyOrangeStar: return "12th"
            case AWConstants.armyBlueMoon: return "Laz."
            case AWConstants.armyYellowComet: return "NRA"
            case AWConstants.armyBlackHole: return "IDS"
            default: return "—"
            }
        }
        return armyName(army, tileset: tileset)
    }
}
