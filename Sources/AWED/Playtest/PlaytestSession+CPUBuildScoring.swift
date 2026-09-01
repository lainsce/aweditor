import AppKit
import Observation
import SwiftUI
import AWEDCore

extension PlaytestSession {
    func famicomBuildRoleScore(
        type: Element,
        captureNeed: Int,
        captureUnits: Int,
        infantryCount: Int,
        enemyPropertyCount: Int,
        landThreat: Double,
        airThreat: Double
    ) -> Double {
        let openingCaptureTarget = min(5, max(3, enemyPropertyCount / 3))
        switch type {
        case .unitInfantry:
            guard captureNeed > 0 else { return -65 }
            return 95 + min(60, Double(captureNeed) * 13) - Double(infantryCount) * 4
        case .unitTank:
            guard captureUnits >= openingCaptureTarget else { return -35 }
            return 76 + min(30, landThreat * 4)
        case .unitMech:
            return captureNeed > 0 && captureUnits < openingCaptureTarget ? 25 : -30
        case .unitAPC:
            return captureUnits >= openingCaptureTarget ? 18 : -15
        case .unitArtillery:
            return captureUnits >= openingCaptureTarget + 1 ? 18 + min(24, landThreat * 3) : -28
        case .unitRocket, .unitMissile, .unitMDTank:
            return captureUnits >= openingCaptureTarget + 2 ? 12 + min(24, landThreat * 3) : -45
        case .unitAntiAir:
            return airThreat > 0 ? 30 + min(30, airThreat * 8) : -20
        case .unitRecon:
            return 12
        default:
            return 0
        }
    }

    func genericBuildRoleScore(
        type: Element,
        captureNeed: Int,
        captureUnits: Int,
        landThreat: Double,
        airThreat: Double,
        seaThreat: Double,
        policy: PlaytestRulebook.CPUPolicy,
        stats: PlaytestUnitStats
    ) -> Double {
        switch type {
        case .unitInfantry, .unitMech, .unitAPC, .unitRecon, .unitTank,
             .unitMDTank, .unitNeoTank, .unitMegaTank, .unitArtillery, .unitRocket:
            return genericLandBuildRoleScore(type: type, captureNeed: captureNeed, captureUnits: captureUnits, landThreat: landThreat, policy: policy)
        case .unitMissile, .unitAntiAir, .unitTCopter, .unitBCopter, .unitFighter,
             .unitBomber, .unitStealth, .unitBlackBomb:
            return genericAirBuildRoleScore(type: type, captureNeed: captureNeed, landThreat: landThreat, airThreat: airThreat)
        case .unitLander, .unitBlackBoat, .unitCruiser, .unitSub, .unitBattleship, .unitCarrier:
            return genericSeaBuildRoleScore(type: type, captureNeed: captureNeed, landThreat: landThreat, airThreat: airThreat, seaThreat: seaThreat)
        default:
            return Double(stats.attackPower) / 6
        }
    }

    func genericLandBuildRoleScore(
        type: Element,
        captureNeed: Int,
        captureUnits: Int,
        landThreat: Double,
        policy: PlaytestRulebook.CPUPolicy
    ) -> Double {
        switch type {
        case .unitInfantry:
            return captureNeed > 0
                ? min(60, 24 + Double(captureNeed) * 10) * policy.captureUnitBuildMultiplier
                : -55 - policy.infantryRepeatPenalty * 0.5
        case .unitMech:
            return (captureNeed > 0 ? 30 + min(18, Double(captureNeed) * 5) : -8)
                * policy.captureUnitBuildMultiplier + min(24, landThreat * 4)
        case .unitAPC:
            return captureUnits > 0 ? 28 : 12
        case .unitRecon:
            return 18 + min(24, landThreat * 4)
        case .unitTank:
            return 28 + min(32, landThreat * 5)
        case .unitMDTank, .unitNeoTank, .unitMegaTank:
            return 24 + min(38, landThreat * 5)
        case .unitArtillery:
            return 24 + min(42, landThreat * 7)
        case .unitRocket:
            return 18 + min(42, landThreat * 7)
        default:
            return 0
        }
    }

    func genericAirBuildRoleScore(
        type: Element,
        captureNeed: Int,
        landThreat: Double,
        airThreat: Double
    ) -> Double {
        switch type {
        case .unitMissile:
            return 10 + min(56, airThreat * 22)
        case .unitAntiAir:
            return 10 + min(72, airThreat * 28)
        case .unitTCopter:
            return 12 + (captureNeed > 0 ? 22 : 0)
        case .unitBCopter:
            return 18 + min(42, landThreat * 6) + min(24, airThreat * 8)
        case .unitFighter:
            return 12 + min(78, airThreat * 30)
        case .unitBomber:
            return 22 + min(62, landThreat * 12)
        case .unitStealth, .unitBlackBomb:
            return 18 + min(42, landThreat * 8) + min(20, airThreat * 6)
        default:
            return 0
        }
    }

    func genericSeaBuildRoleScore(
        type: Element,
        captureNeed: Int,
        landThreat: Double,
        airThreat: Double,
        seaThreat: Double
    ) -> Double {
        switch type {
        case .unitLander:
            return 8 + (captureNeed > 0 ? 24 : 0)
        case .unitBlackBoat:
            return 12 + min(42, landThreat * 7)
        case .unitCruiser:
            return 16 + min(54, airThreat * 16 + seaThreat * 8)
        case .unitSub:
            return 18 + min(64, seaThreat * 20)
        case .unitBattleship:
            return 22 + min(72, landThreat * 12 + seaThreat * 5)
        case .unitCarrier:
            return 15 + min(36, airThreat * 10 + seaThreat * 4)
        default:
            return 0
        }
    }
}
