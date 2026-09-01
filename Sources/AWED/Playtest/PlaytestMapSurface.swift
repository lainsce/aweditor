import AppKit
import SwiftUI
import AWEDCore


struct PlaytestMapSurface: View {
    let session: PlaytestSession
    let previewModel: EditorModel
    let atlas: SpriteAtlas
    let mapSize: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedCameraFocusPoint: GridPoint?

    private static let cameraStepNanoseconds: UInt64 = 55_000_000

    /// The playtest map is a camera viewport rather than a document canvas.
    /// Follow the most immediate point of activity first, then fall back to
    /// the cartridge cursor or the current selection when an action is idle.
    private var cameraFocusPoint: GridPoint? {
        session.cpuMovementPath.last
            // During a legacy CPU turn the cartridge cursor is the actual
            // point of action. Prefer it once a stepped route has finished so
            // clearing the render-only path cannot snap the camera back to the
            // movement origin.
            ?? (session.activeArmyIsCPU && session.ruleset.usesLegacyKeyboardControls ? session.cursorPoint : nil)
            ?? (session.activeArmyIsCPU ? session.cpuActionPoint : nil)
            ?? (session.activeArmyIsCPU ? session.selectedPoint : nil)
            ?? session.playerMovementPath.last
            ?? previewModel.pointerCell
            // AWDS/AWDR use pointer interaction and do not render the
            // cartridge cursor. Do not let the legacy cursor's first-unit
            // fallback pan those maps away from their centered initial view.
            ?? (session.ruleset.usesLegacyKeyboardControls ? session.cursorPoint : nil)
            ?? session.selectedPoint
    }

    var body: some View {
        let tileSize = MapCanvasMetrics.tileSize
        let frameTheme = PlaytestFrameTheme.playtest(for: session.map.tileset)
        let woodPadding = MapCanvasMetrics.woodPadding(for: frameTheme)
        let boardSize = CGSize(
            width: mapSize.width + (woodPadding * 2),
            height: mapSize.height + (woodPadding * 2) + MapCanvasMetrics.bottomWallHeight(for: frameTheme)
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

            let cameraOffset = cameraOffset(
                viewportSize: proxy.size,
                contentSize: contentSize,
                boardOrigin: boardOrigin,
                woodPadding: woodPadding,
                focusPoint: displayedCameraFocusPoint ?? cameraFocusPoint
            )

            ZStack(alignment: .topLeading) {
                Color.clear
                    .frame(width: proxy.size.width, height: proxy.size.height)

                ZStack(alignment: .topLeading) {
                    MapCanvasBoard(
                        model: previewModel,
                        atlas: atlas,
                        mapOverride: session.displayMapForPlaytest,
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
                            x: boardOrigin.x + MapCanvasMetrics.parchmentPadding + woodPadding,
                            y: boardOrigin.y + MapCanvasMetrics.parchmentPadding + woodPadding
                        )

                    PlaytestInteractionLayer(
                        session: session,
                        previewModel: previewModel,
                        atlas: atlas,
                        tileSize: tileSize
                    )
                        .frame(width: mapSize.width, height: mapSize.height)
                        .offset(
                            x: boardOrigin.x + MapCanvasMetrics.parchmentPadding + woodPadding,
                            y: boardOrigin.y + MapCanvasMetrics.parchmentPadding + woodPadding
                        )
                }
                .frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading)
                .offset(cameraOffset)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
        }
        .task(id: cameraFocusPoint) {
            await advanceCamera(to: cameraFocusPoint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Move the camera target through the grid one cardinal cell at a time.
    /// This keeps a long cursor jump or a CPU action from cutting directly to
    /// the endpoint, while the map itself remains a clipped, non-scrollable
    /// viewport.
    @MainActor
    private func advanceCamera(to target: GridPoint?) async {
        guard !Task.isCancelled else { return }
        guard let target else {
            displayedCameraFocusPoint = nil
            return
        }

        guard var current = displayedCameraFocusPoint else {
            displayedCameraFocusPoint = target
            return
        }
        guard current != target else { return }

        while current != target {
            guard !Task.isCancelled else { return }
            current = cameraStep(from: current, toward: target)
            displayedCameraFocusPoint = current
            guard !reduceMotion else { continue }
            try? await Task.sleep(nanoseconds: Self.cameraStepNanoseconds)
        }
    }

    private func cameraStep(from current: GridPoint, toward target: GridPoint) -> GridPoint {
        current.x != target.x ? horizontalCameraStep(from: current, toward: target) : verticalCameraStep(from: current, toward: target)
    }

    private func horizontalCameraStep(from current: GridPoint, toward target: GridPoint) -> GridPoint {
        GridPoint(x: current.x + (target.x > current.x ? 1 : -1), y: current.y)
    }

    private func verticalCameraStep(from current: GridPoint, toward target: GridPoint) -> GridPoint {
        GridPoint(x: current.x, y: current.y + (target.y > current.y ? 1 : -1))
    }

    private func cameraOffset(
        viewportSize: CGSize,
        contentSize: CGSize,
        boardOrigin: CGPoint,
        woodPadding: CGFloat,
        focusPoint: GridPoint?
    ) -> CGSize {
        let desired = focusPoint.map {
            desiredCameraOffset(for: $0, viewportSize: viewportSize, boardOrigin: boardOrigin, woodPadding: woodPadding)
        } ?? CGSize(
            width: (viewportSize.width - contentSize.width) / 2,
            height: (viewportSize.height - contentSize.height) / 2
        )
        return clampedCameraOffset(desired, viewportSize: viewportSize, contentSize: contentSize)
    }

    private func desiredCameraOffset(
        for focusPoint: GridPoint,
        viewportSize: CGSize,
        boardOrigin: CGPoint,
        woodPadding: CGFloat
    ) -> CGSize {
        let tileOrigin = MapCanvasMetrics.tileOrigin(
            x: focusPoint.x,
            y: focusPoint.y,
            tileSize: MapCanvasMetrics.tileSize,
            staggered: session.isStaggeredGrid
        )
        let focus = CGPoint(
            x: boardOrigin.x + MapCanvasMetrics.parchmentPadding + woodPadding + tileOrigin.x + (MapCanvasMetrics.tileSize / 2),
            y: boardOrigin.y + MapCanvasMetrics.parchmentPadding + woodPadding + tileOrigin.y + (MapCanvasMetrics.tileSize / 2)
        )
        return CGSize(width: (viewportSize.width / 2) - focus.x, height: (viewportSize.height / 2) - focus.y)
    }

    private func clampedCameraOffset(_ desired: CGSize, viewportSize: CGSize, contentSize: CGSize) -> CGSize {
        let minimumX = min(0, viewportSize.width - contentSize.width)
        let minimumY = min(0, viewportSize.height - contentSize.height)
        return CGSize(width: min(max(desired.width, minimumX), 0), height: min(max(desired.height, minimumY), 0))
    }
}

/// Receives secondary clicks without replacing the SwiftUI primary-tap
/// gesture. The editor uses the same local-monitor approach for its map
/// canvas, which also lets us suppress the default context menu here.
