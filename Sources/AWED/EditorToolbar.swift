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
            GLWNToolbarMenuButton(title: "Map", systemImage: "map") {
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
        .sharedBackgroundVisibility(.hidden)

        ToolbarSpacer(.fixed)

        ToolbarItemGroup(placement: .navigation) {
            GLWNToolbarControlGroup {
                Button("New", systemImage: "doc.badge.plus", action: newAction)
                    .frame(minWidth: 38, minHeight: 38, maxHeight: 38)
                    .help("Create a new map")
                Button("Open", systemImage: "folder", action: openAction)
                    .frame(minWidth: 38, minHeight: 38, maxHeight: 38)
                    .help("Open a saved map")
                Button("Save", systemImage: "square.and.arrow.down", action: saveAction)
                    .frame(minWidth: 38, minHeight: 38, maxHeight: 38)
                    .disabled(!model.map.isDirty && model.filename != nil)
                    .help("Save the current map")
            }
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarSpacer(.fixed)

        ToolbarItemGroup(placement: .navigation) {
            GLWNToolbarControlGroup {
                Button("Undo", systemImage: "arrow.uturn.backward", action: model.undo)
                    .frame(minWidth: 38, minHeight: 38, maxHeight: 38)
                    .disabled(!model.canUndo)
                Button("Redo", systemImage: "arrow.uturn.forward", action: model.redo)
                    .frame(minWidth: 38, minHeight: 38, maxHeight: 38)
                    .disabled(!model.canRedo)
            }
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarSpacer()

        ToolbarItem(placement: .primaryAction) {
            GLWNSegmentedPicker(
                selection: Binding(
                    get: { model.selectedTool },
                    set: { model.setTool($0) }
                ),
                options: EditorTool.allCases
            ) { tool in
                Label(tool.title, systemImage: tool.systemImage)
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 38, minHeight: 32, maxHeight: 32)
                    .accessibilityLabel(tool.title)
            }
            .frame(minWidth: CGFloat(EditorTool.allCases.count * 38), maxHeight: 38)
            .help("Drawing tool")
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarSpacer(.fixed)

        ToolbarItemGroup(placement: .primaryAction) {
            GLWNToolbarMenuButton(title: "More", systemImage: "ellipsis.circle") {
                Button("Save As…", systemImage: "square.and.arrow.down.on.square", action: saveAsAction)
                Button("Save Screenshot…", systemImage: "photo", action: screenshotAction)
                Divider()
                Button("Preferences…", systemImage: "gearshape", action: { model.dialog = .preferences })
            }
        }
        .sharedBackgroundVisibility(.hidden)
    }
}
