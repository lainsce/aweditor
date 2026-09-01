import Foundation

public extension MapState {
    func allowPlacement(_ element: Element, atX x: Int, y: Int, recheck: Bool = false) -> Bool {
            if element.isForeground {
                if (!recheck && element == foregroundElement(atX: x, y: y)) || element == .unitEmpty { return true }
            }
            if element.isBackground, !recheck, element == backgroundElement(atX: x, y: y) { return true }

            if element.isTerrain { return allowTerrainPlacement(element, atX: x, y: y) }
            if element.isBuilding { return allowBuildingPlacement(element) }
            if element.isUnit { return allowUnitPlacement(element, atX: x, y: y) }
            if element.isExtra { return allowExtraPlacement(element, atX: x, y: y) }
            return false
        }

        private func allowTerrainPlacement(_ element: Element, atX x: Int, y: Int) -> Bool {
            switch element.simplified.value {
            case Element.terrainPlain.value, Element.terrainPlainD.value, Element.terrainWood.value,
                 Element.terrainMountain.value, Element.terrainRoad.value, Element.terrainPipe.value,
                 Element.terrainSea.value:
                return true
            case AWConstants.terrainBlank:
                return false
            case Element.terrainRiver.value:
                return allowRiverPlacement(atX: x, y: y)
            case Element.terrainBridgeH.value:
                return allowBridgePlacement(atX: x, y: y)
            case Element.terrainReef.value:
                return backgroundElement(atX: x, y: y).isSea
            case Element.terrainShoal.value:
                return allowShoalPlacement(atX: x, y: y)
            case Element.terrainSeam.value:
                return allowSeamPlacement(atX: x, y: y)
            default:
                return false
            }
        }

        private func allowRiverPlacement(atX x: Int, y: Int) -> Bool {
            let corners = [
                ((-1, 0), (-1, -1), (0, -1)),
                ((0, -1), (1, -1), (1, 0)),
                ((1, 0), (1, 1), (0, 1)),
                ((0, 1), (-1, 1), (-1, 0))
            ]
            return !corners.contains { closedRiverCorner(atX: x, y: y, offsets: $0) }
        }

        private func closedRiverCorner(
            atX x: Int,
            y: Int,
            offsets: ((Int, Int), (Int, Int), (Int, Int))
        ) -> Bool {
            let elements = [
                backgroundElement(atX: x + offsets.0.0, y: y + offsets.0.1),
                backgroundElement(atX: x + offsets.1.0, y: y + offsets.1.1),
                backgroundElement(atX: x + offsets.2.0, y: y + offsets.2.1)
            ]
            return elements.allSatisfy(\.isRiver)
        }

        private func allowBridgePlacement(atX x: Int, y: Int) -> Bool {
            let current = backgroundElement(atX: x, y: y)
            if current.simplified == .terrainRiver { return true }
            guard current.isSea else { return false }
            let neighbours = cardinalNeighbours(atX: x, y: y)
            guard !hasAdjacentLandPair(neighbours) else { return false }
            return neighbours.contains(where: \.isLand) ||
                neighbours.contains(.terrainBridgeH) || neighbours.contains(.terrainBridgeV)
        }

        private func cardinalNeighbours(atX x: Int, y: Int) -> [Element] {
            [
                backgroundElement(atX: x, y: y - 1),
                backgroundElement(atX: x, y: y + 1),
                backgroundElement(atX: x - 1, y: y),
                backgroundElement(atX: x + 1, y: y)
            ]
        }

        private func hasAdjacentLandPair(_ neighbours: [Element]) -> Bool {
            let pairs = [(0, 1), (1, 2), (2, 3), (3, 0)]
            return pairs.contains { neighbours[$0.0].isLand && neighbours[$0.1].isLand }
        }

        private func allowShoalPlacement(atX x: Int, y: Int) -> Bool {
            let neighbours = cardinalNeighbours(atX: x, y: y)
            if neighbours.allSatisfy(\.isSea) || neighbours.allSatisfy(\.isLand) { return false }
            if invalidShoalAxis(neighbours) { return false }
            return !hasInvalidShoalDiagonal(atX: x, y: y, neighbours: neighbours)
        }

        private func invalidShoalAxis(_ neighbours: [Element]) -> Bool {
            let verticalSea = neighbours[0].isSea && neighbours[1].isSea
            let horizontalSea = neighbours[2].isSea && neighbours[3].isSea
            let verticalLand = neighbours[0].isLand && neighbours[1].isLand
            let horizontalLand = neighbours[2].isLand && neighbours[3].isLand
            return horizontalLand && verticalSea || horizontalSea && verticalLand
        }

        private func hasInvalidShoalDiagonal(atX x: Int, y: Int, neighbours: [Element]) -> Bool {
            let diagonals = [
                (x - 1, y - 1, neighbours[2], neighbours[0]),
                (x + 1, y - 1, neighbours[3], neighbours[0]),
                (x + 1, y + 1, neighbours[3], neighbours[1]),
                (x - 1, y + 1, neighbours[2], neighbours[1])
            ]
            return diagonals.contains {
                backgroundElement(atX: $0.0, y: $0.1).isLand && $0.2.isSea && $0.3.isSea
            }
        }

        private func allowSeamPlacement(atX x: Int, y: Int) -> Bool {
            let current = backgroundElement(atX: x, y: y)
            guard current.isPipe || current.simplified == .terrainPlainD else { return false }
            let neighbours = cardinalNeighbours(atX: x, y: y)
            if neighbours.allSatisfy({ !$0.isPipe }) { return true }
            return hasPipePair(neighbours)
        }

        private func hasPipePair(_ neighbours: [Element]) -> Bool {
            let horizontal = neighbours[2].simplified == .terrainPipe && neighbours[3].simplified == .terrainPipe
            let vertical = neighbours[0].simplified == .terrainPipe && neighbours[1].simplified == .terrainPipe
            return horizontal || vertical
        }

        private func allowBuildingPlacement(_ element: Element) -> Bool {
            !(element.simplified == .buildingHQ && element.army == AWConstants.armyNeutral)
        }

        private func allowUnitPlacement(_ element: Element, atX x: Int, y: Int) -> Bool {
            let underlying = backgroundElement(atX: x, y: y)
            if underlying.isExtra { return false }
            if underlying == .terrainBlank { return true }
            let base = underlying.simplified
            let railroad = tileset == .superFamicomWars && base == .terrainPipe
            switch element.simplified.value {
            case Element.unitInfantry.value, Element.unitMech.value:
                return railroad || base.isBuilding || [.terrainPlain, .terrainPlainD, .terrainWood, .terrainMountain, .terrainRoad, .terrainBridgeH, .terrainRiver, .terrainShoal].contains(base)
            case Element.unitTank.value, Element.unitMDTank.value, Element.unitNeoTank.value, Element.unitMegaTank.value,
                 Element.unitRecon.value, Element.unitAntiAir.value, Element.unitMissile.value, Element.unitArtillery.value,
                 Element.unitRocket.value, Element.unitAPC.value, Element.unitOozium.value:
                return railroad || base.isBuilding || [.terrainPlain, .terrainPlainD, .terrainWood, .terrainRoad, .terrainBridgeH, .terrainShoal].contains(base)
            case Element.unitPipeRunner.value:
                return [.terrainPipe, .terrainSeam, .buildingBase].contains(base)
            case Element.unitBlackBoat.value, Element.unitLander.value:
                return [.terrainShoal, .terrainSea, .terrainReef, .buildingPort].contains(base)
            case Element.unitCruiser.value, Element.unitSub.value, Element.unitBattleship.value, Element.unitCarrier.value:
                return [.terrainSea, .terrainReef, .buildingPort].contains(base)
            case Element.unitTCopter.value, Element.unitBCopter.value, Element.unitFighter.value, Element.unitBomber.value,
                 Element.unitStealth.value, Element.unitBlackBomb.value:
                return railroad || (base != .terrainPipe && base != .terrainSeam)
            default:
                return element == .unitEmpty
            }
        }

        private func allowExtraPlacement(_ element: Element, atX x: Int, y: Int) -> Bool {
            switch element.simplified.value {
            case Element.extraMCannonN.value, Element.extraMCannonS.value, Element.extraMCannonW.value,
                 Element.extraMCannonE.value, Element.extraLCannon.value, Element.extraBCrystal.value:
                return true
            case Element.extraBCannonN.value, Element.extraBCannons.value, Element.extraDeathray.value, Element.extraBobelisk.value:
                return element != element.simplified || (x >= 1 && y >= 1 && x <= width - 2 && y <= height - 2)
            case Element.extraSeaArc.value:
                return allowSeaArcPlacement(element, atX: x, y: y)
            case Element.extraVolcano.value, Element.extraFortress.value, Element.extraBlackArc.value, Element.extraGSilo.value:
                return element != element.simplified || (x >= 1 && y >= 1 && x <= width - 3 && y <= height - 3)
            default:
                return false
            }
        }

        private func allowSeaArcPlacement(_ element: Element, atX x: Int, y: Int) -> Bool {
            let offset = element.largeOffset() ?? (1, 1)
            for dx in (-1 - offset.x)..<(5 - offset.x) {
                for dy in (-1 - offset.y)..<(5 - offset.y) {
                    if backgroundElement(atX: x + dx, y: y + dy).isLand { return false }
                }
            }
            return true
        }
}
