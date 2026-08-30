import SwiftUI
import AWEDCore

struct AWEDCommands: Commands {
    let model: EditorModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New", action: model.requestNewDocument)
                .keyboardShortcut("n")
            Button("Open…") {
                guard let url = FilePanelService.openMap() else { return }
                model.requestOpenDocument(url: url)
            }
            .keyboardShortcut("o")
            Button("Save") {
                guard let url = model.filename else {
                    guard let url = FilePanelService.saveMap(defaultURL: nil) else { return }
                    do { _ = try model.save(to: url) } catch { model.presentError(error) }
                    return
                }
                do { _ = try model.save(to: url) } catch { model.presentError(error) }
            }
            .keyboardShortcut("s")
            Divider()
            Button("Save Screenshot…") {
                guard let request = FilePanelService.saveScreenshot(defaultURL: model.filename) else { return }
                do {
                    let image = ScreenshotRenderer.render(map: model.map, atlas: SpriteAtlas(), palette: model.renderPalette)
                    try ScreenshotRenderer.write(ScreenshotRenderer.apply(request.size, to: image), to: request.url)
                } catch { model.presentError(error) }
            }
            Divider()
            Button("Close", action: model.requestCloseDocument)
                .keyboardShortcut("w")
        }

        CommandGroup(after: .undoRedo) {
            Button("Undo", action: model.undo)
                .keyboardShortcut("z")
                .disabled(!model.canUndo)
            Button("Redo", action: model.redo)
                .keyboardShortcut("y")
                .disabled(!model.canRedo)
        }

        CommandMenu("Edit") {
            Button("Cut") { model.cutSelection() }.keyboardShortcut("x")
            Button("Copy") { model.copySelection() }.keyboardShortcut("c")
            Button("Paste") { model.pasteSelection() }.keyboardShortcut("v")
            Button("Paste Terrain") { model.pasteSelection(terrainOnly: true) }
            Button("Paste Units") { model.pasteSelection(unitsOnly: true) }
            Divider()
            Button("Select All") {
                model.setTool(.selector)
                model.selection = SelectionRect(x: 0, y: 0, width: model.map.width, height: model.map.height)
                model.selectionFragment = MapFragment(map: model.map, x: 0, y: 0, width: model.map.width, height: model.map.height)
            }
            .keyboardShortcut("a")
            Button("Cancel Selection", action: model.cancelSelection)
                .keyboardShortcut(.escape)
            Button("Remove Selection") {
                model.cutSelection()
            }
            .keyboardShortcut(.delete)
            Divider()
            Button("Flip Horizontally") { model.flipSelection(horizontal: true) }
            Button("Flip Vertically") { model.flipSelection(horizontal: false) }
            Button("Rotate 90° Clockwise") { model.rotateSelection(clockwise: true) }
            Button("Rotate 90° Counter-clockwise") { model.rotateSelection(clockwise: false) }
            Divider()
            Button("Delete Units") { model.deleteUnitsInSelection() }
            Button("Delete All Units", action: model.deleteAllUnits)
        }

        CommandMenu("Map") {
            Button("Fill Sea") { model.fill(.terrainSea) }
            Button("Fill Plains") { model.fill(.terrainPlain) }
            Button("Fill Woods") { model.fill(.terrainWood) }
            Button("Fill Mountains") { model.fill(.terrainMountain) }
            Button("Fill Roads") { model.fill(.terrainRoad) }
            Divider()
            Button("Information…") { model.dialog = .information }
                .keyboardShortcut("i")
            Button("Settings…") { model.dialog = .settings }
            Button("Status…") { model.dialog = .status }
        }

        CommandGroup(replacing: .appInfo) {
            Button("About AW Map Editor", systemImage: "info.circle") {
                openWindow(id: AWEDWindowID.about)
            }
        }

        CommandGroup(after: .help) {
            Button("Privacy Policy", systemImage: "hand.raised") {
                openWindow(id: AWEDWindowID.privacyPolicy)
            }
        }
    }
}
