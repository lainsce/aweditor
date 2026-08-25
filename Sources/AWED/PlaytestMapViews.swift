import AppKit
import SwiftUI
import AWEDCore

struct PlaytestMapColumn: View {
    let session: PlaytestSession
    let previewModel: EditorModel
    let atlas: SpriteAtlas
    let mapSize: CGSize
    let showDayBanner: Bool
    let dayBannerSequence: Int

    var body: some View {
        ZStack(alignment: .center) {
            PlaytestMapSurface(
                session: session,
                previewModel: previewModel,
                atlas: atlas,
                mapSize: mapSize
            )

            if showDayBanner {
                PlaytestDayBanner(
                    day: session.turn,
                    army: session.activeArmy,
                    tileset: session.map.tileset
                )
                .id(dayBannerSequence)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PlaytestDayBanner: View {
    let day: Int
    let army: Int
    let tileset: Tileset

    private var armyColor: Color {
        if tileset == .daysOfRuin, army == AWConstants.armyBlackHole {
            return Color(white: 0.12)
        }

        if tileset.isGameBoyWarsFamily {
            switch army {
            case AWConstants.armyOrangeStar:
                return Color(red: 0.78, green: 0.12, blue: 0.12)
            case AWConstants.armyBlueMoon:
                return Color(white: 0.82)
            default:
                break
            }
        }

        switch army {
        case AWConstants.armyOrangeStar:
            return Color(red: 0.94, green: 0.40, blue: 0.12)
        case AWConstants.armyBlueMoon:
            return Color(red: 0.18, green: 0.47, blue: 0.86)
        case AWConstants.armyGreenEarth:
            return Color(red: 0.22, green: 0.62, blue: 0.27)
        case AWConstants.armyYellowComet:
            return Color(red: 0.92, green: 0.70, blue: 0.08)
        case AWConstants.armyBlackHole:
            return Color(red: 0.48, green: 0.30, blue: 0.72)
        default:
            return .secondary
        }
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.48))

            Rectangle()
                .fill(
                    RadialGradient(
                        colors: [
                            armyColor.opacity(0.25),
                            armyColor.opacity(0.08)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 420
                    )
                )

            Text("Day \(day)")
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: armyColor.opacity(0.35), radius: 8, y: 2)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.40), value: day)
        }
        .frame(maxWidth: .infinity, minHeight: 68, maxHeight: 68)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(armyColor.opacity(0.25))
                .frame(height: 4)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(armyColor.opacity(0.25))
                .frame(height: 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Day \(day)")
    }
}

private struct PlaytestMapSurface: View {
    let session: PlaytestSession
    let previewModel: EditorModel
    let atlas: SpriteAtlas
    let mapSize: CGSize

    var body: some View {
        let tileSize = MapCanvasMetrics.tileSize
        let frameTheme = PlaytestFrameTheme.playtest(for: session.map.tileset)
        let boardSize = CGSize(
            width: mapSize.width + (MapCanvasMetrics.woodPadding * 2),
            height: mapSize.height + (MapCanvasMetrics.woodPadding * 2) + MapCanvasMetrics.bottomWallHeight
        )
        let minimumContentSize = CGSize(
            width: boardSize.width + (MapCanvasMetrics.parchmentPadding * 2),
            height: boardSize.height + (MapCanvasMetrics.parchmentPadding * 2)
        )

        GeometryReader { proxy in
            let contentSize = CGSize(
                width: max(proxy.size.width, minimumContentSize.width),
                height: max(proxy.size.height, minimumContentSize.height)
            )
            let boardOrigin = CGPoint(
                x: (contentSize.width - minimumContentSize.width) / 2,
                y: (contentSize.height - minimumContentSize.height) / 2
            )

            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    Color.clear

                    MapCanvasBoard(
                        model: previewModel,
                        atlas: atlas,
                        interactionEnabled: false,
                        frameTheme: frameTheme
                    )
                        .offset(
                            x: boardOrigin.x + MapCanvasMetrics.parchmentPadding,
                            y: boardOrigin.y + MapCanvasMetrics.parchmentPadding
                        )
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)

                    PlaytestWeatherOverlay(
                        weather: session.weather,
                        mapSize: mapSize
                    )
                        .frame(width: mapSize.width, height: mapSize.height)
                        .offset(
                            x: boardOrigin.x + MapCanvasMetrics.parchmentPadding + MapCanvasMetrics.woodPadding,
                            y: boardOrigin.y + MapCanvasMetrics.parchmentPadding + MapCanvasMetrics.woodPadding
                        )

                    PlaytestInteractionLayer(
                        session: session,
                        previewModel: previewModel,
                        tileSize: tileSize
                    )
                        .frame(width: mapSize.width, height: mapSize.height)
                        .offset(
                            x: boardOrigin.x + MapCanvasMetrics.parchmentPadding + MapCanvasMetrics.woodPadding,
                            y: boardOrigin.y + MapCanvasMetrics.parchmentPadding + MapCanvasMetrics.woodPadding
                        )
                }
                .frame(width: contentSize.width, height: contentSize.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Receives secondary clicks without replacing the SwiftUI primary-tap
/// gesture. The editor uses the same local-monitor approach for its map
/// canvas, which also lets us suppress the default context menu here.
struct PlaytestMapInput: NSViewRepresentable {
    let session: PlaytestSession
    let previewModel: EditorModel
    let tileSize: CGFloat

    func makeNSView(context: Context) -> MonitorView {
        MonitorView(session: session, previewModel: previewModel, tileSize: tileSize)
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.session = session
        nsView.previewModel = previewModel
        nsView.tileSize = tileSize
    }

    @MainActor
    final class MonitorView: NSView {
        var session: PlaytestSession
        var previewModel: EditorModel
        var tileSize: CGFloat
        private var eventMonitor: Any?

        init(session: PlaytestSession, previewModel: EditorModel, tileSize: CGFloat) {
            self.session = session
            self.previewModel = previewModel
            self.tileSize = tileSize
            super.init(frame: .zero)
            wantsLayer = false
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeEventMonitor()
            guard window != nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.rightMouseDown, .otherMouseDown]
            ) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        isolated deinit { removeEventMonitor() }

        private func removeEventMonitor() {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let window, event.window === window else { return event }
            let location = convert(event.locationInWindow, from: nil)
            guard bounds.contains(location) else { return event }
            guard event.type == .rightMouseDown || event.buttonNumber == 2 else { return event }

            // SwiftUI's interaction layer and the editor both use a top-left
            // origin. Keep secondary-click hit testing in that same coordinate
            // space; inverting Y here made right-click previews select the
            // mirrored row and made the marker appear upside-down.
            let y = Int(floor(location.y / tileSize))
            let rowOffset = session.isStaggeredGrid && y % 2 != 0 ? tileSize / 2 : 0
            let point = GridPoint(
                x: Int(floor((location.x - rowOffset) / tileSize)),
                y: y
            )
            previewModel.updatePointer(point)
            session.handleSecondaryTap(point)
            return nil
        }
    }
}
