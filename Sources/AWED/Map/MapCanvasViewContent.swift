import SwiftUI
import AWEDCore


struct MapCanvasView: View {
    let model: EditorModel
    let atlas: SpriteAtlas
    let tileSize: Double
    let topOverflow: CGFloat
    let interactionEnabled: Bool
    let mapOverride: MapState?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isDragging = false

    init(
        model: EditorModel,
        atlas: SpriteAtlas,
        tileSize: Double = 24,
        topOverflow: CGFloat = MapCanvasMetrics.tallSpriteOverflow,
        interactionEnabled: Bool = true,
        mapOverride: MapState? = nil
    ) {
        self.model = model
        self.atlas = atlas
        self.tileSize = tileSize
        self.topOverflow = topOverflow
        self.interactionEnabled = interactionEnabled
        self.mapOverride = mapOverride
    }

    private var renderMap: MapState { mapOverride ?? model.map }

    var body: some View {
        let map = renderMap
        let staggered = MapCanvasMetrics.isStaggeredGB(map: map, palette: model.renderPalette)
        let mapSize = MapCanvasMetrics.mapPixelSize(
            width: map.width,
            height: map.height,
            tileSize: CGFloat(tileSize),
            staggered: staggered
        )
        Canvas { context, _ in
            context.translateBy(x: 0, y: topOverflow)
            drawMap(context: &context, staggered: staggered, mapSize: mapSize)
        }
        .frame(
            width: mapSize.width,
            height: (CGFloat(map.height) * tileSize) + topOverflow
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
        .onChange(of: renderMap.tileset) { _, _ in refreshNativeCursor() }
        .onChange(of: model.preferences.drawCursor) { _, _ in refreshNativeCursor() }
        .onDisappear { AWCursorController.shared.reset() }
        .accessibilityLabel("Advance Wars map, \(map.width) by \(map.height) tiles")
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
        let staggered = MapCanvasMetrics.isStaggeredGB(map: renderMap, palette: model.renderPalette)
        let rowOffset = staggered && y % 2 != 0 ? tileSize / 2 : 0
        return GridPoint(x: Int(floor((location.x - rowOffset) / tileSize)), y: y)
    }

    private func isValid(_ point: GridPoint) -> Bool {
        point.x >= 0 && point.x < renderMap.width && point.y >= 0 && point.y < renderMap.height
    }

    private func drawMap(context: inout GraphicsContext, staggered: Bool, mapSize: CGSize) {
        let map = renderMap
        let tile = CGFloat(tileSize)
        let mapBounds = CGRect(origin: .zero, size: mapSize)
        let isFamicom = map.tileset == .famicomWars
        let emptyColor = isFamicom ? FamicomPPUPalette.black : Color.black
        context.clip(to: Path(mapBounds))
        context.fill(Path(mapBounds), with: .color(emptyColor))
        drawTerrainPass(map: map, tile: tile, staggered: staggered, context: &context)
        drawWideBuildings(map: map, tile: tile, staggered: staggered, context: &context)
        drawUnits(map: map, tile: tile, staggered: staggered, context: &context)
        drawSelection(tile: tile, staggered: staggered, context: &context)
        drawPreview(tile: tile, staggered: staggered, context: &context)
        drawCursorFrame(map: map, tile: tile, staggered: staggered, context: &context)
    }

    private func drawTerrainPass(map: MapState, tile: CGFloat, staggered: Bool, context: inout GraphicsContext) {
        let isFamicom = map.tileset == .famicomWars
        let checkerColor = isFamicom ? FamicomPPUPalette.white : Color.white
        for x in 0..<map.width {
            for y in 0..<map.height {
                let rect = MapCanvasMetrics.tileRect(x: x, y: y, tileSize: tile, staggered: staggered)
                if !map.tileset.isGameBoyWarsFamily {
                    let opacity = (x + y).isMultiple(of: 2) ? 0.025 : 0.01
                    context.fill(MapCanvasMetrics.tilePath(in: rect, staggered: staggered), with: .color(checkerColor.opacity(opacity)))
                }
                drawTerrainTile(map: map, x: x, y: y, rect: rect, tile: tile, staggered: staggered, context: &context)
            }
        }
    }

    private func drawTerrainTile(
        map: MapState,
        x: Int,
        y: Int,
        rect: CGRect,
        tile: CGFloat,
        staggered: Bool,
        context: inout GraphicsContext
    ) {
        let terrain = map.backgroundElement(atX: x, y: y)
        let background = map.backgroundDrawElement(atX: x, y: y)
        if let buildingUnderlay = map.buildingUnderlayDrawElement(atX: x, y: y) {
            drawSprite(buildingUnderlay, at: rect, context: &context)
        }
        let isWideBuilding = model.renderPalette.footprint(for: background).width > 1
        let isTall = y == 0 && model.renderPalette.doubleHeight(for: background) &&
            (background.isBuilding || background.isExtra || background.simplified == .terrainMountain)
        if !isWideBuilding && !isTall {
            if let bridgeUnderlay = map.bridgeUnderlayDrawElement(atX: x, y: y) {
                drawSprite(bridgeUnderlay, at: rect, context: &context)
            }
            drawSprite(background, at: rect, context: &context)
        }
        drawSeaCoast(atX: x, y: y, rect: rect, map: map, context: &context)
        drawSeaUpperDepth(at: rect, x: x, y: y, terrain: terrain, map: map, context: &context)
    }

    private func drawWideBuildings(map: MapState, tile: CGFloat, staggered: Bool, context: inout GraphicsContext) {
        for x in 0..<map.width {
            for y in 0..<map.height {
                let rect = MapCanvasMetrics.tileRect(x: x, y: y, tileSize: tile, staggered: staggered)
                let background = map.backgroundDrawElement(atX: x, y: y)
                if model.renderPalette.footprint(for: background).width > 1 {
                    drawSprite(background, at: rect, context: &context)
                }
            }
        }
    }

    private func drawUnits(map: MapState, tile: CGFloat, staggered: Bool, context: inout GraphicsContext) {
        for x in 0..<map.width {
            for y in 0..<map.height {
                let rect = MapCanvasMetrics.tileRect(x: x, y: y, tileSize: tile, staggered: staggered)
                drawSprite(map.foregroundElement(atX: x, y: y), at: rect, context: &context)
            }
        }
    }

    private func drawSelection(tile: CGFloat, staggered: Bool, context: inout GraphicsContext) {
        guard let fragment = model.selectionFragment, let selection = model.selection else { return }
        for x in 0..<fragment.width {
            for y in 0..<fragment.height {
                let rect = MapCanvasMetrics.tileRect(x: selection.x + x, y: selection.y + y, tileSize: tile, staggered: staggered)
                drawSelectionCell(fragment, x: x, y: y, rect: rect, context: &context)
            }
        }
        drawSelectionBorder(selection, tile: tile, staggered: staggered, context: &context)
    }

    private func drawSelectionCell(_ fragment: MapFragment, x: Int, y: Int, rect: CGRect, context: inout GraphicsContext) {
        let background = fragment.backgroundDrawElement(atX: x, y: y)
        guard background != .terrainBlank else {
            drawSprite(fragment.foregroundElement(atX: x, y: y), at: rect, context: &context)
            return
        }
        if let underlay = fragment.buildingUnderlayDrawElement(atX: x, y: y) {
            drawSprite(underlay, at: rect, context: &context)
        }
        if let underlay = fragment.bridgeUnderlayDrawElement(atX: x, y: y) {
            drawSprite(underlay, at: rect, context: &context)
        }
        drawSprite(background, at: rect, context: &context)
        drawSprite(fragment.foregroundElement(atX: x, y: y), at: rect, context: &context)
    }

    private func drawSelectionBorder(_ selection: SelectionRect, tile: CGFloat, staggered: Bool, context: inout GraphicsContext) {
        let origin = MapCanvasMetrics.tileOrigin(x: selection.x, y: selection.y, tileSize: tile, staggered: staggered)
        let border = CGRect(x: origin.x + 0.5, y: origin.y + 0.5, width: CGFloat(selection.width) * tile - 1, height: CGFloat(selection.height) * tile - 1)
        context.stroke(Path(border), with: .color(renderMap.tileset == .famicomWars ? FamicomPPUPalette.black : Color.black), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }

    private func drawPreview(tile: CGFloat, staggered: Bool, context: inout GraphicsContext) {
        guard !model.previewCells.isEmpty else { return }
        let color = renderMap.tileset == .famicomWars ? FamicomPPUPalette.cyan : Color.accentColor
        for point in model.previewCells {
            let rect = MapCanvasMetrics.tileRect(x: point.x, y: point.y, tileSize: tile, staggered: staggered, inset: 1)
            let path = MapCanvasMetrics.tilePath(in: rect, staggered: staggered)
            context.fill(path, with: .color(color.opacity(0.18)))
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        }
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
        let shadow = map.tileset == .famicomWars
            ? FamicomPPUPalette.darkBlue
            : Color(red: 0.02, green: 0.10, blue: 0.16)
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
        let minAnchorX = max(0, x - 1)
        let maxAnchorX = min(map.width - 1, x)
        let minAnchorY = max(0, y - 1)
        let maxAnchorY = min(map.height - 1, y + 1)
        for anchorX in minAnchorX...maxAnchorX {
            for anchorY in minAnchorY...maxAnchorY {
                let background = map.backgroundElement(atX: anchorX, y: anchorY)
                let footprint = model.renderPalette.footprint(for: background)
                let coversCell = anchorX <= x && x < anchorX + footprint.width &&
                    anchorY <= y && y < anchorY + footprint.height
                if coversCell && (model.renderPalette.doubleHeight(for: background) || footprint.width > 1) &&
                    (background.isBuilding || background.isExtra) { return true }
            }
        }
        return false
    }

    private func drawSprite(_ element: Element, at rect: CGRect, context: inout GraphicsContext) {
        guard let image = atlas.image(for: element, palette: model.renderPalette) else { return }
        let isDoubleHeight = model.renderPalette.doubleHeight(for: element)
        let footprint = model.renderPalette.footprint(for: element)
        let drawRect: CGRect
        if isDoubleHeight {
            drawRect = CGRect(x: rect.minX, y: rect.minY - rect.height, width: rect.width, height: rect.height * 2)
        } else {
            drawRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width * CGFloat(footprint.width), height: rect.height * CGFloat(footprint.height))
        }
        if MapCanvasMetrics.isStaggeredGB(map: renderMap, palette: model.renderPalette),
           footprint.width == 1, footprint.height == 1 {
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
        let neighbours = canvasCoastNeighbours(atX: x, y: y, map: map)
        let overlays = canvasCornerCoastOverlays(neighbours) + canvasEdgeCoastOverlays(neighbours)
        for (element, shouldDraw) in overlays where shouldDraw { drawSprite(element, at: rect, context: &context) }
    }

    private func canvasCoastNeighbours(atX x: Int, y: Int, map: MapState) -> CanvasCoastNeighbours {
        CanvasCoastNeighbours(
            up: map.backgroundElement(atX: x, y: y - 1), down: map.backgroundElement(atX: x, y: y + 1),
            left: map.backgroundElement(atX: x - 1, y: y), right: map.backgroundElement(atX: x + 1, y: y),
            upLeft: map.backgroundElement(atX: x - 1, y: y - 1), upRight: map.backgroundElement(atX: x + 1, y: y - 1),
            downRight: map.backgroundElement(atX: x + 1, y: y + 1), downLeft: map.backgroundElement(atX: x - 1, y: y + 1)
        )
    }

    private func canvasCornerCoastOverlays(_ n: CanvasCoastNeighbours) -> [(Element, Bool)] {
        [
            (Element(AWConstants.makeTerrain(6, 3)), n.upLeft.isLand && !n.up.isLand && !n.left.isLand),
            (Element(AWConstants.makeTerrain(5, 3)), n.upRight.isLand && !n.up.isLand && !n.right.isLand),
            (Element(AWConstants.makeTerrain(5, 2)), n.downRight.isLand && !n.down.isLand && !n.right.isLand),
            (Element(AWConstants.makeTerrain(6, 2)), n.downLeft.isLand && !n.down.isLand && !n.left.isLand),
            (Element(AWConstants.makeTerrain(5, 0)), n.up.isLand && n.left.isLand),
            (Element(AWConstants.makeTerrain(6, 0)), n.up.isLand && n.right.isLand),
            (Element(AWConstants.makeTerrain(5, 1)), n.down.isLand && n.left.isLand),
            (Element(AWConstants.makeTerrain(6, 1)), n.down.isLand && n.right.isLand)
        ]
    }

    private func canvasEdgeCoastOverlays(_ n: CanvasCoastNeighbours) -> [(Element, Bool)] {
        [
            (Element(AWConstants.makeTerrain(5, 4)), n.left.isLand),
            (Element(AWConstants.makeTerrain(5, 5)), n.up.isLand),
            (Element(AWConstants.makeTerrain(6, 4)), n.right.isLand),
            (Element(AWConstants.makeTerrain(6, 5)), n.down.isLand)
        ]
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
                with: .color((map.tileset == .famicomWars ? FamicomPPUPalette.white : Color.white).opacity(0.7)),
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

private struct CanvasCoastNeighbours {
    let up: Element
    let down: Element
    let left: Element
    let right: Element
    let upLeft: Element
    let upRight: Element
    let downRight: Element
    let downLeft: Element
}
