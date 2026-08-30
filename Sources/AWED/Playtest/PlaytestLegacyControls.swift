import AppKit
import SwiftUI
import AWEDCore

/// The small controller vocabulary shared by Famicom Wars through Advance
/// Wars 2. These games do not have a mouse-driven map UI on the cartridge:
/// the map cursor moves with the D-pad, A confirms, B backs out, and Select
/// opens the command list.
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
        case .build: "BUILD"
        case .stat: "STAT"
        case .move: "MOVE"
        case .attack: "ATTACK"
        case .capture: "CAPTURE"
        case .load: "LOAD"
        case .unload: "UNLOAD"
        case .join: "JOIN"
        case .resupply: "SUPPLY"
        case .surface: session.selectedSubmarineIsSubmerged ? "SURFACE" : "DIVE"
        case .stealth: session.selectedStealthIsCloaked ? "UNCLOAK" : "CLOAK"
        case .detonate: "DETONATE"
        case .flare: "FLARE"
        case .silo: "SILO"
        case .wait: "WAIT"
        case .endTurn: "END TURN"
        case .surrender: "SURRENDER"
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
        case .move: !session.reachableCells.isEmpty
        case .attack: !session.attackableCells.isEmpty
        case .capture: !session.captureableCells.isEmpty
        case .load: !session.loadableCells.isEmpty
        case .unload: !session.unloadableCells.isEmpty
        case .join: !session.joinableCells.isEmpty
        case .resupply: session.selectedTransportCanResupply
        case .surface: session.selectedUnitCanToggleDepth
        case .stealth: session.selectedUnitCanToggleStealth
        case .detonate: session.selectedUnitCanDetonateBlackBomb
        case .flare: session.selectedUnitCanUseFlare
        case .silo: session.selectedUnitCanLaunchSilo
        case .wait: session.selectedUnitCanWait
        case .endTurn: !session.isGameOver && !session.activeArmyIsCPU && !session.isPlayerMovementAnimating
        case .surrender: !session.isGameOver && !session.activeArmyIsCPU && !session.isPlayerMovementAnimating
        }
    }
}

/// Owns the legacy key path as a first responder. A guarded local monitor is
/// retained only as a fallback for the short periods when SwiftUI gives focus
/// to a rail button or dismisses the setup sheet. The two paths are mutually
/// exclusive, so one physical key can never move/activate twice.
struct PlaytestKeyboardInput: NSViewRepresentable {
    let session: PlaytestSession
    let onKey: (PlaytestLegacyKey) -> Void

    func makeNSView(context: Context) -> MonitorView {
        MonitorView(session: session, onKey: onKey)
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.session = session
        nsView.onKey = onKey
        nsView.claimFirstResponderIfNeeded()
    }

    @MainActor
    final class MonitorView: NSView {
        var session: PlaytestSession
        var onKey: (PlaytestLegacyKey) -> Void
        private var fallbackMonitor: Any?
        private var focusTask: Task<Void, Never>?

        init(session: PlaytestSession, onKey: @escaping (PlaytestLegacyKey) -> Void) {
            self.session = session
            self.onKey = onKey
            super.init(frame: .zero)
            wantsLayer = false
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeFallbackMonitor()
            focusTask?.cancel()
            focusTask = nil

            guard let window else { return }
            fallbackMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.keyDown, .keyUp, .leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] event in
                guard let self, event.window === window else { return event }

                if event.type == .leftMouseDown
                    || event.type == .rightMouseDown
                    || event.type == .otherMouseDown {
                    // Clicking a command-rail button may temporarily make the
                    // button first responder. Reclaim the keyboard after its
                    // tracking loop completes; this monitor does not consume
                    // the click.
                    self.claimFirstResponderIfNeeded()
                    return event
                }

                guard self.session.ruleset.usesLegacyKeyboardControls,
                      let key = Self.key(for: event),
                      window.firstResponder !== self,
                      event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
                    return event
                }

                // The direct responder normally receives this event. If a
                // SwiftUI control owns focus instead, consume it here so it
                // cannot fall through to NSResponder's alert beep. Returning
                // nil is safe because the direct path was not eligible.
                if event.type == .keyDown {
                    if self.session.isStarted,
                       !(event.isARepeat && key.isButton),
                       !self.session.isGameOver {
                        self.onKey(key)
                    }
                }
                return nil
            }
            claimFirstResponderIfNeeded()
        }

        isolated deinit {
            focusTask?.cancel()
            removeFallbackMonitor()
        }

        private func removeFallbackMonitor() {
            if let fallbackMonitor {
                NSEvent.removeMonitor(fallbackMonitor)
                self.fallbackMonitor = nil
            }
        }

        override var acceptsFirstResponder: Bool { true }

        override var canBecomeKeyView: Bool { true }

        func claimFirstResponderIfNeeded() {
            guard session.ruleset.usesLegacyKeyboardControls,
                  session.isStarted,
                  let window else { return }
            guard window.firstResponder !== self else { return }

            if focusTask != nil { return }

            // The sheet can finish its first-responder negotiation one run
            // loop after SwiftUI attaches this view. Retry on the main actor;
            // the direct responder path is what prevents AppKit's fallback
            // `noResponderFor:` beep during control tracking.
            focusTask = Task { @MainActor [weak self] in
                defer { self?.focusTask = nil }
                for attempt in 0..<8 {
                    guard let self,
                          let window = self.window,
                          self.session.ruleset.usesLegacyKeyboardControls,
                          self.session.isStarted else { return }
                    if window.firstResponder === self { return }
                    _ = window.makeFirstResponder(self)
                    if window.firstResponder === self { return }
                    if attempt < 7 {
                        try? await Task.sleep(for: .milliseconds(30))
                    }
                }
            }
        }

        override func resignFirstResponder() -> Bool {
            // Once a legacy match is active, keep this catcher in the key
            // view chain even if the user clicks one of the rail buttons.
            // During setup and teardown normal SwiftUI focus changes remain
            // possible.
            if session.ruleset.usesLegacyKeyboardControls, session.isStarted {
                return false
            }
            return super.resignFirstResponder()
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard session.ruleset.usesLegacyKeyboardControls,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  let key = Self.key(for: event) else {
                return super.performKeyEquivalent(with: event)
            }

            // Some AppKit controls ask the first responder to handle a key
            // equivalent before they send keyDown. Claim the event here as
            // well, so the legacy key cannot become an unhandled equivalent
            // (and beep), while still keeping repeat buttons inert.
            if session.isStarted,
               !(event.isARepeat && key.isButton),
               !session.isGameOver {
                onKey(key)
            }
            return true
        }

        private static func key(for event: NSEvent) -> PlaytestLegacyKey? {
            switch event.keyCode {
            case 123: return .left
            case 124: return .right
            case 125: return .down
            case 126: return .up
            default: break
            }

            switch event.charactersIgnoringModifiers?.lowercased() {
            case "z": return .a
            case "x": return .b
            case "s": return .select
            default: return nil
            }
        }

        override func keyDown(with event: NSEvent) {
            guard session.ruleset.usesLegacyKeyboardControls,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  let key = Self.key(for: event) else {
                super.keyDown(with: event)
                return
            }
            // Repeating arrows are useful for cursor travel; repeating A/B or
            // Select would accidentally confirm multiple actions.
            if event.isARepeat, key.isButton { return }
            if session.isStarted, !session.isGameOver {
                onKey(key)
            }
        }

        override func keyUp(with event: NSEvent) {
            guard session.ruleset.usesLegacyKeyboardControls,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  Self.key(for: event) != nil else {
                super.keyUp(with: event)
                return
            }
            // Do not forward the legacy button release to SwiftUI/AppKit.
        }
    }
}

private struct PlaytestLegacyMenuFrame<Content: View>: View {
    let theme: PlaytestLegacyMenuTheme
    let panelTheme: PlaytestStatusTheme
    @ViewBuilder let content: Content

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let pixel = 1 / max(displayScale, 1)
        let shape = PlaytestPanelShape(cornerRadius: panelTheme.cornerRadius)
        let shadow = panelTheme.shadow

        content
            .padding(theme.contentPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(theme.surface)
            .clipShape(shape)
            .overlay {
                frameOverlay(shape: shape, pixel: pixel)
                    .allowsHitTesting(false)
            }
            .shadow(
                color: shadow.color,
                radius: shadow.radius,
                x: shadow.xPixels * pixel,
                y: shadow.yPixels * pixel
            )
            .environment(\.colorScheme, panelTheme.preferredColorScheme)
    }

    @ViewBuilder
    private func frameOverlay(
        shape: PlaytestPanelShape,
        pixel: CGFloat
    ) -> some View {
        ZStack {
            if panelTheme.outerBorderPixels > 0 {
                shape.strokeBorder(
                    panelTheme.outerBorder,
                    style: StrokeStyle(lineWidth: panelTheme.outerBorderPixels * pixel),
                    antialiased: false
                )
            }
            if panelTheme.innerBorderPixels > 0 {
                shape
                    .inset(by: panelTheme.innerBorderInsetPixels * pixel)
                    .strokeBorder(
                        panelTheme.innerBorder,
                        style: StrokeStyle(lineWidth: panelTheme.innerBorderPixels * pixel),
                        antialiased: false
                    )
            }
            if panelTheme == .famicomWars {
                shape
                    .inset(by: 4 * pixel)
                    .strokeBorder(
                        panelTheme.outerBorder,
                        style: StrokeStyle(lineWidth: 2 * pixel),
                        antialiased: false
                    )
                shape
                    .inset(by: 6 * pixel)
                    .strokeBorder(
                        FamicomPPUPalette.black,
                        style: StrokeStyle(lineWidth: pixel),
                        antialiased: false
                    )
            }
        }
    }
}

private struct PlaytestLegacyMenuButtonStyle: ButtonStyle {
    let theme: PlaytestLegacyMenuTheme
    let isSelected: Bool

    @Environment(\.displayScale) private var displayScale
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pixel = 1 / max(displayScale, 1)
        let shape = RoundedRectangle(cornerRadius: theme.rowCornerRadius)
        let isFamicom = switch theme.frame {
        case .famicom: true
        default: false
        }
        // Famicom Wars keeps the cursor visible even when an unavailable
        // command is selected. Its rows are otherwise flat monochrome text;
        // the olive fill is the only per-row selection treatment.
        let selected = isSelected && (isEnabled || isFamicom)

        configuration.label
            .font(theme.menuFont)
            .foregroundStyle(selected ? theme.activeText : theme.text)
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, minHeight: theme.rowHeight, alignment: .leading)
            .background {
                shape.fill(
                    selected
                        ? theme.activeSurface
                        : (isEnabled ? theme.rowSurface : theme.disabledSurface)
                )
            }
            .overlay(alignment: .top) {
                if !isFamicom {
                    Rectangle()
                        .fill(theme.innerBorder.opacity(selected ? 0.9 : 0.55))
                        .frame(height: pixel)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottom) {
                if !isFamicom {
                    Rectangle()
                        .fill(theme.secondaryBorder.opacity(selected ? 0.95 : 0.72))
                        .frame(height: pixel)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if !isFamicom {
                    shape.strokeBorder(
                        selected ? theme.innerBorder : theme.border.opacity(0.68),
                        style: StrokeStyle(lineWidth: pixel),
                        antialiased: false
                    )
                    .allowsHitTesting(false)
                }
            }
            .opacity(isEnabled ? 1 : 0.58)
            .offset(y: configuration.isPressed ? pixel : 0)
            .contentShape(shape)
    }
}

private struct PlaytestLegacyMenuIcon: View {
    let action: PlaytestLegacyAction?
    let theme: PlaytestLegacyMenuTheme

    var body: some View {
        ZStack {
            Rectangle()
                .fill(theme.secondaryBorder.opacity(0.42))
            Rectangle()
                .stroke(theme.border.opacity(0.88), lineWidth: 1)
            Text(glyph)
                .font(theme.detailFont)
                .foregroundStyle(theme.text)
                .minimumScaleFactor(0.6)
        }
        .frame(width: 21, height: 21)
    }

    private var glyph: String {
        guard let action else { return "+" }
        return switch action {
        case .build: "B"
        case .stat: "I"
        case .move: "M"
        case .attack: "A"
        case .capture: "C"
        case .load: "L"
        case .unload: "U"
        case .join: "J"
        case .resupply: "S"
        case .surface: "D"
        case .stealth: "C"
        case .detonate: "X"
        case .flare: "F"
        case .silo: "T"
        case .wait: "W"
        case .endTurn: "E"
        case .surrender: "S"
        }
    }
}

/// Cartridge-era command rail. The map remains the visual focus, while the
/// left rail makes every legal action discoverable without a modern inspector
/// click target being required.
struct PlaytestLegacyCommandRail: View {
    /// Reserve the largest of the per-cartridge rails plus its 16 px outer
    /// breathing room. The rail overlays the map, so this never changes the
    /// map's centering math.
    static let width: CGFloat = 284

    let session: PlaytestSession
    /// The rail overlays the map, so this is only used to cap a compact menu
    /// on short playtest windows; it never participates in map centering.
    let availableHeight: CGFloat
    @Binding var mode: PlaytestLegacyMenuMode
    @Binding var selection: Int
    @Binding var buildSelection: Int
    let onAction: (PlaytestLegacyAction) -> Void
    let onBuild: (Int) -> Void

    private var theme: PlaytestStatusTheme {
        PlaytestStatusTheme(tileset: session.map.tileset)
    }

    private var menuTheme: PlaytestLegacyMenuTheme {
        theme.legacyMenu
    }

    private var actions: [PlaytestLegacyAction] {
        PlaytestLegacyActionCatalog.actions(for: session)
    }

    private var commandMenuWidth: CGFloat {
        let fallbackFont = NSFont.systemFont(ofSize: theme.legacyMenuFontPointSize)
        let font = NSFont(
            name: theme.legacyMenuFontFamily,
            size: theme.legacyMenuFontPointSize
        ) ?? fallbackFont
        let labels = actions.map {
            PlaytestLegacyActionCatalog.title(for: $0, session: session)
        } + [menuTheme.title]
        let longestText = labels.map { width(of: $0, font: font) }.max() ?? 0
        let twoSpaces = width(of: "  ", font: font)
        let markerColumn: CGFloat = 10 + (menuTheme.showsActionIcons ? 21 : 0)
        let columnGaps: CGFloat = menuTheme.showsActionIcons ? 12 : 6
        let buttonPadding: CGFloat = 14
        let framePadding: CGFloat = 16

        // The two spaces are the only text-derived breathing room. Marker,
        // icon, button, and frame columns are added separately so the
        // longest label remains fully visible without a fixed wide rail.
        let textWidth = longestText + twoSpaces
        let structuralWidth = markerColumn + columnGaps + buttonPadding + framePadding
        let totalWidth = textWidth + structuralWidth
        return ceil(totalWidth)
    }

    private func width(of text: String, font: NSFont) -> CGFloat {
        NSString(string: text).size(withAttributes: [.font: font]).width
    }

    private var commandRowsHeight: CGFloat {
        guard !actions.isEmpty else { return menuTheme.rowHeight }
        return CGFloat(actions.count) * menuTheme.rowHeight
            + CGFloat(max(0, actions.count - 1)) * menuTheme.rowSpacing
    }

    /// The title row, divider, row spacing, and the menu frame's vertical
    /// padding. Command mode intentionally has no footer, so this is the only
    /// chrome added to the command rows.
    private var commandMenuChromeHeight: CGFloat {
        menuTheme.contentPadding * 2 + 26 + 1 + 16
    }

    private var commandMenuHeight: CGFloat {
        let desired = commandMenuChromeHeight + commandRowsHeight
        let maximum = max(commandMenuChromeHeight, availableHeight - 32)
        return min(desired, maximum)
    }

    private var commandScrollHeight: CGFloat {
        max(menuTheme.rowHeight, commandMenuHeight - commandMenuChromeHeight)
    }

    var body: some View {
        menuFrame
        .frame(width: mode == .build ? menuTheme.railWidth : commandMenuWidth)
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var menuFrame: some View {
        PlaytestLegacyMenuFrame(theme: menuTheme, panelTheme: theme) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(mode == .build ? "PRODUCTION" : menuTheme.title)
                        .font(menuTheme.titleFont)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                    Spacer(minLength: 4)
                }

                Rectangle()
                    .fill(menuTheme.secondaryBorder)
                    .frame(height: 1)
                    .opacity(0.86)

                if mode == .build {
                    ScrollView(.vertical, showsIndicators: false) {
                        buildMenu
                    }
                    .frame(maxHeight: .infinity, alignment: .top)

                    Rectangle()
                        .fill(menuTheme.secondaryBorder)
                        .frame(height: 1)
                        .opacity(0.84)

                    Text("Z BUILD   X BACK")
                        .font(menuTheme.detailFont)
                        .foregroundStyle(menuTheme.secondaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.58)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        commandMenu
                    }
                    .frame(height: commandScrollHeight, alignment: .top)
                }
            }
        }
        .modifier(LegacyMenuHeight(mode: mode, commandMenuHeight: commandMenuHeight))
    }

    private var commandMenu: some View {
        VStack(alignment: .leading, spacing: menuTheme.rowSpacing) {
            ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                Button {
                    selection = index
                    onAction(action)
                } label: {
                    HStack(spacing: 6) {
                        Text(mode == .commands && selection == index ? menuTheme.selectionMarker : " ")
                            .font(menuTheme.detailFont)
                            .frame(width: 10, alignment: .center)
                        if menuTheme.showsActionIcons {
                            PlaytestLegacyMenuIcon(action: action, theme: menuTheme)
                        }
                        Text(PlaytestLegacyActionCatalog.title(for: action, session: session))
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(
                    PlaytestLegacyMenuButtonStyle(
                        theme: menuTheme,
                        isSelected: mode == .commands && selection == index
                    )
                )
                .disabled(!PlaytestLegacyActionCatalog.isEnabled(action, session: session))
                .accessibilityValue(PlaytestLegacyActionCatalog.isEnabled(action, session: session) ? "Available" : "Unavailable")
            }
        }
    }

    private var buildMenu: some View {
        VStack(alignment: .leading, spacing: menuTheme.rowSpacing) {
            Button {
                mode = .commands
                selection = 0
            } label: {
                HStack(spacing: 6) {
                    Text(" ")
                        .frame(width: 10)
                    if menuTheme.showsActionIcons {
                        PlaytestLegacyMenuIcon(action: nil, theme: menuTheme)
                    }
                    Text("BACK")
                }
            }
            .buttonStyle(
                PlaytestLegacyMenuButtonStyle(
                    theme: menuTheme,
                    isSelected: false
                )
            )

            if session.productionOptions.isEmpty {
                Text("SELECT AN OWNED PRODUCTION PROPERTY")
                    .font(menuTheme.detailFont)
                    .foregroundStyle(menuTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 5)
            } else {
                ForEach(Array(session.productionOptions.enumerated()), id: \.offset) { index, option in
                    Button {
                        buildSelection = index
                        onBuild(index)
                    } label: {
                        HStack(spacing: 6) {
                            Text(buildSelection == index ? menuTheme.selectionMarker : " ")
                                .font(menuTheme.detailFont)
                                .frame(width: 10, alignment: .center)
                            if menuTheme.showsActionIcons {
                                PlaytestLegacyMenuIcon(action: .build, theme: menuTheme)
                            }
                            Text(option.label.uppercased())
                                .lineLimit(1)
                                .minimumScaleFactor(0.54)
                            Spacer(minLength: 2)
                            Text(PlaytestRulebook.formatFunds(option.cost))
                                .font(menuTheme.detailFont)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(
                        PlaytestLegacyMenuButtonStyle(
                            theme: menuTheme,
                            isSelected: buildSelection == index
                        )
                    )
                    .disabled(!session.canBuild(option))
                }
            }
        }
    }
}

private struct LegacyMenuHeight: ViewModifier {
    let mode: PlaytestLegacyMenuMode
    let commandMenuHeight: CGFloat

    func body(content: Content) -> some View {
        if mode == .build {
            content.frame(maxHeight: .infinity, alignment: .top)
        } else {
            content.frame(height: commandMenuHeight, alignment: .top)
        }
    }
}
