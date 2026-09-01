import AppKit
import Foundation
import Observation
import AWEDCore

extension EditorModel {
    func addUndoPoint() {
        undoStack.append(map)
        if undoStack.count > preferences.undoLimit { undoStack.removeFirst(undoStack.count - preferences.undoLimit) }
        redoStack.removeAll()
    }

    func markSelectionModified() {
        selectionNeedsCommit = true
        if !selectionIsOverlay, selectionEraseRect == nil {
            selectionEraseRect = selection
        }
    }

    private func ensureSelectionUndoPoint() {
        guard !selectionUndoRecorded else { return }
        addUndoPoint()
        selectionUndoRecorded = true
    }

    func clearSelection() {
        selection = nil
        selectionFragment = nil
        previewCells.removeAll()
        movingSelectionOrigin = nil
        movingSelection = false
        selectionNeedsCommit = false
        selectionUndoRecorded = false
        selectionEraseRect = nil
        selectionIsOverlay = false
    }

    func commitSelection() {
        commitSelection(allowMultipleHQ: true)
    }

    func commitSelection(allowMultipleHQ: Bool) {
        guard let selection, let fragment = selectionFragment else { clearSelection(); return }
        let moved = movingSelectionOrigin.map { $0 != selection } ?? false
        guard selectionNeedsCommit || moved else { clearSelection(); return }
        ensureSelectionUndoPoint()
        if !selectionIsOverlay {
            if let origin = movingSelectionOrigin, moved {
                eraseSelectionContents(origin)
            } else if let eraseRect = selectionEraseRect {
                eraseSelectionContents(eraseRect)
            }
        }
        apply(fragment, at: selection.x, y: selection.y, allowMultipleHQ: allowMultipleHQ)
        clearSelection()
    }

    func eraseSelectionContents(_ rect: SelectionRect?) {
        guard let rect else { return }
        for x in rect.x..<(rect.x + rect.width) {
            for y in rect.y..<(rect.y + rect.height) {
                _ = map.setBackground(preferences.defaultTerrain, atX: x, y: y, check: false)
                _ = map.setForeground(.unitEmpty, atX: x, y: y)
            }
        }
        map.updateDraw(x: rect.x - 2, y: rect.y - 2, width: rect.width + 4, height: rect.height + 4)
    }

    private func apply(_ fragment: MapFragment?, at x: Int, y: Int, allowMultipleHQ: Bool) {
        guard let fragment else { return }
        for localX in 0..<fragment.width {
            for localY in 0..<fragment.height {
                let targetX = x + localX
                let targetY = y + localY
                let background = fragment.backgroundElement(atX: localX, y: localY)
                if background != .terrainBlank { _ = map.setBackground(background, atX: targetX, y: targetY, check: false) }
                _ = map.setForeground(fragment.foregroundElement(atX: localX, y: localY), atX: targetX, y: targetY)
            }
        }
        map.updateDraw(x: x - 2, y: y - 2, width: fragment.width + 4, height: fragment.height + 4)
        _ = allowMultipleHQ
    }

    func writeClipboard(_ fragment: MapFragment) {
        guard let data = try? JSONEncoder().encode(fragment) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: clipboardType)
    }

    func readClipboard() -> MapFragment? {
        guard let data = NSPasteboard.general.data(forType: clipboardType) else { return nil }
        return try? JSONDecoder().decode(MapFragment.self, from: data)
    }

    func flipSelection(horizontal: Bool) {
        guard var fragment = selectionFragment else { return }
        markSelectionModified()
        fragment = flippedFragment(fragment, horizontal: horizontal)
        selectionFragment = fragment
    }

    private func flippedFragment(_ fragment: MapFragment, horizontal: Bool) -> MapFragment {
        var result = fragment
        for x in 0..<fragment.width {
            for y in 0..<fragment.height {
                copyFlippedCell(from: fragment, to: &result, x: x, y: y, horizontal: horizontal)
            }
        }
        return result
    }

    private func copyFlippedCell(from fragment: MapFragment, to result: inout MapFragment, x: Int, y: Int, horizontal: Bool) {
        let targetX = horizontal ? fragment.width - x - 1 : x
        let targetY = horizontal ? y : fragment.height - y - 1
        let source = x * fragment.height + y
        let target = targetX * fragment.height + targetY
        result.background[target] = fragment.background[source]
        result.backgroundDraw[target] = fragment.backgroundDraw[source]
        result.foreground[target] = fragment.foreground[source]
    }

    func rotateSelection(clockwise: Bool) {
        guard let fragment = selectionFragment else { return }
        markSelectionModified()
        let rotated = rotatedFragment(fragment, clockwise: clockwise)
        selectionFragment = rotated
        if let selection {
            self.selection = SelectionRect(x: selection.x, y: selection.y, width: rotated.width, height: rotated.height)
        }
    }

    private func rotatedFragment(_ fragment: MapFragment, clockwise: Bool) -> MapFragment {
        var rotated = MapFragment(
            width: fragment.height,
            height: fragment.width,
            background: Array(repeating: .terrainSea, count: fragment.width * fragment.height),
            backgroundDraw: Array(repeating: .terrainSea, count: fragment.width * fragment.height),
            foreground: Array(repeating: .unitEmpty, count: fragment.width * fragment.height)
        )
        for x in 0..<fragment.width {
            for y in 0..<fragment.height {
                copyRotatedCell(from: fragment, to: &rotated, x: x, y: y, clockwise: clockwise)
            }
        }
        return rotated
    }

    private func copyRotatedCell(from fragment: MapFragment, to result: inout MapFragment, x: Int, y: Int, clockwise: Bool) {
        let targetX = clockwise ? fragment.height - y - 1 : y
        let targetY = clockwise ? x : fragment.width - x - 1
        result.setBackground(fragment.backgroundElement(atX: x, y: y), atX: targetX, y: targetY)
        result.setBackgroundDraw(fragment.backgroundDrawElement(atX: x, y: y), atX: targetX, y: targetY)
        result.setForeground(fragment.foregroundElement(atX: x, y: y), atX: targetX, y: targetY)
    }

    func deleteUnitsInSelection() {
        guard var fragment = selectionFragment else { return }
        markSelectionModified()
        fragment.foreground = Array(repeating: .unitEmpty, count: fragment.width * fragment.height)
        selectionFragment = fragment
    }
}
