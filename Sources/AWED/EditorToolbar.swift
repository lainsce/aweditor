import SwiftUI
import AWEDCore

struct EditorToolbar: ToolbarContent {
    @Bindable var model: EditorModel
    let newAction: () -> Void
    let openAction: () -> Void
    let saveAction: () -> Void
    let saveAsAction: () -> Void
    let screenshotAction: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Menu("Map", systemImage: "map") {
                Menu("Fill") {
                    Button("Sea") { model.fill(.terrainSea) }
                    Button("Plains") { model.fill(.terrainPlain) }
                    Button("Woods") { model.fill(.terrainWood) }
                    Button("Mountains") { model.fill(.terrainMountain) }
                    Button("Roads") { model.fill(.terrainRoad) }
                }
                Divider()
                Button("Information…", systemImage: "info.circle") { model.dialog = .information }
                Button("Settings…", systemImage: "slider.horizontal.3") { model.dialog = .settings }
                Button("Status…", systemImage: "chart.bar") { model.dialog = .status }
            }
        }

        ToolbarSpacer(.fixed)

        ToolbarItemGroup(placement: .navigation) {
            Button("New", systemImage: "doc.badge.plus", action: newAction)
                .help("Create a new map")
            Button("Open", systemImage: "folder", action: openAction)
                .help("Open a saved map")
            Button("Save", systemImage: "square.and.arrow.down", action: saveAction)
                .disabled(!model.map.isDirty && model.filename != nil)
                .help("Save the current map")
        }

        ToolbarSpacer(.fixed)

        ToolbarItemGroup(placement: .navigation) {
            Button("Undo", systemImage: "arrow.uturn.backward", action: model.undo)
                .disabled(!model.canUndo)
            Button("Redo", systemImage: "arrow.uturn.forward", action: model.redo)
                .disabled(!model.canRedo)
        }

        ToolbarSpacer()

        ToolbarItem(placement: .primaryAction) {
            Picker("Tool", selection: Binding(
                get: { model.selectedTool },
                set: { model.setTool($0) }
            )) {
                ForEach(EditorTool.allCases) { tool in
                    Label(tool.title, systemImage: tool.systemImage).tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .help("Drawing tool")
        }

        ToolbarSpacer(.fixed)

        ToolbarItemGroup(placement: .primaryAction) {
            Menu("More", systemImage: "ellipsis.circle") {
                Button("Save As…", systemImage: "square.and.arrow.down.on.square", action: saveAsAction)
                Button("Save Screenshot…", systemImage: "photo", action: screenshotAction)
                Divider()
                Button("Preferences…", systemImage: "gearshape", action: { model.dialog = .preferences })
            }
        }
    }
}
