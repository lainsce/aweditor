import SwiftUI
import AWEDCore

struct PlaytestView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var session: PlaytestSession
    @State private var previewModel: EditorModel
    @State private var dayBannerSequence = 0
    @State private var isDayBannerVisible = false
    @State private var isShowingArmySetup = false
    @State private var legacyMenuMode: PlaytestLegacyMenuMode = .closed
    @State private var legacyMenuSelection = 0
    @State private var legacyBuildSelection = 0
    @State private var legacyTarget: PlaytestLegacyTarget?

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
            let inspectorWidth: CGFloat = 256
            let isLegacyPlaytest = session.ruleset.usesLegacyKeyboardControls
            let legacyRailWidth = isLegacyPlaytest
                ? PlaytestLegacyCommandRail.width
                : 0
            // The map is the flyout's camera viewport for every era. Side
            // panels sit on top of its trailing edge so the board remains
            // centered in the flyout instead of being anchored to the
            // inspector's left boundary.
            let mapColumnWidth = proxy.size.width
            let headerHeight = PlaytestHeader.height
            let dividerHeight: CGFloat = 1
            let mapAreaHeight = max(0, proxy.size.height - headerHeight - dividerHeight)
            let dayBannerHeight = PlaytestDayBanner.height(
                for: session.map.tileset,
                mapAreaHeight: mapAreaHeight
            )
            let dayBannerWidth = PlaytestDayBanner.width(
                for: session.map.tileset,
                availableWidth: mapColumnWidth,
                tileSize: MapCanvasMetrics.tileSize
            )
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

                    if isLegacyPlaytest {
                        ZStack(alignment: .topLeading) {
                            ZStack(alignment: .topTrailing) {
                                PlaytestMapColumn(
                                    session: session,
                                    previewModel: previewModel,
                                    atlas: atlas,
                                    mapSize: mapSize
                                )
                                .frame(width: mapColumnWidth, height: mapAreaHeight)

                                PlaytestInspector(session: session)
                                    .frame(width: inspectorWidth, height: mapAreaHeight)
                                    .allowsHitTesting(false)
                            }

                            PlaytestLegacyCommandRail(
                                session: session,
                                availableHeight: mapAreaHeight,
                                mode: $legacyMenuMode,
                                selection: $legacyMenuSelection,
                                buildSelection: $legacyBuildSelection,
                                onAction: activateLegacyAction,
                                onBuild: activateLegacyBuild
                            )
                            .frame(
                                width: legacyRailWidth,
                                height: mapAreaHeight,
                                alignment: .topLeading
                            )
                        }
                        .frame(width: mapColumnWidth, height: mapAreaHeight)
                    } else {
                        ZStack(alignment: .topTrailing) {
                            PlaytestMapColumn(
                                session: session,
                                previewModel: previewModel,
                                atlas: atlas,
                                mapSize: mapSize
                            )
                            .frame(width: mapColumnWidth, height: mapAreaHeight)

                            PlaytestInspector(session: session)
                                .frame(width: inspectorWidth, height: mapAreaHeight)
                        }
                        .frame(width: mapColumnWidth, height: mapAreaHeight, alignment: .topLeading)
                    }
                }

                PlaytestKeyboardInput(session: session, onKey: handleLegacyKey)
                    // Keep the AppKit catcher attached to the presented
                    // sheet's full content area. A zero-sized representable
                    // can be detached during SwiftUI layout updates, which
                    // lets arrow/A/B/Select events fall through to AppKit's
                    // default responder and trigger its alert sound.
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)

                if isDayBannerVisible {
                    PlaytestDayBanner(
                        day: session.turn,
                        army: session.activeArmy,
                        tileset: session.map.tileset,
                        atlas: atlas,
                        bannerHeight: dayBannerHeight
                    )
                    .id(dayBannerSequence)
                    .frame(width: dayBannerWidth, height: dayBannerHeight)
                    .offset(
                        x: (mapColumnWidth - dayBannerWidth) / 2,
                        y: headerHeight + dividerHeight + (mapAreaHeight - dayBannerHeight) / 2
                    )
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        )
                    )
                    .zIndex(1)
                    .allowsHitTesting(false)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(minWidth: 800, minHeight: 600)
        .interactiveDismissDisabled(true)
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
            // Keep the transition readable long enough to identify the
            // active faction, then ease it away rather than snapping out.
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.32)) {
                isDayBannerVisible = false
            }
        }
        .onChange(of: session.mapRevision) { _, _ in syncPreviewModel() }
        .onChange(of: session.musicRevision) { _, _ in
            routePlaytestMusic()
        }
        .onChange(of: session.activeArmy) { _, _ in
            // The backdrop only changes with the active army when Fog of War
            // (or submerged enemy rendering) is involved. Avoid rebuilding
            // the entire sprite Canvas on every ordinary CPU turn switch.
            if session.isFogOfWarActive || !session.submergedUnits.isEmpty {
                syncPreviewModel()
            }
            closeLegacyMenu()
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

    private var legacyActions: [PlaytestLegacyAction] {
        PlaytestLegacyActionCatalog.actions(for: session)
    }

    private func handleLegacyKey(_ key: PlaytestLegacyKey) {
        guard session.ruleset.usesLegacyKeyboardControls,
              session.isStarted,
              !session.activeArmyIsCPU,
              !session.isPlayerMovementAnimating,
              !session.isGameOver else { return }

        switch key {
        case .up:
            switch legacyMenuMode {
            case .commands: moveLegacyMenu(by: -1)
            case .build: moveLegacyBuild(by: -1)
            case .closed: session.moveCursor(dx: 0, dy: -1)
            }
        case .down:
            switch legacyMenuMode {
            case .commands: moveLegacyMenu(by: 1)
            case .build: moveLegacyBuild(by: 1)
            case .closed: session.moveCursor(dx: 0, dy: 1)
            }
        case .left:
            if legacyMenuMode == .closed {
                session.moveCursor(dx: -1, dy: 0)
            }
        case .right:
            if legacyMenuMode == .closed {
                session.moveCursor(dx: 1, dy: 0)
            }
        case .a:
            activateLegacyA()
        case .b:
            switch legacyMenuMode {
            case .build:
                legacyMenuMode = .commands
                legacyBuildSelection = 0
            case .commands:
                legacyMenuMode = .closed
            case .closed:
                if legacyTarget != nil {
                    legacyTarget = nil
                    session.cancelLegacySelection()
                } else {
                    session.cancelLegacySelection()
                }
            }
        case .select:
            switch legacyMenuMode {
            case .closed: openLegacyCommands()
            case .commands, .build:
                legacyMenuMode = .closed
            }
        }
    }

    private func activateLegacyA() {
        switch legacyMenuMode {
        case .closed:
            if legacyTarget == .resupply {
                guard let target = session.cursorPoint else { return }
                session.resupplySelectedTransport(target: target)
                legacyTarget = nil
            } else if session.selectedPoint != nil, session.selectedPoint == session.cursorPoint {
                if session.selectedBuildingName != nil, !session.productionOptions.isEmpty {
                    legacyBuildSelection = 0
                    legacyMenuMode = .build
                } else {
                    openLegacyCommands()
                }
            } else {
                session.selectLegacyCursor()
                if session.selectedBuildingName != nil, !session.productionOptions.isEmpty {
                    legacyBuildSelection = 0
                    legacyMenuMode = .build
                }
            }
        case .commands:
            guard legacyActions.indices.contains(legacyMenuSelection) else { return }
            activateLegacyAction(legacyActions[legacyMenuSelection])
        case .build:
            activateLegacyBuild(legacyBuildSelection)
        }
    }

    private func openLegacyCommands() {
        legacyMenuSelection = min(max(legacyMenuSelection, 0), max(0, legacyActions.count - 1))
        legacyMenuMode = .commands
    }

    private func moveLegacyMenu(by offset: Int) {
        guard !legacyActions.isEmpty else { return }
        let count = legacyActions.count
        let current = min(max(legacyMenuSelection, 0), count - 1)
        legacyMenuSelection = (current + offset + count) % count
    }

    private func moveLegacyBuild(by offset: Int) {
        guard !session.productionOptions.isEmpty else { return }
        let count = session.productionOptions.count
        let current = min(max(legacyBuildSelection, 0), count - 1)
        legacyBuildSelection = (current + offset + count) % count
    }

    private func activateLegacyAction(_ action: PlaytestLegacyAction) {
        guard PlaytestLegacyActionCatalog.isEnabled(action, session: session) else {
            if action == .build {
                session.statusMessage = "Select an owned, empty production property with enough funds."
            }
            return
        }

        switch action {
        case .build:
            guard session.selectedBuildingName != nil else {
                session.statusMessage = "Select an owned production property first."
                return
            }
            legacyBuildSelection = 0
            legacyMenuMode = .build
        case .stat:
            session.inspectLegacyCursor()
            closeLegacyMenu()
        case .move:
            let message = session.ruleset.showsMovementAvailabilityBadge
                ? "Choose an M marker, then press A."
                : "Choose a movement tile, then press A."
            focusLegacyTarget(session.reachableCells, message: message)
        case .attack:
            focusLegacyTarget(session.attackableCells, message: "Choose a red target, then press A.")
        case .capture:
            closeLegacyMenu()
            session.capture()
        case .load:
            focusLegacyTarget(session.loadableCells, message: "Choose a transport, then press A to load.")
        case .unload:
            focusLegacyTarget(session.unloadableCells, message: "Choose an unload tile, then press A.")
        case .join:
            focusLegacyTarget(session.joinableCells, message: "Choose the allied unit, then press A to join.")
        case .resupply:
            if session.selectedTransportIsBlackBoat {
                guard let target = session.firstLegacyTarget(in: session.refuelableCells) else {
                    session.statusMessage = "No adjacent unit needs resupply."
                    return
                }
                session.setCursor(target)
                legacyTarget = .resupply
                legacyMenuMode = .closed
                session.statusMessage = "Choose a unit to resupply, then press A."
            } else {
                closeLegacyMenu()
                session.resupplySelectedTransport()
            }
        case .surface:
            closeLegacyMenu()
            session.toggleSubmerge()
        case .stealth:
            closeLegacyMenu()
            session.toggleStealth()
        case .detonate:
            closeLegacyMenu()
            session.detonateBlackBomb()
        case .flare:
            closeLegacyMenu()
            session.useFlare()
        case .silo:
            session.beginSiloLaunch()
            if let target = session.firstLegacyTarget(in: session.siloTargetCells) {
                session.setCursor(target)
            }
            closeLegacyMenu()
        case .wait:
            closeLegacyMenu()
            session.wait()
        case .endTurn:
            closeLegacyMenu()
            session.endTurn()
            routePlaytestMusic()
        case .surrender:
            closeLegacyMenu()
            exitPlaytest()
        }
    }

    private func activateLegacyBuild(_ index: Int) {
        guard session.productionOptions.indices.contains(index) else { return }
        let option = session.productionOptions[index]
        guard session.canBuild(option) else {
            session.statusMessage = "That unit cannot be built here right now."
            return
        }
        session.buildUnit(option)
        closeLegacyMenu()
    }

    private func focusLegacyTarget(_ points: Set<GridPoint>, message: String) {
        guard let target = session.firstLegacyTarget(in: points) else {
            session.statusMessage = "There is no legal target for that action."
            return
        }
        session.setCursor(target)
        legacyTarget = nil
        legacyMenuMode = .closed
        session.statusMessage = message
    }

    private func closeLegacyMenu() {
        legacyMenuMode = .closed
        legacyMenuSelection = 0
        legacyBuildSelection = 0
        legacyTarget = nil
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
