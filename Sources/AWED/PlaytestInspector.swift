import AWEDCore
import SwiftUI

struct PlaytestInspector: View {
    let session: PlaytestSession

    private var statusTheme: PlaytestStatusTheme {
        PlaytestStatusTheme(tileset: session.map.tileset)
    }

    private var hidesLegacyCommandButtons: Bool {
        session.ruleset.usesLegacyKeyboardControls
    }

    private var sortedRefuelableCells: [GridPoint] {
        session.refuelableCells.sorted {
            $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let selectedUnitName = session.selectedUnitName {
                        PlaytestStatusPanel(
                            "Unit status",
                            tileset: session.map.tileset
                        ) {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(selectedUnitName)
                                    .font(statusTheme.titleFont)
                                if let health = session.selectedUnitHealth {
                                    if statusTheme.showsStatusMeters {
                                        PlaytestEraMeter(
                                            value: Double(health),
                                            total: 100,
                                            tint: health > 50 ? statusTheme.armyAccent(session.activeArmy) : statusTheme.warningText,
                                            theme: statusTheme
                                        )
                                    }
                                    Text("Health \(health)%")
                                        .font(statusTheme.valueFont)
                                        .foregroundStyle(statusTheme.secondaryText)
                                }
                                if let fuel = session.selectedUnitFuel {
                                    if statusTheme.showsStatusMeters {
                                        PlaytestEraMeter(
                                            value: Double(fuel),
                                            total: Double(session.selectedUnitMaxFuel ?? 100),
                                            tint: fuel > 25 ? statusTheme.resourceTint : statusTheme.warningText,
                                            theme: statusTheme
                                        )
                                    }
                                    Text(
                                        "\(session.selectedUnitResourceLabel ?? "Fuel") \(fuel)/\(session.selectedUnitMaxFuel ?? 100)"
                                    )
                                    .font(statusTheme.valueFont)
                                    .foregroundStyle(statusTheme.secondaryText)
                                }
                                if let ammo = session.selectedUnitAmmo {
                                    Text("Primary ammo \(ammo)")
                                        .font(statusTheme.valueFont)
                                        .foregroundStyle(statusTheme.secondaryText)
                                }
                                if session.selectedUnitIsSubmarine {
                                    Text(session.selectedSubmarineIsSubmerged ? "SUBMERGED" : "SURFACED")
                                        .font(statusTheme.detailFont)
                                        .foregroundStyle(statusTheme.secondaryText)
                                }
                                if let capacity = session.selectedTransportCapacity {
                                    Text("CARGO \(session.selectedCargoCount)/\(capacity)")
                                        .font(statusTheme.detailFont)
                                    if let cargo = session.selectedCargoSummary {
                                        Text(cargo)
                                            .font(statusTheme.detailFont)
                                            .foregroundStyle(statusTheme.secondaryText)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    if !hidesLegacyCommandButtons,
                                       session.selectedCargoNames.count > 1 {
                                        HStack(spacing: 6) {
                                            ForEach(Array(session.selectedCargoNames.enumerated()), id: \.offset) { index, name in
                                                Button(name) {
                                                    session.selectCargo(index: index)
                                                }
                                                .buttonStyle(
                                                    PlaytestEraButtonStyle(theme: statusTheme, tone: .neutral)
                                                )
                                            }
                                        }
                                    }
                                    HStack(spacing: 10) {
                                        if !session.loadableCells.isEmpty {
                                            Text("LOAD")
                                                .font(statusTheme.detailFont)
                                                .foregroundStyle(statusTheme.resourceTint)
                                        }
                                        if !session.unloadableCells.isEmpty {
                                            Text("UNLOAD")
                                                .font(statusTheme.detailFont)
                                                .foregroundStyle(statusTheme.warningText)
                                        }
                                    }
                                }
                                if !hidesLegacyCommandButtons {
                                    if session.selectedTransportCanResupply {
                                        if session.selectedTransportIsBlackBoat {
                                            ForEach(
                                                sortedRefuelableCells,
                                                id: \.self
                                            ) { point in
                                                PlaytestRepairButton(
                                                    session: session,
                                                    point: point
                                                )
                                            }
                                        } else {
                                            Button("Resupply adjacent units") {
                                                session.resupplySelectedTransport()
                                            }
                                            .buttonStyle(
                                                PlaytestEraButtonStyle(theme: statusTheme, tone: .primary)
                                            )
                                        }
                                    }
                                    if session.selectedUnitCanLaunchSilo {
                                        Button("Launch Missile Silo", action: session.beginSiloLaunch)
                                        .buttonStyle(
                                            PlaytestEraButtonStyle(theme: statusTheme, tone: .primary)
                                        )
                                    }
                                    if session.selectedUnitCanUseFlare {
                                        Button("Use Flare", action: session.useFlare)
                                            .buttonStyle(
                                                PlaytestEraButtonStyle(theme: statusTheme, tone: .primary)
                                            )
                                    }
                                }
                                if let progress = session.selectedCaptureProgress {
                                    Text(progress)
                                        .font(statusTheme.valueFont)
                                        .foregroundStyle(statusTheme.secondaryText)
                                }
                                if !hidesLegacyCommandButtons {
                                    HStack(spacing: 8) {
                                        if session.selectedUnitIsSubmarine {
                                            Button(
                                                session.selectedSubmarineIsSubmerged ? "Surface" : "Dive",
                                                action: session.toggleSubmerge
                                            )
                                            .buttonStyle(
                                                PlaytestEraButtonStyle(theme: statusTheme, tone: .neutral)
                                            )
                                        }
                                        if session.selectedUnitIsStealth {
                                            Button(
                                                session.selectedStealthIsCloaked ? "Uncloak" : "Cloak",
                                                action: session.toggleStealth
                                            )
                                            .buttonStyle(
                                                PlaytestEraButtonStyle(theme: statusTheme, tone: .neutral)
                                            )
                                        }
                                        if session.selectedUnitCanDetonateBlackBomb {
                                            Button("Detonate", action: session.detonateBlackBomb)
                                                .buttonStyle(
                                                    PlaytestEraButtonStyle(theme: statusTheme, tone: .primary)
                                                )
                                        }
                                        if session.captureableCells.contains(where: { $0 == session.selectedPoint }) {
                                            Button("Capture", action: session.capture)
                                                .buttonStyle(
                                                    PlaytestEraButtonStyle(theme: statusTheme, tone: .primary)
                                                )
                                        }
                                        Button("Wait", action: session.wait)
                                            .buttonStyle(
                                                PlaytestEraButtonStyle(theme: statusTheme, tone: .neutral)
                                            )
                                    }
                                }
                            }
                        }
                    } else if let selectedBuildingName = session.selectedBuildingName {
                        PlaytestStatusPanel(
                            "Property status",
                            tileset: session.map.tileset
                        ) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(selectedBuildingName)
                                    .font(statusTheme.titleFont)
                                if let owner = session.selectedBuildingOwnerName {
                                    Text("Owner: \(owner)")
                                        .font(statusTheme.detailFont)
                                        .foregroundStyle(statusTheme.secondaryText)
                                }
                                if !session.ruleset.usesLegacyKeyboardControls,
                                   !session.productionOptions.isEmpty {
                                    Text("Build unit")
                                        .font(statusTheme.bodyFont)
                                    ForEach(session.productionOptions) { option in
                                        Button {
                                            session.buildUnit(option)
                                        } label: {
                                            HStack(spacing: 8) {
                                                Text(option.label)
                                                Spacer(minLength: 8)
                                                Text(PlaytestRulebook.formatFunds(option.cost))
                                                    .font(statusTheme.valueFont)
                                            }
                                        }
                                        .buttonStyle(
                                            PlaytestEraButtonStyle(theme: statusTheme, tone: .neutral)
                                        )
                                        .disabled(!session.canBuild(option))
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)

            PlaytestStatusPanel(
                "Battle status",
                tileset: session.map.tileset
            ) {
                PlaytestSidebarStatus(session: session)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.clear)
    }
}

private struct PlaytestRepairButton: View {
    let session: PlaytestSession
    let point: GridPoint

    var body: some View {
        Button("Repair \(session.unitName(at: point) ?? "unit")") {
            session.resupplySelectedTransport(target: point)
        }
        .buttonStyle(
            PlaytestEraButtonStyle(
                theme: PlaytestStatusTheme(tileset: session.map.tileset),
                tone: .primary
            )
        )
    }
}

private struct PlaytestSidebarStatus: View {
    let session: PlaytestSession

    private var theme: PlaytestStatusTheme {
        PlaytestStatusTheme(tileset: session.map.tileset)
    }

    private var activeTeamColor: Color {
        if theme == .famicomWars {
            return theme.armyAccent(session.activeArmy)
        }

        return switch session.team(for: session.activeArmy) {
            case .red: Color.red
            case .blue: Color.blue
            case .yellow: Color.yellow
            case .green: Color.green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("DAY \(session.turn)")
                Spacer(minLength: 6)
                Text(PlaytestRulebook.formatFunds(session.activeFunds))
            }
            .font(theme.valueFont)
            .foregroundStyle(theme.secondaryText)

            HStack(spacing: 4) {
                Image(systemName: "flag.fill")
                    .foregroundStyle(activeTeamColor)
                    .accessibilityHidden(true)
                Text("\(session.activeArmyName)")
                    .font(theme.titleFont)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Day \(session.turn), \(session.activeArmyName)'s \(session.activeArmyIsCPU ? "CPU" : "player") turn, team \(session.team(for: session.activeArmy).displayName), available funds \(PlaytestRulebook.formatFunds(session.activeFunds))"
        )
    }
}
