import AppKit
import Observation
import SwiftUI
import AWEDCore

private struct CPUPlanningSnapshotBuilder {
    var ownUnitPoints: [GridPoint] = []
    var enemyUnitPoints: [GridPoint] = []
    var enemyUnits: [PlaytestSession.CPUEnemyInfo] = []
    var ownPropertyPoints: [GridPoint] = []
    var enemyPropertyPoints: [GridPoint] = []
    var enemyHQPoints: [GridPoint] = []
    var pipeSeamPoints: [GridPoint] = []
    var ownCounts: [Int: Int] = [:]
    var ownDomains = (land: 0, air: 0, sea: 0)
    var enemyDomains = (land: 0, air: 0, sea: 0)

    mutating func addOwnUnit(_ point: GridPoint, unit: Element, stats: PlaytestUnitStats) {
        ownUnitPoints.append(point)
        ownCounts[unit.simplified.value, default: 0] += 1
        addDomain(stats.domain, to: &ownDomains)
    }

    mutating func addEnemyUnit(_ info: PlaytestSession.CPUEnemyInfo) {
        enemyUnitPoints.append(info.point)
        enemyUnits.append(info)
        addDomain(info.stats.domain, to: &enemyDomains)
    }

    private func addDomain(_ domain: PlaytestUnitDomain, to counts: inout (land: Int, air: Int, sea: Int)) {
        switch domain {
        case .land: counts.land += 1
        case .air: counts.air += 1
        case .sea: counts.sea += 1
        }
    }

    func snapshot() -> PlaytestSession.CPUPlanningSnapshot {
        PlaytestSession.CPUPlanningSnapshot(
            ownUnitPoints: ownUnitPoints,
            enemyUnitPoints: enemyUnitPoints,
            enemyUnits: enemyUnits,
            ownPropertyPoints: ownPropertyPoints,
            enemyPropertyPoints: enemyPropertyPoints,
            enemyHQPoints: enemyHQPoints,
            pipeSeamPoints: pipeSeamPoints,
            ownCounts: ownCounts,
            ownDomains: ownDomains,
            enemyDomains: enemyDomains
        )
    }
}

extension PlaytestSession {
    func runCPUIfNeeded() {
        guard !isExecutingCPU, isCPUArmy(activeArmy), !isGameOver else { return }

        isExecutingCPU = true
        let runID = UUID()
        cpuRunID = runID
        cpuTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.finishCPURun(runID: runID)
            }
            await self.runCPULoop(runID: runID)
        }
    }

    private func finishCPURun(runID: UUID) {
        guard cpuRunID == runID else { return }
        isExecutingCPU = false
        cpuTask = nil
        clearCPUMovementPreview()
        cpuMovementPathCache.removeAll(keepingCapacity: true)
    }

    private func runCPULoop(runID: UUID) async {
        var actionCount = 0
        var cpuTurnStart = DispatchTime.now().uptimeNanoseconds
        while isCPUArmy(activeArmy), !isGameOver {
            if actionCount >= 400 {
                guard await endCPUTurn(start: cpuTurnStart, runID: runID) else { return }
                cpuTurnStart = DispatchTime.now().uptimeNanoseconds
                actionCount = 0
                continue
            }

            await Task.yield()
            guard !Task.isCancelled, cpuRunID == runID else { return }
            actionCount += 1
            guard let plan = bestCPUPlan() else {
                guard await endCPUTurn(start: cpuTurnStart, runID: runID) else { return }
                cpuTurnStart = DispatchTime.now().uptimeNanoseconds
                actionCount = 0
                continue
            }

            let previousArmy = activeArmy
            let previousMoved = movedCells
            let previousSelection = selectedPoint
            guard await executeCPUTurnAction(plan, runID: runID) else { return }
            repairStaleCPUAction(previousArmy: previousArmy, moved: previousMoved, selection: previousSelection)
            let pause = activeArmy == previousArmy ? Self.cpuActionPause : Self.cpuTurnPause
            try? await Task.sleep(nanoseconds: scaledCPUDelay(pause))
            guard !Task.isCancelled, cpuRunID == runID else { return }
        }

        if isCPUArmy(activeArmy), !isGameOver {
            _ = await endCPUTurn(start: cpuTurnStart, runID: runID)
        }
    }

    private func endCPUTurn(start: UInt64, runID: UUID) async -> Bool {
        clearCPUMovementPreview()
        guard await waitForMinimumCPUTurn(start: start, runID: runID) else { return false }
        endTurn()
        try? await Task.sleep(nanoseconds: scaledCPUDelay(Self.cpuTurnPause))
        return !Task.isCancelled && cpuRunID == runID
    }

    private func executeCPUTurnAction(_ plan: CPUPlan, runID: UUID) async -> Bool {
        prepareCPUMovementPreview(for: plan.action)
        // Yield to SwiftUI so the current enemy unit's marker is visible before the CPU commits its action.
        try? await Task.sleep(nanoseconds: scaledCPUDelay(Self.cpuActionPreviewDelay))
        guard !Task.isCancelled, cpuRunID == runID else { return false }
        await executeCPU(plan.action)
        clearCPUMovementPreview()
        return true
    }

    private func repairStaleCPUAction(previousArmy: Int, moved: Set<GridPoint>, selection: GridPoint?) {
        guard activeArmy == previousArmy, movedCells == moved, selectedPoint == selection else { return }
        clearSelection()
        statusMessage = "The CPU ended an unavailable action."
    }

    /// Keeps short CPU turns readable without blocking the main actor. The
    /// task's cancellation is checked both while sleeping and by the caller,
    /// so closing/restarting playtest never waits out the pacing interval.
    func waitForMinimumCPUTurn(start: UInt64, runID: UUID) async -> Bool {
        let elapsed = DispatchTime.now().uptimeNanoseconds &- start
        if elapsed < cpuMinimumTurnDuration {
            try? await Task.sleep(nanoseconds: cpuMinimumTurnDuration - elapsed)
        }
        return !Task.isCancelled && cpuRunID == runID
    }

    func prepareCPUMovementPreview(for action: CPUAction) {
        clearCPUMovementPreview()
        cpuActionPoint = actionFocusPoint(for: action)
        // The cartridge cursor is the CPU's visible hand. Put it on the
        // action's focus before the preview pause so captures, attacks,
        // production, and movement all read as deliberate cursor actions.
        cursorPoint = cpuActionPoint

        guard case let .move(origin, _) = action,
              let unit = unit(at: origin),
              unit.army == activeArmy,
              PlaytestRulebook.stats(for: unit, ruleset: ruleset) != nil,
              !movedCells.contains(origin) else { return }

        cpuMovementPath = [origin]
    }

    func actionFocusPoint(for action: CPUAction) -> GridPoint {
        switch action {
        case let .attack(_, target), let .capture(target), let .build(target, _),
             let .resupply(target), let .detonate(target), let .flare(target),
             let .stealth(target), let .wait(target):
            return target
        case let .move(origin, _), let .join(origin, _), let .load(origin, _),
             let .unload(origin, _):
            return origin
        }
    }

    func clearCPUMovementPreview() {
        cpuMovementPath.removeAll(keepingCapacity: true)
        cpuMovementAnimation = nil
    }

    func makeCPUPlanningSnapshot() -> CPUPlanningSnapshot {
        var builder = CPUPlanningSnapshotBuilder()
        for point in allMapPoints() {
            appendCPUPlanningUnit(at: point, to: &builder)
            appendCPUPlanningBuilding(at: point, to: &builder)
            if isPipeSeam(at: point) { builder.pipeSeamPoints.append(point) }
        }
        return builder.snapshot()
    }

    private func appendCPUPlanningUnit(at point: GridPoint, to builder: inout CPUPlanningSnapshotBuilder) {
        let unit = map.foregroundElement(atX: point.x, y: point.y)
        guard unit.isUnitNonEmpty,
              let stats = PlaytestRulebook.stats(for: unit, ruleset: ruleset) else { return }
        if unit.army == activeArmy {
            builder.addOwnUnit(point, unit: unit, stats: stats)
        } else if isHostile(unit.army, activeArmy), (!isFogOfWarActive || isVisible(point)) {
            builder.addEnemyUnit(CPUEnemyInfo(point: point, unit: unit, stats: stats))
        }
    }

    private func appendCPUPlanningBuilding(at point: GridPoint, to builder: inout CPUPlanningSnapshotBuilder) {
        let building = map.backgroundElement(atX: point.x, y: point.y)
        if building.simplified == .buildingHQ, isHostile(building.army, activeArmy) {
            builder.enemyHQPoints.append(point)
        }
        if building.isBuilding, building.army == activeArmy {
            builder.ownPropertyPoints.append(point)
            return
        }
        guard PlaytestRulebook.isCapturableBuilding(building, ruleset: ruleset),
              building.army == AWConstants.armyNeutral || isHostile(building.army, activeArmy),
              !isFogOfWarActive || building.army == AWConstants.armyNeutral || isVisible(point) else { return }
        builder.enemyPropertyPoints.append(point)
    }

    func bestCPUPlan() -> CPUPlan? {
        cpuPlanningSnapshot = makeCPUPlanningSnapshot()
        cpuThreatCache.removeAll(keepingCapacity: true)
        cpuMovementPathCache.removeAll(keepingCapacity: true)
        cpuAttackableCache.removeAll(keepingCapacity: true)
        cpuNearestEnemyDistanceCache.removeAll(keepingCapacity: true)
        cpuNearestEnemyPropertyDistanceCache.removeAll(keepingCapacity: true)
        cpuTransportDropOffCache.removeAll(keepingCapacity: true)
        defer {
            cpuPlanningSnapshot = nil
            cpuThreatCache.removeAll(keepingCapacity: true)
            cpuAttackableCache.removeAll(keepingCapacity: true)
            cpuNearestEnemyDistanceCache.removeAll(keepingCapacity: true)
            cpuNearestEnemyPropertyDistanceCache.removeAll(keepingCapacity: true)
            cpuTransportDropOffCache.removeAll(keepingCapacity: true)
        }

        if let followUp = cpuFollowUpPlan() { return followUp }

        var plans: [CPUPlan] = []
        plans.append(contentsOf: cpuAttackPlans())
        plans.append(contentsOf: cpuCapturePlans())
        plans.append(contentsOf: cpuTransportPlans())
        plans.append(contentsOf: cpuSpecialPlans())
        plans.append(contentsOf: cpuBuildPlans())
        plans.append(contentsOf: cpuMovePlans())
        plans.append(contentsOf: cpuWaitPlans())
        return plans.max { lhs, rhs in
            if lhs.score == rhs.score {
                return cpuActionOrder(lhs.action) < cpuActionOrder(rhs.action)
            }
            return lhs.score < rhs.score
        }
    }

    /// A moved unit stays selected long enough to resolve an available attack
    /// or capture a property it entered. Other actions remain pre-movement
    /// actions.
    func cpuFollowUpPlan() -> CPUPlan? {
        guard let point = selectedPoint,
              let unit = unit(at: point),
              unit.army == activeArmy else { return nil }
        if movedCells.contains(point) {
            return movedUnitFollowUp(at: point, unit: unit)
        }
        return idleUnitFollowUp(at: point, unit: unit)
    }

    private func movedUnitFollowUp(at point: GridPoint, unit: Element) -> CPUPlan? {
        if unit.simplified == .unitBlackBomb {
            return CPUPlan(score: 620, action: .detonate(point: point))
        }
        if ruleset == .daysOfRuin, unit.simplified == .unitOozium {
            return CPUPlan(score: 120, action: .flare(point: point))
        }
        return bestImmediateCPUPlan(at: point, fallback: CPUPlan(score: -10, action: .wait(point: point)))
    }

    private func idleUnitFollowUp(at point: GridPoint, unit: Element) -> CPUPlan? {
        if let immediatePlan = bestImmediateCPUPlan(at: point) {
            return immediatePlan
        }
        let policy = cpuPolicy
        let capacity = PlaytestRulebook.transportCapacity(for: unit, ruleset: ruleset)
        if capacity > 0, let cargoPoint = sortedGridPoints(loadableCells).first {
            return CPUPlan(score: 150 * policy.transportActionMultiplier, action: .load(transport: point, cargo: cargoPoint))
        }
        if capacity == 0, let transportPoint = sortedGridPoints(loadableCells).first {
            return CPUPlan(score: 145 * policy.transportActionMultiplier, action: .move(origin: point, destination: transportPoint))
        }
        if let destination = sortedGridPoints(unloadableCells).first {
            return CPUPlan(score: 140 * policy.transportActionMultiplier, action: .unload(transport: point, destination: destination))
        }
        if let destination = sortedGridPoints(joinableCells).first {
            return CPUPlan(score: 95, action: .join(origin: point, destination: destination))
        }
        guard !refuelableCells.isEmpty else { return nil }
        return CPUPlan(score: 90 * policy.supplyActionMultiplier, action: .resupply(point: point))
    }

    private func bestImmediateCPUPlan(at point: GridPoint, fallback: CPUPlan? = nil) -> CPUPlan? {
        let capturePlan = sortedGridPoints(captureableCells).first.map {
            CPUPlan(score: captureScore(at: $0), action: .capture(point: $0))
        }
        let attackPlan = sortedGridPoints(attackableCells).max {
            attackScore(from: point, to: $0) < attackScore(from: point, to: $1)
        }.map {
            CPUPlan(score: attackScore(from: point, to: $0), action: .attack(origin: point, target: $0))
        }
        return [capturePlan, attackPlan].compactMap { $0 }.max { $0.score < $1.score } ?? fallback
    }

    func executeCPU(_ action: CPUAction) async {
        switch action {
        case let .attack(origin, target):
            selectedPoint = origin
            attack(to: target)
        case let .capture(point):
            selectedPoint = point
            capture()
        case let .build(point, option):
            selectedPoint = point
            buildUnit(option)
        case let .move(origin, destination):
            await executeCPUMove(from: origin, to: destination)
        case let .load(transport, cargoPoint):
            selectedPoint = transport
            if let transportUnit = unit(at: transport) {
                updateTransportActions(for: transportUnit, at: transport)
            }
            loadUnit(from: cargoPoint)
        case let .unload(transport, destination):
            selectedPoint = transport
            if let transportUnit = unit(at: transport) {
                updateTransportActions(for: transportUnit, at: transport)
            }
            unloadUnit(to: destination)
        case let .join(origin, destination):
            selectedPoint = origin
            joinUnit(to: destination)
        case let .resupply(point):
            selectedPoint = point
            if let transport = unit(at: point) {
                updateTransportActions(for: transport, at: point)
            }
            resupplySelectedTransport(target: sortedGridPoints(refuelableCells).first)
        case let .detonate(point):
            selectedPoint = point
            detonateBlackBomb()
        case let .flare(point):
            selectedPoint = point
            useFlare()
        case let .stealth(point):
            selectedPoint = point
            toggleStealth()
        case let .wait(point):
            selectedPoint = point
            wait()
        }
    }

    func cpuActionOrder(_ action: CPUAction) -> Int {
        switch action {
        case .attack: 0
        case .capture: 1
        case .load, .unload, .join, .resupply, .detonate, .flare, .stealth: 2
        case .build: 3
        case .move: 4
        case .wait: 5
        }
    }

    /// Commits a CPU move one tile at a time so the unit appears to walk,
    /// tread, sail, or fly across the board instead of teleporting to the
    /// planned destination. The existing movement routine still owns all
    /// legality, fuel, cargo, and post-move-action rules.
}
