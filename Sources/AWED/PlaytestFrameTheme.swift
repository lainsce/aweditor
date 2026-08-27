import SwiftUI
import AWEDCore

enum PlaytestFlatWoodBorderStyle: Equatable {
    case textured
    case inspector(PlaytestStatusTheme)
}

/// The parchment and board chrome used by the playtest flyout.
///
/// These are deliberately restrained palettes: the map remains the focal
/// point, while the frame picks up the screen language of the game being
/// played (limited Game Boy greens, Famicom-era browns, and the later Wars
/// palettes). The editor keeps its original warm paper treatment through
/// `editor`.
struct PlaytestFrameTheme {
    let parchmentGradient: [Color]
    let parchmentHighlight: Color
    let parchmentShadow: Color
    let gridColor: Color
    let gridRegularOpacity: Double
    let gridMajorOpacity: Double
    /// Historical cartridges used a flat screen surround rather than the
    /// editor's raised, textured wood frame.
    let flatWoodBorderStyle: PlaytestFlatWoodBorderStyle

    let woodGradient: [Color]
    /// The editor's lower wall historically used a slightly darker base than
    /// the frame face. Playtest themes can fall back to their first wood tone.
    let woodLowerBase: Color?
    let woodDeep: Color
    let woodHighlight: Color
    let woodGrainDark: Color
    let woodGrainLight: Color

    let headerTint: Color
    let headerFGTint: Color
    let headerOpacity: Double
    let headerBorder: Color
    let headerShadow: Color

    var usesFlatWoodBorder: Bool {
        flatWoodBorderStyle != .textured
    }

    /// The historical flat frame treatments also used a uniform screen
    /// surround. Keep the parchment fill independent from the wood renderer
    /// so adding a new frame style cannot accidentally reintroduce a paper
    /// gradient to a cartridge-era map.
    var usesFlatParchment: Bool {
        switch flatWoodBorderStyle {
        case .textured:
            false
        case .inspector:
            true
        }
    }

    static let editor = PlaytestFrameTheme(
        parchmentGradient: [
            rgb(0xF7EBC9), rgb(0xE8D6AA), rgb(0xE0CA97)
        ],
        parchmentHighlight: .white,
        parchmentShadow: .black,
        gridColor: rgb(0x5E421F),
        gridRegularOpacity: 0.06,
        gridMajorOpacity: 0.09,
        flatWoodBorderStyle: .textured,
        woodGradient: [rgb(0x7A3A14), rgb(0xB06324), rgb(0x8C4517)],
        woodLowerBase: rgb(0x6E2E0E),
        woodDeep: rgb(0x290E04),
        woodHighlight: rgb(0xF9AB42),
        woodGrainDark: rgb(0x451C09),
        woodGrainLight: rgb(0xF2A64C),
        headerTint: .white,
        headerFGTint: .black,
        headerOpacity: 0.48,
        headerBorder: rgb(0x846A3B),
        headerShadow: .black
    )

    static func playtest(for tileset: Tileset) -> PlaytestFrameTheme {
        switch tileset {
        case .famicomWars:
            return PlaytestFrameTheme(
                parchmentGradient: [FamicomPPUPalette.black, FamicomPPUPalette.black, FamicomPPUPalette.black],
                parchmentHighlight: FamicomPPUPalette.black,
                parchmentShadow: FamicomPPUPalette.black,
                gridColor: FamicomPPUPalette.black,
                gridRegularOpacity: 0,
                gridMajorOpacity: 0,
                flatWoodBorderStyle: .inspector(.famicomWars),
                woodGradient: [FamicomPPUPalette.brown, FamicomPPUPalette.darkBrown, FamicomPPUPalette.gold],
                woodLowerBase: nil,
                woodDeep: FamicomPPUPalette.black,
                woodHighlight: FamicomPPUPalette.yellow,
                woodGrainDark: FamicomPPUPalette.brown,
                woodGrainLight: FamicomPPUPalette.gold,
                headerTint: FamicomPPUPalette.black,
                headerFGTint: FamicomPPUPalette.white,
                headerOpacity: 1,
                headerBorder: FamicomPPUPalette.darkGray,
                headerShadow: FamicomPPUPalette.black
            )
        case .superFamicomWars:
            return PlaytestFrameTheme(
                parchmentGradient: [rgb(0xF2E3D0), rgb(0xD9BFA9), rgb(0xB58D78)],
                parchmentHighlight: rgb(0xFFF5E8),
                parchmentShadow: rgb(0x51332A),
                gridColor: rgb(0x6A4338),
                gridRegularOpacity: 0.065,
                gridMajorOpacity: 0.105,
                flatWoodBorderStyle: .inspector(.superFamicomWars),
                woodGradient: [rgb(0x472016), rgb(0x8B4630), rgb(0x542319)],
                woodLowerBase: nil,
                woodDeep: rgb(0x1B0907),
                woodHighlight: rgb(0xD98B57),
                woodGrainDark: rgb(0x2B100B),
                woodGrainLight: rgb(0xE8A47A),
                // Super Famicom Wars keeps the dark brown command-window
                // language in its header rather than switching to the
                // editor's light chrome.
                headerTint: rgb(0x673A2A),
                headerFGTint: rgb(0xFFF5E8),
                headerOpacity: 1,
                headerBorder: rgb(0x1F2730),
                headerShadow: rgb(0x160C0A)
            )
        case .gbWars:
            return Self.gameBoy(
                parchment: [rgb(0x9A9E3F), rgb(0x496B22), rgb(0x1B2A09)],
                wood: [rgb(0x496B22), rgb(0x0E450B), rgb(0x1B2A09)],
                headerTint: rgb(0xF2F0B7),
                headerFGTint: rgb(0x1B2A09),
                headerBorder: rgb(0x1B2A09),
                statusTheme: .gameBoyWars
            )
        case .gbWars2:
            return Self.gameBoy(
                parchment: [rgb(0xE5E6D7), rgb(0xB7C5B0), rgb(0x7A9274)],
                wood: [rgb(0x233E32), rgb(0x4C765A), rgb(0x17291F)],
                headerTint: rgb(0xF4F7E8),
                headerFGTint: rgb(0x1B2A09),
                headerBorder: rgb(0x315A42),
                statusTheme: .gameBoyWars2
            )
        case .gbWars3:
            return Self.gameBoy(
                parchment: [rgb(0xF0EDC9), rgb(0xB7C88A), rgb(0x698B5D)],
                wood: [rgb(0x3A5A24), rgb(0x6D8738), rgb(0x263E1C)],
                headerTint: rgb(0xFFFEE0),
                headerFGTint: rgb(0x1B2A09),
                headerBorder: rgb(0x38572A),
                statusTheme: .gameBoyWars3
            )
        case .aw1:
            return PlaytestFrameTheme(
                parchmentGradient: [rgb(0xF5F0D9), rgb(0xDCCB9B), rgb(0xB5A57A)],
                parchmentHighlight: rgb(0xFFFBEA),
                parchmentShadow: rgb(0x4F4635),
                gridColor: rgb(0x67553B),
                gridRegularOpacity: 0.06,
                gridMajorOpacity: 0.09,
                flatWoodBorderStyle: .inspector(.advanceWars),
                woodGradient: [rgb(0x3B271B), rgb(0x72522D), rgb(0x3E2517)],
                woodLowerBase: nil,
                woodDeep: rgb(0x17100B),
                woodHighlight: rgb(0xD7A46A),
                woodGrainDark: rgb(0x29190E),
                woodGrainLight: rgb(0xD9A46E),
                headerTint: rgb(0xFFFDF2),
                headerFGTint: rgb(0x1B2A09),
                headerOpacity: 1,
                headerBorder: rgb(0x6B614D),
                headerShadow: rgb(0x302519)
            )
        case .aw2:
            return PlaytestFrameTheme(
                parchmentGradient: [rgb(0xEDF1DC), rgb(0xC7D2B4), rgb(0x8BA79A)],
                parchmentHighlight: rgb(0xF9FFF0),
                parchmentShadow: rgb(0x324A4A),
                gridColor: rgb(0x3A5D5A),
                gridRegularOpacity: 0.06,
                gridMajorOpacity: 0.095,
                flatWoodBorderStyle: .inspector(.advanceWars2),
                woodGradient: [rgb(0x203D4A), rgb(0x4B6E65), rgb(0x1B2B32)],
                woodLowerBase: nil,
                woodDeep: rgb(0x0D1B20),
                woodHighlight: rgb(0xA9D0B0),
                woodGrainDark: rgb(0x142932),
                woodGrainLight: rgb(0x93C4B1),
                headerTint: rgb(0xF7FFF4),
                headerFGTint: rgb(0x1B2A09),
                headerOpacity: 1,
                headerBorder: rgb(0x47716E),
                headerShadow: rgb(0x1A3032)
            )
        case .normal, .snow, .desert, .wasteland:
            return PlaytestFrameTheme(
                parchmentGradient: [rgb(0xE7F3EA), rgb(0xB8D7D0), rgb(0x6D9D9B)],
                parchmentHighlight: rgb(0xF5FFF9),
                parchmentShadow: rgb(0x274D50),
                gridColor: rgb(0x31595C),
                gridRegularOpacity: 0.055,
                gridMajorOpacity: 0.09,
                flatWoodBorderStyle: .textured,
                woodGradient: [rgb(0x203A43), rgb(0x356A72), rgb(0x162A32)],
                woodLowerBase: nil,
                woodDeep: rgb(0x0B161C),
                woodHighlight: rgb(0x9CD5D2),
                woodGrainDark: rgb(0x142A32),
                woodGrainLight: rgb(0x78B8B8),
                headerTint: rgb(0xF8FFFF),
                headerFGTint: rgb(0x1B2A09),
                headerOpacity: 0.52,
                headerBorder: rgb(0x3F7477),
                headerShadow: rgb(0x172E34)
            )
        case .daysOfRuin:
            return PlaytestFrameTheme(
                parchmentGradient: [rgb(0xE2E0D6), rgb(0xB8B8AE), rgb(0x787A78)],
                parchmentHighlight: rgb(0xF3F1E8),
                parchmentShadow: rgb(0x252928),
                gridColor: rgb(0x464843),
                gridRegularOpacity: 0.065,
                gridMajorOpacity: 0.10,
                flatWoodBorderStyle: .textured,
                woodGradient: [rgb(0x272B2C), rgb(0x55534C), rgb(0x1B1D1E)],
                woodLowerBase: nil,
                woodDeep: rgb(0x0F1112),
                woodHighlight: rgb(0xA9A086),
                woodGrainDark: rgb(0x16191A),
                woodGrainLight: rgb(0x8C887D),
                headerTint: rgb(0xF2F1EB),
                headerFGTint: rgb(0x1B2A09),
                headerOpacity: 0.54,
                headerBorder: rgb(0x5B5E5A),
                headerShadow: rgb(0x1A1D1D)
            )
        }
    }

    private static func gameBoy(
        parchment: [Color],
        wood: [Color],
        headerTint: Color,
        headerFGTint: Color,
        headerBorder: Color,
        statusTheme: PlaytestStatusTheme
    ) -> PlaytestFrameTheme {
        PlaytestFrameTheme(
            parchmentGradient: parchment,
            parchmentHighlight: rgb(0xD7D98D),
            parchmentShadow: rgb(0x122006),
            gridColor: rgb(0x1B2A09),
            gridRegularOpacity: 0.075,
            gridMajorOpacity: 0.12,
            flatWoodBorderStyle: .inspector(statusTheme),
            woodGradient: wood,
            woodLowerBase: nil,
            woodDeep: rgb(0x081005),
            woodHighlight: rgb(0x9A9E3F),
            woodGrainDark: rgb(0x0E450B),
            woodGrainLight: rgb(0x78952F),
            headerTint: headerTint,
            headerFGTint: headerFGTint,
            // Game Boy Wars 1–3 use the same opaque LCD-style command
            // windows as their map/status panels. Modern textured frames
            // retain translucency below, where it is part of the chrome.
            headerOpacity: 1,
            headerBorder: headerBorder,
            headerShadow: rgb(0x0E1808)
        )
    }

    private static func rgb(_ value: UInt32) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
