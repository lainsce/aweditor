import SwiftUI
import AWEDCore

struct PlaytestInteractionLayer: View {
    let session: PlaytestSession
    let previewModel: EditorModel
    let atlas: SpriteAtlas
    let tileSize: CGFloat

    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @State var isDragging = false
    @State var movedDuringDrag = false

    var canvas: some View { interactionCanvas }

    var interactionHighlightColor: Color {
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

    var interactionCanvas: some View {
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

    var pointerGesture: some Gesture {
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
}
