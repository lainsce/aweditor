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
            NativeToolbarMenuButton(title: "Map", systemImage: "map") {
                Button("Information…", systemImage: "info.circle") { model.dialog = .information }
                Button("Settings…", systemImage: "slider.horizontal.3") { model.dialog = .settings }
                Button("Status…", systemImage: "chart.bar") { model.dialog = .status }
            }
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarSpacer(.fixed)
            .sharedBackgroundVisibility(.hidden)

        ToolbarItemGroup(placement: .navigation) {
            NativeToolbarControlGroup {
                Button(action: newAction) {
                    NativeToolbarIcon(systemImage: "doc.badge.plus")
                }
                    .frame(minWidth: 38, minHeight: 38, maxHeight: 38)
                    .accessibilityLabel("New")
                    .help("Create a new map")
                Button(action: openAction) {
                    NativeToolbarIcon(systemImage: "folder")
                }
                    .frame(minWidth: 38, minHeight: 38, maxHeight: 38)
                    .accessibilityLabel("Open")
                    .help("Open a saved map")
                Button(action: saveAction) {
                    NativeToolbarIcon(systemImage: "square.and.arrow.down")
                }
                    .frame(minWidth: 38, minHeight: 38, maxHeight: 38)
                    .accessibilityLabel("Save")
                    .disabled(!model.map.isDirty && model.filename != nil)
                    .help("Save the current map")
            }
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarSpacer(.fixed)
            .sharedBackgroundVisibility(.hidden)

        ToolbarItemGroup(placement: .navigation) {
            NativeToolbarControlGroup {
                Button(action: model.undo) {
                    NativeToolbarIcon(systemImage: "arrow.uturn.backward")
                }
                    .frame(minWidth: 38, minHeight: 38, maxHeight: 38)
                    .accessibilityLabel("Undo")
                    .disabled(!model.canUndo)
                Button(action: model.redo) {
                    NativeToolbarIcon(systemImage: "arrow.uturn.forward")
                }
                    .frame(minWidth: 38, minHeight: 38, maxHeight: 38)
                    .accessibilityLabel("Redo")
                    .disabled(!model.canRedo)
            }
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarSpacer()
            .sharedBackgroundVisibility(.hidden)

        ToolbarItem(placement: .primaryAction) {
            NativeToolbarControlGroup {
                NativeSegmentedPicker(
                    selection: Binding(
                        get: { model.selectedTool },
                        set: { model.setTool($0) }
                    ),
                    options: EditorTool.allCases
                ) { tool in
                    NativeToolbarIcon(systemImage: tool.systemImage)
                        .frame(minWidth: 38, minHeight: 32, maxHeight: 32)
                        .accessibilityLabel(tool.title)
                }
                .frame(minWidth: CGFloat(EditorTool.allCases.count * 38), maxHeight: 38)
                .help("Drawing tool")
            }
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarSpacer(.fixed)
            .sharedBackgroundVisibility(.hidden)

        ToolbarItemGroup(placement: .primaryAction) {
            NativeToolbarMenuButton(title: "More", systemImage: "ellipsis.circle") {
                Button("Save As…", systemImage: "square.and.arrow.down.on.square", action: saveAsAction)
                Button("Save Screenshot…", systemImage: "photo", action: screenshotAction)
                Divider()
                Button("Preferences…", systemImage: "gearshape", action: { model.dialog = .preferences })
            }
        }
        .sharedBackgroundVisibility(.hidden)
    }
}
