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
    /// Playtest renders the board as a read-only backdrop. Its interaction
    /// layer owns pointer conversion there, so the editor's local event
    /// monitor must not compete for the same mouse events.
    let interactionEnabled: Bool

    init(model: EditorModel, atlas: SpriteAtlas, interactionEnabled: Bool = true) {
        self.model = model
        self.atlas = atlas
        self.interactionEnabled = interactionEnabled
    }

    var body: some View {
        let mapHeight = CGFloat(model.map.height) * MapCanvasMetrics.tileSize
        let staggered = MapCanvasMetrics.isStaggeredGB(map: model.map, palette: model.renderPalette)
        let mapSize = MapCanvasMetrics.mapPixelSize(
            width: model.map.width,
            height: model.map.height,
            tileSize: MapCanvasMetrics.tileSize,
            staggered: staggered
        )
        let boardWidth = mapSize.width + (MapCanvasMetrics.woodPadding * 2)
        let boardHeight = mapHeight + (MapCanvasMetrics.woodPadding * 2)

        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                MapCanvasView(
                    model: model,
                    atlas: atlas,
                    tileSize: Double(MapCanvasMetrics.tileSize),
                    topOverflow: 0,
                    interactionEnabled: interactionEnabled
                )
                .offset(
                    x: MapCanvasMetrics.woodPadding,
                    y: MapCanvasMetrics.woodPadding
                )
            }
                .frame(
                    width: boardWidth,
                height: boardHeight,
                alignment: .topLeading
            )
            .background {
                MapWoodSurface()
            }
            .overlay {
                MapWoodBorderOverlay()
            }
            .overlay {
                MapWoodDepthOverlay()
            }
            // Keep this in an overlay so its extra drawing height does not
            // change the board's measured height or push the lower wall away.
            .overlay(alignment: .topLeading) {
                MapCanvasTallSpriteOverflow(
                    model: model,
                    atlas: atlas,
                    tileSize: MapCanvasMetrics.tileSize
                )
                .offset(
                    x: MapCanvasMetrics.woodPadding,
                    y: MapCanvasMetrics.woodPadding - MapCanvasMetrics.tallSpriteOverflow
                )
                .zIndex(2)
            }

            MapWoodLowerWall()
                .frame(width: boardWidth, height: MapCanvasMetrics.bottomWallHeight)
        }
        .frame(width: boardWidth)
        .shadow(color: Color.black.opacity(0.22), radius: 10, y: 5)
    }
}

private struct MapCanvasTallSpriteOverflow: View {
    let model: EditorModel
    let atlas: SpriteAtlas
    let tileSize: CGFloat

    var body: some View {
        let staggered = MapCanvasMetrics.isStaggeredGB(map: model.map, palette: model.renderPalette)
        let mapSize = MapCanvasMetrics.mapPixelSize(
            width: model.map.width,
            height: model.map.height,
            tileSize: tileSize,
            staggered: staggered
        )
        Canvas { context, _ in
            let map = model.map
            for x in 0..<map.width {
                let origin = MapCanvasMetrics.tileOrigin(x: x, y: 0, tileSize: tileSize, staggered: staggered)
                let rect = CGRect(origin: origin, size: CGSize(width: tileSize, height: tileSize))
                drawSprite(map.backgroundDrawElement(atX: x, y: 0), at: rect, context: &context)
                drawSprite(map.foregroundElement(atX: x, y: 0), at: rect, context: &context)
            }
        }
        .frame(
            width: mapSize.width,
            height: tileSize * 2,
            alignment: .topLeading
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawSprite(_ element: Element, at rect: CGRect, context: inout GraphicsContext) {
        guard model.renderPalette.doubleHeight(for: element),
              element.isBuilding || element.isExtra || element.simplified == .terrainMountain,
              let image = atlas.image(for: element, palette: model.renderPalette) else { return }
        context.draw(
            context.resolve(image),
            in: CGRect(x: rect.minX, y: 0, width: rect.width, height: rect.height * 2)
        )
    }
}

private struct MapWoodBorderOverlay: View {
    var body: some View {
        MapWoodSurface()
            .mask {
                MapWoodBorderShape()
                    .fill(.white, style: FillStyle(eoFill: true))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct MapWoodBorderShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRect(
            rect.insetBy(
                dx: MapCanvasMetrics.woodPadding,
                dy: MapCanvasMetrics.woodPadding
            )
        )
        return path
    }
}

private struct MapWoodDepthOverlay: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let highlightOpacity = reduceTransparency ? 0.30 : 0.56
        let shadowOpacity = reduceTransparency ? 0.36 : 0.66

        ZStack {
            Rectangle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.78, blue: 0.38).opacity(highlightOpacity),
                            Color(red: 0.48, green: 0.22, blue: 0.07).opacity(0.78),
                            Color(red: 0.12, green: 0.045, blue: 0.012).opacity(shadowOpacity)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 3
                )

            Rectangle()
                .strokeBorder(Color.black.opacity(shadowOpacity), lineWidth: 2)
                .padding(MapCanvasMetrics.woodPadding - 2)
                .shadow(color: Color.black.opacity(reduceTransparency ? 0.16 : 0.34), radius: 4, y: 2)

            Rectangle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(highlightOpacity),
                            .clear,
                            Color.black.opacity(shadowOpacity)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 2
                )
                .padding(MapCanvasMetrics.woodPadding - 5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct MapWoodLowerWall: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Canvas { context, size in
            let bevelHeight = min(CGFloat(6), size.height * 0.35)
            let sideSlope = min(CGFloat(12), size.width * 0.08)
            let lowerInset = min(CGFloat(20), sideSlope * 1.6)
            let base = Color(red: 0.43, green: 0.18, blue: 0.055)
            let deep = Color(red: 0.16, green: 0.055, blue: 0.016)
            let highlight = Color(red: 0.98, green: 0.67, blue: 0.26)
            let opacity = reduceTransparency ? 0.72 : 1

            var frontFace = Path()
            frontFace.move(to: CGPoint(x: sideSlope, y: bevelHeight))
            frontFace.addLine(to: CGPoint(x: size.width - sideSlope, y: bevelHeight))
            frontFace.addLine(to: CGPoint(x: size.width - lowerInset, y: size.height))
            frontFace.addLine(to: CGPoint(x: lowerInset, y: size.height))
            frontFace.closeSubpath()
            context.fill(
                frontFace,
                with: .linearGradient(
                    Gradient(colors: [
                        base.opacity(opacity),
                        deep.opacity(opacity)
                    ]),
                    startPoint: CGPoint(x: 0, y: bevelHeight),
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )

            var angledTop = Path()
            angledTop.move(to: CGPoint(x: 0, y: 0))
            angledTop.addLine(to: CGPoint(x: size.width, y: 0))
            angledTop.addLine(to: CGPoint(x: size.width - sideSlope, y: bevelHeight))
            angledTop.addLine(to: CGPoint(x: sideSlope, y: bevelHeight))
            angledTop.closeSubpath()
            context.fill(
                angledTop,
                with: .linearGradient(
                    Gradient(colors: [
                        highlight.opacity(reduceTransparency ? 0.44 : 0.80),
                        base.opacity(opacity)
                    ]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: bevelHeight)
                )
            )

            var topEdge = Path()
            topEdge.move(to: CGPoint(x: 0, y: 0.5))
            topEdge.addLine(to: CGPoint(x: size.width, y: 0.5))
            context.stroke(
                topEdge,
                with: .color(highlight.opacity(reduceTransparency ? 0.34 : 0.62)),
                style: StrokeStyle(lineWidth: 1)
            )

            var frontEdge = Path()
            frontEdge.move(to: CGPoint(x: sideSlope, y: bevelHeight))
            frontEdge.addLine(to: CGPoint(x: size.width - sideSlope, y: bevelHeight))
            context.stroke(
                frontEdge,
                with: .color(deep.opacity(reduceTransparency ? 0.48 : 0.78)),
                style: StrokeStyle(lineWidth: 1.4)
            )

            for y in stride(from: bevelHeight + 5, through: size.height - 2, by: CGFloat(8)) {
                let progress = (y - bevelHeight) / max(size.height - bevelHeight, 1)
                let inset = sideSlope + ((lowerInset - sideSlope) * progress)
                var grain = Path()
                grain.move(to: CGPoint(x: inset + 3, y: y))
                grain.addCurve(
                    to: CGPoint(x: size.width - inset - 3, y: y + 0.8),
                    control1: CGPoint(x: size.width * 0.32, y: y - 1.5),
                    control2: CGPoint(x: size.width * 0.67, y: y + 2)
                )
                context.stroke(
                    grain,
                    with: .color(deep.opacity(reduceTransparency ? 0.10 : 0.18)),
                    style: StrokeStyle(lineWidth: 0.7)
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct MapParchmentSurface: View {
    let tileSize: CGFloat
    let mapSize: CGSize

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let bounds = CGRect(origin: .zero, size: size)
                context.fill(
                    Path(bounds),
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 0.97, green: 0.92, blue: 0.79),
                            Color(red: 0.91, green: 0.84, blue: 0.67),
                            Color(red: 0.88, green: 0.79, blue: 0.59)
                        ]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: size.width, y: size.height)
                    )
                )

                drawPaperGrid(context: &context, size: size)
            }
            .overlay {
                LinearGradient(
                    colors: [
                        Color.white.opacity(reduceTransparency ? 0.16 : 0.27),
                        .clear,
                        Color.black.opacity(reduceTransparency ? 0.07 : 0.13)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .accessibilityHidden(true)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func drawPaperGrid(context: inout GraphicsContext, size: CGSize) {
        let gridColor = Color(red: 0.37, green: 0.26, blue: 0.12)
        let regularOpacity = reduceTransparency ? 0.10 : 0.06
        let majorOpacity = reduceTransparency ? 0.15 : 0.09
        let mapOrigin = CGPoint(
            x: (size.width - mapSize.width) / 2,
            y: (size.height - mapSize.height) / 2
        )

        drawGridLines(
            context: &context,
            size: size,
            origin: mapOrigin.x,
            length: size.height,
            isMajor: { index in index.isMultiple(of: 4) },
            makePath: { position in
                var path = Path()
                path.move(to: CGPoint(x: position, y: 0))
                path.addLine(to: CGPoint(x: position, y: size.height))
                return path
            },
            color: gridColor,
            regularOpacity: regularOpacity,
            majorOpacity: majorOpacity
        )

        drawGridLines(
            context: &context,
            size: size,
            origin: mapOrigin.y,
            length: size.width,
            isMajor: { index in index.isMultiple(of: 4) },
            makePath: { position in
                var path = Path()
                path.move(to: CGPoint(x: 0, y: position))
                path.addLine(to: CGPoint(x: size.width, y: position))
                return path
            },
            color: gridColor,
            regularOpacity: regularOpacity,
            majorOpacity: majorOpacity
        )
    }

    private func drawGridLines(
        context: inout GraphicsContext,
        size: CGSize,
        origin: CGFloat,
        length: CGFloat,
        isMajor: (Int) -> Bool,
        makePath: (CGFloat) -> Path,
        color: Color,
        regularOpacity: Double,
        majorOpacity: Double
    ) {
        var position = origin
        var index = 0
        while position <= length {
            if position >= 0 {
                let major = isMajor(index)
                context.stroke(
                    makePath(position),
                    with: .color(color.opacity(major ? majorOpacity : regularOpacity)),
                    style: StrokeStyle(lineWidth: major ? 0.9 : 0.6)
                )
            }
            position += tileSize
            index += 1
        }

        position = origin - tileSize
        index = 1
        while position >= 0 {
            let major = isMajor(index)
            context.stroke(
                makePath(position),
                with: .color(color.opacity(major ? majorOpacity : regularOpacity)),
                style: StrokeStyle(lineWidth: major ? 0.9 : 0.6)
            )
            position -= tileSize
            index += 1
        }
    }
}

private struct MapWoodSurface: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.48, green: 0.23, blue: 0.08),
                        Color(red: 0.69, green: 0.39, blue: 0.14),
                        Color(red: 0.55, green: 0.27, blue: 0.09)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                MapWoodGrain()
            }
    }
}

private struct MapWoodGrain: View {
    var body: some View {
        Canvas { context, size in
            let dark = Color(red: 0.27, green: 0.11, blue: 0.035)
            let light = Color(red: 0.95, green: 0.66, blue: 0.30)

            for y in stride(from: CGFloat(7), through: size.height, by: CGFloat(18)) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addCurve(
                    to: CGPoint(x: size.width, y: y + 1.5),
                    control1: CGPoint(x: size.width * 0.30, y: y - 3),
                    control2: CGPoint(x: size.width * 0.68, y: y + 4)
                )
                context.stroke(path, with: .color(dark.opacity(0.15)), style: StrokeStyle(lineWidth: 0.8))
            }

            for x in stride(from: CGFloat(10), through: size.width, by: CGFloat(28)) {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addCurve(
                    to: CGPoint(x: x + 2, y: size.height),
                    control1: CGPoint(x: x - 4, y: size.height * 0.30),
                    control2: CGPoint(x: x + 5, y: size.height * 0.72)
                )
                context.stroke(path, with: .color(light.opacity(0.13)), style: StrokeStyle(lineWidth: 0.7))
            }

            let knotCenters = [
                CGPoint(x: size.width * 0.16, y: size.height * 0.32),
                CGPoint(x: size.width * 0.82, y: size.height * 0.68)
            ]
            for center in knotCenters {
                let knot = CGRect(x: center.x - 8, y: center.y - 3, width: 16, height: 6)
                context.stroke(Path(ellipseIn: knot), with: .color(dark.opacity(0.16)), style: StrokeStyle(lineWidth: 1))
                context.stroke(Path(ellipseIn: knot.insetBy(dx: 3, dy: 1)), with: .color(light.opacity(0.16)), style: StrokeStyle(lineWidth: 0.8))
            }
        }
        .allowsHitTesting(false)
    }
}

struct MapCanvasView: View {
    let model: EditorModel
    let atlas: SpriteAtlas
    let tileSize: Double
    let topOverflow: CGFloat
    let interactionEnabled: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isDragging = false

    init(
        model: EditorModel,
        atlas: SpriteAtlas,
        tileSize: Double = 28,
        topOverflow: CGFloat = MapCanvasMetrics.tallSpriteOverflow,
        interactionEnabled: Bool = true
    ) {
        self.model = model
        self.atlas = atlas
        self.tileSize = tileSize
        self.topOverflow = topOverflow
        self.interactionEnabled = interactionEnabled
    }

    var body: some View {
        let staggered = MapCanvasMetrics.isStaggeredGB(map: model.map, palette: model.renderPalette)
        let mapSize = MapCanvasMetrics.mapPixelSize(
            width: model.map.width,
            height: model.map.height,
            tileSize: CGFloat(tileSize),
            staggered: staggered
        )
        Canvas { context, _ in
            context.translateBy(x: 0, y: topOverflow)
            drawMap(context: &context, staggered: staggered, mapSize: mapSize)
        }
        .frame(
            width: mapSize.width,
            height: (CGFloat(model.map.height) * tileSize) + topOverflow
        )
        .background(
            Group {
                if interactionEnabled {
                    MapCanvasInput(
                        model: model,
                        tileSize: tileSize,
                        topInset: Double(topOverflow)
                    )
                    .allowsHitTesting(false)
                }
            }
        )
        .contentShape(Rectangle())
        .gesture(pointerGesture)
        .onContinuousHover(coordinateSpace: .local) { phase in
            guard interactionEnabled else { return }
            switch phase {
            case .active(let location):
                let point = cell(for: location)
                let validPoint = isValid(point) ? point : nil
                model.updatePointer(validPoint)
                updateNativeCursor(at: validPoint)
            case .ended:
                model.updatePointer(nil)
                AWCursorController.shared.reset()
            }
        }
        .onChange(of: model.selectedTool) { _, _ in refreshNativeCursor() }
        .onChange(of: model.selectedElement) { _, _ in refreshNativeCursor() }
        .onChange(of: model.pointerCell) { _, _ in refreshNativeCursor() }
        .onChange(of: model.map.tileset) { _, _ in refreshNativeCursor() }
        .onChange(of: model.preferences.drawCursor) { _, _ in refreshNativeCursor() }
        .onDisappear { AWCursorController.shared.reset() }
        .accessibilityLabel("Advance Wars map, \(model.map.width) by \(model.map.height) tiles")
        .accessibilityHint("Drag to draw with the selected tool")
    }

    private var pointerGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let point = cell(for: value.location)
                if !isDragging {
                    isDragging = true
                    model.handlePointer(point, phase: .began, modifiers: currentPointerModifiers)
                } else {
                    model.handlePointer(point, phase: .changed, modifiers: currentPointerModifiers)
                }
            }
            .onEnded { value in
                isDragging = false
                model.handlePointer(cell(for: value.location), phase: .ended, modifiers: currentPointerModifiers)
            }
    }

    private var currentPointerModifiers: PointerModifiers {
        let flags = NSEvent.modifierFlags
        return PointerModifiers(
            command: flags.contains(.command) || flags.contains(.control),
            shift: flags.contains(.shift),
            option: flags.contains(.option)
        )
    }

    private func cell(for location: CGPoint) -> GridPoint {
        let y = Int(floor((location.y - topOverflow) / tileSize))
        let staggered = MapCanvasMetrics.isStaggeredGB(map: model.map, palette: model.renderPalette)
        let rowOffset = staggered && y % 2 != 0 ? tileSize / 2 : 0
        return GridPoint(x: Int(floor((location.x - rowOffset) / tileSize)), y: y)
    }

    private func isValid(_ point: GridPoint) -> Bool {
        point.x >= 0 && point.x < model.map.width && point.y >= 0 && point.y < model.map.height
    }

    private func drawMap(context: inout GraphicsContext, staggered: Bool, mapSize: CGSize) {
        let map = model.map
        let tile = CGFloat(tileSize)
        let mapBounds = CGRect(origin: .zero, size: mapSize)
        context.clip(to: Path(mapBounds))
        // Keep transparent/unused areas true black so the four-colour Game Boy
        // palettes do not pick up the editor's dark slate backing.
        context.fill(Path(mapBounds), with: .color(.black))

        for x in 0..<map.width {
            for y in 0..<map.height {
                let rect = MapCanvasMetrics.tileRect(x: x, y: y, tileSize: tile, staggered: staggered)
                if !map.tileset.isGameBoyWarsFamily {
                    context.fill(MapCanvasMetrics.tilePath(in: rect, staggered: staggered), with: .color(Color.white.opacity((x + y).isMultiple(of: 2) ? 0.025 : 0.01)))
                }
                let terrain = map.backgroundElement(atX: x, y: y)
                let background = map.backgroundDrawElement(atX: x, y: y)
                // Row-zero double-height artwork is supplied by the separate
                // overflow layer so it can project above the wood rim without
                // bringing the tile background with it.
                if let buildingUnderlay = map.buildingUnderlayDrawElement(atX: x, y: y) {
                    drawSprite(buildingUnderlay, at: rect, context: &context)
                }
                if !(y == 0 && model.renderPalette.doubleHeight(for: background) &&
                    (background.isBuilding || background.isExtra || background.simplified == .terrainMountain)) {
                    if let bridgeUnderlay = map.bridgeUnderlayDrawElement(atX: x, y: y) {
                        drawSprite(bridgeUnderlay, at: rect, context: &context)
                    }
                    drawSprite(background, at: rect, context: &context)
                }
                drawSeaCoast(atX: x, y: y, rect: rect, map: map, context: &context)
                drawSeaUpperDepth(at: rect, x: x, y: y, terrain: terrain, map: map, context: &context)
                let foreground = map.foregroundElement(atX: x, y: y)
                if !(y == 0 && model.renderPalette.doubleHeight(for: foreground) && (foreground.isBuilding || foreground.isExtra)) {
                    drawSprite(foreground, at: rect, context: &context)
                }
            }
        }

        if let fragment = model.selectionFragment, let selection = model.selection {
            for x in 0..<fragment.width {
                for y in 0..<fragment.height {
                    let rect = MapCanvasMetrics.tileRect(
                        x: selection.x + x,
                        y: selection.y + y,
                        tileSize: tile,
                        staggered: staggered
                    )
                    let background = fragment.backgroundDrawElement(atX: x, y: y)
                    if background != .terrainBlank {
                        if let buildingUnderlay = fragment.buildingUnderlayDrawElement(atX: x, y: y) {
                            drawSprite(buildingUnderlay, at: rect, context: &context)
                        }
                        if let bridgeUnderlay = fragment.bridgeUnderlayDrawElement(atX: x, y: y) {
                            drawSprite(bridgeUnderlay, at: rect, context: &context)
                        }
                        drawSprite(background, at: rect, context: &context)
                    }
                    drawSprite(fragment.foregroundElement(atX: x, y: y), at: rect, context: &context)
                }
            }
            let borderOrigin = MapCanvasMetrics.tileOrigin(
                x: selection.x,
                y: selection.y,
                tileSize: tile,
                staggered: staggered
            )
            let border = CGRect(
                x: borderOrigin.x + 0.5,
                y: borderOrigin.y + 0.5,
                width: CGFloat(selection.width) * tile - 1,
                height: CGFloat(selection.height) * tile - 1
            )
            context.stroke(Path(border), with: .color(.black), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }

        if !model.previewCells.isEmpty {
            for point in model.previewCells {
                let rect = MapCanvasMetrics.tileRect(
                    x: point.x,
                    y: point.y,
                    tileSize: tile,
                    staggered: staggered,
                    inset: 1
                )
                let path = MapCanvasMetrics.tilePath(in: rect, staggered: staggered)
                context.fill(path, with: .color(Color.accentColor.opacity(0.18)))
                context.stroke(path, with: .color(Color.accentColor), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
        }

        drawCursorFrame(map: map, tile: tile, staggered: staggered, context: &context)
    }

    private func drawSeaUpperDepth(
        at rect: CGRect,
        x: Int,
        y: Int,
        terrain: Element,
        map: MapState,
        context: inout GraphicsContext
    ) {
        // Use the underlying tile, not its derived draw sprite, so every
        // non-sea cell opts out independently even when it borders the sea.
        guard rect.minY == 0,
              terrain.simplified == .terrainSea,
              !map.tileset.isGameBoyWarsFamily,
              !hasTallSpriteCover(atX: x, y: y, map: map) else { return }

        let depthHeight = min(rect.height * 0.38, 10)
        let shadow = Color(red: 0.02, green: 0.10, blue: 0.16)
        let leadingOpacity = reduceTransparency ? 0.045 : 0.085
        let trailingOpacity = reduceTransparency ? 0.012 : 0.028
        let depthRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: depthHeight)

        context.fill(
            Path(depthRect),
            with: .linearGradient(
                Gradient(colors: [
                    shadow.opacity(leadingOpacity),
                    shadow.opacity(trailingOpacity),
                    .clear
                ]),
                startPoint: CGPoint(x: rect.midX, y: rect.minY),
                endPoint: CGPoint(x: rect.midX, y: depthRect.maxY)
            )
        )
    }

    private func hasTallSpriteCover(atX x: Int, y: Int, map: MapState) -> Bool {
        // A double-height building/extra anchored on row zero occupies this
        // cell, while one anchored on row one occupies its upper half. The
        // sea shadow must stay behind both cases, including transparent areas
        // in the sprite artwork.
        for anchorY in y...min(y + 1, map.height - 1) {
            let background = map.backgroundElement(atX: x, y: anchorY)
            if model.renderPalette.doubleHeight(for: background) && (background.isBuilding || background.isExtra) { return true }
        }
        return false
    }

    private func drawSprite(_ element: Element, at rect: CGRect, context: inout GraphicsContext) {
        guard let image = atlas.image(for: element, palette: model.renderPalette) else { return }
        let isDoubleHeight = model.renderPalette.doubleHeight(for: element)
        let drawRect = isDoubleHeight ? CGRect(x: rect.minX, y: rect.minY - rect.height, width: rect.width, height: rect.height * 2) : rect
        if MapCanvasMetrics.isStaggeredGB(map: model.map, palette: model.renderPalette), !isDoubleHeight {
            var clippedContext = context
            clippedContext.clip(to: MapCanvasMetrics.tilePath(in: rect, staggered: true))
            clippedContext.draw(clippedContext.resolve(image), in: drawRect)
        } else {
            context.draw(context.resolve(image), in: drawRect)
        }
    }

    private func drawSeaCoast(atX x: Int, y: Int, rect: CGRect, map: MapState, context: inout GraphicsContext) {
        // Enclosed sea cells are already represented by a dedicated draw
        // variant (terrain columns 7). Compose overlays only for base sea.
        guard !map.tileset.isGameBoyWarsFamily,
              map.backgroundDrawElement(atX: x, y: y) == .terrainSea else { return }
        let up = map.backgroundElement(atX: x, y: y - 1)
        let down = map.backgroundElement(atX: x, y: y + 1)
        let left = map.backgroundElement(atX: x - 1, y: y)
        let right = map.backgroundElement(atX: x + 1, y: y)
        let upLeft = map.backgroundElement(atX: x - 1, y: y - 1)
        let upRight = map.backgroundElement(atX: x + 1, y: y - 1)
        let downRight = map.backgroundElement(atX: x + 1, y: y + 1)
        let downLeft = map.backgroundElement(atX: x - 1, y: y + 1)
        let overlays: [(Element, Bool)] = [
            (Element(AWConstants.makeTerrain(6, 3)), upLeft.isLand && !up.isLand && !left.isLand),
            (Element(AWConstants.makeTerrain(5, 3)), upRight.isLand && !up.isLand && !right.isLand),
            (Element(AWConstants.makeTerrain(5, 2)), downRight.isLand && !down.isLand && !right.isLand),
            (Element(AWConstants.makeTerrain(6, 2)), downLeft.isLand && !down.isLand && !left.isLand),
            (Element(AWConstants.makeTerrain(5, 4)), left.isLand),
            (Element(AWConstants.makeTerrain(5, 5)), up.isLand),
            (Element(AWConstants.makeTerrain(6, 4)), right.isLand),
            (Element(AWConstants.makeTerrain(6, 5)), down.isLand),
            (Element(AWConstants.makeTerrain(5, 0)), up.isLand && left.isLand),
            (Element(AWConstants.makeTerrain(6, 0)), up.isLand && right.isLand),
            (Element(AWConstants.makeTerrain(5, 1)), down.isLand && left.isLand),
            (Element(AWConstants.makeTerrain(6, 1)), down.isLand && right.isLand)
        ]
        for (element, shouldDraw) in overlays where shouldDraw { drawSprite(element, at: rect, context: &context) }
    }

    private func drawCursorFrame(
        map: MapState,
        tile: CGFloat,
        staggered: Bool,
        context: inout GraphicsContext
    ) {
        guard model.preferences.drawCursor,
              let pointer = model.pointerCell,
              pointer.x >= 0, pointer.x < map.width,
              pointer.y >= 0, pointer.y < map.height else { return }

        let footprint = model.selectedTool == .pencil ? model.selectedElement.size : 1
        let frame: AWCursorFrame
        switch footprint {
        case 3: frame = .large3
        case 4: frame = .large4
        default: frame = .single
        }
        // The 18×18 single-cell frame is drawn one source pixel above and to
        // the left of the cell in the original editor. Keep that one-pixel
        // inset at the current tile scale so its three balls leave the
        // lower-right position for the pointer tip.
        let sourcePixels = footprint > 1 ? CGFloat(footprint * 16) : 18
        let frameScale = tile / 16
        let origin = footprint > 1 ? 1 : 0
        let singleFrameInset = footprint > 1 ? 0 : frameScale
        let tileOrigin = MapCanvasMetrics.tileOrigin(
            x: pointer.x - origin,
            y: pointer.y - origin,
            tileSize: tile,
            staggered: staggered
        )
        let rect = CGRect(
            x: tileOrigin.x - singleFrameInset,
            y: tileOrigin.y - singleFrameInset,
            width: sourcePixels * frameScale,
            height: sourcePixels * frameScale
        )
        if let image = CursorAtlas.shared.frameImage(frame, tileset: map.tileset) {
            context.draw(context.resolve(image), in: rect)
        } else {
            context.stroke(
                Path(rect.insetBy(dx: 0.5, dy: 0.5)),
                with: .color(Color.white.opacity(0.7)),
                style: StrokeStyle(lineWidth: 1)
            )
        }
    }

    private func refreshNativeCursor() {
        updateNativeCursor(at: model.pointerCell)
    }

    private func updateNativeCursor(at point: GridPoint?) {
        guard model.preferences.drawCursor,
              let point,
              point.x >= 0, point.x < model.map.width,
              point.y >= 0, point.y < model.map.height else {
            AWCursorController.shared.reset()
            return
        }

        let kind: AWCursorKind
        if model.selectedElement == .unitDelete || model.selectedElement == .unitEmpty {
            kind = .delete
        } else if [.line, .rectangle, .filledRectangle, .bucket].contains(model.selectedTool), model.selectedElement.size > 1 {
            kind = .forbidden
        } else if model.selectedTool == .pencil,
                  !model.map.allowPlacement(model.selectedElement, atX: point.x, y: point.y) {
            kind = .forbidden
        } else {
            kind = .allowed
        }
        AWCursorController.shared.update(kind: kind, tileset: model.map.tileset)
    }
}
