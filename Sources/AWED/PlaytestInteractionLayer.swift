import SwiftUI
import AWEDCore

struct PlaytestInteractionLayer: View {
    let session: PlaytestSession
    let previewModel: EditorModel
    let atlas: SpriteAtlas
    let tileSize: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isDragging = false
    @State private var movedDuringDrag = false

    private var canvas: some View { interactionCanvas }

    private var interactionHighlightColor: Color {
        session.map.tileset == .famicomWars ? FamicomPPUPalette.white : Color.white
    }

    var body: some View {
        canvas
        .contentShape(Rectangle())
        .gesture(pointerGesture)
        .background {
            PlaytestMapInput(session: session, previewModel: previewModel, tileSize: tileSize)
                .allowsHitTesting(false)
        }
        .accessibilityElement()
        .accessibilityLabel("Playtest map")
        .accessibilityValue(session.statusMessage)
        .accessibilityHint(session.ruleset.usesLegacyKeyboardControls
            ? "Use arrow keys to move the map cursor, Z for A to confirm, X for B to cancel, and S for Select to open the command menu."
            : "Select a unit, drag across blue movement tiles to plan a route, release to move, choose a highlighted destination or target, or right-click a unit to preview its attacks. Use the inspector for capture, refueling, depth, missile silos, and production actions.")
        .accessibilityAddTraits(.isButton)
        .allowsHitTesting(!session.ruleset.usesLegacyKeyboardControls)
    }

    private var interactionCanvas: some View {
        Canvas { context, _ in
            let isFamicom = session.map.tileset == .famicomWars
            let movementGlass = isFamicom
                ? FamicomPPUPalette.blue
                : Color(red: 0.10, green: 0.52, blue: 1.0)
            let attackGlass = isFamicom
                ? FamicomPPUPalette.red
                : Color(red: 1.0, green: 0.16, blue: 0.20)
            let captureBase = isFamicom ? FamicomPPUPalette.yellow : Color.yellow
            let loadBase = isFamicom ? FamicomPPUPalette.cyan : Color.cyan
            let unloadBase = isFamicom ? FamicomPPUPalette.orange : Color.orange
            let refuelBase = isFamicom ? FamicomPPUPalette.green : Color.green
            let joinBase = isFamicom ? FamicomPPUPalette.paleGreen : Color.mint
            let siloBase = isFamicom ? FamicomPPUPalette.purple : Color.purple
            let captureFill = captureBase.opacity(reduceTransparency ? 0.12 : 0.28)
            let captureStroke = captureBase.opacity(reduceTransparency ? 0.50 : 0.90)
            let loadFill = loadBase.opacity(reduceTransparency ? 0.10 : 0.18)
            let loadStroke = loadBase.opacity(reduceTransparency ? 0.42 : 0.80)
            let unloadFill = unloadBase.opacity(reduceTransparency ? 0.10 : 0.18)
            let unloadStroke = unloadBase.opacity(reduceTransparency ? 0.42 : 0.80)
            let refuelFill = refuelBase.opacity(reduceTransparency ? 0.10 : 0.18)
            let refuelStroke = refuelBase.opacity(reduceTransparency ? 0.42 : 0.80)
            let joinFill = joinBase.opacity(reduceTransparency ? 0.08 : 0.16)
            let joinStroke = joinBase.opacity(reduceTransparency ? 0.40 : 0.75)
            let siloFill = siloBase.opacity(reduceTransparency ? 0.08 : 0.16)
            let siloStroke = siloBase.opacity(reduceTransparency ? 0.40 : 0.75)
            let highlightColor = isFamicom ? FamicomPPUPalette.white : Color.white
            let selectionColor = isFamicom ? FamicomPPUPalette.white : Color.accentColor

            drawFogOverlay(context: &context)

            // Reachable cells use the era-specific player affordance (blue
            // glass for Advance Wars/Famicom, `M` badges for GB Wars). CPU
            // turns keep only the current-unit marker below so the AI's
            // planning does not look like destinations the player can tap.
            if !session.activeArmyIsCPU {
                if session.ruleset == .superFamicomWars {
                    drawSuperFamicomMovementTiles(session.reachableCells, context: &context)
                } else {
                    for point in session.reachableCells {
                        if session.ruleset.showsMovementAvailabilityBadge {
                            drawMovementAvailabilityBadge(point, context: &context)
                        } else {
                            drawGlassTile(point, base: movementGlass, context: &context)
                        }
                    }
                }
            }
            for point in session.attackableCells {
                drawGlassTile(point, base: attackGlass, context: &context)
            }
            for point in session.attackPreviewCells {
                drawGlassTile(point, base: attackGlass, context: &context)
            }
            for point in session.captureableCells {
                drawTile(point, fill: captureFill, stroke: captureStroke, context: &context)
            }
            for point in session.loadableCells {
                drawTile(point, fill: loadFill, stroke: loadStroke, context: &context)
            }
            for point in session.joinableCells {
                drawTile(point, fill: joinFill, stroke: joinStroke, context: &context)
            }
            for point in session.unloadableCells {
                drawTile(point, fill: unloadFill, stroke: unloadStroke, context: &context)
            }
            for point in session.refuelableCells {
                drawTile(point, fill: refuelFill, stroke: refuelStroke, context: &context)
            }
            for point in session.siloTargetCells {
                drawTile(point, fill: siloFill, stroke: siloStroke, context: &context)
            }

            drawUnitState(context: &context)
            if session.ruleset.showsMovementArrow {
                drawMovementPath(session.cpuMovementPath, context: &context)
                drawMovementPath(session.playerMovementPath, context: &context)
            }
            if let animation = session.movementAnimation {
                drawMovingUnit(animation, context: &context)
            }
            drawTransportMarkers(context: &context)

            if let attackPreviewOrigin = session.attackPreviewOrigin {
                context.stroke(
                    tilePath(for: attackPreviewOrigin, inset: 0.5),
                    with: .color(highlightColor.opacity(0.85)),
                    style: StrokeStyle(lineWidth: 2)
                )
                context.stroke(
                    tilePath(for: attackPreviewOrigin, inset: 2.5),
                    with: .color(attackGlass.opacity(0.9)),
                    style: StrokeStyle(lineWidth: 1)
                )
            }

            if let selectedPoint = session.selectedPoint, !session.activeArmyIsCPU {
                context.stroke(tilePath(for: selectedPoint, inset: 0.5), with: .color(highlightColor.opacity(0.95)), style: StrokeStyle(lineWidth: 2))
                context.stroke(tilePath(for: selectedPoint, inset: 2.5), with: .color(selectionColor), style: StrokeStyle(lineWidth: 1))
            }

            if session.ruleset.usesLegacyKeyboardControls,
               let cursorPoint = session.cursorPoint {
                drawKeyboardCursor(cursorPoint, context: &context)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pointerGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let point = cell(for: value.location)
                if !isDragging {
                    isDragging = true
                    movedDuringDrag = false
                }

                previewModel.updatePointer(point)
                if session.updatePlayerMovementPreview(to: point) {
                    movedDuringDrag = true
                }
            }
            .onEnded { value in
                let point = cell(for: value.location)
                previewModel.updatePointer(point)

                if movedDuringDrag {
                    _ = session.commitPlayerMovementPreview(at: point)
                } else {
                    session.clearPlayerMovementPreview()
                    session.handleTap(point)
                }

                isDragging = false
                movedDuringDrag = false
            }
    }

    private func cell(for location: CGPoint) -> GridPoint {
        let y = Int(floor(location.y / tileSize))
        let rowOffset = session.isStaggeredGrid && y % 2 != 0 ? tileSize / 2 : 0
        return GridPoint(
            x: Int(floor((location.x - rowOffset) / tileSize)),
            y: y
        )
    }

    private func tileRect(for point: GridPoint, inset: CGFloat) -> CGRect {
        MapCanvasMetrics.tileRect(
            x: point.x,
            y: point.y,
            tileSize: tileSize,
            staggered: session.isStaggeredGrid,
            inset: inset
        )
    }

    private func tilePath(for point: GridPoint, inset: CGFloat) -> Path {
        MapCanvasMetrics.tilePath(
            in: tileRect(for: point, inset: inset),
            staggered: session.isStaggeredGrid
        )
    }

    private func drawTile(_ point: GridPoint, fill: Color, stroke: Color, context: inout GraphicsContext) {
        let rect = tileRect(for: point, inset: 1)
        let path = MapCanvasMetrics.tilePath(in: rect, staggered: session.isStaggeredGrid)
        context.fill(path, with: .color(fill))
        context.stroke(path, with: .color(stroke), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
    }

    private func drawGlassTile(
        _ point: GridPoint,
        base: Color,
        context: inout GraphicsContext,
        fillGradient: Gradient? = nil,
        gradientStartPoint: CGPoint? = nil,
        gradientEndPoint: CGPoint? = nil
    ) {
        let rect = tileRect(for: point, inset: 1)
        let fillOpacity = reduceTransparency ? 0.56 : 0.30
        let edgeOpacity = reduceTransparency ? 0.72 : 0.48
        let innerOpacity = reduceTransparency ? 0.86 : 0.66
        let path = tilePath(for: point, inset: 1)
        let innerPath = tilePath(for: point, inset: 2.5)
        let gradient = fillGradient ?? Gradient(colors: [
            interactionHighlightColor.opacity(reduceTransparency ? 0.24 : 0.16),
            base.opacity(fillOpacity),
            base.opacity(fillOpacity * 0.58)
        ])
        let startPoint = gradientStartPoint ?? CGPoint(x: rect.midX, y: rect.minY)
        let endPoint = gradientEndPoint ?? CGPoint(x: rect.midX, y: rect.maxY)

        context.fill(
            path,
            with: .linearGradient(
                gradient,
                startPoint: startPoint,
                endPoint: endPoint
            )
        )
        context.stroke(
            path,
            with: .color(base.opacity(edgeOpacity)),
            style: StrokeStyle(lineWidth: 1)
        )
        context.stroke(
            innerPath,
            with: .color(base.opacity(innerOpacity)),
            style: StrokeStyle(lineWidth: 1)
        )
    }

    /// Super Famicom Wars gives its blue movement range a single diagonal
    /// rainbow wash. The gradient is anchored to the complete reachable-cell
    /// bounds so adjacent tiles continue the same top-left-to-bottom-right
    /// sweep instead of restarting the colors at every tile.
    private func drawSuperFamicomMovementTiles(
        _ points: Set<GridPoint>,
        context: inout GraphicsContext
    ) {
        guard !points.isEmpty else { return }

        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for point in points {
            let rect = tileRect(for: point, inset: 1)
            minX = min(minX, rect.minX)
            minY = min(minY, rect.minY)
            maxX = max(maxX, rect.maxX)
            maxY = max(maxY, rect.maxY)
        }

        let opacity = reduceTransparency ? 0.56 : 0.30
        let gradient = Gradient(colors: [
            Color(red: 0.10, green: 0.24, blue: 1.00).opacity(opacity),
            Color(red: 0.05, green: 0.78, blue: 1.00).opacity(opacity),
            Color(red: 0.20, green: 0.96, blue: 0.55).opacity(opacity),
            Color(red: 1.00, green: 0.88, blue: 0.18).opacity(opacity),
            Color(red: 1.00, green: 0.26, blue: 0.64).opacity(opacity * 0.88)
        ])
        let startPoint = CGPoint(x: minX, y: minY)
        let endPoint = CGPoint(x: maxX, y: maxY)
        let movementBase = Color(red: 0.10, green: 0.52, blue: 1.0)

        for point in points {
            drawGlassTile(
                point,
                base: movementBase,
                context: &context,
                fillGradient: gradient,
                gradientStartPoint: startPoint,
                gradientEndPoint: endPoint
            )
        }
    }

    /// Game Boy Wars marks each legal destination with a compact `M` badge.
    /// Keep the marker opaque enough to read over terrain while using the
    /// same era palette as the status panels instead of the modern blue glass.
    private func drawMovementAvailabilityBadge(_ point: GridPoint, context: inout GraphicsContext) {
        let theme = PlaytestStatusTheme(tileset: session.map.tileset)
        let rect = tileRect(for: point, inset: 0)
        let badgeRect = CGRect(
            x: rect.maxX - 12,
            y: rect.maxY - 12,
            width: 11,
            height: 11
        )
        context.fill(
            Path(roundedRect: badgeRect, cornerRadius: 1.5),
            with: .color(theme.surface.opacity(reduceTransparency ? 0.88 : 0.96))
        )
        context.stroke(
            Path(roundedRect: badgeRect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 1),
            with: .color(theme.outerBorder),
            style: StrokeStyle(lineWidth: 1)
        )

        let text = context.resolve(
            Text("M")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(theme.outerBorder)
        )
        context.draw(text, at: CGPoint(x: badgeRect.midX, y: badgeRect.midY), anchor: .center)
    }

    private func drawKeyboardCursor(_ point: GridPoint, context: inout GraphicsContext) {
        let frameScale = tileSize / 16
        let origin = MapCanvasMetrics.tileOrigin(
            x: point.x,
            y: point.y,
            tileSize: tileSize,
            staggered: session.isStaggeredGrid
        )
        let rect = CGRect(
            x: origin.x - frameScale,
            y: origin.y - frameScale,
            width: 18 * frameScale,
            height: 18 * frameScale
        )
        if let image = CursorAtlas.shared.frameImage(.single, tileset: session.map.tileset) {
            context.draw(context.resolve(image), in: rect)
        } else {
            context.stroke(
                Path(rect.insetBy(dx: 0.5, dy: 0.5)),
                with: .color(interactionHighlightColor.opacity(0.85)),
                style: StrokeStyle(lineWidth: 1)
            )
        }
    }

    private func drawFogOverlay(context: inout GraphicsContext) {
        guard session.isFogOfWarActive else { return }

        // Keep the map's terrain texture just perceptible through the veil,
        // while making hidden units and properties unreadable. A stronger,
        // nearly opaque treatment is used when transparency is reduced so
        // the hidden-state distinction remains clear without relying on
        // translucency.
        let fogColor = Color(red: 0.11, green: 0.05, blue: 0.17)
            .opacity(reduceTransparency ? 0.94 : 0.86)

        for x in 0..<session.map.width {
            for y in 0..<session.map.height {
                let point = GridPoint(x: x, y: y)
                guard !session.isVisible(point) else { continue }
                context.fill(tilePath(for: point, inset: 0), with: .color(fogColor))
            }
        }
    }

    private func drawUnitState(context: inout GraphicsContext) {
        let shadowColor = session.map.tileset == .famicomWars
            ? FamicomPPUPalette.black
            : Color.black
        let damageBadgeTheme = PlaytestStatusTheme(tileset: session.map.tileset).damageBadgeTheme

        for x in 0..<session.map.width {
            for y in 0..<session.map.height {
                let point = GridPoint(x: x, y: y)
                let unit = session.map.foregroundElement(atX: x, y: y)
                guard unit.isUnitNonEmpty, session.isVisible(point) else { continue }

                // The moving sprite is rendered separately below so its
                // health badge does not remain glued to the committed endpoint
                // while the artwork is travelling between cells.
                if let animation = session.movementAnimation,
                   unit == animation.unit,
                   point == animation.from || point == animation.to {
                    continue
                }

                let rect = tileRect(for: point, inset: 0)
                let isCurrentCPUMovement = session.activeArmyIsCPU
                    && session.isCPUMovementAnimating
                    && session.cpuMovementPath.last == point
                if session.movedCells.contains(point), unit.army == session.activeArmy, !isCurrentCPUMovement {
                    context.fill(
                        tilePath(for: point, inset: 0),
                        with: .color(shadowColor.opacity(reduceTransparency ? 0.18 : 0.30))
                    )
                }

                let hasMoved = session.movedCells.contains(point)
                    && unit.army == session.activeArmy
                if session.ruleset.showsMovedUnitBadge, hasMoved, !isCurrentCPUMovement {
                    drawMovedUnitBadge(at: rect, context: &context)
                }

                let health = session.unitHealth[point, default: 100]
                // The playtest rules expose unit health as whole tens. Keep
                // damaged units at a visible 1 rather than letting a nearly
                // destroyed unit disappear from the badge entirely.
                let displayHealth = max(1, min(10, health / 10))
                guard displayHealth < 10 else { continue }
                drawDamageBadge(
                    displayHealth,
                    at: rect,
                    theme: damageBadgeTheme,
                    context: &context
                )
            }
        }
    }

    private func drawDamageBadge(
        _ displayHealth: Int,
        at tileRect: CGRect,
        theme: PlaytestDamageBadgeTheme,
        context: inout GraphicsContext
    ) {
        let badgeRect = CGRect(
            x: tileRect.minX + theme.offset.x,
            y: tileRect.maxY - theme.offset.y - theme.size.height,
            width: theme.size.width,
            height: theme.size.height
        )

        if theme.shadowOpacity > 0 {
            let shadowRect = badgeRect.offsetBy(
                dx: theme.shadowOffset.width,
                dy: theme.shadowOffset.height
            )
            context.fill(
                Path(roundedRect: shadowRect, cornerRadius: theme.cornerRadius),
                with: .color(theme.shadow.opacity(theme.shadowOpacity))
            )
        }

        context.fill(
            Path(roundedRect: badgeRect, cornerRadius: theme.cornerRadius),
            with: .color(theme.background)
        )
        if theme.borderWidth > 0 {
            let borderRect = badgeRect.insetBy(
                dx: theme.borderWidth / 2,
                dy: theme.borderWidth / 2
            )
            context.stroke(
                Path(
                    roundedRect: borderRect,
                    cornerRadius: max(0, theme.cornerRadius - theme.borderWidth / 2)
                ),
                with: .color(theme.border),
                style: StrokeStyle(lineWidth: theme.borderWidth)
            )
        }

        let text = context.resolve(
            Text("\(displayHealth)")
                .font(theme.font)
                .foregroundStyle(theme.text)
        )
        context.draw(
            text,
            at: CGPoint(x: badgeRect.midX, y: badgeRect.midY),
            anchor: .center
        )
    }

    /// Famicom Wars and GB Wars use a small `E` indicator for a unit that has
    /// already acted this turn. Its lower-right placement leaves the health
    /// badge in the lower-left corner when both markers are present.
    private func drawMovedUnitBadge(at rect: CGRect, context: inout GraphicsContext) {
        let theme = PlaytestStatusTheme(tileset: session.map.tileset)
        let isFamicom = session.map.tileset == .famicomWars
        let background = isFamicom ? FamicomPPUPalette.black : theme.outerBorder
        let foreground = isFamicom ? FamicomPPUPalette.white : theme.surface
        let border = isFamicom ? FamicomPPUPalette.white : theme.innerBorder
        let badgeRect = CGRect(
            x: rect.maxX - 12,
            y: rect.maxY - 12,
            width: 11,
            height: 11
        )

        context.fill(
            Path(roundedRect: badgeRect, cornerRadius: 1.5),
            with: .color(background.opacity(reduceTransparency ? 0.88 : 0.96))
        )
        context.stroke(
            Path(roundedRect: badgeRect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 1),
            with: .color(border),
            style: StrokeStyle(lineWidth: 1)
        )

        let text = context.resolve(
            Text("E")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(foreground)
        )
        context.draw(text, at: CGPoint(x: badgeRect.midX, y: badgeRect.midY), anchor: .center)
    }

    /// Draws the currently moving unit at the latest committed cell. Keeping
    /// this separate from the backdrop makes every intermediate tile visible
    /// even if SwiftUI coalesces two map redraws; there is deliberately no
    /// interpolation between `from` and `to`.
    private func drawMovingUnit(
        _ animation: PlaytestMovementAnimation,
        context: inout GraphicsContext
    ) {
        guard session.isVisible(animation.from) || session.isVisible(animation.to),
              let image = atlas.image(for: animation.unit, palette: session.displayPalette) else { return }

        // Movement is intentionally stepped, not interpolated. The map state
        // and this render-only sprite both switch to `to` for one whole delay,
        // then advance to the next legal tile.
        let origin = MapCanvasMetrics.tileOrigin(
            x: animation.to.x,
            y: animation.to.y,
            tileSize: tileSize,
            staggered: session.isStaggeredGrid
        )
        let rect = CGRect(
            origin: origin,
            size: CGSize(width: tileSize, height: tileSize)
        )
        context.draw(context.resolve(image), in: rect)
    }

    /// Draws a planned route as a strict cardinal path through tile centres.
    /// The final segment receives an arrowhead, keeping both CPU routes and
    /// player drag previews tile-bound instead of turning into a free-form
    /// cursor marker.
    private func drawMovementPath(_ points: [GridPoint], context: inout GraphicsContext) {
        guard points.count > 1 else { return }

        let centers = points.map { point in
            let rect = tileRect(for: point, inset: 0)
            return CGPoint(x: rect.midX, y: rect.midY)
        }

        var shaft = Path()
        shaft.move(to: centers[0])
        for center in centers.dropFirst() {
            shaft.addLine(to: center)
        }

        let pathBase = session.map.tileset == .famicomWars
            ? FamicomPPUPalette.orange
            : Color.orange
        let pathShadow = session.map.tileset == .famicomWars
            ? FamicomPPUPalette.black
            : Color.black
        let orange = pathBase.opacity(0.88)
        context.stroke(
            shaft,
            with: .color(pathShadow.opacity(0.20)),
            style: StrokeStyle(
                lineWidth: max(7, tileSize * 0.28),
                lineCap: .round,
                lineJoin: .round
            )
        )
        context.stroke(
            shaft,
            with: .color(orange),
            style: StrokeStyle(
                lineWidth: max(4, tileSize * 0.17),
                lineCap: .round,
                lineJoin: .round
            )
        )

        guard let previous = centers.dropLast().last,
              let tip = centers.last else { return }
        let direction = CGPoint(x: tip.x - previous.x, y: tip.y - previous.y)
        let length = hypot(direction.x, direction.y)
        guard length > 0 else { return }

        let unit = CGPoint(x: direction.x / length, y: direction.y / length)
        let perpendicular = CGPoint(x: -unit.y, y: unit.x)
        let headLength = min(tileSize * 0.46, length * 0.65)
        let headWidth = min(tileSize * 0.34, headLength * 0.82)
        let base = CGPoint(
            x: tip.x - unit.x * headLength,
            y: tip.y - unit.y * headLength
        )
        let left = CGPoint(
            x: base.x + perpendicular.x * headWidth,
            y: base.y + perpendicular.y * headWidth
        )
        let right = CGPoint(
            x: base.x - perpendicular.x * headWidth,
            y: base.y - perpendicular.y * headWidth
        )

        var head = Path()
        head.move(to: tip)
        head.addLine(to: left)
        head.addLine(to: right)
        head.closeSubpath()
        context.fill(head, with: .color(orange))
    }

    private func drawTransportMarkers(context: inout GraphicsContext) {
        let cyan = session.map.tileset == .famicomWars ? FamicomPPUPalette.cyan : Color.cyan
        let mint = session.map.tileset == .famicomWars ? FamicomPPUPalette.paleGreen : Color.mint
        let orange = session.map.tileset == .famicomWars ? FamicomPPUPalette.orange : Color.orange
        let green = session.map.tileset == .famicomWars ? FamicomPPUPalette.green : Color.green

        for point in session.loadableCells {
            drawMarker("↓", at: point, color: cyan, context: &context)
        }
        for point in session.joinableCells {
            drawMarker("+", at: point, color: mint, context: &context)
        }
        for point in session.unloadableCells {
            drawMarker("↑", at: point, color: orange, context: &context)
        }
        for point in session.refuelableCells {
            drawMarker("+", at: point, color: green, context: &context)
        }
        if let selectedPoint = session.selectedPoint, session.selectedCargoCount > 0 {
            drawMarker("↑", at: selectedPoint, color: orange, context: &context, corner: .topTrailing)
        }
    }

    private func drawMarker(
        _ symbol: String,
        at point: GridPoint,
        color: Color,
        context: inout GraphicsContext,
        corner: UnitPoint = .center
    ) {
        let rect = tileRect(for: point, inset: 0)
        let position: CGPoint
        switch corner {
        case .topTrailing:
            position = CGPoint(x: rect.maxX - 8, y: rect.minY + 8)
        default:
            position = CGPoint(x: rect.midX, y: rect.midY)
        }
        let text = context.resolve(
            Text(symbol)
                .font(.system(size: corner == .center ? 14 : 11, weight: .black, design: .rounded))
                .foregroundStyle(color)
        )
        context.draw(text, at: position, anchor: .center)
    }
}
