import SwiftUI
import AppKit

@main
struct AWEDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session: AWEDSession

    init() {
        let session = AWEDSession()
        _session = State(initialValue: session)
        AppDelegate.session = session
    }

    var body: some Scene {
        Window("Advance Wars Series Map Editor", id: "main") {
            ContentView(model: session.model, atlas: session.atlas, music: session.music)
        }
        .commands {
            AWEDCommands(model: session.model)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1024, height: 600)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
    }
}

@MainActor
final class AWEDSession {
    let model: EditorModel
    let atlas: SpriteAtlas
    let music: BackgroundMusicController

    init() {
        model = EditorModel()
        atlas = SpriteAtlas()
        music = BackgroundMusicController()
        music.apply(enabled: model.preferences.volumeEnabled, volume: model.preferences.volume)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var session: AWEDSession?
    private var fallbackWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor [weak self] in
            self?.ensureWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.session?.music.stop()
    }

    private func ensureWindow() {
        guard !NSApp.windows.contains(where: { $0.isVisible }), let session = Self.session else { return }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1024, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Advance Wars Map Editor"
        window.minSize = NSSize(width: 800, height: 600)
        window.contentView = NSHostingView(rootView: ContentView(model: session.model, atlas: session.atlas, music: session.music))
        window.center()
        window.makeKeyAndOrderFront(nil)
        fallbackWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }
}
