import SwiftUI
import AWEDCore
import AppKit

struct DialogContainer: View {
    let dialog: EditorDialog
    let model: EditorModel
    let music: BackgroundMusicController

    var body: some View {
        Group {
            switch dialog {
            case .information: MapInformationView(model: model)
            case .settings: MapSettingsView(model: model)
            case .status: MapStatusView(model: model)
            case .preferences: PreferencesView(model: model, music: music)
            case .about: AboutView()
            }
        }
        .padding(12)
        .frame(minWidth: dialog == .status ? 600 : 420, minHeight: dialog == .status ? 420 : 280)
    }
}

struct MapInformationView: View {
    let model: EditorModel
    @State private var draftName: String
    @State private var draftAuthor: String
    @State private var draftDescription: String

    init(model: EditorModel) {
        self.model = model
        _draftName = State(initialValue: model.map.name)
        _draftAuthor = State(initialValue: model.map.author)
        _draftDescription = State(initialValue: model.map.description)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Map Information").font(.title2).bold()
            Form {
                NativeFormRow("Map Name") {
                    TextField("", text: $draftName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Map Name")
                        .onChange(of: draftName) { _, newValue in draftName = String(newValue.prefix(AWConstants.nameMaximumLength)) }
                }
                NativeFormRow("Author") {
                    TextField("", text: $draftAuthor)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Author")
                        .onChange(of: draftAuthor) { _, newValue in draftAuthor = String(newValue.prefix(AWConstants.authorMaximumLength)) }
                }
                NativeFormRow("Description") {
                    TextField("", text: $draftDescription, axis: .vertical)
                        .lineLimit(5...12)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Description")
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.dialog = nil }
                    .buttonStyle(.bordered)
                Button("Save") {
                    model.updateInformation(name: draftName, author: draftAuthor, description: draftDescription)
                    model.dialog = nil
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

struct MapSettingsView: View {
    let model: EditorModel
    @State private var width: Int
    @State private var height: Int

    init(model: EditorModel) {
        self.model = model
        _width = State(initialValue: model.map.width)
        _height = State(initialValue: model.map.height)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Map Settings").font(.title2).bold()
            Form {
                NativeFormRow("Width") {
                    NativeTextFieldStepper(
                        value: $width,
                        in: AWConstants.mapMinimumWidth...AWConstants.mapMaximumWidth,
                        step: 1
                    )
                }
                NativeFormRow("Height") {
                    NativeTextFieldStepper(
                        value: $height,
                        in: AWConstants.mapMinimumHeight...AWConstants.mapMaximumHeight,
                        step: 1
                    )
                }
                NativeFormRow("Map art") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.visualVariant.displayName)
                            .font(.body)
                        Text("Choose variants directly in the Map Art tab.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            if width * height >= 100 * 100 {
                Label("Large maps can use substantial memory.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.dialog = nil }
                    .buttonStyle(.bordered)
                Button("Apply") {
                    model.updateSettings(width: width, height: height, tileset: model.visualVariant.baseTileset)
                    model.dialog = nil
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

struct PreferencesView: View {
    let model: EditorModel
    let music: BackgroundMusicController
    @State private var preferences: EditorPreferences

    init(model: EditorModel, music: BackgroundMusicController) {
        self.model = model
        self.music = music
        _preferences = State(initialValue: model.preferences)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Editor Preferences").font(.title2).bold()
            Form {
                Section("Background Music") {
                    NativeFormRow("Enable BGM") {
                        Toggle("", isOn: $preferences.volumeEnabled)
                            .labelsHidden()
                            .toggleStyle(NativeToggleStyle())
                            .accessibilityLabel("Enable background music")
                    }
                    NativeFormRow("Volume") {
                        HStack {
                            NativeSliderField(
                                value: Binding(
                                    get: { Double(preferences.volume) },
                                    set: { preferences.volume = Int($0.rounded()) }
                                ),
                                in: 0...100,
                                step: 1
                            )
                            .accessibilityLabel("Volume")
                            Text("\(preferences.volume)%").monospacedDigit().frame(width: 42, alignment: .trailing)
                        }
                        .frame(maxWidth: .infinity)
                        .disabled(!preferences.volumeEnabled)
                    }
                }
                Section("New Maps") {
                    NativeFormRow("Default width") {
                        NativeTextFieldStepper(
                            value: $preferences.defaultWidth,
                            in: AWConstants.mapMinimumWidth...AWConstants.mapMaximumWidth,
                            step: 1
                        )
                    }
                    NativeFormRow("Default height") {
                        NativeTextFieldStepper(
                            value: $preferences.defaultHeight,
                            in: AWConstants.mapMinimumHeight...AWConstants.mapMaximumHeight,
                            step: 1
                        )
                    }
                    NativeFormRow("Default terrain") {
                        NativePullDownMenu(
                            "Default terrain",
                            selection: $preferences.defaultTerrain,
                            options: terrainOptions,
                            showsTitle: false
                        ) { terrain in
                            Text(terrainTitle(terrain))
                        }
                    }
                    NativeFormRow("Undo/redo limit") {
                        NativePullDownMenu(
                            "Undo/redo limit",
                            selection: $preferences.undoLimit,
                            options: [10, 20, 30, 40, 50, 100],
                            showsTitle: false
                        ) { value in
                            Text("\(value)")
                        }
                    }
                    NativeFormRow("Default author") {
                        TextField("", text: $preferences.defaultAuthor)
                            .textFieldStyle(.bordered)
                            .frame(alignment: .leading)
                            .accessibilityLabel("Default author")
                            .onChange(of: preferences.defaultAuthor) { _, newValue in preferences.defaultAuthor = String(newValue.prefix(AWConstants.authorMaximumLength)) }
                    }
                }
                Section("Interaction") {
                    NativeFormRow("Draw cursors") {
                        Toggle("", isOn: $preferences.drawCursor)
                            .labelsHidden()
                            .toggleStyle(NativeToggleStyle())
                            .accessibilityLabel("Draw cursors")
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.dialog = nil }
                    .buttonStyle(.bordered)
                Button("Save") {
                    model.updatePreferences(preferences)
                    music.apply(
                        tileset: model.map.tileset,
                        enabled: preferences.volumeEnabled,
                        volume: preferences.volume
                    )
                    model.dialog = nil
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var terrainOptions: [Element] {
        [.terrainPlain, .terrainWood, .terrainMountain, .terrainRoad, .terrainSea]
    }

    private func terrainTitle(_ terrain: Element) -> String {
        if terrain == .terrainPlain { return "Plains" }
        if terrain == .terrainWood { return "Woods" }
        if terrain == .terrainMountain { return "Mountains" }
        if terrain == .terrainRoad { return "Roads" }
        if terrain == .terrainSea { return "Sea" }
        return "Terrain"
    }
}

struct MapStatusView: View {
    let model: EditorModel

    var body: some View {
        let counts = model.statusCounts()
        VStack(alignment: .leading, spacing: 15) {
            Text("Map Status").font(.title2).bold()
            let columns = ["Cities", "Bases", "Ports", "Airports", "Towers"]
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("Army").bold()
                    ForEach(columns, id: \.self) { Text($0).bold().frame(maxWidth: .infinity, alignment: .center) }
                    Text("Units").bold().frame(maxWidth: .infinity, alignment: .center)
                }
                ForEach(PaletteCatalog.visibleArmies(for: model.map.tileset) + [AWConstants.armyNeutral], id: \.self) { army in
                    GridRow {
                        Text(PaletteCatalog.armyName(army, tileset: model.map.tileset))
                        ForEach(0..<columns.count, id: \.self) { column in
                            Text("\(counts.values[column][army])").monospacedDigit().frame(maxWidth: .infinity, alignment: .center)
                        }
                        Text(army == AWConstants.armyNeutral ? "–" : "\(counts.unitCounts[army])")
                            .monospacedDigit().frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            Divider()
            Text("Pipe seams: \(counts.pipeSeams)")
            Text("Missile silos: \(counts.silos)")
            Text("Total properties: \(counts.totalProperties)\(counts.totalProperties > AWConstants.propertiesLimit ? " (over the in-game limit of \(AWConstants.propertiesLimit))" : "")")
                .bold()
            if counts.totalProperties > AWConstants.propertiesLimit {
                Label("This map has more properties than the game limit.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Close") { model.dialog = nil }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
            }
        }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Group {
                if let image = NSApplication.shared.applicationIconImage {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.none)
                } else {
                    Image(systemName: "map")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 128, height: 128)
            Text("AW Map Editor").font(.title2).bold()
            Text("SwiftUI Port · 1.0")
                .foregroundStyle(.secondary)
            Text("Create and share maps for the Advance Wars series.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 390)
            Text("Original map format compatibility is preserved.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 390)
            Link("Original Editor", destination: URL(string: "https://github.com/joaofrancese/awsmaped")!)
            Button("Close") { dismiss() }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
        }
        .padding(24)
    }
}
