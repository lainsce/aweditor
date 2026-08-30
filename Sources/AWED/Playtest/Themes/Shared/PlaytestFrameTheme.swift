import SwiftUI
import AppKit
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
///
/// Per-game frame values live in sibling `Themes/<game>` files; this shared
/// type only owns the common shape and tileset dispatch.
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
            adaptiveRGB(light: 0xFFEECC, dark: 0x3A3026),
            adaptiveRGB(light: 0xEEDDAA, dark: 0x30261D),
            adaptiveRGB(light: 0xEECC99, dark: 0x261C15)
        ],
        parchmentHighlight: .white,
        parchmentShadow: .black,
        gridColor: rgb(0x554411),
        gridRegularOpacity: 0.12,
        gridMajorOpacity: 0.2,
        flatWoodBorderStyle: .textured,
        woodGradient: [rgb(0x773311), rgb(0xBB6622), rgb(0x884411)],
        woodLowerBase: rgb(0x662200),
        woodDeep: rgb(0x220000),
        woodHighlight: rgb(0xFFAA44),
        woodGrainDark: rgb(0x441100),
        woodGrainLight: rgb(0xFFAA44),
        headerTint: .white,
        headerFGTint: .black,
        headerOpacity: 0.5,
        headerBorder: rgb(0x886633),
        headerShadow: .black
    )

    static func playtest(for tileset: Tileset) -> PlaytestFrameTheme {
        switch tileset {
        case .famicomWars: return .famicomWars
        case .superFamicomWars: return .superFamicomWars
        case .gbWars: return .gameBoyWars
        case .gbWars2: return .gameBoyWars2
        case .gbWars3: return .gameBoyWars3
        case .aw1: return .advanceWars
        case .aw2: return .advanceWars2
        case .normal, .snow, .desert, .wasteland: return .dualStrike
        case .daysOfRuin: return .daysOfRuin
        }
    }

    static func gameBoy(
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

    static func rgb(_ value: UInt32) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    static func adaptiveRGB(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? dark
                : light

            return NSColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}
