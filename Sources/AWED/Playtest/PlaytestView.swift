import SwiftUI
import AWEDCore
struct PlaytestView: View {
    @Environment(\.dismiss) var dismiss
    @State var session: PlaytestSession
    @State var previewModel: EditorModel
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
                    mapContent(
                        isLegacyPlaytest: isLegacyPlaytest,
                        mapColumnWidth: mapColumnWidth,
                        mapAreaHeight: mapAreaHeight,
                        inspectorWidth: inspectorWidth,
                        legacyRailWidth: legacyRailWidth
                    )
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

    @ViewBuilder
    private func mapContent(
        isLegacyPlaytest: Bool,
        mapColumnWidth: CGFloat,
        mapAreaHeight: CGFloat,
        inspectorWidth: CGFloat,
        legacyRailWidth: CGFloat
    ) -> some View {
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
                .frame(width: legacyRailWidth, height: mapAreaHeight, alignment: .topLeading)
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
        case .up, .down: handleLegacyVerticalKey(key)
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
        case .b: handleLegacyBack()
        case .select: handleLegacySelect()
        }
    }

    private func handleLegacyVerticalKey(_ key: PlaytestLegacyKey) {
        let offset = key == .up ? -1 : 1
        switch legacyMenuMode {
        case .commands: moveLegacyMenu(by: offset)
        case .build: moveLegacyBuild(by: offset)
        case .closed: session.moveCursor(dx: 0, dy: offset)
        }
    }

    private func handleLegacyBack() {
        switch legacyMenuMode {
        case .build:
            legacyMenuMode = .commands
            legacyBuildSelection = 0
        case .commands:
            legacyMenuMode = .closed
        case .closed:
            legacyTarget = nil
            session.cancelLegacySelection()
        }
    }

    private func handleLegacySelect() {
        switch legacyMenuMode {
        case .closed: openLegacyCommands()
        case .commands, .build: legacyMenuMode = .closed
        }
    }
    private func activateLegacyA() {
        switch legacyMenuMode {
        case .closed: activateLegacyClosedA()
        case .commands: activateLegacyCommandA()
        case .build: activateLegacyBuild(legacyBuildSelection)
        }
    }

    private func activateLegacyClosedA() {
        if legacyTarget == .resupply {
            guard let target = session.cursorPoint else { return }
            session.resupplySelectedTransport(target: target)
            legacyTarget = nil
            return
        }
        if session.selectedPoint != nil, session.selectedPoint == session.cursorPoint {
            openLegacySelectionOrCommands()
            return
        }
        session.selectLegacyCursor()
        openLegacyBuildIfAvailable()
    }

    private func openLegacySelectionOrCommands() {
        if session.selectedBuildingName != nil, !session.productionOptions.isEmpty {
            openLegacyBuild()
        } else {
            openLegacyCommands()
        }
    }

    private func openLegacyBuildIfAvailable() {
        if session.selectedBuildingName != nil, !session.productionOptions.isEmpty {
            openLegacyBuild()
        }
    }

    private func openLegacyBuild() {
        legacyBuildSelection = 0
        legacyMenuMode = .build
    }

    private func activateLegacyCommandA() {
        guard legacyActions.indices.contains(legacyMenuSelection) else { return }
        activateLegacyAction(legacyActions[legacyMenuSelection])
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
        case .build: activateLegacyBuildAction()
        case .stat: activateLegacyStatAction()
        case .move, .attack, .load, .unload, .join: activateLegacyTargetAction(action)
        case .capture: closeLegacyMenu(); session.capture()
        case .resupply: activateLegacyResupplyAction()
        case .surface, .stealth, .detonate, .flare: activateLegacyToggleAction(action)
        case .silo: activateLegacySiloAction()
        case .wait: closeLegacyMenu(); session.wait()
        case .endTurn: closeLegacyMenu(); session.endTurn(); routePlaytestMusic()
        case .surrender: closeLegacyMenu(); exitPlaytest()
        }
    }

    private func activateLegacyBuildAction() {
        guard session.selectedBuildingName != nil else {
            session.statusMessage = "Select an owned production property first."
            return
        }
        openLegacyBuild()
    }

    private func activateLegacyStatAction() {
        session.inspectLegacyCursor()
        closeLegacyMenu()
    }

    private func activateLegacyTargetAction(_ action: PlaytestLegacyAction) {
        switch action {
        case .move:
            let message = session.ruleset.showsMovementAvailabilityBadge ? "Choose an M marker, then press A." : "Choose a movement tile, then press A."
            focusLegacyTarget(session.reachableCells, message: message)
        case .attack: focusLegacyTarget(session.attackableCells, message: "Choose a red target, then press A.")
        case .load: focusLegacyTarget(session.loadableCells, message: "Choose a transport, then press A to load.")
        case .unload: focusLegacyTarget(session.unloadableCells, message: "Choose an unload tile, then press A.")
        case .join: focusLegacyTarget(session.joinableCells, message: "Choose the allied unit, then press A to join.")
        default: break
        }
    }

    private func activateLegacyResupplyAction() {
        guard session.selectedTransportIsBlackBoat else {
            closeLegacyMenu()
            session.resupplySelectedTransport()
            return
        }
        guard let target = session.firstLegacyTarget(in: session.refuelableCells) else {
            session.statusMessage = "No adjacent unit needs resupply."
            return
        }
        session.setCursor(target)
        legacyTarget = .resupply
        legacyMenuMode = .closed
        session.statusMessage = "Choose a unit to resupply, then press A."
    }

    private func activateLegacyToggleAction(_ action: PlaytestLegacyAction) {
        closeLegacyMenu()
        switch action {
        case .surface: session.toggleSubmerge()
        case .stealth: session.toggleStealth()
        case .detonate: session.detonateBlackBomb()
        case .flare: session.useFlare()
        default: break
        }
    }

    private func activateLegacySiloAction() {
        session.beginSiloLaunch()
        if let target = session.firstLegacyTarget(in: session.siloTargetCells) {
            session.setCursor(target)
        }
        closeLegacyMenu()
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
}
