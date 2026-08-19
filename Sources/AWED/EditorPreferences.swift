import Foundation
import AWEDCore

struct EditorPreferences: Codable, Equatable, Sendable {
    var volumeEnabled = true
    var volume = 50
    var defaultWidth = AWConstants.mapDefaultWidth
    var defaultHeight = AWConstants.mapDefaultHeight
    var defaultTerrain = Element.terrainSea
    var defaultTileset = Tileset.normal
    var defaultAuthor = "unknown"
    var undoLimit = 30
    var drawCursor = true

    static let storageKey = "AWED.preferences"

    static func load() -> EditorPreferences {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let preferences = try? JSONDecoder().decode(EditorPreferences.self, from: data) else {
            return EditorPreferences()
        }
        return preferences.validated()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    func validated() -> EditorPreferences {
        var copy = self
        copy.volume = min(max(volume, 0), 100)
        copy.defaultWidth = min(max(defaultWidth, AWConstants.mapMinimumWidth), AWConstants.mapMaximumWidth)
        copy.defaultHeight = min(max(defaultHeight, AWConstants.mapMinimumHeight), AWConstants.mapMaximumHeight)
        if ![Element.terrainPlain, .terrainWood, .terrainMountain, .terrainRoad, .terrainSea].contains(defaultTerrain) {
            copy.defaultTerrain = .terrainSea
        }
        copy.defaultAuthor = String(defaultAuthor.prefix(AWConstants.authorMaximumLength))
        if ![10, 20, 30, 40, 50, 100].contains(undoLimit) { copy.undoLimit = 30 }
        return copy
    }
}
