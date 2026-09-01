import AWEDCore
import SwiftUI

/// Display-space names for the NTSC Famicom/NES RP2C02 (2C02) master palette.
///
/// The PPU stores six-bit palette indices rather than RGB triples. Keeping the
/// index-to-RGB table here makes the historical UI use the same finite colour
/// vocabulary as the cartridge instead of accumulating hand-picked SwiftUI
/// colours. The RGB rendition follows the commonly used NTSC 2C02 table
/// documented by NESdev: https://www.nesdev.org/wiki/PPU_palettes
enum FamicomPPUPalette {
    private static let rgbByIndex: [UInt32] = [
        0x7C7C7C, 0x0000FC, 0x0000BC, 0x4428BC,
        0x940084, 0xA80020, 0xA81000, 0x881400,
        0x503000, 0x007800, 0x006800, 0x005800,
        0x004058, 0x000000, 0x000000, 0x000000,
        0xBCBCBC, 0x0078F8, 0x0058F8, 0x6844FC,
        0xD800CC, 0xE40058, 0xF83800, 0xE45C10,
        0xAC7C00, 0x00B800, 0x00A800, 0x00A844,
        0x008888, 0x000000, 0x000000, 0x000000,
        0xF8F8F8, 0x3CBCFC, 0x6888FC, 0x9878F8,
        0xF878F8, 0xF85898, 0xF87858, 0xF0D0B0,
        0xB8B800, 0xB8F818, 0x58D854, 0x58F898,
        0x00E8D8, 0x787878, 0x000000, 0x000000,
        0xFCFCFC, 0xA4E4FC, 0xB8B8F8, 0xD8B8F8,
        0xF8B8F8, 0xF8A4C0, 0xF0D0B0, 0xFCE0C0,
        0xF8D878, 0xD8F878, 0xB8F8B8, 0xB8F8D8,
        0x00FCFC, 0xF8D8F8, 0x000000, 0x000000
    ]

    static let black = color(index: 0x0F)
    static let darkGray = color(index: 0x00)
    static let gray = color(index: 0x10)
    static let mediumGray = color(index: 0x2D)
    static let lightGray = color(index: 0x20)
    static let white = color(index: 0x30)
    static let red = color(index: 0x16)
    static let darkRed = color(index: 0x06)
    static let blue = color(index: 0x12)
    static let darkBlue = color(index: 0x02)
    static let green = color(index: 0x19)
    static let darkGreen = color(index: 0x0A)
    static let yellow = color(index: 0x28)
    static let orange = color(index: 0x17)
    static let gold = color(index: 0x18)
    static let cyan = color(index: 0x21)
    static let paleBlue = color(index: 0x31)
    static let paleGreen = color(index: 0x3A)
    static let purple = color(index: 0x03)
    static let brown = color(index: 0x08)
    static let darkBrown = color(index: 0x07)

    private static func color(index: Int) -> Color {
        let value = rgbByIndex[index & 0x3F]
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

enum PlaytestBannerTreatment: Equatable {
    case famicomWars
    case gameBoyWars
    case superFamicomWars
    case gameBoyWars2
    case gameBoyWars3
    case advanceWars
    case advanceWars2
    case dualStrike
    case daysOfRuin
}

struct PlaytestBannerTheme {
    let treatment: PlaytestBannerTreatment
    let titleFont: Font
    let titleColor: Color
    let surface: Color
    let secondarySurface: Color
    let border: Color
    let innerBorder: Color
    let shadow: Color
    let cornerRadius: CGFloat
    let borderPixels: CGFloat
    let shadowRadius: CGFloat
    let shadowYOffset: CGFloat
}

/// The command rail is an editor-side convenience, but its chrome follows
/// the command windows that each cartridge actually used. Keeping this as a
/// separate value object avoids making the status cards inherit a rail's
/// unusually dense spacing or selection colors.
struct PlaytestLegacyMenuTheme {
    enum Frame {
        case famicom
        case superFamicom
        case gameBoyDMG
        case gameBoyColor
        case gameBoyWars3
        case advanceWars
        case modern
    }

    let title: String
    let surface: Color
    let rowSurface: Color
    let activeSurface: Color
    let disabledSurface: Color
    let text: Color
    let activeText: Color
    let secondaryText: Color
    let border: Color
    let innerBorder: Color
    let secondaryBorder: Color
    let frameShadow: Color
    let frame: Frame
    let railWidth: CGFloat
    let contentPadding: CGFloat
    let rowHeight: CGFloat
    let rowSpacing: CGFloat
    let rowCornerRadius: CGFloat
    let selectionMarker: String
    /// Only the GBA map menu uses a persistent pictogram column. The
    /// Famicom/Super Famicom and Game Boy command windows are text-first;
    /// adding editor-style letter badges there would be visibly anachronistic.
    let showsActionIcons: Bool
    let menuFont: Font
    let titleFont: Font
    let detailFont: Font
}

/// The small strength readout drawn over a damaged unit.  These markers are
/// part of the map artwork, so their geometry is intentionally more compact
/// and pixel-like than the inspector's modern controls.
struct PlaytestDamageBadgeTheme {
    let background: Color
    let border: Color
    let text: Color
    let font: Font
    let size: CGSize
    let offset: CGPoint
    let cornerRadius: CGFloat
    let borderWidth: CGFloat
    let shadow: Color
    let shadowOffset: CGSize
    let shadowOpacity: Double
}

enum PlaytestStatusTheme: Equatable {
    case famicomWars
    case gameBoyWars
    case superFamicomWars
    case gameBoyWars2
    case gameBoyWars3
    case advanceWars
    case advanceWars2
    case dualStrike
    case daysOfRuin

    // Measured from a classic Game Boy display rather than the brighter
    // generic DMG palette commonly used by emulators.
    static let gameBoyBlack = rgb(0x1B2A09)
    static let gameBoyDarkGray = rgb(0x0E450B)
    static let gameBoyLightGray = rgb(0x496B22)
    static let gameBoyWhite = rgb(0x9A9E3F)

    init(tileset: Tileset) {
        switch tileset {
        case .famicomWars: self = .famicomWars
        case .gbWars: self = .gameBoyWars
        case .superFamicomWars: self = .superFamicomWars
        case .gbWars2: self = .gameBoyWars2
        case .gbWars3: self = .gameBoyWars3
        case .aw1: self = .advanceWars
        case .aw2: self = .advanceWars2
        case .normal, .snow, .desert, .wasteland: self = .dualStrike
        case .daysOfRuin: self = .daysOfRuin
        }
    }


    static func rgb(_ value: UInt32) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    static func rgb555(_ red: Int, _ green: Int, _ blue: Int) -> Color {
        Color(red: Double(red) / 31, green: Double(green) / 31, blue: Double(blue) / 31)
    }
}
