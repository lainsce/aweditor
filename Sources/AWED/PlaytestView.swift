import SwiftUI
import AWEDCore

struct PlaytestView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var session: PlaytestSession
    @State private var previewModel: EditorModel
    @State private var dayBannerSequence = 0
    @State private var isDayBannerVisible = false
    @State private var isShowingArmySetup = false

    let atlas: SpriteAtlas
    let mapSize: CGSize
    /// The app-wide controller is shared with the editor so entering a
    /// playtest replaces (rather than layers over) design music.
    let music: BackgroundMusicController?
    let designTileset: Tileset
    let designMusicEnabled: Bool
    let designMusicVolume: Int

    init(
        map: MapState,
        visualVariant: MapVisualVariant? = nil,
        atlas: SpriteAtlas,
        music: BackgroundMusicController? = nil,
        designMusicEnabled: Bool = true,
        designMusicVolume: Int = 100
    ) {
        let session = PlaytestSession(map: map, visualVariant: visualVariant, startCPU: false)
        _session = State(initialValue: session)
        let previewModel = EditorModel(map: session.displayMap)
        previewModel.spritePalette = session.displayPalette
        _previewModel = State(initialValue: previewModel)
        _isShowingArmySetup = State(initialValue: session.needsInitialArmySetup)
        self.atlas = atlas
        self.music = music
        self.designTileset = map.tileset
        self.designMusicEnabled = designMusicEnabled
        self.designMusicVolume = designMusicVolume
        self.mapSize = MapCanvasMetrics.mapPixelSize(
            width: map.width,
            height: map.height,
            tileSize: MapCanvasMetrics.tileSize,
            staggered: session.isStaggeredGrid
        )
    }

    var body: some View {
        let frameTheme = PlaytestFrameTheme.playtest(for: session.map.tileset)

        GeometryReader { proxy in
            let inspectorWidth: CGFloat = 270
            let headerHeight = PlaytestHeader.height
            let dividerHeight: CGFloat = 1
            let mapColumnWidth = max(0, proxy.size.width - inspectorWidth)
            let mapAreaHeight = max(0, proxy.size.height - headerHeight - dividerHeight)
            // Keep the grid origin in the same coordinate space as the
            // parchment. The board's internal paper/wood padding cancels out
            // against the centering math in PlaytestMapSurface.
            let mapGridOrigin = CGPoint(
                x: (mapColumnWidth - mapSize.width) / 2,
                y: headerHeight + dividerHeight + (mapAreaHeight - mapSize.height) / 2
            )

            ZStack(alignment: .topLeading) {
                MapParchmentSurface(
                    tileSize: MapCanvasMetrics.tileSize,
                    mapSize: mapSize,
                    gridOrigin: mapGridOrigin,
                    theme: frameTheme
                )
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    PlaytestHeader(
                        session: session,
                        restartAction: {
                            session.restart()
                            routePlaytestMusic()
                        },
                        endTurnAction: {
                            session.endTurn()
                            routePlaytestMusic()
                        },
                        exitAction: exitPlaytest
                    )

                    Rectangle()
                        .fill(frameTheme.headerBorder.opacity(0.30))
                        .frame(height: dividerHeight)

                    HStack(spacing: 0) {
                        PlaytestMapColumn(
                            session: session,
                            previewModel: previewModel,
                            atlas: atlas,
                            mapSize: mapSize,
                            showDayBanner: isDayBannerVisible,
                            dayBannerSequence: dayBannerSequence
                        )
                        .frame(width: mapColumnWidth, height: mapAreaHeight)

                        PlaytestInspector(session: session)
                            .frame(width: inspectorWidth, height: mapAreaHeight)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(minWidth: 1_080, minHeight: 680)
        .onAppear {
            // Design music should not continue under the playtest sheet while
            // the initial army/teams setup is being chosen.
            music?.stop()
            syncPreviewModel()
            if !session.needsInitialArmySetup {
                session.startPlaytest()
                routePlaytestMusic()
                presentDayBanner()
            }
        }
        .onDisappear {
            restoreEditorMusic()
        }
        .task(id: dayBannerSequence) {
            guard dayBannerSequence > 0 else { return }
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                isDayBannerVisible = false
            }
        }
        .onChange(of: session.mapRevision) { _, _ in syncPreviewModel() }
        .onChange(of: session.activeArmy) { _, _ in
            // The backdrop only changes with the active army when Fog of War
            // (or submerged enemy rendering) is involved. Avoid rebuilding
            // the entire sprite Canvas on every ordinary CPU turn switch.
            if session.isFogOfWarActive || !session.submergedUnits.isEmpty {
                syncPreviewModel()
            }
            presentDayBanner()
            routePlaytestMusic()
        }
        .onChange(of: session.winnerArmy) { _, _ in
            routePlaytestMusic()
        }
        .onChange(of: session.fogOfWarEnabled) { _, _ in syncPreviewModel() }
        .onChange(of: session.weather) { _, _ in syncPreviewModel() }
        .onChange(of: session.submergedRevision) { _, _ in syncPreviewModel() }
        .sheet(isPresented: $isShowingArmySetup) {
            PlaytestArmySetupView(
                session: session,
                continueAction: {
                    isShowingArmySetup = false
                    syncPreviewModel()
                    routePlaytestMusic()
                    presentDayBanner()
                },
                exitAction: exitPlaytest
            )
        }
    }

    private func syncPreviewModel() {
        previewModel.map = session.displayMap
        previewModel.spritePalette = session.displayPalette
    }

    private func presentDayBanner() {
        withAnimation(.easeOut(duration: 0.16)) {
            dayBannerSequence &+= 1
            isDayBannerVisible = true
        }
    }

    private func routePlaytestMusic() {
        guard let music else { return }
        let cue: PlaytestMusicCue
        if let winner = session.winnerArmy {
            cue = winner == session.activeArmy ? .winning : .losing
        } else {
            cue = session.playtestMusicCue
        }
        music.apply(
            playtestTileset: session.map.tileset,
            army: session.activeArmy,
            cue: cue,
            enabled: designMusicEnabled,
            volume: designMusicVolume
        )
    }

    private func restoreEditorMusic() {
        music?.apply(
            tileset: designTileset,
            enabled: designMusicEnabled,
            volume: designMusicVolume
        )
    }

    private func exitPlaytest() {
        session.stopCPU()
        restoreEditorMusic()
        dismiss()
    }
}

private struct PlaytestArmySetupView: View {
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
                                .foregroundStyle((teams[army] ?? .red).color)
                                .accessibilityHidden(true)
                            Picker("Team", selection: teamBinding(for: army)) {
                                ForEach(PlaytestTeam.allCases) { team in
                                    Label {
                                        Text(team.displayName)
                                    } icon: {
                                        Image(systemName: "flag.fill")
                                            .foregroundStyle(team.color)
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
                    .keyboardShortcut(.cancelAction)
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
