import AWEDCore

struct MapStatusCounts: Sendable {
    let values: [[Int]]
    let unitCounts: [Int]
    let pipeSeams: Int
    let silos: Int
    let totalProperties: Int

    init(map: MapState) {
        let buildingTypes: [Element] = [.buildingCity, .buildingBase, .buildingPort, .buildingAirport, .buildingTower]
        values = buildingTypes.map { building in
            (0...AWConstants.armyNeutral).map { army in
                map.background.count { $0 == building.changedArmy(army) }
            }
        }
        unitCounts = (0..<AWConstants.playableArmies).map { army in
            map.foreground.count { $0.isUnitNonEmpty && $0.army == army }
        }
        pipeSeams = map.background.count { $0.simplified == .terrainSeam }
        silos = map.background.count { $0.simplified == .buildingSilo }
        totalProperties = map.countBuildingsAndSeams()
    }
}
