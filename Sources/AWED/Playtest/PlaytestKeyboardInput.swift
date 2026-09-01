import AppKit
import SwiftUI
import AWEDCore


struct PlaytestKeyboardInput: NSViewRepresentable {
    let session: PlaytestSession
    let onKey: (PlaytestLegacyKey) -> Void

    func makeNSView(context: Context) -> MonitorView {
        MonitorView(session: session, onKey: onKey)
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.session = session
        nsView.onKey = onKey
        nsView.claimFirstResponderIfNeeded()
    }

    @MainActor
    final class MonitorView: NSView {
        var session: PlaytestSession
        var onKey: (PlaytestLegacyKey) -> Void
        private var fallbackMonitor: Any?
        private var focusTask: Task<Void, Never>?

        init(session: PlaytestSession, onKey: @escaping (PlaytestLegacyKey) -> Void) {
            self.session = session
            self.onKey = onKey
            super.init(frame: .zero)
            wantsLayer = false
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeFallbackMonitor()
            focusTask?.cancel()
            focusTask = nil

            guard let window else { return }
            fallbackMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.keyDown, .keyUp, .leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] event in
                guard let self, event.window === window else { return event }

                if event.type == .leftMouseDown
                    || event.type == .rightMouseDown
                    || event.type == .otherMouseDown {
                    // Clicking a command-rail button may temporarily make the
                    // button first responder. Reclaim the keyboard after its
                    // tracking loop completes; this monitor does not consume
                    // the click.
                    self.claimFirstResponderIfNeeded()
                    return event
                }

                guard self.session.ruleset.usesLegacyKeyboardControls,
                      let key = Self.key(for: event),
                      window.firstResponder !== self,
                      event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
                    return event
                }

                // The direct responder normally receives this event. If a
                // SwiftUI control owns focus instead, consume it here so it
                // cannot fall through to NSResponder's alert beep. Returning
                // nil is safe because the direct path was not eligible.
                if event.type == .keyDown {
                    if self.session.isStarted,
                       !(event.isARepeat && key.isButton),
                       !self.session.isGameOver {
                        self.onKey(key)
                    }
                }
                return nil
            }
            claimFirstResponderIfNeeded()
        }

        isolated deinit {
            focusTask?.cancel()
            removeFallbackMonitor()
        }

        private func removeFallbackMonitor() {
            if let fallbackMonitor {
                NSEvent.removeMonitor(fallbackMonitor)
                self.fallbackMonitor = nil
            }
        }

        override var acceptsFirstResponder: Bool { true }

        override var canBecomeKeyView: Bool { true }

        func claimFirstResponderIfNeeded() {
            guard session.ruleset.usesLegacyKeyboardControls,
                  session.isStarted,
                  let window else { return }
            guard window.firstResponder !== self else { return }

            if focusTask != nil { return }

            // The sheet can finish its first-responder negotiation one run
            // loop after SwiftUI attaches this view. Retry on the main actor;
            // the direct responder path is what prevents AppKit's fallback
            // `noResponderFor:` beep during control tracking.
            focusTask = Task { @MainActor [weak self] in
                defer { self?.focusTask = nil }
                for attempt in 0..<8 {
                    guard let self,
                          let window = self.window,
                          self.session.ruleset.usesLegacyKeyboardControls,
                          self.session.isStarted else { return }
                    if window.firstResponder === self { return }
                    _ = window.makeFirstResponder(self)
                    if window.firstResponder === self { return }
                    if attempt < 7 {
                        try? await Task.sleep(for: .milliseconds(30))
                    }
                }
            }
        }

        override func resignFirstResponder() -> Bool {
            // Once a legacy match is active, keep this catcher in the key
            // view chain even if the user clicks one of the rail buttons.
            // During setup and teardown normal SwiftUI focus changes remain
            // possible.
            if session.ruleset.usesLegacyKeyboardControls, session.isStarted {
                return false
            }
            return super.resignFirstResponder()
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard session.ruleset.usesLegacyKeyboardControls,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  let key = Self.key(for: event) else {
                return super.performKeyEquivalent(with: event)
            }

            // Some AppKit controls ask the first responder to handle a key
            // equivalent before they send keyDown. Claim the event here as
            // well, so the legacy key cannot become an unhandled equivalent
            // (and beep), while still keeping repeat buttons inert.
            if session.isStarted,
               !(event.isARepeat && key.isButton),
               !session.isGameOver {
                onKey(key)
            }
            return true
        }

        private static func key(for event: NSEvent) -> PlaytestLegacyKey? {
            switch event.keyCode {
            case 123: return .left
            case 124: return .right
            case 125: return .down
            case 126: return .up
            default: break
            }

            switch event.charactersIgnoringModifiers?.lowercased() {
            case "z": return .a
            case "x": return .b
            case "s": return .select
            default: return nil
            }
        }

        override func keyDown(with event: NSEvent) {
            guard session.ruleset.usesLegacyKeyboardControls,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  let key = Self.key(for: event) else {
                super.keyDown(with: event)
                return
            }
            // Repeating arrows are useful for cursor travel; repeating A/B or
            // Select would accidentally confirm multiple actions.
            if event.isARepeat, key.isButton { return }
            if session.isStarted, !session.isGameOver {
                onKey(key)
            }
        }

        override func keyUp(with event: NSEvent) {
            guard session.ruleset.usesLegacyKeyboardControls,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  Self.key(for: event) != nil else {
                super.keyUp(with: event)
                return
            }
            // Do not forward the legacy button release to SwiftUI/AppKit.
        }
    }
}
