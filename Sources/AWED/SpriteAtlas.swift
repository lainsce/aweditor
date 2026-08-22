import AppKit
import SwiftUI
import AWEDCore

/// A render-only sprite palette. The persisted map tileset remains a
/// `Tileset`; playtest weather can select a palette without changing the map
/// format or the editor's palette selection.
enum SpritePalette {
    case tileset(Tileset)
    case gbaRain(base: Tileset)
    case gbaSnow(base: Tileset)
    case famicomWars
    case gbWars

    /// The historical Famicom sheet mixes one-cell properties with the
    /// editor's usual two-cell building sprites. Keep that geometry with the
    /// render palette instead of changing the persisted `Element` contract.
    func doubleHeight(for element: Element) -> Bool {
        if case .gbWars = self, element.isBuilding {
            return false
        }
        guard case .famicomWars = self, element.isBuilding else {
            return element.doubleHeight
        }

        switch element.simplified {
        case .buildingHQ, .buildingBase:
            return false
        default:
            return element.doubleHeight
        }
    }

    /// Famicom's one-cell HQs and bases still live in the top row of each
    /// two-row building group in the normalized atlas. Keep their source
    /// lookup aligned with that atlas row while cropping only 16 pixels.
    func drawY(for element: Element) -> Int {
        if case .gbWars = self, element.isBuilding {
            // The GB Wars property sheet keeps each 16×16 faction row on a
            // two-row cadence, even though the sprites themselves are not
            // double-height. This maps Red Star (row 0), White Moon (row 2),
            // and neutral properties (row 10) to their actual atlas cells.
            return element.y * 2
        }
        if case .famicomWars = self,
           element.isBuilding,
           !doubleHeight(for: element) {
            return element.y * 2
        }
        return element.drawY
    }

    func sheetName(for kind: SpriteSheetKind) -> String {
        switch self {
        case .tileset(let tileset):
            return "\(kind.rawValue)_\(tileset.rawValue)"
        case .gbaRain(let base):
            // GBA weather changes the terrain palette. Buildings and units
            // retain their game-specific normal artwork and faction colors.
            guard kind.rawValue == SpriteSheetKind.terrain.rawValue else {
                return "\(kind.rawValue)_\(base.rawValue)"
            }
            guard let baseName = gbaBaseName(for: base) else {
                return "\(kind.rawValue)_\(base.rawValue)"
            }
            return "terrain_\(baseName)_rain"
        case .gbaSnow(let base):
            guard kind.rawValue == SpriteSheetKind.terrain.rawValue else {
                return "\(kind.rawValue)_\(base.rawValue)"
            }
            guard let baseName = gbaBaseName(for: base) else {
                return "\(kind.rawValue)_\(base.rawValue)"
            }
            return "terrain_\(baseName)_snow"
        case .famicomWars:
            // The historical Famicom atlas is a dedicated source-derived
            // sheet, not a recolored Dual Strike fallback.
            return "\(kind.rawValue)_6"
        case .gbWars:
            // GB Wars uses the compact four-tone reference-derived atlas.
            return "\(kind.rawValue)_7"
        }
    }

    private func gbaBaseName(for tileset: Tileset) -> String? {
        switch tileset {
        case .aw1: "aw1"
        case .aw2: "aw2"
        default: nil
        }
    }
}

/// The art choices available while authoring a map. The four Dual Strike
/// palettes are stored directly by the map format. GBA weather palettes are
/// deliberately render-only variants: the map still stores its AW1/AW2 base
/// tileset, so legacy map files remain byte-for-byte compatible. Advance Wars
/// 1 has clear and snow only; rain is an AW2 weather variant.
enum MapVisualVariant: String, CaseIterable, Identifiable, Equatable, Sendable {
    case famicomWars
    case gbWars
    case aw1Clear
    case aw1Snow
    case aw2Clear
    case aw2Rain
    case aw2Snow
    case dualStrikeNormal
    case dualStrikeSnow
    case dualStrikeDesert
    case dualStrikeWasteland

    struct Group: Identifiable, Sendable {
        let id: String
        let title: String
        let variants: [MapVisualVariant]
    }

    struct Effect: Identifiable, Sendable {
        enum Tint: String, Sendable {
            case neutral
            case fuel
            case range
            case visual
            case movement
            case weather
            case air

            var color: Color {
                switch self {
                case .neutral: .secondary
                case .fuel: .orange
                case .range: .purple
                case .visual: .teal
                case .movement: .blue
                case .weather: .cyan
                case .air: .indigo
                }
            }
        }

        let systemImage: String
        let value: String
        let accessibilityLabel: String
        let tint: Tint

        var id: String { "\(systemImage)-\(value)" }
    }

    static let groups: [Group] = [
        Group(
            id: "famicomWars",
            title: "Famicom Wars · 1988",
            variants: [.famicomWars]
        ),
        Group(
            id: "gbWars",
            title: "GB Wars · 1991",
            variants: [.gbWars]
        ),
        Group(
            id: "advanceWars",
            title: "Advance Wars · 2001",
            variants: [.aw1Clear, .aw1Snow]
        ),
        Group(
            id: "advanceWars2",
            title: "Advance Wars 2 · 2003",
            variants: [.aw2Clear, .aw2Rain, .aw2Snow]
        ),
        Group(
            id: "dualStrike",
            title: "Advance Wars: Dual Strike · 2005",
            variants: [.dualStrikeNormal, .dualStrikeSnow, .dualStrikeDesert, .dualStrikeWasteland]
        )
    ]

    var id: String { rawValue }

    var baseTileset: Tileset {
        switch self {
        case .famicomWars: .famicomWars
        case .gbWars: .gbWars
        case .aw1Clear, .aw1Snow: .aw1
        case .aw2Clear, .aw2Rain, .aw2Snow: .aw2
        case .dualStrikeNormal: .normal
        case .dualStrikeSnow: .snow
        case .dualStrikeDesert: .desert
        case .dualStrikeWasteland: .wasteland
        }
    }

    var palette: SpritePalette {
        switch self {
        case .famicomWars: .famicomWars
        case .gbWars: .gbWars
        case .aw1Clear: .tileset(.aw1)
        case .aw1Snow: .gbaSnow(base: .aw1)
        case .aw2Clear: .tileset(.aw2)
        case .aw2Rain: .gbaRain(base: .aw2)
        case .aw2Snow: .gbaSnow(base: .aw2)
        case .dualStrikeNormal: .tileset(.normal)
        case .dualStrikeSnow: .tileset(.snow)
        case .dualStrikeDesert: .tileset(.desert)
        case .dualStrikeWasteland: .tileset(.wasteland)
        }
    }

    var familyName: String {
        switch self {
        case .famicomWars: "Famicom Wars"
        case .gbWars: "GB Wars"
        case .aw1Clear, .aw1Snow: "Advance Wars"
        case .aw2Clear, .aw2Rain, .aw2Snow: "Advance Wars 2"
        case .dualStrikeNormal, .dualStrikeSnow, .dualStrikeDesert, .dualStrikeWasteland: "Dual Strike"
        }
    }

    var shortName: String {
        switch self {
        case .famicomWars: "Famicom"
        case .gbWars: "Game Boy"
        case .aw1Clear, .aw2Clear: "Clear"
        case .aw1Snow, .aw2Snow: "Snow"
        case .aw2Rain: "Rain"
        case .dualStrikeNormal: "Normal"
        case .dualStrikeSnow: "Snow"
        case .dualStrikeDesert: "Desert"
        case .dualStrikeWasteland: "Wasteland"
        }
    }

    /// Compact gameplay/rendering modifiers shown beneath each map-art name.
    /// A zero means the variant has no rules modifier; "Art" marks the
    /// Dual Strike wasteland palette as visual-only.
    var effects: [Effect] {
        switch self {
        case .famicomWars:
            [Effect(systemImage: "paintpalette.fill", value: "8-bit", accessibilityLabel: "Visual palette only", tint: .visual)]
        case .gbWars:
            [Effect(systemImage: "paintpalette.fill", value: "4-tone", accessibilityLabel: "Visual palette only", tint: .visual)]
        case .dualStrikeNormal:
            [Effect(systemImage: "sun.max.fill", value: "0", accessibilityLabel: "No gameplay modifiers", tint: .neutral)]
        case .dualStrikeSnow:
            [Effect(systemImage: "fuelpump.fill", value: "×2", accessibilityLabel: "Fuel and rations doubled", tint: .fuel)]
        case .dualStrikeDesert:
            [Effect(systemImage: "scope", value: "−1", accessibilityLabel: "Indirect maximum range reduced by one", tint: .range)]
        case .dualStrikeWasteland:
            [Effect(systemImage: "paintpalette.fill", value: "Art", accessibilityLabel: "Visual palette only", tint: .visual)]
        case .aw1Clear:
            [Effect(systemImage: "sun.max.fill", value: "0", accessibilityLabel: "No gameplay modifiers", tint: .neutral)]
        case .aw1Snow:
            [Effect(systemImage: "figure.walk", value: "+1", accessibilityLabel: "Weather-affected movement costs increase by one", tint: .movement)]
        case .aw2Clear:
            [Effect(systemImage: "sun.max.fill", value: "0", accessibilityLabel: "No gameplay modifiers", tint: .neutral)]
        case .aw2Rain:
            [Effect(systemImage: "cloud.rain.fill", value: "+1", accessibilityLabel: "Vehicle movement costs increase by one", tint: .weather)]
        case .aw2Snow:
            [
                Effect(systemImage: "snowflake", value: "+1", accessibilityLabel: "Weather-affected movement costs increase by one", tint: .movement),
                Effect(systemImage: "airplane", value: "+1", accessibilityLabel: "Air movement cost increases by one", tint: .air)
            ]
        }
    }

    var effectAccessibilityLabel: String {
        effects
            .map { "\($0.accessibilityLabel) (\($0.value))" }
            .joined(separator: ", ")
    }

    var displayName: String { "\(familyName) · \(shortName)" }

    static func defaultVariant(for tileset: Tileset) -> MapVisualVariant {
        switch tileset {
        case .famicomWars: .famicomWars
        case .gbWars: .gbWars
        case .normal: .dualStrikeNormal
        case .snow: .dualStrikeSnow
        case .desert: .dualStrikeDesert
        case .wasteland: .dualStrikeWasteland
        case .aw1: .aw1Clear
        case .aw2: .aw2Clear
        }
    }

}

@MainActor
final class SpriteAtlas {
    private var sheets: [String: CGImage] = [:]
    private var sprites: [String: Image] = [:]

    func image(for element: Element, tileset: Tileset) -> Image? {
        image(for: element, palette: .tileset(tileset))
    }

    func image(for element: Element, palette: SpritePalette) -> Image? {
        guard element.drawable else { return nil }
        let sheetName = palette.sheetName(for: element.spritesheet)
        let cacheKey = "\(sheetName)-\(element.value)"
        if let cached = sprites[cacheKey] { return cached }
        guard let cropped = croppedImage(for: element, sheetName: sheetName, palette: palette) else { return nil }
        let image = Image(decorative: cropped, scale: 1, orientation: .up)
        sprites[cacheKey] = image
        return image
    }

    func cgImage(for element: Element, tileset: Tileset) -> CGImage? {
        cgImage(for: element, palette: .tileset(tileset))
    }

    func cgImage(for element: Element, palette: SpritePalette) -> CGImage? {
        guard element.drawable else { return nil }
        let sheetName = palette.sheetName(for: element.spritesheet)
        return croppedImage(for: element, sheetName: sheetName, palette: palette)
    }

    private func croppedImage(for element: Element, sheetName: String, palette: SpritePalette) -> CGImage? {
        guard let sheet = loadSheet(named: sheetName) else { return nil }
        let sourceWidth = 16
        let sourceHeight = palette.doubleHeight(for: element) ? 32 : 16
        let sourceX = element.drawX * 16
        let sourceYFromTop = palette.drawY(for: element) * 16
        guard sourceX >= 0, sourceYFromTop >= 0, sourceX + sourceWidth <= sheet.width, sourceYFromTop + sourceHeight <= sheet.height else { return nil }
        let sourceRect = CGRect(
            x: sourceX,
            y: sourceYFromTop,
            width: sourceWidth,
            height: sourceHeight
        )
        return sheet.cropping(to: sourceRect)
    }

    private func loadSheet(named name: String) -> CGImage? {
        if let sheet = sheets[name] { return sheet }
        let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Spritesheets")
            ?? Bundle.main.url(forResource: name, withExtension: "png")
        guard let url, let image = NSImage(contentsOf: url) else { return nil }
        var proposed = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return nil }
        sheets[name] = cgImage
        return cgImage
    }
}
