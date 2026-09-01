import AWEDCore
import SwiftUI

extension PlaytestStatusTheme {
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

}
