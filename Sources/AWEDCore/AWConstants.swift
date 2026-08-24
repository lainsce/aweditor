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
    // Keep the original raw values above stable for existing map files. The
    // historical variants are editor-only extensions and therefore append to
    // the persisted enum rather than being inserted chronologically.
    case superFamicomWars = 8
    case daysOfRuin = 9
    case gbWars2 = 10
    case gbWars3 = 11

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
        case .superFamicomWars: "Super Famicom Wars"
        case .daysOfRuin: "Advance Wars: Days of Ruin"
        case .gbWars2: "Game Boy Wars 2"
        case .gbWars3: "Game Boy Wars 3"
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
        case .gbWars, .gbWars2: "bgm_4"
        case .daysOfRuin: "bgm_5"
        case .gbWars3: "bgm_6"
        case .superFamicomWars: "bgm_7"
        }
    }

    /// Chronological order for authoring controls. Raw values stay stable so
    /// existing AWS/AWD map files continue to decode their original six
    /// tilesets unchanged.
    public static var launchOrdered: [Tileset] {
        [
            .famicomWars,
            .gbWars,
            .superFamicomWars,
            .gbWars2,
            .aw1,
            .gbWars3,
            .aw2,
            .normal,
            .snow,
            .desert,
            .wasteland,
            .daysOfRuin
        ]
    }

    /// The game rules used when launching an in-editor playtest for this
    /// tileset. Every historical art family keeps a distinct mechanics
    /// identity; this enum is not persisted in map files, so adding rulesets
    /// does not disturb the stable `Tileset` raw values above.
    public var playtestRuleset: PlaytestRuleset {
        switch self {
        case .normal, .snow, .desert, .wasteland: .dualStrike
        case .aw1: .advanceWars
        case .aw2: .advanceWars2
        case .famicomWars: .famicomWars
        case .gbWars: .gameBoyWars
        case .superFamicomWars: .superFamicomWars
        case .gbWars2: .gameBoyWars2
        case .gbWars3: .gameBoyWars3
        case .daysOfRuin: .daysOfRuin
        }
    }

    /// The compact family checks are shared by the editor and playtest
    /// renderer. They intentionally include the historical variants so the
    /// staggered Game Boy grid and the limited Famicom palette stay in sync
    /// everywhere a map can be drawn.
    public var isFamicomWarsFamily: Bool {
        self == .famicomWars || self == .superFamicomWars
    }

    public var isGameBoyWarsFamily: Bool {
        self == .gbWars || self == .gbWars2 || self == .gbWars3
    }

    public var isHistoricalWarsVariant: Bool {
        isFamicomWarsFamily || isGameBoyWarsFamily || self == .daysOfRuin
    }
}

public enum PlaytestRuleset: String, CaseIterable, Codable, Sendable {
    case dualStrike
    case advanceWars
    case advanceWars2
    case famicomWars
    case gameBoyWars
    case superFamicomWars
    case gameBoyWars2
    case gameBoyWars3
    case daysOfRuin

    public var displayName: String {
        switch self {
        case .dualStrike: "Advance Wars: Dual Strike"
        case .advanceWars: "Advance Wars"
        case .advanceWars2: "Advance Wars 2"
        case .famicomWars: "Famicom Wars"
        case .gameBoyWars: "Game Boy Wars"
        case .superFamicomWars: "Super Famicom Wars"
        case .gameBoyWars2: "Game Boy Wars 2"
        case .gameBoyWars3: "Game Boy Wars 3"
        case .daysOfRuin: "Advance Wars: Days of Ruin"
        }
    }

    public var shortName: String {
        switch self {
        case .dualStrike: "Dual Strike"
        case .advanceWars: "AW1"
        case .advanceWars2: "AW2"
        case .famicomWars: "Famicom Wars"
        case .gameBoyWars: "GB Wars"
        case .superFamicomWars: "SFW"
        case .gameBoyWars2: "GB Wars 2"
        case .gameBoyWars3: "GB Wars 3"
        case .daysOfRuin: "Days of Ruin"
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
