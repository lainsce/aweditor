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
    private static let gameBoyBlack = rgb(0x1B2A09)
    private static let gameBoyDarkGray = rgb(0x0E450B)
    private static let gameBoyLightGray = rgb(0x496B22)
    private static let gameBoyWhite = rgb(0x9A9E3F)

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

    // These values describe the games' compact map/status popups, rather than
    // borrowing the more decorative chrome from their title and CO screens.
    var surface: Color {
        switch self {
        case .famicomWars:
            FamicomPPUPalette.black
        case .gameBoyWars:
            Self.gameBoyWhite
        case .superFamicomWars:
            Self.rgb555(19, 9, 11)
        case .gameBoyWars2:
            Self.rgb555(29, 31, 31)
        case .gameBoyWars3:
            Self.rgb555(31, 31, 29)
        case .advanceWars, .advanceWars2:
            Self.rgb555(4, 5, 1)
        case .dualStrike:
            Self.rgb555(3, 4, 2)
        case .daysOfRuin:
            Self.rgb555(4, 4, 3)
        }
    }

    var surfaceOpacity: Double {
        switch self {
        case .advanceWars: 0.80
        case .advanceWars2: 0.82
        case .dualStrike: 0.84
        case .daysOfRuin: 0.88
        default: 1
        }
    }

    var primaryText: Color {
        switch self {
        case .famicomWars:
            FamicomPPUPalette.white
        case .gameBoyWars:
            Self.gameBoyBlack
        case .superFamicomWars:
            Self.rgb555(31, 29, 27)
        case .gameBoyWars2:
            Self.rgb555(0, 1, 4)
        case .gameBoyWars3:
            Self.rgb555(1, 2, 1)
        case .advanceWars, .advanceWars2, .dualStrike:
            Self.rgb555(31, 31, 29)
        case .daysOfRuin:
            Self.rgb555(29, 28, 24)
        }
    }

    var secondaryText: Color {
        switch self {
        case .famicomWars:
            FamicomPPUPalette.gray
        case .gameBoyWars:
            Self.gameBoyDarkGray
        case .superFamicomWars:
            Self.rgb555(29, 20, 21)
        case .gameBoyWars2:
            Self.rgb555(3, 13, 31)
        case .gameBoyWars3:
            Self.rgb555(3, 10, 27)
        case .advanceWars, .advanceWars2, .dualStrike:
            Self.rgb555(25, 27, 20)
        case .daysOfRuin:
            Self.rgb555(21, 20, 17)
        }
    }

    var outerBorder: Color {
        switch self {
        case .famicomWars: FamicomPPUPalette.darkGray
        case .gameBoyWars: Self.gameBoyBlack
        case .superFamicomWars: Self.rgb555(5, 2, 4)
        case .gameBoyWars2: Self.rgb555(0, 1, 4)
        case .gameBoyWars3: Self.rgb555(1, 2, 1)
        case .daysOfRuin: Self.rgb555(1, 1, 1)
        case .advanceWars, .advanceWars2, .dualStrike: .clear
        }
    }

    var innerBorder: Color {
        switch self {
        case .famicomWars: FamicomPPUPalette.white
        case .gameBoyWars: Self.gameBoyLightGray
        case .superFamicomWars: Self.rgb555(29, 20, 21)
        case .gameBoyWars2: Self.rgb555(18, 27, 31)
        case .gameBoyWars3: Self.rgb555(12, 22, 5)
        case .advanceWars, .advanceWars2, .dualStrike, .daysOfRuin: .clear
        }
    }

    // Border widths are measured in physical screen pixels. The view converts
    // them with displayScale so a requested 1 px rule remains 1 px on Retina.
    var outerBorderPixels: CGFloat {
        switch self {
        case .famicomWars: 2
        case .advanceWars, .advanceWars2, .dualStrike: 0
        default: 1
        }
    }

    var innerBorderPixels: CGFloat {
        switch self {
        case .famicomWars: 2
        case .gameBoyWars, .superFamicomWars, .gameBoyWars2, .gameBoyWars3: 1
        case .advanceWars, .advanceWars2, .dualStrike, .daysOfRuin: 0
        }
    }

    var innerBorderInsetPixels: CGFloat {
        switch self {
        case .famicomWars: 2
        case .superFamicomWars, .gameBoyWars3: 3
        case .gameBoyWars, .gameBoyWars2: 2
        case .advanceWars, .advanceWars2, .dualStrike, .daysOfRuin: 0
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .famicomWars: 4
        case .superFamicomWars: 2
        default: 0
        }
    }

    var contentPadding: CGFloat {
        switch self {
        case .famicomWars, .gameBoyWars, .superFamicomWars, .gameBoyWars2, .gameBoyWars3: 6
        case .advanceWars, .advanceWars2, .dualStrike, .daysOfRuin: 8
        }
    }

    /// Visual grammar for the keyboard-operated command rail. The values are
    /// deliberately based on the map/menu windows, rather than title screens
    /// or the editor's glass surfaces.
    var legacyMenu: PlaytestLegacyMenuTheme {
        switch self {
        case .famicomWars:
            PlaytestLegacyMenuTheme(
                title: "COMMAND",
                surface: FamicomPPUPalette.black,
                rowSurface: FamicomPPUPalette.black,
                activeSurface: FamicomPPUPalette.yellow,
                disabledSurface: FamicomPPUPalette.black,
                text: FamicomPPUPalette.white,
                activeText: FamicomPPUPalette.black,
                secondaryText: FamicomPPUPalette.gray,
                border: FamicomPPUPalette.darkGray,
                innerBorder: FamicomPPUPalette.white,
                secondaryBorder: FamicomPPUPalette.darkGray,
                frameShadow: FamicomPPUPalette.black,
                frame: .famicom,
                railWidth: 248,
                contentPadding: 10,
                rowHeight: 27,
                rowSpacing: 3,
                rowCornerRadius: 0,
                selectionMarker: "◆",
                showsActionIcons: false,
                menuFont: themedFont(9, relativeTo: .body, weight: .regular),
                titleFont: titleFont,
                detailFont: detailFont
            )

        case .superFamicomWars:
            PlaytestLegacyMenuTheme(
                title: "COMMAND MENU",
                surface: Self.rgb555(9, 4, 6),
                rowSurface: Self.rgb555(15, 8, 11),
                activeSurface: Self.rgb555(27, 22, 7),
                disabledSurface: Self.rgb555(7, 4, 6),
                text: Self.rgb555(31, 29, 27),
                activeText: Self.rgb555(4, 3, 2),
                secondaryText: Self.rgb555(20, 15, 15),
                border: Self.rgb555(0, 12, 22),
                innerBorder: Self.rgb555(26, 31, 31),
                secondaryBorder: Self.rgb555(12, 22, 28),
                frameShadow: Self.rgb555(1, 1, 2),
                frame: .superFamicom,
                railWidth: 256,
                contentPadding: 11,
                rowHeight: 29,
                rowSpacing: 4,
                rowCornerRadius: 0,
                selectionMarker: "▶",
                showsActionIcons: false,
                menuFont: themedFont(16, relativeTo: .body, weight: .regular),
                titleFont: titleFont,
                detailFont: detailFont
            )

        case .gameBoyWars:
            PlaytestLegacyMenuTheme(
                title: "COMMAND",
                surface: Self.rgb(0xBFC66E),
                rowSurface: Self.rgb(0xD4D58B),
                activeSurface: Self.rgb(0x315315),
                disabledSurface: Self.rgb(0x7A813B),
                text: Self.gameBoyBlack,
                activeText: Self.rgb(0xE7E9A4),
                secondaryText: Self.gameBoyDarkGray,
                border: Self.gameBoyBlack,
                innerBorder: Self.gameBoyLightGray,
                secondaryBorder: Self.rgb(0xD4D58B),
                frameShadow: Self.gameBoyDarkGray,
                frame: .gameBoyDMG,
                railWidth: 226,
                contentPadding: 9,
                rowHeight: 29,
                rowSpacing: 3,
                rowCornerRadius: 0,
                selectionMarker: "■",
                showsActionIcons: false,
                menuFont: bodyFont,
                titleFont: titleFont,
                detailFont: detailFont
            )

        case .gameBoyWars2:
            // Hudson kept the original GB Wars interface in this release;
            // only the GBC palette and range indicators are new.
            PlaytestLegacyMenuTheme(
                title: "COMMAND",
                surface: Self.rgb555(29, 31, 25),
                rowSurface: Self.rgb555(31, 31, 29),
                activeSurface: Self.rgb555(16, 22, 30),
                disabledSurface: Self.rgb555(20, 22, 19),
                text: Self.rgb555(0, 1, 4),
                activeText: Self.rgb555(31, 31, 29),
                secondaryText: Self.rgb555(3, 13, 31),
                border: Self.rgb555(0, 1, 4),
                innerBorder: Self.rgb555(19, 28, 31),
                secondaryBorder: Self.rgb555(29, 23, 7),
                frameShadow: Self.rgb555(0, 1, 4),
                frame: .gameBoyColor,
                railWidth: 230,
                contentPadding: 9,
                rowHeight: 28,
                rowSpacing: 3,
                rowCornerRadius: 0,
                selectionMarker: "▶",
                showsActionIcons: false,
                menuFont: bodyFont,
                titleFont: titleFont,
                detailFont: detailFont
            )

        case .gameBoyWars3:
            PlaytestLegacyMenuTheme(
                title: "COMMAND",
                surface: Self.rgb555(31, 31, 29),
                rowSurface: Self.rgb555(31, 31, 29),
                activeSurface: Self.rgb555(20, 27, 9),
                disabledSurface: Self.rgb555(20, 22, 17),
                text: Self.rgb555(3, 10, 27),
                activeText: Self.rgb555(31, 31, 23),
                secondaryText: Self.rgb555(3, 10, 27),
                border: Self.rgb555(0, 8, 20),
                innerBorder: Self.rgb555(0, 22, 31),
                secondaryBorder: Self.rgb555(28, 31, 18),
                frameShadow: Self.rgb555(0, 3, 8),
                frame: .gameBoyWars3,
                railWidth: 232,
                contentPadding: 8,
                rowHeight: 28,
                rowSpacing: 2,
                rowCornerRadius: 0,
                selectionMarker: "▶",
                showsActionIcons: false,
                menuFont: bodyFont,
                titleFont: titleFont,
                detailFont: detailFont
            )

        case .advanceWars:
            PlaytestLegacyMenuTheme(
                title: "MAP MENU",
                surface: Self.rgb555(31, 25, 18),
                rowSurface: Self.rgb555(31, 25, 18),
                activeSurface: Self.rgb555(19, 21, 27),
                disabledSurface: Self.rgb555(20, 18, 14),
                text: Self.rgb555(12, 6, 3),
                activeText: Self.rgb555(31, 31, 29),
                secondaryText: Self.rgb555(21, 15, 10),
                border: Self.rgb555(7, 4, 3),
                innerBorder: Self.rgb555(31, 14, 6),
                secondaryBorder: Self.rgb555(21, 24, 28),
                frameShadow: Self.rgb555(2, 2, 2),
                frame: .advanceWars,
                railWidth: 252,
                contentPadding: 12,
                rowHeight: 31,
                rowSpacing: 2,
                rowCornerRadius: 1,
                selectionMarker: "›",
                showsActionIcons: true,
                menuFont: bodyFont,
                titleFont: titleFont,
                detailFont: detailFont
            )

        case .advanceWars2:
            PlaytestLegacyMenuTheme(
                title: "MAP MENU",
                surface: Self.rgb555(31, 26, 20),
                rowSurface: Self.rgb555(31, 26, 20),
                activeSurface: Self.rgb555(11, 18, 26),
                disabledSurface: Self.rgb555(19, 18, 15),
                text: Self.rgb555(9, 6, 4),
                activeText: Self.rgb555(31, 31, 29),
                secondaryText: Self.rgb555(21, 16, 11),
                border: Self.rgb555(5, 6, 8),
                innerBorder: Self.rgb555(25, 11, 4),
                secondaryBorder: Self.rgb555(22, 24, 29),
                frameShadow: Self.rgb555(1, 2, 3),
                frame: .advanceWars,
                railWidth: 252,
                contentPadding: 12,
                rowHeight: 31,
                rowSpacing: 2,
                rowCornerRadius: 1,
                selectionMarker: "›",
                showsActionIcons: true,
                menuFont: bodyFont,
                titleFont: titleFont,
                detailFont: detailFont
            )

        case .dualStrike:
            PlaytestLegacyMenuTheme(
                title: "COMMAND",
                surface: surface,
                rowSurface: surface,
                activeSurface: resourceTint,
                disabledSurface: surface.opacity(0.6),
                text: primaryText,
                activeText: primaryText,
                secondaryText: secondaryText,
                border: buttonBorder,
                innerBorder: .clear,
                secondaryBorder: .clear,
                frameShadow: .clear,
                frame: .modern,
                railWidth: 230,
                contentPadding: 9,
                rowHeight: 32,
                rowSpacing: 5,
                rowCornerRadius: buttonCornerRadius,
                selectionMarker: "›",
                showsActionIcons: false,
                menuFont: bodyFont,
                titleFont: titleFont,
                detailFont: detailFont
            )

        case .daysOfRuin:
            PlaytestLegacyMenuTheme(
                title: "COMMAND",
                surface: surface,
                rowSurface: surface,
                activeSurface: resourceTint,
                disabledSurface: surface.opacity(0.6),
                text: primaryText,
                activeText: primaryText,
                secondaryText: secondaryText,
                border: buttonBorder,
                innerBorder: .clear,
                secondaryBorder: .clear,
                frameShadow: .clear,
                frame: .modern,
                railWidth: 230,
                contentPadding: 9,
                rowHeight: 32,
                rowSpacing: 5,
                rowCornerRadius: buttonCornerRadius,
                selectionMarker: "›",
                showsActionIcons: false,
                menuFont: bodyFont,
                titleFont: titleFont,
                detailFont: detailFont
            )
        }
    }

    var preferredColorScheme: ColorScheme {
        switch self {
        case .gameBoyWars, .gameBoyWars2, .gameBoyWars3: .light
        default: .dark
        }
    }

    private struct FontProfile {
        let family: String
        let bodySize: CGFloat
        let titleSize: CGFloat
        let detailSize: CGFloat
        let valueSize: CGFloat
        let bodyWeight: Font.Weight
        let titleWeight: Font.Weight
        let detailWeight: Font.Weight
        let valueWeight: Font.Weight
    }

    private var fontProfile: FontProfile {
        switch self {
        case .famicomWars:
            FontProfile(
                family: "Press Start 2P",
                bodySize: 12,
                titleSize: 12,
                detailSize: 8,
                valueSize: 9,
                bodyWeight: .regular,
                titleWeight: .regular,
                detailWeight: .regular,
                valueWeight: .regular
            )
        case .gameBoyWars:
            FontProfile(
                family: "VT323",
                bodySize: 18,
                titleSize: 21,
                detailSize: 14,
                valueSize: 15,
                bodyWeight: .regular,
                titleWeight: .regular,
                detailWeight: .regular,
                valueWeight: .regular
            )
        case .superFamicomWars:
            FontProfile(
                family: "VT323",
                bodySize: 18,
                titleSize: 21,
                detailSize: 14,
                valueSize: 15,
                bodyWeight: .regular,
                titleWeight: .regular,
                detailWeight: .regular,
                valueWeight: .regular
            )
        case .gameBoyWars2, .gameBoyWars3:
            FontProfile(
                family: "Silkscreen",
                bodySize: 13,
                titleSize: 15,
                detailSize: 10,
                valueSize: 11,
                bodyWeight: .regular,
                titleWeight: .bold,
                detailWeight: .bold,
                valueWeight: .bold
            )
        case .advanceWars, .advanceWars2:
            FontProfile(
                family: "Share Tech Mono",
                bodySize: 13,
                titleSize: 16,
                detailSize: 11,
                valueSize: 12,
                bodyWeight: .regular,
                titleWeight: .regular,
                detailWeight: .regular,
                valueWeight: .regular
            )
        case .dualStrike:
            FontProfile(
                family: "Rajdhani",
                bodySize: 14,
                titleSize: 17,
                detailSize: 11,
                valueSize: 12,
                bodyWeight: .regular,
                titleWeight: .semibold,
                detailWeight: .semibold,
                valueWeight: .semibold
            )
        case .daysOfRuin:
            FontProfile(
                family: "Rajdhani",
                bodySize: 14,
                titleSize: 18,
                detailSize: 12,
                valueSize: 12,
                bodyWeight: .regular,
                titleWeight: .semibold,
                detailWeight: .semibold,
                valueWeight: .semibold
            )
        }
    }

    /// Font metadata used when a legacy menu sizes itself to its visible
    /// command labels. Keeping the measurement source next to the SwiftUI
    /// font construction prevents the rail from drifting when an era's face
    /// or point size changes.
    var legacyMenuFontFamily: String { fontProfile.family }

    var legacyMenuFontPointSize: CGFloat {
        switch self {
        case .famicomWars: 9
        case .superFamicomWars: 16
        default: fontProfile.bodySize
        }
    }

    private func themedFont(
        _ size: CGFloat,
        relativeTo textStyle: Font.TextStyle,
        weight: Font.Weight
    ) -> Font {
        .custom(fontProfile.family, size: size, relativeTo: textStyle)
            .weight(weight)
    }

    var bodyFont: Font {
        themedFont(
            fontProfile.bodySize,
            relativeTo: .body,
            weight: fontProfile.bodyWeight
        )
    }

    var titleFont: Font {
        themedFont(
            fontProfile.titleSize,
            relativeTo: .headline,
            weight: fontProfile.titleWeight
        )
    }

    var detailFont: Font {
        themedFont(
            fontProfile.detailSize,
            relativeTo: .caption,
            weight: fontProfile.detailWeight
        )
    }

    var valueFont: Font {
        themedFont(
            fontProfile.valueSize,
            relativeTo: .callout,
            weight: fontProfile.valueWeight
        )
    }

    /// Era-specific map strength readouts.  The original cartridge UIs use
    /// small opaque number blocks, not the rounded translucent badge that is
    /// appropriate for the modern editor chrome.
    var damageBadgeTheme: PlaytestDamageBadgeTheme {
        switch self {
        case .famicomWars:
            PlaytestDamageBadgeTheme(
                background: FamicomPPUPalette.black,
                border: FamicomPPUPalette.gray,
                text: FamicomPPUPalette.white,
                font: themedFont(6, relativeTo: .caption, weight: .regular),
                size: CGSize(width: 12, height: 10),
                offset: CGPoint(x: 1, y: 1),
                cornerRadius: 0,
                borderWidth: 1,
                shadow: FamicomPPUPalette.black,
                shadowOffset: CGSize(width: 1, height: 1),
                shadowOpacity: 0.95
            )

        case .gameBoyWars:
            PlaytestDamageBadgeTheme(
                background: Self.gameBoyBlack,
                border: Self.gameBoyDarkGray,
                text: Self.gameBoyWhite,
                font: themedFont(9, relativeTo: .caption, weight: .regular),
                size: CGSize(width: 13, height: 10),
                offset: CGPoint(x: 1, y: 1),
                cornerRadius: 0,
                borderWidth: 1,
                shadow: Self.gameBoyDarkGray,
                shadowOffset: CGSize(width: 1, height: 1),
                shadowOpacity: 0.9
            )

        case .superFamicomWars:
            PlaytestDamageBadgeTheme(
                background: Self.rgb555(5, 2, 4),
                border: Self.rgb555(29, 20, 21),
                text: Self.rgb555(31, 29, 27),
                font: themedFont(9, relativeTo: .caption, weight: .regular),
                size: CGSize(width: 14, height: 11),
                offset: CGPoint(x: 1, y: 1),
                cornerRadius: 0,
                borderWidth: 1,
                shadow: Self.rgb555(1, 1, 2),
                shadowOffset: CGSize(width: 1, height: 1),
                shadowOpacity: 0.9
            )

        case .gameBoyWars2:
            PlaytestDamageBadgeTheme(
                background: Self.rgb555(0, 1, 4),
                border: Self.rgb555(18, 27, 31),
                text: Self.rgb555(31, 31, 29),
                font: themedFont(8, relativeTo: .caption, weight: .bold),
                size: CGSize(width: 13, height: 10),
                offset: CGPoint(x: 1, y: 1),
                cornerRadius: 0,
                borderWidth: 1,
                shadow: Self.rgb555(0, 1, 4),
                shadowOffset: CGSize(width: 1, height: 1),
                shadowOpacity: 0.85
            )

        case .gameBoyWars3:
            PlaytestDamageBadgeTheme(
                background: Self.rgb555(0, 8, 20),
                border: Self.rgb555(0, 22, 31),
                text: Self.rgb555(31, 31, 23),
                font: themedFont(8, relativeTo: .caption, weight: .bold),
                size: CGSize(width: 13, height: 10),
                offset: CGPoint(x: 1, y: 1),
                cornerRadius: 0,
                borderWidth: 1,
                shadow: Self.rgb555(0, 3, 8),
                shadowOffset: CGSize(width: 1, height: 1),
                shadowOpacity: 0.85
            )

        case .advanceWars:
            PlaytestDamageBadgeTheme(
                background: Self.rgb555(2, 2, 2),
                border: Self.rgb555(15, 16, 14),
                text: Self.rgb555(31, 31, 29),
                font: themedFont(8, relativeTo: .caption, weight: .regular),
                size: CGSize(width: 14, height: 10),
                offset: CGPoint(x: 1, y: 1),
                cornerRadius: 0,
                borderWidth: 1,
                shadow: Self.rgb555(0, 0, 0),
                shadowOffset: CGSize(width: 1, height: 1),
                shadowOpacity: 0.75
            )

        case .advanceWars2:
            PlaytestDamageBadgeTheme(
                background: Self.rgb555(2, 4, 7),
                border: Self.rgb555(17, 23, 27),
                text: Self.rgb555(31, 31, 29),
                font: themedFont(8, relativeTo: .caption, weight: .regular),
                size: CGSize(width: 14, height: 10),
                offset: CGPoint(x: 1, y: 1),
                cornerRadius: 0,
                borderWidth: 1,
                shadow: Self.rgb555(0, 1, 3),
                shadowOffset: CGSize(width: 1, height: 1),
                shadowOpacity: 0.75
            )

        case .dualStrike:
            PlaytestDamageBadgeTheme(
                background: Self.rgb555(2, 7, 10),
                border: buttonBorder,
                text: primaryText,
                font: themedFont(9, relativeTo: .caption, weight: .semibold),
                size: CGSize(width: 15, height: 11),
                offset: CGPoint(x: 1, y: 1),
                cornerRadius: 2,
                borderWidth: 1,
                shadow: Self.rgb555(0, 1, 2),
                shadowOffset: CGSize(width: 1, height: 1),
                shadowOpacity: 0.55
            )

        case .daysOfRuin:
            PlaytestDamageBadgeTheme(
                background: Self.rgb555(8, 6, 5),
                border: Self.rgb555(20, 16, 11),
                text: Self.rgb555(29, 28, 24),
                font: themedFont(9, relativeTo: .caption, weight: .semibold),
                size: CGSize(width: 15, height: 11),
                offset: CGPoint(x: 1, y: 1),
                cornerRadius: 1,
                borderWidth: 1,
                shadow: Self.rgb555(1, 1, 1),
                shadowOffset: CGSize(width: 1, height: 1),
                shadowOpacity: 0.6
            )
        }
    }

    /// The day banner is deliberately separate from the status-card surface.
    /// Each game family gets the compact, low-resolution treatment associated
    /// with its hardware generation instead of inheriting the editor's glass.
    var bannerTheme: PlaytestBannerTheme {
        switch self {
        case .famicomWars:
            PlaytestBannerTheme(
                treatment: .famicomWars,
                titleFont: themedFont(16, relativeTo: .title2, weight: .regular),
                titleColor: FamicomPPUPalette.white,
                surface: FamicomPPUPalette.black,
                secondarySurface: FamicomPPUPalette.green,
                border: FamicomPPUPalette.green,
                innerBorder: .clear,
                shadow: FamicomPPUPalette.black,
                cornerRadius: 3,
                borderPixels: 2,
                shadowRadius: 0,
                shadowYOffset: 0
            )
        case .gameBoyWars:
            PlaytestBannerTheme(
                treatment: .gameBoyWars,
                titleFont: themedFont(27, relativeTo: .title, weight: .regular),
                titleColor: Self.gameBoyBlack,
                surface: Self.gameBoyWhite,
                secondarySurface: Self.gameBoyLightGray,
                border: Self.gameBoyBlack,
                innerBorder: Self.gameBoyDarkGray,
                shadow: Self.gameBoyDarkGray,
                cornerRadius: 0,
                borderPixels: 1,
                shadowRadius: 0,
                shadowYOffset: 1
            )
        case .superFamicomWars:
            PlaytestBannerTheme(
                treatment: .superFamicomWars,
                titleFont: themedFont(18, relativeTo: .title2, weight: .regular),
                titleColor: Self.rgb(0xC8B1FF),
                surface: Self.rgb(0x673A2A),
                secondarySurface: Self.rgb(0x7B4936),
                border: Self.rgb(0x1F2730),
                innerBorder: Self.rgb(0x89949D),
                shadow: Self.rgb(0x160C0A),
                cornerRadius: 0,
                borderPixels: 1,
                shadowRadius: 1,
                shadowYOffset: 2
            )
        case .gameBoyWars2:
            PlaytestBannerTheme(
                treatment: .gameBoyWars2,
                titleFont: themedFont(18, relativeTo: .title2, weight: .bold),
                titleColor: Self.rgb555(0, 1, 4),
                surface: Self.rgb555(29, 31, 31),
                secondarySurface: Self.rgb555(18, 27, 31),
                border: Self.rgb555(0, 1, 4),
                innerBorder: Self.rgb555(3, 13, 31),
                shadow: Self.rgb555(0, 1, 4),
                cornerRadius: 0,
                borderPixels: 1,
                shadowRadius: 0,
                shadowYOffset: 1
            )
        case .gameBoyWars3:
            PlaytestBannerTheme(
                treatment: .gameBoyWars3,
                titleFont: themedFont(18, relativeTo: .title2, weight: .bold),
                titleColor: Self.rgb555(31, 24, 0),
                surface: Self.rgb(0x000000),
                secondarySurface: Self.rgb555(0, 11, 29),
                border: Self.rgb555(0, 26, 31),
                innerBorder: Self.rgb555(0, 12, 29),
                shadow: Self.rgb555(0, 3, 8),
                cornerRadius: 8,
                borderPixels: 2,
                shadowRadius: 0,
                shadowYOffset: 1
            )
        case .advanceWars:
            PlaytestBannerTheme(
                treatment: .advanceWars,
                titleFont: themedFont(23, relativeTo: .title2, weight: .regular),
                titleColor: Self.rgb555(31, 31, 29),
                surface: Self.rgb555(2, 5, 10),
                secondarySurface: Self.rgb555(4, 12, 20),
                border: .clear,
                innerBorder: .clear,
                shadow: .clear,
                cornerRadius: 0,
                borderPixels: 0,
                shadowRadius: 0,
                shadowYOffset: 0
            )
        case .advanceWars2:
            PlaytestBannerTheme(
                treatment: .advanceWars2,
                titleFont: themedFont(23, relativeTo: .title2, weight: .regular),
                titleColor: Self.rgb555(31, 31, 29),
                surface: Self.rgb555(3, 8, 16),
                secondarySurface: Self.rgb555(5, 17, 29),
                border: .clear,
                innerBorder: .clear,
                shadow: .clear,
                cornerRadius: 0,
                borderPixels: 0,
                shadowRadius: 0,
                shadowYOffset: 0
            )
        case .dualStrike:
            PlaytestBannerTheme(
                treatment: .dualStrike,
                titleFont: .custom("Silkscreen", size: 22, relativeTo: .title2).weight(.bold),
                titleColor: .clear,
                surface: .clear,
                secondarySurface: .clear,
                border: .clear,
                innerBorder: .clear,
                shadow: .clear,
                cornerRadius: 0,
                borderPixels: 0,
                shadowRadius: 0,
                shadowYOffset: 0
            )
        case .daysOfRuin:
            PlaytestBannerTheme(
                treatment: .daysOfRuin,
                titleFont: themedFont(26, relativeTo: .title, weight: .bold),
                titleColor: Self.rgb555(31, 31, 29),
                surface: Self.rgb555(4, 9, 11),
                secondarySurface: Self.rgb555(8, 16, 18),
                border: Self.rgb555(19, 27, 29),
                innerBorder: Self.rgb555(9, 20, 22),
                shadow: Self.rgb555(1, 2, 3),
                cornerRadius: 1,
                borderPixels: 1,
                shadowRadius: 3,
                shadowYOffset: 2
            )
        }
    }

    var shadow: (color: Color, radius: CGFloat, xPixels: CGFloat, yPixels: CGFloat) {
        switch self {
        case .superFamicomWars:
            (Self.rgb555(5, 2, 4).opacity(0.72), 0, 1, 1)
        case .gameBoyWars, .gameBoyWars2, .gameBoyWars3:
            (outerBorder.opacity(0.58), 0, 1, 1)
        default:
            (.clear, 0, 0, 0)
        }
    }

    var warningText: Color {
        switch self {
        case .famicomWars: FamicomPPUPalette.red
        case .gameBoyWars: Self.gameBoyDarkGray
        case .superFamicomWars: Self.rgb555(31, 18, 12)
        case .gameBoyWars2: Self.rgb555(27, 4, 3)
        case .gameBoyWars3: Self.rgb555(27, 4, 3)
        case .advanceWars, .advanceWars2, .dualStrike: Self.rgb555(31, 16, 2)
        case .daysOfRuin: Self.rgb555(24, 8, 5)
        }
    }

    var resourceTint: Color {
        switch self {
        case .famicomWars: FamicomPPUPalette.green
        case .gameBoyWars: Self.gameBoyDarkGray
        case .superFamicomWars: Self.rgb555(29, 20, 21)
        case .gameBoyWars2: Self.rgb555(3, 13, 31)
        case .gameBoyWars3: Self.rgb555(3, 10, 27)
        case .advanceWars, .advanceWars2, .dualStrike: Self.rgb555(5, 17, 29)
        case .daysOfRuin: Self.rgb555(20, 17, 12)
        }
    }

    var buttonCornerRadius: CGFloat {
        switch self {
        case .famicomWars, .gameBoyWars, .gameBoyWars2, .gameBoyWars3: 0
        case .superFamicomWars: 2
        case .advanceWars, .advanceWars2, .dualStrike: 5
        case .daysOfRuin: 1
        }
    }

    var buttonMinHeight: CGFloat {
        switch self {
        case .famicomWars, .gameBoyWars, .gameBoyWars2, .gameBoyWars3: 28
        default: 32
        }
    }

    var buttonBorder: Color {
        switch self {
        case .famicomWars: FamicomPPUPalette.white
        case .gameBoyWars: Self.gameBoyBlack
        case .superFamicomWars: Self.rgb555(5, 2, 4)
        case .gameBoyWars2: Self.rgb555(0, 1, 4)
        case .gameBoyWars3: Self.rgb555(1, 2, 1)
        case .advanceWars, .advanceWars2: Self.rgb555(2, 5, 10)
        case .dualStrike: Self.rgb555(1, 3, 4)
        case .daysOfRuin: Self.rgb555(1, 1, 1)
        }
    }

    var buttonUpperEdge: Color {
        switch self {
        case .famicomWars: FamicomPPUPalette.gray
        case .gameBoyWars: Self.gameBoyWhite
        case .superFamicomWars: Self.rgb555(31, 24, 22)
        case .gameBoyWars2: Self.rgb555(29, 31, 31)
        case .gameBoyWars3: Self.rgb555(31, 31, 29)
        case .advanceWars, .advanceWars2: Self.rgb555(31, 31, 25)
        case .dualStrike: Self.rgb555(22, 28, 29)
        case .daysOfRuin: Self.rgb555(22, 20, 15)
        }
    }

    var buttonLowerEdge: Color {
        switch self {
        case .famicomWars: FamicomPPUPalette.darkGray
        case .gameBoyWars: Self.gameBoyDarkGray
        case .superFamicomWars: Self.rgb555(8, 3, 5)
        case .gameBoyWars2: Self.rgb555(3, 13, 31)
        case .gameBoyWars3: Self.rgb555(3, 10, 2)
        case .advanceWars, .advanceWars2: Self.rgb555(3, 8, 14)
        case .dualStrike: Self.rgb555(2, 6, 8)
        case .daysOfRuin: Self.rgb555(3, 3, 2)
        }
    }

    func buttonSurface(tone: PlaytestEraButtonStyle.Tone, pressed: Bool) -> Color {
        if pressed { return buttonLowerEdge }

        return switch (self, tone) {
        case (.famicomWars, .primary): FamicomPPUPalette.gray
        case (.famicomWars, .neutral): FamicomPPUPalette.cyan
        case (.gameBoyWars, .primary): Self.gameBoyDarkGray
        case (.gameBoyWars, .neutral): Self.gameBoyLightGray
        case (.superFamicomWars, .primary): Self.rgb555(29, 20, 21)
        case (.superFamicomWars, .neutral): Self.rgb555(17, 10, 13)
        case (.gameBoyWars2, .primary): Self.rgb555(3, 13, 31)
        case (.gameBoyWars2, .neutral): Self.rgb555(18, 27, 31)
        case (.gameBoyWars3, .primary): Self.rgb555(12, 22, 5)
        case (.gameBoyWars3, .neutral): Self.rgb555(27, 29, 19)
        case (.advanceWars, .primary), (.advanceWars2, .primary): Self.rgb555(28, 14, 2)
        case (.advanceWars, .neutral), (.advanceWars2, .neutral): Self.rgb555(4, 12, 20)
        case (.dualStrike, .primary): Self.rgb555(4, 18, 24)
        case (.dualStrike, .neutral): Self.rgb555(6, 10, 9)
        case (.daysOfRuin, .primary): Self.rgb555(20, 12, 5)
        case (.daysOfRuin, .neutral): Self.rgb555(9, 9, 7)
        }
    }

    func buttonText(tone: PlaytestEraButtonStyle.Tone) -> Color {
        switch (self, tone) {
        case (.gameBoyWars, .primary): Self.gameBoyWhite
        case (.gameBoyWars2, .primary): Self.rgb555(29, 31, 31)
        case (.gameBoyWars3, .primary): Self.rgb555(31, 31, 29)
        case (.gameBoyWars2, .neutral), (.gameBoyWars3, .neutral): buttonBorder
        default: primaryText
        }
    }

    var meterTrack: Color {
        switch self {
        case .famicomWars: FamicomPPUPalette.black
        case .gameBoyWars: Self.gameBoyLightGray
        case .superFamicomWars: Self.rgb555(8, 3, 5)
        case .gameBoyWars2: Self.rgb555(18, 27, 31)
        case .gameBoyWars3: Self.rgb555(27, 29, 19)
        case .advanceWars, .advanceWars2: Self.rgb555(2, 5, 10)
        case .dualStrike: Self.rgb555(1, 3, 4)
        case .daysOfRuin: Self.rgb555(3, 3, 2)
        }
    }

    /// The original Famicom and first two Game Boy cartridges reported unit
    /// condition as text/icon values rather than drawing a segmented meter.
    /// Keep the theme's meter palette available for shared code, but let the
    /// inspector omit that modern visualization for those eras.
    var showsStatusMeters: Bool {
        switch self {
        case .famicomWars, .superFamicomWars, .gameBoyWars, .gameBoyWars2:
            false
        default:
            true
        }
    }

    var meterBorder: Color { buttonBorder }

    var meterDivider: Color {
        switch self {
        case .famicomWars: FamicomPPUPalette.black
        case .gameBoyWars: Self.gameBoyBlack
        case .superFamicomWars: Self.rgb555(5, 2, 4)
        case .gameBoyWars2: Self.rgb555(0, 1, 4)
        case .gameBoyWars3: Self.rgb555(1, 2, 1)
        case .advanceWars, .advanceWars2, .dualStrike: surface
        case .daysOfRuin: Self.rgb555(1, 1, 1)
        }
    }

    var meterSegmentCount: Int {
        switch self {
        case .famicomWars, .gameBoyWars: 8
        case .superFamicomWars, .gameBoyWars2, .gameBoyWars3: 10
        case .advanceWars, .advanceWars2, .dualStrike: 10
        case .daysOfRuin: 5
        }
    }

    var meterHeight: CGFloat {
        switch self {
        case .famicomWars, .gameBoyWars, .gameBoyWars2, .gameBoyWars3: 8
        case .superFamicomWars: 9
        case .advanceWars, .advanceWars2, .dualStrike: 10
        case .daysOfRuin: 11
        }
    }

    var meterCornerRadius: CGFloat {
        switch self {
        case .advanceWars, .advanceWars2, .dualStrike: 3
        default: 0
        }
    }

    func armyAccent(_ army: Int) -> Color {
        if self == .gameBoyWars {
            return army == AWConstants.armyBlueMoon ? Self.gameBoyWhite : Self.gameBoyBlack
        }
        if self == .gameBoyWars2 {
            return army == AWConstants.armyBlueMoon ? Self.rgb555(18, 27, 31) : Self.rgb555(0, 1, 4)
        }
        if self == .gameBoyWars3 {
            return army == AWConstants.armyBlueMoon ? Self.rgb555(29, 31, 31) : Self.rgb555(27, 4, 3)
        }
        if self == .daysOfRuin, army == AWConstants.armyBlackHole {
            return Self.rgb555(3, 3, 3)
        }

        return switch army {
        case AWConstants.armyOrangeStar:
            self == .famicomWars ? FamicomPPUPalette.red : Self.rgb555(29, 6, 3)
        case AWConstants.armyBlueMoon:
            self == .famicomWars ? FamicomPPUPalette.blue : Self.rgb555(4, 13, 28)
        case AWConstants.armyGreenEarth:
            self == .famicomWars ? FamicomPPUPalette.green : Self.rgb555(4, 19, 7)
        case AWConstants.armyYellowComet:
            self == .famicomWars ? FamicomPPUPalette.yellow : Self.rgb555(29, 22, 2)
        case AWConstants.armyBlackHole:
            self == .famicomWars ? FamicomPPUPalette.purple : Self.rgb555(12, 7, 18)
        default:
            innerBorder
        }
    }

    private static func rgb(_ value: UInt32) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    private static func rgb555(_ red: Int, _ green: Int, _ blue: Int) -> Color {
        Color(red: Double(red) / 31, green: Double(green) / 31, blue: Double(blue) / 31)
    }
}
