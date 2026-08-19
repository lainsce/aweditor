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
}

enum PaletteCatalog {
    static func items(for tab: PaletteTab) -> [PaletteItem] {
        switch tab {
        case .terrain: terrainItems
        case .unit: unitItems
        case .extra: extraItems
        }
    }

    static func label(for element: Element) -> String {
        if element == .unitEmpty { return "Empty Unit" }

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

    static func armyName(_ army: Int) -> String {
        switch army {
        case AWConstants.armyOrangeStar: "Orange Star"
        case AWConstants.armyBlueMoon: "Blue Moon"
        case AWConstants.armyGreenEarth: "Green Earth"
        case AWConstants.armyYellowComet: "Gold Comet"
        case AWConstants.armyBlackHole: "Black Hole"
        default: "Neutral"
        }
    }

    static func armyAbbreviation(_ army: Int) -> String {
        switch army {
        case AWConstants.armyOrangeStar: "Orange Star"
        case AWConstants.armyBlueMoon: "Blue Moon"
        case AWConstants.armyGreenEarth: "Green Earth"
        case AWConstants.armyYellowComet: "Gold Comet"
        case AWConstants.armyBlackHole: "Black Hole"
        default: "–"
        }
    }
}
