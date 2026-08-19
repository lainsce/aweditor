import AppKit
import SwiftUI

/// Bridges the original editor's secondary mouse-button shortcuts into the
/// SwiftUI canvas without replacing its native left-button drawing gesture.
struct MapCanvasInput: NSViewRepresentable {
    let model: EditorModel
    let tileSize: Double

    func makeNSView(context: Context) -> MonitorView {
        MonitorView(model: model, tileSize: tileSize)
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.model = model
        nsView.tileSize = tileSize
    }

    @MainActor
    final class MonitorView: NSView {
        var model: EditorModel
        var tileSize: Double
        private var eventMonitor: Any?

        init(model: EditorModel, tileSize: Double) {
            self.model = model
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
                matching: [.rightMouseDown, .otherMouseDown, .scrollWheel]
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
            guard bounds.contains(location), let point = cell(at: location) else { return event }

            switch event.type {
            case .rightMouseDown:
                model.updatePointer(point)
                model.pick(at: point)
                // Right-click is a picker in the original editor, not a
                // context-menu invocation.
                return nil
            case .otherMouseDown where event.buttonNumber == 2:
                model.advancePaletteTab()
                return nil
            case .scrollWheel:
                guard event.scrollingDeltaY != 0 || event.deltaY != 0 else { return event }
                return model.cycleArmy(for: event.scrollingDeltaY == 0 ? event.deltaY : event.scrollingDeltaY) ? nil : event
            default:
                return event
            }
        }

        private func cell(at location: CGPoint) -> GridPoint? {
            let x = Int(location.x / tileSize)
            let y = Int(location.y / tileSize)
            guard x >= 0, x < model.map.width, y >= 0, y < model.map.height else { return nil }
            return GridPoint(x: x, y: y)
        }
    }
}
