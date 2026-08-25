import SwiftUI
import AWEDCore

struct PlaytestInteractionLayer: View {
    let session: PlaytestSession
    let previewModel: EditorModel
    let tileSize: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isDragging = false
    @State private var movedDuringDrag = false

    var body: some View {
        Canvas { context, _ in
            let movementGlass = Color(red: 0.10, green: 0.52, blue: 1.0)
            let attackGlass = Color(red: 1.0, green: 0.16, blue: 0.20)
            let captureFill = Color.yellow.opacity(reduceTransparency ? 0.12 : 0.28)
            let captureStroke = Color.yellow.opacity(reduceTransparency ? 0.50 : 0.90)
            let loadFill = Color.cyan.opacity(reduceTransparency ? 0.10 : 0.18)
            let loadStroke = Color.cyan.opacity(reduceTransparency ? 0.42 : 0.80)
            let unloadFill = Color.orange.opacity(reduceTransparency ? 0.10 : 0.18)
            let unloadStroke = Color.orange.opacity(reduceTransparency ? 0.42 : 0.80)
            let refuelFill = Color.green.opacity(reduceTransparency ? 0.10 : 0.18)
            let refuelStroke = Color.green.opacity(reduceTransparency ? 0.42 : 0.80)
            let joinFill = Color.mint.opacity(reduceTransparency ? 0.08 : 0.16)
            let joinStroke = Color.mint.opacity(reduceTransparency ? 0.40 : 0.75)
            let siloFill = Color.purple.opacity(reduceTransparency ? 0.08 : 0.16)
            let siloStroke = Color.purple.opacity(reduceTransparency ? 0.40 : 0.75)

            drawFogOverlay(context: &context)

            // Blue-glass reachable cells are a player affordance. CPU turns
            // keep only the current-unit marker below so the AI's planning
            // does not look like a set of destinations the player can tap.
            if !session.activeArmyIsCPU {
                for point in session.reachableCells {
                    drawGlassTile(point, base: movementGlass, context: &context)
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
            drawMovementPath(session.cpuMovementPath, context: &context)
            drawMovementPath(session.playerMovementPath, context: &context)
            drawTransportMarkers(context: &context)

            if let attackPreviewOrigin = session.attackPreviewOrigin {
                context.stroke(
                    tilePath(for: attackPreviewOrigin, inset: 0.5),
                    with: .color(Color.white.opacity(0.85)),
                    style: StrokeStyle(lineWidth: 2)
                )
                context.stroke(
                    tilePath(for: attackPreviewOrigin, inset: 2.5),
                    with: .color(attackGlass.opacity(0.9)),
                    style: StrokeStyle(lineWidth: 1)
                )
            }

            if let selectedPoint = session.selectedPoint, !session.activeArmyIsCPU {
                context.stroke(tilePath(for: selectedPoint, inset: 0.5), with: .color(.white.opacity(0.95)), style: StrokeStyle(lineWidth: 2))
                context.stroke(tilePath(for: selectedPoint, inset: 2.5), with: .color(Color.accentColor), style: StrokeStyle(lineWidth: 1))
            }
        }
        .contentShape(Rectangle())
        .gesture(pointerGesture)
        .background {
            PlaytestMapInput(session: session, previewModel: previewModel, tileSize: tileSize)
                .allowsHitTesting(false)
        }
        .accessibilityElement()
        .accessibilityLabel("Playtest map")
        .accessibilityValue(session.statusMessage)
        .accessibilityHint("Select a unit, drag across blue movement tiles to plan a route, release to move, choose a highlighted destination or target, or right-click a unit to preview its attacks. Use the inspector for capture, refueling, depth, missile silos, and production actions.")
        .accessibilityAddTraits(.isButton)
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

    private func drawGlassTile(_ point: GridPoint, base: Color, context: inout GraphicsContext) {
        let rect = tileRect(for: point, inset: 1)
        let fillOpacity = reduceTransparency ? 0.56 : 0.30
        let edgeOpacity = reduceTransparency ? 0.72 : 0.48
        let innerOpacity = reduceTransparency ? 0.86 : 0.66
        let path = tilePath(for: point, inset: 1)
        let innerPath = tilePath(for: point, inset: 2.5)

        context.fill(
            path,
            with: .linearGradient(
                Gradient(colors: [
                    Color.white.opacity(reduceTransparency ? 0.24 : 0.16),
                    base.opacity(fillOpacity),
                    base.opacity(fillOpacity * 0.58)
                ]),
                startPoint: CGPoint(x: rect.midX, y: rect.minY),
                endPoint: CGPoint(x: rect.midX, y: rect.maxY)
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
        for x in 0..<session.map.width {
            for y in 0..<session.map.height {
                let point = GridPoint(x: x, y: y)
                let unit = session.map.foregroundElement(atX: x, y: y)
                guard unit.isUnitNonEmpty, session.isVisible(point) else { continue }

                let rect = tileRect(for: point, inset: 0)
                let isCurrentCPUMovement = session.activeArmyIsCPU
                    && session.isCPUMovementAnimating
                    && session.cpuMovementPath.last == point
                if session.movedCells.contains(point), unit.army == session.activeArmy, !isCurrentCPUMovement {
                    context.fill(
                        tilePath(for: point, inset: 0),
                        with: .color(Color.black.opacity(reduceTransparency ? 0.18 : 0.30))
                    )
                }

                let health = session.unitHealth[point, default: 100]
                // Advance Wars renders the unit's health as whole tens. Keep
                // damaged units at a visible 1 rather than letting a nearly
                // destroyed unit disappear from the badge entirely.
                let displayHealth = max(1, min(10, health / 10))
                guard displayHealth < 10 else { continue }
                let badgeRect = CGRect(
                    x: rect.minX + 2,
                    y: rect.maxY - 13,
                    width: 14,
                    height: 11
                )
                context.fill(
                    Path(roundedRect: badgeRect, cornerRadius: 2),
                    with: .color(Color.black.opacity(reduceTransparency ? 0.62 : 0.78))
                )

                let text = context.resolve(
                    Text("\(displayHealth)")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                )
                context.draw(text, at: CGPoint(x: badgeRect.midX, y: badgeRect.midY), anchor: .center)
            }
        }
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

        let orange = Color.orange.opacity(0.88)
        context.stroke(
            shaft,
            with: .color(Color.black.opacity(0.20)),
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
        for point in session.loadableCells {
            drawMarker("↓", at: point, color: .cyan, context: &context)
        }
        for point in session.joinableCells {
            drawMarker("+", at: point, color: .mint, context: &context)
        }
        for point in session.unloadableCells {
            drawMarker("↑", at: point, color: .orange, context: &context)
        }
        for point in session.refuelableCells {
            drawMarker("+", at: point, color: .green, context: &context)
        }
        if let selectedPoint = session.selectedPoint, session.selectedCargoCount > 0 {
            drawMarker("↑", at: selectedPoint, color: .orange, context: &context, corner: .topTrailing)
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
