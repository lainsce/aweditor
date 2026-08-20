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
                GLWNFormRow("Map Name") {
                    TextField("", text: $draftName)
                        .textFieldStyle(GLWNTextFieldStyle())
                        .accessibilityLabel("Map Name")
                        .onChange(of: draftName) { _, newValue in draftName = String(newValue.prefix(AWConstants.nameMaximumLength)) }
                }
                GLWNFormRow("Author") {
                    TextField("", text: $draftAuthor)
                        .textFieldStyle(GLWNTextFieldStyle())
                        .accessibilityLabel("Author")
                        .onChange(of: draftAuthor) { _, newValue in draftAuthor = String(newValue.prefix(AWConstants.authorMaximumLength)) }
                }
                GLWNFormRow("Description") {
                    TextField("", text: $draftDescription, axis: .vertical)
                        .lineLimit(5...12)
                        .textFieldStyle(GLWNTextFieldStyle())
                        .accessibilityLabel("Description")
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.dialog = nil }
                    .buttonStyle(GLWNInContentButtonStyle(tone: .neutral))
                Button("Save") {
                    model.updateInformation(name: draftName, author: draftAuthor, description: draftDescription)
                    model.dialog = nil
                }
                .buttonStyle(GLWNInContentButtonStyle(tone: .accent))
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

struct MapSettingsView: View {
    let model: EditorModel
    @State private var width: Int
    @State private var height: Int
    @State private var tileset: Tileset

    init(model: EditorModel) {
        self.model = model
        _width = State(initialValue: model.map.width)
        _height = State(initialValue: model.map.height)
        _tileset = State(initialValue: model.map.tileset)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Map Settings").font(.title2).bold()
            Form {
                GLWNFormRow("Width") {
                    Stepper(value: $width, in: AWConstants.mapMinimumWidth...AWConstants.mapMaximumWidth) {
                        Text("\(width)").monospacedDigit()
                    }
                }
                GLWNFormRow("Height") {
                    Stepper(value: $height, in: AWConstants.mapMinimumHeight...AWConstants.mapMaximumHeight) {
                        Text("\(height)").monospacedDigit()
                    }
                }
                GLWNFormRow("Tileset") {
                    GLWNPullDownMenu(
                        "Tileset",
                        selection: $tileset,
                        options: Tileset.allCases,
                        showsTitle: false
                    ) { tile in
                        Text(tile.displayName)
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
                    .buttonStyle(GLWNInContentButtonStyle(tone: .neutral))
                Button("Apply") {
                    model.updateSettings(width: width, height: height, tileset: tileset)
                    model.dialog = nil
                }
                .buttonStyle(GLWNInContentButtonStyle(tone: .accent))
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Editor Preferences").font(.title2).bold()
            Form {
                Section("Background Music") {
                    GLWNFormRow("Enable BGM") {
                        Toggle("", isOn: $preferences.volumeEnabled)
                            .labelsHidden()
                            .toggleStyle(GLWNAquaToggleStyle())
                            .accessibilityLabel("Enable background music")
                    }
                    GLWNFormRow("Volume") {
                        HStack {
                            Slider(value: Binding(get: { Double(preferences.volume) }, set: { preferences.volume = Int($0.rounded()) }), in: 0...100, step: 1)
                            Text("\(preferences.volume)%").monospacedDigit().frame(width: 42, alignment: .trailing)
                        }
                        .disabled(!preferences.volumeEnabled)
                    }
                }
                Section("New Maps") {
                    GLWNFormRow("Default width") {
                        Stepper(value: $preferences.defaultWidth, in: AWConstants.mapMinimumWidth...AWConstants.mapMaximumWidth) {
                            Text("\(preferences.defaultWidth)").monospacedDigit()
                        }
                    }
                    GLWNFormRow("Default height") {
                        Stepper(value: $preferences.defaultHeight, in: AWConstants.mapMinimumHeight...AWConstants.mapMaximumHeight) {
                            Text("\(preferences.defaultHeight)").monospacedDigit()
                        }
                    }
                    GLWNFormRow("Default terrain") {
                        GLWNPullDownMenu(
                            "Default terrain",
                            selection: $preferences.defaultTerrain,
                            options: terrainOptions,
                            showsTitle: false
                        ) { terrain in
                            Text(terrainTitle(terrain))
                        }
                    }
                    GLWNFormRow("Default tileset") {
                        GLWNPullDownMenu(
                            "Default tileset",
                            selection: $preferences.defaultTileset,
                            options: Tileset.allCases,
                            showsTitle: false
                        ) { tile in
                            Text(tile.displayName)
                        }
                    }
                    GLWNFormRow("Undo/redo limit") {
                        GLWNPullDownMenu(
                            "Undo/redo limit",
                            selection: $preferences.undoLimit,
                            options: [10, 20, 30, 40, 50, 100],
                            showsTitle: false
                        ) { value in
                            Text("\(value)")
                        }
                    }
                    GLWNFormRow("Default author") {
                        TextField("", text: $preferences.defaultAuthor)
                            .textFieldStyle(GLWNTextFieldStyle())
                            .accessibilityLabel("Default author")
                            .onChange(of: preferences.defaultAuthor) { _, newValue in preferences.defaultAuthor = String(newValue.prefix(AWConstants.authorMaximumLength)) }
                    }
                }
                Section("Interaction") {
                    GLWNFormRow("Draw AW-style cursors") {
                        Toggle("", isOn: $preferences.drawCursor)
                            .labelsHidden()
                            .toggleStyle(GLWNAquaToggleStyle())
                            .accessibilityLabel("Draw AW-style cursors")
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.dialog = nil }
                    .buttonStyle(GLWNInContentButtonStyle(tone: .neutral))
                Button("Save") {
                    model.updatePreferences(preferences)
                    music.apply(enabled: preferences.volumeEnabled, volume: preferences.volume)
                    model.dialog = nil
                }
                .buttonStyle(GLWNInContentButtonStyle(tone: .accent))
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
                ForEach(0...AWConstants.armyNeutral, id: \.self) { army in
                    GridRow {
                        Text(PaletteCatalog.armyName(army))
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
                    .buttonStyle(GLWNInContentButtonStyle(tone: .neutral))
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
                .buttonStyle(GLWNInContentButtonStyle(tone: .neutral))
                .keyboardShortcut(.cancelAction)
        }
        .padding(24)
    }
}
