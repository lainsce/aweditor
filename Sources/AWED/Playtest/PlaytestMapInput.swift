import AppKit
import SwiftUI
import AWEDCore


struct PlaytestMapInput: NSViewRepresentable {
    let session: PlaytestSession
    let previewModel: EditorModel
    let tileSize: CGFloat

    func makeNSView(context: Context) -> MonitorView {
        MonitorView(session: session, previewModel: previewModel, tileSize: tileSize)
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.session = session
        nsView.previewModel = previewModel
        nsView.tileSize = tileSize
    }

    @MainActor
    final class MonitorView: NSView {
        var session: PlaytestSession
        var previewModel: EditorModel
        var tileSize: CGFloat
        private var eventMonitor: Any?

        init(session: PlaytestSession, previewModel: EditorModel, tileSize: CGFloat) {
            self.session = session
            self.previewModel = previewModel
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
                matching: [.rightMouseDown, .otherMouseDown]
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
            // Pre-DS cartridges are keyboard-only in playtest. Keep the map
            // monitor alive for the view lifecycle, but do not let a secondary
            // click bypass the A/B/Select command model.
            guard !session.ruleset.usesLegacyKeyboardControls else { return event }
            let location = convert(event.locationInWindow, from: nil)
            guard bounds.contains(location) else { return event }
            guard event.type == .rightMouseDown || event.buttonNumber == 2 else { return event }

            // SwiftUI's interaction layer and the editor both use a top-left
            // origin. Keep secondary-click hit testing in that same coordinate
            // space; inverting Y here made right-click previews select the
            // mirrored row and made the marker appear upside-down.
            let y = Int(floor(location.y / tileSize))
            let rowOffset = session.isStaggeredGrid && y % 2 != 0 ? tileSize / 2 : 0
            let point = GridPoint(
                x: Int(floor((location.x - rowOffset) / tileSize)),
                y: y
            )
            previewModel.updatePointer(point)
            session.handleSecondaryTap(point)
            return nil
        }
    }
}
