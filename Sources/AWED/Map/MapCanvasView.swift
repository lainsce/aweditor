import SwiftUI
import AWEDCore


enum MapCanvasMetrics {
    static let tileSize: CGFloat = 28
    /// Tall building/extra sprites use one tile of artwork above their anchor
    /// cell. Keep that bleed available above row zero without changing the
    /// map's tile origin or its wood-frame dimensions.
    static let tallSpriteOverflow: CGFloat = tileSize
    static let woodPadding: CGFloat = 10
    static let bottomWallHeight: CGFloat = 20
    static let parchmentPadding: CGFloat = 12

    /// Keep a two-pixel breathing gap between a flat frame's innermost rule
    /// and the map. The inset includes the inspector-style border stack, so
    /// the rule itself never ends up painted over the first map cells.
    static func woodPadding(for frameTheme: PlaytestFrameTheme) -> CGFloat {
        guard case let .inspector(statusTheme) = frameTheme.flatWoodBorderStyle else {
            return woodPadding
        }

        let outerExtent = statusTheme.outerBorderPixels
        let innerExtent = statusTheme.innerBorderPixels > 0
            ? statusTheme.innerBorderInsetPixels + statusTheme.innerBorderPixels
            : 0
        let famicomExtent: CGFloat = statusTheme == .famicomWars ? 6 + 1 : 0
        return max(outerExtent, innerExtent, famicomExtent) + 2
    }

    static func bottomWallHeight(for frameTheme: PlaytestFrameTheme) -> CGFloat {
        frameTheme.usesFlatWoodBorder ? 0 : bottomWallHeight
    }

    /// Game Boy Wars lays out its logical cells as horizontally staggered
    /// four-sided spaces. Keep this decision in one geometry helper so the
    /// editor, hit testing, playtest, and screenshot renderer cannot drift
    /// apart when a GB Wars palette is selected.
    static func isStaggeredGB(map: MapState, palette: SpritePalette? = nil) -> Bool {
        if map.tileset.isGameBoyWarsFamily { return true }
        if let palette, palette.isGameBoyWarsFamily { return true }
        return false
    }

    static func mapPixelSize(width: Int, height: Int, tileSize: CGFloat, staggered: Bool) -> CGSize {
        CGSize(
            width: CGFloat(width) * tileSize + (staggered && height > 1 ? tileSize / 2 : 0),
            height: CGFloat(height) * tileSize
        )
    }

    static func tileOrigin(x: Int, y: Int, tileSize: CGFloat, staggered: Bool) -> CGPoint {
        CGPoint(
            x: CGFloat(x) * tileSize + (staggered && y % 2 != 0 ? tileSize / 2 : 0),
            y: CGFloat(y) * tileSize
        )
    }

    static func tileRect(x: Int, y: Int, tileSize: CGFloat, staggered: Bool, inset: CGFloat = 0) -> CGRect {
        CGRect(
            origin: tileOrigin(x: x, y: y, tileSize: tileSize, staggered: staggered),
            size: CGSize(width: tileSize, height: tileSize)
        ).insetBy(dx: inset, dy: inset)
    }

    static func tilePath(in rect: CGRect, staggered _: Bool) -> Path {
        // The stagger belongs to the row origin, not to the tile shape.
        // GB Wars uses ordinary four-sided cells with an alternating
        // half-cell horizontal offset between rows.
        Path(rect)
    }
}
struct MapCanvasBoard: View {
    let model: EditorModel
    let atlas: SpriteAtlas
    /// Optional read-only map source for live playtest rendering. The editor
    /// keeps using `model.map`; playtest can supply the session snapshot
    /// directly so a tile-by-tile movement step cannot wait for a secondary
    /// model-sync callback before the unit sprite changes.
    let mapOverride: MapState?
    /// Playtest renders the board as a read-only backdrop. Its interaction
    /// layer owns pointer conversion there, so the editor's local event
    /// monitor must not compete for the same mouse events.
    let interactionEnabled: Bool
    let frameTheme: PlaytestFrameTheme

    init(
        model: EditorModel,
        atlas: SpriteAtlas,
        mapOverride: MapState? = nil,
        interactionEnabled: Bool = true,
        frameTheme: PlaytestFrameTheme = .editor
    ) {
        self.model = model
        self.atlas = atlas
        self.mapOverride = mapOverride
        self.interactionEnabled = interactionEnabled
        self.frameTheme = frameTheme
    }

    var body: some View {
        let renderMap = mapOverride ?? model.map
        let mapHeight = CGFloat(renderMap.height) * MapCanvasMetrics.tileSize
        let staggered = MapCanvasMetrics.isStaggeredGB(map: renderMap, palette: model.renderPalette)
        let mapSize = MapCanvasMetrics.mapPixelSize(
            width: renderMap.width,
            height: renderMap.height,
            tileSize: MapCanvasMetrics.tileSize,
            staggered: staggered
        )
        let woodPadding = MapCanvasMetrics.woodPadding(for: frameTheme)
        let boardWidth = mapSize.width + (woodPadding * 2)
        let boardHeight = mapHeight + (woodPadding * 2)

        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                MapCanvasView(
                    model: model,
                    atlas: atlas,
                    tileSize: Double(MapCanvasMetrics.tileSize),
                    topOverflow: 0,
                    interactionEnabled: interactionEnabled,
                    mapOverride: mapOverride
                )
                .offset(
                    x: woodPadding,
                    y: woodPadding
                )
            }
            .frame(
                width: boardWidth,
                height: boardHeight,
                alignment: .topLeading
            )
            .background {
                if case let .inspector(statusTheme) = frameTheme.flatWoodBorderStyle {
                    Rectangle()
                        .fill(statusTheme.surface)
                } else if frameTheme.usesFlatWoodBorder {
                    Rectangle()
                        .fill(frameTheme.woodGradient.first ?? frameTheme.woodDeep)
                } else {
                    MapWoodSurface(theme: frameTheme)
                }
            }
            .overlay {
                if case let .inspector(statusTheme) = frameTheme.flatWoodBorderStyle {
                    MapInspectorBorder(theme: statusTheme)
                } else if !frameTheme.usesFlatWoodBorder {
                    MapWoodBorderOverlay(theme: frameTheme)
                }
            }
            .overlay {
                if !frameTheme.usesFlatWoodBorder {
                    MapWoodDepthOverlay(theme: frameTheme)
                }
            }
            // Keep this in an overlay so its extra drawing height does not
            // change the board's measured height or push the lower wall away.
            .overlay(alignment: .topLeading) {
                MapCanvasTallSpriteOverflow(
                    model: model,
                    atlas: atlas,
                    tileSize: MapCanvasMetrics.tileSize,
                    mapOverride: mapOverride
                )
                .offset(
                    x: woodPadding,
                    y: woodPadding - MapCanvasMetrics.tallSpriteOverflow
                )
                .zIndex(2)
            }

            if !frameTheme.usesFlatWoodBorder {
                MapWoodLowerWall(theme: frameTheme)
                    .frame(width: boardWidth, height: MapCanvasMetrics.bottomWallHeight)
            }
        }
        .frame(width: boardWidth)
        .shadow(
            color: frameTheme.usesFlatWoodBorder ? .clear : Color.black.opacity(0.22),
            radius: frameTheme.usesFlatWoodBorder ? 0 : 10,
            y: frameTheme.usesFlatWoodBorder ? 0 : 5
        )
    }
}
