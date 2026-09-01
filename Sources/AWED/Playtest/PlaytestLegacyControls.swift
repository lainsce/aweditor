import AppKit
import SwiftUI
import AWEDCore


enum PlaytestLegacyKey: Equatable, Sendable {
    case up
    case down
    case left
    case right
    case a
    case b
    case select

    var isButton: Bool {
        switch self {
        case .a, .b, .select: true
        case .up, .down, .left, .right: false
        }
    }
}

enum PlaytestLegacyMenuMode: Equatable {
    case closed
    case commands
    case build
}

enum PlaytestLegacyTarget: Equatable {
    case resupply
}

enum PlaytestLegacyAction: String, Hashable, Identifiable {
    case build
    case stat
    case move
    case attack
    case capture
    case load
    case unload
    case join
    case resupply
    case surface
    case stealth
    case detonate
    case flare
    case silo
    case wait
    case endTurn
    case surrender

    var id: String { rawValue }
}

@MainActor
enum PlaytestLegacyActionCatalog {
    static func actions(for session: PlaytestSession) -> [PlaytestLegacyAction] {
        var actions: [PlaytestLegacyAction] = []
        // Build only belongs in the list while a selected, empty property has
        // a production roster. Stat likewise requires a selected unit or
        // property; neither command is useful on an unselected map tile.
        if session.selectedBuildingName != nil, !session.productionOptions.isEmpty {
            actions.append(.build)
        }
        if session.selectedUnitName != nil || session.selectedBuildingName != nil {
            actions.append(.stat)
        }
        if !session.reachableCells.isEmpty { actions.append(.move) }
        if !session.attackableCells.isEmpty { actions.append(.attack) }
        if !session.captureableCells.isEmpty { actions.append(.capture) }
        if !session.loadableCells.isEmpty { actions.append(.load) }
        if !session.unloadableCells.isEmpty { actions.append(.unload) }
        if !session.joinableCells.isEmpty { actions.append(.join) }
        if session.selectedTransportCanResupply { actions.append(.resupply) }
        if session.selectedUnitCanToggleDepth { actions.append(.surface) }
        if session.selectedUnitCanToggleStealth { actions.append(.stealth) }
        if session.selectedUnitCanDetonateBlackBomb { actions.append(.detonate) }
        if session.selectedUnitCanUseFlare { actions.append(.flare) }
        if session.selectedUnitCanLaunchSilo { actions.append(.silo) }
        if session.selectedUnitCanWait { actions.append(.wait) }
        actions.append(.endTurn)
        actions.append(.surrender)
        return actions
    }

    static func title(for action: PlaytestLegacyAction, session: PlaytestSession) -> String {
        switch action {
        case .surface: session.selectedSubmarineIsSubmerged ? "SURFACE" : "DIVE"
        case .stealth: session.selectedStealthIsCloaked ? "UNCLOAK" : "CLOAK"
        default: simpleTitle(for: action)
        }
    }

    private static func simpleTitle(for action: PlaytestLegacyAction) -> String {
        switch action {
        case .build: "BUILD"
        case .stat: "STAT"
        case .move: "MOVE"
        case .attack: "ATTACK"
        case .capture: "CAPTURE"
        case .load: "LOAD"
        case .unload: "UNLOAD"
        case .join: "JOIN"
        case .resupply: "SUPPLY"
        case .detonate: "DETONATE"
        case .flare: "FLARE"
        case .silo: "SILO"
        case .wait: "WAIT"
        case .endTurn: "END TURN"
        case .surrender: "SURRENDER"
        case .surface, .stealth: ""
        }
    }

    static func isEnabled(_ action: PlaytestLegacyAction, session: PlaytestSession) -> Bool {
        switch action {
        case .build:
            // Once listed, the cartridge opens the production list even when
            // every unit is currently unaffordable. Individual entries show
            // their disabled state.
            session.selectedBuildingName != nil && !session.productionOptions.isEmpty
        case .stat: true
        case .move, .attack, .capture, .load, .unload, .join: cellActionIsEnabled(action, session: session)
        case .resupply: session.selectedTransportCanResupply
        case .surface, .stealth, .detonate, .flare, .silo, .wait: unitActionIsEnabled(action, session: session)
        case .endTurn, .surrender: turnActionIsEnabled(session)
        }
    }

    private static func cellActionIsEnabled(_ action: PlaytestLegacyAction, session: PlaytestSession) -> Bool {
        switch action {
        case .move: return !session.reachableCells.isEmpty
        case .attack: return !session.attackableCells.isEmpty
        case .capture: return !session.captureableCells.isEmpty
        case .load: return !session.loadableCells.isEmpty
        case .unload: return !session.unloadableCells.isEmpty
        case .join: return !session.joinableCells.isEmpty
        default: return false
        }
    }

    private static func unitActionIsEnabled(_ action: PlaytestLegacyAction, session: PlaytestSession) -> Bool {
        switch action {
        case .surface: return session.selectedUnitCanToggleDepth
        case .stealth: return session.selectedUnitCanToggleStealth
        case .detonate: return session.selectedUnitCanDetonateBlackBomb
        case .flare: return session.selectedUnitCanUseFlare
        case .silo: return session.selectedUnitCanLaunchSilo
        case .wait: return session.selectedUnitCanWait
        default: return false
        }
    }

    private static func turnActionIsEnabled(_ session: PlaytestSession) -> Bool {
        !session.isGameOver && !session.activeArmyIsCPU && !session.isPlayerMovementAnimating
    }
}

/// Owns the legacy key path as a first responder. A guarded local monitor is
/// retained only as a fallback for the short periods when SwiftUI gives focus
/// to a rail button or dismisses the setup sheet. The two paths are mutually
/// exclusive, so one physical key can never move/activate twice.
