import AWEDCore

// Era-specific CPU profiles live outside the ruleset dispatcher so the
// selection logic remains small and each profile can be tuned independently.
extension PlaytestRulebook {
    static func dualStrikeCPUPolicy() -> CPUPolicy {
        CPUPolicy(attackBias: 220, counterRiskMultiplier: 0.95, targetCostMultiplier: 1.0,
                  captureMultiplier: 1.0, captureProgressWeight: 12, hqCaptureMultiplier: 1.25,
                  productionCaptureMultiplier: 1.10, enemyPropertyMultiplier: 1.0,
                  propertyApproachMultiplier: 1.0, contactMultiplier: 1.0, threatMultiplier: 0.90,
                  transportTargetMultiplier: 1.0, loadedTransportBonus: 60,
                  transportActionMultiplier: 1.0, supplyActionMultiplier: 1.0,
                  infantryRepeatPenalty: 16, captureUnitBuildMultiplier: 1.0,
                  buildDiversityPenalty: 10, indirectAttackMultiplier: 1.0, hqProductionRadius: nil)
    }

    static func advanceWarsCPUPolicy() -> CPUPolicy {
        CPUPolicy(attackBias: 235, counterRiskMultiplier: 0.78, targetCostMultiplier: 1.0,
                  captureMultiplier: 1.05, captureProgressWeight: 14, hqCaptureMultiplier: 1.35,
                  productionCaptureMultiplier: 1.20, enemyPropertyMultiplier: 1.05,
                  propertyApproachMultiplier: 1.10, contactMultiplier: 1.10, threatMultiplier: 0.75,
                  transportTargetMultiplier: 1.70, loadedTransportBonus: 80,
                  transportActionMultiplier: 1.0, supplyActionMultiplier: 1.0,
                  infantryRepeatPenalty: 20, captureUnitBuildMultiplier: 1.05,
                  buildDiversityPenalty: 11, indirectAttackMultiplier: 0.95, hqProductionRadius: nil)
    }

    static func advanceWars2CPUPolicy() -> CPUPolicy {
        CPUPolicy(attackBias: 228, counterRiskMultiplier: 0.90, targetCostMultiplier: 1.0,
                  captureMultiplier: 1.10, captureProgressWeight: 15, hqCaptureMultiplier: 1.45,
                  productionCaptureMultiplier: 1.25, enemyPropertyMultiplier: 1.10,
                  propertyApproachMultiplier: 1.08, contactMultiplier: 1.05, threatMultiplier: 0.80,
                  transportTargetMultiplier: 1.10, loadedTransportBonus: 170,
                  transportActionMultiplier: 1.10, supplyActionMultiplier: 1.0,
                  infantryRepeatPenalty: 20, captureUnitBuildMultiplier: 1.05,
                  buildDiversityPenalty: 11, indirectAttackMultiplier: 1.0, hqProductionRadius: nil)
    }

    static func famicomWarsCPUPolicy() -> CPUPolicy {
        CPUPolicy(attackBias: 245, counterRiskMultiplier: 0.70, targetCostMultiplier: 1.0,
                  captureMultiplier: 1.15, captureProgressWeight: 16, hqCaptureMultiplier: 1.40,
                  productionCaptureMultiplier: 1.30, enemyPropertyMultiplier: 1.10,
                  propertyApproachMultiplier: 1.22, contactMultiplier: 1.15, threatMultiplier: 0.60,
                  transportTargetMultiplier: 1.0, loadedTransportBonus: 40,
                  transportActionMultiplier: 1.15, supplyActionMultiplier: 1.10,
                  infantryRepeatPenalty: 22, captureUnitBuildMultiplier: 1.05,
                  buildDiversityPenalty: 10, indirectAttackMultiplier: 1.0, hqProductionRadius: 2)
    }

    static func superFamicomWarsCPUPolicy() -> CPUPolicy {
        CPUPolicy(attackBias: 255, counterRiskMultiplier: 0.60, targetCostMultiplier: 1.0,
                  captureMultiplier: 1.12, captureProgressWeight: 16, hqCaptureMultiplier: 1.45,
                  productionCaptureMultiplier: 1.30, enemyPropertyMultiplier: 1.10,
                  propertyApproachMultiplier: 1.25, contactMultiplier: 1.20, threatMultiplier: 0.45,
                  transportTargetMultiplier: 1.0, loadedTransportBonus: 40,
                  transportActionMultiplier: 1.20, supplyActionMultiplier: 1.10,
                  infantryRepeatPenalty: 22, captureUnitBuildMultiplier: 1.0,
                  buildDiversityPenalty: 11, indirectAttackMultiplier: 1.15, hqProductionRadius: 2)
    }

    static func gameBoyWarsCPUPolicy() -> CPUPolicy {
        CPUPolicy(attackBias: 215, counterRiskMultiplier: 0.90, targetCostMultiplier: 1.0,
                  captureMultiplier: 1.0, captureProgressWeight: 12, hqCaptureMultiplier: 1.20,
                  productionCaptureMultiplier: 1.10, enemyPropertyMultiplier: 1.0,
                  propertyApproachMultiplier: 0.95, contactMultiplier: 0.95, threatMultiplier: 0.95,
                  transportTargetMultiplier: 0.90, loadedTransportBonus: 30,
                  transportActionMultiplier: 0.90, supplyActionMultiplier: 0.90,
                  infantryRepeatPenalty: 24, captureUnitBuildMultiplier: 0.95,
                  buildDiversityPenalty: 9, indirectAttackMultiplier: 0.90, hqProductionRadius: nil)
    }

    static func gameBoyWars2CPUPolicy() -> CPUPolicy {
        CPUPolicy(attackBias: 220, counterRiskMultiplier: 0.82, targetCostMultiplier: 1.0,
                  captureMultiplier: 1.05, captureProgressWeight: 13, hqCaptureMultiplier: 1.30,
                  productionCaptureMultiplier: 1.15, enemyPropertyMultiplier: 1.0,
                  propertyApproachMultiplier: 1.0, contactMultiplier: 1.0, threatMultiplier: 0.85,
                  transportTargetMultiplier: 1.0, loadedTransportBonus: 55,
                  transportActionMultiplier: 1.0, supplyActionMultiplier: 0.95,
                  infantryRepeatPenalty: 22, captureUnitBuildMultiplier: 1.0,
                  buildDiversityPenalty: 10, indirectAttackMultiplier: 0.95, hqProductionRadius: nil)
    }

    static func gameBoyWars3CPUPolicy() -> CPUPolicy {
        CPUPolicy(attackBias: 230, counterRiskMultiplier: 0.78, targetCostMultiplier: 1.0,
                  captureMultiplier: 1.10, captureProgressWeight: 14, hqCaptureMultiplier: 1.35,
                  productionCaptureMultiplier: 1.20, enemyPropertyMultiplier: 1.05,
                  propertyApproachMultiplier: 1.08, contactMultiplier: 1.05, threatMultiplier: 0.75,
                  transportTargetMultiplier: 1.0, loadedTransportBonus: 70,
                  transportActionMultiplier: 1.05, supplyActionMultiplier: 1.0,
                  infantryRepeatPenalty: 24, captureUnitBuildMultiplier: 1.0,
                  buildDiversityPenalty: 12, indirectAttackMultiplier: 1.0, hqProductionRadius: nil)
    }

    static func daysOfRuinCPUPolicy() -> CPUPolicy {
        CPUPolicy(attackBias: 240, counterRiskMultiplier: 0.75, targetCostMultiplier: 1.0,
                  captureMultiplier: 1.15, captureProgressWeight: 16, hqCaptureMultiplier: 1.45,
                  productionCaptureMultiplier: 1.25, enemyPropertyMultiplier: 1.10,
                  propertyApproachMultiplier: 1.12, contactMultiplier: 1.10, threatMultiplier: 0.70,
                  transportTargetMultiplier: 1.15, loadedTransportBonus: 90,
                  transportActionMultiplier: 1.10, supplyActionMultiplier: 1.05,
                  infantryRepeatPenalty: 20, captureUnitBuildMultiplier: 1.05,
                  buildDiversityPenalty: 12, indirectAttackMultiplier: 1.10, hqProductionRadius: nil)
    }
}
