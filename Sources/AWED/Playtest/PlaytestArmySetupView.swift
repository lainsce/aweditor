import SwiftUI
import AWEDCore


struct PlaytestArmySetupView: View {
    let session: PlaytestSession
    let continueAction: () -> Void
    let exitAction: () -> Void

    @State private var playerArmy: Int?
    @State private var cpuArmies: Set<Int>
    @State private var teams: [Int: PlaytestTeam]
    @State private var isCPUOnlyMatch: Bool

    init(session: PlaytestSession, continueAction: @escaping () -> Void, exitAction: @escaping () -> Void) {
        self.session = session
        self.continueAction = continueAction
        self.exitAction = exitAction
        let armies = session.playableArmies
        let automatic = PlaytestConfiguration.automatic(for: armies)
        _playerArmy = State(initialValue: session.playerArmy ?? automatic.playerArmy)
        _cpuArmies = State(initialValue: automatic.cpuArmies)
        _teams = State(initialValue: automatic.teams)
        _isCPUOnlyMatch = State(initialValue: session.supportsCPUOnlyMatch && session.playerArmy == nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set up playtest")
                .font(.title2.weight(.bold))
            Text(isCPUOnlyMatch
                ? "Both armies will be controlled by the CPU. You can still choose their alliances before the first turn."
                : "Choose the human side, CPU sides, and alliances before the first turn.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if session.supportsCPUOnlyMatch {
                Toggle(isOn: cpuOnlyMatchBinding) {
                    Label("No player (CPU vs CPU)", systemImage: "cpu")
                }
                .toggleStyle(NativeToggleStyle())
                .help("Let all playable armies take their turns automatically without a human side.")
            }

            VStack(spacing: 8) {
                ForEach(session.playableArmies, id: \.self) { army in
                    HStack(spacing: 12) {
                        Text(PaletteCatalog.armyName(army, tileset: session.map.tileset))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Picker("Control", selection: controlBinding(for: army)) {
                            Text("Player").tag(true)
                            Text("CPU").tag(false)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 92)
                        .disabled(isCPUOnlyMatch)

                        HStack(spacing: 5) {
                            Image(systemName: "flag.fill")
                                .foregroundStyle(armyFlagColor(for: army))
                                .accessibilityHidden(true)
                            Picker("Team", selection: teamBinding(for: army)) {
                                ForEach(PlaytestTeam.allCases) { team in
                                    Label {
                                        Text(team.displayName)
                                    } icon: {
                                        Image(systemName: "flag.fill")
                                            .foregroundStyle(teamColor(team))
                                    }
                                    .tag(team)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        }
                        .frame(width: 124)
                    }
                    .padding(.vertical, 4)
                }
            }

            HStack {
                Button("Cancel", action: exitAction)
                Spacer()
                Button("Start Playtest") {
                    let configuration = PlaytestConfiguration(
                        playerArmy: isCPUOnlyMatch ? nil : playerArmy,
                        cpuArmies: isCPUOnlyMatch ? Set(session.playableArmies) : cpuArmies,
                        teams: teams
                    )
                    guard session.applyConfiguration(configuration) else { return }
                    session.startPlaytest()
                    continueAction()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!isCPUOnlyMatch && playerArmy == nil)
            }
        }
        .padding(24)
        .frame(width: 560)
        .interactiveDismissDisabled(true)
    }

    private func controlBinding(for army: Int) -> Binding<Bool> {
        Binding(
            get: { playerArmy == army },
            set: { isPlayer in
                if isPlayer {
                    playerArmy = army
                    cpuArmies.remove(army)
                } else {
                    cpuArmies.insert(army)
                    if playerArmy == army {
                        playerArmy = session.playableArmies.first(where: { $0 != army })
                        if let playerArmy { cpuArmies.remove(playerArmy) }
                    }
                }
            }
        )
    }

    private var cpuOnlyMatchBinding: Binding<Bool> {
        Binding(
            get: { isCPUOnlyMatch },
            set: { enabled in
                guard session.supportsCPUOnlyMatch else { return }
                isCPUOnlyMatch = enabled
                if enabled {
                    playerArmy = nil
                    cpuArmies = Set(session.playableArmies)
                } else {
                    let automatic = PlaytestConfiguration.automatic(for: session.playableArmies)
                    playerArmy = automatic.playerArmy
                    cpuArmies = automatic.cpuArmies
                }
            }
        )
    }

    private func teamBinding(for army: Int) -> Binding<PlaytestTeam> {
        Binding(
            get: { teams[army] ?? .red },
            set: { teams[army] = $0 }
        )
    }

    private func armyFlagColor(for army: Int) -> Color {
        if session.map.tileset == .famicomWars {
            return PlaytestStatusTheme(tileset: session.map.tileset).armyAccent(army)
        }
        return (teams[army] ?? .red).color
    }

    private func teamColor(_ team: PlaytestTeam) -> Color {
        guard session.map.tileset == .famicomWars else { return team.color }

        switch team {
        case .red: return FamicomPPUPalette.red
        case .blue: return FamicomPPUPalette.blue
        case .yellow: return FamicomPPUPalette.yellow
        case .green: return FamicomPPUPalette.green
        }
    }
}

private extension PlaytestTeam {
    var color: Color {
        switch self {
        case .red: .red
        case .blue: .blue
        case .yellow: .yellow
        case .green: .green
        }
    }
}
