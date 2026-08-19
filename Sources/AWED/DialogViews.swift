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
                TextField("Map Name", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: draftName) { _, newValue in draftName = String(newValue.prefix(AWConstants.nameMaximumLength)) }
                TextField("Author", text: $draftAuthor)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: draftAuthor) { _, newValue in draftAuthor = String(newValue.prefix(AWConstants.authorMaximumLength)) }
                TextField("Description", text: $draftDescription, axis: .vertical)
                    .lineLimit(5...12)
                    .textFieldStyle(.roundedBorder)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.dialog = nil }
                Button("Save") {
                    model.updateInformation(name: draftName, author: draftAuthor, description: draftDescription)
                    model.dialog = nil
                }
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
                Stepper(value: $width, in: AWConstants.mapMinimumWidth...AWConstants.mapMaximumWidth) {
                    LabeledContent("Width") { Text("\(width)").monospacedDigit() }
                }
                Stepper(value: $height, in: AWConstants.mapMinimumHeight...AWConstants.mapMaximumHeight) {
                    LabeledContent("Height") { Text("\(height)").monospacedDigit() }
                }
                Picker("Tileset", selection: $tileset) {
                    ForEach(Tileset.allCases, id: \.self) { tile in
                        Text(tile.displayName).tag(tile)
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
                Button("Apply") {
                    model.updateSettings(width: width, height: height, tileset: tileset)
                    model.dialog = nil
                }
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
                    Toggle("Enable background music", isOn: $preferences.volumeEnabled)
                    LabeledContent("Volume") {
                        HStack {
                            Slider(value: Binding(get: { Double(preferences.volume) }, set: { preferences.volume = Int($0.rounded()) }), in: 0...100, step: 1)
                            Text("\(preferences.volume)%").monospacedDigit().frame(width: 42, alignment: .trailing)
                        }
                        .disabled(!preferences.volumeEnabled)
                    }
                }
                Section("New Maps") {
                    Stepper(value: $preferences.defaultWidth, in: AWConstants.mapMinimumWidth...AWConstants.mapMaximumWidth) {
                        LabeledContent("Default width") { Text("\(preferences.defaultWidth)").monospacedDigit() }
                    }
                    Stepper(value: $preferences.defaultHeight, in: AWConstants.mapMinimumHeight...AWConstants.mapMaximumHeight) {
                        LabeledContent("Default height") { Text("\(preferences.defaultHeight)").monospacedDigit() }
                    }
                    Picker("Default terrain", selection: $preferences.defaultTerrain) {
                        Text("Plains").tag(Element.terrainPlain)
                        Text("Woods").tag(Element.terrainWood)
                        Text("Mountains").tag(Element.terrainMountain)
                        Text("Roads").tag(Element.terrainRoad)
                        Text("Sea").tag(Element.terrainSea)
                    }
                    Picker("Default tileset", selection: $preferences.defaultTileset) {
                        ForEach(Tileset.allCases, id: \.self) { tile in Text(tile.displayName).tag(tile) }
                    }
                    Picker("Undo/redo limit", selection: $preferences.undoLimit) {
                        ForEach([10, 20, 30, 40, 50, 100], id: \.self) { value in Text("\(value)").tag(value) }
                    }
                    TextField("Default author", text: $preferences.defaultAuthor)
                        .onChange(of: preferences.defaultAuthor) { _, newValue in preferences.defaultAuthor = String(newValue.prefix(AWConstants.authorMaximumLength)) }
                }
                Section("Interaction") {
                    Toggle("Draw AW-style cursors", isOn: $preferences.drawCursor)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.dialog = nil }
                Button("Save") {
                    model.updatePreferences(preferences)
                    music.apply(enabled: preferences.volumeEnabled, volume: preferences.volume)
                    model.dialog = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
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
            .frame(width: 72, height: 72)
            Text("Advance Wars Series Map Editor").font(.title2).bold()
            Text("SwiftUI port · version 1.0")
                .foregroundStyle(.secondary)
            Text("Create, edit, and share custom maps for the Advance Wars series. Original map format compatibility is preserved.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 390)
            Link("Original Editor", destination: URL(string: "https://github.com/joaofrancese/awsmaped")!)
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }
}
