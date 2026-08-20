import SwiftUI
import AWEDCore

enum MapCanvasMetrics {
    static let tileSize: CGFloat = 28
    static let woodPadding: CGFloat = 10
    static let parchmentPadding: CGFloat = 12
}

struct MapCanvasBoard: View {
    let model: EditorModel
    let atlas: SpriteAtlas

    var body: some View {
        MapCanvasView(model: model, atlas: atlas, tileSize: Double(MapCanvasMetrics.tileSize))
            .padding(MapCanvasMetrics.woodPadding)
            .background {
                MapWoodSurface()
            }
            .overlay {
                Rectangle()
                    .stroke(Color(red: 0.25, green: 0.13, blue: 0.055).opacity(0.82), lineWidth: 2)
                Rectangle()
                    .stroke(Color(red: 0.98, green: 0.80, blue: 0.42).opacity(0.48), lineWidth: 1)
                    .padding(4)
                Rectangle()
                    .stroke(Color(red: 0.28, green: 0.14, blue: 0.06).opacity(0.68), lineWidth: 1)
                    .padding(7)
            }
            .shadow(color: Color.black.opacity(0.22), radius: 10, y: 5)
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
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
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
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
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

    @State private var isDragging = false

    init(model: EditorModel, atlas: SpriteAtlas, tileSize: Double = 28) {
        self.model = model
        self.atlas = atlas
        self.tileSize = tileSize
    }

    var body: some View {
        Canvas { context, _ in
            drawMap(context: &context)
        }
        .frame(width: CGFloat(model.map.width) * tileSize, height: CGFloat(model.map.height) * tileSize)
        .background(MapCanvasInput(model: model, tileSize: tileSize).allowsHitTesting(false))
        .contentShape(Rectangle())
        .gesture(pointerGesture)
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location):
                let point = cell(for: location)
                model.updatePointer(point)
                updateNativeCursor(at: point)
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
        GridPoint(x: Int(location.x / tileSize), y: Int(location.y / tileSize))
    }

    private func drawMap(context: inout GraphicsContext) {
        let map = model.map
        let tile = CGFloat(tileSize)
        context.fill(Path(CGRect(x: 0, y: 0, width: CGFloat(map.width) * tile, height: CGFloat(map.height) * tile)), with: .color(Color(red: 0.12, green: 0.16, blue: 0.18)))

        for x in 0..<map.width {
            for y in 0..<map.height {
                let rect = CGRect(x: CGFloat(x) * tile, y: CGFloat(y) * tile, width: tile, height: tile)
                context.fill(Path(rect), with: .color(Color.white.opacity((x + y).isMultiple(of: 2) ? 0.025 : 0.01)))
                drawSprite(map.backgroundDrawElement(atX: x, y: y), at: rect, context: &context)
                drawSeaCoast(atX: x, y: y, rect: rect, map: map, context: &context)
                drawSprite(map.foregroundElement(atX: x, y: y), at: rect, context: &context)
            }
        }

        if let fragment = model.selectionFragment, let selection = model.selection {
            for x in 0..<fragment.width {
                for y in 0..<fragment.height {
                    let rect = CGRect(x: CGFloat(selection.x + x) * tile, y: CGFloat(selection.y + y) * tile, width: tile, height: tile)
                    let background = fragment.backgroundDrawElement(atX: x, y: y)
                    if background != .terrainBlank { drawSprite(background, at: rect, context: &context) }
                    drawSprite(fragment.foregroundElement(atX: x, y: y), at: rect, context: &context)
                }
            }
            let border = CGRect(x: CGFloat(selection.x) * tile + 0.5, y: CGFloat(selection.y) * tile + 0.5, width: CGFloat(selection.width) * tile - 1, height: CGFloat(selection.height) * tile - 1)
            context.stroke(Path(border), with: .color(.black), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }

        if !model.previewCells.isEmpty {
            for point in model.previewCells {
                let rect = CGRect(x: CGFloat(point.x) * tile + 1, y: CGFloat(point.y) * tile + 1, width: tile - 2, height: tile - 2)
                context.fill(Path(rect), with: .color(Color.accentColor.opacity(0.18)))
                context.stroke(Path(rect), with: .color(Color.accentColor), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
        }

        drawCursorFrame(map: map, tile: tile, context: &context)
    }

    private func drawSprite(_ element: Element, at rect: CGRect, context: inout GraphicsContext) {
        guard let image = atlas.image(for: element, tileset: model.map.tileset) else { return }
        let drawRect = element.doubleHeight ? CGRect(x: rect.minX, y: rect.minY - rect.height, width: rect.width, height: rect.height * 2) : rect
        context.draw(context.resolve(image), in: drawRect)
    }

    private func drawSeaCoast(atX x: Int, y: Int, rect: CGRect, map: MapState, context: inout GraphicsContext) {
        // Enclosed sea cells are already represented by a dedicated draw
        // variant (terrain columns 7). Compose overlays only for base sea.
        guard map.backgroundDrawElement(atX: x, y: y) == .terrainSea else { return }
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

    private func drawCursorFrame(map: MapState, tile: CGFloat, context: inout GraphicsContext) {
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
        let rect = CGRect(
            x: CGFloat(pointer.x - origin) * tile - singleFrameInset,
            y: CGFloat(pointer.y - origin) * tile - singleFrameInset,
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
