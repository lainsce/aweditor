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
        // The original NES release is a two-army game. Green Soil and
        // Yellow Comet are fan additions and must not leak into either the
        // authoring palette or the Famicom playtest roster. Super Famicom
        // Wars is a separate release and retains its four-army roster.
        if tileset == .famicomWars {
            return [AWConstants.armyOrangeStar, AWConstants.armyBlueMoon]
        }
        if tileset == .superFamicomWars {
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
    /// Famicom Wars is the original two-army NES game: Red Star remains the
    /// human-controlled side while White Moon is the opposing CPU side.
    /// Super Famicom Wars keeps its four-army roster. GB Wars remains
    /// two-player. Days of Ruin has no Green Earth-equivalent faction, so its
    /// four source armies use shared rows 0, 1, 3, and 4.
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
        let base = baseItems(for: tab)
        guard let tileset else { return base }
        if tileset == .daysOfRuin { return daysOfRuinItems(base, tab: tab, tileset: tileset) }
        if tileset.isGameBoyWarsFamily { return gameBoyItems(base, tab: tab, tileset: tileset) }
        if tileset.isFamicomWarsFamily { return famicomItems(base, tab: tab, tileset: tileset) }
        return base
    }

    private static func baseItems(for tab: PaletteTab) -> [PaletteItem] {
        switch tab {
        case .terrain: return terrainItems
        case .unit: return unitItems
        case .extra: return extraItems
        case .mapArt: return []
        }
    }

    private static func daysOfRuinItems(_ items: [PaletteItem], tab: PaletteTab, tileset: Tileset) -> [PaletteItem] {
        guard tab == .unit else {
            return items.filter { !$0.element.isBuilding || visibleArmies(for: tileset).contains($0.element.army) || $0.element.army == AWConstants.armyNeutral }
                .map { $0.element.isBuilding && $0.element.simplified != .buildingSilo ? $0.withLabel(buildingLabel(for: $0.element, tileset: tileset)) : $0 }
        }
        return rosterItems(daysOfRuinUnitRoster, from: items).map { item in
            daysOfRuinUnitLabel(for: item.element).map { item.withLabel($0) } ?? item
        }
    }

    private static func gameBoyItems(_ items: [PaletteItem], tab: PaletteTab, tileset: Tileset) -> [PaletteItem] {
        guard tab == .unit else { return gameBoyTerrainItems(items, tileset: tileset) }
        let roster = tileset == .gbWars ? gbWars1UnitRoster : gbWarsSharedUnitRoster
        return rosterItems(roster, from: items).map { item in
            gbWarsUnitLabel(for: item.element, tileset: tileset).map { item.withLabel($0) } ?? item
        }
    }

    private static func famicomItems(_ items: [PaletteItem], tab: PaletteTab, tileset: Tileset) -> [PaletteItem] {
        if tab == .unit {
            return rosterItems(famicomWarsUnitRoster, from: items).map { item in
                famicomWarsUnitLabel(for: item.element).map { item.withLabel($0) } ?? item
            }
        }
        return items.filter { item in
            guard !item.element.isBuilding || visibleArmies(for: tileset).contains(item.element.army) || item.element.army == AWConstants.armyNeutral else { return false }
            switch item.element.simplified {
            case .terrainPlainD, .terrainSeam, .buildingSilo: return false
            case .terrainPipe, .buildingTower, .buildingLab: return tileset == .superFamicomWars
            default: return true
            }
        }.map { item in
            if tileset == .superFamicomWars, item.element.simplified == .terrainPipe { return item.withLabel("Railroad") }
            return item.element.isBuilding ? item.withLabel(buildingLabel(for: item.element, tileset: tileset)) : item
        }
    }

    private static func rosterItems(_ roster: [Element], from items: [PaletteItem]) -> [PaletteItem] {
        let deleteItem = items.first(where: { $0.element == .unitDelete })
        return [deleteItem].compactMap { $0 } + roster.compactMap { role in
            items.first(where: { $0.element.simplified == role.simplified })
        }
    }

    private static func gameBoyTerrainItems(_ items: [PaletteItem], tileset: Tileset) -> [PaletteItem] {
        let hiddenBuildings: Set<Element> = [.buildingSilo, .buildingTower, .buildingLab, .buildingHQ]
        let hiddenTerrain: Set<Element> = [.terrainPlainD, .terrainReef, .terrainPipe, .terrainSeam]
        return items.filter { item in
            guard item.tab == .terrain else { return true }
            if item.element.isBuilding {
                return !hiddenBuildings.contains(item.element.simplified) &&
                    (visibleArmies(for: tileset).contains(item.element.army) || item.element.army == AWConstants.armyNeutral)
            }
            return !hiddenTerrain.contains(item.element.simplified)
        }.map { item in
            item.element.isBuilding ? item.withLabel(buildingLabel(for: item.element, tileset: tileset)) : item
        }
    }

    static func label(for element: Element, tileset: Tileset? = nil) -> String {
        if element == .unitEmpty { return "Empty Unit" }

        if let tileset,
           tileset.isGameBoyWarsFamily,
           let label = gbWarsUnitLabel(for: element, tileset: tileset) {
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

    /// Original GB Wars cartridge order, mapped into the editor's stable unit
    /// slots. Playtest support remains intentionally separate from authoring.
    private static let gbWars1UnitRoster: [Element] = [
        .unitInfantry,
        .unitMech,
        .unitMDTank,
        .unitTank,
        .unitMegaTank,
        .unitRocket,
        .unitArtillery,
        .unitMissile,
        .unitAntiAir,
        .unitPipeRunner,
        .unitAPC,
        .unitRecon,
        .unitFighter,
        .unitStealth,
        .unitBomber,
        .unitBCopter,
        .unitTCopter,
        .unitBattleship,
        .unitCruiser,
        .unitLander,
        .unitSub,
        .unitNeoTank,
        .unitBlackBomb,
        .unitCarrier
    ]

    private static let gbWarsSharedUnitRoster: [Element] = [
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

    private static func gbWarsUnitLabel(for element: Element, tileset: Tileset) -> String? {
        let labels = tileset == .gbWars ? gbWars1Labels : gbWarsLaterLabels
        return labels[element.simplified.value]
    }

    private static let gbWars1Labels: [Int: String] = [
        Element.unitInfantry.simplified.value: "Infantry",
        Element.unitMech.simplified.value: "Combat Engineer",
        Element.unitMDTank.simplified.value: "Tank A",
        Element.unitTank.simplified.value: "Tank B",
        Element.unitMegaTank.simplified.value: "Gun Battery",
        Element.unitRocket.simplified.value: "Self-Propelled Gun A",
        Element.unitArtillery.simplified.value: "Self-Propelled Gun B",
        Element.unitMissile.simplified.value: "Anti-Air Missile",
        Element.unitAntiAir.simplified.value: "Anti-Air Tank",
        Element.unitPipeRunner.simplified.value: "Rocket Launcher",
        Element.unitAPC.simplified.value: "Armored Car",
        Element.unitRecon.simplified.value: "Supply Transport",
        Element.unitFighter.simplified.value: "Fighter A",
        Element.unitStealth.simplified.value: "Fighter B",
        Element.unitBomber.simplified.value: "Bomber",
        Element.unitBCopter.simplified.value: "Attack Helicopter",
        Element.unitTCopter.simplified.value: "Transport Helicopter",
        Element.unitBattleship.simplified.value: "Battleship",
        Element.unitCruiser.simplified.value: "Carrier",
        Element.unitLander.simplified.value: "Transport Ship",
        Element.unitSub.simplified.value: "Submarine",
        Element.unitNeoTank.simplified.value: "Tank Z",
        Element.unitBlackBomb.simplified.value: "Super Missile",
        Element.unitCarrier.simplified.value: "Radar Transport"
    ]

    private static let gbWarsLaterLabels: [Int: String] = [
        Element.unitRecon.simplified.value: "Combat Buggy",
        Element.unitRocket.simplified.value: "Rocket Launcher",
        Element.unitAntiAir.simplified.value: "Anti-Air",
        Element.unitTCopter.simplified.value: "Transport Plane",
        Element.unitBCopter.simplified.value: "Copter",
        Element.unitBattleship.simplified.value: "Aegis Warship"
    ]

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

    static var terrainItems: [PaletteItem] { PaletteCatalogItems.terrain }

    static var unitItems: [PaletteItem] { PaletteCatalogItems.unit }

    static var extraItems: [PaletteItem] { PaletteCatalogItems.extra }

    static func armyName(_ army: Int, tileset: Tileset? = nil) -> String {
        if tileset == .daysOfRuin { return daysOfRuinArmyNames[army] ?? "Unavailable" }
        if tileset == .famicomWars || tileset == .superFamicomWars {
            let names = tileset == .famicomWars ? famicomArmyNames : superFamicomArmyNames
            return names[army] ?? "Unavailable"
        }
        if tileset?.isGameBoyWarsFamily == true, let name = gameBoyArmyNames[army] { return name }
        return standardArmyNames[army] ?? "Neutral"
    }

    private static let daysOfRuinArmyNames: [Int: String] = [
        AWConstants.armyOrangeStar: "12th Battalion",
        AWConstants.armyBlueMoon: "Lazuria",
        AWConstants.armyYellowComet: "New Rubinelle Army",
        AWConstants.armyBlackHole: "Intelligence Defense Systems",
        AWConstants.armyNeutral: "Neutral"
    ]

    private static let famicomArmyNames: [Int: String] = [
        AWConstants.armyOrangeStar: "Red Star",
        AWConstants.armyBlueMoon: "White Moon",
        AWConstants.armyNeutral: "Neutral"
    ]

    private static let superFamicomArmyNames: [Int: String] = [
        AWConstants.armyOrangeStar: "Red Star",
        AWConstants.armyBlueMoon: "White Moon",
        AWConstants.armyGreenEarth: "Green Soil",
        AWConstants.armyYellowComet: "Yellow Comet",
        AWConstants.armyNeutral: "Neutral"
    ]

    private static let gameBoyArmyNames: [Int: String] = [
        AWConstants.armyOrangeStar: "Red Star",
        AWConstants.armyBlueMoon: "White Moon"
    ]

    private static let standardArmyNames: [Int: String] = [
        AWConstants.armyOrangeStar: "Orange Star",
        AWConstants.armyBlueMoon: "Blue Moon",
        AWConstants.armyGreenEarth: "Green Earth",
        AWConstants.armyYellowComet: "Gold Comet",
        AWConstants.armyBlackHole: "Black Hole"
    ]

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
