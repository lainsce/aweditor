import Foundation

public enum AWConstants {
    public static let unitEmpty = 0xFFFF
    public static let unitDelete = 0xFFFE
    public static let terrainBlank = 0xFFFD

    public static let terrainStart = 0
    public static let terrainEnd = 299
    public static let buildingStart = 300
    public static let buildingEnd = 499
    public static let unitStart = 500
    public static let unitEnd = 899
    public static let extraStart = 900
    public static let extraEnd = 1299

    public static let terrainColumns = 30
    public static let buildingColumns = 10
    public static let unitColumns = 20
    public static let extraColumns = 20

    public static let mapMinimumWidth = 1
    public static let mapMinimumHeight = 1
    public static let mapDefaultWidth = 30
    public static let mapDefaultHeight = 20
    public static let mapMaximumWidth = 10_000
    public static let mapMaximumHeight = 10_000

    public static let nameMaximumLength = 50
    public static let authorMaximumLength = 50
    public static let descriptionMaximumLength = 1024 * 100
    public static let propertiesLimit = 60

    public static let armyOrangeStar = 0
    public static let armyBlueMoon = 1
    public static let armyGreenEarth = 2
    public static let armyYellowComet = 3
    public static let armyBlackHole = 4
    public static let armyNeutral = 5
    public static let playableArmies = 5

    public static func makeTerrain(_ x: Int, _ y: Int) -> Int {
        x + y * terrainColumns + terrainStart
    }

    public static func makeBuilding(_ x: Int, _ y: Int) -> Int {
        x + y * buildingColumns + buildingStart
    }

    public static func makeUnit(_ x: Int, _ y: Int) -> Int {
        x + y * unitColumns + unitStart
    }

    public static func makeExtra(_ x: Int, _ y: Int) -> Int {
        x + y * extraColumns + extraStart
    }
}

public enum Tileset: Int, CaseIterable, Codable, Sendable {
    case normal = 0
    case snow = 1
    case desert = 2
    case wasteland = 3
    case aw1 = 4
    case aw2 = 5
    case famicomWars = 6
    case gbWars = 7

    public var displayName: String {
        switch self {
        case .normal: "Dual Strike · Normal"
        case .snow: "Dual Strike · Snow"
        case .desert: "Dual Strike · Desert"
        case .wasteland: "Dual Strike · Wasteland"
        case .aw1: "Advance Wars"
        case .aw2: "Advance Wars 2"
        case .famicomWars: "Famicom Wars"
        case .gbWars: "GB Wars"
        }
    }

    /// The bundled looping music track for this game's tileset family.
    /// Dual Strike's four visual variants intentionally share the original
    /// `bgm.mp3`, while the historical game families use their own tracks.
    public var backgroundMusicResourceName: String {
        switch self {
        case .normal, .snow, .desert, .wasteland: "bgm"
        case .aw1, .aw2: "bgm_2"
        case .famicomWars: "bgm_3"
        case .gbWars: "bgm_4"
        }
    }

    /// Chronological order for authoring controls. Raw values stay stable so
    /// existing AWS/AWD map files continue to decode their original six
    /// tilesets unchanged.
    public static var launchOrdered: [Tileset] {
        [.famicomWars, .gbWars, .aw1, .aw2, .normal, .snow, .desert, .wasteland]
    }

    /// The game rules used when launching an in-editor playtest for this
    /// tileset. The historical Famicom/GB looks currently use the closest
    /// implemented GBA rules for playtest mechanics; their art remains
    /// distinct and the rules can be split out later without changing files.
    public var playtestRuleset: PlaytestRuleset {
        switch self {
        case .normal, .snow, .desert, .wasteland: .dualStrike
        case .aw1, .famicomWars, .gbWars: .advanceWars
        case .aw2: .advanceWars2
        }
    }
}

public enum PlaytestRuleset: String, CaseIterable, Codable, Sendable {
    case dualStrike
    case advanceWars
    case advanceWars2

    public var displayName: String {
        switch self {
        case .dualStrike: "Advance Wars: Dual Strike"
        case .advanceWars: "Advance Wars"
        case .advanceWars2: "Advance Wars 2"
        }
    }

    public var shortName: String {
        switch self {
        case .dualStrike: "Dual Strike"
        case .advanceWars: "AW1"
        case .advanceWars2: "AW2"
        }
    }
}

public enum MapFormat: String, CaseIterable, Codable, Sendable {
    case awm
    case aw2
    case awd
    case aws

    public var header: String {
        switch self {
        case .awm: "AWMap 001"
        case .aw2: "AW2Map001"
        case .awd: "AWDMap001"
        case .aws: "AWSMap001"
        }
    }

    public var mapType: Int {
        switch self {
        case .awm: 2
        case .aw2: 3
        case .awd: 4
        case .aws: 5
        }
    }

    public var displayName: String {
        switch self {
        case .awm: "Advance Wars (.awm)"
        case .aw2: "Advance Wars 2 (.aw2)"
        case .awd: "Advance Wars DS (.awd)"
        case .aws: "AW Series (.aws)"
        }
    }

    public var supportsVariableSize: Bool { self == .aws }

    public init(fileExtension: String) {
        switch fileExtension.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) {
        case "awm": self = .awm
        case "aw2": self = .aw2
        case "awd": self = .awd
        default: self = .aws
        }
    }
}

public enum PaletteTab: String, CaseIterable, Identifiable, Sendable {
    case terrain
    case unit
    case extra
    case mapArt

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .terrain: "Terrain"
        case .unit: "Unit"
        case .extra: "Extra"
        case .mapArt: "Map Art"
        }
    }
}
